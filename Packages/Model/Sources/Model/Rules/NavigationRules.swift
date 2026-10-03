import Foundation

/// What ⌘W does to an entry (spec §A.3, §A.7).
public struct CloseSteps: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Move the selection to the fallback (`NavigationRules.closeFallback`).
    public static let switchAway = CloseSteps(rawValue: 1 << 0)
    /// Drop the page (web process); the entry stays.
    public static let unload = CloseSteps(rawValue: 1 << 1)
    /// Navigate back to the stored URL on next load (live URL = stored URL).
    public static let reset = CloseSteps(rawValue: 1 << 2)
    /// Remove the entry from the sidebar.
    public static let remove = CloseSteps(rawValue: 1 << 3)
}

/// Where the selection goes when the selected entry closes.
public enum CloseFallback: Equatable, Sendable {
    case select(UUID)
    /// Permanent entry, nothing else to show: a blank Today tab + the palette (§A.3).
    case newTodayTabAndPalette
    /// Today tab, nothing else to show: the empty state ("Press ⌘T…", §A.7).
    case emptyState
}

/// Sidebar ordering, MRU and ⌘W rules, as pure functions.
public enum NavigationRules {
    /// ⌘W steps for an entry of `kind` under the user's preference.
    public static func closeSteps(for kind: EntryKind, behavior: PermanentCloseBehavior) -> CloseSteps {
        switch kind {
        case .today: return [.switchAway, .unload, .remove]
        case .folder: return []
        case .essential, .pinned:
            switch behavior {
            case .resetUnloadSwitch: return [.switchAway, .unload, .reset]
            case .unloadSwitch: return [.switchAway, .unload]
            case .resetSwitch: return [.switchAway, .reset]
            case .switchOnly: return [.switchAway]
            case .reset: return [.reset]
            case .close: return [.switchAway, .unload, .remove]
            }
        }
    }

    /// Entries most recently used first. Never-used entries come last in
    /// `order`'s (sidebar) order; ties keep sidebar order.
    public static func mruOrder(_ order: [Entry]) -> [Entry] {
        order.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastActiveAt, rhs.element.lastActiveAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// The selection after `closing` closes (§A.3 step 1, §A.7): the most
    /// recently used other entry of the space; else the first Today tab;
    /// else a new Today tab (permanent entries) or the empty state (Today).
    /// `order` is the space's sidebar order (`sidebarOrder`).
    public static func closeFallback(closing: Entry, order: [Entry]) -> CloseFallback {
        let others = order.filter { $0.id != closing.id && $0.kind != .folder }
        if let recent = mruOrder(others).first(where: { $0.lastActiveAt != nil }) {
            return .select(recent.id)
        }
        if let today = others.first(where: { $0.kind == .today }) {
            return .select(today.id)
        }
        return closing.kind == .today ? .emptyState : .newTodayTabAndPalette
    }

    /// The order ⌘1…⌘9 and ⌥⌘↑/↓ walk: essentials, then pinned depth-first
    /// (folders themselves are not selectable; children of collapsed folders
    /// are skipped, as they are not visible), then Today tabs.
    /// Each array must be sorted by `position`.
    public static func sidebarOrder(essentials: [Entry], pinnedRoot: [Entry], pinnedChildren: [UUID: [Entry]],
                                    today: [Entry], pinnedCollapsed: Bool = false) -> [Entry] {
        var result = essentials
        if !pinnedCollapsed {
            func walk(_ level: [Entry]) {
                for entry in level {
                    if entry.kind == .folder {
                        if !entry.isCollapsed { walk(pinnedChildren[entry.id] ?? []) }
                    } else {
                        result.append(entry)
                    }
                }
            }
            walk(pinnedRoot)
        }
        result.append(contentsOf: today)
        return result
    }

    /// ⇧⌘] / ⌥⌘↓ (`offset` 1) and ⇧⌘[ / ⌥⌘↑ (−1): the entry next to
    /// `selected` in `order` (the sidebar order), wrapping around at the
    /// ends. With nothing selected (or the selection not in `order`, e.g. a
    /// child peeking out of a collapsed folder) it is the first entry for a
    /// forward step and the last for a backward one.
    public static func adjacent(to selected: UUID?, offset: Int, in order: [Entry]) -> Entry? {
        guard !order.isEmpty, offset != 0 else { return nil }
        guard let index = order.firstIndex(where: { $0.id == selected }) else {
            return offset > 0 ? order.first : order.last
        }
        let count = order.count
        return order[((index + offset) % count + count) % count]
    }

    /// Where a tab opened from a page goes in the Today list `today` (§A.7):
    /// right below a Today opener; below `lastRelated`, the previous tab the
    /// same opener opened, while the user has not switched tabs since
    /// (Firefox `insertRelatedAfterCurrent`, so ⌘-clicked links keep their
    /// order); at the top of Today for a permanent opener (as Duplicate).
    public static func relatedTabIndex(opener: Entry, lastRelated: UUID?, today: [Entry]) -> Int {
        if let lastRelated, let index = today.firstIndex(where: { $0.id == lastRelated }) { return index + 1 }
        if opener.kind == .today, let index = today.firstIndex(where: { $0.id == opener.id }) { return index + 1 }
        return 0
    }

    /// ⌘`digit` target: 1…8 = the Nth item, 9 = the last (Chrome/Arc).
    public static func digitTarget(_ digit: Int, in order: [Entry]) -> Entry? {
        switch digit {
        case 1...8: order.indices.contains(digit - 1) ? order[digit - 1] : nil
        case 9: order.last
        default: nil
        }
    }
}
