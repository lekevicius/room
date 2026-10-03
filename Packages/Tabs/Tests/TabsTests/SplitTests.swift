import AppKit
import Engine
import FakeEngine
import Model
import Testing
@testable import Tabs

@Suite("Split view on the tab controller (spec §D)", .serialized)
struct SplitTests {
    @Test("Selecting any pane shows the whole split, every pane's page loaded and kept from discarding; the focused one is current")
    func showsEveryPane() async throws {
        let fixture = try TabsFixture()
        let a = try fixture.today("https://a.example/"), b = try fixture.today("https://b.example/"), c = try fixture.today("https://c.example/")
        let group = try fixture.sidebarStore.createSplitGroup([a.id, b.id, c.id], layout: .vbox)
        try fixture.select(b.id)
        await fixture.settle()
        let split = try #require(fixture.display.split)
        #expect(split.group == group.id && split.layout == .vbox && split.focused == b.id)
        #expect(split.panes.map(\.entry) == [a.id, b.id, c.id])
        #expect(split.panes.allSatisfy { $0.contents != nil })
        #expect(fixture.tabs.current === fixture.page(b.id))
        #expect(fixture.display.shown === fixture.page(b.id))
        fixture.advance(minutes: 24 * 60)
        #expect(fixture.tabs.discardIdlePages().isEmpty, "panes on screen are never discarded")
    }

    @Test("The card follows the split: a new layout, a pane leaving, the split dissolving")
    func follows() async throws {
        let fixture = try TabsFixture()
        let a = try fixture.today("https://a.example/"), b = try fixture.today("https://b.example/"), c = try fixture.today("https://c.example/")
        let group = try fixture.sidebarStore.createSplitGroup([a.id, b.id, c.id])
        try fixture.select(a.id)
        await fixture.settle()
        try fixture.sidebarStore.setSplitLayout(group.id, .grid)
        #expect(fixture.display.split?.layout == .grid)
        fixture.sidebarStore.removeFromSplitGroup(c.id)
        #expect(fixture.display.split?.panes.map(\.entry) == [a.id, b.id])
        fixture.sidebarStore.dissolveSplitGroup(group.id)
        #expect(fixture.display.split == nil)
        #expect(fixture.display.shown === fixture.page(a.id))
    }

    @Test("A new split's empty pane has no page until the palette gives it a URL")
    func emptyPane() async throws {
        let fixture = try TabsFixture()
        let a = try fixture.today("https://a.example/")
        try fixture.select(a.id)
        await fixture.settle()
        fixture.sidebar.newSplitPane()
        let empty = try #require(fixture.display.split?.focused)
        #expect(empty != a.id && fixture.tabs.contents(for: empty) == nil && fixture.display.shown == nil)
        fixture.tabs.navigateSelected(to: "https://chosen.example/")
        await fixture.settle()
        #expect(fixture.page(empty)?.url == URL(string: "https://chosen.example/"))
        #expect(fixture.display.split?.panes.map(\.entry) == [a.id, empty])
    }

    @Test("Peek ▸ Split (⇧⌘O): the Peek's page becomes the pane beside its entry, focused")
    func peekSplit() async throws {
        let fixture = try TabsFixture()
        let peekDisplay = RecordingPeekDisplay()
        fixture.tabs.peekDisplay = peekDisplay
        let pinned = try fixture.pinned("https://news.example.com/")
        try fixture.select(pinned.id)
        await fixture.settle()
        let page = try #require(fixture.page(pinned.id))
        let article = URL(string: "https://www.other.org/story")!
        page.simulateStatusText(article.absoluteString)
        page.simulateLinkClick(to: article, disposition: .currentTab)
        await fixture.settle()
        let peek = try #require(peekDisplay.shown)
        fixture.tabs.splitShownPeek()
        await fixture.settle()
        let split = try #require(fixture.display.split)
        #expect(split.panes.count == 2 && split.panes[0].entry == pinned.id)
        #expect(split.panes[1].contents === peek && split.focused == split.panes[1].entry)
        #expect(peekDisplay.shown == nil && fixture.tabs.shownPeek == nil)
    }
}
