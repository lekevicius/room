import AppKit
import Design
import Engine

/// The page's chrome surfaces behind the engine's UI delegate (ROADMAP 2.6
/// task 2): JavaScript dialogs, `beforeunload`, permissions, HTTP auth and
/// certificate errors through `prompts`; context menus with Room's items;
/// file choosers. Presentation is injected so tests run it on FakeEngine
/// pages without a window.
public final class PageChrome: WebContentsUIDelegate {
    public let prompts = PagePrompts()
    /// Pages whose renderer went away (the crashed-page view, 2.6b).
    public let crashes = PageCrashes()
    /// Shows a context menu at a point of the page's view (default: `NSMenu` pop-up on the next turn).
    public var presentMenu: (ContextMenu, NSPoint, NSView) -> Void = { menu, point, view in
        // Outside the engine's callback: the pop-up runs its own event loop.
        DispatchQueue.main.async { MainActor.assumeIsolated { menu.popUp(at: point, in: view) } }
    }
    /// Runs a file chooser (default: the system panel as a sheet on the page's window).
    public var chooseFiles: (FileChooserRequest, (any WebContents), @escaping ([URL]?) -> Void) -> Void = { request, page, completion in
        guard let window = page.nativeView.window else { return completion(nil) }
        FileChooser.run(request, in: window, completion: completion)
    }
    /// Room's context-menu items (open in a new tab, Peek, copy).
    public var performMenuAction: ((RoomMenuAction, any WebContents) -> Void)?
    /// Whether Open Link in Peek is enabled (Phase 2.7).
    public var isPeekAvailable = false
    /// Links to other applications: once per scheme for the session (3.4b).
    public let externalApps = ExternalApps()
    /// Shows a notice (an engine infobar, the translate offer) as a toast;
    /// `dismissNotice` takes it down by the toast's id (3.4b).
    public var showNotice: ((Toast) -> Void)?
    public var dismissNotice: ((String) -> Void)?
    /// The notices still pending, oldest first (spikes read them).
    public private(set) var notices: [InfoBar] = []
    /// Opens `chrome://password-manager` as a tab (the password popover's
    /// Manage, the saved confirmation's action; 5.8a).
    public var openPasswordManager: (() -> Void)?

    public init() {}

    // MARK: JavaScript dialogs

    public func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?,
                            completion: @escaping () -> Void) {
        prompts.ask(.alert(message: message, origin: origin), for: webContents) { _ in completion() }
    }

    public func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?,
                            completion: @escaping (Bool) -> Void) {
        prompts.ask(.confirm(message: message, origin: origin), for: webContents) { completion($0 == .accept(text: nil)) }
    }

    public func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?,
                            completion: @escaping (String?) -> Void) {
        prompts.ask(.prompt(message: message, defaultText: defaultText, origin: origin), for: webContents) { response in
            if case .accept(let text) = response { completion(text ?? "") } else { completion(nil) }
        }
    }

    public func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool,
                            completion: @escaping (Bool) -> Void) {
        prompts.ask(.beforeUnload(isReload: isReload, origin: webContents.url), for: webContents) { completion($0 == .accept(text: nil)) }
    }

    public func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {
        prompts.engineDismissedDialogs(for: webContents)
    }

    // MARK: Permissions, auth, certificates

    public func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest],
                            quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        prompts.askPermission(requests, for: webContents, answer: completion)
    }

    public func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {
        prompts.engineDismissedPermission(for: webContents)
    }

    public func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge,
                            completion: @escaping (URLCredential?) -> Void) {
        prompts.ask(.auth(challenge), for: webContents) { response in
            if case .signIn(let user, let password) = response {
                completion(URLCredential(user: user, password: password, persistence: .forSession))
            } else {
                completion(nil)
            }
        }
    }

    /// Go Back cancels the navigation and returns to the previous page when
    /// there is one; Proceed only when the error can be bypassed (`PromptRules`).
    public func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError,
                            completion: @escaping (Bool) -> Void) {
        prompts.ask(.certificate(error), for: webContents) { [weak webContents] response in
            let proceed = response == .proceed
            completion(proceed)
            if !proceed, let webContents, webContents.canGoBack { webContents.goBack() }
        }
    }

    // MARK: Passwords (5.8a)

    /// Room presents every save offer: the popover on the site button; Save
    /// is confirmed with a toast whose Manage opens the password manager.
    public func webContents(_ webContents: any WebContents, willOfferPasswordSave offer: PasswordOffer,
                            completion: @escaping (PasswordOfferResponse) -> Void) -> Bool {
        offerPassword(offer, for: webContents, completion: completion)
    }

    public func webContents(_ webContents: any WebContents, willOfferPasswordUpdate offer: PasswordOffer,
                            completion: @escaping (PasswordOfferResponse) -> Void) -> Bool {
        offerPassword(offer, for: webContents, completion: completion)
    }

    /// The engine saved a password itself (a generated one): the same confirmation.
    public func webContents(_ webContents: any WebContents, didSavePassword offer: PasswordOffer) -> Bool {
        confirmSaved(offer, after: .save)
        return true
    }

    public func webContentsDidWithdrawPasswordOffer(_ webContents: any WebContents) {
        prompts.engineWithdrewPasswordOffer(for: webContents)
    }

    private func offerPassword(_ offer: PasswordOffer, for webContents: any WebContents,
                               completion: @escaping (PasswordOfferResponse) -> Void) -> Bool {
        prompts.offerPassword(offer, for: webContents) { [weak self] response in
            completion(response)
            self?.confirmSaved(offer, after: response)
        }
        return true
    }

    private func confirmSaved(_ offer: PasswordOffer, after response: PasswordOfferResponse) {
        guard let message = PasswordOfferRules.confirmation(offer, after: response) else { return }
        let manage = Toast.Action(title: "Manage") { [weak self] in self?.openPasswordManager?() }
        showNotice?(Toast(id: PasswordOfferRules.confirmationToastID, symbol: .password, message: message, action: manage))
    }

    // MARK: Menus and files

    public func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        let contextMenu = ContextMenu(model: menu, element: element, peekAvailable: isPeekAvailable) { [weak self, weak webContents] action in
            guard let webContents else { return }
            self?.performMenuAction?(action, webContents)
        }
        presentMenu(contextMenu, element.location, webContents.nativeView)
        return true
    }

    public func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest,
                            completion: @escaping ([URL]?) -> Void) {
        chooseFiles(request, webContents, completion)
    }

    // MARK: The renderer, other applications, notices (3.4b)

    public func webContentsDidBecomeUnresponsive(_ webContents: any WebContents,
                                                 completion: @escaping (UnresponsiveRendererAction) -> Void) {
        crashes.unresponsive(webContents, answer: completion)
    }

    public func webContentsDidBecomeResponsive(_ webContents: any WebContents) {
        crashes.responsive(webContents)
    }

    /// The first link of a scheme asks (a sheet in the card); after Open the
    /// scheme opens without asking for the rest of the session.
    public func webContents(_ webContents: any WebContents, shouldOpenExternalURL request: ExternalURLRequest,
                            completion: @escaping (Bool) -> Void) {
        if externalApps.isAllowed(request.scheme) { return completion(true) }
        prompts.ask(.externalApp(request), for: webContents) { [weak self] response in
            let open = response == .accept(text: nil)
            if open { self?.externalApps.allow(request.scheme) }
            completion(open)
        }
    }

    public static func noticeToastID(_ infoBar: InfoBar) -> String { "notice-\(infoBar.id)" }

    /// A toast with the notice's first button; it goes when the engine removes the notice.
    public func webContents(_ webContents: any WebContents, didAddInfoBar infoBar: InfoBar) {
        notices.append(infoBar)
        let action = infoBar.buttons.first.map { title in
            Toast.Action(title: title) { [weak infoBar] in infoBar?.press(0) }
        }
        showNotice?(Toast(id: Self.noticeToastID(infoBar), symbol: .info, message: infoBar.message, action: action))
    }

    public func webContents(_ webContents: any WebContents, didRemoveInfoBar infoBar: InfoBar) {
        notices.removeAll { $0 === infoBar }
        dismissNotice?(Self.noticeToastID(infoBar))
    }

    // MARK: Lifetime

    public func webContentsDidClose(_ webContents: any WebContents) {
        prompts.pageClosed(webContents)
        crashes.pageClosed(webContents)
    }

    // MARK: The renderer

    public func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        crashes.crashed(webContents, status: status)
    }
}
