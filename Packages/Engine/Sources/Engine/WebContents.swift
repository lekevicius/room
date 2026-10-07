import AppKit
import Observation

/// One tab's page: a renderer, its navigation history and a native view.
/// Chromium `content::WebContents` plus tab helpers.
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
    /// What the page captures now (camera, microphone, a screen) and whether
    /// it is captured itself; the delegate hears each change.
    var captureState: CaptureState { get }
    /// The page's media session (title, artist, artwork, playback), if any.
    var mediaSession: MediaSessionInfo? { get }

    // MARK: Find in page

    /// Starts or continues a find. Results arrive in `findResult`.
    func find(_ text: String, forward: Bool, matchCase: Bool)
    func stopFind(clearSelection: Bool)
    /// The latest result of the active find; `nil` when no find is active.
    var findResult: FindResult? { get }

    // MARK: Lifecycle

    /// The page's back/forward list and current entry as opaque data the host
    /// stores and hands back in `WebContentsConfiguration.restoredNavigationState`
    /// (relaunch, crash recovery, an unloaded entry coming back); `nil` when
    /// there is nothing to save or the engine cannot serialise it. The
    /// navigation delegate hears `webContentsDidChangeNavigationState` when it
    /// changes. Written by one engine version; another may not read it.
    var navigationState: Data? { get }
    /// Why the engine would keep the page now (a form with unsaved input,
    /// Picture-in-Picture, sound, a capture…); empty when nothing blocks a
    /// discard. Asked by the host's discard policy before `discard()`.
    var discardBlockers: DiscardBlockers { get }
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
    /// Ends the page's captures of `kinds`; `captureState` follows.
    func stopCapturing(_ kinds: CaptureKinds)

    // MARK: Media session controls (4.6)

    /// Resumes the media session as the system's play key would: the page's
    /// "play" action handler when it has one, else its players.
    func mediaPlay()
    /// Pauses it (the page's "pause" handler, else its players).
    func mediaPause()
    /// The page's "nexttrack" handler (nothing without one).
    func mediaNextTrack()
    /// The page's "previoustrack" handler (nothing without one).
    func mediaPreviousTrack()
    /// The page's "seekto" handler, else its players seek.
    func mediaSeek(to seconds: TimeInterval)

    // MARK: Documents (4.7a)

    /// Saves the page to `url` (a file URL) in `format`; returns once the
    /// file is written. `.completeHTML` also writes the page's resources into
    /// "<name>_files" beside it. Throws when the page cannot be saved.
    func savePage(as format: SavePageFormat, to url: URL) async throws
    /// Sends one DevTools protocol command to the page and returns its
    /// `result` object (JSON values: `String`, `NSNumber`, arrays,
    /// dictionaries, `NSNull`). Bounded to the host's own commands (the
    /// full-page capture); throws the protocol's error, or when the engine
    /// cannot attach.
    func sendDevToolsCommand(_ method: String, params: [String: Any]) async throws -> [String: Any]

    // MARK: Windows (4.8b)

    /// Moves the page into `window` (another host window showing it now)
    /// with its back/forward list, renderer and state: RoomCore moves it
    /// from its window's `RoomBrowser` into `window`'s for the page's profile
    /// (Chromium's tab drag between windows, `TabStripModel::
    /// DetachTabAtForInsertion` then `InsertDetachedTabAt`); pages it opens
    /// from now on open in `window`. `nativeView` stays the same view: the
    /// host moves it into `window`'s card. The host never asks while the page
    /// shows in a Peek or a picture-in-picture panel. Throws
    /// `EngineError.closed` for a closed page.
    func move(toHostWindow window: NSWindow) throws
}

public extension WebContents {
    func load(_ url: URL) {
        load(url, transition: .typed, fromAddressBar: false)
    }

    func find(_ text: String) {
        find(text, forward: true, matchCase: false)
    }
}

/// What `WebContents.savePage(as:to:)` writes.
nonisolated public enum SavePageFormat: String, Sendable, Hashable, CaseIterable {
    /// The page's HTML only.
    case html
    /// The HTML and its resources in "<name>_files" beside it.
    case completeHTML
    /// One MHTML web archive.
    case mhtml

    /// The file name extension for the format.
    public var fileExtension: String {
        switch self {
        case .html, .completeHTML: "html"
        case .mhtml: "mhtml"
        }
    }

    /// The resources directory `.completeHTML` writes beside `file`
    /// ("Page.html" → "Page_files"); `nil` for the others.
    public func resourcesDirectory(for file: URL) -> URL? {
        guard self == .completeHTML else { return nil }
        return file.deletingPathExtension().deletingLastPathComponent()
            .appending(path: file.deletingPathExtension().lastPathComponent + "_files", directoryHint: .isDirectory)
    }
}

/// DevTools for one page, rendered into a view the host provides and sizes.
@MainActor
public protocol DevTools: AnyObject {
    var isOpen: Bool { get }
    /// `false` when the engine can show DevTools only in a window of its own:
    /// the host view is then unused.
    var isDockable: Bool { get }
    /// Shows DevTools filling `hostView`. A second call moves it to the new host.
    func open(in hostView: NSView)
    /// Opens DevTools if needed on a tool: the console (⌥⌘J) or the element picker (⌥⌘C).
    func open(in hostView: NSView, tool: DevToolsTool)
    /// Opens DevTools if needed and selects the element at `point` (in the
    /// web contents' `nativeView` coordinates).
    func inspectElement(at point: NSPoint, in hostView: NSView)
    func close()
}

/// What ⌥⌘J and ⌥⌘C open DevTools on.
nonisolated public enum DevToolsTool: Sendable, Hashable {
    case console
    /// Pick an element on the page to inspect.
    case elementPicker
}

/// Options for `Profile.createWebContents`.
nonisolated public struct WebContentsConfiguration: Sendable, Hashable {
    /// Start hidden (no compositing, timers throttled) until the view is shown.
    public var initiallyHidden: Bool
    /// Let the window material show where the page paints no background.
    public var transparentBackground: Bool
    public var initiallyMuted: Bool
    public var disallowAutoplay: Bool
    /// The window whose card will show the page. RoomCore binds the page to
    /// that window's Chrome `Browser` (one per window and profile; its tab
    /// strip mirrors the window's loaded pages, and the pages it opens arrive
    /// there too); an engine without browser objects ignores it. Read at
    /// creation only: moving a page to another window is Chapter 4.8.
    public weak var hostWindow: NSWindow?
    /// A `WebContents.navigationState` saved earlier: the page starts with
    /// that back/forward list, its `url`, `title` and `canGoBack` reading the
    /// restored current entry, and loads it on its first `reload()` (a
    /// `load(_:)` instead navigates onward with the list behind it). Ignored
    /// when the engine cannot read it (the page then starts empty, as without
    /// it).
    public var restoredNavigationState: Data?

    public init(
        initiallyHidden: Bool = false,
        transparentBackground: Bool = false,
        initiallyMuted: Bool = false,
        disallowAutoplay: Bool = false,
        hostWindow: NSWindow? = nil,
        restoredNavigationState: Data? = nil
    ) {
        self.initiallyHidden = initiallyHidden
        self.transparentBackground = transparentBackground
        self.initiallyMuted = initiallyMuted
        self.disallowAutoplay = disallowAutoplay
        self.hostWindow = hostWindow
        self.restoredNavigationState = restoredNavigationState
    }

    // The window by identity.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.initiallyHidden == rhs.initiallyHidden && lhs.transparentBackground == rhs.transparentBackground
            && lhs.initiallyMuted == rhs.initiallyMuted && lhs.disallowAutoplay == rhs.disallowAutoplay
            && lhs.hostWindow === rhs.hostWindow && lhs.restoredNavigationState == rhs.restoredNavigationState
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(initiallyHidden)
        hasher.combine(transparentBackground)
        hasher.combine(initiallyMuted)
        hasher.combine(disallowAutoplay)
        hasher.combine(hostWindow.map(ObjectIdentifier.init))
        hasher.combine(restoredNavigationState)
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

/// Why the engine would not discard a page now (Chromium's
/// performance_manager `CannotDiscardReason`s; spec §H, §A.7: a page with
/// unsaved form input, in Picture-in-Picture or playing audio is never
/// discarded). Visibility is the host's own rule and never appears here.
nonisolated public struct DiscardBlockers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// The user typed into a form on the page.
    public static let formInteractions = DiscardBlockers(rawValue: 1 << 0)
    /// Other edits (a text area, `contenteditable`).
    public static let userEdits = DiscardBlockers(rawValue: 1 << 1)
    public static let pictureInPicture = DiscardBlockers(rawValue: 1 << 2)
    public static let audible = DiscardBlockers(rawValue: 1 << 3)
    /// Played sound in the last minute.
    public static let recentlyAudible = DiscardBlockers(rawValue: 1 << 4)
    /// Camera, microphone, a window or the screen, or being mirrored.
    public static let capturing = DiscardBlockers(rawValue: 1 << 5)
    /// The page may show notifications.
    public static let notifications = DiscardBlockers(rawValue: 1 << 6)
    public static let devTools = DiscardBlockers(rawValue: 1 << 7)
    /// A USB or Bluetooth device.
    public static let connectedDevice = DiscardBlockers(rawValue: 1 << 8)
    /// Anything else the engine protects (a PDF, a non-web page).
    public static let other = DiscardBlockers(rawValue: 1 << 9)

    /// Names for logs and spike output.
    public var names: [String] {
        let all: [(DiscardBlockers, String)] = [
            (.formInteractions, "formInteractions"), (.userEdits, "userEdits"), (.pictureInPicture, "pictureInPicture"),
            (.audible, "audible"), (.recentlyAudible, "recentlyAudible"), (.capturing, "capturing"),
            (.notifications, "notifications"), (.devTools, "devTools"), (.connectedDevice, "connectedDevice"), (.other, "other"),
        ]
        return all.filter { contains($0.0) }.map(\.1)
    }
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
