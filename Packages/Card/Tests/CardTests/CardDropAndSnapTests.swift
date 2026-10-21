import CoreGraphics
import Design
import Testing
@testable import Card

/// 5.5b: who takes a drop on the card (spec §I.7) and the split divider's snap (ROADMAP 5.5 task 6).
@Suite("Card drops and the split snap")
struct CardDropAndSnapTests {
    @Test("The page takes what it accepts; Room what it refuses; several links are always Room's; a page's own drag stays the page's")
    func dropOwner() {
        // A link or a file over a part of the page that takes it (Blink loads it in a new tab, or a drop zone takes it).
        #expect(CardDropRule.owner(links: 1, files: 0, fromPage: false, roomCanOpen: true, pageAccepts: true) == .page)
        #expect(CardDropRule.owner(links: 0, files: 2, fromPage: false, roomCanOpen: true, pageAccepts: true) == .page)
        // Text over a part that is not editable: a search tab; image data: a file:// tab.
        #expect(CardDropRule.owner(links: 0, files: 0, fromPage: false, roomCanOpen: true, pageAccepts: false) == .room)
        // Two links: Room's even where the page would take one.
        #expect(CardDropRule.owner(links: 2, files: 0, fromPage: false, roomCanOpen: true, pageAccepts: true) == .room)
        // A page's own link dropped back on a page: Room opens nothing.
        #expect(CardDropRule.owner(links: 2, files: 0, fromPage: true, roomCanOpen: true, pageAccepts: false) == .none)
        #expect(CardDropRule.owner(links: 1, files: 0, fromPage: true, roomCanOpen: true, pageAccepts: true) == .page)
        // Nothing to open and the page refuses.
        #expect(CardDropRule.owner(links: 0, files: 0, fromPage: false, roomCanOpen: false, pageAccepts: false) == .none)
    }

    @Test("A divider dragged within the snap distance of its equal point lands on it")
    func snap() {
        let bounds = CGRect(x: 0, y: 0, width: 1008, height: 608)
        let ratios = [0.3, 0.7]
        let divider = SplitGeometry.dividers(in: bounds, layout: .hbox, count: 2, ratios: ratios)[0]
        // Two panes of (1008 - 8) points: equal at x = 500.
        #expect(SplitGeometry.equalPosition(of: divider, in: bounds, layout: .hbox, count: 2, ratios: ratios) == 500)
        #expect(SplitGeometry.snap(500 + SplitMetrics.snapDistance, dragging: divider, in: bounds, layout: .hbox, count: 2, ratios: ratios)
            == (500, true))
        #expect(SplitGeometry.snap(500 + SplitMetrics.snapDistance + 1, dragging: divider, in: bounds, layout: .hbox, count: 2, ratios: ratios)
            == (500 + SplitMetrics.snapDistance + 1, false))
        let snapped = SplitGeometry.ratios(dragging: divider, to: 500, in: bounds, layout: .hbox, count: 2, ratios: ratios)
        #expect(snapped == [0.5, 0.5])
        // Three panes: the second divider's equal point halves the last two panes' share only.
        let three = [0.5, 0.2, 0.3]
        let second = SplitGeometry.dividers(in: bounds, layout: .hbox, count: 3, ratios: three)[1]
        let equal = SplitGeometry.equalPosition(of: second, in: bounds, layout: .hbox, count: 3, ratios: three) ?? 0
        let after = SplitGeometry.ratios(dragging: second, to: equal, in: bounds, layout: .hbox, count: 3, ratios: three)
        #expect(abs(after[0] - 0.5) < 1e-9 && abs(after[1] - 0.25) < 1e-9 && abs(after[2] - 0.25) < 1e-9)
    }
}
