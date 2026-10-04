import AppKit
import Engine
import RoomCore

/// `Profile` over a `RoomProfile` (Chromium `Profile` in
/// `<user data>/Room Profile <name>`). At the embryo's depth it creates pages
/// and stores the downloads delegate; the rest is `nil` or `notSupported`
/// (docs/engine-api.md, RoomCore column).
public final class RoomCoreProfile: Profile {
    public let name: String
    public weak var downloadsDelegate: (any DownloadsDelegate)?

    let profile: RoomProfile
    private let liveContents = NSHashTable<RoomCoreWebContents>.weakObjects()

    init(name: String, profile: RoomProfile) {
        self.name = name
        self.profile = profile
    }

    /// Pages of this profile that are not closed.
    public var webContents: [RoomCoreWebContents] { liveContents.allObjects.filter { $0.state != .closed } }

    public func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents {
        try makeWebContents(configuration)
    }

    public func makeWebContents(_ configuration: WebContentsConfiguration = WebContentsConfiguration()) throws -> RoomCoreWebContents {
        if RoomCoreApplication.current?.isTerminating == true { throw EngineError.notRunning }
        let contents = RoomCoreWebContents(page: profile.createWebContents(), configuration: configuration)
        liveContents.add(contents)
        return contents
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
