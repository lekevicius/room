import Foundation
import Omnibox

/// Why the palette is open (spec §C).
nonisolated public enum PaletteMode: Equatable, Sendable {
    /// ⌘T: no tab exists until a commit.
    case new
    /// ⌘L or a click on the header's address field: the entry in the card,
    /// prefilled with `url` (its page's URL when it opened).
    case edit(entry: UUID, url: String)

    public var entry: UUID? {
        if case .edit(let entry, _) = self { entry } else { nil }
    }

    /// The text the field starts with.
    public var prefill: String {
        if case .edit(_, let url) = self { url } else { "" }
    }
}

/// The modifier held while committing (spec §C: Enter, ⌘Enter, ⌥Enter).
nonisolated public enum CommitModifier: Equatable, Sendable {
    case none
    /// ⌘: the other place: the current tab from ⌘T, a new tab from ⌘L, a copy of an entry.
    case command
    /// ⌥: a new tab in the background.
    case option
}

/// What a commit does to tabs.
nonisolated public enum CommitAction: Equatable, Sendable {
    /// A new Today tab (selected unless `background`).
    case openTab(url: String, background: Bool)
    /// Load `url` in the entry in the card.
    case navigateCurrent(url: String)
    /// ⌘L, Enter on the unchanged URL (Arc).
    case reloadCurrent
    /// Select an existing entry, showing its space first.
    case switchTo(entry: UUID, space: UUID?)
    /// Restore an archived tab to its space and select it (spec §H).
    case restoreArchived(id: UUID)
    /// Run a registry command (the palette closes first).
    case runCommand(id: String)
    /// Put a site-search chip in the field (the palette stays open).
    case enterSiteSearch(keyword: String)
    /// Nothing to commit (an empty field).
    case none
}

/// What Esc does.
nonisolated public enum EscapeAction: Equatable, Sendable {
    case close
    /// ⌘L with edited text: put the URL back, selected; the next Esc closes (spec §C "Esc restores").
    case restore(String)
}

/// The ⌘T / ⌘L table of spec §C as a pure function.
nonisolated public enum PaletteSemantics {
    /// - Parameters:
    ///   - action: the highlighted row's action (`nil`: no rows).
    ///   - textUnchanged: ⌘L and the field still holds the prefilled URL.
    ///   - hasCurrent: an entry is in the card (⌘Enter from ⌘T needs one).
    public static func commit(mode: PaletteMode, action: MatchAction?, textUnchanged: Bool, modifier: CommitModifier,
                              hasCurrent: Bool) -> CommitAction {
        if case .edit(_, let url) = mode, textUnchanged {
            switch modifier {
            case .none: return .reloadCurrent
            case .command: return .openTab(url: url, background: false)
            case .option: return .openTab(url: url, background: true)
            }
        }
        guard let action else { return .none }
        switch action {
        case .navigate(let url), .search(_, let url):
            switch (mode, modifier) {
            case (.new, .none): return .openTab(url: url, background: false)
            case (.new, .command): return hasCurrent ? .navigateCurrent(url: url) : .openTab(url: url, background: false)
            case (.edit, .none): return .navigateCurrent(url: url)
            case (.edit, .command): return .openTab(url: url, background: false)
            case (_, .option): return .openTab(url: url, background: true)
            }
        case .switchToEntry(let id, let space, let url):
            switch modifier {
            case .none: return .switchTo(entry: id, space: space)
            case .command: return url.map { .openTab(url: $0, background: false) } ?? .switchTo(entry: id, space: space)
            case .option: return url.map { .openTab(url: $0, background: true) } ?? .switchTo(entry: id, space: space)
            }
        case .restoreArchived(let id, let url):
            switch modifier {
            case .none: return .restoreArchived(id: id)
            case .command: return .openTab(url: url, background: false)
            case .option: return .openTab(url: url, background: true)
            }
        case .command(let id):
            return .runCommand(id: id)
        case .enterSiteSearch(let keyword):
            return .enterSiteSearch(keyword: keyword)
        case .pasteAndGo:
            // The palette reads the clipboard and commits what it holds instead.
            return .none
        }
    }

    /// B-102 (as Arc): what the field shows while ↑, ↓ or ⇥ select a row: the row's
    /// destination (its URL, or its query), so the field says where Return goes. `nil`:
    /// the typed text stays (the top hit, with its inline completion; commands, the
    /// site-search hint and Paste and Go, whose destinations are not text to edit).
    public static func selectionText(for action: MatchAction, isTopHit: Bool) -> String? {
        guard !isTopHit else { return nil }
        switch action {
        case .navigate(let url): return url
        case .search(let query, _): return query
        case .switchToEntry(_, _, let url): return url
        case .restoreArchived(_, let url): return url
        case .command, .enterSiteSearch, .pasteAndGo: return nil
        }
    }

    public static func escape(mode: PaletteMode, text: String) -> EscapeAction {
        if case .edit(_, let url) = mode, text != url { return .restore(url) }
        return .close
    }
}

/// Typed-but-uncommitted text per tab (spec §C: kept 45 s, Zen
/// `wait-to-clear`). The palette remembers it when it is dismissed with
/// edited text (click outside, ⌘L again, switching tabs) and offers it on
/// the next ⌘L on that tab within the window; Esc and commits forget it.
nonisolated public struct TypedTextMemory: Sendable {
    public var lifetime: TimeInterval
    private var stored: [UUID: (text: String, at: Date)] = [:]

    public init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    public mutating func remember(_ text: String, for entry: UUID, at date: Date) {
        stored[entry] = (text, date)
    }

    /// The remembered text if it is still fresh; it is used up either way.
    public mutating func take(for entry: UUID, at date: Date) -> String? {
        guard let item = stored.removeValue(forKey: entry) else { return nil }
        return date.timeIntervalSince(item.at) <= lifetime ? item.text : nil
    }

    public mutating func forget(_ entry: UUID) {
        stored[entry] = nil
    }
}
