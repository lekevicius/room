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

    public init(
        id: UUID = UUID(), kind: EntryKind, spaceID: UUID?, profileID: UUID, folderID: UUID? = nil,
        splitGroupID: UUID? = nil, position: Int = 0, storedURL: String? = nil, storedTitle: String? = nil,
        customLabel: String? = nil, customIcon: String? = nil, faviconID: Int64? = nil,
        isCollapsed: Bool = false, createdAt: Timestamp = .now, lastActiveAt: Timestamp? = nil,
        liveURL: String? = nil, liveTitle: String? = nil
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
    /// Pane sizes as fractions, one per member in member position order.
    public var ratios: [Double]

    public init(id: UUID = UUID(), layout: SplitLayout = .hbox, ratios: [Double] = []) {
        self.id = id
        self.layout = layout
        self.ratios = ratios
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

    public init() {}

    private enum CodingKeys: String, CodingKey { case permanentCloseBehavior, archiveAfterHours, searchSuggestions, searchEngine }

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
    }
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

    public init(
        profiles: [Profile] = [], spaces: [Space] = [], entries: [Entry] = [], splitGroups: [SplitGroup] = [],
        windows: [WindowState] = [], windowSpaces: [WindowSpace] = [], settings: Settings = Settings()
    ) {
        self.profiles = profiles
        self.spaces = spaces
        self.entries = entries
        self.splitGroups = splitGroups
        self.windows = windows
        self.windowSpaces = windowSpaces
        self.settings = settings
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
        return copy
    }

    /// Canonical JSON (sorted keys), used for snapshots and content hashes.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(canonical())
    }
}
