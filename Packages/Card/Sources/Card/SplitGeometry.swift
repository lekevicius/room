import CoreGraphics
import Design

/// Split view's layout maths (spec §D), pure, in a flipped coordinate space
/// (y grows downward; pane 0 is top-left). `hbox` puts panes side by side,
/// `vbox` stacks them, `grid` makes two columns over two rows (a third pane
/// spans the bottom row; two panes are a row). Ratios as `SplitRules` keeps
/// them: one fraction per pane for `hbox`/`vbox`; for the grid the two
/// column fractions, then the two row fractions.
public enum SplitGeometry {
    public enum Layout: Sendable { case hbox, vbox, grid }

    /// A vertical line is dragged along x; a horizontal one along y.
    public enum Axis: Sendable { case vertical, horizontal }

    /// A resizer between panes: `index` is the boundary after pane `index`
    /// (`hbox`, `vbox`) or 0 = the column split, 1 = the row split (grid).
    public struct Divider: Equatable, Sendable {
        public var index: Int
        public var axis: Axis
        /// The gap between the panes (`SplitMetrics.paneGap`; B-113: the cards' gap, no drawn line).
        public var line: CGRect
        /// The hit area centred on it (`SplitMetrics.resizerHitWidth`).
        public var hit: CGRect
    }

    // MARK: Frames

    public static func frames(in bounds: CGRect, layout: Layout, count: Int, ratios: [Double],
                              gap: CGFloat = SplitMetrics.paneGap) -> [CGRect] {
        guard count > 1 else { return count == 1 ? [bounds] : [] }
        switch effective(layout, count) {
        case .hbox:
            return segments(bounds.minX, bounds.maxX, ratios: fractions(ratios, count), gap: gap).map {
                CGRect(x: $0.lowerBound, y: bounds.minY, width: $0.upperBound - $0.lowerBound, height: bounds.height)
            }
        case .vbox:
            return segments(bounds.minY, bounds.maxY, ratios: fractions(ratios, count), gap: gap).map {
                CGRect(x: bounds.minX, y: $0.lowerBound, width: bounds.width, height: $0.upperBound - $0.lowerBound)
            }
        case .grid:
            let (columns, rows) = gridFractions(ratios)
            let xs = segments(bounds.minX, bounds.maxX, ratios: columns, gap: gap)
            let ys = segments(bounds.minY, bounds.maxY, ratios: rows, gap: gap)
            func cell(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>) -> CGRect {
                CGRect(x: x.lowerBound, y: y.lowerBound, width: x.upperBound - x.lowerBound, height: y.upperBound - y.lowerBound)
            }
            var frames = [cell(xs[0], ys[0]), cell(xs[1], ys[0])]
            if count == 3 {
                frames.append(cell(bounds.minX...bounds.maxX, ys[1]))
            } else {
                frames += [cell(xs[0], ys[1]), cell(xs[1], ys[1])]
            }
            return frames
        }
    }

    // MARK: Resizers

    public static func dividers(in bounds: CGRect, layout: Layout, count: Int, ratios: [Double],
                                gap: CGFloat = SplitMetrics.paneGap, hitWidth: CGFloat = SplitMetrics.resizerHitWidth) -> [Divider] {
        guard count > 1 else { return [] }
        let frames = frames(in: bounds, layout: layout, count: count, ratios: ratios, gap: gap)
        func vertical(_ index: Int, x: CGFloat, y: ClosedRange<CGFloat>) -> Divider {
            let line = CGRect(x: x, y: y.lowerBound, width: gap, height: y.upperBound - y.lowerBound)
            return Divider(index: index, axis: .vertical, line: line, hit: line.insetBy(dx: (gap - hitWidth) / 2, dy: 0))
        }
        func horizontal(_ index: Int, y: CGFloat) -> Divider {
            let line = CGRect(x: bounds.minX, y: y, width: bounds.width, height: gap)
            return Divider(index: index, axis: .horizontal, line: line, hit: line.insetBy(dx: 0, dy: (gap - hitWidth) / 2))
        }
        switch effective(layout, count) {
        case .hbox:
            return (0..<count - 1).map { vertical($0, x: frames[$0].maxX, y: bounds.minY...bounds.maxY) }
        case .vbox:
            return (0..<count - 1).map { horizontal($0, y: frames[$0].maxY) }
        case .grid:
            // With three panes the column line runs through the top row only.
            let columnSpan = count == 3 ? bounds.minY...frames[0].maxY : bounds.minY...bounds.maxY
            return [vertical(0, x: frames[0].maxX, y: columnSpan), horizontal(1, y: frames[0].maxY)]
        }
    }

    /// The ratios after `divider` is dragged so its line is at `position`
    /// (x for a vertical line, y for a horizontal one): only the two sides of
    /// that boundary change, and neither gets smaller than `minimumLength`.
    public static func ratios(dragging divider: Divider, to position: CGFloat, in bounds: CGRect, layout: Layout, count: Int,
                              ratios: [Double], gap: CGFloat = SplitMetrics.paneGap) -> [Double] {
        let along = divider.axis == .vertical
        let start = along ? bounds.minX : bounds.minY
        let length = along ? bounds.width : bounds.height
        switch effective(layout, count) {
        case .hbox, .vbox:
            var parts = fractions(ratios, count)
            let available = length - gap * CGFloat(count - 1)
            guard available > 0, parts.indices.contains(divider.index + 1) else { return parts }
            let before = parts[..<divider.index].reduce(0, +)
            let pairStart = start + CGFloat(before) * available + gap * CGFloat(divider.index)
            let pair = CGFloat(parts[divider.index] + parts[divider.index + 1]) * available
            let minimum = minimumLength(along: available, count: count)
            let first = min(max(position - pairStart, minimum), max(minimum, pair - minimum))
            parts[divider.index] = Double(first / available)
            parts[divider.index + 1] = Double((pair - first) / available)
            return parts
        case .grid:
            let (columns, rows) = gridFractions(ratios)
            let available = length - gap
            guard available > 0 else { return ratios }
            let minimum = minimumLength(along: available, count: 2)
            let first = min(max(position - start, minimum), max(minimum, available - minimum))
            let split = [Double(first / available), Double((available - first) / available)]
            return divider.index == 0 ? split + rows : columns + split
        }
    }

    /// The smallest a pane may get along an axis of `available` points:
    /// `SplitMetrics.minimumPaneFraction` of it, at least
    /// `SplitMetrics.minimumPaneLength`, never more than an equal share.
    public static func minimumLength(along available: CGFloat, count: Int) -> CGFloat {
        let wanted = max(available * SplitMetrics.minimumPaneFraction, SplitMetrics.minimumPaneLength)
        return min(wanted, available / CGFloat(max(count, 1)))
    }

    // MARK: Drop zones

    /// Where an entry dragged over a pane would go (spec §D): within
    /// `band` of an edge it splits to that side (the nearest edge in a corner), elsewhere it replaces the pane.
    public enum DropZone: Equatable, Sendable { case left, right, top, bottom, center }

    public static func dropZone(at point: CGPoint, in pane: CGRect, band: CGFloat = SplitMetrics.dropEdgeBand) -> DropZone? {
        guard pane.contains(point) else { return nil }
        let distances: [(DropZone, CGFloat)] = [(.left, point.x - pane.minX), (.right, pane.maxX - point.x),
                                                (.top, point.y - pane.minY), (.bottom, pane.maxY - point.y)]
        guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 < band else { return .center }
        return nearest.0
    }

    /// What the drop's preview covers: the side's share of the pane, or all of it.
    public static func dropPreview(_ zone: DropZone, in pane: CGRect, fraction: CGFloat = SplitMetrics.dropPreviewFraction) -> CGRect {
        let width = (pane.width * fraction).rounded(), height = (pane.height * fraction).rounded()
        switch zone {
        case .left: return CGRect(x: pane.minX, y: pane.minY, width: width, height: pane.height)
        case .right: return CGRect(x: pane.maxX - width, y: pane.minY, width: width, height: pane.height)
        case .top: return CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: height)
        case .bottom: return CGRect(x: pane.minX, y: pane.maxY - height, width: pane.width, height: height)
        case .center: return pane
        }
    }

    // MARK: Internals

    /// A two-pane grid is a row.
    private static func effective(_ layout: Layout, _ count: Int) -> Layout {
        layout == .grid && count <= 2 ? .hbox : layout
    }

    /// `count` positive fractions summing to 1 (equal ones if `ratios` do not fit).
    private static func fractions(_ ratios: [Double], _ count: Int) -> [Double] {
        let usable = ratios.count >= count ? Array(ratios.prefix(count)) : []
        let sum = usable.reduce(0, +)
        guard usable.count == count, usable.allSatisfy({ $0 > 0 }), sum > 0 else { return Array(repeating: 1 / Double(count), count: count) }
        return usable.map { $0 / sum }
    }

    private static func gridFractions(_ ratios: [Double]) -> (columns: [Double], rows: [Double]) {
        (fractions(Array(ratios.prefix(2)), 2), fractions(Array(ratios.dropFirst(2).prefix(2)), 2))
    }

    /// Consecutive ranges from `start` to `end` with `gap` between them, in
    /// proportion to `ratios`; ends on whole points, the last ends at `end`.
    private static func segments(_ start: CGFloat, _ end: CGFloat, ratios: [Double], gap: CGFloat) -> [ClosedRange<CGFloat>] {
        let available = end - start - gap * CGFloat(ratios.count - 1)
        var result: [ClosedRange<CGFloat>] = []
        var cursor = start
        var sum = 0.0
        for (index, ratio) in ratios.enumerated() {
            sum += ratio
            let last = index == ratios.count - 1
            let stop = last ? end : (start + CGFloat(sum) * available + gap * CGFloat(index)).rounded()
            result.append(cursor...max(cursor, stop))
            cursor = stop + gap
        }
        return result
    }
}
