import AppKit
import Engine
import Observation
import RoomCore

/// `WebContents` over a `RoomWebContents` (Chromium `content::WebContents`):
/// load, history, reload/stop, title, URL, loading, the native view, close,
/// (3.2a) the pages it opens, the hovered link and element fullscreen,
/// (3.2b) reserved, unhandled and consumed keys and isolated-world scripts,
/// and (3.3a) real transitions, the navigation policy and commits, favicon,
/// progress, theme and background colours, security, audible, muted, zoom,
/// discard and the lifecycle state, (3.3b) find through Chrome's
/// `FindTabHelper`, viewport capture, print preview and DevTools in the
/// host's pane, (3.4b) JavaScript dialogs and beforeunload through the host's
/// sheets, the hung-renderer question, external protocols, notices, the
/// capture state and the media session. A page created for a host window is in that window's Chrome
/// tab strip (`RoomBrowser`), which attaches Chrome's tab helpers
/// (docs/engine-api.md).
///
/// `nativeView` is a view this object owns, with Chromium's
/// `WebContentsViewCocoa` inside, so it stays valid after `close()`.
@Observable
public final class RoomCoreWebContents: NSObject, WebContents, RoomWebContentsDelegate {
    @ObservationIgnored public weak var uiDelegate: (any WebContentsUIDelegate)?
    @ObservationIgnored public weak var navigationDelegate: (any NavigationDelegate)?

    /// How the page was made; `hostWindow` follows `move(toHostWindow:)`.
    public private(set) var configuration: WebContentsConfiguration

    public private(set) var title: String?
    public private(set) var url: URL?
    public private(set) var favicon: NSImage?
    public private(set) var isLoading = false
    public private(set) var loadProgress = 1.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var themeColor: NSColor?
    public private(set) var rootBackgroundColor: NSColor?
    public private(set) var securityState = SecurityState.none
    public private(set) var isAudible = false
    public private(set) var blockedRequestCount = 0
    public private(set) var state = WebContentsState.alive
    public private(set) var findResult: FindResult?
    /// `MediaStreamCaptureIndicator` through RoomCore's `captureState`.
    public private(set) var captureState = CaptureState()
    /// `content::MediaSession` through RoomCore's `mediaSession`.
    public private(set) var mediaSession: MediaSessionInfo?
    @ObservationIgnored private var roomMediaSession: RoomMediaSessionInfo?
    @ObservationIgnored private var artworkCache: (image: NSImage, png: Data?)?
    /// `WebContents::SetAudioMuted`; follows `DidUpdateAudioMutingState`.
    /// The delegate hears every change, the host's own included.
    public var isMuted: Bool {
        didSet {
            guard isMuted != oldValue else { return }
            if page.isMuted != isMuted { page.isMuted = isMuted }
            uiDelegate?.webContents(self, didChangeMuted: isMuted)
        }
    }
    /// Chrome's `ZoomController` (per host: the host's other pages follow);
    /// follows `ZoomObserver::OnZoomChanged`.
    public var zoomFactor = 1.0 {
        didSet { if abs(page.zoomFactor - zoomFactor) > 0.0001 { page.zoomFactor = zoomFactor } }
    }

    /// What the page asked for when it opened this one: the window.open
    /// rect or the picture-in-picture size (top-left screen coordinates);
    /// `nil` for a page the host created or one opened without features.
    /// Engine-specific until the host has a popup window (Chapter 4).
    public private(set) var requestedBounds: CGRect?

    public var nativeView: NSView { pageView }
    /// Chrome's `DevToolsWindow` with its front-end in the host's pane.
    public var devTools: (any DevTools)? {
        if roomDevTools == nil, state != .closed { roomDevTools = RoomCoreDevTools(contents: self) }
        return roomDevTools
    }

    @ObservationIgnored let page: RoomWebContents
    @ObservationIgnored private weak var profile: RoomCoreProfile?
    @ObservationIgnored private let pageView = RoomCorePageView()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var scriptSerial = 0
    @ObservationIgnored private var roomDevTools: RoomCoreDevTools?
    /// Between `find` and `stopFind`: results that arrive after a stop are dropped.
    @ObservationIgnored private var findActive = false
    /// From a denied certificate error to the end of the run-loop turn.
    @ObservationIgnored private var certificateDenialPending = false
    /// RoomCore's notices by object, so their removal reaches the same `InfoBar`.
    @ObservationIgnored private var notices: [ObjectIdentifier: InfoBar] = [:]
    @ObservationIgnored private var noticeSerial = 0

    init(page: RoomWebContents, configuration: WebContentsConfiguration, profile: RoomCoreProfile?) {
        self.page = page
        self.configuration = configuration
        self.profile = profile
        isMuted = configuration.initiallyMuted
        super.init()
        page.delegate = self
        if configuration.initiallyMuted { page.isMuted = true }
        if let view = page.nativeView { pageView.host(view) }
        let weakSelf = WeakContents(self)
        observations = [
            page.observe(\.url) { _, _ in weakSelf.refresh() },
            page.observe(\.title) { _, _ in weakSelf.refresh() },
            page.observe(\.isLoading) { _, _ in weakSelf.refresh() },
            page.observe(\.canGoBack) { _, _ in weakSelf.refresh() },
            page.observe(\.canGoForward) { _, _ in weakSelf.refresh() },
            page.observe(\.isClosed) { _, _ in weakSelf.refresh() },
            page.observe(\.favicon) { _, _ in weakSelf.refresh() },
            page.observe(\.loadProgress) { _, _ in weakSelf.refresh() },
            page.observe(\.themeColor) { _, _ in weakSelf.refresh() },
            page.observe(\.backgroundColor) { _, _ in weakSelf.refresh() },
            page.observe(\.securityLevel) { _, _ in weakSelf.refresh() },
            page.observe(\.hasMixedContent) { _, _ in weakSelf.refresh() },
            page.observe(\.isAudible) { _, _ in weakSelf.refresh() },
            page.observe(\.blockedRequestCount) { _, _ in weakSelf.refresh() },
            page.observe(\.isMuted) { _, _ in weakSelf.refresh() },
            page.observe(\.zoomFactor) { _, _ in weakSelf.refresh() },
            page.observe(\.lifecycleState) { _, _ in weakSelf.refresh() },
            page.observe(\.captureState) { _, _ in weakSelf.refresh() },
            page.observe(\.mediaSession) { _, _ in weakSelf.refresh() },
            // A discard replaces Chromium's WebContents, and with it the view.
            page.observe(\.nativeView) { _, _ in weakSelf.rehostView() },
        ]
        refresh()
    }

    /// Puts the page's current Chromium view in `pageView` (after a discard).
    fileprivate func rehostView() {
        guard let view = page.nativeView, view.superview !== pageView else { return }
        pageView.subviews.forEach { $0.removeFromSuperview() }
        pageView.host(view)
    }

    /// Copies RoomCore's KVO state (main thread) into the observable properties.
    fileprivate func refresh() {
        if page.isClosed {
            guard state != .closed else { return }
            observations = []
            isLoading = false
            loadProgress = 1
            canGoBack = false
            canGoForward = false
            state = .closed
            uiDelegate?.webContentsDidClose(self)
            return
        }
        if url != page.url { url = page.url }
        let newTitle = page.title.isEmpty ? nil : page.title
        if title != newTitle { title = newTitle }
        if isLoading != page.isLoading { isLoading = page.isLoading }
        let progress = isLoading ? page.loadProgress : 1
        if loadProgress != progress { loadProgress = progress }
        if canGoBack != page.canGoBack { canGoBack = page.canGoBack }
        if canGoForward != page.canGoForward { canGoForward = page.canGoForward }
        if favicon !== page.favicon { favicon = page.favicon }
        if themeColor != page.themeColor { themeColor = page.themeColor }
        if rootBackgroundColor != page.backgroundColor { rootBackgroundColor = page.backgroundColor }
        let security = SecurityState(page.securityLevel, hasMixedContent: page.hasMixedContent)
        if securityState != security {
            securityState = security
            uiDelegate?.webContents(self, didChangeSecurityState: security)
        }
        if isAudible != page.isAudible {
            isAudible = page.isAudible
            uiDelegate?.webContents(self, didChangeAudible: isAudible)
        }
        if isMuted != page.isMuted { isMuted = page.isMuted }
        if blockedRequestCount != page.blockedRequestCount { blockedRequestCount = page.blockedRequestCount }
        if abs(zoomFactor - page.zoomFactor) > 0.0001 { zoomFactor = page.zoomFactor }
        let lifecycle: WebContentsState = switch page.lifecycleState {
        case .discarded: .discarded
        case .frozen: .frozen
        default: .alive
        }
        if state != lifecycle { state = lifecycle }
        let capture = CaptureState(rawValue: Int(page.captureState.rawValue))
        if captureState != capture {
            captureState = capture
            uiDelegate?.webContents(self, didChangeCaptureState: capture)
        }
        // A new RoomMediaSessionInfo for every change (KVO); the artwork's PNG is made once per image.
        if page.mediaSession !== roomMediaSession {
            roomMediaSession = page.mediaSession
            let session = page.mediaSession.map { MediaSessionInfo($0, artwork: artworkPNG(for: $0.artwork)) }
            if mediaSession != session { mediaSession = session }
        }
    }

    // MARK: Navigation

    /// `NavigationController::LoadURLWithParams` with the transition's
    /// `ui::PageTransition` (FROM_ADDRESS_BAR when `fromAddressBar`).
    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        page.loadURL(url, transition: RoomPageTransition(transition), fromAddressBar: fromAddressBar)
    }

    public func goBack() {
        // After a denied certificate error RoomCore already left the failed
        // navigation (the page shows what it showed before); the presenter's
        // Go Back in the same turn, written for an engine's committed error page,
        // would step one entry too far.
        if certificateDenialPending { return }
        page.goBack()
    }
    public func goForward() { page.goForward() }
    public func reload() { page.reload() }
    /// `ReloadType::BYPASSING_CACHE`.
    public func reloadIgnoringCache() { page.reloadIgnoringCache() }
    public func stop() { page.stop() }

    // MARK: Find

    /// `FindTabHelper::StartFinding` with `find_match`: one request per call
    /// (the same text steps to the next match, a new text selects its first).
    /// Results come from
    /// `FindResultObserver` through the delegate.
    public func find(_ text: String, forward: Bool, matchCase: Bool) {
        guard state != .closed else { return }
        findActive = true
        page.find(text, forward: forward, matchCase: matchCase)
    }

    /// `FindTabHelper::StopFinding(kClear | kKeep)`.
    public func stopFind(clearSelection: Bool) {
        findActive = false
        findResult = nil
        page.stopFinding(clearSelection: clearSelection)
    }

    public func webContents(_ webContents: RoomWebContents, didUpdateFindResultWithMatchCount matchCount: Int,
                            activeMatch: Int, selectionRect: NSRect, finalUpdate: Bool) {
        guard findActive else { return }
        let result = FindResult(matchCount: matchCount, activeMatch: activeMatch, isFinal: finalUpdate)
        if findResult != result { findResult = result }
    }

    // MARK: Lifecycle

    /// Chrome's `TabLifecycleUnit` discard: the renderer goes, the
    /// navigation entries stay, so the page that `reload()` brings back has
    /// its back/forward list (B-13). Chrome swaps in a new `WebContents`;
    /// RoomCore moves this page (and its view) onto it.
    /// Chromium's session serialisation of the page's entries (RoomCore's
    /// `navigationState`: `SerializedNavigationEntry` with `PageState`).
    public var navigationState: Data? { state == .closed ? nil : page.navigationState }

    /// performance_manager's `CannotDiscardReason`s (RoomCore's `discardBlockers`).
    public var discardBlockers: DiscardBlockers {
        guard state != .closed else { return [] }
        return DiscardBlockers(rawValue: UInt(page.discardBlockers.rawValue))
    }

    public func discard() throws {
        guard state != .closed else { throw EngineError.closed }
        guard page.discard() else { throw EngineError.failed("RoomCore refused the discard (no tab strip, or already discarded)") }
        refresh()
    }

    /// Closes the page through its tab strip, which runs its beforeunload
    /// handler first (the host's sheet); `webContentsDidClose` follows from
    /// the `closed` change once it is gone.
    public func close() {
        guard state != .closed else { return }
        page.close()
    }

    // MARK: Tools

    /// `RenderWidgetHostView::CopyFromSurface` of the main frame: the page as
    /// the compositor drew it, at the screen's scale (size in points).
    public func captureViewport() async throws -> NSImage {
        guard state != .closed else { throw EngineError.closed }
        return try await withCheckedThrowingContinuation { continuation in
            page.captureViewport { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: EngineError.failed(error?.localizedDescription ?? "captureViewport: no image"))
                }
            }
        }
    }

    /// Runs `script` in RoomCore's isolated world of the main frame (the
    /// page's DOM, not its globals) and returns the completion value as JSON
    /// text, like the DevTools protocol's `Runtime.evaluate` (strings quoted,
    /// `undefined` as `null`). Chromium's isolated-world call does not wait
    /// for promises, so the script runs through `eval` in a wrapper that
    /// parks a promise's outcome in the isolated world, where it is polled.
    public func executeJavaScript(_ script: String) async throws -> String {
        guard state != .closed else { throw EngineError.closed }
        scriptSerial += 1
        let id = scriptSerial
        let source = String(decoding: try JSONSerialization.data(withJSONObject: script, options: .fragmentsAllowed), as: UTF8.self)
        // DevTools' front-end (devtools://, the pane's page) runs in its main
        // world, where its CSP (`script-src 'self'`) forbids `eval`: the script
        // goes in as an expression there.
        let code = url?.scheme == "devtools" ? Self.wrapper(expression: script, id: id) : Self.wrapper(source: source, id: id)
        var outcome = try await evaluate(code)
        if case .pending = outcome {
            // A promise parked in this document; a navigation takes it away.
            let document = url
            let poll = "(() => { const r = window.__roomScriptResults; if (!r || !(\(id) in r)) return null; const x = r[\(id)]; delete r[\(id)]; return x; })()"
            let deadline = ContinuousClock.now + .seconds(120)
            repeat {
                guard ContinuousClock.now < deadline, state != .closed else {
                    throw EngineError.failed("executeJavaScript: the promise did not settle")
                }
                guard url == document else { throw EngineError.failed("executeJavaScript: the page navigated before the promise settled") }
                try await Task.sleep(for: .milliseconds(4))
                outcome = try await evaluate(poll)
            } while outcome == .notSettled
        }
        switch outcome {
        case .value(let json): return json
        case .exception(let message): throw EngineError.javaScriptException(message)
        case .pending, .notSettled: return "null"
        }
    }

    /// Evaluates the script as global code (its completion value, like the
    /// DevTools protocol's `Runtime.evaluate`), catching what it throws.
    private static func wrapper(source: String, id: Int) -> String {
        wrapper(evaluating: "(0, eval)(\(source))", id: id)
    }

    /// The same for a script that is one expression, without `eval`.
    private static func wrapper(expression: String, id: Int) -> String {
        wrapper(evaluating: "(\n\(expression)\n)", id: id)
    }

    private static func wrapper(evaluating evaluation: String, id: Int) -> String {
        """
        (() => { let v; try { v = \(evaluation); } catch (e) { return { e: String(e && e.message || e) }; }
        if (v && typeof v.then === 'function') { const r = (window.__roomScriptResults = window.__roomScriptResults || {});
        v.then(x => { r[\(id)] = { v: x }; }, e => { r[\(id)] = { e: String(e && e.message || e) }; }); return { p: \(id) }; }
        return { v: v }; })()
        """
    }

    /// What one isolated-world evaluation of the wrapper or the poll returned.
    private enum ScriptOutcome: Sendable, Equatable {
        /// `{v}`: the value as JSON text (`null` for undefined).
        case value(String)
        /// `{e}`: the script threw, or its promise rejected.
        case exception(String)
        /// `{p}`: a promise; its outcome is polled.
        case pending
        /// The poll found no outcome yet.
        case notSettled

        init(_ result: Any?) {
            guard let object = result as? [String: Any] else {
                self = .notSettled
                return
            }
            if let message = object["e"] as? String {
                self = .exception(message)
            } else if object["p"] != nil {
                self = .pending
            } else if let value = object["v"], !(value is NSNull),
                      let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) {
                self = .value(String(decoding: data, as: UTF8.self))
            } else {
                self = .value("null")
            }
        }
    }

    /// One isolated-world evaluation. A page showing a JavaScript dialog
    /// (Chrome's own until 3.4b routes `alert` to the host's sheet) runs no
    /// script until it closes, so an answer that has not come in 30 s is an
    /// error, not a wait without end (found by the 3.2b tour's popups step).
    private func evaluate(_ script: String) async throws -> ScriptOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            page.evaluateJavaScript(script) { result, error in
                if let error {
                    once.resume(throwing: EngineError.failed(error.localizedDescription))
                } else {
                    once.resume(returning: ScriptOutcome(result))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.scriptTimeout) {
                once.resume(throwing: EngineError.failed("executeJavaScript: no answer in \(Int(Self.scriptTimeout)) s (a JavaScript dialog may be open)"))
            }
        }
    }

    private static let scriptTimeout: TimeInterval = 30

    /// Chrome's print preview (Views, over the host window: B-29) through
    /// `printing::StartPrint`.
    public func print() {
        guard state != .closed else { return }
        if !page.printWithPreview() { NSLog("RoomCore: print refused (no page to print)") }
    }

    /// Leaves element fullscreen; `webContentsDidRequestExitFullscreen`
    /// follows from Chrome's FullscreenController.
    public func exitFullscreen() { page.exitFullscreen() }

    /// `MediaStreamCaptureIndicator::StopMediaCapturing`; `captureState` follows.
    public func stopCapturing(_ kinds: CaptureKinds) {
        guard state != .closed else { return }
        var mask: RoomCaptureKinds = []
        if kinds.contains(.userMedia) { mask.insert(.userMedia) }
        if kinds.contains(.displayMedia) { mask.insert(.displayMedia) }
        page.stopCapturing(mask)
    }

    // MARK: Media session controls (`content::MediaSession`, 4.6)

    public func mediaPlay() {
        guard state != .closed else { return }
        page.mediaPlay()
    }

    public func mediaPause() {
        guard state != .closed else { return }
        page.mediaPause()
    }

    public func mediaNextTrack() {
        guard state != .closed else { return }
        page.mediaNextTrack()
    }

    public func mediaPreviousTrack() {
        guard state != .closed else { return }
        page.mediaPreviousTrack()
    }

    public func mediaSeek(to seconds: TimeInterval) {
        guard state != .closed else { return }
        page.mediaSeek(to: seconds)
    }

    // MARK: Documents (4.7a)

    /// `WebContents::SavePage` (HTML, complete HTML: Chrome's SavePackage,
    /// which also appears as a download item) or `GenerateMHTML`.
    public func savePage(as format: SavePageFormat, to url: URL) async throws {
        guard state != .closed else { throw EngineError.closed }
        guard url.isFileURL else { throw EngineError.failed("savePage: not a file URL: \(url)") }
        let roomFormat: RoomSavePageFormat = switch format {
        case .html: .HTML
        case .completeHTML: .completeHTML
        case .mhtml: .MHTML
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            page.savePage(as: roomFormat, toPath: url.path) { error in
                if let error {
                    continuation.resume(throwing: EngineError.failed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// One DevTools protocol command through a `DevToolsAgentHost` client
    /// `//room` attaches for it and detaches after the answer.
    public func sendDevToolsCommand(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        guard state != .closed else { throw EngineError.closed }
        guard JSONSerialization.isValidJSONObject(params) else {
            throw EngineError.failed("sendDevToolsCommand: the parameters are not JSON")
        }
        let box = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UncheckedResult, any Error>) in
            page.sendDevToolsCommand(method, params: params) { result, error in
                if let result {
                    // Made by RoomCore on the main thread and read only there.
                    nonisolated(unsafe) let answer = result
                    continuation.resume(returning: UncheckedResult(value: answer))
                } else {
                    continuation.resume(throwing: EngineError.failed(error?.localizedDescription ?? "sendDevToolsCommand: no answer"))
                }
            }
        }
        return box.value
    }

    /// The protocol's answer handed through the continuation (JSON values,
    /// made and read on the main thread).
    private struct UncheckedResult: @unchecked Sendable {
        let value: [String: Any]
    }

    /// The artwork image as PNG data, converted once per image RoomCore hands over.
    private func artworkPNG(for image: NSImage?) -> Data? {
        guard let image else { return nil }
        if let cached = artworkCache, cached.image === image { return cached.png }
        let png = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        artworkCache = (image, png)
        return png
    }

    // MARK: Windows (4.8b)

    /// `-[RoomWebContents moveToBrowser:error:]` into `window`'s `RoomBrowser`
    /// for the page's profile (made on first use, as for a new page): Chrome's
    /// tab drag between windows; the back/forward list, renderer and tab
    /// helpers go along and `nativeView` (this object's view) is the same.
    public func move(toHostWindow window: NSWindow) throws {
        guard state != .closed, let profile else { throw EngineError.closed }
        do {
            try page.move(to: profile.browser(for: window))
        } catch {
            throw EngineError.failed(error.localizedDescription)
        }
        configuration.hostWindow = window
    }

    // MARK: RoomWebContentsDelegate

    /// The policy for a navigation, from the `//room` navigation throttle
    /// (the page's own navigations) or Navigate()'s disposition hook (pages
    /// it opens elsewhere).
    public func webContents(_ webContents: RoomWebContents, decidePolicyFor action: RoomNavigationAction) -> RoomWindowOpenDisposition {
        guard let navigationDelegate else { return action.disposition }
        return RoomWindowOpenDisposition(navigationDelegate.webContents(self, decidePolicyFor: NavigationAction(action)))
    }

    public func webContents(_ webContents: RoomWebContents, didCommitNavigation url: URL, transition: RoomPageTransition,
                            sameDocument: Bool) {
        navigationDelegate?.webContents(self, didCommitNavigation: url, transition: PageTransition(transition))
    }

    public func webContentsDidChangeNavigationState(_ webContents: RoomWebContents) {
        navigationDelegate?.webContentsDidChangeNavigationState(self)
    }

    /// A page this one opened, already in this page's `Browser` (never a
    /// window of its own): the host places it, or closes it.
    public func webContents(_ webContents: RoomWebContents, didCreate newContents: RoomWebContents, targetURL: URL?,
                            disposition: RoomWindowOpenDisposition, requestedBounds: NSRect, userGesture: Bool) {
        let mapped = Disposition(disposition)
        let configuration = WebContentsConfiguration(initiallyHidden: mapped == .newBackgroundTab,
                                                     hostWindow: self.configuration.hostWindow)
        // Off the record (patches/0014, 4.8b): the page belongs to this
        // profile's twin, in the twin's Browser; the host moves it into its
        // incognito window.
        guard let owner = profile?.owner(of: newContents.profile) else {
            newContents.close()
            return
        }
        let contents = owner.adoptOpened(newContents, configuration: configuration)
        if requestedBounds.width > 0 || requestedBounds.height > 0 { contents.requestedBounds = requestedBounds }
        guard let uiDelegate else {
            contents.close()
            return
        }
        uiDelegate.webContents(self, didCreate: contents, targetURL: targetURL, disposition: mapped)
    }

    /// `WebContentsObserver::PrimaryMainFrameRenderProcessGone`: the host's
    /// crashed-page view.
    public func webContents(_ webContents: RoomWebContents, didHandleCookieBanner consentPlatform: String, optedOut: Bool) {
        uiDelegate?.webContents(self, didHandleCookieBanner: consentPlatform, optedOut: optedOut)
    }

    public func webContents(_ webContents: RoomWebContents, renderProcessGone status: RoomTerminationStatus) {
        let mapped: TerminationStatus = switch status {
        case .normal: .normal
        case .killed: .killed
        case .crashed: .crashed
        case .outOfMemory: .outOfMemory
        case .launchFailed: .launchFailed
        case .integrityFailure: .integrityFailure
        default: .abnormal
        }
        uiDelegate?.webContents(self, processGone: mapped)
    }

    public func webContents(_ webContents: RoomWebContents, didChangeStatusText text: String?) {
        uiDelegate?.webContents(self, didChangeStatusText: text)
    }

    /// Chrome's focus-the-location-bar command (`IDC_FOCUS_LOCATION` through
    /// `RoomAppController`'s dispatch, `RoomLocationBar::FocusLocation`).
    public func webContentsDidRequestFocusOnLocationBar(_ webContents: RoomWebContents) {
        NSLog("RoomCore: Chrome asked to focus the location bar")
        uiDelegate?.webContentsDidRequestFocusOnLocationBar(self)
    }

    /// `WebContentsDelegate::ActivateContents` (B-107): Chrome made the page
    /// its window's active tab (picture-in-picture's back to tab, `opener.focus()`).
    public func webContentsDidRequestActivation(_ webContents: RoomWebContents) {
        NSLog("RoomCore: Chrome asked to show a page")
        uiDelegate?.webContentsDidRequestActivation(self)
    }

    /// One of Chrome's confirmation toasts (`RoomToastController`, B-58): the
    /// host shows its own.
    @objc(webContents:didRequestToast:)
    public func webContents(_ webContents: RoomWebContents, didRequestToast kind: String) {
        uiDelegate?.webContents(self, didRequestToast: ToastKind(engineName: kind))
    }

    /// Where Chrome's Views bubbles point (`RoomToolbarButtonProvider` and the
    /// window's bubble anchor, 3.7a): the host's site button.
    public func webContentsBubbleAnchorRect(_ webContents: RoomWebContents) -> NSRect {
        uiDelegate?.bubbleAnchorRect(for: self) ?? .zero
    }

    public func webContentsDidRequestEnterFullscreen(_ webContents: RoomWebContents, origin: URL?) {
        uiDelegate?.webContentsDidRequestEnterFullscreen(self, origin: origin)
    }

    public func webContentsDidRequestExitFullscreen(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidRequestExitFullscreen(self)
    }

    /// A key-down before the page sees it: a reserved one goes to the main
    /// menu here, once, and never to the page.
    public func webContents(_ webContents: RoomWebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        guard uiDelegate?.webContents(self, isReservedKeyEvent: event) == true else { return false }
        _ = NSApp.mainMenu?.performKeyEquivalent(with: Self.menuEvent(for: event))
        return true
    }

    /// The event to offer the menu: a fresh copy of an ⌥ key whose character
    /// ⌥ changed ("†" for ⌥⌘T), which no longer matches its item once the
    /// page's view has handled the original (B-86, found in 4.4a; the copy
    /// moved here from the app's delegate in 4.4b).
    static func menuEvent(for event: NSEvent) -> NSEvent {
        guard event.type == .keyDown, event.modifierFlags.contains(.option),
              event.characters?.lowercased() != event.charactersIgnoringModifiers?.lowercased(),
              let copy = NSEvent.keyEvent(with: event.type, location: event.locationInWindow, modifierFlags: event.modifierFlags,
                                          timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                          characters: event.characters ?? "", charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                                          isARepeat: event.isARepeat, keyCode: event.keyCode)
        else { return event }
        return copy
    }

    /// A key-down the page did not consume: the delegate offers it to the
    /// main menu (RoomCore does nothing else with it).
    public func webContents(_ webContents: RoomWebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        if let uiDelegate { return uiDelegate.webContents(self, handleUnhandledKeyEvent: event) }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    // MARK: Prompts, menus, files (3.4a)

    /// Chrome's `PermissionRequestManager` prompt (patch 0017): the host's
    /// popover answers with Accept / AcceptThisTime / Deny / Dismiss.
    public func webContents(_ webContents: RoomWebContents, willAskForPermissions requests: [RoomPermissionRequest],
                            quietReason: RoomPermissionQuietReason, completion: @escaping (RoomPermissionResponse) -> Void) {
        let mapped = requests.compactMap(PermissionRequest.init)
        guard let uiDelegate, !mapped.isEmpty else { return completion(.dismissed) }
        uiDelegate.webContents(self, willAskForPermission: mapped, quietReason: PermissionQuietReason(quietReason)) { response in
            switch response {
            case .granted: completion(.granted)
            case .grantedOnce: completion(.grantedOnce)
            case .denied: completion(.denied)
            case .dismissed: completion(.dismissed)
            }
        }
    }

    public func webContentsDidDismissPermissionPrompt(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidDismissPermissionPrompt(self)
    }

    /// Chrome's `RenderViewContextMenu` (patch 0018): the host shows its own
    /// menu with Room's items first; Chrome runs the command chosen.
    public func webContents(_ webContents: RoomWebContents, willShowContextMenu menu: RoomContextMenu) -> Bool {
        guard let uiDelegate else { return false }
        let model = MenuModel(items: menu.items.map(MenuItem.init)) { id in
            if let id { menu.selectCommand(id) } else { menu.cancel() }
        }
        return uiDelegate.webContents(self, willShowContextMenu: model, for: ContextMenuElement(menu))
    }

    /// Chrome's `LoginHandler` with the host's sign-in sheet (patch 0020).
    public func webContents(_ webContents: RoomWebContents, didReceiveAuthChallenge challenge: RoomAuthChallenge,
                            completion: @escaping (String?, String?) -> Void) {
        guard let uiDelegate else { return completion(nil, nil) }
        let mapped = AuthChallenge(origin: challenge.origin, realm: challenge.realm, scheme: challenge.scheme, isProxy: challenge.isProxyChallenge)
        uiDelegate.webContents(self, didReceiveAuthChallenge: mapped) { credential in
            if let credential, let user = credential.user {
                completion(user, credential.password ?? "")
            } else {
                completion(nil, nil)
            }
        }
    }

    /// A certificate error with Chrome's verdict (patch 0021): HSTS and
    /// pinned hosts are never overridable (B-24). A denial stops the
    /// navigation in RoomCore; the presenter's Go Back in the same turn is
    /// skipped (`goBack()`).
    public func webContents(_ webContents: RoomWebContents, didFailCertificateCheck error: RoomCertificateError,
                            completion: @escaping (Bool) -> Void) {
        guard let uiDelegate else { return completion(false) }
        let mapped = CertificateError(url: error.url, code: error.errorCode, description: error.errorName,
                                      certificateChain: error.certificateChain, isOverridable: error.isOverridable)
        uiDelegate.webContents(self, didFailCertificateCheck: mapped) { [weak self] proceed in
            if !proceed, let self {
                self.certificateDenialPending = true
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.certificateDenialPending = false }
                }
            }
            completion(proceed)
        }
    }

    /// `<input type=file>` through the host's open panel (patch 0022).
    public func webContents(_ webContents: RoomWebContents, runFileChooser request: RoomFileChooserRequest,
                            completion: @escaping ([URL]?) -> Void) {
        guard let uiDelegate else { return completion(nil) }
        uiDelegate.webContents(self, runFileChooser: FileChooserRequest(request), completion: completion)
    }

    // MARK: Dialogs, the renderer, other applications, notices (3.4b)

    /// Chrome's `TabModalDialogManager` with the host's sheets (a //room
    /// delegate): alert, confirm, prompt. Chrome withdraws them on navigation.
    public func webContents(_ webContents: RoomWebContents, runJavaScriptDialog type: RoomJavaScriptDialogType, message: String,
                            defaultText: String, origin: URL?, completion: @escaping (Bool, String?) -> Void) {
        guard let uiDelegate else { return completion(type == .alert, nil) }
        switch type {
        case .confirm:
            uiDelegate.webContents(self, runJavaScriptConfirm: message, origin: origin) { completion($0, nil) }
        case .prompt:
            uiDelegate.webContents(self, runJavaScriptPrompt: message, defaultText: defaultText, origin: origin) { text in
                completion(text != nil, text)
            }
        default:
            uiDelegate.webContents(self, runJavaScriptAlert: message, origin: origin) { completion(true, nil) }
        }
    }

    /// Chrome's app-modal beforeunload (a close, a reload, the quit) with the
    /// host's Leave/Stay sheet; "stay" during a quit cancels it.
    public func webContents(_ webContents: RoomWebContents, runBeforeUnloadDialogForReload isReload: Bool,
                            completion: @escaping (Bool) -> Void) {
        guard let uiDelegate else { return completion(true) }
        uiDelegate.webContents(self, runBeforeUnloadDialogForReload: isReload, completion: completion)
    }

    public func webContentsDidDismissJavaScriptDialogs(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidDismissJavaScriptDialogs(self)
    }

    /// Chrome's hang monitor through a //room `TabDialogs`.
    public func webContentsRendererDidBecomeUnresponsive(_ webContents: RoomWebContents,
                                                         completion: @escaping (RoomUnresponsiveAction) -> Void) {
        guard let uiDelegate else { return completion(.wait) }
        uiDelegate.webContentsDidBecomeUnresponsive(self) { completion($0 == .terminate ? .terminate : .wait) }
    }

    public func webContentsRendererDidBecomeResponsive(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidBecomeResponsive(self)
    }

    /// Chrome's external protocol dialog (patch 0023): "open" launches the
    /// handler through `ExternalProtocolHandler`.
    public func webContents(_ webContents: RoomWebContents, shouldOpenExternalProtocol request: RoomExternalProtocolRequest,
                            completion: @escaping (Bool) -> Void) {
        guard let uiDelegate else { return completion(false) }
        let mapped = ExternalURLRequest(url: request.url, scheme: request.scheme.lowercased(), initiatingOrigin: request.initiatingOrigin,
                                        isUserGesture: request.isUserGesture, applicationName: request.applicationName)
        uiDelegate.webContents(self, shouldOpenExternalURL: mapped, completion: completion)
    }

    /// Chrome's infobars (a `ContentInfoBarManager` observer) and the desktop
    /// translate offer, as notices.
    public func webContents(_ webContents: RoomWebContents, didAdd infoBar: RoomInfoBar) {
        noticeSerial += 1
        let kind: InfoBar.Kind = infoBar.kind == .translateOffer
            ? .translateOffer(source: infoBar.sourceLanguage ?? "", target: infoBar.targetLanguage ?? "")
            : .engine(identifier: infoBar.identifier)
        let notice = InfoBar(id: noticeSerial, kind: kind, message: infoBar.message, buttons: infoBar.buttons) { index in
            if let index { infoBar.pressButton(at: index) } else { infoBar.dismiss() }
        }
        notices[ObjectIdentifier(infoBar)] = notice
        guard let uiDelegate else { return infoBar.dismiss() }
        uiDelegate.webContents(self, didAddInfoBar: notice)
    }

    public func webContents(_ webContents: RoomWebContents, didRemove infoBar: RoomInfoBar) {
        guard let notice = notices.removeValue(forKey: ObjectIdentifier(infoBar)) else { return }
        notice.withdraw()
        uiDelegate?.webContents(self, didRemoveInfoBar: notice)
    }

    public func webContents(_ webContents: RoomWebContents, didConsumeKeyCode keyCode: UInt16,
                            modifierFlags: NSEvent.ModifierFlags, phase: RoomKeyEventPhase) {
        let mapped: KeyEventInfo.Phase = switch phase {
        case .keyUp: .keyUp
        case .character: .character
        default: .keyDown
        }
        uiDelegate?.webContents(self, didConsumeKey: KeyEventInfo(keyCode: keyCode, modifiers: modifierFlags, phase: mapped))
    }
}

extension Disposition {
    /// RoomCore's dispositions in the `Engine` protocol's terms: a singleton
    /// or switch-to-tab that Chromium had to open, and a split's new pane,
    /// arrive as foreground tabs (the host has no such placement yet).
    init(_ disposition: RoomWindowOpenDisposition) {
        switch disposition {
        case .newBackgroundTab: self = .newBackgroundTab
        case .newPopup: self = .newPopup
        case .newWindow: self = .newWindow
        case .newPictureInPicture: self = .newPictureInPicture
        case .offTheRecord: self = .offTheRecord
        case .newForegroundTab, .singletonTab, .switchToTab, .newSplitView: self = .newForegroundTab
        case .currentTab: self = .currentTab
        case .ignoreAction: self = .ignore
        case .saveToDisk: self = .saveToDisk
        @unknown default: self = .newForegroundTab
        }
    }
}

extension RoomWindowOpenDisposition {
    init(_ disposition: Disposition) {
        switch disposition {
        case .ignore: self = .ignoreAction
        case .currentTab: self = .currentTab
        case .newForegroundTab: self = .newForegroundTab
        case .newBackgroundTab: self = .newBackgroundTab
        case .newWindow: self = .newWindow
        case .newPopup: self = .newPopup
        case .newPictureInPicture: self = .newPictureInPicture
        case .saveToDisk: self = .saveToDisk
        case .offTheRecord: self = .offTheRecord
        }
    }
}

extension RoomPageTransition {
    init(_ transition: PageTransition) {
        switch transition {
        case .link: self = .link
        case .typed: self = .typed
        case .bookmark: self = .autoBookmark
        case .generated: self = .generated
        case .keyword: self = .keyword
        case .formSubmit: self = .formSubmit
        case .reload: self = .reload
        case .other: self = .other
        }
    }
}

extension PageTransition {
    init(_ transition: RoomPageTransition) {
        switch transition {
        case .link: self = .link
        case .typed: self = .typed
        case .autoBookmark: self = .bookmark
        case .generated: self = .generated
        case .keyword: self = .keyword
        case .formSubmit: self = .formSubmit
        case .reload: self = .reload
        default: self = .other
        }
    }
}

extension NavigationAction {
    /// RoomCore's action in the protocol's terms: `kind` is exact (a click on
    /// a link is never a script's `window.location`, B-33).
    init(_ action: RoomNavigationAction) {
        let kind: Kind = switch action.kind {
        case .linkClicked: .linkActivated
        case .formSubmitted: .formSubmitted
        case .backForward: .backForward
        case .reload: .reload
        default: .other
        }
        self.init(url: action.url, referrer: action.referrer, kind: kind, transition: PageTransition(action.transition),
                  disposition: Disposition(action.disposition), isUserGesture: action.isUserGesture,
                  isRedirect: action.isRedirect, isClientRedirect: action.isClientRedirect)
    }
}

extension PermissionRequest {
    /// Chrome's request in the protocol's terms: local and loopback network
    /// are one kind; navigator.storage.persist() (kDiskQuota) has none.
    init?(_ request: RoomPermissionRequest) {
        let kind: Kind
        switch request.kind {
        case .camera: kind = .camera
        case .microphone: kind = .microphone
        case .cameraPanTiltZoom: kind = .cameraPanTiltZoom
        case .geolocation: kind = .geolocation
        case .notifications: kind = .notifications
        case .clipboard: kind = .clipboard
        case .midiSysex: kind = .midiSysex
        case .storageAccess: kind = .storageAccess
        case .topLevelStorageAccess: kind = .topLevelStorageAccess
        case .windowManagement: kind = .windowManagement
        case .localFonts: kind = .localFonts
        case .idleDetection: kind = .idleDetection
        case .keyboardLock: kind = .keyboardLock
        case .pointerLock: kind = .pointerLock
        case .multipleDownloads: kind = .multipleDownloads
        case .registerProtocolHandler: kind = .registerProtocolHandler
        case .fileSystemAccess: kind = .fileSystemAccess
        case .localNetwork, .loopbackNetwork: kind = .localNetworkAccess
        case .sensors: kind = .sensors
        case .arSession: kind = .arSession
        case .vrSession: kind = .vrSession
        case .handTracking: kind = .handTracking
        case .identityProvider: kind = .identityProvider
        case .webAppInstallation: kind = .webAppInstallation
        case .capturedSurfaceControl: kind = .capturedSurfaceControl
        default: return nil
        }
        let system: SystemAuthorization = switch request.systemAuthorization {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        default: .notApplicable
        }
        self.init(kind: kind, origin: request.origin, systemAuthorization: system)
    }
}

extension PermissionQuietReason {
    /// Chrome's quiet-UI reasons; the predictions are one case, disruptive
    /// behaviour reads as abusive content, a request without a gesture as
    /// abusive requests.
    init?(_ reason: RoomPermissionQuietReason) {
        switch reason {
        case .enabledInSettings: self = .enabledInSettings
        case .crowdDeny: self = .crowdDeny
        case .abusiveRequests, .lackOfGesture: self = .abusiveRequests
        case .abusiveContent, .disruptiveBehavior: self = .abusiveContent
        case .servicePredictedUnlikelyGrant, .onDevicePredictedUnlikelyGrant: self = .predictedUnlikelyGrant
        default: return nil
        }
    }
}

extension MenuItem {
    init(_ item: RoomMenuItem) {
        let kind: Kind = switch item.type {
        case .check: .checkbox
        case .radio: .radio(group: item.groupId)
        case .separator: .separator
        case .submenu: .submenu((item.submenu ?? []).map(MenuItem.init))
        default: .command
        }
        self.init(id: item.commandId, kind: kind, title: item.title, isEnabled: item.isEnabled, isChecked: item.isChecked,
                  keyEquivalent: item.keyEquivalent, keyEquivalentModifiers: item.keyEquivalentModifierMask)
    }
}

extension ContextMenuElement {
    init(_ menu: RoomContextMenu) {
        let media: MediaType = switch menu.mediaType {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .canvas: .canvas
        case .file: .file
        case .plugin: .plugin
        default: .none
        }
        self.init(location: menu.location, pageURL: menu.pageURL, frameURL: menu.frameURL, linkURL: menu.linkURL,
                  linkText: menu.linkText, sourceURL: menu.sourceURL, mediaType: media, selectionText: menu.selectionText,
                  isEditable: menu.isEditable, misspelledWord: menu.misspelledWord,
                  dictionarySuggestions: menu.dictionarySuggestions)
    }
}

extension FileChooserRequest {
    init(_ request: RoomFileChooserRequest) {
        let mode: Mode = switch request.mode {
        case .openMultiple: .openMultiple
        case .uploadFolder, .openDirectory: .openFolder
        case .save: .save
        default: .open
        }
        self.init(mode: mode, title: request.title, defaultPath: request.defaultPath, acceptTypes: request.acceptTypes)
    }
}

extension MediaSessionInfo {
    init(_ info: RoomMediaSessionInfo, artwork: Data?) {
        let state: PlaybackState = switch info.playbackState {
        case .playing: .playing
        case .paused: .paused
        default: .none
        }
        let map: [(RoomMediaSessionActions, MediaSessionAction)] = [
            (.play, .play), (.pause, .pause), (.previousTrack, .previousTrack), (.nextTrack, .nextTrack),
            (.seekBackward, .seekBackward), (.seekForward, .seekForward), (.seekTo, .seekTo), (.stop, .stop), (.skipAd, .skipAd),
        ]
        let actions = Set(map.filter { info.actions.contains($0.0) }.map(\.1))
        let position = info.hasPosition ? Position(duration: info.duration, position: info.position, rate: info.playbackRate) : nil
        self.init(title: info.title, artist: info.artist, album: info.album, artworkURL: info.artworkURL, artwork: artwork,
                  playbackState: state, actions: actions, position: position)
    }
}

extension SecurityState {
    /// Chrome's security level: WARNING is plain HTTP ("Not secure").
    init(_ level: RoomSecurityLevel, hasMixedContent: Bool) {
        let mapped: Level = switch level {
        case .secure: .secure
        case .warning: .insecure
        case .dangerous: .dangerous
        default: .none
        }
        self.init(level: mapped, hasMixedContent: hasMixedContent)
    }
}

/// Resumes a continuation once: the first of the script's answer and its
/// timeout wins (both arrive on the main thread).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) { self.continuation = continuation }

    func resume(returning value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Hands the contents through KVO's change handler and dereferences it on
/// the main thread, where RoomCore posts every change.
private struct WeakContents: @unchecked Sendable {
    weak var contents: RoomCoreWebContents?

    init(_ contents: RoomCoreWebContents) { self.contents = contents }

    nonisolated func refresh() {
        MainActor.assumeIsolated { contents?.refresh() }
    }

    nonisolated func rehostView() {
        MainActor.assumeIsolated { contents?.rehostView() }
    }
}

/// The page's view: Chromium's `WebContentsViewCocoa` filling it.
final class RoomCorePageView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("web-contents")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func host(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
