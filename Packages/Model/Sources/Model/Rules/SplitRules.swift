import Foundation

/// Where a pane dropped on another pane goes (spec §D drop zones).
public enum SplitEdge: String, Hashable, Sendable, CaseIterable {
    case left, right, top, bottom

    /// Left and right sit side by side (`hbox`); top and bottom stack (`vbox`).
    public var isHorizontal: Bool { self == .left || self == .right }
    /// Before the target pane (left, top) or after it.
    public var isLeading: Bool { self == .left || self == .top }
}

/// Split view (spec §D) as pure functions: pane order, focus, ratios, the
/// group row's place in the sidebar, what ⌘W does to a pane.
public enum SplitRules {
    /// Arc and Zen allow four panes.
    public static let maxPanes = 4

    public static func canAdd(toCount count: Int) -> Bool { count < maxPanes }

    /// Equal sizes: one fraction per pane side by side or stacked; the grid
    /// keeps two column fractions and two row fractions (a 2-pane grid is a row).
    public static func equalRatios(layout: SplitLayout, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        switch layout {
        case .hbox, .vbox: return Array(repeating: 1 / Double(count), count: count)
        case .grid: return count <= 2 ? [0.5, 0.5] : [0.5, 0.5, 0.5, 0.5]
        }
    }

    /// `ratios` if they fit `layout` and `count` (right count, positive,
    /// summing to 1 per axis), else equal ones.
    public static func normalizedRatios(_ ratios: [Double], layout: SplitLayout, count: Int) -> [Double] {
        let equal = equalRatios(layout: layout, count: count)
        guard ratios.count == equal.count, ratios.allSatisfy({ $0 > 0 && $0.isFinite }) else { return equal }
        func sumsToOne(_ slice: ArraySlice<Double>) -> Bool { abs(slice.reduce(0, +) - 1) < 0.001 }
        switch layout {
        case .hbox, .vbox:
            return sumsToOne(ratios[...]) ? ratios : equal
        case .grid:
            let columns = ratios.prefix(2), rows = ratios.dropFirst(2)
            return sumsToOne(columns) && (rows.isEmpty || sumsToOne(rows)) ? ratios : equal
        }
    }

    /// The member whose row stands for the group in the sidebar: the group
    /// row sits in the pinned section if any member is permanent, else in
    /// Today (spec §D), at that member's place.
    public static func anchor(of members: [Entry]) -> UUID? {
        (members.first { $0.kind == .pinned } ?? members.first)?.id
    }

    /// The pane that takes the focus when `id` leaves the group: the next
    /// pane, else the previous one.
    public static func focusAfterLeaving(_ id: UUID, order: [UUID]) -> UUID? {
        guard let index = order.firstIndex(of: id) else { return order.first }
        let rest = order.filter { $0 != id }
        guard !rest.isEmpty else { return nil }
        return rest[min(index, rest.count - 1)]
    }

    /// ⌃⇧] (`offset` 1) / ⌃⇧[ (−1), wrapping around.
    public static func adjacentPane(to id: UUID, offset: Int, order: [UUID]) -> UUID? {
        guard let index = order.firstIndex(of: id), !order.isEmpty else { return order.first }
        let count = order.count
        return order[((index + offset) % count + count) % count]
    }

    /// ⌃⇧1…4: pane `number` (1-based), if the group has it.
    public static func pane(number: Int, order: [UUID]) -> UUID? {
        order.indices.contains(number - 1) ? order[number - 1] : nil
    }

    /// What ⌘W does to the focused pane (spec §D): a permanent entry gets
    /// §A.3's steps without the switch (the focus stays in the group) and
    /// leaves the split, a Today tab closes; either way the next pane takes
    /// the focus (a group left with one pane dissolves into a normal entry).
    public struct PaneClose: Equatable, Sendable {
        public var steps: CloseSteps
        public var leavesGroup: Bool
        public var focus: UUID?
    }

    public static func paneClose(_ entry: Entry, behavior: PermanentCloseBehavior, order: [UUID]) -> PaneClose {
        let steps = NavigationRules.closeSteps(for: entry.kind, behavior: behavior).subtracting(.switchAway)
        return PaneClose(steps: steps, leavesGroup: !steps.contains(.remove), focus: focusAfterLeaving(entry.id, order: order))
    }

    /// An entry dropped on pane `index`'s `edge` (or joined to it) goes before or after it.
    public static func insertionIndex(target index: Int, edge: SplitEdge) -> Int {
        edge.isLeading ? index : index + 1
    }

    /// The layout after a drop on `edge` leaves `count` panes: two panes
    /// follow the drop's axis; more keep the layout unless the drop crosses
    /// it, which makes a grid.
    public static func layout(afterDropOn edge: SplitEdge, current: SplitLayout?, count: Int) -> SplitLayout {
        let axis: SplitLayout = edge.isHorizontal ? .hbox : .vbox
        guard count > 2, let current else { return axis }
        return current == .grid || current == axis ? current : .grid
    }

    /// Pane `from` moved to `to` (the header's grip): side-by-side and
    /// stacked sizes travel with their pane; the grid keeps its columns and rows.
    public static func ratiosAfterMove(_ ratios: [Double], layout: SplitLayout, from: Int, to: Int) -> [Double] {
        guard layout != .grid, ratios.indices.contains(from), ratios.indices.contains(to) else { return ratios }
        var moved = ratios
        moved.insert(moved.remove(at: from), at: to)
        return moved
    }
}
