import Foundation
import GRDB

// The persisted sidebar model (schema v1). Every type here is a plain value:
// the Store owns the only mutable copy and hands whole `RoomState` snapshots
// to the `StateWriter`. Column names are the property names.

/// Milliseconds since 1970, stored as an INTEGER. `Date` would round-trip
/// through SQLite text or a `Double` and come back a hair different, which
/// breaks the writer's diff and the kill test's content hashes.
public struct Timestamp: Hashable, Comparable, Sendable, Codable, DatabaseValueConvertible {
    public var milliseconds: Int64

    public init(milliseconds: Int64) { self.milliseconds = milliseconds }

    public init(_ date: Date) {
        milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static var now: Timestamp { Timestamp(Date()) }

    public var date: Date { Date(timeIntervalSince1970: Double(milliseconds) / 1000) }

    public static func < (lhs: Timestamp, rhs: Timestamp) -> Bool { lhs.milliseconds < rhs.milliseconds }

    public init(from decoder: any Decoder) throws {
        milliseconds = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(milliseconds)
    }

    public var databaseValue: DatabaseValue { milliseconds.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Timestamp? {
        Int64.fromDatabaseValue(dbValue).map(Timestamp.init(milliseconds:))
    }
}

/// A cookie jar (engine request context). Essentials belong to a profile.
public struct Profile: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "profile"

    public var id: UUID
    public var name: String
    public var position: Int

    public init(id: UUID = UUID(), name: String, position: Int) {
        self.id = id
        self.name = name
        self.position = position
    }
}

/// How a space's 1–3 theme colours are extended into a palette (spec §B).
public enum ThemeAlgorithm: String, Hashable, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case complementary, split, analogous, triadic, floating
}

public struct Space: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "space"

    public var id: UUID
    public var name: String
    /// Emoji or SF Symbol name; `nil` = the default space glyph.
    public var icon: String?
    /// Hex colours (`#RRGGBB`), 0–3.
    public var themeColors: [String]
    public var themeAlgorithm: ThemeAlgorithm
    /// Tint opacity, 0–1.
    public var themeOpacity: Double
    public var profileID: UUID
    public var position: Int
    public var pinnedCollapsed: Bool

    public init(
        id: UUID = UUID(), name: String, icon: String? = nil, themeColors: [String] = [],
        themeAlgorithm: ThemeAlgorithm = .floating, themeOpacity: Double = 0.5,
        profileID: UUID, position: Int, pinnedCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.themeColors = themeColors
        self.themeAlgorithm = themeAlgorithm
        self.themeOpacity = themeOpacity
        self.profileID = profileID
        self.position = position
        self.pinnedCollapsed = pinnedCollapsed
    }
}

/// Spec §A.1. Folders live only in the pinned section in v1 (§A.6).
public enum EntryKind: String, Hashable, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case essential, pinned, folder, today

    public var section: EntrySection {
        switch self {
        case .essential: .essentials
        case .pinned, .folder: .pinned
        case .today: .today
        }
    }

    /// Essentials, pinned entries and folders survive Clear and archiving.
    public var isPermanent: Bool { self != .today }
}

/// The three places an entry can live; crossing between them converts the
/// entry's kind (spec §A.9).
public enum EntrySection: String, Hashable, Sendable, Codable, CaseIterable {
    case essentials, pinned, today
}

public struct Entry: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entry"

    public var id: UUID
    public var kind: EntryKind
    /// `nil` for essentials (they belong to the profile, shown in each of its spaces).
    public var spaceID: UUID?
    public var profileID: UUID
    /// Parent folder (pinned section only).
    public var folderID: UUID?
    public var splitGroupID: UUID?
    /// Order among the siblings in the same container (0-based, contiguous).
    public var position: Int
    /// Permanent entries: the URL the entry resets to.
    public var storedURL: String?
    /// Permanent entries: the page title at pin time.
    public var storedTitle: String?
    /// User label (rename); folders keep their name here.
    public var customLabel: String?
    /// Emoji or SF Symbol name chosen by the user.
    public var customIcon: String?
    /// Row in `favicon` (a cache; no foreign key, a missing row means "letter tile").
    public var faviconID: Int64?
    /// Folders only.
    public var isCollapsed: Bool
    public var createdAt: Timestamp
    /// MRU key; `nil` until first selected.
    public var lastActiveAt: Timestamp?
    /// The page the entry last showed (restored unloaded at launch).
    public var liveURL: String?
    public var liveTitle: String?
    /// The page's back/forward list as the engine serialised it
    /// (`WebContents.navigationState`, opaque; schema v5, Phase 3.7b): an
    /// entry revived from unloaded (relaunch, crash recovery, discard, ⌘W's
    /// unload, ⇧⌘T) goes Back where it was. `nil` when the page had none or
    /// the engine cannot serialise it.
    public var navigationState: Data?

    public init(
        id: UUID = UUID(), kind: EntryKind, spaceID: UUID?, profileID: UUID, folderID: UUID? = nil,
        splitGroupID: UUID? = nil, position: Int = 0, storedURL: String? = nil, storedTitle: String? = nil,
        customLabel: String? = nil, customIcon: String? = nil, faviconID: Int64? = nil,
        isCollapsed: Bool = false, createdAt: Timestamp = .now, lastActiveAt: Timestamp? = nil,
        liveURL: String? = nil, liveTitle: String? = nil, navigationState: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.spaceID = spaceID
        self.profileID = profileID
        self.folderID = folderID
        self.splitGroupID = splitGroupID
        self.position = position
        self.storedURL = storedURL
        self.storedTitle = storedTitle
        self.customLabel = customLabel
        self.customIcon = customIcon
        self.faviconID = faviconID
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.liveURL = liveURL
        self.liveTitle = liveTitle
        self.navigationState = navigationState
    }

    /// The URL a click loads: the live page if there is one, else the stored one.
    public var currentURL: String? { liveURL ?? storedURL }

    /// Row title: user label, then live title, then stored title, then the URL.
    public var displayTitle: String {
        customLabel ?? liveTitle ?? storedTitle ?? currentURL ?? ""
    }
}

public enum SplitLayout: String, Hashable, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    case hbox, vbox, grid
}

/// ≤4 panes (Phase 2.7); members point here through `Entry.splitGroupID`.
public struct SplitGroup: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "split_group"

    public var id: UUID
    public var layout: SplitLayout
    /// Pane sizes as fractions (`SplitRules.equalRatios`): `hbox`/`vbox` one
    /// per pane in `members` order; `grid` the two column fractions, then the two row fractions.
    public var ratios: [Double]
    /// The member entries in pane order (schema v4, Phase 2.7b): members may
    /// sit in different sections (a Today tab beside a pinned entry), so their
    /// positions cannot order the panes.
    public var members: [UUID]

    public init(id: UUID = UUID(), layout: SplitLayout = .hbox, ratios: [Double] = [], members: [UUID] = []) {
        self.id = id
        self.layout = layout
        self.ratios = ratios
        self.members = members
    }

    private enum CodingKeys: String, CodingKey { case id, layout, ratios, members }

    /// JSON snapshots written before schema v4 have no `members`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layout = try container.decode(SplitLayout.self, forKey: .layout)
        ratios = try container.decode([Double].self, forKey: .ratios)
        members = try container.decodeIfPresent([UUID].self, forKey: .members) ?? []
    }
}

/// One browser window's restorable state.
public struct WindowState: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "window"

    public var id: UUID
    /// Screen frame (AppKit coordinates); `nil` until the window first moves.
    public var frameX: Double?
    public var frameY: Double?
    public var frameWidth: Double?
    public var frameHeight: Double?
    public var sidebarWidth: Double
    public var sidebarVisible: Bool
    public var activeSpaceID: UUID?
    public var position: Int

    public init(
        id: UUID = UUID(), sidebarWidth: Double, sidebarVisible: Bool = true,
        activeSpaceID: UUID?, position: Int = 0
    ) {
        self.id = id
        self.sidebarWidth = sidebarWidth
        self.sidebarVisible = sidebarVisible
        self.activeSpaceID = activeSpaceID
        self.position = position
    }

    public var frame: CGRect? {
        get {
            guard let frameX, let frameY, let frameWidth, let frameHeight else { return nil }
            return CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        }
        set {
            frameX = newValue.map { Double($0.origin.x) }
            frameY = newValue.map { Double($0.origin.y) }
            frameWidth = newValue.map { Double($0.size.width) }
            frameHeight = newValue.map { Double($0.size.height) }
        }
    }
}

/// The selected entry of one space in one window.
public struct WindowSpace: Hashable, Sendable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "window_space"

    public var windowID: UUID
    public var spaceID: UUID
    public var selectedEntryID: UUID?

    public init(windowID: UUID, spaceID: UUID, selectedEntryID: UUID?) {
        self.windowID = windowID
        self.spaceID = spaceID
        self.selectedEntryID = selectedEntryID
    }
}

/// Favicon cache by host (written outside the state pipeline).
public struct Favicon: Hashable, Sendable, Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "favicon"

    public var id: Int64?
    public var host: String
    public var png: Data
    public var sha256: String
    public var updatedAt: Timestamp

    public init(id: Int64? = nil, host: String, png: Data, sha256: String, updatedAt: Timestamp) {
        self.id = id
        self.host = host
        self.png = png
        self.sha256 = sha256
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// Why an entry left the sidebar for the Archive (schema v7, Phase 4.1a).
public enum ArchiveReason: String, Hashable, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    /// The sweep: a Today tab untouched for `Settings.archiveAfterHours` (spec §A.7).
    case auto
    /// Clear (⇧⌘K).
    case clear
    /// Its space was deleted (B-15).
    case spaceDeleted
    /// Its window closed (Today tabs per window, 4.8a).
    case windowClosed
    /// "Archive" / "Archive Below" in the context menu.
    case manual
}

/// One archived tab (spec §A.7, §H): what the Library lists and Restore
/// brings back as a Today tab of its space. The id is the entry's id, so an
/// Undo or ⇧⌘T that puts the entry back finds its row.
public struct ArchivedEntry: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "archive"

    public var id: UUID
    public var url: String
    public var title: String?
    /// Row in `favicon` (a cache, as on `Entry`).
    public var faviconID: Int64?
    /// The space it was in; `nil` for an essential, or a space that was
    /// deleted later (restore then goes to the active space).
    public var spaceID: UUID?
    public var profileID: UUID
    public var archivedAt: Timestamp
    public var reason: ArchiveReason
    /// The entry's back/forward list (`Entry.navigationState`), so a restore
    /// goes Back where the tab was.
    public var navigationState: Data?

    public init(id: UUID = UUID(), url: String, title: String? = nil, faviconID: Int64? = nil, spaceID: UUID?,
                profileID: UUID, archivedAt: Timestamp, reason: ArchiveReason, navigationState: Data? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.faviconID = faviconID
        self.spaceID = spaceID
        self.profileID = profileID
        self.archivedAt = archivedAt
        self.reason = reason
        self.navigationState = navigationState
    }

    /// The row for `entry`, or `nil` when it has nothing to bring back (a
    /// folder, or an entry that never had a URL).
    public init?(_ entry: Entry, reason: ArchiveReason, at time: Timestamp) {
        guard entry.kind != .folder, let url = entry.currentURL, !url.isEmpty else { return nil }
        self.init(id: entry.id, url: url, title: entry.customLabel ?? entry.liveTitle ?? entry.storedTitle,
                  faviconID: entry.faviconID, spaceID: entry.spaceID, profileID: entry.profileID, archivedAt: time,
                  reason: reason, navigationState: entry.navigationState)
    }

    /// The row's title, else its URL.
    public var displayTitle: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? url }

    /// The URL's host without "www." (the Library's domain column).
    public var domain: String {
        guard let host = URL(string: url)?.host() else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// How a routing rule matches a URL (spec §B; `RoutingRules`).
public enum RoutingMatch: String, Hashable, Sendable, Codable, CaseIterable, DatabaseValueConvertible {
    /// The pattern appears in the full URL string, ignoring case.
    case contains
    /// The URL's host is the pattern, ignoring case and a leading "www.".
    case equals
    /// `NSRegularExpression` over the full URL string.
    case regex
}

/// One space routing rule (schema v8, Phase 4.2; spec §B): a link whose URL
/// matches opens in `targetSpaceID`. Rules are evaluated in `position` order
/// and the first enabled match wins.
public struct RoutingRule: Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "routing_rule"

    public var id: UUID
    public var match: RoutingMatch
    public var pattern: String
    public var targetSpaceID: UUID
    public var position: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), match: RoutingMatch, pattern: String, targetSpaceID: UUID, position: Int = 0,
                enabled: Bool = true) {
        self.id = id
        self.match = match
        self.pattern = pattern
        self.targetSpaceID = targetSpaceID
        self.position = position
        self.enabled = enabled
    }
}

/// Spec §A.3 `sidebar.permanentCloseBehavior` (Zen's values).
public enum PermanentCloseBehavior: String, Hashable, Sendable, Codable, CaseIterable {
    case resetUnloadSwitch = "reset-unload-switch"
    case unloadSwitch = "unload-switch"
    case resetSwitch = "reset-switch"
    case switchOnly = "switch"
    case reset
    case close
}

/// User settings, one JSON document in `kv`. Unknown or missing keys decode
/// to defaults so later phases can add settings without a migration.
public struct Settings: Hashable, Sendable, Codable {
    public var permanentCloseBehavior: PermanentCloseBehavior = .resetUnloadSwitch
    /// Today tabs untouched this long are archived (spec §A.7; 12, 24, 168, 720).
    public var archiveAfterHours: Int = 12
    /// Search suggestions from the engine while typing in the palette: on by
    /// default, the off switch in Settings (user decision 2026-10-03; CLAUDE.md).
    public var searchSuggestions: Bool = true
    /// The default search engine's identifier (`google`, `duckduckgo`, `kagi`);
    /// Google until the first-run choice (Phase 2.8).
    public var searchEngine: String = "google"
    /// The one-time "Logins and cookies won't carry over" warning was
    /// confirmed (moving a tab to a space of another profile, spec §B).
    public var crossProfileMoveWarned: Bool = false
    /// Where downloads are saved, a folder path; `nil` is the user's
    /// Downloads folder (spec §F, ROADMAP 2.6 task 1).
    public var downloadDirectory: String?
    /// View ▸ Show Toolbar: the 36 pt bar with Back, Forward, Reload and the
    /// full URL across the card's top (spec §E); off by default.
    public var showsToolbar: Bool = false
    /// Links ▸ "Open links to other sites from pinned tabs in Peek" (spec §A.4; on by default).
    public var peekOffSiteLinks: Bool = true
    /// Appearance ▸ Sidebar: the window side the sidebar docks on (Settings v0, ROADMAP 2.8).
    public var sidebarSide: SidebarSide = .left
    /// Appearance ▸ Appearance: follow the system, or always light or dark (Settings v0).
    public var appearance: AppearanceSetting = .system
    /// The first-run card in the sidebar (search engine, default browser,
    /// the two opt-ins) was finished; Settings ▸ General shows it again (ROADMAP 2.8 task 4).
    public var firstRunDone: Bool = false
    /// Crash reports to Sentry: off unless the user turns it on (first run or
    /// Settings ▸ Privacy); while off the SDK is never started (ROADMAP 2.8 task 5).
    public var crashReports: Bool = false
    /// Sparkle's scheduled update checks: off unless the user turns them on;
    /// while off the updater is not started at launch (ROADMAP 2.8 task 5).
    public var automaticUpdateChecks: Bool = false
    /// Profiles whose Chapter 2 history was imported into the engine's
    /// history (Phase 3.5, once per profile; the local tables go in 3.9).
    public var historyImportedProfiles: [UUID] = []
    /// The last extension update check (Phase 3.6a: once a day while an
    /// extension is installed, on the host's timer); kept so a relaunch does
    /// not check again at once. `nil` until the first extension is installed.
    public var extensionsLastUpdateCheck: Date?
    /// Links ▸ "Route links between spaces" (spec §B): a link opened from a
    /// page as a new tab goes to the space a routing rule names. Off by default.
    public var routeLinksBetweenSpaces: Bool = false
    /// Links ▸ "Open external links in": a space, or `nil` for the Most
    /// Recent Space (the default; spec §B). Used when no rule matches; a
    /// space that no longer exists counts as `nil`.
    public var externalLinksSpaceID: UUID?
    /// Settings ▸ Shortcuts (4.4a): action id (`MenuItemSpec.id`, e.g.
    /// "togglePin:") → key ("⌥⌘P"; `""` for no key). An absent id keeps the
    /// default of `docs/shortcuts.md`; `UIKitCore.ShortcutTable` reads it.
    public var shortcutOverrides: [String: String] = [:]
    /// Settings ▸ Search (4.4a): the engines list, `nil` for Room's built-in
    /// list (`Omnibox.SearchEngines.builtIn`); written whole on the first edit.
    public var searchEngines: [SearchEngineSetting]?
    /// Settings ▸ Search: each profile's default engine (profile id string →
    /// engine id); a profile without one uses `searchEngine` (the first-run choice).
    public var searchEngineByProfile: [String: String] = [:]
    /// Settings ▸ Downloads (4.4a): a save panel for every download instead of the folder.
    public var askWhereToSave: Bool = false
    /// Settings ▸ Downloads (4.4a): PDFs open in Room's viewer (`true`, Chrome's
    /// default) or download; stored now, read by 4.7a.
    public var pdfsOpenInRoom: Bool = true
    /// Settings ▸ Extensions (4.5): the extensions allowed in incognito, per
    /// profile (profile id string → extension ids); stored now, applied by
    /// 4.8b's incognito window (Chrome's own default: none allowed).
    public var extensionsInIncognito: [String: [String]] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case permanentCloseBehavior, archiveAfterHours, searchSuggestions, searchEngine, crossProfileMoveWarned, downloadDirectory
        case showsToolbar, peekOffSiteLinks, sidebarSide, appearance, firstRunDone, crashReports, automaticUpdateChecks
        case historyImportedProfiles, extensionsLastUpdateCheck, routeLinksBetweenSpaces, externalLinksSpaceID
        case shortcutOverrides, searchEngines, searchEngineByProfile, askWhereToSave, pdfsOpenInRoom
        case extensionsInIncognito
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        permanentCloseBehavior = (try? container.decodeIfPresent(PermanentCloseBehavior.self, forKey: .permanentCloseBehavior))
            .flatMap { $0 } ?? defaults.permanentCloseBehavior
        archiveAfterHours = (try? container.decodeIfPresent(Int.self, forKey: .archiveAfterHours)).flatMap { $0 }
            ?? defaults.archiveAfterHours
        searchSuggestions = (try? container.decodeIfPresent(Bool.self, forKey: .searchSuggestions)).flatMap { $0 }
            ?? defaults.searchSuggestions
        searchEngine = (try? container.decodeIfPresent(String.self, forKey: .searchEngine)).flatMap { $0 } ?? defaults.searchEngine
        crossProfileMoveWarned = (try? container.decodeIfPresent(Bool.self, forKey: .crossProfileMoveWarned)).flatMap { $0 }
            ?? defaults.crossProfileMoveWarned
        downloadDirectory = (try? container.decodeIfPresent(String.self, forKey: .downloadDirectory)).flatMap { $0 }
        showsToolbar = (try? container.decodeIfPresent(Bool.self, forKey: .showsToolbar)).flatMap { $0 } ?? defaults.showsToolbar
        peekOffSiteLinks = (try? container.decodeIfPresent(Bool.self, forKey: .peekOffSiteLinks)).flatMap { $0 } ?? defaults.peekOffSiteLinks
        sidebarSide = (try? container.decodeIfPresent(SidebarSide.self, forKey: .sidebarSide)).flatMap { $0 } ?? defaults.sidebarSide
        appearance = (try? container.decodeIfPresent(AppearanceSetting.self, forKey: .appearance)).flatMap { $0 } ?? defaults.appearance
        firstRunDone = (try? container.decodeIfPresent(Bool.self, forKey: .firstRunDone)).flatMap { $0 } ?? defaults.firstRunDone
        crashReports = (try? container.decodeIfPresent(Bool.self, forKey: .crashReports)).flatMap { $0 } ?? defaults.crashReports
        automaticUpdateChecks = (try? container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks)).flatMap { $0 }
            ?? defaults.automaticUpdateChecks
        historyImportedProfiles = (try? container.decodeIfPresent([UUID].self, forKey: .historyImportedProfiles)).flatMap { $0 }
            ?? defaults.historyImportedProfiles
        extensionsLastUpdateCheck = (try? container.decodeIfPresent(Date.self, forKey: .extensionsLastUpdateCheck)).flatMap { $0 }
        routeLinksBetweenSpaces = (try? container.decodeIfPresent(Bool.self, forKey: .routeLinksBetweenSpaces)).flatMap { $0 }
            ?? defaults.routeLinksBetweenSpaces
        externalLinksSpaceID = (try? container.decodeIfPresent(UUID.self, forKey: .externalLinksSpaceID)).flatMap { $0 }
        shortcutOverrides = (try? container.decodeIfPresent([String: String].self, forKey: .shortcutOverrides)).flatMap { $0 }
            ?? defaults.shortcutOverrides
        searchEngines = (try? container.decodeIfPresent([SearchEngineSetting].self, forKey: .searchEngines)).flatMap { $0 }
        searchEngineByProfile = (try? container.decodeIfPresent([String: String].self, forKey: .searchEngineByProfile)).flatMap { $0 }
            ?? defaults.searchEngineByProfile
        askWhereToSave = (try? container.decodeIfPresent(Bool.self, forKey: .askWhereToSave)).flatMap { $0 } ?? defaults.askWhereToSave
        pdfsOpenInRoom = (try? container.decodeIfPresent(Bool.self, forKey: .pdfsOpenInRoom)).flatMap { $0 } ?? defaults.pdfsOpenInRoom
        extensionsInIncognito = (try? container.decodeIfPresent([String: [String]].self, forKey: .extensionsInIncognito)).flatMap { $0 }
            ?? defaults.extensionsInIncognito
    }

    /// Whether `extensionID` of profile `profileID` may run in that profile's incognito window (4.5, for 4.8b).
    public func allowsInIncognito(_ extensionID: String, profile profileID: UUID) -> Bool {
        extensionsInIncognito[profileID.uuidString]?.contains(extensionID) == true
    }

    public mutating func setAllowsInIncognito(_ allowed: Bool, _ extensionID: String, profile profileID: UUID) {
        var ids = extensionsInIncognito[profileID.uuidString] ?? []
        ids.removeAll { $0 == extensionID }
        if allowed { ids.append(extensionID) }
        extensionsInIncognito[profileID.uuidString] = ids.isEmpty ? nil : ids
    }
}

/// A search engine in Settings ▸ Search (4.4a): the URLs hold `{searchTerms}`
/// where the query goes (Chrome's template word; Settings shows it as `%s`).
public struct SearchEngineSetting: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    /// Typed in the palette and followed by Tab, searches this engine ("ddg").
    public var keyword: String
    public var searchURL: String
    /// The suggestions endpoint (OpenSearch JSON), if any.
    public var suggestURL: String?

    public init(id: String, name: String, keyword: String, searchURL: String, suggestURL: String? = nil) {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.searchURL = searchURL
        self.suggestURL = suggestURL
    }
}

/// The side of the window the sidebar docks on; the traffic lights stay where AppKit puts them.
public enum SidebarSide: String, Hashable, Sendable, Codable, CaseIterable {
    case left, right
}

/// Light, dark, or the system's choice.
public enum AppearanceSetting: String, Hashable, Sendable, Codable, CaseIterable {
    case system, light, dark
}

/// Everything the state pipeline persists, as one value.
public struct RoomState: Hashable, Sendable, Codable {
    public var profiles: [Profile] = []
    public var spaces: [Space] = []
    public var entries: [Entry] = []
    public var splitGroups: [SplitGroup] = []
    public var windows: [WindowState] = []
    public var windowSpaces: [WindowSpace] = []
    public var settings = Settings()
    /// The Archive (schema v7). Written with the state, so archiving an entry
    /// and removing it land in one transaction; left out of the JSON
    /// snapshot (`StateSnapshot.encoded`).
    public var archive: [ArchivedEntry] = []
    /// Space routing rules (schema v8), in the snapshot too (they are small).
    public var routingRules: [RoutingRule] = []

    public init(
        profiles: [Profile] = [], spaces: [Space] = [], entries: [Entry] = [], splitGroups: [SplitGroup] = [],
        windows: [WindowState] = [], windowSpaces: [WindowSpace] = [], settings: Settings = Settings(),
        archive: [ArchivedEntry] = [], routingRules: [RoutingRule] = []
    ) {
        self.profiles = profiles
        self.spaces = spaces
        self.entries = entries
        self.splitGroups = splitGroups
        self.windows = windows
        self.windowSpaces = windowSpaces
        self.settings = settings
        self.archive = archive
        self.routingRules = routingRules
    }

    private enum CodingKeys: String, CodingKey {
        case profiles, spaces, entries, splitGroups, windows, windowSpaces, settings, archive, routingRules
    }

    /// Snapshots written before v7 (and every snapshot since: the archive is
    /// left out of them) have no `archive`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([Profile].self, forKey: .profiles)
        spaces = try container.decode([Space].self, forKey: .spaces)
        entries = try container.decode([Entry].self, forKey: .entries)
        splitGroups = try container.decode([SplitGroup].self, forKey: .splitGroups)
        windows = try container.decode([WindowState].self, forKey: .windows)
        windowSpaces = try container.decode([WindowSpace].self, forKey: .windowSpaces)
        settings = try container.decode(Settings.self, forKey: .settings)
        archive = try container.decodeIfPresent([ArchivedEntry].self, forKey: .archive) ?? []
        // Snapshots written before v8 have no rules.
        routingRules = try container.decodeIfPresent([RoutingRule].self, forKey: .routingRules) ?? []
    }

    public var isEmpty: Bool { profiles.isEmpty }

    /// Arrays sorted by primary key, so equal states compare and hash equal
    /// whatever order the store or the database produced them in.
    public func canonical() -> RoomState {
        var copy = self
        copy.profiles.sort { $0.id.uuidString < $1.id.uuidString }
        copy.spaces.sort { $0.id.uuidString < $1.id.uuidString }
        copy.entries.sort { $0.id.uuidString < $1.id.uuidString }
        copy.splitGroups.sort { $0.id.uuidString < $1.id.uuidString }
        copy.windows.sort { $0.id.uuidString < $1.id.uuidString }
        copy.windowSpaces.sort { ($0.windowID.uuidString, $0.spaceID.uuidString) < ($1.windowID.uuidString, $1.spaceID.uuidString) }
        copy.archive.sort { $0.id.uuidString < $1.id.uuidString }
        copy.routingRules.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }

    /// Canonical JSON (sorted keys), used for snapshots and content hashes.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(canonical())
    }
}
