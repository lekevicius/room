import AppKit
import CEFBridge
import Engine
import Observation

/// `WebContents` over one CEF browser (Alloy style, hosted as a child view).
///
/// `nativeView` is a `CEFPageView` this object owns; the CEF browser's
/// container view sits inside it. That keeps the view stable across the
/// emulated `discard()`, which closes the browser and creates a new one on the
/// next `load`/`reload`.
@Observable
public final class CEFWebContents: NSObject, WebContents {
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
    /// Camera and microphone from `CefDisplayHandler::OnMediaAccessChange`;
    /// CEF reports no screen capture and cannot stop a capture.
    public private(set) var captureState = CaptureState()
    /// **CEF: not available** (no media session API): always `nil`.
    public var mediaSession: MediaSessionInfo? { nil }

    public var isMuted: Bool {
        didSet {
            guard isMuted != oldValue else { return }
            browser?.isAudioMuted = isMuted
            uiDelegate?.webContents(self, didChangeMuted: isMuted)
        }
    }

    public var zoomFactor = 1.0 {
        didSet {
            guard zoomFactor != oldValue else { return }
            browser?.zoomLevel = ZoomConversion.level(forFactor: zoomFactor)
        }
    }

    /// How often `isAudible` is re-checked with JavaScript after the page
    /// became audible (CEF reports only the "became audible" edge).
    @ObservationIgnored public var audibilityPollInterval: Duration = .seconds(1)
    /// Console messages from the page, for debugging and the spikes.
    @ObservationIgnored public var consoleMessageHandler: ((String) -> Void)?

    @ObservationIgnored let profile: CEFProfile
    @ObservationIgnored private(set) var browser: RoomCEFBrowser?
    @ObservationIgnored private let pageView = CEFPageView()
    @ObservationIgnored private var discarding = false
    @ObservationIgnored private var closeRequested = false
    @ObservationIgnored private var lastFindText: String?
    /// JavaScript dialogs waiting for the UI, by our own id.
    @ObservationIgnored private var pendingDialogs: [Int: (Bool, String?) -> Void] = [:]
    @ObservationIgnored private var nextDialogID = 1
    /// Permission prompts the UI delegate answered (their dismissal is not a withdrawal).
    @ObservationIgnored private var answeredPrompts: Set<UInt64> = []
    @ObservationIgnored private var faviconURL: String?
    /// The link under the pointer or keyboard focus (CEF's status message):
    /// tells a click on a link from a script navigation (B-33).
    @ObservationIgnored private var hoveredLink: URL?
    /// What the last `load` asked for: CEF commits every browser-initiated
    /// load as TYPED, so the requested transition stands in for it.
    @ObservationIgnored private var requestedTransition: PageTransition?
    /// The URL of the last commit reported to the navigation delegate.
    @ObservationIgnored private var committedURL: URL?
    /// A commit waiting one run-loop turn, so an error page is not reported.
    @ObservationIgnored private var pendingCommit: (url: URL, transition: PageTransition)?
    /// The URL of a main-frame load that failed since the last load request.
    @ObservationIgnored private var failedURL: String?
    @ObservationIgnored private var audibilityPoll: Task<Void, Never>?
    @ObservationIgnored private lazy var cefDevTools = CEFDevTools(contents: self)

    init(profile: CEFProfile, configuration: WebContentsConfiguration) throws {
        self.profile = profile
        self.configuration = configuration
        self.isMuted = configuration.initiallyMuted
        super.init()
        pageView.isHidden = configuration.initiallyHidden
        try createBrowser()
    }

    /// Wraps a popup the bridge created for `window.open`/`target=_blank`.
    init(profile: CEFProfile, popup: RoomCEFBrowser, configuration: WebContentsConfiguration) {
        self.profile = profile
        self.configuration = configuration
        self.isMuted = false
        super.init()
        attach(popup)
    }

    public var nativeView: NSView { pageView }

    var identifier: Int { browser?.identifier ?? 0 }

    private func createBrowser() throws {
        guard let browser = RoomCEFBrowser(requestContext: profile.context, hidden: false, delegate: self) else {
            throw EngineError.failed("CefBrowserHost::CreateBrowserSync returned null")
        }
        attach(browser)
    }

    private func attach(_ browser: RoomCEFBrowser) {
        self.browser = browser
        browser.delegate = self
        pageView.host(browser.containerView)
        state = .alive
        profile.register(self)
        if isMuted { browser.isAudioMuted = true }
        if zoomFactor != 1 { browser.zoomLevel = ZoomConversion.level(forFactor: zoomFactor) }
        if configuration.transparentBackground { applyTransparentBackground() }
    }

    // MARK: Navigation

    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        // CEF always loads with TYPED | FROM_ADDRESS_BAR; `transition` is
        // remembered and reported at the commit instead.
        dismissDialogsForNavigation()
        if state == .discarded { revive() }
        self.url = url
        requestedTransition = transition
        failedURL = nil
        browser?.loadURL(url.absoluteString)
    }

    public func goBack() {
        dismissDialogsForNavigation()
        browser?.goBack()
    }

    public func goForward() {
        dismissDialogsForNavigation()
        browser?.goForward()
    }

    /// Chrome's tab-modal dialog manager closes a page's JavaScript dialogs
    /// when a navigation starts; Alloy has none, and a same-site navigation
    /// cannot commit while the renderer waits in `alert()` (measured in
    /// 2.6b: the request went out, the page never changed). So a navigation
    /// Room starts answers them with Cancel and tells the UI delegate they are gone.
    private func dismissDialogsForNavigation() {
        guard !pendingDialogs.isEmpty else { return }
        let dialogs = pendingDialogs
        pendingDialogs = [:]
        for completion in dialogs.values { completion(false, nil) }
        uiDelegate?.webContentsDidDismissJavaScriptDialogs(self)
    }

    public func reload() {
        dismissDialogsForNavigation()
        if state == .discarded, let url {
            // A discarded page coming back is a reload, not a visit.
            load(url, transition: .reload, fromAddressBar: false)
        } else {
            browser?.reload()
        }
    }

    public func reloadIgnoringCache() {
        dismissDialogsForNavigation()
        if state == .discarded, let url {
            load(url, transition: .reload, fromAddressBar: false)
        } else {
            browser?.reloadIgnoringCache()
        }
    }

    public func stop() { browser?.stopLoad() }

    // MARK: Find

    public func find(_ text: String, forward: Bool, matchCase: Bool) {
        let findNext = text == lastFindText
        lastFindText = text
        browser?.find(text, forward: forward, matchCase: matchCase, findNext: findNext)
        // CEF's first request for a text only counts matches (active match 0,
        // measured in 2.6b); the follow-up selects the first one, as Chrome's
        // find bar does while typing.
        if !findNext { browser?.find(text, forward: forward, matchCase: matchCase, findNext: true) }
    }

    public func stopFind(clearSelection: Bool) {
        lastFindText = nil
        findResult = nil
        browser?.stopFinding(clearSelection)
    }

    // MARK: Lifecycle

    /// Emulated: closes the browser without beforeunload and keeps URL and
    /// title; the next `load`/`reload` creates a new browser (back/forward
    /// history is lost).
    /// **CEF: not available** (no navigation-entry serialisation, B-13).
    public var navigationState: Data? { nil }

    /// **CEF: not available**: CEF cannot see form input, Picture-in-Picture
    /// or captures (B-17); the host's 2.3 rules (selected, audible) apply alone.
    public var discardBlockers: DiscardBlockers { [] }

    public func discard() throws {
        guard state == .alive, let browser else { return }
        discarding = true
        browser.close(true)
    }

    private func revive() {
        do {
            try createBrowser()
        } catch {
            NSLog("Room: could not recreate discarded browser: \(error)")
        }
    }

    public func close() {
        if state == .discarded {
            state = .closed
            uiDelegate?.webContentsDidClose(self)
            return
        }
        guard let browser, state != .closed else { return }
        closeRequested = true
        browser.close(false)
    }

    // MARK: Tools

    public var devTools: (any DevTools)? { cefDevTools }

    public func captureViewport() async throws -> NSImage {
        let result = try await devToolsMethod("Page.captureScreenshot", params: ["format": "png"])
        guard let base64 = result["data"] as? String, let data = Data(base64Encoded: base64),
              let rep = NSBitmapImageRep(data: data)
        else { throw EngineError.failed("Page.captureScreenshot returned no image") }
        let scale = pageView.window?.backingScaleFactor ?? 2
        let image = NSImage(size: NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale))
        image.addRepresentation(rep)
        return image
    }

    public func executeJavaScript(_ script: String) async throws -> String {
        let result = try await devToolsMethod(
            "Runtime.evaluate",
            params: ["expression": script, "returnByValue": true, "awaitPromise": true]
        )
        if let exception = result["exceptionDetails"] as? [String: Any] {
            let description = ((exception["exception"] as? [String: Any])?["description"] as? String)
                ?? (exception["text"] as? String) ?? "exception"
            throw EngineError.javaScriptException(description)
        }
        guard let value = (result["result"] as? [String: Any])?["value"] else { return "null" }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public func print() { browser?.printPage() }

    public func exitFullscreen() { browser?.exitFullscreen() }

    /// **CEF: not available** (no API to stop a page's capture): no-op.
    public func stopCapturing(_ kinds: CaptureKinds) {}

    /// Sends a DevTools protocol command over CEF's in-process channel and
    /// returns the decoded result object.
    public func devToolsMethod(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard let browser, state == .alive else { throw EngineError.closed }
        let json = params.isEmpty ? nil : String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
        let (success, data): (Bool, Data) = await withCheckedContinuation { continuation in
            browser.executeDevToolsMethod(method, paramsJSON: json) { success, data in
                continuation.resume(returning: (success, data))
            }
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard success else {
            throw EngineError.failed("\(method): \(object["message"] as? String ?? String(decoding: data, as: UTF8.self))")
        }
        return object
    }

    // MARK: Emulated page state

    private func applyTransparentBackground() {
        Task {
            _ = try? await devToolsMethod(
                "Emulation.setDefaultBackgroundColorOverride",
                params: ["color": ["r": 0, "g": 0, "b": 0, "a": 0]]
            )
        }
    }

    /// `themeColor` and `rootBackgroundColor` read after each main-frame load.
    private func readPageColors() {
        Task {
            guard let json = try? await executeJavaScript(PageScripts.colors),
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            else { return }
            themeColor = CSSColor.parse(object["theme"] as? String)
            if configuration.transparentBackground {
                rootBackgroundColor = nil
                return
            }
            let candidates = [object["root"], object["body"]].compactMap { CSSColor.parse($0 as? String) }
            if let opaque = candidates.first(where: { $0.alphaComponent > 0 }) {
                rootBackgroundColor = opaque.withAlphaComponent(1)
            } else {
                // Nothing painted a background: Chromium's canvas default.
                let dark = (object["scheme"] as? String)?.contains("dark") == true
                rootBackgroundColor = dark ? NSColor(srgbRed: 18 / 255, green: 18 / 255, blue: 18 / 255, alpha: 1) : .white
            }
        }
    }

    private func updateSecurityState() {
        let level: SecurityState.Level
        var mixed = false
        let status = browser?.visibleSecurityStatus()
        switch url?.scheme {
        case "https", "wss":
            if let status {
                level = status.certificateError ? .dangerous : (status.secureConnection ? .secure : .none)
                mixed = status.mixedContent
            } else {
                level = .none
            }
        case "http", "ws":
            level = .insecure
        default:
            level = .none
        }
        let newState = SecurityState(level: level, hasMixedContent: mixed)
        guard newState != securityState else { return }
        securityState = newState
        uiDelegate?.webContents(self, didChangeSecurityState: newState)
    }

    private func setAudible(_ audible: Bool) {
        guard audible != isAudible else { return }
        isAudible = audible
        uiDelegate?.webContents(self, didChangeAudible: audible)
    }

    /// CEF reports only the start of audio; poll media elements for the end.
    private func startAudibilityPoll() {
        audibilityPoll?.cancel()
        audibilityPoll = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.audibilityPollInterval else { return }
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled, self.state == .alive else { return }
                let playing = (try? await self.executeJavaScript(PageScripts.mediaPlaying)) ?? "false"
                if playing != "true" {
                    self.setAudible(false)
                    return
                }
            }
        }
    }

    private func openInNewContents(_ url: URL, disposition: Disposition) {
        guard let uiDelegate,
              let contents = try? CEFWebContents(profile: profile, configuration: WebContentsConfiguration(initiallyHidden: disposition == .newBackgroundTab))
        else { return }
        contents.load(url)
        uiDelegate.webContents(self, didCreate: contents, targetURL: url, disposition: disposition)
    }
}

// MARK: - Bridge callbacks

extension CEFWebContents: RoomCEFBrowserDelegate {
    public func browser(_ browser: RoomCEFBrowser, shouldOpenPopupWithURL url: String?, disposition: RoomCEFDisposition, userGesture: Bool) -> Bool {
        guard uiDelegate != nil else { return false }
        let target = url.flatMap(URL.init(string:))
        if let navigationDelegate, let target {
            let action = NavigationAction(
                url: target,
                referrer: self.url,
                kind: .linkActivated,
                transition: .link,
                disposition: Disposition(disposition),
                isUserGesture: userGesture
            )
            if navigationDelegate.webContents(self, decidePolicyFor: action) == .ignore { return false }
        }
        return true
    }

    public func browser(_ browser: RoomCEFBrowser, didCreatePopup popup: RoomCEFBrowser, targetURL url: String?, disposition: RoomCEFDisposition, userGesture: Bool) {
        let contents = CEFWebContents(profile: profile, popup: popup, configuration: WebContentsConfiguration())
        if let uiDelegate {
            uiDelegate.webContents(self, didCreate: contents, targetURL: url.flatMap(URL.init(string:)), disposition: Disposition(disposition))
        } else {
            contents.close()
        }
    }

    public func browserDidClose(_ browser: RoomCEFBrowser) {
        guard browser === self.browser else { return }
        self.browser = nil
        audibilityPoll?.cancel()
        setAudible(false)
        isLoading = false
        loadProgress = 1
        profile.unregister(self)
        if discarding && !closeRequested {
            discarding = false
            state = .discarded
            canGoBack = false
            canGoForward = false
            return
        }
        state = .closed
        uiDelegate?.webContentsDidClose(self)
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeAddress url: String) {
        let address = URL(string: url)
        self.url = address
        updateSecurityState()
        // A new address that no `OnLoadStart` claims in the same turn is a
        // same-document navigation (fragment, `pushState`; CEF reports those
        // as loading too, so the loading state cannot tell them apart).
        guard let address, committedURL != nil, address != committedURL else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.committedURL != address, self.url == address else { return }
            self.committedURL = address
            self.navigationDelegate?.webContents(self, didCommitNavigation: address, transition: .link)
        }
    }

    public func browser(_ browser: RoomCEFBrowser, didCommitMainFrameNavigation url: String, transition: RoomCEFTransition) {
        guard let committed = URL(string: url) else { return }
        var reported = PageTransition(transition)
        if transition == .typed, let requestedTransition { reported = requestedTransition }
        requestedTransition = nil
        committedURL = committed
        pendingCommit = (committed, reported)
        // `OnLoadError` for an error page arrives around the commit, in the same turn.
        DispatchQueue.main.async { [weak self] in self?.deliverPendingCommit() }
    }

    public func browser(_ browser: RoomCEFBrowser, didFailMainFrameLoad errorCode: Int, errorText: String, url: String) {
        // ERR_ABORTED (-3): cancelled (a policy decision, a download, a newer load), not an error page.
        if errorCode != -3 { failedURL = url }
    }

    private func deliverPendingCommit() {
        guard let pending = pendingCommit else { return }
        pendingCommit = nil
        guard pending.url.absoluteString != failedURL else { return }
        navigationDelegate?.webContents(self, didCommitNavigation: pending.url, transition: pending.transition)
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeTitle title: String?) {
        self.title = title
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeFaviconURLs urls: [String]) {
        guard let first = urls.first else {
            faviconURL = nil
            favicon = nil
            return
        }
        guard first != faviconURL else { return }
        faviconURL = first
        let scale = pageView.window?.backingScaleFactor ?? 2
        browser.downloadFavicon(first, maxSize: Int(16 * scale)) { [weak self] image in
            guard let self, self.faviconURL == first else { return }
            image?.size = NSSize(width: 16, height: 16)
            self.favicon = image
        }
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeFullscreen fullscreen: Bool) {
        if fullscreen {
            uiDelegate?.webContentsDidRequestEnterFullscreen(self, origin: url)
        } else {
            uiDelegate?.webContentsDidRequestExitFullscreen(self)
        }
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeStatusMessage message: String?) {
        hoveredLink = message.flatMap(URL.init(string:))
        uiDelegate?.webContents(self, didChangeStatusText: message?.isEmpty == true ? nil : message)
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeLoadingProgress progress: Double) {
        loadProgress = progress
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeConsoleMessage message: String, source: String, line: Int) {
        consoleMessageHandler?(message)
    }

    public func browser(_ browser: RoomCEFBrowser, loadingStateChanged isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        if !isLoading {
            loadProgress = 1
            updateSecurityState()
            // Chrome keeps zoom per host: a navigation can change it under us.
            let engineZoom = ZoomConversion.factor(forLevel: browser.zoomLevel)
            if abs(engineZoom - zoomFactor) > 0.001 { zoomFactor = engineZoom }
        }
    }

    public func browser(_ browser: RoomCEFBrowser, didFinishMainFrameLoad httpStatusCode: Int) {
        updateSecurityState()
        readPageColors()
    }

    public func browser(_ browser: RoomCEFBrowser, isReservedKeyEvent event: NSEvent) -> Bool {
        guard uiDelegate?.webContents(self, isReservedKeyEvent: event) == true else { return false }
        // Kept from the page; the menu gets it instead.
        _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
        return true
    }

    public func browser(_ browser: RoomCEFBrowser, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        if let uiDelegate { return uiDelegate.webContents(self, handleUnhandledKeyEvent: event) }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    public func browser(_ browser: RoomCEFBrowser, shouldCancelNavigation request: RoomCEFNavigationRequest) -> Bool {
        if !request.redirect { failedURL = nil }
        guard let navigationDelegate else { return false }
        var action = NavigationAction(request)
        // CEF reports a click on a link and the page's script setting
        // `window.location` alike (TT_LINK with a gesture): only a navigation
        // to the link under the pointer or keyboard focus (the status text)
        // counts as a click; anything else is the script's (B-33: a page that
        // rewrites href on mousedown is misjudged; RoomCore knows exactly).
        if action.kind == .linkActivated, !request.redirect,
           !(hoveredLink.map { Self.sameDocument($0, action.url) } ?? false) {
            action.kind = .other
        }
        let decision = navigationDelegate.webContents(self, decidePolicyFor: action)
        switch decision {
        case .currentTab:
            return false
        case .ignore:
            return true
        default:
            openInNewContents(action.url, disposition: decision)
            return true
        }
    }

    public func browser(_ browser: RoomCEFBrowser, shouldCancelOpenURL url: String, disposition: RoomCEFDisposition, userGesture: Bool) -> Bool {
        let requested = Disposition(disposition)
        guard let target = URL(string: url) else { return true }
        var decision = requested
        if let navigationDelegate {
            let action = NavigationAction(url: target, referrer: self.url, kind: .linkActivated, transition: .link, disposition: requested, isUserGesture: userGesture)
            decision = navigationDelegate.webContents(self, decidePolicyFor: action)
        }
        switch decision {
        case .currentTab:
            return false
        case .ignore:
            return true
        default:
            // Alloy would load it in this browser; open it as new contents instead.
            openInNewContents(target, disposition: decision)
            return true
        }
    }

    public func browser(_ browser: RoomCEFBrowser, authChallengeForOrigin origin: String, isProxy: Bool, realm: String?, scheme: String, completion: @escaping (String?, String?) -> Void) {
        guard let uiDelegate, let originURL = URL(string: origin) else {
            completion(nil, nil)
            return
        }
        let challenge = AuthChallenge(origin: originURL, realm: realm, scheme: scheme, isProxy: isProxy)
        uiDelegate.webContents(self, didReceiveAuthChallenge: challenge) { credential in
            completion(credential?.user, credential?.password)
        }
    }

    public func browser(_ browser: RoomCEFBrowser, certificateError errorCode: Int, url: String, certificates derChain: [Data], completion: @escaping (Bool) -> Void) {
        guard let uiDelegate, let pageURL = URL(string: url) else {
            completion(false)
            return
        }
        // CEF does not say whether the host has HSTS (`strict_enforcement`): the conservative rule.
        let overridable = CertificateRules.isOverridable(code: errorCode, host: pageURL.host() ?? "", strictTransportSecurity: nil)
        let error = CertificateError(url: pageURL, code: errorCode, description: CertificateErrorNames.name(for: errorCode),
                                     certificateChain: derChain, isOverridable: overridable)
        uiDelegate.webContents(self, didFailCertificateCheck: error, completion: completion)
    }

    public func browser(_ browser: RoomCEFBrowser, renderProcessTerminated status: RoomCEFTerminationStatus) {
        uiDelegate?.webContents(self, processGone: TerminationStatus(status))
    }

    /// `CefRequestHandler::OnRenderProcessUnresponsive` (CEF's hang monitor).
    public func browser(_ browser: RoomCEFBrowser, renderProcessUnresponsiveWithCompletion completion: @escaping (Bool) -> Void) {
        guard let uiDelegate else { return completion(false) }
        uiDelegate.webContentsDidBecomeUnresponsive(self) { completion($0 == .terminate) }
    }

    public func browserRenderProcessResponsive(_ browser: RoomCEFBrowser) {
        uiDelegate?.webContentsDidBecomeResponsive(self)
    }

    public func browser(_ browser: RoomCEFBrowser, didChangeMediaAccessVideo video: Bool, audio: Bool) {
        var state = CaptureState()
        if video { state.insert(.camera) }
        if audio { state.insert(.microphone) }
        guard state != captureState else { return }
        captureState = state
        uiDelegate?.webContents(self, didChangeCaptureState: state)
    }

    public func browser(_ browser: RoomCEFBrowser, permissionPrompt promptID: UInt64, origin: String, permissions: RoomCEFPermissionTypes, completion: @escaping (RoomCEFPermissionResult) -> Void) {
        let originURL = URL(string: origin) ?? URL(string: "about:blank")!
        // CEF does not report macOS's authorization (`.notApplicable`).
        let requests = PermissionRequest.Kind.kinds(in: permissions).map {
            PermissionRequest(kind: $0, origin: originURL, systemAuthorization: .notApplicable)
        }
        guard let uiDelegate, !requests.isEmpty else {
            completion(.dismiss)
            return
        }
        uiDelegate.webContents(self, willAskForPermission: requests, quietReason: nil) { [weak self] response in
            self?.answeredPrompts.insert(promptID)
            completion(RoomCEFPermissionResult(response))
        }
    }

    /// CEF reports every prompt's end here, answered ones included: only a
    /// prompt nobody answered was withdrawn by the engine (`cef_permission_handler.h`).
    public func browser(_ browser: RoomCEFBrowser, dismissPermissionPrompt promptID: UInt64) {
        if answeredPrompts.remove(promptID) != nil { return }
        uiDelegate?.webContentsDidDismissPermissionPrompt(self)
    }

    public func browser(_ browser: RoomCEFBrowser, mediaAccessForOrigin origin: String, permissions: RoomCEFMediaAccess, completion: @escaping (RoomCEFMediaAccess) -> Void) {
        let originURL = URL(string: origin) ?? URL(string: "about:blank")!
        // CEF does not report macOS's authorization (`.notApplicable`).
        let requests = PermissionRequest.Kind.kinds(in: permissions).map {
            PermissionRequest(kind: $0, origin: originURL, systemAuthorization: .notApplicable)
        }
        guard let uiDelegate, !requests.isEmpty else {
            completion([])
            return
        }
        uiDelegate.webContents(self, willAskForPermission: requests, quietReason: nil) { response in
            completion(response == .granted || response == .grantedOnce ? permissions : [])
        }
    }

    public func browser(_ browser: RoomCEFBrowser, runJSDialog type: RoomCEFJSDialogType, message: String, defaultText: String, origin: String?, completion engineCompletion: @escaping (Bool, String?) -> Void) {
        let originURL = origin.flatMap(URL.init(string:))
        guard let uiDelegate else {
            engineCompletion(false, nil)
            return
        }
        // Answered once: by the UI, or with Cancel when a navigation dismisses it.
        let id = nextDialogID
        nextDialogID += 1
        pendingDialogs[id] = engineCompletion
        let completion: (Bool, String?) -> Void = { [weak self] success, text in
            guard let self, let pending = self.pendingDialogs.removeValue(forKey: id) else { return }
            pending(success, text)
        }
        switch type {
        case .alert:
            uiDelegate.webContents(self, runJavaScriptAlert: message, origin: originURL) { completion(true, nil) }
        case .confirm:
            uiDelegate.webContents(self, runJavaScriptConfirm: message, origin: originURL) { completion($0, nil) }
        case .prompt:
            uiDelegate.webContents(self, runJavaScriptPrompt: message, defaultText: defaultText, origin: originURL) { text in
                completion(text != nil, text)
            }
        @unknown default:
            completion(false, nil)
        }
    }

    public func browser(_ browser: RoomCEFBrowser, runBeforeUnloadDialogIsReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        let answer: (Bool) -> Void = { [weak self] leave in
            if !leave {
                self?.closeRequested = false
                CEFApplication.current?.cancelTermination()
            }
            completion(leave)
        }
        guard let uiDelegate else {
            answer(true)
            return
        }
        uiDelegate.webContents(self, runBeforeUnloadDialogForReload: isReload, completion: answer)
    }

    public func browserDidResetDialogState(_ browser: RoomCEFBrowser) {
        // Whatever was pending is gone with the engine's state.
        pendingDialogs = [:]
        uiDelegate?.webContentsDidDismissJavaScriptDialogs(self)
    }

    public func browser(_ browser: RoomCEFBrowser, runContextMenu items: [RoomCEFMenuItem], params: RoomCEFContextMenuParams, completion: @escaping (Int) -> Void) -> Bool {
        guard let uiDelegate else { return false }
        let menu = MenuModel(items: items.map(MenuItem.init)) { id in completion(id ?? -1) }
        let presented = uiDelegate.webContents(self, willShowContextMenu: menu, for: ContextMenuElement(params))
        if !presented { menu.cancel() }
        return presented
    }

    public func browser(_ browser: RoomCEFBrowser, runFileDialog mode: RoomCEFFileDialogMode, title: String?, defaultPath: String?, acceptTypes: [String], completion: @escaping ([String]?) -> Void) -> Bool {
        guard let uiDelegate else { return false }
        let request = FileChooserRequest(
            mode: FileChooserRequest.Mode(mode),
            title: title,
            defaultPath: defaultPath.map { URL(fileURLWithPath: $0) },
            acceptTypes: acceptTypes
        )
        uiDelegate.webContents(self, runFileChooser: request) { urls in
            completion(urls?.map(\.path))
        }
        return true
    }

    public func browser(_ browser: RoomCEFBrowser, findResultCount count: Int, activeMatch: Int, finalUpdate: Bool) {
        guard lastFindText != nil else { return }
        findResult = FindResult(matchCount: count, activeMatch: activeMatch, isFinal: finalUpdate)
    }

    public func browser(_ browser: RoomCEFBrowser, willBeginDownload item: RoomCEFDownloadItem, suggestedName: String, completion: @escaping (String?) -> Void) {
        var download = DownloadItem(item)
        download.suggestedFilename = suggestedName
        profile.willBeginDownload(download) { completion($0?.path) }
    }

    public func browser(_ browser: RoomCEFBrowser, didUpdateDownload item: RoomCEFDownloadItem, control: RoomCEFDownloadControl) {
        profile.didUpdateDownload(DownloadItem(item), control: control)
    }

    public func browserDidBecomeAudible(_ browser: RoomCEFBrowser) {
        setAudible(true)
        startAudibilityPoll()
    }
}

/// The view `nativeView` returns: hosts the CEF browser's container and
/// starts hidden for `initiallyHidden` until the host adds it somewhere.
final class CEFPageView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("web-contents")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func host(_ container: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        addSubview(container)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil { isHidden = false }
    }
}

/// JavaScript the CEF engine runs to emulate page state Chromium would report.
enum PageScripts {
    static let colors = """
    (() => {
      const bg = e => e ? getComputedStyle(e).backgroundColor : null;
      const meta = document.querySelector('meta[name="theme-color"]');
      return { root: bg(document.documentElement), body: bg(document.body),
               theme: meta ? meta.content : null,
               scheme: getComputedStyle(document.documentElement).colorScheme };
    })()
    """

    /// Top-document media only: misses iframes and Web Audio.
    static let mediaPlaying = """
    [...document.querySelectorAll('video,audio')].some(m =>
      !m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState > 2)
    """
}

/// `net::Error` names for the certificate errors CEF reports.
enum CertificateErrorNames {
    static func name(for code: Int) -> String {
        switch code {
        case -200: "ERR_CERT_COMMON_NAME_INVALID"
        case -201: "ERR_CERT_DATE_INVALID"
        case -202: "ERR_CERT_AUTHORITY_INVALID"
        case -203: "ERR_CERT_CONTAINS_ERRORS"
        case -204: "ERR_CERT_NO_REVOCATION_MECHANISM"
        case -205: "ERR_CERT_UNABLE_TO_CHECK_REVOCATION"
        case -206: "ERR_CERT_REVOKED"
        case -207: "ERR_CERT_INVALID"
        case -208: "ERR_CERT_WEAK_SIGNATURE_ALGORITHM"
        case -210: "ERR_CERT_NON_UNIQUE_NAME"
        case -211: "ERR_CERT_WEAK_KEY"
        case -212: "ERR_CERT_NAME_CONSTRAINT_VIOLATION"
        case -213: "ERR_CERT_VALIDITY_TOO_LONG"
        case -214: "ERR_CERTIFICATE_TRANSPARENCY_REQUIRED"
        case -217: "ERR_CERT_KNOWN_INTERCEPTION_BLOCKED"
        default: "net error \(code)"
        }
    }
}

extension CEFWebContents {
    /// The same URL but for the fragment and a trailing slash.
    nonisolated static func sameDocument(_ a: URL, _ b: URL) -> Bool {
        func key(_ url: URL) -> String {
            var string = url.absoluteString
            if let hash = string.firstIndex(of: "#") { string = String(string[..<hash]) }
            if string.hasSuffix("/") { string.removeLast() }
            return string
        }
        return key(a) == key(b)
    }
}
