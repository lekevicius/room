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
    /// Differentiate Without Colour (5.3b): the audible and muted glyphs inside a circle (`AudioGlyph`).
    case audibleShape
    case mutedShape
    case play
    case pause
    case nextTrack
    case pictureInPicture
    /// Document picture-in-picture's back to tab (B-107).
    case pictureInPictureExit

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
    /// The password save and update popover and its confirmation (5.8a).
    case password

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
        case .siteInfo: "slider.horizontal.2.square"
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
        case .audibleShape: "speaker.wave.2.circle.fill"
        case .mutedShape: "speaker.slash.circle.fill"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .nextTrack: "forward.fill"
        case .pictureInPicture: "pip.enter"
        case .pictureInPictureExit: "pip.exit"
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
        case .password: "key.fill"
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

    /// A template image for this symbol in `style` (vibrancy tints template images).
    public func image(_ style: IconStyle = .menu, accessibilityDescription: String? = nil) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        let image = base?.withSymbolConfiguration(style.configuration)
        image?.isTemplate = true
        return image
    }
}

/// The icon-weights table (5.2a): every SF Symbol the chrome draws takes its
/// point size and weight from one of these roles (`Symbol.image(_:)`, or
/// `configuration` for a symbol a person picked, a space's icon), so one line
/// changes a role everywhere. `docs/design-tokens.md` "Icon weights" lists them.
public enum IconStyle: String, CaseIterable, Sendable {
    /// Menu items and list icons (AppKit's own menu glyph size).
    case menu
    /// The one control metric's glyph (B-110): the top bar's buttons, the
    /// site button, the extensions' overflow, the footer's downloads and New
    /// Tab, Peek's header (the Room Browser design: SF Pro 13).
    case control
    /// Smaller controls inside a field or panel: Copy URL, the zoom buttons,
    /// the find bar's search glyph, an extension action without an icon.
    case controlSmall
    /// A split pane's header (24 pt) buttons and grip.
    case paneControl
    /// The find bar's previous, next and done.
    case findButton
    /// The Library's section chevrons.
    case disclosure
    /// A row's × and audio buttons (24 pt hover squares).
    case rowButton
    /// A row's reset button, the space title's "…", the reader and capture indicators.
    case rowAction
    /// The space title's and a folder's collapse chevron.
    case rowChevron
    /// The New Tab row's "+".
    case rowGlyph
    /// A folder row's glyph (B-115: Finder's and Notes' sidebar folder: larger than a favicon, regular weight).
    case folder
    /// A space's SF Symbol beside its title.
    case spaceTitle
    /// A space's SF Symbol in the footer.
    case spaceIcon
    /// The dot of a space without an icon.
    case spaceDot
    /// An Essentials tile's reset glyph.
    case tileReset
    /// An Essentials tile's audio badge.
    case tileBadge
    /// The media row's buttons and its placeholder glyph.
    case media
    /// The downloads button's arrow inside the progress ring.
    case downloadProgress
    /// The palette field's search glyph.
    case paletteField
    /// A palette row's symbol (commands, the URL row).
    case paletteRow
    /// A palette row's ×.
    case paletteDelete
    /// The certificate interstitial's and the crashed page's symbol.
    case interstitial

    public var pointSize: CGFloat {
        switch self {
        case .menu, .control, .tileReset, .paletteRow: 13
        case .controlSmall, .rowGlyph, .spaceTitle, .spaceIcon: 12
        case .paneControl, .findButton, .disclosure, .rowAction, .media, .downloadProgress: 11
        case .rowButton, .paletteDelete: 10
        case .rowChevron: 9
        case .folder: 15
        case .tileBadge: 8
        case .spaceDot: SpaceIconMetrics.dotSize
        case .paletteField: 15
        case .interstitial: PromptMetrics.interstitialIconSize
        }
    }

    public var weight: NSFont.Weight {
        switch self {
        case .menu, .control, .controlSmall, .paneControl, .rowGlyph, .folder, .spaceDot, .media, .downloadProgress,
             .paletteField, .paletteRow, .interstitial: .regular
        case .rowButton, .rowAction, .rowChevron, .spaceIcon, .tileReset: .medium
        case .findButton, .disclosure, .spaceTitle, .tileBadge, .paletteDelete: .semibold
        }
    }

    /// The symbol configuration for this role.
    public var configuration: NSImage.SymbolConfiguration { NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight) }
}
