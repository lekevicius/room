import Foundation

// The neutral values the readers return (Phase 4.3a): what another browser
// holds, before any decision about where it goes in Room (`ImportPlanner`).

/// A bookmark, an Arc tab or a Netscape link.
public struct ImportedLink: Hashable, Sendable {
    public var url: String
    public var title: String
    public var dateAdded: Date?
    /// The browser's own id (Chrome's `guid`, Safari's `WebBookmarkUUID`, Arc's item id).
    public var guid: String?

    public init(url: String, title: String, dateAdded: Date? = nil, guid: String? = nil) {
        self.url = url
        self.title = title
        self.dateAdded = dateAdded
        self.guid = guid
    }
}

public struct ImportedFolder: Hashable, Sendable {
    public var title: String
    public var children: [ImportedNode]
    public var dateAdded: Date?
    public var guid: String?

    public init(title: String, children: [ImportedNode], dateAdded: Date? = nil, guid: String? = nil) {
        self.title = title
        self.children = children
        self.dateAdded = dateAdded
        self.guid = guid
    }
}

public indirect enum ImportedNode: Hashable, Sendable {
    case link(ImportedLink)
    case folder(ImportedFolder)

    /// Links in this subtree.
    public var linkCount: Int {
        switch self {
        case .link: 1
        case .folder(let folder): folder.children.reduce(0) { $0 + $1.linkCount }
        }
    }

    /// Folders in this subtree, itself included.
    public var folderCount: Int {
        switch self {
        case .link: 0
        case .folder(let folder): 1 + folder.children.reduce(0) { $0 + $1.folderCount }
        }
    }
}

/// Something a reader or the planner left out, and why (the sheet lists them).
public struct SkippedItem: Hashable, Sendable {
    public var item: String
    public var reason: String

    public init(_ item: String, reason: String) {
        self.item = item
        self.reason = reason
    }
}

/// Bookmarks in the three places every format has: the bar (Chrome's
/// "Bookmarks bar", Safari's Favourites bar, Netscape's
/// `PERSONAL_TOOLBAR_FOLDER`), everything else ("Other bookmarks", Safari's
/// menu, its Reading List as a folder, its other top-level folders), and
/// Chrome's "Mobile bookmarks".
public struct ImportedBookmarks: Hashable, Sendable {
    public var bar: [ImportedNode]
    public var other: [ImportedNode]
    public var mobile: [ImportedNode]
    public var skipped: [SkippedItem]

    public init(bar: [ImportedNode] = [], other: [ImportedNode] = [], mobile: [ImportedNode] = [], skipped: [SkippedItem] = []) {
        self.bar = bar
        self.other = other
        self.mobile = mobile
        self.skipped = skipped
    }

    public var links: Int { (bar + other + mobile).reduce(0) { $0 + $1.linkCount } }
    public var folders: Int { (bar + other + mobile).reduce(0) { $0 + $1.folderCount } }
}

/// How a visit began (Chrome's core `ui::PageTransition`; Safari has none).
public enum ImportedTransition: String, Hashable, Sendable {
    case link, typed, bookmark, generated, keyword, formSubmit, reload, other
}

public struct ImportedVisit: Hashable, Sendable {
    public var time: Date
    public var transition: ImportedTransition

    public init(time: Date, transition: ImportedTransition) {
        self.time = time
        self.transition = transition
    }
}

public struct ImportedHistoryURL: Hashable, Sendable {
    public var url: String
    public var title: String
    /// The browser's own counts (Chrome's `visit_count`, `typed_count`; Safari's `visit_count`, no typed count).
    public var visitCount: Int
    public var typedCount: Int
    public var lastVisit: Date?
    /// Oldest first.
    public var visits: [ImportedVisit]

    public init(url: String, title: String, visitCount: Int, typedCount: Int, lastVisit: Date?, visits: [ImportedVisit]) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.typedCount = typedCount
        self.lastVisit = lastVisit
        self.visits = visits
    }
}

public struct ImportedHistory: Hashable, Sendable {
    public var urls: [ImportedHistoryURL]
    public var skipped: [SkippedItem]

    public init(urls: [ImportedHistoryURL] = [], skipped: [SkippedItem] = []) {
        self.urls = urls
        self.skipped = skipped
    }

    public var visits: Int { urls.reduce(0) { $0 + $1.visits.count } }
}

/// One installed extension (Chrome-family `Preferences`).
public struct ImportedExtension: Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var fromWebStore: Bool
    public var enabled: Bool

    public init(id: String, name: String, version: String, fromWebStore: Bool, enabled: Bool) {
        self.id = id
        self.name = name
        self.version = version
        self.fromWebStore = fromWebStore
        self.enabled = enabled
    }
}

public struct ImportedExtensions: Hashable, Sendable {
    public var extensions: [ImportedExtension]
    public var skipped: [SkippedItem]

    public init(extensions: [ImportedExtension] = [], skipped: [SkippedItem] = []) {
        self.extensions = extensions
        self.skipped = skipped
    }
}

/// An Arc profile: the default one, or a Chromium profile directory with the
/// name `Local State` gives it.
public struct ImportedProfile: Hashable, Sendable {
    /// "default", or the directory's basename ("Profile 1").
    public var key: String
    public var name: String
    public var isDefault: Bool

    public init(key: String, name: String, isDefault: Bool) {
        self.key = key
        self.name = name
        self.isDefault = isDefault
    }

    public static let defaultKey = "default"
}

public struct ImportedSpace: Hashable, Sendable {
    public var id: String
    public var name: String
    /// An emoji, when Arc has one.
    public var icon: String?
    /// `#RRGGBB`.
    public var colors: [String]
    public var profileKey: String
    public var pinned: [ImportedNode]
    public var today: [ImportedLink]

    public init(id: String, name: String, icon: String? = nil, colors: [String] = [], profileKey: String,
                pinned: [ImportedNode] = [], today: [ImportedLink] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colors = colors
        self.profileKey = profileKey
        self.pinned = pinned
        self.today = today
    }
}

/// Arc's sidebar: profiles, spaces (pinned trees and Today tabs) and the
/// essentials of each profile.
public struct ImportedSidebar: Hashable, Sendable {
    public var profiles: [ImportedProfile]
    public var spaces: [ImportedSpace]
    /// Per profile key, in grid order.
    public var essentials: [String: [ImportedLink]]
    public var skipped: [SkippedItem]

    public init(profiles: [ImportedProfile] = [], spaces: [ImportedSpace] = [], essentials: [String: [ImportedLink]] = [:],
                skipped: [SkippedItem] = []) {
        self.profiles = profiles
        self.spaces = spaces
        self.essentials = essentials
        self.skipped = skipped
    }

    public var pinnedLinks: Int { spaces.reduce(0) { $0 + $1.pinned.reduce(0) { $0 + $1.linkCount } } }
    public var folders: Int { spaces.reduce(0) { $0 + $1.pinned.reduce(0) { $0 + $1.folderCount } } }
    public var todayTabs: Int { spaces.reduce(0) { $0 + $1.today.count } }
    public var essentialsCount: Int { essentials.values.reduce(0) { $0 + $1.count } }
}

/// The formats Room reads.
public enum ImportFormat: String, Hashable, Sendable {
    case chromeBookmarks = "Bookmarks"
    case safariBookmarks = "Bookmarks.plist"
    case netscapeBookmarks = "bookmarks HTML"
    case chromeHistory = "History"
    case safariHistory = "History.db"
    case chromePreferences = "Preferences"
    case chromeLocalState = "Local State"
    case arcSidebar = "StorableSidebar.json"
}

/// A file a reader could not use. `message` is the sheet's line.
public struct ImportError: Error, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The file is missing or cannot be read (permissions: Safari's files need the open panel).
        case unreadable
        /// The file is not in the format, or its structure is not the one expected.
        case malformed
    }

    public var kind: Kind
    public var format: ImportFormat
    public var detail: String

    public init(_ kind: Kind, _ format: ImportFormat, _ detail: String) {
        self.kind = kind
        self.format = format
        self.detail = detail
    }

    public var message: String {
        switch kind {
        case .unreadable: "\(format.rawValue) could not be read: \(detail)"
        case .malformed: "\(format.rawValue) is not in the expected format: \(detail)"
        }
    }
}

/// Times as the formats store them.
public enum ImportTime {
    /// Seconds from 1601-01-01 (Windows/WebKit epoch) to 1970-01-01.
    static let webKitOffset: Double = 11_644_473_600

    /// Chromium's microseconds since 1601 (`base::Time::ToDeltaSinceWindowsEpoch`); `nil` for 0.
    public static func webKit(_ microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - webKitOffset)
    }

    /// The same as a decimal string (Chrome's `Bookmarks` writes them so).
    public static func webKit(_ string: String?) -> Date? {
        string.flatMap { Int64($0) }.flatMap(webKit)
    }

    /// Safari: seconds since 2001-01-01 (Core Foundation's reference date).
    public static func safari(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    /// Netscape `ADD_DATE`: seconds since 1970 (some exporters write microseconds or milliseconds).
    public static func netscape(_ string: String?) -> Date? {
        guard let string, let value = Double(string), value > 0 else { return nil }
        if value > 1e14 { return Date(timeIntervalSince1970: value / 1_000_000) }
        if value > 1e11 { return Date(timeIntervalSince1970: value / 1_000) }
        return Date(timeIntervalSince1970: value)
    }
}
