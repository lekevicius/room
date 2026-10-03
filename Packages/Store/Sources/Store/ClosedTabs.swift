import Foundation
import Model

/// A closed tab, for ⇧⌘T (spec §G "Reopen closed tab").
public enum ClosedTab: Equatable, Sendable {
    /// Entries one command removed (⌘W on a Today tab, Clear, Close Tabs
    /// Below / Other Tabs): reopened together, where they were.
    case removed([RemovedEntry])
    /// The page of a permanent entry that ⌘W unloaded or reset (the entry
    /// stays): the entry as it was, with the page's live URL and title.
    case page(Entry)
}

/// The window's reopen stack: newest last, at most `capacity` (Chrome's
/// `TabRestoreService` keeps 25).
public struct ClosedTabStack: Equatable, Sendable {
    public static let capacity = 25

    public private(set) var items: [ClosedTab] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    public mutating func push(_ tab: ClosedTab) {
        if case .removed(let entries) = tab, entries.isEmpty { return }
        items.append(tab)
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
    }

    public mutating func pop() -> ClosedTab? { items.popLast() }
}

extension SidebarStore {
    /// ⇧⌘T: puts a closed tab back and returns the entry to select, or `nil`
    /// when nothing of it can come back (its space, or the permanent entry,
    /// is gone). Removed entries return at their old positions (`restore`);
    /// a permanent entry gets its page's URL and title back as the live page.
    public func reopen(_ closed: ClosedTab) -> UUID? {
        switch closed {
        case .removed(let removed):
            restore(removed)
            return removed.sorted { $0.index < $1.index }.map(\.entry.id).first { entry($0) != nil }
        case .page(let before):
            guard entry(before.id) != nil else { return nil }
            if let url = before.liveURL { try? setLivePage(before.id, url: url, title: before.liveTitle) }
            return before.id
        }
    }
}
