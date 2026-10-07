import Foundation
import Model
import Testing
@testable import Store

/// Schema v9 (Phase 4.8a, spec §J, Arc's model): Today tabs belong to a
/// window; spaces, pinned entries, folders and essentials are shared.
@Suite("Store: windows (schema v9, per-window Today tabs)")
@MainActor
struct WindowsTests {
    /// A store with two windows on the seeded space; the first is the default.
    func twoWindows() throws -> (TestStore, UUID, UUID, UUID) {
        let test = try TestStore()
        let space = try #require(test.store.sidebar.spaces.first?.id)
        let first = test.store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space).id
        let second = test.store.windows.createWindow(frame: CGRect(x: 40, y: 40, width: 900, height: 700), sidebarWidth: 240,
                                                     space: space).id
        return (test, space, first, second)
    }

    @Test("Each window's Today list shows its own tabs; pinned entries, folders and essentials show in both")
    func perWindowToday() throws {
        let (test, space, first, second) = try twoWindows()
        let sidebar = test.store.sidebar
        let a = try sidebar.addEntry(.today, url: "https://a.example/", space: space)
        let b = try sidebar.addEntry(.today, url: "https://b.example/", space: space, window: second)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p.example/", space: space)
        let essential = try sidebar.addEntry(.essential, url: "https://e.example/", space: space)
        #expect(a.windowID == first && b.windowID == second)
        #expect(pinned.windowID == nil && essential.windowID == nil)
        #expect(sidebar.today(space: space, window: first).map(\.id) == [a.id])
        #expect(sidebar.today(space: space, window: second).map(\.id) == [b.id])
        // `nil` is the default window (the first, until the app names its key window).
        #expect(sidebar.today(space: space).map(\.id) == [a.id])
        for window in [first, second] {
            let snapshot = try #require(sidebar.snapshot(space: space, window: window))
            #expect(snapshot.pinned.map(\.entry.id) == [pinned.id] && snapshot.essentials.map(\.id) == [essential.id])
            #expect(sidebar.sidebarOrder(space: space, window: window).map(\.id)
                    == [essential.id, pinned.id, window == first ? a.id : b.id])
        }
        // Positions count within each window's list.
        #expect(a.position == 0 && b.position == 0)
        // The default window follows the app's key window.
        sidebar.defaultWindow = { second }
        #expect(sidebar.today(space: space).map(\.id) == [b.id])
    }

    @Test("A rename of a shared entry is one change both windows' lists read; a Today tab's container names its window")
    func sharedEdit() throws {
        let (test, space, _, second) = try twoWindows()
        let sidebar = test.store.sidebar
        let pinned = try sidebar.addEntry(.pinned, url: "https://p.example/", space: space)
        let b = try sidebar.addEntry(.today, url: "https://b.example/", space: space, window: second)
        var changes: [SidebarChange] = []
        let token = sidebar.observe { changes.append($0) }
        try sidebar.rename(pinned.id, to: "Renamed")
        #expect(changes.last?.entries == [pinned.id])
        #expect(sidebar.entry(pinned.id)?.displayTitle == "Renamed")
        #expect(sidebar.entry(b.id)?.container == .today(space: space, window: second))
        _ = token
    }

    @Test("Converting moves a window: pinned → a window's Today takes that window, Today → pinned is shared")
    func conversions() throws {
        let (test, space, first, second) = try twoWindows()
        let sidebar = test.store.sidebar
        let tab = try sidebar.addEntry(.today, url: "https://a.example/", space: space, window: second)
        try sidebar.move(tab.id, to: .pinned(space: space, folder: nil), at: 0)
        #expect(sidebar.entry(tab.id)?.kind == .pinned && sidebar.entry(tab.id)?.windowID == nil)
        try sidebar.move([tab.id], to: .today(space: space, window: second), insertingAt: 0)
        #expect(sidebar.entry(tab.id)?.windowID == second)
        #expect(sidebar.today(space: space, window: first).isEmpty)
        // Without a window the default one's list takes it.
        try sidebar.move(tab.id, to: .essentials(profile: sidebar.profiles[0].id), at: 0)
        #expect(sidebar.entry(tab.id)?.windowID == nil)
        try sidebar.move(tab.id, to: .today(space: space), at: 0)
        #expect(sidebar.entry(tab.id)?.windowID == first)
        // A Today tab moves to another window's list at the top (the drag out, Open in New Window).
        let other = try sidebar.addEntry(.today, url: "https://b.example/", space: space, window: second)
        try sidebar.moveToday(tab.id, toWindow: second)
        #expect(sidebar.today(space: space, window: second).map(\.id) == [tab.id, other.id])
        let pin = try sidebar.addEntry(.pinned, url: "https://p.example/", space: space)
        #expect(throws: SidebarError.invalidKind) { try sidebar.moveToday(pin.id, toWindow: first) }
    }

    @Test("Clear empties one window's list; closing a window archives its Today tabs with reason windowClosed")
    func clearAndClose() throws {
        let (test, space, first, second) = try twoWindows()
        let sidebar = test.store.sidebar
        let a = try sidebar.addEntry(.today, url: "https://a.example/", space: space, window: first)
        let b = try sidebar.addEntry(.today, url: "https://b.example/", space: space, window: second)
        let pinned = try sidebar.addEntry(.pinned, url: "https://p.example/", space: space)
        let removed = sidebar.clearToday(space: space, window: second)
        #expect(removed.map(\.entry.id) == [b.id] && sidebar.entry(a.id) != nil)
        sidebar.restore(removed)
        #expect(sidebar.today(space: space, window: second).map(\.id) == [b.id])
        let closed = sidebar.archiveToday(window: second)
        test.store.windows.removeWindow(second)
        #expect(closed.map(\.entry.id) == [b.id])
        #expect(sidebar.archive[b.id]?.reason == .windowClosed)
        #expect(sidebar.entry(a.id) != nil && sidebar.entry(pinned.id) != nil)
        #expect(test.store.windows.windows.map(\.id) == [first])
        // Restorable from the Library into a window.
        let back = try sidebar.restore(archived: b.id, activeSpace: space, window: first)
        #expect(back.windowID == first && sidebar.today(space: space, window: first).first?.id == back.id)
    }

    @Test("Window rows: created at the end with a frame; removed with their selections; the rest renumbered")
    func windowRows() throws {
        let (test, space, first, second) = try twoWindows()
        let windows = test.store.windows
        #expect(windows.windows.map(\.position) == [0, 1])
        #expect(windows.window(second)?.frame == CGRect(x: 40, y: 40, width: 900, height: 700))
        let pinned = try test.store.sidebar.addEntry(.pinned, url: "https://p.example/", space: space)
        windows.select(pinned.id, space: space, window: second)
        windows.select(pinned.id, space: space, window: first)
        #expect(Set(windows.windows(selecting: pinned.id)) == [first, second])
        windows.moveToFront(second)
        #expect(windows.windows.map(\.id) == [second, first] && windows.windows.map(\.position) == [0, 1])
        windows.removeWindow(first)
        #expect(windows.windows.map(\.id) == [second] && windows.windows[0].position == 0)
        #expect(windows.windows(selecting: pinned.id) == [second])
        #expect(windows.selectedEntry(space: space, window: first) == nil)
    }

    @Test("Window state and Today tabs survive a relaunch with both windows")
    func relaunch() async throws {
        let (test, space, first, second) = try twoWindows()
        let b = try test.store.sidebar.addEntry(.today, url: "https://b.example/", space: space, window: second)
        test.store.windows.setActiveSpace(space, window: second)
        test.store.close()
        let reopened = try test.reopen()
        #expect(reopened.windows.windows.map(\.id) == [first, second])
        #expect(reopened.windows.window(second)?.frame == CGRect(x: 40, y: 40, width: 900, height: 700))
        #expect(reopened.sidebar.today(space: space, window: second).map(\.id) == [b.id])
        #expect(reopened.sidebar.today(space: space, window: first).isEmpty)
        reopened.close()
    }

    @Test("Orphans (no window, or a window not open) join a window's lists at their ends")
    func adoptOrphans() throws {
        let test = try TestStore()
        let sidebar = test.store.sidebar
        let space = try #require(sidebar.spaces.first?.id)
        // No window yet: Today tabs are window-less.
        let loose = try sidebar.addEntry(.today, url: "https://a.example/", space: space)
        #expect(loose.windowID == nil)
        let window = test.store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space).id
        let gone = UUID()
        let stray = try sidebar.addEntry(.today, url: "https://b.example/", space: space, window: gone)
        let own = try sidebar.addEntry(.today, url: "https://c.example/", space: space, window: window)
        let orphans = Set(sidebar.todayOrphans(open: [window]).map(\.id))
        #expect(orphans == [loose.id, stray.id])
        #expect(sidebar.adoptTodayOrphans(into: window, open: [window]) == 2)
        #expect(sidebar.today(space: space, window: window).first?.id == own.id)
        #expect(Set(sidebar.today(space: space, window: window).map(\.id)) == [own.id, loose.id, stray.id])
        #expect(sidebar.adoptTodayOrphans(into: window, open: [window]) == 0)
    }

    @Test("Restore Sidebar maps a backup's windows onto the open ones; an unmapped window's Today tabs go to the current one")
    func remapWindows() throws {
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        let w1 = WindowState(sidebarWidth: 200, activeSpaceID: space.id, position: 0)
        let w2 = WindowState(sidebarWidth: 200, activeSpaceID: space.id, position: 1)
        let t1 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://1.example/", windowID: w1.id)
        let t2 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://2.example/", windowID: w2.id)
        let loose = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://3.example/")
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, storedURL: "https://p.example/")
        let state = RoomState(profiles: [profile], spaces: [space], entries: [t1, t2, loose, pinned], windows: [w2, w1],
                              windowSpaces: [WindowSpace(windowID: w1.id, spaceID: space.id, selectedEntryID: t1.id),
                                             WindowSpace(windowID: w2.id, spaceID: space.id, selectedEntryID: t2.id)])
        let open = UUID()
        let mapped = state.remappingWindows(onto: [open], current: open)
        #expect(mapped.windows.map(\.id) == [open])
        #expect(mapped.windowSpaces.map(\.selectedEntryID) == [t1.id])
        #expect(mapped.entries.filter { $0.kind == .today }.allSatisfy { $0.windowID == open })
        #expect(mapped.entries.first { $0.id == pinned.id }?.windowID == nil)
    }
}

/// The incognito window's store (4.8b, ROADMAP 4.8 task 7: nothing incognito is persisted).
@Suite("Incognito store")
@MainActor
struct IncognitoStoreTests {
    @Test("An incognito store holds one space of the active profile and writes nothing anywhere")
    func ephemeral() throws {
        let disk = try TestStore()
        let profile = try #require(disk.store.sidebar.profiles.first)
        var settings = disk.store.settings.settings
        settings.searchSuggestions = false
        let incognito = RoomStore.incognito(profile: profile, settings: settings, sidebarWidth: 240, themeColors: ["#26262C"])
        #expect(incognito.isEphemeral && !disk.store.isEphemeral)
        #expect(incognito.sidebar.profiles.map(\.id) == [profile.id])
        let space = try #require(incognito.sidebar.spaces.first)
        #expect(incognito.sidebar.spaces.count == 1 && space.profileID == profile.id && space.themeColors == ["#26262C"])
        #expect(incognito.windows.windows.count == 1 && incognito.windows.windows.first?.activeSpaceID == space.id)
        #expect(!incognito.settings.settings.searchSuggestions)
        // Today tabs live and go in memory; the disk store never sees them.
        let tab = try incognito.sidebar.addEntry(.today, url: "https://private.example/", title: "Private", space: space.id)
        #expect(incognito.sidebar.today(space: space.id).map(\.id) == [tab.id])
        incognito.flush()
        incognito.close()
        #expect(!FileManager.default.fileExists(atPath: incognito.storage.directory.path))
        let reopened = try disk.reopen()
        #expect(reopened.sidebar.entry(tab.id) == nil && reopened.sidebar.spaces.allSatisfy { $0.id != space.id })
    }
}
