import AppKit
import Engine
import FakeEngine
import Model
import Sidebar
import Store
import Testing
@testable import Tabs

/// What the card was asked to show.
final class RecordingDisplay: PageDisplay {
    private(set) var shown: (any WebContents)?
    private(set) var showCount = 0

    func show(_ contents: (any WebContents)?) {
        shown = contents
        showCount += 1
    }
}

/// Answers beforeunload with a fixed choice.
final class BeforeUnloadAnswer: WebContentsUIDelegate {
    var leave: Bool
    init(leave: Bool) { self.leave = leave }
    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        completion(leave)
    }
}

/// A window's sidebar and tab controller on a fresh store, with FakeEngine pages.
final class TabsFixture {
    let directory: URL
    let store: RoomStore
    let sidebar: SidebarController
    let tabs: TabController
    let display = RecordingDisplay()
    let engine = FakeApplication()
    let profile: FakeProfile
    let space: Space
    var clock = Date(timeIntervalSince1970: 1_000_000)

    init(withProfile: Bool = true, populate: (RoomStore, Space) throws -> Void = { _, _ in }) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomTabsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try engine.initialize(EngineConfiguration(userDataDirectory: directory))
        profile = try engine.profile(named: "Default")
        store = try RoomStore.open(directory: directory)
        space = store.sidebar.spaces[0]
        try populate(store, space)
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        sidebar = SidebarController(store: store, windowID: window.id)
        tabs = TabController(store: store)
        tabs.display = display
        tabs.sidebar = sidebar
        tabs.now = { [unowned self] in clock }
        if withProfile { tabs.profile = profile }
        sidebar.host = tabs
    }

    /// The store closes first: removing the directory under a write still in
    /// flight logged "disk I/O error" (2.5 carry-over).
    isolated deinit {
        store.close()
        try? FileManager.default.removeItem(at: directory)
    }

    var sidebarStore: SidebarStore { store.sidebar }

    @discardableResult
    func today(_ url: String, title: String? = nil) throws -> Entry {
        try sidebarStore.addEntry(.today, url: url, title: title, space: space.id)
    }

    @discardableResult
    func pinned(_ url: String) throws -> Entry {
        try sidebarStore.addEntry(.pinned, url: url, title: "Pinned", space: space.id)
    }

    func page(_ id: UUID) -> FakeWebContents? { tabs.contents(for: id) as? FakeWebContents }

    var todayIDs: [UUID] { sidebarStore.today(space: space.id).map(\.id) }

    /// Lets page observations (re-armed on the next main-actor turn) run.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func advance(minutes: Double) { clock += minutes * 60 }

    /// Selects as a click does, stamping the MRU key with the fixture's clock.
    func select(_ id: UUID) throws {
        sidebar.select(id)
        try sidebarStore.markActive(id, at: Timestamp(clock))
    }
}

@Suite("Tab controller: profiles (ROADMAP 2.5 task 4)")
struct ProfileTests {
    /// A second profile with a space, and its FakeEngine profile delivered.
    private func work(_ f: TabsFixture) throws -> (space: Space, engine: FakeProfile) {
        let profile = f.sidebarStore.createProfile(name: "Work")
        let space = try f.sidebarStore.createSpace(name: "Work", profile: profile.id)
        let engine = try f.engine.profile(named: "Work")
        f.tabs.setEngineProfile(engine, for: profile.id)
        return (space, engine)
    }

    @Test("A page moved to a space of another profile loads again there, at its URL; the card follows")
    func crossProfileMove() async throws {
        let f = try TabsFixture()
        let (work, workEngine) = try work(f)
        let tab = try f.today("https://a.example/start")
        f.sidebar.select(tab.id)
        let before = try #require(f.page(tab.id))
        try f.sidebarStore.move(tab.id, to: .today(space: work.id), at: 0)
        await f.settle()
        let after = try #require(f.page(tab.id))
        #expect(after !== before)
        #expect(before.state == .closed)
        #expect(workEngine.openWebContents.contains { $0 === after })
        #expect(!f.profile.openWebContents.contains { $0 === before })
        #expect(after.url?.absoluteString == "https://a.example/start")
        #expect(f.display.shown === after)
        #expect(f.sidebarStore.entry(tab.id)?.profileID == work.profileID)
    }

    @Test("Moving within one profile keeps the page")
    func sameProfileMove() async throws {
        let f = try TabsFixture()
        let other = try f.sidebarStore.createSpace(name: "Other", profile: f.space.profileID)
        let tab = try f.today("https://a.example")
        f.sidebar.select(tab.id)
        let before = try #require(f.page(tab.id))
        try f.sidebarStore.move(tab.id, to: .today(space: other.id), at: 0)
        await f.settle()
        #expect(f.page(tab.id) === before)
        #expect(before.state == .alive)
    }

    @Test("A page whose profile has no engine profile yet asks for it once and loads when it arrives")
    func waitsForProfile() throws {
        let f = try TabsFixture()
        let profile = f.sidebarStore.createProfile(name: "Later")
        let space = try f.sidebarStore.createSpace(name: "Later", profile: profile.id)
        var requests: [String] = []
        f.tabs.requestEngineProfile = { requests.append($0.name) }
        let tab = try f.sidebarStore.addEntry(.today, url: "https://later.example", space: space.id)
        let background = try f.sidebarStore.addEntry(.today, url: "https://background.example", space: space.id)
        f.sidebar.showSpace(space.id)
        f.sidebar.select(tab.id)
        #expect(f.tabs.loadInBackground(background) == nil)
        #expect(requests == ["Later"])
        #expect(f.display.shown == nil)
        let engine = try f.engine.profile(named: "Later")
        f.tabs.setEngineProfile(engine, for: profile.id)
        #expect(engine.openWebContents.count == 2)
        #expect(f.display.shown?.url?.absoluteString == "https://later.example")
    }

    @Test("Engine profile names stay one directory deep")
    func engineNames() {
        #expect(TabController.engineProfileName(for: Model.Profile(name: "Default", position: 0)) == "Default")
        #expect(TabController.engineProfileName(for: Model.Profile(name: "a/b:c", position: 0)) == "a-b-c")
        #expect(TabController.engineProfileName(for: Model.Profile(name: "..hidden", position: 0)) == "hidden")
    }
}

@Suite("Tab controller: pages per entry and the card (ROADMAP 2.3)")
struct PageTests {
    @Test("A page is created on an entry's first selection; switching keeps the others alive and shows the selected one")
    func pagesPerEntry() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        f.sidebar.select(a.id)
        #expect(f.profile.openWebContents.count == 2)
        #expect(f.display.shown === f.tabs.contents(for: a.id))
        #expect(f.page(b.id)?.state == .alive)
        #expect(f.page(a.id)?.url?.absoluteString == "https://a.example")
        #expect(f.tabs.pageState(for: b.id).isLoaded)
    }

    @Test("At launch only the selected entry loads, once the profile exists (spec §H)")
    func onlySelectionLoadsAtLaunch() throws {
        var selected: UUID?
        let f = try TabsFixture(withProfile: false) { store, space in
            let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
            for index in 0..<5 {
                let entry = try store.sidebar.addEntry(.today, url: "https://t\(index).example", space: space.id)
                if index == 3 { selected = entry.id }
            }
            try store.sidebar.addEntry(.pinned, url: "https://p.example", space: space.id)
            store.windows.select(selected, space: space.id, window: window.id)
        }
        f.tabs.showSelection()
        #expect(f.profile.openWebContents.isEmpty)
        f.tabs.profile = f.profile
        #expect(f.profile.openWebContents.count == 1)
        #expect(f.tabs.loadedEntryIDs == [selected!])
        #expect(f.display.shown?.url?.absoluteString == "https://t3.example")
    }

    @Test("Nothing selected at launch shows the empty state")
    func emptyAtLaunch() throws {
        let f = try TabsFixture()
        f.tabs.showSelection()
        #expect(f.display.showCount == 1 && f.display.shown == nil)
    }

    @Test("Title and URL reach the store; a same-site link marks a pinned entry changed (§A.1, §A.4)")
    func pageStateIntoStore() async throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://docs.example/start")
        f.sidebar.select(pinned.id)
        f.page(pinned.id)?.simulateLinkClick(to: URL(string: "https://docs.example/next")!)
        await f.settle()
        let entry = try #require(f.sidebarStore.entry(pinned.id))
        #expect(entry.liveURL == "https://docs.example/next")
        #expect(entry.liveTitle == "docs.example")
        #expect(f.sidebarStore.isChanged(pinned.id))
        #expect(entry.storedURL == "https://docs.example/start")
    }

    @Test("Favicons are cached by host and shown for the unloaded entry, also after reopening the store (§I.2)")
    func faviconCache() async throws {
        let f = try TabsFixture()
        let tab = try f.today("https://icons.example/page")
        f.sidebar.select(tab.id)
        let icon = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        f.page(tab.id)?.simulateFavicon(icon)
        await f.settle()
        let id = try #require(f.sidebarStore.entry(tab.id)?.faviconID)
        #expect(f.store.favicons.id(forHost: "icons.example") == id)
        f.tabs.unload(tab.id)
        #expect(!f.tabs.pageState(for: tab.id).isLoaded)
        #expect(f.tabs.pageState(for: tab.id).favicon != nil)
        let reopened = FaviconStore(database: f.store.persistence.writer.database)
        #expect(reopened.png(id) != nil)
    }

    @Test("A page that closes itself (window.close) closes its Today tab")
    func pageClosesItself() async throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        f.page(b.id)?.simulateWindowClose()
        #expect(f.sidebarStore.entry(b.id) == nil)
        #expect(f.sidebar.selectedEntryID == a.id)
        #expect(f.tabs.contents(for: b.id) == nil)
    }
}

@Suite("Tab controller: ⌘W, ⇧⌘T, MRU, empty state (§A.3, §A.7, §G)")
struct CloseTests {
    @Test("⌘W on a Today tab closes its page, removes it and selects the most recently used entry")
    func closeToday() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example"), c = try f.today("https://c.example")
        try f.select(a.id)
        f.advance(minutes: 1)
        try f.select(c.id)
        f.advance(minutes: 1)
        try f.select(b.id)
        let page = try #require(f.page(b.id))
        f.sidebar.closeCommandTargets()
        #expect(page.state == .closed)
        #expect(f.sidebarStore.entry(b.id) == nil)
        // MRU (c), not the neighbour.
        #expect(f.sidebar.selectedEntryID == c.id)
        #expect(f.display.shown === f.tabs.contents(for: c.id))
    }

    @Test("Closing the last Today tab with nothing else selectable shows the empty state")
    func closeLastToday() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example")
        f.sidebar.select(a.id)
        f.sidebar.closeCommandTargets()
        #expect(f.sidebar.selectedEntryID == nil)
        #expect(f.display.shown == nil)
        #expect(f.profile.openWebContents.isEmpty)
    }

    @Test("Closing the last Today tab keeps a pinned selection (the MRU entry)")
    func closeLastTodayKeepsPinned() throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://p.example"), a = try f.today("https://a.example")
        try f.select(pinned.id)
        f.advance(minutes: 1)
        try f.select(a.id)
        f.sidebar.closeCommandTargets()
        #expect(f.sidebar.selectedEntryID == pinned.id)
        #expect(f.display.shown === f.tabs.contents(for: pinned.id))
    }

    @Test("⌘W on a changed pinned entry switches away, unloads and resets it; the entry stays (§A.3)")
    func closePinned() async throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), pinned = try f.pinned("https://p.example/home")
        try f.select(a.id)
        f.advance(minutes: 1)
        try f.select(pinned.id)
        f.page(pinned.id)?.simulateLinkClick(to: URL(string: "https://p.example/deep")!)
        await f.settle()
        let page = try #require(f.page(pinned.id))
        f.sidebar.closeCommandTargets()
        #expect(page.state == .closed)
        #expect(f.tabs.contents(for: pinned.id) == nil)
        let entry = try #require(f.sidebarStore.entry(pinned.id))
        #expect(entry.liveURL == "https://p.example/home")
        #expect(f.sidebar.selectedEntryID == a.id)
    }

    @Test("⇧⌘T reopens a closed Today tab where it was, selected, at its URL")
    func reopenToday() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example"), c = try f.today("https://c.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        f.sidebar.closeCommandTargets()
        #expect(f.todayIDs == [a.id, c.id])
        f.sidebar.reopenClosedTab()
        #expect(f.todayIDs == [a.id, b.id, c.id])
        #expect(f.sidebar.selectedEntryID == b.id)
        #expect(f.page(b.id)?.url?.absoluteString == "https://b.example")
        #expect(!f.sidebar.canReopenClosedTab)
    }

    @Test("⇧⌘T after ⌘W on a pinned entry brings its page back at the URL it had")
    func reopenPinnedPage() async throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), pinned = try f.pinned("https://p.example/home")
        f.sidebar.select(a.id)
        f.sidebar.select(pinned.id)
        f.page(pinned.id)?.simulateLinkClick(to: URL(string: "https://p.example/deep")!)
        await f.settle()
        f.sidebar.closeCommandTargets()
        f.sidebar.reopenClosedTab()
        #expect(f.sidebar.selectedEntryID == pinned.id)
        #expect(f.page(pinned.id)?.url?.absoluteString == "https://p.example/deep")
    }

    @Test("⇧⌘T after Clear restores every Today tab at once; newest closes reopen first")
    func reopenOrder() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.sidebar.clearTodayTabs()
        #expect(f.todayIDs.isEmpty)
        let c = try f.today("https://c.example")
        f.sidebar.select(c.id)
        f.sidebar.closeCommandTargets()
        f.sidebar.reopenClosedTab()
        #expect(f.todayIDs == [c.id])
        f.sidebar.reopenClosedTab()
        #expect(Set(f.todayIDs) == [a.id, b.id, c.id])
    }

    @Test("Keeping a page in its beforeunload dialog during ⌘W brings it back as a Today tab, selected")
    func beforeUnloadStay() async throws {
        let f = try TabsFixture()
        let answer = BeforeUnloadAnswer(leave: false)
        f.tabs.pageUIDelegate = answer
        let a = try f.today("https://a.example"), b = try f.today("https://form.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        let page = try #require(f.page(b.id))
        page.hasBeforeUnloadHandler = true
        f.sidebar.closeCommandTargets()
        await f.settle()
        #expect(page.state == .alive)
        #expect(f.sidebarStore.entry(b.id) == nil)
        let kept = try #require(f.sidebar.selectedEntryID)
        #expect(f.tabs.contents(for: kept) === page)
        #expect(f.sidebarStore.entry(kept)?.kind == .today)
    }
}

@Suite("Tab controller: tabs opened from pages (§A.7)")
struct RelatedTabTests {
    @Test("A link from a Today tab opens right below it, selected")
    func foregroundBelowOpener() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.page(a.id)?.simulateLinkClick(to: URL(string: "https://a.example/child")!, disposition: .newForegroundTab)
        let ids = f.todayIDs
        #expect(ids.count == 3 && ids[0] == a.id && ids[2] == b.id)
        #expect(f.sidebar.selectedEntryID == ids[1])
        #expect(f.page(ids[1])?.url?.absoluteString == "https://a.example/child")
    }

    @Test("Background links from one opener keep their order below it until the user switches tabs")
    func backgroundChain() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.page(a.id)?.simulateLinkClick(to: URL(string: "https://one.example")!, disposition: .newBackgroundTab)
        f.page(a.id)?.simulateLinkClick(to: URL(string: "https://two.example")!, disposition: .newBackgroundTab)
        var urls = f.sidebarStore.today(space: f.space.id).map(\.liveURL)
        #expect(urls == ["https://a.example", "https://one.example", "https://two.example", "https://b.example"])
        #expect(f.sidebar.selectedEntryID == a.id)
        // A tab switch ends the chain: the next link goes right below its opener again.
        f.sidebar.select(b.id)
        f.sidebar.select(a.id)
        f.page(a.id)?.simulateLinkClick(to: URL(string: "https://three.example")!, disposition: .newBackgroundTab)
        urls = f.sidebarStore.today(space: f.space.id).map(\.liveURL)
        #expect(urls.prefix(2) == ["https://a.example", "https://three.example"])
    }

    @Test("Open Link in New Tab from a page's context menu opens below it, behind it (2.6)")
    func contextMenuLink() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        let page = try #require(f.page(a.id))
        let id = try #require(f.tabs.openLink(URL(string: "https://a.example/menu")!, from: page))
        #expect(f.todayIDs == [a.id, id, b.id])
        #expect(f.sidebar.selectedEntryID == a.id)
        #expect(f.page(id)?.url?.absoluteString == "https://a.example/menu")
    }

    @Test("A link from a pinned entry opens at the top of Today")
    func fromPinned() throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://p.example"), a = try f.today("https://a.example")
        f.sidebar.select(pinned.id)
        f.page(pinned.id)?.simulateLinkClick(to: URL(string: "https://elsewhere.example")!, disposition: .newForegroundTab)
        let today = f.sidebarStore.today(space: f.space.id)
        #expect(today.map(\.liveURL) == ["https://elsewhere.example", "https://a.example"])
        #expect(f.sidebar.selectedEntryID == today[0].id)
        _ = a
    }
}

@Suite("Tab controller: discarding (spec §H)")
struct DiscardTests {
    @Test("Idle limits: Today 60 min, permanent 3 h; never the selected or an audible page")
    func idle() throws {
        let f = try TabsFixture()
        let today = try f.today("https://t.example"), audible = try f.today("https://music.example")
        let pinned = try f.pinned("https://p.example"), selected = try f.today("https://s.example")
        for entry in [today, audible, pinned, selected] { f.sidebar.select(entry.id) }
        f.page(audible.id)?.simulateAudio(true)
        f.advance(minutes: 59)
        #expect(f.tabs.discardIdlePages().isEmpty)
        f.advance(minutes: 2)
        #expect(f.tabs.discardIdlePages() == [today.id])
        #expect(f.page(today.id)?.state == .discarded)
        #expect(!f.tabs.pageState(for: today.id).isLoaded)
        f.advance(minutes: 120)
        #expect(f.tabs.discardIdlePages() == [pinned.id])
        #expect(f.page(selected.id)?.state == .alive && f.page(audible.id)?.state == .alive)
    }

    @Test("A discarded page keeps its URL and title and reloads when selected")
    func discardedReloads() throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example/page"), b = try f.today("https://b.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        f.advance(minutes: 61)
        f.tabs.discardIdlePages()
        #expect(f.sidebarStore.entry(a.id)?.liveURL == "https://a.example/page")
        f.sidebar.select(a.id)
        #expect(f.page(a.id)?.state == .alive)
        #expect(f.page(a.id)?.url?.absoluteString == "https://a.example/page")
        #expect(f.profile.openWebContents.count == 2)
    }

    @Test("Memory pressure discards the least recently seen first; critical discards every background page")
    func pressure() {
        let now = Date()
        func page(_ minutesAgo: Double, selected: Bool = false, audible: Bool = false) -> DiscardPolicy.Page {
            DiscardPolicy.Page(id: UUID(), kind: .today, isSelected: selected, isAudible: audible, isAlive: true,
                               lastVisible: now - minutesAgo * 60)
        }
        let pages = [page(1), page(30), page(10), page(5), page(0, selected: true), page(90, audible: true)]
        #expect(DiscardPolicy.underPressure(pages, critical: false) == [pages[1].id, pages[2].id])
        #expect(Set(DiscardPolicy.underPressure(pages, critical: true)) == Set(pages[0..<4].map(\.id)))
    }
}

@Suite("Tab switching (§G)")
struct SwitchingTests {
    @Test("⌃Tab starts on the previous tab, ⌃⇧Tab on the oldest; steps wrap; W drops the highlighted one")
    func switcherState() {
        let ids = (0..<5).map { _ in UUID() }
        var state = TabSwitcherState(items: ids, backwards: false)
        #expect(state.highlighted == ids[1])
        state.step(-2)
        #expect(state.highlighted == ids[4])
        state.step(1)
        #expect(state.highlighted == ids[0])
        #expect(TabSwitcherState(items: ids, backwards: true).highlighted == ids[4])
        state.step(4)
        #expect(state.removeHighlighted() == ids[4])
        #expect(state.highlighted == ids[3] && state.items.count == 4)
    }

    @Test("The switcher lists the five most recently used entries, the selected one first")
    func recentEntries() throws {
        let f = try TabsFixture()
        let entries = try (0..<7).map { try f.today("https://\($0).example") }
        for entry in entries {
            f.advance(minutes: 1)
            try f.select(entry.id)
        }
        f.advance(minutes: 1)
        try f.select(entries[2].id)
        let recent = f.sidebar.recentEntries(limit: 5).map(\.id)
        #expect(recent == [entries[2].id, entries[6].id, entries[5].id, entries[4].id, entries[3].id])
    }

    @Test("⌘1–9 and the next/previous commands select in sidebar order")
    func digitsAndAdjacent() throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://p.example")
        let a = try f.today("https://a.example"), b = try f.today("https://b.example")
        f.sidebar.selectTab(digit: 1)
        #expect(f.sidebar.selectedEntryID == pinned.id)
        f.sidebar.selectTab(digit: 9)
        #expect(f.sidebar.selectedEntryID == b.id)
        f.sidebar.selectAdjacentTab(1)
        #expect(f.sidebar.selectedEntryID == pinned.id)
        f.sidebar.selectAdjacentTab(-1)
        f.sidebar.selectAdjacentTab(-1)
        #expect(f.sidebar.selectedEntryID == a.id)
        #expect(f.display.shown === f.tabs.contents(for: a.id))
    }
}

@Suite("Tab controller: history recording (ROADMAP 2.4 task 4)")
struct HistoryRecordingTests {
    /// Waits for the history writes queued so far (the writer is serial).
    private func flushHistory(_ f: TabsFixture) throws {
        try f.store.history.recordVisitNow(url: "https://barrier.invalid/", title: nil, transition: .link, profile: f.space.profileID)
    }

    @Test("Commits become visits with how they started; a restored page is not a visit; the title follows")
    func visits() async throws {
        let f = try TabsFixture()
        let restored = try f.today("https://restored.example/")
        f.sidebar.select(restored.id)
        f.tabs.openNewTab(url: "https://typed.example/")
        f.tabs.openNewTab(url: "https://www.google.com/search?q=room", transition: .generated)
        f.page(f.tabs.currentEntryID!)?.simulateLinkClick(to: URL(string: "https://result.example/")!)
        await f.settle()
        try flushHistory(f)
        let history = f.store.history
        #expect(try history.row(url: "https://restored.example/", profile: f.space.profileID) == nil)
        #expect(try history.visits(url: "https://typed.example/", profile: f.space.profileID).map(\.1) == [.typed])
        #expect(try history.visits(url: "https://www.google.com/search?q=room", profile: f.space.profileID).map(\.1) == [.generated])
        #expect(try history.visits(url: "https://result.example/", profile: f.space.profileID).map(\.1) == [.link])
        // FakeEngine titles a finished page with its host.
        #expect(try history.row(url: "https://typed.example/", profile: f.space.profileID)?.title == "typed.example")
    }

    @Test("Reloads and discarded pages coming back add no visit; an unloaded pinned entry opens as a bookmark")
    func noDuplicates() async throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://pinned.example/")
        let other = try f.today("https://other.example/")
        f.sidebar.select(pinned.id)
        f.tabs.current?.reload()
        f.sidebar.select(other.id)
        try f.tabs.contents(for: pinned.id)?.discard()
        f.sidebar.select(pinned.id)
        await f.settle()
        try flushHistory(f)
        #expect(try f.store.history.visits(url: "https://pinned.example/", profile: f.space.profileID).map(\.1) == [.bookmark])
    }
}
