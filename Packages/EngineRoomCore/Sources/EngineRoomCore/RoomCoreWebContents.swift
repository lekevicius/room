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
/// discard and the lifecycle state. A page created for a host window is in
/// that window's Chrome tab strip (`RoomBrowser`), which attaches Chrome's
/// tab helpers; find, capture, print and DevTools are 3.3b's
/// (docs/engine-api.md).
///
/// `nativeView` is a view this object owns, with Chromium's
/// `WebContentsViewCocoa` inside, so it stays valid after `close()`.
@Observable
public final class RoomCoreWebContents: NSObject, WebContents, RoomWebContentsDelegate {
    @ObservationIgnored public weak var uiDelegate: (any WebContentsUIDelegate)?
    @ObservationIgnored public weak var navigationDelegate: (any NavigationDelegate)?

    public let configuration: WebContentsConfiguration

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
    public private(set) var state = WebContentsState.alive
    public private(set) var findResult: FindResult?
    /// `WebContents::SetAudioMuted`; follows `DidUpdateAudioMutingState`.
    public var isMuted: Bool {
        didSet { if page.isMuted != isMuted { page.isMuted = isMuted } }
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
    public var devTools: (any DevTools)? { nil }

    @ObservationIgnored let page: RoomWebContents
    @ObservationIgnored private weak var profile: RoomCoreProfile?
    @ObservationIgnored private let pageView = RoomCorePageView()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var scriptSerial = 0

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
            page.observe(\.isMuted) { _, _ in weakSelf.refresh() },
            page.observe(\.zoomFactor) { _, _ in weakSelf.refresh() },
            page.observe(\.lifecycleState) { _, _ in weakSelf.refresh() },
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
        if isMuted != page.isMuted {
            isMuted = page.isMuted
            uiDelegate?.webContents(self, didChangeMuted: isMuted)
        }
        if abs(zoomFactor - page.zoomFactor) > 0.0001 { zoomFactor = page.zoomFactor }
        let lifecycle: WebContentsState = switch page.lifecycleState {
        case .discarded: .discarded
        case .frozen: .frozen
        default: .alive
        }
        if state != lifecycle { state = lifecycle }
    }

    // MARK: Navigation

    /// `NavigationController::LoadURLWithParams` with the transition's
    /// `ui::PageTransition` (FROM_ADDRESS_BAR when `fromAddressBar`).
    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        page.loadURL(url, transition: RoomPageTransition(transition), fromAddressBar: fromAddressBar)
    }

    public func goBack() { page.goBack() }
    public func goForward() { page.goForward() }
    public func reload() { page.reload() }
    /// `ReloadType::BYPASSING_CACHE`.
    public func reloadIgnoringCache() { page.reloadIgnoringCache() }
    public func stop() { page.stop() }

    // MARK: Find (3.3b: FindTabHelper)

    public func find(_ text: String, forward: Bool, matchCase: Bool) {}
    public func stopFind(clearSelection: Bool) {}

    // MARK: Lifecycle

    /// Chrome's `TabLifecycleUnit` discard: the renderer goes, the
    /// navigation entries stay, so the page that `reload()` brings back has
    /// its back/forward list (B-13). Chrome swaps in a new `WebContents`;
    /// RoomCore moves this page (and its view) onto it.
    public func discard() throws {
        guard state != .closed else { throw EngineError.closed }
        guard page.discard() else { throw EngineError.failed("RoomCore refused the discard (no tab strip, or already discarded)") }
        refresh()
    }

    /// Closes the page through its tab strip, which runs its beforeunload
    /// handler first (Chrome's own dialog until 3.4b); `webContentsDidClose`
    /// follows from the `closed` change once it is gone.
    public func close() {
        guard state != .closed else { return }
        page.close()
    }

    // MARK: Tools (3.3b)

    public func captureViewport() async throws -> NSImage {
        throw EngineError.notSupported("RoomCoreWebContents.captureViewport")
    }

    /// Runs `script` in RoomCore's isolated world of the main frame (the
    /// page's DOM, not its globals) and returns the completion value as JSON
    /// text, like the CEF engine's `Runtime.evaluate` (strings quoted,
    /// `undefined` as `null`). Chromium's isolated-world call does not wait
    /// for promises, so the script runs through `eval` in a wrapper that
    /// parks a promise's outcome in the isolated world, where it is polled.
    public func executeJavaScript(_ script: String) async throws -> String {
        guard state != .closed else { throw EngineError.closed }
        scriptSerial += 1
        let id = scriptSerial
        let source = String(decoding: try JSONSerialization.data(withJSONObject: script, options: .fragmentsAllowed), as: UTF8.self)
        var outcome = try await evaluate(Self.wrapper(source: source, id: id))
        if case .pending = outcome {
            let poll = "(() => { const r = window.__roomScriptResults; if (!r || !(\(id) in r)) return null; const x = r[\(id)]; delete r[\(id)]; return x; })()"
            let deadline = ContinuousClock.now + .seconds(120)
            repeat {
                guard ContinuousClock.now < deadline, state != .closed else {
                    throw EngineError.failed("executeJavaScript: the promise did not settle")
                }
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
        """
        (() => { let v; try { v = (0, eval)(\(source)); } catch (e) { return { e: String(e && e.message || e) }; }
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

    public func print() {}

    /// Leaves element fullscreen; `webContentsDidRequestExitFullscreen`
    /// follows from Chrome's FullscreenController.
    public func exitFullscreen() { page.exitFullscreen() }

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

    /// A page this one opened, already in this page's `Browser` (never a
    /// window of its own): the host places it, or closes it.
    public func webContents(_ webContents: RoomWebContents, didCreate newContents: RoomWebContents, targetURL: URL?,
                            disposition: RoomWindowOpenDisposition, requestedBounds: NSRect, userGesture: Bool) {
        let mapped = Disposition(disposition)
        let configuration = WebContentsConfiguration(initiallyHidden: mapped == .newBackgroundTab,
                                                     hostWindow: self.configuration.hostWindow)
        guard let profile else {
            newContents.close()
            return
        }
        let contents = profile.adoptOpened(newContents, configuration: configuration)
        if requestedBounds.width > 0 || requestedBounds.height > 0 { contents.requestedBounds = requestedBounds }
        guard let uiDelegate else {
            contents.close()
            return
        }
        uiDelegate.webContents(self, didCreate: contents, targetURL: targetURL, disposition: mapped)
    }

    public func webContents(_ webContents: RoomWebContents, didChangeStatusText text: String?) {
        uiDelegate?.webContents(self, didChangeStatusText: text)
    }

    public func webContentsDidRequestEnterFullscreen(_ webContents: RoomWebContents, origin: URL?) {
        uiDelegate?.webContentsDidRequestEnterFullscreen(self, origin: origin)
    }

    public func webContentsDidRequestExitFullscreen(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidRequestExitFullscreen(self)
    }

    /// A key-down before the page sees it: a reserved one goes to the main
    /// menu here, once (as the CEF engine does), and never to the page.
    public func webContents(_ webContents: RoomWebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        guard uiDelegate?.webContents(self, isReservedKeyEvent: event) == true else { return false }
        _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
        return true
    }

    /// A key-down the page did not consume: the delegate offers it to the
    /// main menu (RoomCore does nothing else with it).
    public func webContents(_ webContents: RoomWebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        if let uiDelegate { return uiDelegate.webContents(self, handleUnhandledKeyEvent: event) }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
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
