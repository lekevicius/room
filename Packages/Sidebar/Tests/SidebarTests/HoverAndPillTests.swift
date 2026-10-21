import AppKit
import Model
import Store
import Testing
@testable import Sidebar

/// The 2026-10-21 pass's sidebar bugs (B-108, B-109).
@Suite("Sidebar pill and hover after layout changes")
struct HoverAndPillTests {
    @Test("B-108: a sidebar resize carries the selected row's pill to the rows' new width")
    func pillFollowsResize() throws {
        let f = try SidebarFixture()
        let a = try f.sidebar.addEntry(.today, url: "https://a.example", title: "A", space: f.space.id)
        f.controller.select(a.id)
        let outline = f.controller.outline
        let row = outline.row(forItem: try #require(f.controller.tree.displayedNode(for: a.id)))
        #expect(outline.pill.frame == SidebarRowView.pillRect(in: outline.rect(ofRow: row)))
        f.controller.bodyView.setFrameSize(NSSize(width: 400, height: 2000))
        f.controller.bodyView.layoutSubtreeIfNeeded()
        let wider = SidebarRowView.pillRect(in: outline.rect(ofRow: row))
        #expect(wider.width > 300)
        #expect(outline.pill.frame == wider)
    }

    @Test("B-109: after a close, the row that slides under a still pointer is the hovered one")
    func hoverAfterClose() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let a = try s.addEntry(.today, url: "https://a.example", title: "A", space: space)
        let b = try s.addEntry(.today, url: "https://b.example", title: "B", space: space)
        let c = try s.addEntry(.today, url: "https://c.example", title: "C", space: space)
        f.controller.select(a.id)
        let outline = f.controller.outline
        let rowB = outline.row(forItem: try #require(f.controller.tree.displayedNode(for: b.id)))
        let pointer = NSPoint(x: outline.rect(ofRow: rowB).midX, y: outline.rect(ofRow: rowB).midY)
        outline.pointerLocation = { pointer }
        outline.refreshHover()
        #expect(f.controller.hoveredEntryForTesting == b.id)
        f.controller.close(b.id)
        #expect(outline.row(at: pointer) == rowB)
        #expect(f.controller.hoveredEntryForTesting == c.id)
    }
}
