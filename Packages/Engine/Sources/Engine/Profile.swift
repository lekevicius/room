import AppKit

/// A browsing profile: one cookie jar, cache, history and set of site
/// permissions. Chromium `Profile`.
@MainActor
public protocol Profile: AnyObject {
    /// The name the profile was created with; also its directory name.
    var name: String { get }

    /// Creates a tab's web contents. It has no URL until `load` is called and
    /// is not shown until its `nativeView` is added to a window.
    func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents

    /// Receives every download started in this profile. Held weakly.
    var downloadsDelegate: (any DownloadsDelegate)? { get set }

    func pauseDownload(id: DownloadItem.ID)
    func resumeDownload(id: DownloadItem.ID)
    func cancelDownload(id: DownloadItem.ID)
    /// Removes the download from the engine's list and its download history
    /// (Chromium `DownloadItem::Remove`), so a relaunch does not list it; a
    /// finished file stays on disk, a partial one is deleted. No further
    /// update is reported for it. The host cancels a running one first.
    func removeDownload(id: DownloadItem.ID)

    /// The engine's stored favicon for a page, if it has one.
    func favicon(for pageURL: URL) async -> NSImage?

    /// Deletes site data of the given kinds, for one origin or (`nil`) all.
    func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws

    /// The setting stored for `permission` on `origin`, or `nil` when the
    /// site has none (the permission's default applies).
    func permissionSetting(_ permission: SitePermission, for origin: URL) -> PermissionSetting?
    /// Stores `setting` for `origin`; `nil` removes the site's setting.
    func setPermissionSetting(_ setting: PermissionSetting?, for permission: SitePermission, origin: URL)
    /// Every site with its own setting for `permission` (4.4b, Settings ▸
    /// Privacy): the user's and the prompts' answers, not the default.
    /// RoomCore: `HostContentSettingsMap::GetSettingsForOneType`, the
    /// preference provider's rules whose site is not the wildcard.
    func contentSettings(ofType permission: SitePermission) -> [ContentSettingEntry]

    /// Clear browsing data (4.4b, Settings ▸ Privacy): removes `kinds`
    /// recorded in `period` (until now) from every site. RoomCore:
    /// `BrowsingDataRemover` with Chrome's data types for Chrome's periods.
    func clearBrowsingData(_ kinds: BrowsingDataKinds, since period: BrowsingDataPeriod) async

    // Optional capabilities: `nil` when the engine does not provide them
    // (the fakes by default, no engine). Specified in Chapter 3.

    /// Chromium's history service.
    var history: (any ProfileHistory)? { get }
    /// Chromium's bookmark model (import source; the sidebar has its own model).
    var bookmarks: (any ProfileBookmarks)? { get }
    /// Installed extensions, their actions and popups.
    var extensions: (any ProfileExtensions)? { get }
    /// A new omnibox `AutocompleteController`, one per address field; `nil`
    /// when the engine has none (the palette's Chapter 2 providers run).
    func makeAutocompleteController() -> (any AutocompleteController)?
    /// Makes `engine` the profile's default search engine, so the engine's
    /// search suggestions and search matches use it. Templates use
    /// `{searchTerms}`. Ignored by engines without an omnibox.
    func setDefaultSearchEngine(_ engine: SearchEngineTemplate)

    /// Imports passwords from a CSV in Chrome's export format (a header
    /// naming `name,url,username,password,note` or Chrome's aliases) into the
    /// profile's password store (Chromium `PasswordImporter`, 4.3b). A row
    /// whose site and username are saved with another password is a
    /// conflict: `conflicts` decides for all of them at once. Engines without
    /// a password store answer `.unavailable`.
    func importPasswords(csv: String, conflicts: PasswordImportConflictPolicy) async -> PasswordImportResult

    /// Whether the engine saw this profile's previous session end cleanly
    /// (Chromium's exit type: `false` after a crash or a kill), read when the
    /// profile loaded; `nil` when the engine does not track it. The
    /// host combines it with its own store's `uncleanExit`.
    var lastExitWasClean: Bool? { get }
}

/// Chromium's history service for one profile (Phase 3.5). The palette's
/// history and ⌘Y read it, and the Chapter 2 history is imported into it
/// once per profile. Queries answer asynchronously (Chromium's history
/// thread). RoomCore: `HistoryService`; the no-engine app: none.
@MainActor public protocol ProfileHistory: AnyObject {
    /// URLs whose title or URL contain every word of `text`, most recent first.
    func search(_ text: String, limit: Int) async -> [HistoryEntry]
    /// URLs last visited in `range` (open ends allowed), most recent first.
    func entries(from start: Date?, to end: Date?, limit: Int) async -> [HistoryEntry]
    /// The URL's row and its visits; `nil` when it is not in history.
    func visits(for url: URL) async -> (entry: HistoryEntry, visits: [HistoryVisit])?
    /// The most visited URLs, recent visits weighing more (⌘Y).
    func mostVisited(limit: Int) async -> [HistoryEntry]
    /// Removes the URL and its visits.
    func delete(url: URL)
    /// Removes every URL of `host` ("www." and the scheme ignored); how many.
    @discardableResult func delete(host: String) async -> Int
    /// Adds URLs with their visits (the Chapter 2 import); visits older than
    /// the engine keeps (Chromium: 90 days) are left out and counted.
    func importEntries(_ entries: [HistoryImportEntry]) async -> HistoryImportResult
}

/// One URL in the engine's history.
nonisolated public struct HistoryEntry: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var visitCount: Int
    public var typedCount: Int
    public var lastVisit: Date?

    public init(url: URL, title: String, visitCount: Int = 0, typedCount: Int = 0, lastVisit: Date? = nil) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.typedCount = typedCount
        self.lastVisit = lastVisit
    }
}

/// One visit of a URL.
nonisolated public struct HistoryVisit: Hashable, Sendable {
    public var time: Date
    public var transition: PageTransition

    public init(time: Date, transition: PageTransition) {
        self.time = time
        self.transition = transition
    }
}

/// A URL to import with its visits; its visit and typed counts are its
/// visits' (reloads are not visits).
nonisolated public struct HistoryImportEntry: Hashable, Sendable {
    public var url: URL
    public var title: String?
    public var visits: [HistoryVisit]

    public init(url: URL, title: String?, visits: [HistoryVisit]) {
        self.url = url
        self.title = title
        self.visits = visits
    }
}

/// What an import added and what it left out.
nonisolated public struct HistoryImportResult: Hashable, Sendable {
    public var urls: Int
    public var visits: Int
    /// Visits older than the engine keeps.
    public var expiredVisits: Int
    /// URLs whose every visit was older than that.
    public var expiredURLs: Int

    public init(urls: Int = 0, visits: Int = 0, expiredVisits: Int = 0, expiredURLs: Int = 0) {
        self.urls = urls
        self.visits = visits
        self.expiredVisits = expiredVisits
        self.expiredURLs = expiredURLs
    }

    public static func + (lhs: HistoryImportResult, rhs: HistoryImportResult) -> HistoryImportResult {
        HistoryImportResult(urls: lhs.urls + rhs.urls, visits: lhs.visits + rhs.visits,
                            expiredVisits: lhs.expiredVisits + rhs.expiredVisits, expiredURLs: lhs.expiredURLs + rhs.expiredURLs)
    }
}

/// What a password import does with a row whose site and username are
/// already saved with a different password (asked once for the whole file).
nonisolated public enum PasswordImportConflictPolicy: Hashable, Sendable {
    /// The saved password stays.
    case skip
    /// The imported password replaces it.
    case replace
}

/// What `Profile.importPasswords` did. Never holds a password.
nonisolated public struct PasswordImportResult: Hashable, Sendable {
    nonisolated public enum Status: String, Hashable, Sendable {
        case success
        /// The text has no header the importer recognises.
        case badFormat
        /// Over the importer's size limit (Chromium: 1000 KB).
        case tooLarge
        /// More rows than the importer takes at once.
        case tooMany
        case unreadable
        /// Another import is still running in the profile.
        case busy
        /// The profile has no password store (off the record, no engine).
        case unavailable
        case failed
    }

    /// Why a row was not added as given.
    nonisolated public enum Reason: String, Hashable, Sendable {
        case conflictKept, conflictReplaced
        case missingURL, invalidURL, missingPassword
        case longURL, longUsername, longPassword, longNote
        case malformed
    }

    nonisolated public struct Row: Hashable, Sendable {
        public var url: String
        public var username: String
        public var reason: Reason

        public init(url: String, username: String, reason: Reason) {
            self.url = url
            self.username = username
            self.reason = reason
        }
    }

    public var status: Status
    /// Rows now saved: added, already saved with the same password, or
    /// replaced (Chromium's count).
    public var imported: Int
    /// Rows that met a saved password for the same site and username.
    public var conflicts: Int
    /// Of `conflicts`, how many replaced the saved password.
    public var replaced: Int
    /// Every row not added as given (conflicts first), with its reason.
    public var rows: [Row]

    /// Rows refused for their content (not conflicts).
    public var skipped: Int { rows.count { $0.reason != .conflictKept && $0.reason != .conflictReplaced } }

    public init(status: Status, imported: Int = 0, conflicts: Int = 0, replaced: Int = 0, rows: [Row] = []) {
        self.status = status
        self.imported = imported
        self.conflicts = conflicts
        self.replaced = replaced
        self.rows = rows
    }
}

/// Chromium bookmark model. Members arrive in Phase 4.3.
@MainActor public protocol ProfileBookmarks: AnyObject {}


/// Chromium's omnibox autocomplete for one address field (Phase 3.5):
/// Chrome's history providers (and, only when the host's suggestions switch
/// is on, its search suggestions) answer the palette's input. RoomCore:
/// `AutocompleteController` with `ChromeAutocompleteProviderClient`.
@MainActor public protocol AutocompleteController: AnyObject {
    /// Hears every change of `matches`. Held weakly.
    var delegate: (any AutocompleteControllerDelegate)? { get set }
    /// Starts a query; the delegate hears the synchronous pass from inside
    /// this call and later passes as asynchronous providers answer.
    /// `providers` is chosen per call by the host (no `.search` while the
    /// suggestions switch is off: then nothing leaves the machine).
    func start(_ input: AutocompleteInput)
    /// Stops the query; `matches` stays.
    func stop()
    /// The engine's result, its default match first when it has one.
    var matches: [AutocompleteMatch] { get }
    /// No provider is still working on the last query.
    var isDone: Bool { get }
    /// Asks the match's provider to delete it (history: the URL).
    func deleteMatch(at index: Int)
}

@MainActor public protocol AutocompleteControllerDelegate: AnyObject {
    func autocompleteControllerDidUpdate(_ controller: any AutocompleteController)
}

/// What the field holds and how to answer it.
nonisolated public struct AutocompleteInput: Hashable, Sendable {
    public var text: String
    /// The cursor's position in `text` (UTF-16 offset); `nil`: at the end.
    public var cursorPosition: Int?
    /// After a deletion: nothing completes inline.
    public var preventsInlineCompletion: Bool
    /// The text is a keyword search.
    public var keywordMode: Bool
    public var providers: AutocompleteProviders

    public init(text: String, cursorPosition: Int? = nil, preventsInlineCompletion: Bool = false, keywordMode: Bool = false,
                providers: AutocompleteProviders) {
        self.text = text
        self.cursorPosition = cursorPosition
        self.preventsInlineCompletion = preventsInlineCompletion
        self.keywordMode = keywordMode
        self.providers = providers
    }
}

/// Chromium's providers the host can ask for.
nonisolated public struct AutocompleteProviders: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let historyQuick = AutocompleteProviders(rawValue: 1 << 0)
    public static let historyURL = AutocompleteProviders(rawValue: 1 << 1)
    public static let bookmark = AutocompleteProviders(rawValue: 1 << 2)
    public static let shortcuts = AutocompleteProviders(rawValue: 1 << 3)
    public static let openTab = AutocompleteProviders(rawValue: 1 << 4)
    /// Search suggestions from the default engine: network.
    public static let search = AutocompleteProviders(rawValue: 1 << 5)

    /// Everything that reads only the profile's own data.
    public static let local: AutocompleteProviders = [.historyQuick, .historyURL, .bookmark, .shortcuts, .openTab]
}

/// The kinds of match the host tells apart (Chromium's AutocompleteMatchType).
nonisolated public enum AutocompleteMatchKind: Sendable, Hashable {
    case urlWhatYouTyped, historyURL, historyTitle, historyBody, historyKeyword, navSuggest
    case searchWhatYouTyped, searchHistory, searchSuggest, searchOtherEngine, bookmarkTitle, openTab, other

    /// A page from the profile's history.
    public var isHistory: Bool {
        switch self {
        case .historyURL, .historyTitle, .historyBody, .historyKeyword: true
        default: false
        }
    }
}

/// One match of the engine's result.
nonisolated public struct AutocompleteMatch: Hashable, Sendable {
    public var contents: String
    public var description: String
    public var destinationURL: URL?
    public var fillIntoEdit: String
    /// The text after the cursor that completes it inline; empty when none.
    public var inlineCompletion: String
    /// Chromium's relevance (not Room's bands: the host maps by rank).
    public var relevance: Int
    public var kind: AutocompleteMatchKind
    /// The provider that made it (one member; empty for one the host does not ask).
    public var provider: AutocompleteProviders
    public var isDeletable: Bool
    /// The destination is open in a tab the engine knows.
    public var hasTabMatch: Bool
    public var allowedToBeDefault: Bool

    public init(contents: String, description: String = "", destinationURL: URL?, fillIntoEdit: String = "", inlineCompletion: String = "",
                relevance: Int, kind: AutocompleteMatchKind, provider: AutocompleteProviders, isDeletable: Bool = false,
                hasTabMatch: Bool = false, allowedToBeDefault: Bool = false) {
        self.contents = contents
        self.description = description
        self.destinationURL = destinationURL
        self.fillIntoEdit = fillIntoEdit
        self.inlineCompletion = inlineCompletion
        self.relevance = relevance
        self.kind = kind
        self.provider = provider
        self.isDeletable = isDeletable
        self.hasTabMatch = hasTabMatch
        self.allowedToBeDefault = allowedToBeDefault
    }
}

/// A search engine as the engine's omnibox keeps it.
nonisolated public struct SearchEngineTemplate: Hashable, Sendable {
    public var name: String
    /// Names the engine: a different keyword is a different engine.
    public var keyword: String
    /// The results page with `{searchTerms}`.
    public var searchURL: String
    /// The suggestions endpoint with `{searchTerms}`, if any.
    public var suggestURL: String?

    public init(name: String, keyword: String, searchURL: String, suggestURL: String?) {
        self.name = name
        self.keyword = keyword
        self.searchURL = searchURL
        self.suggestURL = suggestURL
    }
}

/// What `Profile.clearBrowsingData` removes (Chrome's Clear browsing data
/// with its advanced kinds).
nonisolated public struct BrowsingDataKinds: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Visited pages (the engine's history; the palette's history group).
    public static let history = BrowsingDataKinds(rawValue: 1 << 0)
    /// Cookies and every kind of site storage; signs out of most sites.
    public static let cookiesAndSiteData = BrowsingDataKinds(rawValue: 1 << 1)
    public static let cache = BrowsingDataKinds(rawValue: 1 << 2)
    /// The downloads list (the files stay).
    public static let downloads = BrowsingDataKinds(rawValue: 1 << 3)
    /// Autofill's saved form entries and addresses.
    public static let autofill = BrowsingDataKinds(rawValue: 1 << 4)
    public static let passwords = BrowsingDataKinds(rawValue: 1 << 5)

    public static let all: BrowsingDataKinds = [.history, .cookiesAndSiteData, .cache, .downloads, .autofill, .passwords]
}

/// How far back `Profile.clearBrowsingData` goes (Chrome's time periods).
nonisolated public enum BrowsingDataPeriod: String, Sendable, Hashable, CaseIterable {
    case lastHour, lastDay, lastWeek, lastFourWeeks, allTime

    /// The period's start for `now`; `nil` for all time.
    public func start(before now: Date) -> Date? {
        switch self {
        case .lastHour: now.addingTimeInterval(-3600)
        case .lastDay: now.addingTimeInterval(-86_400)
        case .lastWeek: now.addingTimeInterval(-7 * 86_400)
        case .lastFourWeeks: now.addingTimeInterval(-28 * 86_400)
        case .allTime: nil
        }
    }
}

/// One site's own setting for a permission (`Profile.contentSettings(ofType:)`).
nonisolated public struct ContentSettingEntry: Hashable, Sendable {
    /// The site as the engine stores it (Chrome's pattern, e.g.
    /// `https://example.com:443` or `[*.]example.com`).
    public var pattern: String
    /// A URL the pattern matches, for `setPermissionSetting` (change, reset);
    /// `nil` when the pattern names no single site.
    public var origin: URL?
    public var setting: PermissionSetting
    /// The setting applies only where the site is embedded in another
    /// (Chrome's secondary pattern is not the wildcard).
    public var isEmbedded: Bool

    public init(pattern: String, origin: URL?, setting: PermissionSetting, isEmbedded: Bool = false) {
        self.pattern = pattern
        self.origin = origin
        self.setting = setting
        self.isEmbedded = isEmbedded
    }
}

/// Kinds of site data `Profile.clearSiteData` removes.
nonisolated public struct SiteDataTypes: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let cookies = SiteDataTypes(rawValue: 1 << 0)
    public static let cache = SiteDataTypes(rawValue: 1 << 1)
    /// Local/session storage, IndexedDB, Cache Storage, service workers.
    public static let storage = SiteDataTypes(rawValue: 1 << 2)
    public static let httpAuthCredentials = SiteDataTypes(rawValue: 1 << 3)
    /// Site permissions and content settings.
    public static let permissions = SiteDataTypes(rawValue: 1 << 4)

    public static let all: SiteDataTypes = [.cookies, .cache, .storage, .httpAuthCredentials, .permissions]
}
