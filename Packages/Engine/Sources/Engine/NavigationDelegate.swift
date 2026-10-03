import Foundation

/// Decides where each top-level navigation goes before it starts: space
/// routing, Peek, opening off-site links from pinned entries elsewhere.
@MainActor
public protocol NavigationDelegate: AnyObject {
    /// Return `action.disposition` to let the navigation proceed as requested,
    /// another disposition to redirect it, or `.ignore` to cancel it (and, for
    /// example, open the URL in another space yourself).
    func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition

    /// A main-frame navigation committed: the page now shows `url` (history
    /// recording, Phase 2.4). Also for same-document navigations (fragments,
    /// `pushState`), which the engine may report as `.link`. Not called for
    /// navigations that fail before committing or that the delegate cancelled.
    func webContents(_ webContents: any WebContents, didCommitNavigation url: URL, transition: PageTransition)
}

public extension NavigationDelegate {
    func webContents(_ webContents: any WebContents, didCommitNavigation url: URL, transition: PageTransition) {}
}

/// Where a navigation or new window should land. Chromium `WindowOpenDisposition`.
nonisolated public enum Disposition: Sendable, Hashable {
    /// Cancel the navigation.
    case ignore
    case currentTab
    case newForegroundTab
    case newBackgroundTab
    case newWindow
    /// A `window.open` with features (size, no toolbar).
    case newPopup
    case newPictureInPicture
    case saveToDisk
    case offTheRecord
}

/// A navigation about to start in a web contents' main frame.
nonisolated public struct NavigationAction: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case linkActivated
        case formSubmitted
        case backForward
        case reload
        /// Address field, script-initiated or anything else.
        case other
    }

    public var url: URL
    public var referrer: URL?
    public var kind: Kind
    public var transition: PageTransition
    /// What the page or the click asked for (⌘-click → `.newBackgroundTab`).
    public var disposition: Disposition
    public var isUserGesture: Bool
    public var isRedirect: Bool

    public init(
        url: URL,
        referrer: URL? = nil,
        kind: Kind,
        transition: PageTransition,
        disposition: Disposition = .currentTab,
        isUserGesture: Bool = false,
        isRedirect: Bool = false
    ) {
        self.url = url
        self.referrer = referrer
        self.kind = kind
        self.transition = transition
        self.disposition = disposition
        self.isUserGesture = isUserGesture
        self.isRedirect = isRedirect
    }
}
