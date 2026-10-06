import AppKit
import Engine
import FakeEngine
import Foundation
import Model
import Testing
@testable import Tabs

/// What Peek was asked to show.
final class RecordingPeekDisplay: PeekDisplay {
    private(set) var shown: (any WebContents)?
    func showPeek(_ contents: (any WebContents)?, animated: Bool) { shown = contents }
}

@Suite("Peek on the tab controller (spec §A.4, §I.6)", .serialized)
struct PeekTests {
    let article = URL(string: "https://www.other.org/story")!

    /// A pinned entry on news.example.com, selected and loaded, with Peek's display.
    func pinnedFixture() async throws -> (TabsFixture, RecordingPeekDisplay, Entry, FakeWebContents) {
        let fixture = try TabsFixture()
        let display = RecordingPeekDisplay()
        fixture.tabs.peekDisplay = display
        let entry = try fixture.pinned("https://news.example.com/")
        try fixture.select(entry.id)
        await fixture.settle()
        let page = try #require(fixture.page(entry.id))
        return (fixture, display, entry, page)
    }

    /// A person's click on a link (`.linkActivated`; the status text names the link first, as a hovered link does).
    func click(_ page: FakeWebContents, _ url: URL, disposition: Disposition = .currentTab) async {
        page.simulateStatusText(url.absoluteString)
        page.simulateLinkClick(to: url, disposition: disposition)
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("An off-site click from a pinned entry opens Peek over it in the entry's profile; the pinned page stays")
    func offSiteOpensPeek() async throws {
        let (fixture, display, entry, page) = try await pinnedFixture()
        await click(page, article)
        let peek = try #require(display.shown as? FakeWebContents)
        #expect(peek.url == article)
        #expect(page.url == URL(string: "https://news.example.com/"))
        #expect(fixture.tabs.focusedPage === peek)
        #expect(fixture.tabs.engineProfile(for: peek) === fixture.profile)
        #expect(fixture.sidebarStore.entry(entry.id)?.liveURL == "https://news.example.com/")
        // No sidebar entry until Open as Tab.
        #expect(fixture.todayIDs.isEmpty)
    }

    @Test("Same-site clicks and Today tabs navigate in place")
    func inPlace() async throws {
        let (fixture, display, _, page) = try await pinnedFixture()
        await click(page, URL(string: "https://www.example.com/sports")!)
        #expect(display.shown == nil)
        #expect(page.url == URL(string: "https://www.example.com/sports"))
        let tab = try fixture.today("https://news.example.com/")
        try fixture.select(tab.id)
        await fixture.settle()
        let todayPage = try #require(fixture.page(tab.id))
        await click(todayPage, article)
        #expect(display.shown == nil)
        #expect(todayPage.url == article)
    }

    @Test("Open as Tab makes the Peek a selected Today tab with the same page; ⌘W closes the Peek first and ⇧⌘T reopens it")
    func expandCloseReopen() async throws {
        let (fixture, display, entry, page) = try await pinnedFixture()
        await click(page, article)
        let peek = try #require(display.shown)
        fixture.tabs.expandShownPeek()
        await fixture.settle()
        #expect(display.shown == nil)
        #expect(fixture.todayIDs.count == 1)
        #expect(fixture.tabs.current === peek)
        #expect(fixture.sidebarStore.entry(fixture.todayIDs[0])?.liveURL == article.absoluteString)

        try fixture.select(entry.id)
        await fixture.settle()
        await click(page, article)
        #expect(fixture.tabs.closeShownPeek())
        #expect(display.shown == nil)
        fixture.sidebar.reopenClosedTab()
        await fixture.settle()
        #expect((display.shown as? FakeWebContents)?.url == article)
        #expect(fixture.tabs.currentEntryID == entry.id)
    }

    @Test("A fullscreen request from the Peek's page expands it into a Today tab under its entry first, then goes on as the card's page's (B-35)")
    func fullscreenExpandsFirst() async throws {
        let (fixture, display, entry, page) = try await pinnedFixture()
        let earlier = try fixture.today("https://first.example/")
        try fixture.select(entry.id)
        await fixture.settle()
        await click(page, article)
        let peek = try #require(display.shown)
        final class Recorder: WebContentsUIDelegate {
            var requests: [(contents: any WebContents, shown: (any WebContents)?)] = []
            weak var tabs: TabController?
            func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
                requests.append((webContents, tabs?.current))
            }
        }
        let recorder = Recorder()
        recorder.tabs = fixture.tabs
        fixture.tabs.pageUIDelegate = recorder
        fixture.tabs.webContentsDidRequestEnterFullscreen(peek, origin: nil)
        await fixture.settle()
        #expect(display.shown == nil, "the Peek is gone")
        #expect(fixture.todayIDs.count == 2 && fixture.todayIDs[1] == earlier.id, "the new Today tab is directly under its pinned entry: the top of Today")
        #expect(fixture.sidebar.selectedEntryID == fixture.todayIDs[0] && fixture.tabs.current === peek)
        #expect(recorder.requests.count == 1 && recorder.requests[0].contents === peek && recorder.requests[0].shown === peek,
                "the request reached the app with the page already in the card")
        // A card page's request goes on unchanged.
        fixture.tabs.webContentsDidRequestEnterFullscreen(peek, origin: nil)
        #expect(recorder.requests.count == 2 && fixture.todayIDs.count == 2)
    }

    @Test("Open as Tab from a Today tab's Peek places the tab directly under it (spec §I.6)")
    func expandUnderTodayParent() async throws {
        let fixture = try TabsFixture()
        let display = RecordingPeekDisplay()
        fixture.tabs.peekDisplay = display
        let first = try fixture.today("https://one.example/"), parent = try fixture.today("https://two.example/")
        let last = try fixture.today("https://three.example/")
        try fixture.select(parent.id)
        await fixture.settle()
        let page = try #require(fixture.page(parent.id))
        // ⇧-click peeks from any page.
        page.simulateStatusText(article.absoluteString)
        page.simulateLinkClick(to: article, disposition: .newWindow)
        for _ in 0..<20 { await Task.yield() }
        #expect(display.shown != nil)
        fixture.tabs.expandShownPeek()
        await fixture.settle()
        let ids = fixture.todayIDs
        #expect(ids.count == 4 && ids[0] == first.id && ids[1] == parent.id && ids[3] == last.id)
        #expect(fixture.sidebar.selectedEntryID == ids[2])
    }

    @Test("A Peek stays with its entry: it hides on a switch and comes back; unloading the entry closes it")
    func belongsToEntry() async throws {
        let (fixture, display, entry, page) = try await pinnedFixture()
        await click(page, article)
        let peek = try #require(display.shown)
        let tab = try fixture.today("https://elsewhere.net/")
        try fixture.select(tab.id)
        await fixture.settle()
        #expect(display.shown == nil)
        try fixture.select(entry.id)
        await fixture.settle()
        #expect(display.shown === peek)
        fixture.tabs.unload(entry.id)
        #expect(display.shown == nil)
        #expect(peek.state == .closed)
    }

    @Test("Esc the page in Peek did not use closes it")
    func escape() async throws {
        let (fixture, display, _, page) = try await pinnedFixture()
        await click(page, article)
        let peek = try #require(display.shown)
        let esc = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(fixture.tabs.webContents(peek, handleUnhandledKeyEvent: esc))
        #expect(display.shown == nil)
    }
}
