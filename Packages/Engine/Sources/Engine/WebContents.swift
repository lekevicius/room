import AppKit
import Observation

/// One tab's page: a renderer, its navigation history and a native view.
/// Chromium `content::WebContents` plus tab helpers; CEF `CefBrowser`.
///
/// Conforming types are `@Observable`: the page-state properties below change
/// as the page loads and SwiftUI/AppKit observers track them directly.
@MainActor
public protocol WebContents: AnyObject, Observable {
    /// The view that renders the page. The host adds it to its card and sizes it.
    var nativeView: NSView { get }

    var uiDelegate: (any WebContentsUIDelegate)? { get set }
    var navigationDelegate: (any NavigationDelegate)? { get set }

    // MARK: Navigation

    /// Navigates the main frame. `fromAddressBar` marks a navigation the user
    /// typed or picked in the address field (Chromium's FROM_ADDRESS_BAR qualifier).
    func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool)
    func goBack()
    func goForward()
    func reload()
    func reloadIgnoringCache()
    func stop()

    // MARK: Observable page state

    var title: String? { get }
    /// The visible URL (the last committed one, or the pending one while loading
    /// a typed URL).
    var url: URL? { get }
    var favicon: NSImage? { get }
    var isLoading: Bool { get }
    /// 0...1 while loading; 1 when idle.
    var loadProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// `<meta name="theme-color">`, if any.
    var themeColor: NSColor? { get }
    /// The page's root background; the card fills with it during resize.
    var rootBackgroundColor: NSColor? { get }
    var securityState: SecurityState { get }
    var isAudible: Bool { get }
    var isMuted: Bool { get set }
    var state: WebContentsState { get }
    /// Page zoom; 1 is 100%.
    var zoomFactor: Double { get set }

    // MARK: Find in page

    /// Starts or continues a find. Results arrive in `findResult`.
    func find(_ text: String, forward: Bool, matchCase: Bool)
    func stopFind(clearSelection: Bool)
    /// The latest result of the active find; `nil` when no find is active.
    var findResult: FindResult? { get }

    // MARK: Lifecycle

    /// Releases the renderer but keeps the URL and title; the next `reload` or
    /// `load` brings the page back. `state` becomes `.discarded`.
    func discard() throws
    /// Closes the page, running its beforeunload/unload handlers. The UI
    /// delegate's `webContentsDidClose` fires once it is gone.
    func close()

    // MARK: Tools

    /// A snapshot of the visible viewport.
    func captureViewport() async throws -> NSImage
    /// DevTools for this page, or `nil` if the engine cannot host it.
    var devTools: (any DevTools)? { get }
    /// Evaluates `script` in the main frame and returns the result as JSON.
    func executeJavaScript(_ script: String) async throws -> String
    /// Opens the print dialog (or print preview, where the engine has it).
    func print()
    /// Leaves element fullscreen (`requestFullscreen()`); the UI delegate
    /// then hears `webContentsDidRequestExitFullscreen`. No-op otherwise.
    func exitFullscreen()
}

public extension WebContents {
    func load(_ url: URL) {
        load(url, transition: .typed, fromAddressBar: false)
    }

    func find(_ text: String) {
        find(text, forward: true, matchCase: false)
    }
}

/// DevTools for one page, rendered into a view the host provides and sizes.
@MainActor
public protocol DevTools: AnyObject {
    var isOpen: Bool { get }
    /// Shows DevTools filling `hostView`. A second call moves it to the new host.
    func open(in hostView: NSView)
    /// Opens DevTools if needed and selects the element at `point` (in the
    /// web contents' `nativeView` coordinates).
    func inspectElement(at point: NSPoint, in hostView: NSView)
    func close()
}

/// Options for `Profile.createWebContents`.
nonisolated public struct WebContentsConfiguration: Sendable, Hashable {
    /// Start hidden (no compositing, timers throttled) until the view is shown.
    public var initiallyHidden: Bool
    /// Let the window material show where the page paints no background.
    public var transparentBackground: Bool
    public var initiallyMuted: Bool
    public var disallowAutoplay: Bool

    public init(
        initiallyHidden: Bool = false,
        transparentBackground: Bool = false,
        initiallyMuted: Bool = false,
        disallowAutoplay: Bool = false
    ) {
        self.initiallyHidden = initiallyHidden
        self.transparentBackground = transparentBackground
        self.initiallyMuted = initiallyMuted
        self.disallowAutoplay = disallowAutoplay
    }
}

/// Lifecycle state of a page's renderer.
nonisolated public enum WebContentsState: Sendable, Hashable {
    case alive
    /// Renderer released; reloads on next navigation.
    case discarded
    /// Renderer kept but its tasks paused.
    case frozen
    /// `close()` completed; the object is inert.
    case closed
}

/// How a navigation was started; feeds history ranking and omnibox scoring.
nonisolated public enum PageTransition: Sendable, Hashable {
    case link
    /// Typed or picked in the address field.
    case typed
    /// Opened from a pinned entry or bookmark.
    case bookmark
    /// A search the address field generated from typed text.
    case generated
    /// A site-search keyword.
    case keyword
    case formSubmit
    case reload
    case other
}

/// Result of a find-in-page request.
nonisolated public struct FindResult: Sendable, Hashable {
    public var matchCount: Int
    /// 1-based index of the highlighted match; 0 when there is none.
    public var activeMatch: Int
    /// `false` while the engine is still counting matches.
    public var isFinal: Bool

    public init(matchCount: Int, activeMatch: Int, isFinal: Bool) {
        self.matchCount = matchCount
        self.activeMatch = activeMatch
        self.isFinal = isFinal
    }
}

/// Connection security of the visible page.
nonisolated public struct SecurityState: Sendable, Hashable {
    public enum Level: Sendable, Hashable {
        /// No security indicator (about:, file:, chrome:, new pages).
        case none
        case secure
        /// Plain HTTP.
        case insecure
        /// A certificate error the user clicked through, or Safe Browsing hit.
        case dangerous
    }

    public var level: Level
    /// Passive mixed content (HTTP images on an HTTPS page).
    public var hasMixedContent: Bool

    public init(level: Level, hasMixedContent: Bool = false) {
        self.level = level
        self.hasMixedContent = hasMixedContent
    }

    public static let none = SecurityState(level: .none)
}
