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

    /// The profile is another's off-the-record twin (`offTheRecord()`).
    public let isOffTheRecord: Bool
    /// The twin `offTheRecord()` made and `closeOffTheRecord()` ended.
    public private(set) var offTheRecordTwin: FakeProfile?
    /// Set by `closeOffTheRecord()` on the twin it ended.
    public private(set) var isClosed = false
    /// Cookies by host (`setCookie`): in memory, per profile, as an engine
    /// keeps a twin's apart from its parent's.
    public private(set) var cookies: [String: [String: String]] = [:]
    /// Makes `offTheRecord()` throw `profileInUse` (the previous twin still
    /// closing, as RoomCore can report).
    public var offTheRecordUnavailable = false

    init(name: String, isOffTheRecord: Bool = false) {
        self.name = name
        self.isOffTheRecord = isOffTheRecord
    }

    // MARK: Off the record (4.8b)

    public func offTheRecord() throws -> any Profile {
        guard !isOffTheRecord else { throw EngineError.notSupported("offTheRecord of an off-the-record profile") }
        guard !offTheRecordUnavailable else { throw EngineError.profileInUse("the previous twin is closing") }
        return makeOffTheRecord()
    }

    /// `offTheRecord()` returning the concrete type.
    public func makeOffTheRecord() -> FakeProfile {
        if let offTheRecordTwin { return offTheRecordTwin }
        let twin = FakeProfile(name: name, isOffTheRecord: true)
        offTheRecordTwin = twin
        return twin
    }

    /// The twin's pages close and its cookies go with it.
    public func closeOffTheRecord() {
        guard let twin = offTheRecordTwin else { return }
        offTheRecordTwin = nil
        for page in twin.openWebContents { page.closeNow() }
        twin.cookies = [:]
        twin.isClosed = true
    }

    /// A page of `host` set a cookie.
    public func setCookie(_ name: String, value: String, host: String) {
        cookies[host, default: [:]][name] = value
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

    /// Forgets the download (Chromium `DownloadItem::Remove`): no update is
    /// reported for it any more.
    public func removeDownload(id: DownloadItem.ID) {
        downloads.removeValue(forKey: id)
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

    /// Every origin with its own setting for `permission`, by origin.
    public func contentSettings(ofType permission: SitePermission) -> [ContentSettingEntry] {
        permissionSettings.compactMap { key, settings in
            settings[permission].map { ContentSettingEntry(pattern: key, origin: URL(string: key), setting: $0) }
        }.sorted { $0.pattern < $1.pattern }
    }

    // MARK: Clear browsing data (4.4b)

    /// Every `clearBrowsingData` call, in order.
    public private(set) var clearedBrowsingData: [(kinds: BrowsingDataKinds, period: BrowsingDataPeriod)] = []
    /// The fake's clock for the periods.
    public var now: () -> Date = Date.init

    /// History through `fakeHistory`, the downloads list by start time, the
    /// saved passwords (all of them: the fake keeps no dates) for all time;
    /// the rest is only recorded.
    public func clearBrowsingData(_ kinds: BrowsingDataKinds, since period: BrowsingDataPeriod) async {
        clearedBrowsingData.append((kinds, period))
        let start = period.start(before: now())
        if kinds.contains(.history) { fakeHistory?.deleteVisits(since: start) }
        if kinds.contains(.downloads) {
            downloads = downloads.filter { _, item in start.map { item.startTime < $0 } ?? false }
        }
        if kinds.contains(.passwords), start == nil { savedPasswords = [] }
    }

    static func originKey(_ url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host() ?? "")" + (url.port.map { ":\($0)" } ?? "")
    }

    // MARK: History and autocomplete (Phase 3.5), opt-in

    /// `history` when set: a test that wants the engine's history sets one
    /// (the no-history path runs without it).
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

    // MARK: Passwords (4.3b)

    /// A password the fake's store holds.
    public struct SavedPassword: Hashable, Sendable {
        /// `scheme://host[:port]` (Chromium's signon realm without the slash).
        public var site: String
        public var username: String
        public var password: String

        public init(site: String, username: String, password: String) {
            self.site = site
            self.username = username
            self.password = password
        }
    }

    /// The fake's password store: what imports added, and what a test put
    /// there to stand for passwords saved before.
    public var savedPasswords: [SavedPassword] = []

    /// Chromium's importer, reduced: the header names the columns (Chrome's
    /// aliases), a row needs a URL with a host and a password, a row whose
    /// site and username are saved with another password is a conflict, one
    /// saved with the same password counts as imported.
    public func importPasswords(csv: String, conflicts policy: PasswordImportConflictPolicy) async -> PasswordImportResult {
        let lines = FakeCSV.records(csv)
        guard let header = lines.first else { return PasswordImportResult(status: .badFormat) }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ aliases: [String]) -> Int? { names.firstIndex { aliases.contains($0) } }
        guard let urlColumn = column(["url", "website", "origin", "hostname", "login_uri"]),
              let passwordColumn = column(["password", "login_password"]) else {
            return PasswordImportResult(status: .badFormat)
        }
        let userColumn = column(["username", "user", "login", "account", "login_username"])
        var result = PasswordImportResult(status: .success)
        var conflictRows: [PasswordImportResult.Row] = []
        var skippedRows: [PasswordImportResult.Row] = []
        for record in lines.dropFirst() where !(record.count == 1 && record[0].isEmpty) {
            func field(_ index: Int?) -> String { index.flatMap { $0 < record.count ? record[$0] : nil } ?? "" }
            let rawURL = field(urlColumn), username = field(userColumn), password = field(passwordColumn)
            guard !rawURL.isEmpty else {
                skippedRows.append(.init(url: rawURL, username: username, reason: .missingURL))
                continue
            }
            guard let url = URL(string: rawURL), let scheme = url.scheme, ["http", "https"].contains(scheme), let host = url.host(), !host.isEmpty
            else {
                skippedRows.append(.init(url: rawURL, username: username, reason: .invalidURL))
                continue
            }
            guard !password.isEmpty else {
                skippedRows.append(.init(url: rawURL, username: username, reason: .missingPassword))
                continue
            }
            let site = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
            if let index = savedPasswords.firstIndex(where: { $0.site == site && $0.username == username }) {
                if savedPasswords[index].password == password {
                    result.imported += 1
                    continue
                }
                result.conflicts += 1
                if policy == .replace {
                    savedPasswords[index].password = password
                    result.replaced += 1
                    result.imported += 1
                }
                conflictRows.append(.init(url: site, username: username, reason: policy == .replace ? .conflictReplaced : .conflictKept))
                continue
            }
            savedPasswords.append(SavedPassword(site: site, username: username, password: password))
            result.imported += 1
        }
        result.rows = conflictRows + skippedRows
        return result
    }

    // MARK: Capabilities the fake does not provide

    public var bookmarks: (any ProfileBookmarks)? { nil }

    // MARK: Extensions (Phase 3.6a), opt-in

    /// `extensions` when set (a test that wants them sets one).
    public var fakeExtensions: FakeProfileExtensions? {
        didSet { fakeExtensions?.profile = self }
    }
    public var extensions: (any ProfileExtensions)? { fakeExtensions }
}

/// RFC 4180 records: commas, quoted fields with doubled quotes and line
/// breaks, CRLF or LF.
enum FakeCSV {
    static func records(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        func next() -> Character? {
            if let character = pending { pending = nil; return character }
            return iterator.next()
        }
        while let character = next() {
            if quoted {
                if character == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { quoted = false; pending = following }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": quoted = true
            case ",": record.append(field); field = ""
            case "\n", "\r\n", "\r":
                record.append(field); field = ""
                records.append(record); record = []
            default: field.append(character)
            }
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
