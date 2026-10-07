import AppKit
import Engine
import RoomCore

/// `Profile` over a `RoomProfile` (Chromium `Profile` in
/// `<user data>/Room Profile <name>`). It creates pages, binds each to the
/// Chrome `Browser` of its host window (one `RoomBrowser` per window and
/// profile, 3.2a: a Chrome `Browser` holds one profile's tabs, and a Room
/// window shows several profiles' spaces), hands Chrome's downloads to the
/// downloads delegate (3.4a: the host picks the file; Chrome's
/// `DownloadHistory` replays earlier sessions' downloads), and reads and
/// writes the site panel's settings (`HostContentSettingsMap`); since 3.5
/// it gives Chromium's history and omnibox (`RoomCoreOmnibox.swift`), since
/// 3.6a its extensions (`RoomCoreExtensions.swift`); bookmarks are `nil`
/// until 4.3 (docs/engine-api.md, RoomCore column).
public final class RoomCoreProfile: NSObject, Profile, RoomBrowserDelegate, RoomProfileDownloadsDelegate {
    public let name: String
    /// Set: RoomCore asks it for every new download's file and replays the
    /// downloads Chrome remembers (B-28).
    public weak var downloadsDelegate: (any DownloadsDelegate)? {
        didSet { profile.downloadsDelegate = downloadsDelegate == nil ? nil : self }
    }

    let profile: RoomProfile
    private let liveContents = NSHashTable<RoomCoreWebContents>.weakObjects()
    /// The Chrome `Browser` of each host window, created with the window's
    /// first page and gone when its last page leaves (Chromium closes a
    /// `Browser` whose tab strip empties; the next page makes a new one).
    private var browsers: [(window: Weak<NSWindow>, browser: RoomBrowser)] = []
    /// Browsers Chrome is closing: no longer handed out, kept alive until
    /// their `browserDidClose` (B-81).
    private var closingBrowsers: [RoomBrowser] = []

    /// The off-the-record twin `offTheRecord()` made (4.8b), until `closeOffTheRecord()`.
    private var twin: RoomCoreProfile?

    init(name: String, profile: RoomProfile) {
        self.name = name
        self.profile = profile
        super.init()
    }

    // MARK: Off the record (4.8b)

    /// `-[RoomProfile offTheRecordProfile]` (`Profile::GetPrimaryOTRProfile`,
    /// held by RoomCore's headless Browser of the twin).
    public func offTheRecord() throws -> any Profile {
        try makeOffTheRecord()
    }

    /// `offTheRecord()` returning the concrete type.
    public func makeOffTheRecord() throws -> RoomCoreProfile {
        guard !profile.isOffTheRecord else { throw EngineError.notSupported("offTheRecord of an off-the-record profile") }
        guard let otr = profile.offTheRecord() else {
            throw EngineError.profileInUse("the previous off-the-record profile is still being destroyed")
        }
        if let twin, twin.profile === otr { return twin }
        let made = RoomCoreProfile(name: name, profile: otr)
        twin = made
        return made
    }

    /// `-[RoomProfile closeOffTheRecordProfile]`: the twin's Browsers close
    /// (their pages with them) and Chrome destroys it once its renderers exit.
    public func closeOffTheRecord() {
        twin = nil
        profile.closeOffTheRecord()
    }

    /// The twin exists in Chrome (`Profile::HasPrimaryOTRProfile`): from
    /// `offTheRecord()` until Chrome destroyed it after `closeOffTheRecord()`.
    public var hasOffTheRecordProfile: Bool { profile.hasOffTheRecordProfile }

    /// The object for `roomProfile`'s pages: this profile, or its twin for a
    /// page Chrome opened off the record (patches/0014's hook).
    func owner(of roomProfile: RoomProfile) -> RoomCoreProfile? {
        if roomProfile === profile { return self }
        guard roomProfile.isOffTheRecord, let twin = try? makeOffTheRecord(), twin.profile === roomProfile else { return nil }
        return twin
    }

    /// Chromium's exit type for this profile's previous session
    /// (`ExitTypeService`, read when RoomCore first handed out the profile).
    public var lastExitWasClean: Bool? { profile.lastExitWasClean }

    /// Pages of this profile that are not closed.
    public var webContents: [RoomCoreWebContents] { liveContents.allObjects.filter { $0.state != .closed } }

    public func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents {
        try makeWebContents(configuration)
    }

    public func makeWebContents(_ configuration: WebContentsConfiguration = WebContentsConfiguration()) throws -> RoomCoreWebContents {
        if RoomCoreApplication.current?.isTerminating == true { throw EngineError.notRunning }
        // Hidden pages render nothing until their view is in a visible
        // window (Chromium's initially_hidden; WebContentsViewCocoa then
        // reports VISIBLE, and HIDDEN when the host takes the view out).
        let page = profile.createWebContents(initiallyHidden: configuration.initiallyHidden)
        // The saved back/forward list goes in before the page joins a strip
        // or loads (Chrome's tab restore: `Restore` on the new contents).
        if let state = configuration.restoredNavigationState, !page.restoreNavigationState(state) {
            NSLog("RoomCore: a saved navigation state (%ld bytes) was not restored; the page starts empty", state.count)
        }
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

    /// The Chrome `Browser`s of this profile's windows (DEBUG spikes reach
    /// their private spike selectors through them).
    public var spikeBrowsers: [RoomBrowser] { browsers.filter { !$0.browser.isClosed }.map(\.browser) }

    // MARK: RoomBrowserDelegate

    /// Chrome has decided to close the browser (its strip emptied) and
    /// deletes it after the current task: retired now, so a page made in the
    /// same turn gets a new Browser instead of joining one whose deletion is
    /// scheduled (`browser.cc` `!IsDeleteScheduled()`, B-81). The wrapper is
    /// kept until `browserDidClose`: Chrome's window calls back into it while
    /// the Browser is destroyed, and a wrapper released earlier would take
    /// that callback's target with it (found by the `recovery` step, 4.3b).
    public func browserWillClose(_ browser: RoomBrowser) {
        browsers.removeAll { $0.browser === browser }
        if !closingBrowsers.contains(where: { $0 === browser }) { closingBrowsers.append(browser) }
    }

    public func browserDidClose(_ browser: RoomBrowser) {
        browsers.removeAll { $0.browser === browser }
        closingBrowsers.removeAll { $0 === browser }
    }

    func closeAll() {
        for contents in liveContents.allObjects { contents.close() }
    }

    /// Chrome is about to close a window with downloads in progress (the
    /// quit): Room continues and the downloads are cancelled (the Chapter 3
    /// decision; Settings says so in Chapter 4). Chrome's own prompt never shows.
    public func browser(_ browser: RoomBrowser, shouldCloseWithPendingDownloads count: Int,
                        completion: @escaping (Bool) -> Void) {
        NSLog("RoomCore: closing with %ld downloads in progress; they are cancelled", count)
        completion(true)
    }

    // MARK: Downloads (3.4a)

    /// `download::DownloadItem::Pause / Resume / Cancel` by GUID.
    public func pauseDownload(id: DownloadItem.ID) { profile.pauseDownload(id) }
    public func resumeDownload(id: DownloadItem.ID) { profile.resumeDownload(id) }
    public func cancelDownload(id: DownloadItem.ID) { profile.cancelDownload(id) }
    /// `download::DownloadItem::Remove` by GUID (4.1b): out of Chrome's list
    /// and `DownloadHistory`'s database.
    public func removeDownload(id: DownloadItem.ID) { profile.removeDownload(id) }

    /// `DetermineDownloadTarget` (patch 0019): the delegate picks the file.
    public func profile(_ profile: RoomProfile, willBeginDownload item: RoomDownloadItem,
                        completion: @escaping (URL?) -> Void) {
        guard let downloadsDelegate else { return completion(nil) }
        downloadsDelegate.profile(self, willBeginDownload: DownloadItem(item), completion: completion)
    }

    public func profile(_ profile: RoomProfile, didUpdateDownload item: RoomDownloadItem) {
        downloadsDelegate?.profile(self, didUpdateDownload: DownloadItem(item))
    }

    /// Chrome's `FaviconService::GetFaviconImageForPageURL`.
    public func favicon(for pageURL: URL) async -> NSImage? {
        await profile.favicon(forPageURL: pageURL)
    }

    /// `BrowsingDataRemover` for cookies, cache and storage (the origin's
    /// site), the network context's HTTP auth cache, and for permissions the
    /// content settings plus the certificate decisions (`SSLHostStateDelegate`).
    public func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws {
        var mask: RoomSiteDataTypes = []
        if types.contains(.cookies) { mask.insert(.cookies) }
        if types.contains(.cache) { mask.insert(.cache) }
        if types.contains(.storage) { mask.insert(.storage) }
        if types.contains(.httpAuthCredentials) { mask.insert(.httpAuthCredentials) }
        if types.contains(.permissions) { mask.insert(.permissions) }
        await withCheckedContinuation { continuation in
            profile.clearSiteData(mask, for: origin) { continuation.resume() }
        }
    }

    /// `HostContentSettingsMap::GetContentSetting`; `nil` when only the
    /// default (wildcard) setting applies.
    public func permissionSetting(_ permission: SitePermission, for origin: URL) -> PermissionSetting? {
        switch profile.contentSetting(for: RoomContentSettingType(permission), origin: origin) {
        case .allow: .allow
        case .block: .block
        case .ask: .ask
        default: nil
        }
    }

    /// `SetContentSettingDefaultScope`; `nil` removes the site's setting.
    public func setPermissionSetting(_ setting: PermissionSetting?, for permission: SitePermission, origin: URL) {
        let value: RoomContentSetting = switch setting {
        case .allow?: .allow
        case .block?: .block
        case .ask?: .ask
        case nil: .default
        }
        profile.setContentSetting(value, for: RoomContentSettingType(permission), origin: origin)
    }

    /// `HostContentSettingsMap::GetSettingsForOneType`: the preference
    /// provider's rules for a site (4.4b; dictionaries of Foundation values).
    public func contentSettings(ofType permission: SitePermission) -> [ContentSettingEntry] {
        profile.contentSettings(for: RoomContentSettingType(permission)).compactMap { values in
            guard let pattern = values["pattern"] as? String,
                  let raw = (values["setting"] as? NSNumber)?.intValue else { return nil }
            let setting: PermissionSetting
            switch RoomContentSetting(rawValue: raw) {
            case .allow?: setting = .allow
            case .block?: setting = .block
            case .ask?: setting = .ask
            default: return nil
            }
            return ContentSettingEntry(pattern: pattern, origin: values["origin"] as? URL, setting: setting,
                                       isEmbedded: (values["embedded"] as? NSNumber)?.boolValue ?? false)
        }
    }

    /// Chrome's Clear browsing data (`BrowsingDataRemover::RemoveAndReply`
    /// over Chrome's data types and time periods; 4.4b).
    public func clearBrowsingData(_ kinds: BrowsingDataKinds, since period: BrowsingDataPeriod) async {
        var types: RoomBrowsingDataTypes = []
        if kinds.contains(.history) { types.insert(.history) }
        if kinds.contains(.cookiesAndSiteData) { types.insert(.cookiesAndSiteData) }
        if kinds.contains(.cache) { types.insert(.cache) }
        if kinds.contains(.downloads) { types.insert(.downloads) }
        if kinds.contains(.autofill) { types.insert(.autofill) }
        if kinds.contains(.passwords) { types.insert(.passwords) }
        let since: RoomBrowsingDataPeriod = switch period {
        case .lastHour: .lastHour
        case .lastDay: .lastDay
        case .lastWeek: .lastWeek
        case .lastFourWeeks: .fourWeeks
        case .allTime: .allTime
        }
        await withCheckedContinuation { continuation in
            profile.clearBrowsingData(types, since: since) { continuation.resume() }
        }
    }

    // MARK: Passwords (4.3b)

    /// Chromium's `PasswordImporter` over the profile's password stores
    /// (`-[RoomProfile importPasswordsFromCSV:replaceConflicts:completion:]`;
    /// the result crosses as Foundation values).
    public func importPasswords(csv: String, conflicts: PasswordImportConflictPolicy) async -> PasswordImportResult {
        await withCheckedContinuation { continuation in
            profile.importPasswords(csv: csv, replaceConflicts: conflicts == .replace) {
                continuation.resume(returning: PasswordImportResult(roomCore: $0))
            }
        }
    }

    // MARK: History and the omnibox (3.5)

    private lazy var roomHistory: RoomCoreHistory? = profile.history.map { RoomCoreHistory(history: $0) }

    /// Chromium's `HistoryService` for this profile.
    public var history: (any ProfileHistory)? { roomHistory }

    /// Chromium's `AutocompleteController` with `ChromeAutocompleteProviderClient`.
    public func makeAutocompleteController() -> (any AutocompleteController)? {
        profile.makeAutocompleteController().map { RoomCoreAutocompleteController(controller: $0) }
    }

    /// `TemplateURLService`: the default search engine SearchProvider asks.
    public func setDefaultSearchEngine(_ engine: SearchEngineTemplate) {
        profile.setDefaultSearchEngine(name: engine.name, keyword: engine.keyword, searchURL: engine.searchURL, suggestURL: engine.suggestURL)
    }

    /// Chromium's search-suggest preference, kept equal to the host's switch.
    public var searchSuggestEnabled: Bool {
        get { profile.searchSuggestEnabled }
        set { profile.searchSuggestEnabled = newValue }
    }

    public var bookmarks: (any ProfileBookmarks)? { nil }

    // MARK: Extensions (3.6a)

    private lazy var roomExtensions: RoomCoreExtensions? = profile.extensions.map { RoomCoreExtensions(extensions: $0, profile: self) }

    /// Chromium's extension system for this profile (`RoomCoreExtensions.swift`).
    public var extensions: (any ProfileExtensions)? { roomExtensions }

    /// The host's object for one of this profile's pages.
    func contents(for page: RoomWebContents) -> RoomCoreWebContents? {
        liveContents.allObjects.first { $0.page === page }
    }
}

/// A weak reference in a collection.
struct Weak<Object: AnyObject> {
    weak var object: Object?
    init(_ object: Object) { self.object = object }
}

extension RoomContentSettingType {
    /// The site panel's permissions as Chrome's content settings types.
    init(_ permission: SitePermission) {
        switch permission {
        case .geolocation: self = .geolocation
        case .camera: self = .camera
        case .microphone: self = .microphone
        case .notifications: self = .notifications
        case .clipboard: self = .clipboard
        case .sensors: self = .sensors
        case .midiSysex: self = .midiSysex
        case .popups: self = .popups
        case .sound: self = .sound
        case .automaticDownloads: self = .automaticDownloads
        case .javascript: self = .javaScript
        case .images: self = .images
        }
    }
}

extension DownloadItem {
    /// A snapshot of Chrome's `download::DownloadItem` (the GUID is the id).
    init(_ item: RoomDownloadItem) {
        let state: State = switch item.state {
        case .complete: .complete
        case .cancelled: .cancelled
        case .interrupted: .interrupted
        default: .inProgress
        }
        self.init(id: item.identifier, url: item.url, suggestedFilename: item.suggestedFilename,
                  destination: item.destination, mimeType: item.mimeType, receivedBytes: item.receivedBytes,
                  totalBytes: item.totalBytes >= 0 ? item.totalBytes : nil, currentSpeed: item.currentSpeed,
                  state: state, isPaused: item.isPaused, canResume: item.canResume, startTime: item.startTime)
    }
}

extension PasswordImportResult {
    /// The dictionary `-[RoomProfile importPasswordsFromCSV:…]` answers with
    /// (keys in `RoomProfile.h`); an unknown status or reason reads as a failure.
    init(roomCore values: [String: Any]) {
        let rows = (values["rows"] as? [[String: Any]] ?? []).map { row in
            Row(url: row["url"] as? String ?? "", username: row["username"] as? String ?? "",
                reason: (row["reason"] as? String).flatMap(Reason.init(rawValue:)) ?? .malformed)
        }
        self.init(status: (values["status"] as? String).flatMap(Status.init(rawValue:)) ?? .failed,
                  imported: (values["imported"] as? NSNumber)?.intValue ?? 0,
                  conflicts: (values["conflicts"] as? NSNumber)?.intValue ?? 0,
                  replaced: (values["replaced"] as? NSNumber)?.intValue ?? 0,
                  rows: rows)
    }
}
