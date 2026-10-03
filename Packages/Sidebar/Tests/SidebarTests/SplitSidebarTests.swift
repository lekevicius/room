import AppKit
import Model
import Store
import Testing
@testable import Sidebar

@Suite("Split view in the sidebar (spec §D)")
struct SplitSidebarTests {
    @Test("A split is one row, at its permanent pane's place; its panes leave their lists; any pane's selection puts the pill on it")
    func groupRow() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let pinned = try s.addEntry(.pinned, url: "https://p.example", title: "P", space: space)
        let a = try s.addEntry(.today, url: "https://a.example", title: "A", space: space)
        let b = try s.addEntry(.today, url: "https://b.example", title: "B", space: space)
        try s.createSplitGroup([a.id, pinned.id])
        #expect(f.rows() == ["# Space", "  P", "---", "B", "+ New Tab"])
        f.controller.select(a.id)
        let row = try #require(f.controller.tree.displayedNode(for: a.id))
        #expect(row.entryID == pinned.id)
        #expect(f.controller.outline.view(atColumn: 0, row: f.controller.outline.row(forItem: row), makeIfNecessary: true) is SplitGroupCellView)
        s.dissolveSplitGroup(try #require(s.splitGroup(of: a.id)).id)
        #expect(f.rows() == ["# Space", "  P", "---", "A", "B", "+ New Tab"])
    }

    @Test("⌘W closes only the focused pane and the next pane takes the focus; a split left with one pane dissolves")
    func closePane() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let pinned = try s.addEntry(.pinned, url: "https://p.example", title: "P", space: space)
        let a = try s.addEntry(.today, url: "https://a.example", title: "A", space: space)
        let b = try s.addEntry(.today, url: "https://b.example", title: "B", space: space)
        let group = try s.createSplitGroup([a.id, pinned.id, b.id])
        f.controller.select(a.id)
        f.controller.closeCommandTargets()
        #expect(s.entry(a.id) == nil)
        #expect(f.controller.selectedEntryID == pinned.id)
        #expect(s.splitMembers(group.id).map(\.id) == [pinned.id, b.id])
        // A permanent pane gets §A.3 (unloaded, reset) and stays in the sidebar outside the split.
        f.controller.closeCommandTargets()
        #expect(s.entry(pinned.id) != nil && s.entry(pinned.id)?.splitGroupID == nil)
        #expect(f.host.unloaded.contains(pinned.id))
        #expect(f.controller.selectedEntryID == b.id)
        #expect(s.splitGroups[group.id] == nil)
    }

    @Test("⌃⇧N, ⌃⇧] / ⌃⇧[ move the focus inside the split; ⌥⌘U keeps the focused pane selected")
    func focusKeys() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let tabs = try (0..<3).map { try s.addEntry(.today, url: "https://\($0).example", title: "T\($0)", space: space) }
        try s.createSplitGroup(tabs.map(\.id))
        f.controller.select(tabs[0].id)
        f.controller.focusPane(number: 3)
        #expect(f.controller.selectedEntryID == tabs[2].id)
        f.controller.focusAdjacentPane(1)
        #expect(f.controller.selectedEntryID == tabs[0].id)
        f.controller.focusAdjacentPane(-1)
        #expect(f.controller.selectedEntryID == tabs[2].id)
        f.controller.unsplit()
        #expect(s.splitGroups.isEmpty && f.controller.selectedEntryID == tabs[2].id)
    }

    @Test("Join: a row dropped on a tab's centre makes a split with it, focused; a fifth pane is refused")
    func join() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let tabs = try (0..<5).map { try s.addEntry(.today, url: "https://\($0).example", title: "T\($0)", space: space) }
        f.controller.performDrop(.join(with: tabs[0].id, row: 0), ids: [tabs[1].id], copy: false, external: [])
        #expect(s.splitGroup(of: tabs[0].id)?.members == [tabs[0].id, tabs[1].id])
        #expect(f.controller.selectedEntryID == tabs[1].id)
        f.controller.performDrop(.join(with: tabs[1].id, row: 0), ids: [tabs[2].id], copy: false, external: [])
        f.controller.performDrop(.join(with: tabs[0].id, row: 0), ids: [tabs[3].id], copy: false, external: [])
        #expect(s.splitGroup(of: tabs[0].id)?.members == [tabs[0].id, tabs[3].id, tabs[1].id, tabs[2].id])
        #expect(!f.controller.canJoin([tabs[4].id], with: tabs[0].id))
        #expect(!f.controller.performDrop(.join(with: tabs[0].id, row: 0), ids: [tabs[4].id], copy: false, external: []))
    }

    @Test("⇧⌘= adds an empty pane after the focused one and opens the palette on it; drop zones split to their side")
    func newPaneAndDrops() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let a = try s.addEntry(.today, url: "https://a.example", title: "A", space: space)
        let b = try s.addEntry(.today, url: "https://b.example", title: "B", space: space)
        f.controller.select(a.id)
        f.controller.newSplitPane()
        let group = try #require(s.splitGroup(of: a.id))
        #expect(group.members.count == 2 && group.members[0] == a.id)
        let empty = try #require(s.entry(group.members[1]))
        #expect(empty.currentURL == nil && f.controller.selectedEntryID == empty.id)
        f.controller.dropIntoSplit(b.id, edge: .top, of: a.id)
        let after = try #require(s.splitGroup(of: a.id))
        #expect(after.members == [b.id, a.id, empty.id])
        #expect(after.layout == .grid)
    }
}
