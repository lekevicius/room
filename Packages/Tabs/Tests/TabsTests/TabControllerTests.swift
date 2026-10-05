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
    private(set) var split: SplitPresentation?

    func show(_ contents: (any WebContents)?) {
        shown = contents
        showCount += 1
    }

    func showSplit(_ split: SplitPresentation?) { self.split = split }
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

    /// Removes the directory when it goes (a relaunch's fixture leaves it to the first).
    private let ownsDirectory: Bool

    init(withProfile: Bool = true, relaunching earlier: URL? = nil,
         populate: (RoomStore, Space) throws -> Void = { _, _ in }) throws {
        ownsDirectory = earlier == nil
        directory = earlier
            ?? FileManager.default.temporaryDirectory.appending(path: "RoomTabsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        if ownsDirectory { try? FileManager.default.removeItem(at: directory) }
    }

    /// The next launch on the same state: a new engine, store, sidebar and
    /// tab controller (after `store.close()` a clean one, without it as after a crash).
    func relaunch() throws -> TabsFixture { try TabsFixture(relaunching: directory) }

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

    @Test("Every page is created for the controller's window (RoomCore binds it to that window's Browser, 3.2a)")
    func pagesAreCreatedForTheWindow() throws {
        let f = try TabsFixture()
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        f.tabs.window = window
        let tab = try f.today("https://a.example")
        f.sidebar.select(tab.id)
        let page = try #require(f.page(tab.id))
        #expect(page.configuration.hostWindow === window)
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

    @Test("⌘W and \"stay\" in the page's beforeunload dialog: the page stays alive in its own entry, selected (§A.3)")
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
        #expect(f.sidebarStore.entry(b.id)?.kind == .today)
        #expect(f.sidebar.selectedEntryID == b.id)
        #expect(f.tabs.contents(for: b.id) === page)
        #expect(f.todayIDs.count == 2)
        // Nothing was closed, so ⇧⌘T has nothing to reopen.
        f.sidebar.reopenClosedTab()
        #expect(f.todayIDs.count == 2)
    }

    @Test("⌘W and \"leave\": the entry goes once its page closed, and ⇧⌘T brings it back")
    func beforeUnloadLeave() async throws {
        let f = try TabsFixture()
        f.tabs.pageUIDelegate = BeforeUnloadAnswer(leave: true)
        let a = try f.today("https://a.example"), b = try f.today("https://form.example")
        f.sidebar.select(a.id)
        f.sidebar.select(b.id)
        let page = try #require(f.page(b.id))
        page.hasBeforeUnloadHandler = true
        f.sidebar.closeCommandTargets()
        await f.settle()
        #expect(page.state == .closed)
        #expect(f.sidebarStore.entry(b.id) == nil)
        #expect(f.sidebar.selectedEntryID == a.id)
        f.sidebar.reopenClosedTab()
        #expect(f.sidebarStore.entry(b.id) != nil)
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

    @Test("Memory pressure: moderate discards the older half, least recently seen first; critical the oldest, then the next")
    func pressure() {
        let now = Date()
        func page(_ minutesAgo: Double, selected: Bool = false, audible: Bool = false, blockers: DiscardBlockers = []) -> DiscardPolicy.Page {
            DiscardPolicy.Page(id: UUID(), kind: .today, isSelected: selected, isAudible: audible, isAlive: true,
                               lastVisible: now - minutesAgo * 60, blockers: blockers)
        }
        let pages = [page(1), page(30), page(10), page(5), page(0, selected: true), page(90, audible: true),
                     page(120, blockers: .formInteractions)]
        #expect(DiscardPolicy.underPressure(pages, level: .moderate) == [pages[1].id, pages[2].id])
        #expect(DiscardPolicy.underPressure(pages, level: .critical) == [pages[1].id])
        #expect(DiscardPolicy.underPressure(pages, level: .none).isEmpty)
    }

    @Test("A page with a dirty form or in Picture-in-Picture is not discarded when idle; it goes once the engine lets it")
    func blockedPagesStay() throws {
        let f = try TabsFixture()
        let form = try f.today("https://form.example"), pip = try f.today("https://video.example")
        let plain = try f.today("https://plain.example"), selected = try f.today("https://s.example")
        for entry in [form, pip, plain, selected] { f.sidebar.select(entry.id) }
        f.page(form.id)?.simulatedDiscardBlockers = .formInteractions
        f.page(pip.id)?.simulatedDiscardBlockers = .pictureInPicture
        f.advance(minutes: 61)
        #expect(f.tabs.discardIdlePages() == [plain.id])
        #expect(f.page(form.id)?.state == .alive && f.page(pip.id)?.state == .alive)
        #expect(f.tabs.keptByEngine == [form.id: .formInteractions, pip.id: .pictureInPicture])
        // The form is submitted: the next sweep discards it.
        f.page(form.id)?.simulatedDiscardBlockers = []
        #expect(f.tabs.discardIdlePages() == [form.id])
        #expect(f.page(pip.id)?.state == .alive)
    }

    @Test("Critical pressure from the engine discards the oldest hidden page first, never the selection or a blocked page")
    func criticalPressure() throws {
        let f = try TabsFixture()
        let old = try f.today("https://old.example"), blocked = try f.today("https://blocked.example")
        let newer = try f.today("https://newer.example"), selected = try f.today("https://s.example")
        f.sidebar.select(blocked.id)
        f.advance(minutes: 1)
        f.sidebar.select(old.id)
        f.advance(minutes: 1)
        f.sidebar.select(newer.id)
        f.advance(minutes: 1)
        f.sidebar.select(selected.id)
        f.page(blocked.id)?.simulatedDiscardBlockers = .audible
        let relay = PressureRelay(f.tabs)
        f.engine.delegate = relay
        f.engine.simulateMemoryPressure(.critical)
        #expect(f.page(old.id)?.state == .discarded && f.page(newer.id)?.state == .alive)
        f.engine.simulateMemoryPressure(.critical)
        #expect(f.page(newer.id)?.state == .discarded)
        f.engine.simulateMemoryPressure(.critical)
        #expect(f.page(blocked.id)?.state == .alive && f.page(selected.id)?.state == .alive)
        #expect(f.tabs.memoryPressure == .critical)
        _ = relay
    }
}

/// The app's role: the engine's memory pressure to the window's tab controller.
final class PressureRelay: EngineApplicationDelegate {
    let tabs: TabController
    init(_ tabs: TabController) { self.tabs = tabs }
    func engineApplication(_ application: any EngineApplication, didChangeMemoryPressure level: MemoryPressureLevel) {
        tabs.handleMemoryPressure(level)
    }
}

@Suite("Tab controller: session history (3.7b)")
struct SessionHistoryTests {
    @Test("A page made from an entry's stored history reports canGoBack and loads the restored page; a fresh one does not")
    func restoredPageGoesBack() async throws {
        let f = try TabsFixture()
        let a = try f.today("https://a.example/1"), fresh = try f.today("https://fresh.example")
        f.sidebar.select(a.id)
        f.page(a.id)?.load(URL(string: "https://a.example/2")!)
        await f.settle()
        let stored = try #require(f.sidebarStore.entry(a.id)?.navigationState)
        f.sidebar.select(fresh.id)
        f.tabs.unload(a.id)
        f.sidebar.select(a.id)
        let revived = try #require(f.page(a.id))
        #expect(revived.wasRestored && revived.canGoBack && revived.url?.absoluteString == "https://a.example/2")
        #expect(!revived.isLoading && revived.title != nil, "the restored entry loaded")
        revived.goBack()
        #expect(revived.url?.absoluteString == "https://a.example/1")
        #expect(f.page(fresh.id)?.canGoBack == false)
        #expect(f.sidebarStore.entry(fresh.id)?.navigationState != stored)
    }

    @Test("After a relaunch, clean or not, every entry with history goes Back to its previous page")
    func relaunchKeepsHistory() async throws {
        let f = try TabsFixture()
        let entries = try (0..<3).map { try f.today("https://site\($0).example/first") }
        for (index, entry) in entries.enumerated() {
            f.sidebar.select(entry.id)
            f.page(entry.id)?.load(URL(string: "https://site\(index).example/second")!)
        }
        await f.settle()
        // No close(): an unclean exit (the store's debounced write is flushed as a kill would leave the last one).
        f.store.flush()
        let next = try f.relaunch()
        #expect(next.store.uncleanExit)
        for (index, entry) in entries.enumerated() {
            next.sidebar.select(entry.id)
            let page = try #require(next.page(entry.id))
            #expect(page.canGoBack, "entry \(index)")
            page.goBack()
            #expect(page.url?.absoluteString == "https://site\(index).example/first")
        }
    }

    @Test("⌘W on a changed pinned entry unloads and resets it; its next page starts at the stored URL with the old page behind it")
    func resetKeepsHistoryBehind() async throws {
        let f = try TabsFixture()
        let pinned = try f.pinned("https://p.example/")
        let other = try f.today("https://o.example")
        f.sidebar.select(pinned.id)
        f.page(pinned.id)?.load(URL(string: "https://p.example/deeper")!)
        await f.settle()
        f.sidebar.close(pinned.id, behavior: .resetUnloadSwitch)
        #expect(f.page(pinned.id) == nil && f.sidebar.selectedEntryID == other.id)
        f.sidebar.select(pinned.id)
        let page = try #require(f.page(pinned.id))
        #expect(page.url?.absoluteString == "https://p.example/" && page.canGoBack)
        page.goBack()
        #expect(page.url?.absoluteString == "https://p.example/deeper")
    }

    @Test("The first load of a restored page: the restored entry, onward navigation, or the URL alone when the state did not read")
    func firstLoadRule() {
        let url = URL(string: "https://a.example/2")!
        #expect(NavigationRestore.firstLoad(entryURL: url, restoredURL: url, hadState: true) == .loadRestored)
        #expect(NavigationRestore.firstLoad(entryURL: url, restoredURL: URL(string: "https://a.example/1"), hadState: true)
            == .navigate(unreadable: false))
        #expect(NavigationRestore.firstLoad(entryURL: url, restoredURL: nil, hadState: true) == .navigate(unreadable: true))
        #expect(NavigationRestore.firstLoad(entryURL: url, restoredURL: nil, hadState: false) == .navigate(unreadable: false))
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

/// Holds the certificate prompt's completion until the test answers it.
final class CertificateAnswer: WebContentsUIDelegate {
    var pending: ((Bool) -> Void)?
    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        pending = completion
    }
}

@Suite("Tab controller: the certificate interstitial (2.6a carry-over, B-25)")
struct CertificateInterstitialTests {
    @Test("While the interstitial shows, the row's title is the host")
    func titleIsHost() async throws {
        let f = try TabsFixture()
        let answer = CertificateAnswer()
        f.tabs.pageUIDelegate = answer
        let tab = try f.today("https://self-signed.example/page")
        f.sidebar.select(tab.id)
        let page = try #require(f.page(tab.id))
        page.simulateTitle("Privacy error")
        Task { _ = await page.simulateCertificateError() }
        await f.settle()
        #expect(f.sidebarStore.entry(tab.id)?.liveTitle == "self-signed.example")
        page.simulateTitle("Still blocked")
        await f.settle()
        #expect(f.sidebarStore.entry(tab.id)?.liveTitle == "self-signed.example")
        answer.pending?(true)
        page.simulateTitle("The page")
        await f.settle()
        #expect(f.sidebarStore.entry(tab.id)?.liveTitle == "The page")
    }

    @Test("Go Back with nothing to go back to: the page goes, the entry stays with the host, the card is empty")
    func goBackWithoutHistory() async throws {
        let f = try TabsFixture()
        let answer = CertificateAnswer()
        f.tabs.pageUIDelegate = answer
        let tab = try f.today("https://self-signed.example/page")
        f.sidebar.select(tab.id)
        let page = try #require(f.page(tab.id))
        Task { _ = await page.simulateCertificateError() }
        await f.settle()
        answer.pending?(false)
        await f.settle()
        #expect(f.page(tab.id) == nil)
        #expect(page.state == .closed)
        #expect(f.display.shown == nil)
        #expect(f.sidebar.selectedEntryID == tab.id)
        let entry = try #require(f.sidebarStore.entry(tab.id))
        #expect(entry.liveTitle == "self-signed.example")
        #expect(entry.currentURL == "https://self-signed.example/page")
    }

    @Test("Go Back with a page to go back to keeps the page")
    func goBackWithHistory() async throws {
        let f = try TabsFixture()
        let answer = CertificateAnswer()
        f.tabs.pageUIDelegate = answer
        let tab = try f.today("https://ok.example/")
        f.sidebar.select(tab.id)
        let page = try #require(f.page(tab.id))
        page.load(URL(string: "https://self-signed.example/page")!)
        Task { _ = await page.simulateCertificateError() }
        await f.settle()
        answer.pending?(false)
        await f.settle()
        #expect(f.page(tab.id) === page)
        #expect(f.display.shown === page)
    }
}
