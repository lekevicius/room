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
