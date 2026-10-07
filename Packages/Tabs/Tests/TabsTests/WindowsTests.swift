import AppKit
import Engine
import FakeEngine
import Model
import Sidebar
import Store
import Testing
@testable import Tabs

/// Two windows on one store (4.8a): a second sidebar and tab controller
/// beside the fixture's, both under one `PageOwners`.
@MainActor
final class TwoWindows {
    let f: TabsFixture
    let sidebar2: SidebarController
    let tabs2: TabController
    let display2 = RecordingDisplay()
    let owners: PageOwners

    init() throws {
        f = try TabsFixture()
        let window = f.store.windows.createWindow(frame: nil, sidebarWidth: 240, space: f.space.id)
        sidebar2 = SidebarController(store: f.store, windowID: window.id)
        tabs2 = TabController(store: f.store)
        tabs2.display = display2
        tabs2.sidebar = sidebar2
        tabs2.now = { [unowned f] in f.clock }
        tabs2.profile = f.profile
        sidebar2.host = tabs2
        let pair = [f.tabs, tabs2]
        owners = PageOwners { pair }
        f.tabs.ownership = owners
        tabs2.ownership = owners
    }

    func page2(_ id: UUID) -> FakeWebContents? { tabs2.contents(for: id) as? FakeWebContents }

    /// Lets `DispatchQueue.main.async` work run (the selection fallback).
    func nextTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        await f.settle()
    }
}

@Suite("Page ownership across windows (4.8a)")
@MainActor
struct PageOwnershipTests {
    @Test("Claims: no holder loads, the holder keeps, another window's page moves")
    func claimRule() {
        let (entry, w1, w2) = (UUID(), UUID(), UUID())
        #expect(PageOwnership.claim(entry, by: w1, owners: [:]) == .load)
        #expect(PageOwnership.claim(entry, by: w1, owners: [entry: w1]) == .keep)
        #expect(PageOwnership.claim(entry, by: w2, owners: [entry: w1]) == .move(from: w1))
    }

    @Test("The fallback is the most recent used entry that is not the moved one and not on screen elsewhere")
    func fallbackRule() {
        let space = UUID(), profile = UUID()
        func entry(_ used: Bool, _ kind: EntryKind = .pinned) -> Entry {
            Entry(kind: kind, spaceID: space, profileID: profile, lastActiveAt: used ? Timestamp(milliseconds: 1) : nil)
        }
        let moved = entry(true), shownElsewhere = entry(true), folder = entry(true, .folder), unused = entry(false), next = entry(true)
        let mru = [moved, shownElsewhere, folder, unused, next]
        #expect(PageOwnership.fallback(mru: mru, losing: moved.id, visibleElsewhere: [shownElsewhere.id]) == next.id)
        #expect(PageOwnership.fallback(mru: [moved, unused], losing: moved.id, visibleElsewhere: []) == nil)
    }

    @Test("A pinned page selected in window 2 moves there with its history; window 1 falls back to its most recent entry")
    func pinnedMoves() async throws {
        let w = try TwoWindows()
        let f = w.f
        let other = try f.pinned("https://other.example/")
        let pinned = try f.pinned("https://p.example/")
        try f.select(other.id)
        f.advance(minutes: 1)
        try f.select(pinned.id)
        let first = try #require(f.page(pinned.id))
        first.load(URL(string: "https://p.example/next")!, transition: .link, fromAddressBar: false)
        first.finishLoading()
        await f.settle()
        #expect(first.canGoBack)
        f.advance(minutes: 1)
        w.sidebar2.select(pinned.id)
        // Window 1 gave the page up (closed, its history in the entry); window 2 made it from that history.
        #expect(first.state == .closed && f.tabs.contents(for: pinned.id) == nil)
        let moved = try #require(w.page2(pinned.id))
        #expect(moved.wasRestored && moved.canGoBack && moved.url?.absoluteString == "https://p.example/next")
        #expect(w.display2.shown === moved)
        await w.nextTurn()
        // Window 1's selection fell to its MRU, whose page it shows.
        #expect(f.sidebar.selectedEntryID == other.id)
        #expect(f.display.shown != nil && f.display.shown === f.page(other.id))
        // Selecting it again in window 1 moves it back.
        w.sidebar2.select(nil)
        try f.select(pinned.id)
        #expect(w.page2(pinned.id) == nil && f.page(pinned.id) != nil)
    }

    @Test("Each window's Today list and ⌘1 are its own")
    func perWindowTodayAndDigits() async throws {
        let w = try TwoWindows()
        let f = w.f
        let essential = try f.sidebarStore.addEntry(.essential, url: "https://e.example/", space: f.space.id)
        let one = f.tabs.openNewTab(url: "https://one.example/")
        let two = w.tabs2.openNewTab(url: "https://two.example/")
        #expect(f.sidebarStore.today(space: f.space.id, window: f.sidebar.windowID).map(\.id) == [one])
        #expect(f.sidebarStore.today(space: f.space.id, window: w.sidebar2.windowID).map(\.id) == [two])
        // ⌘9 (last) in each window is its own Today tab; ⌘1 the shared essential.
        w.sidebar2.selectTab(digit: 9)
        #expect(w.sidebar2.selectedEntryID == two)
        f.sidebar.selectTab(digit: 9)
        #expect(f.sidebar.selectedEntryID == one)
        w.sidebar2.selectTab(digit: 1)
        #expect(w.sidebar2.selectedEntryID == essential.id)
        // The switcher's recent list is the window's own (no Today tab of the other window).
        let recent2 = w.sidebar2.recentEntries(limit: 10).map(\.id)
        #expect(recent2.contains(two!) && !recent2.contains(one!))
    }

    @Test("The discard policy never takes a page on screen in another window")
    func discardRespectsOtherWindows() async throws {
        let w = try TwoWindows()
        let f = w.f
        let a = try f.pinned("https://a.example/")
        let b = try f.pinned("https://b.example/")
        let shown = try f.pinned("https://shown.example/")
        try f.select(shown.id)
        // Two background pages in window 1.
        f.tabs.loadInBackground(f.sidebarStore.entry(a.id)!)
        f.tabs.loadInBackground(f.sidebarStore.entry(b.id)!)
        // A visible-elsewhere set that names `a` (the policy reads the coordinator's union).
        final class Elsewhere: PageOwnershipCoordinator {
            let visible: Set<UUID>
            init(_ visible: Set<UUID>) { self.visible = visible }
            func tabController(_ controller: TabController, willMakePageFor entry: UUID) {}
            func entriesVisible(besides controller: TabController) -> Set<UUID> { visible }
        }
        let elsewhere = Elsewhere([a.id])
        f.tabs.ownership = elsewhere
        let discarded = f.tabs.discardBackgroundPages()
        #expect(discarded == [b.id])
        #expect(f.page(a.id)?.state == .alive && f.page(shown.id)?.state == .alive)
        // And through the real coordinator: window 2's shown entry counts.
        f.tabs.ownership = w.owners
        #expect(w.owners.entriesVisible(besides: f.tabs) == w.tabs2.visibleEntries)
    }

    @Test("An entry another window removes takes its page with it")
    func removedElsewhere() async throws {
        let w = try TwoWindows()
        let f = w.f
        let pinned = try f.pinned("https://p.example/")
        w.sidebar2.select(pinned.id)
        let page = try #require(w.page2(pinned.id))
        _ = try f.sidebarStore.remove(pinned.id)
        #expect(page.state == .closed && w.tabs2.contents(for: pinned.id) == nil)
    }
}
