import AppKit

/// SF Symbol for every control in the feature spec (sections A–I). One name
/// per control so a later icon pass changes one line.
public enum Symbol: CaseIterable, Sendable {
    // Window and navigation (§E, §G)
    case toggleSidebar
    case back
    case forward
    case reload
    case stop
    case more
    /// "Open in New Window" (4.8a).
    case newWindow

    // Address field and site panel (§C)
    case search
    case siteSecure
    case siteInsecure
    case siteInfo
    case copyURL
    case copyMarkdown
    case paste
    case commands
    case history
    case openURL

    // Sidebar rows (§A, §I)
    case newTab
    case closeTab
    case pin
    case unpin
    case essential
    case removeEssential
    case folder
    case folderOpen
    case newFolder
    case resetPinned
    case changedDot
    case rename
    case changeIcon
    case duplicate
    case unload
    case clearToday
    case disclosure
    case moveTo

    // Spaces (§B)
    case space
    case spaceInactive
    case newSpace
    case editTheme
    case profile
    case routing
    case deleteSpace
    /// Import from another browser (4.3a): the palette command and the summary toast.
    case importData

    // Footer, downloads, library (§F, §H)
    case downloads
    case downloadInProgress
    case library
    case archive
    case restore
    case showInFinder
    case cancel

    // Split view (§D)
    case newSplit
    case paneGrip
    case paneLayout
    case splitVertical
    case splitGrid
    case unsplit
    case dragGrip

    // Peek (§I.6)
    case peekExpand
    case peekSplit

    // Media (§F, §I.5)
    case audible
    case muted
    case play
    case pause
    case nextTrack
    case pictureInPicture

    // Page tools (§C, §G)
    case find
    case zoomIn
    case zoomOut
    case print
    case screenshot
    /// File ▸ Save Page… (4.7a).
    case savePage
    /// View ▸ Developer ▸ View Source (4.7a).
    case viewSource
    case readerMode
    case developerTools
    case share
    case extensions
    case settings
    /// Palette: Switch to Light/Dark/Auto Appearance (2.4b).
    case appearance

    // Permission prompts (§3.4 of the engine API, Chapter 2.6)
    case camera
    case microphone
    case location
    case notifications
    case clipboard

    // Toasts (§F)
    case success
    case undo
    case info

    // The page's state and tools in the card (Phase 2.6b)
    case pageCrashed
    /// The page's renderer stopped responding (3.4b).
    case pageUnresponsive
    /// The page shares a screen, a window or a tab (3.4b, the row's indicator).
    case screenSharing
    case findPrevious
    case findNext
    case dismiss
    case file

    /// The SF Symbols name.
    public var name: String {
        switch self {
        case .toggleSidebar: "sidebar.left"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reload: "arrow.clockwise"
        case .stop: "xmark"
        case .more: "ellipsis"
        case .newWindow: "macwindow.badge.plus"
        case .search: "magnifyingglass"
        case .siteSecure: "lock.fill"
        case .siteInsecure: "exclamationmark.triangle.fill"
        case .siteInfo: "slider.horizontal.3"
        case .copyURL: "link"
        case .copyMarkdown: "text.quote"
        case .paste: "doc.on.clipboard"
        case .commands: "command"
        case .history: "clock.arrow.circlepath"
        case .openURL: "globe"
        case .newTab: "plus"
        case .closeTab: "xmark"
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .essential: "star"
        case .removeEssential: "star.slash"
        case .folder: "folder"
        case .folderOpen: "folder.fill"
        case .newFolder: "folder.badge.plus"
        case .resetPinned: "arrow.uturn.backward"
        case .changedDot: "circle.fill"
        case .rename: "pencil"
        case .changeIcon: "face.smiling"
        case .duplicate: "plus.square.on.square"
        case .unload: "moon.zzz"
        case .clearToday: "xmark.circle"
        case .disclosure: "chevron.down"
        case .moveTo: "arrow.right.square"
        case .space: "circle.fill"
        case .spaceInactive: "circle"
        case .newSpace: "plus.rectangle.on.rectangle"
        case .editTheme: "paintpalette"
        case .profile: "person.crop.circle"
        case .routing: "arrow.triangle.branch"
        case .deleteSpace: "trash"
        case .importData: "square.and.arrow.down.on.square"
        case .downloads: "arrow.down.circle"
        case .downloadInProgress: "arrow.down.circle.dotted"
        case .library: "books.vertical"
        case .archive: "archivebox"
        case .restore: "arrow.uturn.up"
        case .showInFinder: "magnifyingglass.circle"
        case .cancel: "xmark.circle.fill"
        case .newSplit: "rectangle.split.2x1"
        case .paneGrip: "line.3.horizontal"
        case .paneLayout: "rectangle.split.2x2"
        case .splitVertical: "rectangle.split.1x2"
        case .splitGrid: "rectangle.split.2x2"
        case .unsplit: "rectangle"
        case .dragGrip: "line.3.horizontal"
        case .peekExpand: "arrow.up.left.and.arrow.down.right"
        case .peekSplit: "rectangle.righthalf.inset.filled"
        case .audible: "speaker.wave.2.fill"
        case .muted: "speaker.slash.fill"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .nextTrack: "forward.fill"
        case .pictureInPicture: "pip.enter"
        case .find: "text.magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .print: "printer"
        case .screenshot: "camera.viewfinder"
        case .savePage: "square.and.arrow.down"
        case .viewSource: "chevron.left.forwardslash.chevron.right"
        case .readerMode: "doc.plaintext"
        case .developerTools: "hammer"
        case .share: "square.and.arrow.up"
        case .extensions: "puzzlepiece.extension"
        case .settings: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .camera: "camera"
        case .microphone: "mic"
        case .location: "location"
        case .notifications: "bell"
        case .clipboard: "list.clipboard"
        case .success: "checkmark.circle.fill"
        case .undo: "arrow.uturn.backward.circle"
        case .info: "info.circle"
        case .pageCrashed: "exclamationmark.octagon"
        case .pageUnresponsive: "hourglass"
        case .screenSharing: "rectangle.inset.filled.and.person.filled"
        case .findPrevious: "chevron.up"
        case .findNext: "chevron.down"
        case .dismiss: "xmark.circle.fill"
        case .file: "doc"
        }
    }

    /// A template image for this symbol (vibrancy tints template images).
    public func image(pointSize: CGFloat = 13, weight: NSFont.Weight = .regular, accessibilityDescription: String? = nil) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        let image = base?.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        image?.isTemplate = true
        return image
    }
}
