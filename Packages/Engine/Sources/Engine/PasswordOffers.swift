import Foundation

/// The engine's offer to save or update a password a page just submitted
/// (Chrome's password manager, `ManagePasswordsUIController`'s pending
/// state; Phase 5.8a). It never carries the password itself.
nonisolated public struct PasswordOffer: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// No password is saved for this site and username (Chrome's save bubble).
        case save
        /// One is saved with another password (Chrome's update bubble).
        case update
    }

    public var kind: Kind
    /// The site the password is for: scheme, host and port (Chrome's signon realm).
    public var origin: URL
    /// The username the form submitted; empty when it had none.
    public var username: String
    /// The masked marker: one bullet per character of the password, at most
    /// `maskLimit` (`mask(length:)`).
    public var maskedPassword: String

    public init(kind: Kind, origin: URL, username: String, maskedPassword: String) {
        self.kind = kind
        self.origin = origin
        self.username = username
        self.maskedPassword = maskedPassword
    }

    /// The marker's longest run of bullets.
    public static let maskLimit = 12

    /// The marker for a password of `length` characters.
    public static func mask(length: Int) -> String {
        String(repeating: "•", count: min(max(length, 1), maskLimit))
    }
}

/// The host's answer to a `PasswordOffer`.
nonisolated public enum PasswordOfferResponse: Sendable, Hashable {
    /// Save (or, for an update, replace) the password.
    case save
    /// Never offer for this site again (Chrome's blocklist entry for the
    /// origin; removed from `chrome://password-manager`). Save offers only.
    case never
    /// Closed without saving (Not Now, Esc, a click elsewhere): Chrome may offer again.
    case notNow
}
