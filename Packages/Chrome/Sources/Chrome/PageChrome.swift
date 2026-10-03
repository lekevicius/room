import AppKit
import Engine

/// The page's chrome surfaces behind the engine's UI delegate (ROADMAP 2.6
/// task 2): JavaScript dialogs, `beforeunload`, permissions, HTTP auth and
/// certificate errors through `prompts`; context menus with Room's items;
/// file choosers. Presentation is injected so tests run it on FakeEngine
/// pages without a window.
public final class PageChrome: WebContentsUIDelegate {
    public let prompts = PagePrompts()
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

    // MARK: Lifetime

    public func webContentsDidClose(_ webContents: any WebContents) {
        prompts.pageClosed(webContents)
    }
}
