import AppKit
import Engine
import Observation

/// What a page asks the user in the card (ROADMAP 2.6 task 2): JavaScript
/// dialogs, `beforeunload`, HTTP authentication, a certificate error.
public enum PageDialog: Equatable {
    case alert(message: String, origin: URL?)
    case confirm(message: String, origin: URL?)
    case prompt(message: String, defaultText: String, origin: URL?)
    case beforeUnload(isReload: Bool, origin: URL?)
    case auth(AuthChallenge)
    case certificate(CertificateError)
    /// A link to another application (3.4b; asked once per scheme, `ExternalApps`).
    case externalApp(ExternalURLRequest)

    /// Closed by the engine itself when the page navigates or resets its
    /// dialogs (`webContentsDidDismissJavaScriptDialogs`).
    var isJavaScript: Bool {
        switch self {
        case .alert, .confirm, .prompt, .beforeUnload: true
        case .auth, .certificate, .externalApp: false
        }
    }

    /// An alert, confirm or prompt: the dialogs a page can repeat, which
    /// "Prevent additional dialogs" silences (B-116; never `beforeunload`).
    public var isSuppressible: Bool {
        switch self {
        case .alert, .confirm, .prompt: true
        case .beforeUnload, .auth, .certificate, .externalApp: false
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
        case .alert, .confirm, .beforeUnload, .externalApp: .accept(text: nil)
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

    /// "Prevent additional dialogs from this site" is offered from a page's
    /// second alert, confirm or prompt on (B-116; Chrome's rule).
    public static func offersSuppression(dialogCount: Int) -> Bool {
        dialogCount >= 2
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
        /// The page's second alert, confirm or prompt or later since it last
        /// loaded: the dialog offers "Prevent additional dialogs from this site" (B-116).
        public let offersSuppression: Bool
        fileprivate let answer: (DialogResponse) -> Void
    }

    /// The checkbox's words (B-116).
    public static let suppressionTitle = "Prevent additional dialogs from this site"

    /// A permission prompt waiting for an answer.
    public struct PendingPermission {
        public let id: Int
        public let requests: [PermissionRequest]
        public let page: ObjectIdentifier
        fileprivate let answer: (PermissionResponse) -> Void
    }

    /// A password save or update offer waiting for an answer (5.8a).
    public struct PendingPasswordOffer {
        public let id: Int
        public let offer: PasswordOffer
        public let page: ObjectIdentifier
        fileprivate let answer: (PasswordOfferResponse) -> Void
    }

    /// The page in the card (`nil`: the empty state).
    public private(set) var currentPage: ObjectIdentifier?
    /// Called after anything that changes what is shown.
    public var onChange: (() -> Void)?
    /// A dialog arrived for a page not in the card (it waits there).
    public var onPageNeedsAttention: ((ObjectIdentifier) -> Void)?

    private var dialogs: [Pending] = []
    private var permissions: [PendingPermission] = []
    /// One per page: a later submit replaces the earlier offer (Chrome keeps one form manager per tab).
    private var passwordOffers: [PendingPasswordOffer] = []
    /// Alerts, confirms and prompts each page asked since it last started loading (B-116).
    private var dialogCounts: [ObjectIdentifier: Int] = [:]
    /// Pages whose further alerts, confirms and prompts are answered at once
    /// with their escape answer, unseen, until the page loads again (B-116).
    public private(set) var suppressedPages: Set<ObjectIdentifier> = []
    /// Dialogs answered unseen because their page was suppressed (spikes read it).
    public private(set) var suppressedCount = 0
    /// The pages whose loading is watched to end their count and suppression.
    private var watchedPages: Set<ObjectIdentifier> = []
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

    /// The password offer the popover shows now: the page in the card's,
    /// while no dialog or permission prompt is up (it waits behind them).
    public var visiblePasswordOffer: PendingPasswordOffer? {
        guard visibleDialog == nil, visiblePermission == nil else { return nil }
        return passwordOffers.first { $0.page == currentPage }
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
        var offersSuppression = false
        if dialog.isSuppressible {
            if suppressedPages.contains(pageID) {
                // Silenced until the page loads again: Chrome's answer to a suppressed dialog (OK for an alert, Cancel otherwise).
                // On the next turn, as a user's answer comes: the engine's dialog manager is still inside the
                // call that asked (an answer from within it left the page's later dialogs unshown, 5.6a's spike).
                suppressedCount += 1
                let response = PromptRules.escapeResponse(for: dialog)
                DispatchQueue.main.async { answer(response) }
                return id
            }
            let count = (dialogCounts[pageID] ?? 0) + 1
            dialogCounts[pageID] = count
            offersSuppression = PromptRules.offersSuppression(dialogCount: count)
            watchLoading(page)
        }
        dialogs.append(Pending(id: id, dialog: dialog, page: pageID, offersSuppression: offersSuppression, answer: answer))
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

    /// Queues the engine's password offer for `page` (5.8a). It shows when
    /// the page is in the card; a background page's offer waits there
    /// unmarked (Chrome's bubble waits for its tab the same way). An earlier
    /// offer of the same page is answered `.notNow` and replaced.
    @discardableResult
    public func offerPassword(_ offer: PasswordOffer, for page: any WebContents,
                              answer: @escaping (PasswordOfferResponse) -> Void) -> Int {
        let id = takeID()
        let pageID = ObjectIdentifier(page)
        let replaced = passwordOffers.filter { $0.page == pageID }
        passwordOffers.removeAll { $0.page == pageID }
        passwordOffers.append(PendingPasswordOffer(id: id, offer: offer, page: pageID, answer: answer))
        replaced.forEach { $0.answer(.notNow) }
        onChange?()
        return id
    }

    // MARK: Answering

    /// Answers the visible dialog (or the one with `id`). `suppressingFurther`:
    /// the dialog's "Prevent additional dialogs" was checked (B-116): the
    /// page's other waiting alerts, confirms and prompts are answered unseen
    /// too, and so is every later one until the page loads again.
    public func respond(_ response: DialogResponse, to id: Int? = nil, suppressingFurther: Bool = false) {
        guard let pending = id.flatMap({ id in dialogs.first { $0.id == id } }) ?? visibleDialog else { return }
        // Proceeding is refused when the error cannot be bypassed; the dialog stays.
        if response == .proceed, !PromptRules.allowsProceed(pending.dialog) { return }
        dialogs.removeAll { $0.id == pending.id }
        pending.answer(response)
        if suppressingFurther, pending.offersSuppression {
            suppressedPages.insert(pending.page)
            let silenced = dialogs.filter { $0.page == pending.page && $0.dialog.isSuppressible }
            dialogs.removeAll { $0.page == pending.page && $0.dialog.isSuppressible }
            suppressedCount += silenced.count
            silenced.forEach { $0.answer(PromptRules.escapeResponse(for: $0.dialog)) }
        }
        onChange?()
    }

    /// The page started loading (a reload, a navigation): its dialog count
    /// and its suppression end (B-116, Chrome's "until the page reloads").
    public func pageStartedLoading(_ page: ObjectIdentifier) {
        dialogCounts[page] = nil
        suppressedPages.remove(page)
    }

    /// Watches `page` until it starts loading again (`PageCrashes`' pattern).
    private func watchLoading(_ page: any WebContents) {
        let id = ObjectIdentifier(page)
        guard watchedPages.insert(id).inserted else { return }
        observeLoading(PageRef(page), id: id, wasLoading: page.isLoading)
    }

    private func observeLoading(_ ref: PageRef, id: ObjectIdentifier, wasLoading: Bool) {
        guard let page = ref.page else {
            watchedPages.remove(id)
            return pageStartedLoading(id)
        }
        withObservationTracking {
            _ = page.isLoading
        } onChange: { [weak self] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self else { return }
                guard let page = ref.page else {
                    self.watchedPages.remove(id)
                    return self.pageStartedLoading(id)
                }
                if !wasLoading {
                    // Not loading before the change: a load began (a reload, a navigation; it may already be over,
                    // as a fake engine's synchronous load). The count starts again; the page is watched again
                    // from its next dialog.
                    self.watchedPages.remove(id)
                    return self.pageStartedLoading(id)
                }
                self.observeLoading(ref, id: id, wasLoading: page.isLoading)
            }
        }
    }

    public func respondToPermission(_ response: PermissionResponse, to id: Int? = nil) {
        guard let pending = id.flatMap({ id in permissions.first { $0.id == id } }) ?? visiblePermission else { return }
        permissions.removeAll { $0.id == pending.id }
        pending.answer(response)
        onChange?()
    }

    /// Answers the visible password offer (or the one with `id`). An update
    /// offers no Never: answered so, it counts as Not Now.
    public func respondToPasswordOffer(_ response: PasswordOfferResponse, to id: Int? = nil) {
        guard let pending = id.flatMap({ id in passwordOffers.first { $0.id == id } }) ?? visiblePasswordOffer else { return }
        passwordOffers.removeAll { $0.id == pending.id }
        let allowed = response == .never && !PasswordOfferRules.offersNever(pending.offer.kind) ? .notNow : response
        pending.answer(allowed)
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

    /// The engine withdrew the page's password offer: it goes unanswered.
    public func engineWithdrewPasswordOffer(for page: any WebContents) {
        let id = ObjectIdentifier(page)
        let before = passwordOffers.count
        passwordOffers.removeAll { $0.page == id }
        if passwordOffers.count != before { onChange?() }
    }

    /// The page closed: everything it still waits for is answered with its
    /// escape answer (dismissed for permissions, not now for a password), once.
    public func pageClosed(_ page: any WebContents) {
        let id = ObjectIdentifier(page)
        // A later page at the same address starts with no count or suppression.
        pageStartedLoading(id)
        watchedPages.remove(id)
        let closedDialogs = dialogs.filter { $0.page == id }
        let closedPermissions = permissions.filter { $0.page == id }
        let closedOffers = passwordOffers.filter { $0.page == id }
        guard !closedDialogs.isEmpty || !closedPermissions.isEmpty || !closedOffers.isEmpty else { return }
        dialogs.removeAll { $0.page == id }
        permissions.removeAll { $0.page == id }
        passwordOffers.removeAll { $0.page == id }
        closedDialogs.forEach { $0.answer(PromptRules.escapeResponse(for: $0.dialog)) }
        closedPermissions.forEach { $0.answer(.dismissed) }
        closedOffers.forEach { $0.answer(.notNow) }
        if currentPage == id { currentPage = nil }
        onChange?()
    }

    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

/// Links to other applications (3.4b): the first link of a scheme in the
/// session asks (`PageDialog.externalApp`); once opened, that scheme opens
/// without asking until the app quits. A refusal asks again next time.
/// "Always open" across launches is Chapter 4's Settings.
public final class ExternalApps {
    public private(set) var allowedSchemes: Set<String> = []

    public init() {}

    public func isAllowed(_ scheme: String) -> Bool {
        allowedSchemes.contains(scheme.lowercased())
    }

    public func allow(_ scheme: String) {
        allowedSchemes.insert(scheme.lowercased())
    }
}
