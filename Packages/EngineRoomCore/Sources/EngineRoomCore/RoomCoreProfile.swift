import AppKit
import Engine
import RoomCore

/// `Profile` over a `RoomProfile` (Chromium `Profile` in
/// `<user data>/Room Profile <name>`). It creates pages, binds each to the
/// Chrome `Browser` of its host window (one `RoomBrowser` per window and
/// profile, 3.2a: a Chrome `Browser` holds one profile's tabs, and a Room
/// window shows several profiles' spaces) and stores the downloads delegate;
/// the rest is `nil` or `notSupported` (docs/engine-api.md, RoomCore column).
public final class RoomCoreProfile: NSObject, Profile, RoomBrowserDelegate {
    public let name: String
    public weak var downloadsDelegate: (any DownloadsDelegate)?

    let profile: RoomProfile
    private let liveContents = NSHashTable<RoomCoreWebContents>.weakObjects()
    /// The Chrome `Browser` of each host window, created with the window's
    /// first page and gone when its last page leaves (Chromium closes a
    /// `Browser` whose tab strip empties; the next page makes a new one).
    private var browsers: [(window: Weak<NSWindow>, browser: RoomBrowser)] = []

    init(name: String, profile: RoomProfile) {
        self.name = name
        self.profile = profile
        super.init()
    }

    /// Pages of this profile that are not closed.
    public var webContents: [RoomCoreWebContents] { liveContents.allObjects.filter { $0.state != .closed } }

    public func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents {
        try makeWebContents(configuration)
    }

    public func makeWebContents(_ configuration: WebContentsConfiguration = WebContentsConfiguration()) throws -> RoomCoreWebContents {
        if RoomCoreApplication.current?.isTerminating == true { throw EngineError.notRunning }
        let page = profile.createWebContents()
        let contents = RoomCoreWebContents(page: page, configuration: configuration, profile: self)
        liveContents.add(contents)
        // Into the window's tab strip at once (add on create); the strip's
        // active tab follows the page the host shows (RoomCore watches the
        // page's visibility and focus), never the order.
        if let window = configuration.hostWindow {
            browser(for: window).add(page, activate: false)
        }
        return contents
    }

    /// A page Chromium opened from one of this profile's pages; it is already
    /// in the opener's `Browser`.
    func adoptOpened(_ page: RoomWebContents, configuration: WebContentsConfiguration) -> RoomCoreWebContents {
        let contents = RoomCoreWebContents(page: page, configuration: configuration, profile: self)
        liveContents.add(contents)
        return contents
    }

    /// The window's `RoomBrowser` for this profile, made on first use.
    func browser(for window: NSWindow) -> RoomBrowser {
        browsers.removeAll { $0.window.object == nil || $0.browser.isClosed }
        if let existing = browsers.first(where: { $0.window.object === window }) { return existing.browser }
        let browser = RoomBrowser(profile: profile, window: window)
        browser.delegate = self
        browsers.append((Weak(window), browser))
        return browser
    }

    // MARK: RoomBrowserDelegate

    public func browserDidClose(_ browser: RoomBrowser) {
        browsers.removeAll { $0.browser === browser }
    }

    func closeAll() {
        for contents in liveContents.allObjects { contents.close() }
    }

    // Downloads (3.4a): RoomCore does not report downloads yet.
    public func pauseDownload(id: DownloadItem.ID) {}
    public func resumeDownload(id: DownloadItem.ID) {}
    public func cancelDownload(id: DownloadItem.ID) {}

    public func favicon(for pageURL: URL) async -> NSImage? { nil }

    public func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws {
        throw EngineError.notSupported("RoomCoreProfile.clearSiteData")
    }

    public func permissionSetting(_ permission: SitePermission, for origin: URL) -> PermissionSetting? { nil }
    public func setPermissionSetting(_ setting: PermissionSetting?, for permission: SitePermission, origin: URL) {}

    public var history: (any ProfileHistory)? { nil }
    public var bookmarks: (any ProfileBookmarks)? { nil }
    public var extensions: (any ProfileExtensions)? { nil }
    public func makeAutocompleteController() -> (any AutocompleteController)? { nil }
}

/// A weak reference in a collection.
struct Weak<Object: AnyObject> {
    weak var object: Object?
    init(_ object: Object) { self.object = object }
}
