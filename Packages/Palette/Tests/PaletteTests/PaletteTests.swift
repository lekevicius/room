import AppKit
import Engine
import FakeEngine
import Model
import Omnibox
import Sidebar
import Store
import Tabs
import Testing
@testable import Palette

@Suite("Palette semantics (spec §C)")
struct SemanticsTests {
    nonisolated static let entry = UUID(), other = UUID(), space = UUID()
    nonisolated static let page = "https://current.example/"
    nonisolated static let edit = PaletteMode.edit(entry: entry, url: page)
    nonisolated static let go = MatchAction.navigate(url: "https://go.example")
    nonisolated static let tab = MatchAction.switchToEntry(id: other, space: space, url: "https://tab.example")

    @Test("The §C commit table", arguments: [
        // ⌘T: Enter = new Today tab, ⌘Enter = current tab, ⌥Enter = background tab.
        (PaletteMode.new, go, CommitModifier.none, CommitAction.openTab(url: "https://go.example", background: false)),
        (.new, go, .command, .navigateCurrent(url: "https://go.example")),
        (.new, go, .option, .openTab(url: "https://go.example", background: true)),
        // ⌘L: Enter = current tab, ⌘Enter = new tab, ⌥Enter = background.
        (edit, go, .none, .navigateCurrent(url: "https://go.example")),
        (edit, go, .command, .openTab(url: "https://go.example", background: false)),
        (edit, go, .option, .openTab(url: "https://go.example", background: true)),
        // Searches commit like URLs.
        (.new, .search(query: "q", url: "https://s.example/?q=q"), .none, .openTab(url: "https://s.example/?q=q", background: false)),
        // Open tabs and pinned entries: Enter switches (to the space), ⌘Enter opens a copy.
        (.new, tab, .none, .switchTo(entry: other, space: space)),
        (edit, tab, .none, .switchTo(entry: other, space: space)),
        (.new, tab, .command, .openTab(url: "https://tab.example", background: false)),
        (.new, tab, .option, .openTab(url: "https://tab.example", background: true)),
    ])
    func commit(mode: PaletteMode, action: MatchAction, modifier: CommitModifier, expected: CommitAction) {
        #expect(PaletteSemantics.commit(mode: mode, action: action, textUnchanged: false, modifier: modifier, hasCurrent: true) == expected)
    }

    @Test("⌘L with the URL unchanged: Enter reloads, ⌘Enter opens it in a new tab")
    func unchanged() {
        #expect(PaletteSemantics.commit(mode: Self.edit, action: nil, textUnchanged: true, modifier: .none, hasCurrent: true) == .reloadCurrent)
        #expect(PaletteSemantics.commit(mode: Self.edit, action: nil, textUnchanged: true, modifier: .command, hasCurrent: true)
            == .openTab(url: Self.page, background: false))
    }

    @Test("⌘Enter from ⌘T without a page in the card opens a new tab; no rows commits nothing")
    func edges() {
        #expect(PaletteSemantics.commit(mode: .new, action: Self.go, textUnchanged: false, modifier: .command, hasCurrent: false)
            == .openTab(url: "https://go.example", background: false))
        #expect(PaletteSemantics.commit(mode: .new, action: nil, textUnchanged: false, modifier: .none, hasCurrent: true) == CommitAction.none)
    }

    @Test("Esc: ⌘L with edited text restores the URL; otherwise it closes")
    func escape() {
        #expect(PaletteSemantics.escape(mode: Self.edit, text: "typed") == .restore(Self.page))
        #expect(PaletteSemantics.escape(mode: Self.edit, text: Self.page) == .close)
        #expect(PaletteSemantics.escape(mode: .new, text: "typed") == .close)
    }

    @Test("Typed text is kept per tab for 45 s and used once")
    func memory() {
        var memory = TypedTextMemory(lifetime: 45)
        let start = Date(timeIntervalSince1970: 1000)
        memory.remember("half typed", for: Self.entry, at: start)
        #expect(memory.take(for: Self.other, at: start) == nil)
        #expect(memory.take(for: Self.entry, at: start.addingTimeInterval(45)) == "half typed")
        #expect(memory.take(for: Self.entry, at: start.addingTimeInterval(46)) == nil)
        memory.remember("late", for: Self.entry, at: start)
        #expect(memory.take(for: Self.entry, at: start.addingTimeInterval(46)) == nil)
    }
}

/// Records navigations the page was asked to make (reload vs load).
final class RecordingNavigation: NavigationDelegate {
    var actions: [NavigationAction] = []
    func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        actions.append(action)
        return .currentTab
    }
}

/// A window's sidebar, tab controller and palette on a fresh store, FakeEngine pages, no window.
final class PaletteFixture {
    let directory: URL
    let store: RoomStore
    let sidebar: SidebarController
    let tabs: TabController
    let palette: PaletteController
    /// The palette holds its host weakly (the window's content view in the app).
    let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    let engine = FakeApplication()
    let space: Space
    var clock = Date(timeIntervalSince1970: 1_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomPaletteTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try engine.initialize(EngineConfiguration(userDataDirectory: directory))
        store = try RoomStore.open(directory: directory)
        space = store.sidebar.spaces[0]
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        sidebar = SidebarController(store: store, windowID: window.id)
        tabs = TabController(store: store)
        tabs.sidebar = sidebar
        tabs.profile = try engine.profile(named: "Default")
        sidebar.host = tabs
        palette = PaletteController(hostView: hostView, tabs: tabs, sidebar: sidebar)
        palette.now = { [unowned self] in clock }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var today: [Entry] { store.sidebar.today(space: space.id) }

    @discardableResult
    func selectedTab(_ url: String) throws -> Entry {
        let entry = try store.sidebar.addEntry(.today, url: url, space: space.id)
        sidebar.select(entry.id)
        return entry
    }

    func page(_ id: UUID) -> FakeWebContents? { tabs.contents(for: id) as? FakeWebContents }

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@Suite("Palette on the tab controller (spec §C, FakeEngine)")
struct PaletteControllerTests {
    @Test("⌘T: no tab until Enter; Enter opens a selected Today tab at the typed URL and closes")
    func newTab() throws {
        let f = try PaletteFixture()
        f.palette.toggleNew()
        #expect(f.palette.isOpen)
        #expect(f.today.isEmpty)
        f.palette.setText("example.com")
        #expect(f.palette.result.matches.first?.action == .navigate(url: "https://example.com"))
        f.palette.commit(modifier: .none)
        #expect(!f.palette.isOpen)
        #expect(f.today.map(\.currentURL) == ["https://example.com"])
        #expect(f.sidebar.selectedEntryID == f.today.first?.id)
    }

    @Test("⌘T, ⌘Enter navigates the current tab; ⌥Enter opens a background tab")
    func modifiers() throws {
        let f = try PaletteFixture()
        let current = try f.selectedTab("https://a.example")
        f.palette.toggleNew()
        f.palette.setText("b.example.com")
        f.palette.commit(modifier: .command)
        #expect(f.page(current.id)?.url?.absoluteString == "https://b.example.com")
        #expect(f.today.count == 1)

        f.palette.toggleNew()
        f.palette.setText("swift concurrency")
        f.palette.commit(modifier: .option)
        #expect(f.today.count == 2)
        #expect(f.sidebar.selectedEntryID == current.id)
        let background = try #require(f.today.last)
        #expect(f.page(background.id)?.url?.absoluteString == "https://www.google.com/search?q=swift%20concurrency")
    }

    @Test("⌘L prefills the current URL; Enter unchanged reloads; edited, Enter navigates the current tab")
    func edit() throws {
        let f = try PaletteFixture()
        let current = try f.selectedTab("https://a.example/page")
        let recorder = RecordingNavigation()
        f.page(current.id)?.navigationDelegate = recorder
        f.palette.toggleEdit(docked: false)
        #expect(f.palette.mode == .edit(entry: current.id, url: "https://a.example/page"))
        #expect(f.palette.typedText == "https://a.example/page")
        #expect(f.palette.result.isEmpty)
        f.palette.commit(modifier: .none)
        #expect(recorder.actions.map(\.kind) == [.reload])

        f.palette.toggleEdit(docked: false)
        f.palette.setText("a.example/other")
        f.palette.commit(modifier: .none)
        #expect(recorder.actions.last?.url.absoluteString == "https://a.example/other")
        #expect(f.today.count == 1)
    }

    @Test("Esc in ⌘L restores the URL first, then closes; ⌘T/⌘L again closes")
    func escapeAndToggle() throws {
        let f = try PaletteFixture()
        try f.selectedTab("https://a.example")
        f.palette.toggleEdit(docked: false)
        f.palette.setText("typo")
        f.palette.escape()
        #expect(f.palette.isOpen)
        #expect(f.palette.typedText == "https://a.example")
        f.palette.escape()
        #expect(!f.palette.isOpen)
        f.palette.toggleNew()
        f.palette.toggleEdit(docked: false)
        #expect(!f.palette.isOpen)
    }

    @Test("Text typed in ⌘L and dismissed comes back on that tab within 45 s, not after")
    func typedTextKept() throws {
        let f = try PaletteFixture()
        try f.selectedTab("https://a.example")
        f.palette.toggleEdit(docked: false)
        f.palette.setText("half typed")
        f.palette.dismiss()
        f.clock += 30
        f.palette.toggleEdit(docked: false)
        #expect(f.palette.typedText == "half typed")
        f.palette.dismiss()
        f.clock += 46
        f.palette.toggleEdit(docked: false)
        #expect(f.palette.typedText == "https://a.example")
    }

    @Test("An open tab in another space: Enter switches to that space and selects it")
    func switchAcrossSpaces() throws {
        let f = try PaletteFixture()
        try f.selectedTab("https://a.example")
        let work = try f.store.sidebar.createSpace(name: "Work", profile: f.space.profileID)
        let tab = try f.store.sidebar.addEntry(.today, url: "https://linear.app/team", title: "Linear", space: work.id)
        f.palette.toggleNew()
        f.palette.setText("linear")
        let row = try #require(f.palette.result.matches.first { $0.provider == .openTabs })
        #expect(row.spaceName == "Work")
        f.palette.cycleGroup(backwards: false)
        f.palette.commit(modifier: .none)
        #expect(f.sidebar.activeSpaceID == work.id)
        #expect(f.sidebar.selectedEntryID == tab.id)
        #expect(f.tabs.currentEntryID == tab.id)
    }

    @Test("A tab switch while the palette is open dismisses it")
    func tabSwitchDismisses() async throws {
        let f = try PaletteFixture()
        try f.selectedTab("https://a.example")
        let other = try f.store.sidebar.addEntry(.today, url: "https://b.example", space: f.space.id)
        f.palette.toggleNew()
        f.sidebar.select(other.id)
        await f.settle()
        #expect(!f.palette.isOpen)
    }
}
