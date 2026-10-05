import AppKit
import Engine

public final class FakeProfile: Profile {
    public let name: String
    public weak var downloadsDelegate: (any DownloadsDelegate)?

    /// Pages created in this profile and not yet closed.
    public private(set) var openWebContents: [FakeWebContents] = []
    public private(set) var downloads: [DownloadItem.ID: DownloadItem] = [:]
    /// Favicons `favicon(for:)` returns, keyed by page URL.
    public var storedFavicons: [URL: NSImage] = [:]
    /// Every `clearSiteData` call, in order.
    public private(set) var clearedSiteData: [(types: SiteDataTypes, origin: URL?)] = []
    /// What `lastExitWasClean` reports (a test sets it before the host reads it).
    public var lastExitWasClean: Bool? = true

    private var nextDownloadID = 1

    init(name: String) {
        self.name = name
    }

    public func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents {
        makeWebContents(configuration)
    }

    /// `createWebContents` returning the concrete type.
    public func makeWebContents(_ configuration: WebContentsConfiguration = WebContentsConfiguration()) -> FakeWebContents {
        let contents = FakeWebContents(profile: self, configuration: configuration)
        openWebContents.append(contents)
        return contents
    }

    func didClose(_ contents: FakeWebContents) {
        openWebContents.removeAll { $0 === contents }
    }

    // MARK: Downloads

    /// Starts a download as if a page had triggered it. The delegate picks the
    /// destination; without a delegate the download is cancelled.
    @discardableResult
    public func simulateDownload(url: URL, suggestedFilename: String? = nil, totalBytes: Int64? = nil) -> DownloadItem.ID {
        let id = "fake-download-\(nextDownloadID)"
        nextDownloadID += 1
        let item = DownloadItem(
            id: id,
            url: url,
            suggestedFilename: suggestedFilename ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent),
            totalBytes: totalBytes
        )
        downloads[id] = item
        guard let delegate = downloadsDelegate else {
            update(id) { $0.state = .cancelled }
            return id
        }
        delegate.profile(self, willBeginDownload: item) { [weak self] destination in
            self?.update(id) { item in
                if let destination {
                    item.destination = destination
                } else {
                    item.state = .cancelled
                }
            }
        }
        return id
    }

    /// Receives `bytes` more; completes the download when the total is reached.
    public func advanceDownload(id: DownloadItem.ID, by bytes: Int64) {
        update(id) { item in
            guard item.state == .inProgress, !item.isPaused, item.destination != nil else { return }
            item.receivedBytes += bytes
            item.currentSpeed = bytes
            if let total = item.totalBytes, item.receivedBytes >= total {
                item.receivedBytes = total
                item.currentSpeed = 0
                item.state = .complete
            }
        }
    }

    /// Fails an in-progress download as a network error would.
    public func interruptDownload(id: DownloadItem.ID) {
        update(id) { item in
            guard item.state == .inProgress else { return }
            item.state = .interrupted
            item.canResume = true
            item.currentSpeed = 0
        }
    }

    public func pauseDownload(id: DownloadItem.ID) {
        update(id) { item in
            guard item.state == .inProgress else { return }
            item.isPaused = true
            item.canResume = true
            item.currentSpeed = 0
        }
    }

    public func resumeDownload(id: DownloadItem.ID) {
        update(id) { item in
            guard item.canResume, item.state == .inProgress || item.state == .interrupted else { return }
            item.state = .inProgress
            item.isPaused = false
            item.canResume = false
        }
    }

    public func cancelDownload(id: DownloadItem.ID) {
        update(id) { item in
            guard item.state == .inProgress || item.state == .interrupted else { return }
            item.state = .cancelled
            item.isPaused = false
            item.canResume = false
            item.currentSpeed = 0
        }
    }

    private func update(_ id: DownloadItem.ID, _ change: (inout DownloadItem) -> Void) {
        guard var item = downloads[id] else { return }
        let before = item
        change(&item)
        guard item != before else { return }
        downloads[id] = item
        downloadsDelegate?.profile(self, didUpdateDownload: item)
    }

    // MARK: Site data

    public func favicon(for pageURL: URL) async -> NSImage? {
        storedFavicons[pageURL]
    }

    public func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws {
        clearedSiteData.append((types, origin))
    }

    /// Stored site permissions, keyed by origin (`scheme://host[:port]`).
    public private(set) var permissionSettings: [String: [SitePermission: PermissionSetting]] = [:]

    public func permissionSetting(_ permission: SitePermission, for origin: URL) -> PermissionSetting? {
        permissionSettings[Self.originKey(origin)]?[permission]
    }

    public func setPermissionSetting(_ setting: PermissionSetting?, for permission: SitePermission, origin: URL) {
        permissionSettings[Self.originKey(origin), default: [:]][permission] = setting
    }

    static func originKey(_ url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host() ?? "")" + (url.port.map { ":\($0)" } ?? "")
    }

    // MARK: History and autocomplete (Phase 3.5), opt-in

    /// `history` when set: a test that wants the engine's history sets one
    /// (the Chapter 2 path runs without it, as on CEF).
    public var fakeHistory: FakeHistory?
    /// `makeAutocompleteController()` makes a `FakeAutocompleteController`
    /// over `fakeHistory` when set (and `fakeHistory` exists).
    public var providesAutocomplete = false
    /// The controllers handed out, in order.
    public private(set) var autocompleteControllers: [FakeAutocompleteController] = []
    /// What `setDefaultSearchEngine` received, in order.
    public private(set) var defaultSearchEngines: [SearchEngineTemplate] = []

    public var history: (any ProfileHistory)? { fakeHistory }

    public func makeAutocompleteController() -> (any AutocompleteController)? {
        guard providesAutocomplete, let fakeHistory else { return nil }
        let controller = FakeAutocompleteController(history: fakeHistory)
        autocompleteControllers.append(controller)
        return controller
    }

    public func setDefaultSearchEngine(_ engine: SearchEngineTemplate) {
        defaultSearchEngines.append(engine)
    }

    // MARK: Capabilities the fake does not provide

    public var bookmarks: (any ProfileBookmarks)? { nil }

    // MARK: Extensions (Phase 3.6a), opt-in

    /// `extensions` when set (CEF has none; a test that wants them sets one).
    public var fakeExtensions: FakeProfileExtensions?
    public var extensions: (any ProfileExtensions)? { fakeExtensions }
}
