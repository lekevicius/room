import Engine
import Foundation

/// Chrome's password manager, reduced (5.8a): a submitted form offers to
/// save (or update) its password unless the site is on the never list or the
/// same password is saved; the delegate presents the offer or keeps the
/// engine's bubble; its answer reaches the profile's store.
public extension FakeWebContents {
    enum PasswordSubmitOutcome: Sendable, Equatable {
        /// The delegate presented the offer and answered.
        case answered(PasswordOffer.Kind, PasswordOfferResponse)
        /// The delegate did not present it: the engine's own bubble would show.
        case engineBubble(PasswordOffer.Kind)
        /// The engine withdrew the offer before an answer.
        case withdrawn
        /// Nothing was offered: the site is on the never list.
        case neverForSite
        /// Nothing was offered: this username has this password saved already.
        case alreadySaved
    }

    /// `scheme://host[:port]` of `url` (the store's site key).
    static func passwordSite(_ url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
    }

    /// The page's sign-in form was submitted with `username` and `password`.
    func simulatePasswordSubmit(username: String, password: String) async -> PasswordSubmitOutcome {
        guard let profile, let url, let site = Self.passwordSite(url), let origin = URL(string: site) else { return .neverForSite }
        if profile.neverSavePasswordSites.contains(site) { return .neverForSite }
        let saved = profile.savedPasswords.firstIndex { $0.site == site && $0.username == username }
        if let saved, profile.savedPasswords[saved].password == password { return .alreadySaved }
        let kind: PasswordOffer.Kind = saved == nil ? .save : .update
        let offer = PasswordOffer(kind: kind, origin: origin, username: username, maskedPassword: PasswordOffer.mask(length: password.count))
        let outcome: PasswordSubmitOutcome = await withCheckedContinuation { continuation in
            let resumed = ResumeOnce(continuation)
            pendingPasswordOffer = { resumed.resume($0) }
            let answer: (PasswordOfferResponse) -> Void = { [weak self] response in
                guard self?.pendingPasswordOffer != nil else { return }  // withdrawn: no longer called
                self?.pendingPasswordOffer = nil
                resumed.resume(.answered(kind, response))
            }
            let presented = switch kind {
            case .save: effectiveUIDelegate.webContents(self, willOfferPasswordSave: offer, completion: answer)
            case .update: effectiveUIDelegate.webContents(self, willOfferPasswordUpdate: offer, completion: answer)
            }
            if !presented {
                pendingPasswordOffer = nil
                resumed.resume(.engineBubble(kind))
            }
        }
        guard case .answered(_, let response) = outcome else { return outcome }
        switch response {
        case .save:
            if let saved {
                profile.savedPasswords[saved].password = password
            } else {
                profile.savedPasswords.append(FakeProfile.SavedPassword(site: site, username: username, password: password))
            }
        case .never where kind == .save:
            profile.neverSavePasswordSites.insert(site)
        case .never, .notNow:
            break
        }
        return outcome
    }

    /// The engine withdrew the pending offer (the page navigated): the
    /// delegate hears it and the submit returns `.withdrawn`.
    func simulatePasswordOfferWithdrawn() {
        guard let pending = pendingPasswordOffer else { return }
        pendingPasswordOffer = nil
        effectiveUIDelegate.webContentsDidWithdrawPasswordOffer(self)
        pending(.withdrawn)
    }

    /// The engine saved a generated password without asking (the saved
    /// confirmation); returns whether the delegate confirmed it.
    func simulateAutomaticPasswordSave(username: String, password: String) -> Bool {
        guard let profile, let url, let site = Self.passwordSite(url), let origin = URL(string: site) else { return false }
        profile.savedPasswords.append(FakeProfile.SavedPassword(site: site, username: username, password: password))
        let offer = PasswordOffer(kind: .save, origin: origin, username: username, maskedPassword: PasswordOffer.mask(length: password.count))
        return effectiveUIDelegate.webContents(self, didSavePassword: offer)
    }
}

/// Resumes a continuation the first time only.
@MainActor
private final class ResumeOnce {
    private var continuation: CheckedContinuation<FakeWebContents.PasswordSubmitOutcome, Never>?

    init(_ continuation: CheckedContinuation<FakeWebContents.PasswordSubmitOutcome, Never>) {
        self.continuation = continuation
    }

    func resume(_ outcome: FakeWebContents.PasswordSubmitOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
