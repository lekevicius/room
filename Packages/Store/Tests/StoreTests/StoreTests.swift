import Foundation
import Model
import Testing
@testable import Store

/// A store in a fresh temporary directory.
final class TestStore {
    let directory: URL
    private(set) var store: RoomStore

    init(debounce: Duration = .milliseconds(300)) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = try RoomStore.open(directory: directory, debounce: debounce)
    }

    /// Reopens from disk as a relaunch would (after `close()` or without it).
    func reopen(debounce: Duration = .milliseconds(300)) throws -> RoomStore {
        store = try RoomStore.open(directory: directory, debounce: debounce)
        return store
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

/// Delivers `Persistence.onCommit` generations in order; `next()` gives up
/// after a generous timeout so a broken pipeline fails instead of hanging.
final class CommitWaiter {
    private let stream: AsyncStream<Int64>
    private var iterator: AsyncStream<Int64>.Iterator

    init(_ persistence: Persistence, timeout: Duration = .seconds(30)) {
        let (stream, continuation) = AsyncStream.makeStream(of: Int64.self)
        self.stream = stream
        iterator = stream.makeAsyncIterator()
        persistence.onCommit = { continuation.yield($0) }
        Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }
    }

    func next() async -> Int64? {
        var current = iterator
        defer { iterator = current }
        return await current.next(isolation: #isolation)
    }
}

@Suite("Store: seed, persistence pipeline, window state")
struct PersistenceTests {
    @Test("First launch seeds profile Default with space Space and no entries")
    func seed() throws {
        let test = try TestStore()
        let store = test.store
        #expect(store.sidebar.profiles.map(\.name) == ["Default"])
        #expect(store.sidebar.spaces.map(\.name) == ["Space"])
        #expect(store.sidebar.spaces.first?.profileID == store.sidebar.profiles.first?.id)
        #expect(store.sidebar.entries.isEmpty)
        #expect(!store.uncleanExit)
        store.close()
        let reopened = try test.reopen()
        #expect(reopened.sidebar.profiles == store.sidebar.profiles)
        #expect(reopened.sidebar.spaces == store.sidebar.spaces, "not seeded twice")
    }

    @Test("Mutations within the debounce window coalesce into one write")
    func coalescing() async throws {
        let test = try TestStore(debounce: .milliseconds(80))
        let store = test.store
        let space = try #require(store.sidebar.spaces.first)
        let commits = CommitWaiter(store.persistence)
        let start = store.persistence.generation
        for index in 0..<20 { try store.sidebar.addEntry(.today, url: "https://example.com/\(index)", space: space.id) }
        #expect(store.persistence.generation == start, "nothing written before the timer fires")
        // Waits on the commit itself, not a fixed delay: at load 500 the timer can be seconds late.
        #expect(await commits.next() == start + 1)
        #expect(store.persistence.generation == start + 1 && !store.persistence.isDirty, "one write for all twenty")
        #expect(try store.storage.open().state.entries.count == 20)
    }

    @Test("flush writes immediately; close marks a clean exit; no close means unclean")
    func flushAndClose() throws {
        let test = try TestStore()
        let space = try #require(test.store.sidebar.spaces.first)
        try test.store.sidebar.addEntry(.today, url: "https://a.example", space: space.id)
        test.store.flush()
        let crashed = try test.reopen()
        #expect(crashed.uncleanExit)
        #expect(crashed.sidebar.today(space: space.id).map(\.liveURL) == ["https://a.example"])
        crashed.close()
        let clean = try test.reopen()
        #expect(!clean.uncleanExit)
    }

    @Test("An entry's navigation state goes out with the next debounced write, survives an unclean exit, and tells no observer")
    func navigationState() async throws {
        let test = try TestStore(debounce: .milliseconds(80))
        let store = test.store
        let space = try #require(store.sidebar.spaces.first)
        let entry = try store.sidebar.addEntry(.today, url: "https://a.example/2", space: space.id)
        let commits = CommitWaiter(store.persistence)
        #expect(await commits.next() != nil)
        var heard = 0
        let token = store.sidebar.observe { _ in heard += 1 }
        let start = store.persistence.generation
        try store.sidebar.setNavigationState(entry.id, Data("history".utf8))
        try store.sidebar.setNavigationState(entry.id, Data("history 2".utf8))
        #expect(await commits.next() == start + 1, "one transaction for both")
        #expect(heard == 0)
        // No close(): the next launch is an unclean one and still reads it (crash recovery).
        let reopened = try test.reopen()
        #expect(reopened.uncleanExit)
        #expect(reopened.sidebar.entry(entry.id)?.navigationState == Data("history 2".utf8))
        token.cancel()
    }

    @Test("Generations increase across launches")
    func generations() throws {
        let test = try TestStore()
        let space = try #require(test.store.sidebar.spaces.first)
        try test.store.sidebar.addEntry(.today, url: "https://a.example", space: space.id)
        test.store.close()
        let first = test.store.persistence.generation
        let second = try test.reopen()
        #expect(second.persistence.generation == first)
        try second.sidebar.addEntry(.today, url: "https://b.example", space: space.id)
        second.close()
        #expect(try second.storage.open().generation == first + 1)
    }

    @Test("Sidebar width and visibility persist per window (Chapter 1 carry-over)")
    func windowState() throws {
        let test = try TestStore()
        let space = try #require(test.store.sidebar.spaces.first)
        let window = test.store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        #expect(window.sidebarWidth == 240 && window.sidebarVisible && window.activeSpaceID == space.id)
        test.store.windows.setSidebarWidth(312, window: window.id)
        test.store.windows.setSidebarVisible(false, window: window.id)
        test.store.windows.setFrame(CGRect(x: 40, y: 60, width: 1300, height: 900), window: window.id)
        test.store.close()
        let reopened = try test.reopen()
        let restored = reopened.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        #expect(restored.id == window.id)
        #expect(restored.sidebarWidth == 312)
        #expect(!restored.sidebarVisible)
        #expect(restored.frame == CGRect(x: 40, y: 60, width: 1300, height: 900))
    }

    @Test("Selections per space per window persist and follow removals")
    func selections() throws {
        let test = try TestStore()
        let store = test.store
        let space = try #require(store.sidebar.spaces.first)
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        let tab = try store.sidebar.addEntry(.today, url: "https://a.example", space: space.id)
        store.windows.select(tab.id, space: space.id, window: window.id)
        store.close()
        let reopened = try test.reopen()
        #expect(reopened.windows.selectedEntry(space: space.id, window: window.id) == tab.id)
        try reopened.sidebar.remove(tab.id)
        #expect(reopened.windows.selectedEntry(space: space.id, window: window.id) == nil)
        reopened.close()
        #expect(try test.reopen().windows.selectedEntry(space: space.id, window: window.id) == nil)
    }

    @Test("Settings persist")
    func settings() throws {
        let test = try TestStore()
        test.store.settings.update { $0.permanentCloseBehavior = .close }
        test.store.close()
        #expect(try test.reopen().settings.settings.permanentCloseBehavior == .close)
    }

    @Test("After many mixed mutations the reopened state equals the in-memory state")
    func roundTrip() throws {
        let test = try TestStore()
        let store = test.store
        let profile = try #require(store.sidebar.profiles.first)
        let space = try #require(store.sidebar.spaces.first)
        let other = try store.sidebar.createSpace(name: "Other", profile: profile.id)
        let folder = try store.sidebar.addFolder(name: "F", space: space.id)
        for index in 0..<30 {
            let today = try store.sidebar.addEntry(.today, url: "https://e.example/\(index)", title: "T\(index)", space: space.id)
            switch index % 5 {
            case 0: try store.sidebar.move(today.id, to: .pinned(space: space.id, folder: folder.id), at: 0)
            case 1: try store.sidebar.move(today.id, to: .essentials(profile: profile.id), at: 0)
            case 2: try store.sidebar.move(today.id, to: .today(space: other.id), at: 0)
            case 3: try store.sidebar.markActive(today.id, at: Timestamp(milliseconds: Int64(index)))
            default: try store.sidebar.rename(today.id, to: "R\(index)")
            }
        }
        _ = try store.sidebar.createSplitGroup(Array(store.sidebar.today(space: space.id).prefix(2).map(\.id)))
        let expected = store.currentState().canonical()
        store.close()
        #expect(try test.reopen().currentState().canonical() == expected)
    }
}

@Suite("Store: sidebar mutations")
struct SidebarStoreTests {
    let test: TestStore
    var store: RoomStore { test.store }
    let space: Space
    let profile: Profile

    init() throws {
        test = try TestStore()
        space = try #require(test.store.sidebar.spaces.first)
        profile = try #require(test.store.sidebar.profiles.first)
    }

    var sidebar: SidebarStore { store.sidebar }

    @Test("Adding keeps positions contiguous per container")
    func positions() throws {
        let a = try sidebar.addEntry(.today, url: "https://a", space: space.id)
        let b = try sidebar.addEntry(.today, url: "https://b", space: space.id)
        let c = try sidebar.addEntry(.today, url: "https://c", space: space.id, at: 0)
        #expect(sidebar.today(space: space.id).map(\.id) == [c.id, a.id, b.id])
        #expect(sidebar.today(space: space.id).map(\.position) == [0, 1, 2])
        try sidebar.move(b.id, to: .today(space: space.id), at: 0)
        #expect(sidebar.today(space: space.id).map(\.id) == [b.id, c.id, a.id])
        #expect(sidebar.today(space: space.id).map(\.position) == [0, 1, 2])
    }

    @Test("Pinned entries store their URL and start unloaded; Today tabs carry the page")
    func kinds() throws {
        let pinned = try sidebar.addEntry(.pinned, url: "https://p", title: "P", space: space.id)
        #expect(pinned.storedURL == "https://p" && pinned.liveURL == nil)
        let today = try sidebar.addEntry(.today, url: "https://t", title: "T", space: space.id)
        #expect(today.liveURL == "https://t" && today.storedURL == nil)
        let essential = try sidebar.addEntry(.essential, url: "https://e", space: space.id)
        #expect(essential.spaceID == nil && essential.profileID == profile.id)
        #expect(throws: SidebarError.invalidKind) { try sidebar.addEntry(.folder, url: nil, space: space.id) }
    }

    @Test("Dragging across sections converts the type (§A.9)")
    func conversion() throws {
        let today = try sidebar.addEntry(.today, url: "https://a/page", title: "Page", space: space.id)
        try sidebar.move(today.id, to: .pinned(space: space.id, folder: nil), at: 0)
        let pinned = try #require(sidebar.entry(today.id))
        #expect(pinned.kind == .pinned && pinned.storedURL == "https://a/page")
        #expect(sidebar.today(space: space.id).isEmpty)
        try sidebar.move(today.id, to: .today(space: space.id), at: 0)
        let back = try #require(sidebar.entry(today.id))
        #expect(back.kind == .today && back.storedURL == nil && back.liveURL == "https://a/page")
    }

    @Test("A group drag lands together at the drop position, counted with the dragged rows still in place (§A.9)")
    func groupMove() throws {
        let tabs = try (0..<5).map { try sidebar.addEntry(.today, url: "https://t/\($0)", title: "T\($0)", space: space.id) }
        let (a, b, c, d, e) = (tabs[0].id, tabs[1].id, tabs[2].id, tabs[3].id, tabs[4].id)
        // Drop b and d on the gap above e.
        try sidebar.move([b, d], to: .today(space: space.id), insertingAt: 4)
        #expect(sidebar.today(space: space.id).map(\.id) == [a, c, b, d, e])
        // Drop a below the last row.
        try sidebar.move([a], to: .today(space: space.id), insertingAt: 5)
        #expect(sidebar.today(space: space.id).map(\.id) == [c, b, d, e, a])
        #expect(sidebar.today(space: space.id).map(\.position) == Array(0..<5))
        // Across a section boundary: both convert, in one change.
        var changes = 0
        let token = sidebar.observe { _ in changes += 1 }
        try sidebar.move([c, b], to: .pinned(space: space.id, folder: nil), insertingAt: 0)
        token.cancel()
        #expect(changes == 1)
        #expect(sidebar.pinned(space: space.id).map(\.id) == [c, b])
        #expect(sidebar.pinned(space: space.id).map(\.storedURL) == ["https://t/2", "https://t/1"])
        #expect(sidebar.pinned(space: space.id).allSatisfy { $0.kind == .pinned })
        #expect(sidebar.today(space: space.id).map(\.id) == [d, e, a])
    }

    @Test("A group drag into Essentials past the cap is refused whole (§A.9)")
    func groupMoveCap() throws {
        for index in 0..<11 { try sidebar.addEntry(.essential, url: "https://e/\(index)", space: space.id) }
        let one = try sidebar.addEntry(.today, url: "https://t/1", space: space.id)
        let two = try sidebar.addEntry(.today, url: "https://t/2", space: space.id)
        let essentials = Container.essentials(profile: profile.id)
        let before = store.currentState()
        #expect(throws: SidebarError.conversion(.essentialsFull(cap: 12))) {
            try sidebar.move([one.id, two.id], to: essentials, insertingAt: 0)
        }
        #expect(store.currentState() == before)
        #expect((try? sidebar.canMove([one.id, two.id], to: essentials).get()) == nil)
        #expect((try? sidebar.canMove([one.id], to: essentials).get()) != nil)
        try sidebar.move([one.id], to: essentials, insertingAt: 11)
        #expect(sidebar.essentials(profile: profile.id).count == 12)
        #expect(sidebar.entry(one.id)?.kind == .essential && sidebar.entry(one.id)?.storedURL == "https://t/1")
        // Folders never leave the pinned section.
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        #expect(throws: SidebarError.conversion(.folderOutsidePinned)) {
            try sidebar.move([folder.id], to: .today(space: space.id), insertingAt: 0)
        }
    }

    @Test("A folder dragged with its own child moves its subtree once (§A.9)")
    func groupMoveNested() throws {
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        let child = try sidebar.addEntry(.pinned, url: "https://c", space: space.id, folder: folder.id)
        let other = try sidebar.addEntry(.pinned, url: "https://o", space: space.id)
        try sidebar.move([folder.id, child.id], to: .pinned(space: space.id, folder: nil), insertingAt: 2)
        #expect(sidebar.pinned(space: space.id).map(\.id) == [other.id, folder.id])
        #expect(sidebar.pinned(space: space.id, folder: folder.id).map(\.id) == [child.id])
        // Into a folder: the dragged Today tab converts and nests.
        let tab = try sidebar.addEntry(.today, url: "https://t", space: space.id)
        try sidebar.move([tab.id], to: .pinned(space: space.id, folder: folder.id), insertingAt: 1)
        #expect(sidebar.pinned(space: space.id, folder: folder.id).map(\.id) == [child.id, tab.id])
        #expect(sidebar.entry(tab.id)?.kind == .pinned && sidebar.entry(tab.id)?.folderID == folder.id)
    }

    @Test("⌥-drag duplicates into the target section; the originals stay (§A.9)")
    func duplicate() throws {
        let tab = try sidebar.addEntry(.today, url: "https://t/page", title: "Page", space: space.id)
        try sidebar.markActive(tab.id)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p", title: "P", space: space.id)
        let copies = try sidebar.duplicate([tab.id], to: .pinned(space: space.id, folder: nil), at: 0)
        let copy = try #require(copies.first)
        #expect(copy.id != tab.id && copy.kind == .pinned && copy.storedURL == "https://t/page" && copy.lastActiveAt == nil)
        #expect(sidebar.pinned(space: space.id).map(\.id) == [copy.id, pinned.id])
        #expect(sidebar.entry(tab.id)?.kind == .today, "the original stays")
        let todayCopy = try #require(try sidebar.duplicate([pinned.id], to: .today(space: space.id), at: 1).first)
        #expect(todayCopy.kind == .today && todayCopy.liveURL == "https://p" && todayCopy.storedURL == nil)
        #expect(sidebar.today(space: space.id).map(\.id) == [tab.id, todayCopy.id])
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        #expect(throws: SidebarError.invalidKind) { try sidebar.duplicate([folder.id], to: .today(space: space.id), at: 0) }
        for index in 0..<12 { try sidebar.addEntry(.essential, url: "https://e/\(index)", space: space.id) }
        #expect(throws: SidebarError.conversion(.essentialsFull(cap: 12))) {
            try sidebar.duplicate([tab.id], to: .essentials(profile: profile.id), at: 0)
        }
    }

    @Test("The thirteenth essential is refused and nothing changes")
    func essentialsCap() throws {
        for index in 0..<12 { try sidebar.addEntry(.essential, url: "https://e/\(index)", space: space.id) }
        #expect(throws: SidebarError.conversion(.essentialsFull(cap: 12))) {
            try sidebar.addEntry(.essential, url: "https://e/12", space: space.id)
        }
        let today = try sidebar.addEntry(.today, url: "https://t", space: space.id)
        let before = store.currentState()
        #expect(throws: SidebarError.conversion(.essentialsFull(cap: 12))) {
            try sidebar.move(today.id, to: .essentials(profile: profile.id), at: 0)
        }
        #expect(store.currentState() == before)
        // Reordering within the full grid works.
        let last = try #require(sidebar.essentials(profile: profile.id).last)
        try sidebar.move(last.id, to: .essentials(profile: profile.id), at: 0)
        #expect(sidebar.essentials(profile: profile.id).first?.id == last.id)
    }

    @Test("Folders nest to depth 5; a sixth level and cycles are refused")
    func folderDepth() throws {
        var parent: UUID?
        var chain: [Entry] = []
        for level in 1...5 {
            let folder = try sidebar.addFolder(name: "L\(level)", space: space.id, parent: parent)
            chain.append(folder)
            parent = folder.id
        }
        #expect(throws: SidebarError.folder(.tooDeep(maxDepth: 5))) { try sidebar.addFolder(name: "L6", space: space.id, parent: parent) }
        #expect(throws: SidebarError.folder(.cycle)) {
            try sidebar.move(chain[1].id, to: .pinned(space: space.id, folder: chain[3].id), at: 0)
        }
        let tab = try sidebar.addEntry(.today, url: "https://deep", space: space.id)
        try sidebar.move(tab.id, to: .pinned(space: space.id, folder: chain[4].id), at: 0)
        #expect(sidebar.entry(tab.id)?.kind == .pinned)
        #expect(throws: SidebarError.conversion(.folderOutsidePinned)) { try sidebar.move(chain[0].id, to: .today(space: space.id), at: 0) }
    }

    @Test("Moving a folder to another space moves its subtree")
    func folderAcrossSpaces() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let outer = try sidebar.addFolder(name: "Outer", space: space.id)
        let inner = try sidebar.addFolder(name: "Inner", space: space.id, parent: outer.id)
        let leaf = try sidebar.addEntry(.pinned, url: "https://leaf", space: space.id, folder: inner.id)
        try sidebar.move(outer.id, to: .pinned(space: other.id, folder: nil), at: 0)
        #expect([outer.id, inner.id, leaf.id].allSatisfy { sidebar.entry($0)?.spaceID == other.id })
        #expect(sidebar.pinned(space: other.id, folder: inner.id).map(\.id) == [leaf.id])
        #expect(sidebar.pinned(space: space.id).isEmpty)
        store.close()
        let reopened = try test.reopen()
        #expect(reopened.sidebar.pinned(space: other.id, folder: inner.id).map(\.id) == [leaf.id])
    }

    @Test("Removing a folder moves its children into its place (§A.6 Delete)")
    func removeFolder() throws {
        let first = try sidebar.addEntry(.pinned, url: "https://1", space: space.id)
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        let last = try sidebar.addEntry(.pinned, url: "https://3", space: space.id)
        let a = try sidebar.addEntry(.pinned, url: "https://a", space: space.id, folder: folder.id)
        let b = try sidebar.addEntry(.pinned, url: "https://b", space: space.id, folder: folder.id)
        try sidebar.remove(folder.id)
        #expect(sidebar.pinned(space: space.id).map(\.id) == [first.id, a.id, b.id, last.id])
        #expect(sidebar.entry(a.id)?.folderID == nil)
    }

    @Test("Clear removes every Today tab; Undo restores them in order")
    func clearAndUndo() throws {
        let tabs = try (0..<5).map { try sidebar.addEntry(.today, url: "https://t/\($0)", space: space.id) }
        let pinned = try sidebar.addEntry(.pinned, url: "https://p", space: space.id)
        let removed = sidebar.clearToday(space: space.id)
        #expect(removed.count == 5)
        #expect(sidebar.today(space: space.id).isEmpty)
        #expect(sidebar.entry(pinned.id) != nil, "permanent entries survive Clear")
        sidebar.restore(removed)
        #expect(sidebar.today(space: space.id).map(\.id) == tabs.map(\.id))
        #expect(sidebar.today(space: space.id).map(\.position) == Array(0..<5))
    }

    @Test("Deleting a space removes its entries and repoints windows; the last space stays")
    func deleteSpace() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: other.id)
        let tab = try sidebar.addEntry(.today, url: "https://t", space: other.id)
        let essential = try sidebar.addEntry(.essential, url: "https://e", space: other.id)
        store.windows.select(tab.id, space: other.id, window: window.id)
        try sidebar.deleteSpace(other.id)
        #expect(sidebar.entry(tab.id) == nil)
        #expect(sidebar.entry(essential.id) != nil, "essentials belong to the profile")
        #expect(store.windows.window(window.id)?.activeSpaceID == space.id)
        #expect(store.windows.selectedEntry(space: other.id, window: window.id) == nil)
        #expect(throws: SidebarError.lastSpace) { try sidebar.deleteSpace(space.id) }
        store.close()
        #expect(try test.reopen().sidebar.spaces.map(\.id) == [space.id])
    }

    @Test("Spaces: created with their look at a position, reordered, positions contiguous (spec §B)")
    func spaceCRUD() throws {
        let b = try sidebar.createSpace(name: "B", profile: profile.id, icon: "🌲", themeColors: ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"],
                                        themeAlgorithm: .triadic, themeOpacity: 0.8)
        let a = try sidebar.createSpace(name: "A", profile: profile.id, at: 0)
        #expect(sidebar.spaces.map(\.id) == [a.id, space.id, b.id])
        #expect(sidebar.spaces.map(\.position) == [0, 1, 2])
        #expect(b.icon == "🌲" && b.themeAlgorithm == .triadic && b.themeOpacity == 0.8)
        #expect(b.themeColors == ["#FF0000", "#00FF00", "#0000FF"], "three colours at most")
        try sidebar.moveSpace(a.id, to: 2)
        #expect(sidebar.spaces.map(\.id) == [space.id, b.id, a.id])
        #expect(sidebar.spaces.map(\.position) == [0, 1, 2])
        try sidebar.updateSpace(b.id) { $0.name = "Bee"; $0.themeColors = ["#123456"]; $0.icon = "leaf" }
        #expect(sidebar.space(b.id)?.name == "Bee")
        #expect(sidebar.space(b.id)?.icon == "leaf")
        store.close()
        let reopened = try test.reopen().sidebar
        #expect(reopened.spaces.map(\.name) == ["Space", "Bee", "A"])
        #expect(reopened.space(b.id)?.themeAlgorithm == .triadic)
    }

    @Test("Profile names are unique ignoring case")
    func profileNames() {
        #expect(sidebar.createProfile(name: "Work").name == "Work")
        #expect(sidebar.createProfile(name: "work").name == "work 2")
        #expect(sidebar.createProfile(name: "default").name == "default 2")
    }

    @Test("Renaming a profile changes only its name, kept unique; an empty name is refused (B-22)")
    func renameProfile() throws {
        let work = sidebar.createProfile(name: "Work")
        let space = try sidebar.createSpace(name: "Office", profile: work.id)
        #expect(try sidebar.renameProfile(work.id, to: "  Job ") == "Job")
        #expect(try sidebar.renameProfile(work.id, to: "default") == "default 2")
        #expect(sidebar.profiles.first { $0.id == work.id }?.name == "default 2")
        #expect(sidebar.space(space.id)?.profileID == work.id)
        #expect(throws: SidebarError.emptyName) { try sidebar.renameProfile(work.id, to: " ") }
        store.close()
        #expect(try test.reopen().sidebar.profiles.map(\.name) == ["Default", "default 2"])
    }

    @Test("Deleting a profile archives its spaces' entries and Essentials and removes its spaces and rules; Default and the last space stay")
    func deleteProfile() throws {
        let work = sidebar.createProfile(name: "Work")
        let office = try sidebar.createSpace(name: "Office", profile: work.id)
        let lab = try sidebar.createSpace(name: "Lab", profile: work.id)
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: office.id)
        let tab = try sidebar.addEntry(.today, url: "https://t.example/", space: office.id)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p.example/", space: lab.id)
        let essential = try sidebar.addEntry(.essential, url: "https://e.example/", space: office.id)
        let kept = try sidebar.addEntry(.today, url: "https://kept.example/", space: space.id)
        let rule = try sidebar.addRoutingRule(.contains, pattern: "work", target: lab.id)
        #expect(throws: SidebarError.defaultProfile) { try sidebar.deleteProfile(profile.id) }
        try sidebar.deleteProfile(work.id)
        #expect(sidebar.profiles.map(\.id) == [profile.id])
        #expect(sidebar.spaces.map(\.id) == [space.id])
        for id in [tab.id, pinned.id, essential.id] {
            #expect(sidebar.entry(id) == nil)
            #expect(sidebar.archive[id]?.reason == .spaceDeleted)
        }
        #expect(sidebar.entry(kept.id) != nil)
        #expect(!sidebar.routingRules.contains { $0.id == rule.id })
        #expect(store.windows.window(window.id)?.activeSpaceID == space.id)
        let alone = sidebar.createProfile(name: "Alone")
        try sidebar.setSpaceProfile(space.id, to: alone.id)
        #expect(throws: SidebarError.lastSpace) { try sidebar.deleteProfile(alone.id) }
        store.close()
        let reopened = try test.reopen().sidebar
        #expect(reopened.profiles.map(\.name) == ["Default", "Alone"])
        #expect(reopened.archive[tab.id]?.profileID == work.id, "a row outlives its profile")
    }

    @Test("Set Profile moves the space's entries to the profile; essentials stay with theirs (spec §B)")
    func setProfile() throws {
        let work = sidebar.createProfile(name: "Work")
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        let child = try sidebar.addEntry(.pinned, url: "https://child", space: space.id, folder: folder.id)
        let tab = try sidebar.addEntry(.today, url: "https://t", space: space.id)
        let essential = try sidebar.addEntry(.essential, url: "https://e", space: space.id)
        let moved = try sidebar.setSpaceProfile(space.id, to: work.id)
        #expect(Set(moved.map(\.id)) == [child.id, tab.id])
        #expect(sidebar.space(space.id)?.profileID == work.id)
        for id in [folder.id, child.id, tab.id] { #expect(sidebar.entry(id)?.profileID == work.id) }
        #expect(sidebar.entry(essential.id)?.profileID == profile.id)
        #expect(sidebar.essentials(profile: work.id).isEmpty)
        #expect(try sidebar.setSpaceProfile(space.id, to: work.id).isEmpty, "already there")
        #expect(throws: SidebarError.unknownProfile(space.id)) { try sidebar.setSpaceProfile(space.id, to: space.id) }
    }

    @Test("Undo of Delete Space puts it back at its place with its entries in order (B-15)")
    func restoreSpace() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let last = try sidebar.createSpace(name: "Last", profile: profile.id)
        let folder = try sidebar.addFolder(name: "F", space: other.id)
        let child = try sidebar.addEntry(.pinned, url: "https://child", space: other.id, folder: folder.id)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p", space: other.id)
        let tabs = try (0..<3).map { try sidebar.addEntry(.today, url: "https://t\($0)", space: other.id) }
        let removed = try sidebar.deleteSpace(other.id)
        #expect(removed.index == 1)
        #expect(removed.entries.count == 6)
        #expect(sidebar.spaces.map(\.id) == [space.id, last.id])
        sidebar.restoreSpace(removed)
        #expect(sidebar.spaces.map(\.id) == [space.id, other.id, last.id])
        #expect(sidebar.spaces.map(\.position) == [0, 1, 2])
        #expect(sidebar.pinned(space: other.id).map(\.id) == [folder.id, pinned.id])
        #expect(sidebar.pinned(space: other.id, folder: folder.id).map(\.id) == [child.id])
        #expect(sidebar.today(space: other.id).map(\.id) == tabs.map(\.id))
        sidebar.restoreSpace(removed)
        #expect(sidebar.spaces.count == 3, "a second Undo does nothing")
    }

    @Test("Reset, replace and isChanged on a pinned entry (§A.5)")
    func resetAndReplace() throws {
        let pinned = try sidebar.addEntry(.pinned, url: "https://site/", title: "Site", space: space.id)
        try sidebar.setLivePage(pinned.id, url: "https://site#top", title: "Site")
        #expect(!sidebar.isChanged(pinned.id))
        try sidebar.setLivePage(pinned.id, url: "https://site/deeper", title: "Deeper")
        #expect(sidebar.isChanged(pinned.id))
        try sidebar.resetToStoredURL(pinned.id)
        #expect(sidebar.entry(pinned.id)?.liveURL == "https://site/" && !sidebar.isChanged(pinned.id))
        try sidebar.setLivePage(pinned.id, url: "https://site/new", title: "New")
        try sidebar.replaceStoredURLWithCurrent(pinned.id)
        #expect(sidebar.entry(pinned.id)?.storedURL == "https://site/new" && !sidebar.isChanged(pinned.id))
    }

    @Test("⌘W plan and ⌘1–9 order through the store")
    func closePlanAndOrder() throws {
        let essential = try sidebar.addEntry(.essential, url: "https://e", space: space.id)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p", space: space.id)
        let today = try sidebar.addEntry(.today, url: "https://t", space: space.id)
        #expect(sidebar.sidebarOrder(space: space.id).map(\.id) == [essential.id, pinned.id, today.id])
        try sidebar.markActive(essential.id, at: Timestamp(milliseconds: 10))
        try sidebar.markActive(pinned.id, at: Timestamp(milliseconds: 20))
        let plan = try #require(sidebar.closePlan(for: pinned.id, behavior: .resetUnloadSwitch, space: space.id))
        #expect(plan.steps == [.switchAway, .unload, .reset])
        #expect(plan.fallback == .select(essential.id))
        #expect(sidebar.mruOrder(space: space.id).map(\.id) == [pinned.id, essential.id, today.id])
        let resetOnly = try #require(sidebar.closePlan(for: pinned.id, behavior: .reset, space: space.id))
        #expect(resetOnly.fallback == nil)
    }

    @Test("Observers get the touched ids, not the whole tree")
    func changes() throws {
        var received: [SidebarChange] = []
        let token = sidebar.observe { received.append($0) }
        let a = try sidebar.addEntry(.today, url: "https://a", space: space.id)
        try sidebar.rename(a.id, to: "A")
        try sidebar.rename(a.id, to: "A") // no-op: no change event
        try sidebar.remove(a.id)
        token.cancel()
        _ = try sidebar.addEntry(.today, url: "https://b", space: space.id)
        #expect(received.count == 3)
        #expect(received[0].entries == [a.id] && received[0].containers == [.today(space: space.id)])
        #expect(received[1] == SidebarChange(entries: [a.id]))
        #expect(received[2].removedEntries == [a.id] && !received[2].entries.contains(a.id))
    }

    @Test("Snapshot nests the pinned tree")
    func snapshot() throws {
        let folder = try sidebar.addFolder(name: "F", space: space.id)
        let child = try sidebar.addEntry(.pinned, url: "https://c", space: space.id, folder: folder.id)
        let snapshot = try #require(sidebar.snapshot(space: space.id))
        #expect(snapshot.pinned.map(\.entry.id) == [folder.id])
        #expect(snapshot.pinned.first?.children.map(\.entry.id) == [child.id])
    }
}

@Suite("Store: the Archive (schema v7, spec §A.7 and §H)")
struct ArchiveStoreTests {
    let test: TestStore
    var store: RoomStore { test.store }
    let space: Space
    let profile: Profile
    var sidebar: SidebarStore { store.sidebar }

    init() throws {
        test = try TestStore()
        space = try #require(test.store.sidebar.spaces.first)
        profile = try #require(test.store.sidebar.profiles.first)
    }

    @Test("Archive removes the entry and writes its row with the reason and the navigation state; it survives a relaunch")
    func archiveWritesRow() throws {
        sidebar.clock = { Timestamp(milliseconds: 1_000_000) }
        let tab = try sidebar.addEntry(.today, url: "https://a.example/page", title: "A", space: space.id)
        try sidebar.setNavigationState(tab.id, Data([9, 8, 7]))
        let other = try sidebar.addEntry(.today, url: "https://b.example/", space: space.id)
        let removed = sidebar.archive([tab.id], reason: .manual)
        #expect(removed.map(\.entry.id) == [tab.id])
        #expect(sidebar.entry(tab.id) == nil && sidebar.entry(other.id) != nil)
        let row = try #require(sidebar.archive[tab.id])
        #expect(row.url == "https://a.example/page" && row.title == "A" && row.reason == .manual && row.spaceID == space.id)
        #expect(row.archivedAt == Timestamp(milliseconds: 1_000_000) && row.navigationState == Data([9, 8, 7]))
        #expect(sidebar.archivedCount == 1 && sidebar.archivedCount(reason: .manual) == 1)
        store.close()
        let reopened = try test.reopen().sidebar
        #expect(reopened.archive[tab.id] == row)
    }

    @Test("Restore puts the row back at the top of its space as a Today tab and deletes the row")
    func restoreToItsSpace() throws {
        let first = try sidebar.addEntry(.today, url: "https://first.example/", space: space.id)
        let tab = try sidebar.addEntry(.today, url: "https://a.example/", title: "A", space: space.id)
        try sidebar.setNavigationState(tab.id, Data([1]))
        sidebar.archive([tab.id], reason: .auto)
        sidebar.clock = { Timestamp(milliseconds: 5_000) }
        let restored = try sidebar.restore(archived: tab.id, activeSpace: nil)
        #expect(sidebar.today(space: space.id).map(\.id) == [restored.id, first.id])
        #expect(restored.kind == .today && restored.liveURL == "https://a.example/" && restored.liveTitle == "A")
        #expect(restored.navigationState == Data([1]), "back/forward comes back")
        #expect(restored.lastActiveAt == Timestamp(milliseconds: 5_000), "the next sweep does not take it again")
        #expect(sidebar.archive.isEmpty)
        #expect(throws: SidebarError.unknownEntry(tab.id)) { try sidebar.restore(archived: tab.id, activeSpace: nil) }
    }

    @Test("A row whose space is gone restores to the active space, in that space's profile")
    func restoreWhenSpaceGone() throws {
        let work = sidebar.createProfile(name: "Work")
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let elsewhere = try sidebar.createSpace(name: "Elsewhere", profile: work.id)
        let tab = try sidebar.addEntry(.today, url: "https://gone.example/", space: other.id)
        try sidebar.deleteSpace(other.id)
        #expect(sidebar.archive[tab.id]?.reason == .spaceDeleted)
        let restored = try sidebar.restore(archived: tab.id, activeSpace: elsewhere.id)
        #expect(restored.spaceID == elsewhere.id && restored.profileID == work.id)
        #expect(sidebar.today(space: elsewhere.id).first?.id == restored.id)
    }

    @Test("Clear writes its tabs to the Archive (reason clear); Undo puts them back in order and takes the rows out")
    func clearGoesThroughTheArchive() throws {
        let tabs = try (0..<4).map { try sidebar.addEntry(.today, url: "https://t.example/\($0)", space: space.id) }
        let removed = sidebar.clearToday(space: space.id)
        #expect(sidebar.archivedCount(reason: .clear) == 4)
        sidebar.restore(removed)
        #expect(sidebar.today(space: space.id).map(\.id) == tabs.map(\.id))
        #expect(sidebar.archive.isEmpty)
    }

    @Test("Deleting a space archives its entries with a page (B-15); its Undo takes them back out")
    func deleteSpaceArchives() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let folder = try sidebar.addFolder(name: "F", space: other.id)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p.example/", title: "P", space: other.id, folder: folder.id)
        let tab = try sidebar.addEntry(.today, url: "https://t.example/", space: other.id)
        let removed = try sidebar.deleteSpace(other.id)
        #expect(Set(sidebar.archive.keys) == [pinned.id, tab.id], "the folder has no row")
        #expect(sidebar.archivedCount(reason: .spaceDeleted) == 2)
        sidebar.restoreSpace(removed)
        #expect(sidebar.archive.isEmpty && sidebar.entry(pinned.id) != nil && sidebar.entry(tab.id) != nil)
    }

    @Test("Routing rules (spec §B): added, edited, reordered and enabled; an invalid regex is refused and nothing is saved; they survive a relaunch")
    func routingRules() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let a = try sidebar.addRoutingRule(.contains, pattern: " github ", target: other.id)
        let b = try sidebar.addRoutingRule(.equals, pattern: "example.com", target: space.id)
        #expect(a.pattern == "github" && a.enabled)
        #expect(throws: SidebarError.routingPattern(RoutingRules.validate(.regex, pattern: "([a-z")!)) {
            try sidebar.addRoutingRule(.regex, pattern: "([a-z", target: space.id)
        }
        #expect(throws: SidebarError.self) { try sidebar.updateRoutingRule(a.id) { $0.match = .regex; $0.pattern = "(" } }
        #expect(sidebar.routingRules.map(\.id) == [a.id, b.id] && sidebar.routingRules[0].match == .contains, "the refused edit left the rule as it was")
        #expect(throws: SidebarError.unknownSpace(a.id)) { try sidebar.updateRoutingRule(a.id) { $0.targetSpaceID = a.id } }
        try sidebar.moveRoutingRule(b.id, to: 0)
        #expect(sidebar.routingRules.map(\.id) == [b.id, a.id] && sidebar.routingRules.map(\.position) == [0, 1])
        try sidebar.updateRoutingRule(a.id) { $0.enabled = false }
        let c = try sidebar.addRoutingRule(.regex, pattern: #"^https://docs\."#, target: other.id)
        sidebar.removeRoutingRule(b.id)
        #expect(sidebar.routingRules.map(\.id) == [a.id, c.id] && sidebar.routingRules.map(\.position) == [0, 1])
        store.close()
        let reopened = try test.reopen().sidebar
        #expect(reopened.routingRules.map(\.id) == [a.id, c.id])
        #expect(reopened.routingRules.first?.enabled == false && reopened.routingRules.last?.match == .regex)
    }

    @Test("Deleting a space deletes the rules targeting it (spec §B); its Undo brings them back in place")
    func deleteSpaceDeletesItsRules() throws {
        let other = try sidebar.createSpace(name: "Other", profile: profile.id)
        let first = try sidebar.addRoutingRule(.contains, pattern: "one", target: space.id)
        let gone = try sidebar.addRoutingRule(.contains, pattern: "two", target: other.id)
        let last = try sidebar.addRoutingRule(.equals, pattern: "three.example", target: space.id)
        let removed = try sidebar.deleteSpace(other.id)
        #expect(removed.routingRules.map(\.id) == [gone.id])
        #expect(sidebar.routingRules.map(\.id) == [first.id, last.id] && sidebar.routingRules.map(\.position) == [0, 1])
        sidebar.restoreSpace(removed)
        #expect(sidebar.routingRules.map(\.id) == [first.id, gone.id, last.id] && sidebar.routingRules.map(\.position) == [0, 1, 2])
        _ = try sidebar.deleteSpace(other.id)
        store.close()
        #expect(try test.reopen().sidebar.routingRules.map(\.id) == [first.id, last.id], "the deletion was written with the space's")
    }

    @Test("Archive Below's undo keeps the order; the queries group by day and match text")
    func archiveBelowAndQueries() throws {
        let tabs = try (0..<4).map { try sidebar.addEntry(.today, url: "https://site\($0).example/", title: "Tab \($0)", space: space.id) }
        sidebar.clock = { Timestamp(milliseconds: 86_400_000 * 10 + 3_600_000) }
        let removed = sidebar.archive([tabs[2].id, tabs[3].id], reason: .manual)
        sidebar.clock = { Timestamp(milliseconds: 86_400_000 * 11 + 3_600_000) }
        sidebar.archive([tabs[0].id], reason: .manual)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let days = sidebar.archivedByDay(calendar: utc)
        #expect(days.map(\.rows.count) == [1, 2], "newest day first")
        #expect(sidebar.archivedEntries(matching: "SITE3").map(\.id) == [tabs[3].id])
        #expect(sidebar.archivedEntries(matching: "tab site2").map(\.id) == [tabs[2].id])
        sidebar.restore(removed)
        #expect(sidebar.today(space: space.id).map(\.id) == [tabs[1].id, tabs[2].id, tabs[3].id])
        sidebar.deleteArchived([tabs[0].id])
        #expect(sidebar.archive.isEmpty)
    }

    @Test("Retention (B-80): rows older than the span go, rows past the shorter one lose their navigation state; both survive a relaunch")
    func retention() throws {
        let day: Int64 = 86_400_000
        let tabs = try (0..<3).map { try sidebar.addEntry(.today, url: "https://r\($0).example/", space: space.id) }
        for tab in tabs { try sidebar.setNavigationState(tab.id, Data([1, 2, 3])) }
        // Archived 40, 10 and 2 days before "now" (day 100).
        for (tab, at) in zip(tabs, [60, 90, 98]) {
            sidebar.clock = { Timestamp(milliseconds: day * Int64(at)) }
            sidebar.archive([tab.id], reason: .auto)
        }
        let plan = sidebar.applyArchiveRetention(now: Timestamp(milliseconds: day * 100), rows: 30 * 86_400, navigationState: 7 * 86_400)
        #expect(plan.prune == [tabs[0].id] && plan.dropNavigationState == [tabs[1].id])
        #expect(sidebar.archive[tabs[0].id] == nil)
        #expect(sidebar.archive[tabs[1].id]?.navigationState == nil && sidebar.archive[tabs[2].id]?.navigationState == Data([1, 2, 3]))
        store.close()
        let reopened = try test.reopen().sidebar
        #expect(reopened.archive.count == 2)
        #expect(reopened.archive[tabs[1].id]?.navigationState == nil && reopened.archive[tabs[2].id]?.navigationState == Data([1, 2, 3]))
    }
}

@Suite("Store: Restore Sidebar (spec §H, ROADMAP 4.1b task 6)")
struct RestoreSidebarTests {
    @Test("A backup's spaces, entries, splits, selections and Archive replace the current ones in one write; profiles stay")
    func restore() throws {
        let test = try TestStore()
        let store = test.store
        let sidebar = store.sidebar
        let profile = try #require(sidebar.profiles.first)
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: sidebar.spaces.first?.id)
        let first = try #require(sidebar.spaces.first)
        let second = try sidebar.createSpace(name: "Two", profile: profile.id)
        let tab = try sidebar.addEntry(.today, url: "https://kept.example/", space: second.id)
        store.windows.select(tab.id, space: second.id, window: window.id)
        store.windows.setActiveSpace(second.id, window: window.id)
        store.flush()
        let backups = store.backups
        let file = try backups.take(from: store.persistence.writer.database, at: Date())
        // After the backup: the space is deleted, a new tab and a new profile appear.
        _ = try sidebar.deleteSpace(second.id)
        let later = try sidebar.addEntry(.today, url: "https://later.example/", space: first.id)
        let newProfile = sidebar.createProfile(name: "Later")
        store.flush()
        let before = store.persistence.generation
        let backup = try backups.loadState(file)
        store.restoreSidebar(from: backup.state, window: window.id)
        #expect(sidebar.space(second.id) != nil && sidebar.entry(tab.id) != nil)
        #expect(sidebar.entry(later.id) == nil)
        #expect(sidebar.profiles.contains { $0.id == newProfile.id })
        #expect(store.windows.selectedEntry(space: second.id, window: window.id) == tab.id)
        #expect(store.windows.window(window.id)?.activeSpaceID == second.id)
        #expect(store.persistence.generation == before + 1)
        #expect(try store.persistence.writer.database.generation() == before + 1)
        store.close()
        let reopened = try test.reopen()
        #expect(reopened.sidebar.space(second.id) != nil && reopened.sidebar.entry(tab.id) != nil)
        #expect(reopened.sidebar.entry(later.id) == nil)
        #expect(reopened.windows.selectedEntry(space: second.id, window: window.id) == tab.id)
    }
}

@Suite("Store: split groups (spec §D)")
struct SplitGroupStoreTests {
    let test: TestStore
    let space: Space

    init() throws {
        test = try TestStore()
        space = try #require(test.store.sidebar.spaces.first)
    }

    var sidebar: SidebarStore { test.store.sidebar }

    private func tabs(_ count: Int) throws -> [Entry] {
        try (0..<count).map { try sidebar.addEntry(.today, url: "https://\($0).example", space: space.id) }
    }

    @Test("A split keeps its panes in order with equal sizes; at most four; essentials and folders are refused")
    func create() throws {
        let t = try tabs(5)
        let group = try sidebar.createSplitGroup([t[2].id, t[0].id], layout: .vbox)
        #expect(sidebar.splitMembers(group.id).map(\.id) == [t[2].id, t[0].id])
        #expect(group.ratios == [0.5, 0.5])
        #expect(sidebar.splitGroup(of: t[0].id)?.id == group.id)
        try sidebar.addToSplitGroup(t[1].id, group: group.id, at: 1)
        try sidebar.addToSplitGroup(t[3].id, group: group.id)
        #expect(sidebar.splitMembers(group.id).map(\.id) == [t[2].id, t[1].id, t[0].id, t[3].id])
        #expect(throws: SidebarError.splitFull) { try sidebar.addToSplitGroup(t[4].id, group: group.id) }
        let essential = try sidebar.addEntry(.essential, url: "https://e", space: space.id)
        #expect(throws: SidebarError.invalidKind) { try sidebar.createSplitGroup([essential.id, t[4].id]) }
    }

    @Test("A split left with one pane dissolves (leaving, closing, becoming an essential); Undo of a close rejoins")
    func dissolve() throws {
        let t = try tabs(4)
        let group = try sidebar.createSplitGroup([t[0].id, t[1].id, t[2].id])
        let removed = try sidebar.remove(t[1].id)
        #expect(sidebar.splitMembers(group.id).map(\.id) == [t[0].id, t[2].id])
        sidebar.restore([removed])
        #expect(sidebar.splitMembers(group.id).map(\.id) == [t[0].id, t[2].id, t[1].id])
        try sidebar.move(t[2].id, to: .essentials(profile: space.profileID), at: 0)
        #expect(sidebar.splitGroup(of: t[2].id) == nil)
        sidebar.removeFromSplitGroup(t[1].id)
        #expect(sidebar.splitGroups[group.id] == nil)
        #expect(sidebar.splitGroup(of: t[0].id) == nil)
    }

    @Test("Layout changes start equal; sizes that do not fit become equal; the grip moves a pane with its size")
    func layoutAndRatios() throws {
        let t = try tabs(3)
        let group = try sidebar.createSplitGroup(t.map(\.id))
        try sidebar.setSplitRatios(group.id, [0.2, 0.3, 0.5])
        #expect(sidebar.splitGroups[group.id]?.ratios == [0.2, 0.3, 0.5])
        try sidebar.moveSplitMember(group.id, from: 0, to: 2)
        #expect(sidebar.splitGroups[group.id]?.members == [t[1].id, t[2].id, t[0].id])
        #expect(sidebar.splitGroups[group.id]?.ratios == [0.3, 0.5, 0.2])
        try sidebar.setSplitLayout(group.id, .grid)
        #expect(sidebar.splitGroups[group.id]?.ratios == [0.5, 0.5, 0.5, 0.5])
        try sidebar.setSplitRatios(group.id, [0.9, 0.9])
        #expect(sidebar.splitGroups[group.id]?.ratios == [0.5, 0.5, 0.5, 0.5])
    }

    @Test("A pane's place goes to another entry (a drop in its centre); a split survives a relaunch")
    func replaceAndReopen() throws {
        let t = try tabs(3)
        let group = try sidebar.createSplitGroup([t[0].id, t[1].id])
        try sidebar.replaceSplitMember(t[0].id, with: t[2].id)
        #expect(sidebar.splitMembers(group.id).map(\.id) == [t[2].id, t[1].id])
        #expect(sidebar.splitGroup(of: t[0].id) == nil)
        test.store.close()
        let reopened = try test.reopen()
        #expect(reopened.sidebar.splitMembers(group.id).map(\.id) == [t[2].id, t[1].id])
    }
}

@Suite("Reopen stack (⇧⌘T)")
struct ClosedTabStackTests {
    @Test("The reopen stack keeps the 25 most recent closes")
    func stackCapacity() {
        var stack = ClosedTabStack()
        let space = UUID(), profile = UUID()
        for index in 0..<30 {
            let entry = Entry(kind: .today, spaceID: space, profileID: profile, position: index, liveURL: "https://\(index).example")
            stack.push(.removed([RemovedEntry(entry: entry, index: index)]))
        }
        stack.push(.removed([]))
        #expect(stack.items.count == ClosedTabStack.capacity)
        guard case .removed(let newest)? = stack.pop() else { Issue.record("no item"); return }
        #expect(newest.first?.index == 29)
    }

}
