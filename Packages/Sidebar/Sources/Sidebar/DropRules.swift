import CoreGraphics
import Foundation
import Model
import Store

/// The ⌘/⇧-click multi-selection (spec §A.9): entries of one section only,
/// kept in that section's displayed order. The selected entry (the pill)
/// is separate; it joins the multi-selection when the first ⌘-click is in
/// its section, as in Arc.
public struct MultiSelection: Equatable, Sendable {
    public private(set) var ids: [UUID] = []
    public private(set) var section: EntrySection?
    /// Where the next ⇧-click range starts.
    public private(set) var anchor: UUID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// ⌘-click on `id` in `section`, whose displayed order is `order`.
    /// `primary` is the selected entry.
    public mutating func toggle(_ id: UUID, section: EntrySection, order: [UUID], primary: UUID?) {
        if self.section != section || ids.isEmpty {
            var start: Set<UUID> = [id]
            if let primary, primary != id, order.contains(primary) { start.insert(primary) }
            ids = order.filter(start.contains)
            self.section = section
        } else if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            if ids.isEmpty { self.section = nil }
        } else {
            let members = Set(ids).union([id])
            ids = order.filter(members.contains)
        }
        anchor = id
    }

    /// ⇧-click on `id`: the range from the anchor (or the selected entry)
    /// to `id`, if they share the section; otherwise `id` alone.
    public mutating func extend(to id: UUID, section: EntrySection, order: [UUID], primary: UUID?) {
        let start = [self.section == section ? anchor : nil, primary].compactMap { $0 }.first { order.contains($0) }
        guard let start, let from = order.firstIndex(of: start), let to = order.firstIndex(of: id) else {
            ids = [id]
            self.section = section
            anchor = id
            return
        }
        ids = Array(order[min(from, to)...max(from, to)])
        self.section = section
        anchor = start
    }

    /// Drops entries that left the section or the sidebar.
    public mutating func retain(_ order: [UUID]) {
        let present = Set(order)
        ids.removeAll { !present.contains($0) }
        if ids.isEmpty { clear() }
    }

    public mutating func clear() {
        ids = []
        section = nil
        anchor = nil
    }
}

/// Where a drag over the outline lands (spec §A.6, §A.9), as a pure
/// function of the rows and the pointer. The top and bottom 20% of an entry
/// row reorder; the middle 60% drops onto it once the pointer has rested
/// there for `holdDelay` (onto a folder: into it; onto a pinned entry: a new
/// folder with both). Before that the middle splits at half height.
public enum DropRules {
    /// The reorder zone at each edge of a row (Zen: 20% top and bottom).
    public static let edgeZone: CGFloat = 0.2
    /// How long the pointer rests on a row before a drop goes onto it (spec §A.6).
    public static let holdDelay: TimeInterval = 0.5

    /// One outline row as the drop logic sees it.
    public enum Row: Equatable, Sendable {
        case spaceTitle
        /// An entry at `index` in `container`, `depth` folder levels deep;
        /// `showsChildren` for a folder whose children follow it.
        case entry(id: UUID, kind: EntryKind, container: Container, index: Int, depth: Int, showsChildren: Bool)
        case separator
        case newTab
    }

    /// The insertion line: above row `boundary` (`rows.count` = below the
    /// last row), indented `depth` folder levels.
    public struct Line: Equatable, Sendable {
        public var boundary: Int
        public var depth: Int
    }

    public enum Target: Equatable, Sendable {
        /// Insert at `index` of `container` (`Int.max` = at the end).
        case insert(Container, index: Int, line: Line)
        /// Append inside this folder (row `row` highlights).
        case intoFolder(UUID, row: Int)
        /// A new folder holding this pinned entry and the dragged one.
        case newFolder(with: UUID, row: Int)

        public var container: Container? {
            if case .insert(let container, _, _) = self { container } else { nil }
        }
    }

    /// The target for a pointer over `row` (nil: below the rows) at
    /// `fraction` of its height from the top. `held`: the pointer has rested
    /// on this row for `holdDelay`. `single`: one non-folder entry is dragged
    /// (the only drag that can make a folder).
    public static func target(rows: [Row], row: Int?, fraction: CGFloat, held: Bool, space: UUID, single: Bool) -> Target {
        let index = row.flatMap { rows.indices.contains($0) ? $0 : nil }
        return target(index.map { rows[$0] }, at: index ?? rows.count, rowCount: rows.count, fraction: fraction, held: held,
                      space: space, single: single)
    }

    /// The same for one row (`nil`: below the last of `rowCount` rows), so a
    /// drag update need not describe every row.
    public static func target(_ row: Row?, at index: Int, rowCount: Int, fraction: CGFloat, held: Bool, space: UUID,
                              single: Bool) -> Target {
        let today = Container.today(space: space)
        let pinnedRoot = Container.pinned(space: space, folder: nil)
        guard let row else {
            return .insert(today, index: .max, line: Line(boundary: rowCount, depth: 0))
        }
        let upper = fraction < 0.5
        switch row {
        case .spaceTitle:
            return .insert(pinnedRoot, index: 0, line: Line(boundary: index + 1, depth: 0))
        case .separator:
            return upper
                ? .insert(pinnedRoot, index: .max, line: Line(boundary: index, depth: 0))
                : .insert(today, index: 0, line: Line(boundary: index + 1, depth: 0))
        case .newTab:
            return .insert(today, index: .max, line: Line(boundary: index, depth: 0))
        case .entry(let id, let kind, let container, let position, let depth, let showsChildren):
            if isMiddle(fraction) && held {
                if kind == .folder { return .intoFolder(id, row: index) }
                if kind == .pinned && single { return .newFolder(with: id, row: index) }
            }
            if upper { return .insert(container, index: position, line: Line(boundary: index, depth: depth)) }
            if kind == .folder && showsChildren {
                return .insert(.pinned(space: space, folder: id), index: 0, line: Line(boundary: index + 1, depth: depth + 1))
            }
            return .insert(container, index: position + 1, line: Line(boundary: index + 1, depth: depth))
        }
    }

    /// The drop-onto zone: the middle 60% of a row (spec §A.6).
    public static func isMiddle(_ fraction: CGFloat) -> Bool {
        fraction >= edgeZone && fraction <= 1 - edgeZone
    }

    /// A drop position in the Essentials grid: insert at `index`; the line
    /// goes beside tile `tile` (after it if `after`).
    public struct GridDrop: Equatable, Sendable {
        public var index: Int
        public var tile: Int
        public var after: Bool
    }

    /// The drop position for a point in the grid's coordinates: before the
    /// nearest tile if left of its centre, else after it.
    public static func gridDrop(frames: [CGRect], point: CGPoint) -> GridDrop {
        guard !frames.isEmpty else { return GridDrop(index: 0, tile: 0, after: false) }
        func distance(_ frame: CGRect) -> CGFloat {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return dx * dx + dy * dy
        }
        let nearest = frames.indices.min { distance(frames[$0]) < distance(frames[$1]) } ?? 0
        let after = point.x >= frames[nearest].midX
        return GridDrop(index: after ? nearest + 1 : nearest, tile: nearest, after: after)
    }

    public static func gridIndex(frames: [CGRect], point: CGPoint) -> Int {
        gridDrop(frames: frames, point: point).index
    }
}
