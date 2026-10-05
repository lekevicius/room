import Design
import Engine
import Foundation

/// Where a navigation of an entry's page goes (spec §A.4).
public enum PeekDecision: Equatable, Sendable {
    /// As the page asked (in place, or the engine's new-tab dispositions).
    case asRequested
    /// Cancelled here and opened in Peek over the page.
    case peek
}

/// Peek's off-site rule (spec §A.4, §I.6): a click on a link from a
/// permanent entry to another site (eTLD+1) opens in Peek; form posts,
/// redirect chains the site started, OAuth and login flows, and
/// `window.location` set by the page within 2 s of a user gesture navigate
/// in place, so logins never break. ⇧-click opens Peek from any page.
///
/// A click on a link is the engine's `NavigationAction.Kind.linkActivated`
/// (exact on RoomCore from the navigation throttle, B-33); a script
/// navigation is `.other` with a link transition.
public enum PeekRules {
    nonisolated public struct Context: Equatable, Sendable {
        /// The page belongs to an essential or a pinned entry.
        public var isPermanentEntry: Bool
        /// Settings ▸ "Open links to other sites from pinned tabs in Peek".
        public var isEnabled: Bool
        /// The page's committed URL: the site a click would leave.
        public var currentURL: URL?
        /// Since the last mouse or key press in the window; `nil` when unknown.
        public var secondsSinceUserInput: TimeInterval?

        public init(isPermanentEntry: Bool, isEnabled: Bool = true, currentURL: URL?, secondsSinceUserInput: TimeInterval? = nil) {
            self.isPermanentEntry = isPermanentEntry
            self.isEnabled = isEnabled
            self.currentURL = currentURL
            self.secondsSinceUserInput = secondsSinceUserInput
        }
    }

    /// `isSameSite` is the engine's (`EngineApplication.isSameSite`).
    public static func decision(for action: NavigationAction, context: Context, isSameSite: (URL, URL) -> Bool) -> PeekDecision {
        guard context.isEnabled, isWebURL(action.url) else { return .asRequested }
        // ⇧-click (Chrome's "new window" disposition) peeks from any page.
        if action.disposition == .newWindow, action.isUserGesture, action.kind == .linkActivated { return .peek }
        guard context.isPermanentEntry, action.disposition == .currentTab, action.isUserGesture, !action.isRedirect,
              !action.isClientRedirect, let current = context.currentURL, isWebURL(current), !isSameSite(action.url, current),
              !isLoginFlow(action.url) else { return .asRequested }
        switch action.kind {
        case .linkActivated:
            return .peek
        case .other where action.transition == .link:
            // The page's script set `window.location`. Within 2 s of a gesture
            // (or with no input seen at all) it navigates in place.
            guard let since = context.secondsSinceUserInput, since >= Timing.peekGestureWindow else { return .asRequested }
            return .peek
        default:
            return .asRequested
        }
    }

    /// OAuth authorisation requests and identity providers' sign-in pages.
    nonisolated public static func isLoginFlow(_ url: URL) -> Bool {
        let names = Set((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { $0.name.lowercased() })
        if names.contains("client_id"), names.contains("redirect_uri") || names.contains("response_type") { return true }
        if names.contains("samlrequest") || names.contains("openid.mode") { return true }
        let components = Set(url.pathComponents.map { $0.lowercased() })
        return !components.isDisjoint(with: ["oauth", "oauth2", "authorize", "openid", "saml", "sso", "signin", "login", "servicelogin"])
    }

    nonisolated private static func isWebURL(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
