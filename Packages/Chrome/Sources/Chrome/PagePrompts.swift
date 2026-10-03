import AppKit
import Engine

/// What a page asks the user in the card (ROADMAP 2.6 task 2): JavaScript
/// dialogs, `beforeunload`, HTTP authentication, a certificate error.
public enum PageDialog: Equatable {
    case alert(message: String, origin: URL?)
    case confirm(message: String, origin: URL?)
    case prompt(message: String, defaultText: String, origin: URL?)
    case beforeUnload(isReload: Bool, origin: URL?)
    case auth(AuthChallenge)
    case certificate(CertificateError)

    /// Closed by the engine itself when the page navigates or resets its
    /// dialogs (`webContentsDidDismissJavaScriptDialogs`).
    var isJavaScript: Bool {
        switch self {
        case .alert, .confirm, .prompt, .beforeUnload: true
        case .auth, .certificate: false
        }
    }
}

/// How the user answered a dialog.
public enum DialogResponse: Equatable {
    /// OK, Leave, Reload; a prompt's text.
    case accept(text: String?)
    /// Cancel, Stay, Esc, Go Back.
    case cancel
    case signIn(user: String, password: String)
    /// Visit the site despite its certificate.
    case proceed
}

/// The decisions behind the page's prompts, as pure functions (tested).
public enum PromptRules {
    /// Esc and closing without a choice: an alert is acknowledged, every
    /// other dialog answers its safe "no" (Stay, Cancel, Go Back).
    public static func escapeResponse(for dialog: PageDialog) -> DialogResponse {
        if case .alert = dialog { return .accept(text: nil) }
        return .cancel
    }

    /// Return: the dialog's primary button. A certificate error's is Go Back.
    public static func returnResponse(for dialog: PageDialog, text: String?) -> DialogResponse {
        switch dialog {
        case .alert, .confirm, .beforeUnload: .accept(text: nil)
        case .prompt: .accept(text: text ?? "")
        case .auth: .signIn(user: text ?? "", password: "")
        case .certificate: .cancel
        }
    }

    /// Proceeding past a certificate error only when the engine says the
    /// error can be bypassed (never on HSTS hosts, `CertificateRules`).
    public static func allowsProceed(_ dialog: PageDialog) -> Bool {
        if case .certificate(let error) = dialog { return error.isOverridable }
        return false
    }

    /// `beforeunload` decides whether a page can go: it is shown at once,
    /// over whatever the card shows (a page being closed has left its entry
    /// and the card). Every other dialog waits until its page is in the card.
    public static func showsImmediately(_ dialog: PageDialog) -> Bool {
        if case .beforeUnload = dialog { return true }
        return false
    }

    /// The permissions Chrome offers a one-time grant for ("Allow This Time").
    public static func offersOneTimeGrant(_ requests: [PermissionRequest]) -> Bool {
        requests.allSatisfy { [.camera, .microphone, .cameraPanTiltZoom, .geolocation].contains($0.kind) }
    }
}

/// The page's dialogs and permission prompts (ROADMAP 2.6 task 2), one
/// queue per page. The card shows the front dialog of the page it shows
/// (`beforeunload` shows at once, `PromptRules.showsImmediately`); the
/// permission popover shows the front permission prompt of the page in the
/// card. Every engine completion is called exactly once: with the user's
/// answer, with the escape answer when the page closes, or never when the
/// engine withdrew the prompt itself.
///
/// Presentation (the AppKit sheet, interstitial and popover) observes
/// `onChange`; tests drive it through `respond` and `respondToPermission`.
public final class PagePrompts {
    /// A dialog waiting for an answer.
    public struct Pending {
        public let id: Int
        public let dialog: PageDialog
        /// The page that asked.
        public let page: ObjectIdentifier
        fileprivate let answer: (DialogResponse) -> Void
    }

    /// A permission prompt waiting for an answer.
    public struct PendingPermission {
        public let id: Int
        public let requests: [PermissionRequest]
        public let page: ObjectIdentifier
        fileprivate let answer: (PermissionResponse) -> Void
    }

    /// The page in the card (`nil`: the empty state).
    public private(set) var currentPage: ObjectIdentifier?
    /// Called after anything that changes what is shown.
    public var onChange: (() -> Void)?
    /// A dialog arrived for a page not in the card (it waits there).
    public var onPageNeedsAttention: ((ObjectIdentifier) -> Void)?

    private var dialogs: [Pending] = []
    private var permissions: [PendingPermission] = []
    private var nextID = 1

    public init() {}

    /// The dialog the card shows now.
    public var visibleDialog: Pending? {
        dialogs.first { PromptRules.showsImmediately($0.dialog) } ?? dialogs.first { $0.page == currentPage }
    }

    /// The permission prompt the popover shows now (none while a dialog is up).
    public var visiblePermission: PendingPermission? {
        guard visibleDialog == nil else { return nil }
        return permissions.first { $0.page == currentPage }
    }

    /// Whether `page` has a prompt waiting (the sidebar may mark it).
    public func hasPending(_ page: ObjectIdentifier) -> Bool {
        dialogs.contains { $0.page == page } || permissions.contains { $0.page == page }
    }

    public func setCurrentPage(_ page: (any WebContents)?) {
        let id = page.map(ObjectIdentifier.init)
        guard id != currentPage else { return }
        currentPage = id
        onChange?()
    }

    // MARK: Asking

    /// Queues `dialog` for `page`; `answer` receives the user's response once.
    @discardableResult
    public func ask(_ dialog: PageDialog, for page: any WebContents, answer: @escaping (DialogResponse) -> Void) -> Int {
        let id = takeID()
        let pageID = ObjectIdentifier(page)
        dialogs.append(Pending(id: id, dialog: dialog, page: pageID, answer: answer))
        if pageID != currentPage, !PromptRules.showsImmediately(dialog) { onPageNeedsAttention?(pageID) }
        onChange?()
        return id
    }

    @discardableResult
    public func askPermission(_ requests: [PermissionRequest], for page: any WebContents,
                              answer: @escaping (PermissionResponse) -> Void) -> Int {
        let id = takeID()
        let pageID = ObjectIdentifier(page)
        permissions.append(PendingPermission(id: id, requests: requests, page: pageID, answer: answer))
        if pageID != currentPage { onPageNeedsAttention?(pageID) }
        onChange?()
        return id
    }

    // MARK: Answering

    /// Answers the visible dialog (or the one with `id`).
    public func respond(_ response: DialogResponse, to id: Int? = nil) {
        guard let pending = id.flatMap({ id in dialogs.first { $0.id == id } }) ?? visibleDialog else { return }
        // Proceeding is refused when the error cannot be bypassed; the dialog stays.
        if response == .proceed, !PromptRules.allowsProceed(pending.dialog) { return }
        dialogs.removeAll { $0.id == pending.id }
        pending.answer(response)
        onChange?()
    }

    public func respondToPermission(_ response: PermissionResponse, to id: Int? = nil) {
        guard let pending = id.flatMap({ id in permissions.first { $0.id == id } }) ?? visiblePermission else { return }
        permissions.removeAll { $0.id == pending.id }
        pending.answer(response)
        onChange?()
    }

    // MARK: The engine withdrawing prompts

    /// The engine closed the page's JavaScript dialogs (navigation, reset):
    /// they go without an answer.
    public func engineDismissedDialogs(for page: any WebContents) {
        let id = ObjectIdentifier(page)
        let before = dialogs.count
        dialogs.removeAll { $0.page == id && $0.dialog.isJavaScript }
        if dialogs.count != before { onChange?() }
    }

    /// The engine withdrew the page's permission prompt: the oldest one goes.
    public func engineDismissedPermission(for page: any WebContents) {
        let id = ObjectIdentifier(page)
        guard let index = permissions.firstIndex(where: { $0.page == id }) else { return }
        permissions.remove(at: index)
        onChange?()
    }

    /// The page closed: everything it still waits for is answered with its
    /// escape answer (dismissed for permissions), once.
    public func pageClosed(_ page: any WebContents) {
        let id = ObjectIdentifier(page)
        let closedDialogs = dialogs.filter { $0.page == id }
        let closedPermissions = permissions.filter { $0.page == id }
        guard !closedDialogs.isEmpty || !closedPermissions.isEmpty else { return }
        dialogs.removeAll { $0.page == id }
        permissions.removeAll { $0.page == id }
        closedDialogs.forEach { $0.answer(PromptRules.escapeResponse(for: $0.dialog)) }
        closedPermissions.forEach { $0.answer(.dismissed) }
        if currentPage == id { currentPage = nil }
        onChange?()
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
