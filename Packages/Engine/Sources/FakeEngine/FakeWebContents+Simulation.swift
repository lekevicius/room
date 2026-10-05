import AppKit
import Engine

/// Page-side events. Each one reaches the delegates the way an engine would
/// deliver it; the async ones return what the delegate answered.
public extension FakeWebContents {
    /// Where a key event ended up.
    enum KeyRoute: Sendable, Equatable {
        /// The delegate reserved it; the page never saw it.
        case reserved
        /// The page handled it.
        case consumedByPage
        /// The page ignored it and the delegate (or the main menu) handled it.
        case handledByDelegate
        /// Nobody handled it.
        case unhandled
    }

    /// A link click; ⌘-click and middle-click pass `.newBackgroundTab`.
    func simulateLinkClick(to url: URL, disposition: Disposition = .currentTab) {
        navigate(NavigationAction(
            url: url,
            referrer: self.url,
            kind: .linkActivated,
            transition: .link,
            disposition: disposition,
            isUserGesture: true
        ))
    }

    /// `window.open(url)` (`.newPopup` when the page passed window features).
    func simulateWindowOpen(_ url: URL, disposition: Disposition = .newForegroundTab) {
        simulateLinkClick(to: url, disposition: disposition)
    }

    /// `window.close()` from script.
    func simulateWindowClose() {
        closeNow()
    }

    func simulateAlert(_ message: String) async {
        await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, runJavaScriptAlert: message, origin: origin) {
                continuation.resume()
            }
        }
    }

    func simulateConfirm(_ message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, runJavaScriptConfirm: message, origin: origin) {
                continuation.resume(returning: $0)
            }
        }
    }

    func simulatePrompt(_ message: String, defaultText: String = "") async -> String? {
        await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, runJavaScriptPrompt: message, defaultText: defaultText, origin: origin) {
                continuation.resume(returning: $0)
            }
        }
    }

    /// The engine dismissing open dialogs (e.g. the page navigated away).
    func simulateDialogsDismissed() {
        effectiveUIDelegate.webContentsDidDismissJavaScriptDialogs(self)
    }

    func simulatePermissionRequest(
        _ kinds: [PermissionRequest.Kind],
        quietReason: PermissionQuietReason? = nil,
        systemAuthorization: PermissionRequest.SystemAuthorization = .notApplicable
    ) async -> PermissionResponse {
        let origin = origin ?? URL(string: "about:blank")!
        let requests = kinds.map { PermissionRequest(kind: $0, origin: origin, systemAuthorization: systemAuthorization) }
        return await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, willAskForPermission: requests, quietReason: quietReason) {
                continuation.resume(returning: $0)
            }
        }
    }

    func simulatePermissionPromptDismissed() {
        effectiveUIDelegate.webContentsDidDismissPermissionPrompt(self)
    }

    func simulateAuthChallenge(realm: String? = nil, scheme: String = "Basic", isProxy: Bool = false) async -> URLCredential? {
        let challenge = AuthChallenge(origin: origin ?? URL(string: "about:blank")!, realm: realm, scheme: scheme, isProxy: isProxy)
        return await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, didReceiveAuthChallenge: challenge) {
                continuation.resume(returning: $0)
            }
        }
    }

    func simulateCertificateError(code: Int = -202, description: String = "ERR_CERT_AUTHORITY_INVALID", isOverridable: Bool = true) async -> Bool {
        let error = CertificateError(
            url: url ?? URL(string: "about:blank")!,
            code: code,
            description: description,
            isOverridable: isOverridable
        )
        return await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, didFailCertificateCheck: error) {
                continuation.resume(returning: $0)
            }
        }
    }

    func simulateFileChooser(_ request: FileChooserRequest) async -> [URL]? {
        await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, runFileChooser: request) {
                continuation.resume(returning: $0)
            }
        }
    }

    /// A right-click. Returns the chosen command, or `nil` when the menu was
    /// cancelled or the delegate let the engine show its own menu (which the
    /// fake treats as cancelled).
    func simulateContextMenu(_ element: ContextMenuElement, items: [MenuItem]) async -> MenuItem.ID? {
        await withCheckedContinuation { continuation in
            let menu = MenuModel(items: items) { continuation.resume(returning: $0) }
            if !effectiveUIDelegate.webContents(self, willShowContextMenu: menu, for: element) {
                menu.cancel()
            }
        }
    }

    func simulateStatusText(_ text: String?) {
        effectiveUIDelegate.webContents(self, didChangeStatusText: text)
    }

    func simulateFullscreenRequest(enter: Bool) {
        isFullscreen = enter
        if enter {
            effectiveUIDelegate.webContentsDidRequestEnterFullscreen(self, origin: origin)
        } else {
            effectiveUIDelegate.webContentsDidRequestExitFullscreen(self)
        }
    }

    /// A key-down arriving at the page. `pageHandles` says whether the page's
    /// script consumes it.
    @discardableResult
    func simulateKeyDown(_ event: NSEvent, pageHandles: Bool) -> KeyRoute {
        let delegate = effectiveUIDelegate
        if delegate.webContents(self, isReservedKeyEvent: event) {
            _ = NSApp?.mainMenu?.performKeyEquivalent(with: event)
            return .reserved
        }
        if pageHandles {
            delegate.webContents(self, didConsumeKey: KeyEventInfo(keyCode: event.keyCode, modifiers: event.modifierFlags, phase: .keyDown))
            return .consumedByPage
        }
        return delegate.webContents(self, handleUnhandledKeyEvent: event) ? .handledByDelegate : .unhandled
    }
}

extension FakeWebContents {
    /// Origin of the current page, as engines report it to prompts.
    var origin: URL? {
        guard let url, let scheme = url.scheme, let host = url.host() else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        return components.url
    }

    // MARK: 3.4b: the renderer, other applications, notices, capture

    /// The renderer stops responding; returns the delegate's answer
    /// (`.terminate` ends it like a crash with `.killed`).
    public func simulateUnresponsive() async -> UnresponsiveRendererAction {
        let action = await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContentsDidBecomeUnresponsive(self) { continuation.resume(returning: $0) }
        }
        if action == .terminate {
            terminatedUnresponsiveCount += 1
            simulateCrash(.killed)
        }
        return action
    }

    /// The renderer answers again.
    public func simulateResponsive() {
        effectiveUIDelegate.webContentsDidBecomeResponsive(self)
    }

    /// A link to another application; returns whether the delegate let it open.
    @discardableResult
    public func simulateExternalURL(_ url: URL, applicationName: String = "Mail", isUserGesture: Bool = true) async -> Bool {
        let request = ExternalURLRequest(url: url, scheme: url.scheme?.lowercased() ?? "", initiatingOrigin: origin,
                                         isUserGesture: isUserGesture, applicationName: applicationName)
        let open = await withCheckedContinuation { continuation in
            effectiveUIDelegate.webContents(self, shouldOpenExternalURL: request) { continuation.resume(returning: $0) }
        }
        if open { openedExternalURLs.append(url) }
        return open
    }

    /// The engine adds a notice; `removeInfoBar` takes it away.
    public func simulateInfoBar(_ infoBar: InfoBar) {
        effectiveUIDelegate.webContents(self, didAddInfoBar: infoBar)
    }

    public func simulateInfoBarRemoved(_ infoBar: InfoBar) {
        infoBar.withdraw()
        effectiveUIDelegate.webContents(self, didRemoveInfoBar: infoBar)
    }

    /// The page starts or stops capturing.
    public func simulateCapture(_ state: CaptureState) {
        guard state != captureState else { return }
        captureState = state
        effectiveUIDelegate.webContents(self, didChangeCaptureState: state)
    }

    /// The page sets `navigator.mediaSession.metadata` (nil: none).
    public func simulateMediaSession(_ info: MediaSessionInfo?) {
        mediaSession = info
    }
}
