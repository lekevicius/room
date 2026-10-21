import CoreGraphics
import Design
import Testing
@testable import Card

@Suite("Split layout maths (spec §D)")
struct SplitGeometryTests {
    let bounds = CGRect(x: 0, y: 0, width: 1008, height: 608)

    @Test("Side by side and stacked: panes fill the card with the cards' gap between them (B-113), in proportion")
    func hboxAndVbox() {
        let row = SplitGeometry.frames(in: bounds, layout: .hbox, count: 2, ratios: [0.5, 0.5])
        #expect(row == [CGRect(x: 0, y: 0, width: 500, height: 608), CGRect(x: 508, y: 0, width: 500, height: 608)])
        let stack = SplitGeometry.frames(in: bounds, layout: .vbox, count: 3, ratios: [0.25, 0.25, 0.5])
        #expect(stack.map(\.minY) == [0, 156, 312])
        #expect(stack.last?.maxY == 608)
    }

    @Test("Grid: four panes in two rows; a third pane spans the bottom row; two panes are a row")
    func grid() {
        let four = SplitGeometry.frames(in: bounds, layout: .grid, count: 4, ratios: [0.5, 0.5, 0.5, 0.5])
        #expect(four.map(\.origin) == [CGPoint(x: 0, y: 0), CGPoint(x: 508, y: 0), CGPoint(x: 0, y: 308), CGPoint(x: 508, y: 308)])
        let three = SplitGeometry.frames(in: bounds, layout: .grid, count: 3, ratios: [0.5, 0.5, 0.5, 0.5])
        #expect(three[2] == CGRect(x: 0, y: 308, width: 1008, height: 300))
        let two = SplitGeometry.frames(in: bounds, layout: .grid, count: 2, ratios: [0.3, 0.7])
        #expect(two[0].height == 608 && two[0].width == 300)
    }

    @Test("Resizers: a hit area over each gap and a point either side; the grid's column line spans only the top row with three panes")
    func dividers() {
        let row = SplitGeometry.dividers(in: bounds, layout: .hbox, count: 3, ratios: [1.0 / 3, 1.0 / 3, 1.0 / 3])
        #expect(row.count == 2)
        #expect(row[0].line.width == SplitMetrics.paneGap && row[0].hit.width == SplitMetrics.resizerHitWidth)
        #expect(row[0].hit.midX == row[0].line.midX)
        let grid = SplitGeometry.dividers(in: bounds, layout: .grid, count: 3, ratios: [0.5, 0.5, 0.5, 0.5])
        #expect(grid.map(\.axis) == [.vertical, .horizontal])
        #expect(grid[0].line.maxY == 300)
    }

    @Test("Dragging a resizer moves only its two panes; neither gets under the minimum")
    func drag() throws {
        let ratios = [0.25, 0.25, 0.5]
        let line = try #require(SplitGeometry.dividers(in: bounds, layout: .hbox, count: 3, ratios: ratios).first)
        let moved = SplitGeometry.ratios(dragging: line, to: 400, in: bounds, layout: .hbox, count: 3, ratios: ratios)
        #expect(abs(moved[0] + moved[1] - 0.5) < 0.0001)
        #expect(moved[2] == 0.5)
        let squeezed = SplitGeometry.ratios(dragging: line, to: -50, in: bounds, layout: .hbox, count: 3, ratios: ratios)
        #expect(squeezed[0] * 992 >= SplitMetrics.minimumPaneLength - 0.001)
        let grid = SplitGeometry.dividers(in: bounds, layout: .grid, count: 4, ratios: [0.5, 0.5, 0.5, 0.5])
        let rows = SplitGeometry.ratios(dragging: grid[1], to: 2000, in: bounds, layout: .grid, count: 4, ratios: [0.5, 0.5, 0.5, 0.5])
        #expect(Array(rows.prefix(2)) == [0.5, 0.5])
        #expect(rows[3] * 600 >= SplitMetrics.minimumPaneLength - 0.001)
    }

    @Test("The minimum pane is 7% of the split, at least 120 pt, never more than an equal share")
    func minimum() {
        #expect(abs(SplitGeometry.minimumLength(along: 3000, count: 2) - 210) < 0.001)
        #expect(SplitGeometry.minimumLength(along: 1000, count: 2) == SplitMetrics.minimumPaneLength)
        #expect(SplitGeometry.minimumLength(along: 300, count: 4) == 75)
    }

    @Test("Drop zones: within 40 pt of an edge split to that side (nearest edge in a corner), elsewhere replace")
    func dropZones() {
        let pane = CGRect(x: 100, y: 0, width: 400, height: 600)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 120, y: 300), in: pane) == .left)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 490, y: 300), in: pane) == .right)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 300, y: 10), in: pane) == .top)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 130, y: 595), in: pane) == .bottom)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 300, y: 300), in: pane) == .center)
        #expect(SplitGeometry.dropZone(at: CGPoint(x: 50, y: 300), in: pane) == nil)
        #expect(SplitGeometry.dropPreview(.right, in: pane) == CGRect(x: 300, y: 0, width: 200, height: 600))
        #expect(SplitGeometry.dropPreview(.center, in: pane) == pane)
    }
}
