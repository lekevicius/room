import Foundation
import Model

/// What the user typed.
public struct OmniboxInput: Hashable, Sendable {
    public var text: String
    /// Set when the last edit was a deletion: inline completion would put
    /// back what the user just removed (Chromium's `prevent_inline_autocomplete`).
    public var preventsInlineCompletion: Bool

    public init(text: String, preventsInlineCompletion: Bool = false) {
        self.text = text
        self.preventsInlineCompletion = preventsInlineCompletion
    }

    public var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isEmpty: Bool { trimmed.isEmpty }
}

/// Where a match came from. The 2.4b providers are named here so the
/// scorer's bands (`Relevance`) cover them from the start.
public enum ProviderKind: String, Hashable, Sendable, CaseIterable {
    /// What you typed: the URL it fixes up to, or a search for it.
    case verbatim
    /// Today tabs across all spaces.
    case openTabs
    /// Pinned entries (all spaces) and essentials.
    case pinned
    /// 2.4b: the FTS5 history table with frecency.
    case history
    /// 2.4b: the search engine's suggestions (network; off switch).
    case suggest
    /// 2.4b: the command registry (`>` or Tab from an empty field).
    case commands
}

/// The palette's groups, in display order (spec §C): the top hit, then each
/// group with its matches by relevance.
public enum MatchGroup: Int, Hashable, Sendable, CaseIterable, Comparable {
    case topHit, openTabs, pinned, history, search, commands

    public static func < (lhs: MatchGroup, rhs: MatchGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The group a provider's matches belong to when they are not the top hit.
    public init(provider: ProviderKind) {
        switch provider {
        case .verbatim, .suggest: self = .search
        case .openTabs: self = .openTabs
        case .pinned: self = .pinned
        case .history: self = .history
        case .commands: self = .commands
        }
    }
}

/// What committing a match does; the palette turns it into tab operations
/// with the modifier keys (spec §C, `PaletteSemantics`).
public enum MatchAction: Hashable, Sendable {
    /// Load a URL (typed, history, a suggestion that is a URL).
    case navigate(url: String)
    /// Search for `query`; `url` is the engine's results page.
    case search(query: String, url: String)
    /// An existing entry: switch to it (its space first); ⌘ opens a copy of `url`.
    case switchToEntry(id: UUID, space: UUID?, url: String?)
    /// 2.4b: a registry command by identifier.
    case command(id: String)

    /// The page this action ends on, if it is a page (dedupe key, copies).
    public var url: String? {
        switch self {
        case .navigate(let url): url
        case .search(_, let url): url
        case .switchToEntry(_, _, let url): url
        case .command: nil
        }
    }
}

/// The row's icon. Entries resolve to their favicon in the palette.
public enum MatchIcon: Hashable, Sendable {
    case entry(UUID)
    case search
    case url
    /// 2.4b: a command's SF Symbol.
    case symbol(String)
}

/// One suggestion.
public struct OmniboxMatch: Hashable, Sendable, Identifiable {
    /// Stable across keystrokes for the same suggestion (row identity).
    public var id: String
    public var provider: ProviderKind
    /// Chromium-like relevance, 0…1500 (`Relevance` holds the bands).
    public var relevance: Int
    public var action: MatchAction
    public var title: String
    /// The URL or domain under the title.
    public var detail: String?
    public var icon: MatchIcon
    /// The space name chip of a tab or pinned entry in another space (spec §C).
    public var spaceName: String?
    /// Text that completes the input in the field when this is the top hit
    /// (spec §C: from history only, 2.4b; the scorer drops it otherwise).
    public var inlineCompletion: String?
    /// The scorer never drops it for the 8-row cap (the search row for what
    /// was typed: there is always a way to search, spec §C group 5).
    public var keepsSlot: Bool
    /// 2.4b: history rows can be removed (⇧Delete, ⌘⌥Delete, the × on hover).
    public var isDeletable: Bool
    /// Set by the scorer: the group this match is shown in.
    public internal(set) var group: MatchGroup

    public init(id: String, provider: ProviderKind, relevance: Int, action: MatchAction, title: String, detail: String? = nil,
                icon: MatchIcon, spaceName: String? = nil, inlineCompletion: String? = nil, keepsSlot: Bool = false,
                isDeletable: Bool = false) {
        self.id = id
        self.provider = provider
        self.relevance = relevance
        self.action = action
        self.title = title
        self.detail = detail
        self.icon = icon
        self.spaceName = spaceName
        self.inlineCompletion = inlineCompletion
        self.keepsSlot = keepsSlot
        self.isDeletable = isDeletable
        group = MatchGroup(provider: provider)
    }

    /// Matches that end on the same page are one suggestion (spec §C).
    public var dedupeKey: String {
        if case .command(let id) = action { return "command:" + id }
        return action.url.map(URLNormalization.normalized) ?? id
    }
}

/// One sidebar entry as the providers see it: a value snapshot the palette
/// builds from the store when it opens (labels per spec §I.3).
public struct OmniboxEntry: Hashable, Sendable {
    public var id: UUID
    public var kind: EntryKind
    public var title: String
    /// Where the entry's page is now (`liveURL ?? storedURL`).
    public var url: String?
    /// A permanent entry's pinned URL (also matched: "the GitHub pin").
    public var storedURL: String?
    public var spaceID: UUID?
    public var spaceName: String?
    public var lastActiveAt: Date?

    public init(id: UUID, kind: EntryKind, title: String, url: String?, storedURL: String? = nil, spaceID: UUID?,
                spaceName: String? = nil, lastActiveAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.url = url
        self.storedURL = storedURL
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.lastActiveAt = lastActiveAt
    }
}

/// What the providers know besides the input.
public struct OmniboxContext: Sendable {
    public let entries: [OmniboxEntry]
    /// Lowercased titles, hosts and URLs, computed once per context (the
    /// palette builds one when it opens), not per keystroke.
    let keys: [EntryKeys]
    public var activeSpaceID: UUID?
    /// The entry in the card: never suggested (switching to it does nothing).
    public var currentEntryID: UUID?
    public var searchEngine: SearchEngine
    /// The recency clock (tests inject one).
    public var now: Date

    /// `previous`: an earlier context whose precomputed keys are reused for
    /// entries that did not change (the palette reopens on mostly the same sidebar).
    public init(entries: [OmniboxEntry] = [], activeSpaceID: UUID? = nil, currentEntryID: UUID? = nil,
                searchEngine: SearchEngine = .google, now: Date = Date(), reusingKeysFrom previous: OmniboxContext? = nil) {
        self.entries = entries
        if let previous {
            var known: [UUID: (entry: OmniboxEntry, keys: EntryKeys)] = [:]
            for (entry, keys) in zip(previous.entries, previous.keys) { known[entry.id] = (entry, keys) }
            keys = entries.map { entry in
                if let old = known[entry.id], old.entry.url == entry.url, old.entry.storedURL == entry.storedURL, old.entry.title == entry.title {
                    return old.keys
                }
                return EntryKeys(entry)
            }
        } else {
            keys = entries.map(EntryKeys.init)
        }
        self.activeSpaceID = activeSpaceID
        self.currentEntryID = currentEntryID
        self.searchEngine = searchEngine
        self.now = now
    }
}

/// What matching needs from an entry, precomputed.
struct EntryKeys: Sendable {
    var title: String
    /// Hosts without "www.".
    var hosts: [String]
    /// URLs lowercased, without "http(s)://".
    var bareURLs: [String]
    /// `URLNormalization.normalized` of each URL (exact matches).
    var normalizedURLs: [String]

    init(_ entry: OmniboxEntry) {
        let urls = [entry.url, entry.storedURL].compactMap { $0 }
        title = entry.title.lowercased()
        hosts = urls.compactMap { URLComponents(string: $0)?.host?.lowercased() }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        bareURLs = urls.map { url in
            var lower = url.lowercased()
            for prefix in ["https://", "http://"] where lower.hasPrefix(prefix) {
                lower.removeFirst(prefix.count)
                break
            }
            return lower
        }
        normalizedURLs = urls.map(URLNormalization.normalized)
    }
}
