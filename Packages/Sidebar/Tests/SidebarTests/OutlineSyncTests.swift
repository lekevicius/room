import AppKit
import Chrome
import Model
import Omnibox
import Store
import Testing
@testable import Sidebar

/// A host without pages that records what the sidebar asked for.
final class RecordingHost: SidebarHost {
    var loaded: Set<UUID> = []
    var activated: [UUID] = []
    var unloaded: [UUID] = []

    func pageState(for entry: UUID) -> EntryPageState { EntryPageState(isLoaded: loaded.contains(entry)) }
    func activate(_ entry: Entry) {
        activated.append(entry.id)
        loaded.insert(entry.id)
    }
    func deactivate() {}
    func unload(_ entry: UUID) {
        unloaded.append(entry)
        loaded.remove(entry)
    }
    func reset(_ entry: Entry) {}
    func separate(_ entry: UUID, into newEntry: Entry) {
        loaded.remove(entry)
        loaded.insert(newEntry.id)
    }
    func reload(_ entry: UUID) {}
    func setMuted(_ muted: Bool, entry: UUID) {}
    func newTab() {}
    func editAddress() {}
}

/// A sidebar on a fresh store, its outline never in a window.
final class SidebarFixture {
    let directory: URL
    let store: RoomStore
    let controller: SidebarController
    let host = RecordingHost()
    let space: Space
    let profile: Profile

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomSidebarTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = try RoomStore.open(directory: directory)
        space = store.sidebar.spaces[0]
        profile = store.sidebar.profiles[0]
        let window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: space.id)
        controller = SidebarController(store: store, windowID: window.id)
        controller.host = host
        controller.bodyView.frame = NSRect(x: 0, y: 0, width: 240, height: 2000)
        controller.bodyView.layoutSubtreeIfNeeded()
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var sidebar: SidebarStore { store.sidebar }

    /// What NSOutlineView shows, row by row.
    func rows() -> [String] {
        let outline = controller.outline
        return (0..<outline.numberOfRows).map { row in
            let node = outline.item(atRow: row) as! OutlineNode
            let indent = String(repeating: "  ", count: outline.level(forRow: row))
            switch node.kind {
            case .spaceTitle: return "# " + (sidebar.space(space.id)?.name ?? "")
            case .separator: return "---"
            case .newTab: return "+ New Tab"
            case .entry(let id): return indent + EntryLabel.title(sidebar.entry(id)!)
            }
        }
    }

    /// What the spec says it should show: space title, pinned depth-first
    /// (a collapsed folder or section lists only the selected entry inside
    /// it), separator, Today, New Tab.
    func expectedRows() -> [String] {
        let selected = controller.selectedEntryID
        func contains(_ folder: UUID?, _ id: UUID) -> Bool {
            sidebar.pinned(space: space.id, folder: folder).contains { $0.id == id || ($0.kind == .folder && contains($0.id, id)) }
        }
        var rows = ["# " + (sidebar.space(space.id)?.name ?? "")]
        func walk(_ folder: UUID?, level: Int, collapsed: Bool) {
            if collapsed {
                if let selected, contains(folder, selected), let entry = sidebar.entry(selected) {
                    rows.append(String(repeating: "  ", count: level) + EntryLabel.title(entry))
                }
                return
            }
            for entry in sidebar.pinned(space: space.id, folder: folder) {
                rows.append(String(repeating: "  ", count: level) + EntryLabel.title(entry))
                if entry.kind == .folder { walk(entry.id, level: level + 1, collapsed: entry.isCollapsed) }
            }
        }
        walk(nil, level: 1, collapsed: sidebar.space(space.id)?.pinnedCollapsed == true)
        rows.append("---")
        rows += sidebar.today(space: space.id).map { EntryLabel.title($0) }
        rows.append("+ New Tab")
        return rows
    }
}

@Suite("Sidebar outline follows the store (rows reloaded per SidebarChange)")
struct OutlineSyncTests {
    @Test("A sequence of mutations keeps every row where the store says")
    func mutations() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        #expect(f.rows() == f.expectedRows())

        let a = try s.addEntry(.today, url: "https://a.example", title: "A", space: space)
        let b = try s.addEntry(.today, url: "https://b.example", title: "B", space: space)
        let c = try s.addEntry(.today, url: "https://c.example", title: "C", space: space)
        #expect(f.rows() == f.expectedRows())

        let docs = try s.addFolder(name: "Docs", space: space)
        let inner = try s.addFolder(name: "Inner", space: space, parent: docs.id)
        try s.move(a.id, to: .pinned(space: space, folder: nil), at: 0)
        try s.move(b.id, to: .pinned(space: space, folder: docs.id), at: 0)
        try s.move(c.id, to: .pinned(space: space, folder: inner.id), at: 0)
        #expect(f.rows() == f.expectedRows())

        // Reorder within a list, then across sections and back.
        try s.move(a.id, to: .pinned(space: space, folder: nil), at: 2)
        try s.move(b.id, to: .today(space: space), at: 0)
        try s.move(b.id, to: .pinned(space: space, folder: inner.id), at: 1)
        #expect(f.rows() == f.expectedRows())

        // Collapse with the selection inside: it peeks out under the folder.
        f.controller.select(c.id)
        try s.setFolderCollapsed(docs.id, true)
        #expect(f.rows() == f.expectedRows())
        #expect(f.rows().contains("    C"), "selected entry peeks under the collapsed top folder")
        f.controller.select(a.id)
        #expect(f.rows() == f.expectedRows())
        try s.setFolderCollapsed(docs.id, false)
        #expect(f.rows() == f.expectedRows())

        // Collapse the pinned section, rename, delete a folder (children move up), essentials leave the outline.
        try s.updateSpace(space) { $0.pinnedCollapsed = true }
        #expect(f.rows() == f.expectedRows())
        try s.updateSpace(space) { $0.pinnedCollapsed = false }
        try s.rename(c.id, to: "Renamed")
        try s.remove(inner.id)
        #expect(f.rows() == f.expectedRows())
        try s.move(a.id, to: .essentials(profile: f.profile.id), at: 0)
        #expect(f.rows() == f.expectedRows())
        #expect(f.controller.grid.tile(for: a.id) != nil)

        // Clear and Undo.
        for index in 0..<4 { try s.addEntry(.today, url: "https://t\(index).example", title: "T\(index)", space: space) }
        let removed = s.clearToday(space: space)
        #expect(f.rows() == f.expectedRows())
        s.restore(removed)
        #expect(f.rows() == f.expectedRows())
        #expect(f.controller.selectedEntryID == a.id)
    }

    @Test("Clear moves the selection off a Today tab to the most recent other entry; Undo brings it back")
    func clearAndUndo() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let pinned = try s.addEntry(.pinned, url: "https://p.example", title: "P", space: space)
        let tab = try s.addEntry(.today, url: "https://t.example", title: "T", space: space)
        f.controller.select(pinned.id)
        f.controller.select(tab.id)
        let toasts = RecordingToasts()
        f.controller.toasts = toasts
        f.controller.clearToday(nil)
        #expect(s.today(space: space).isEmpty)
        #expect(f.controller.selectedEntryID == pinned.id)
        #expect(f.host.unloaded.contains(tab.id))
        #expect(f.rows() == f.expectedRows())
        let toast = try #require(toasts.shown.last)
        #expect(toast.action?.title == "Undo")
        toast.action?.handler()
        #expect(s.today(space: space).map(\.id) == [tab.id])
        #expect(f.controller.selectedEntryID == tab.id)
        #expect(f.rows() == f.expectedRows())
    }

    @Test("Closing the selected Today tab selects the most recently used other entry (spec §A.7)")
    func closeSelectsMRU() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let first = try s.addEntry(.today, url: "https://1.example", title: "1", space: space)
        let second = try s.addEntry(.today, url: "https://2.example", title: "2", space: space)
        let third = try s.addEntry(.today, url: "https://3.example", title: "3", space: space)
        f.controller.select(first.id)
        try s.markActive(first.id, at: Timestamp(milliseconds: 1))
        try s.markActive(third.id, at: Timestamp(milliseconds: 2))
        f.controller.select(second.id)
        try s.markActive(second.id, at: Timestamp(milliseconds: 3))
        f.controller.perform(ClickRules.outcome(.middle, kind: .today, isSelected: true, isChanged: false, isLoaded: true),
                             on: second.id)
        #expect(s.entry(second.id) == nil)
        #expect(f.controller.selectedEntryID == third.id)
        #expect(f.rows() == f.expectedRows())
    }

    @Test("⌘-click separate: the page continues as a new selected Today tab, the pinned entry resets")
    func separate() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let pinned = try s.addEntry(.pinned, url: "https://mail.example.com", title: "Mail", space: space)
        f.controller.select(pinned.id)
        try s.setLivePage(pinned.id, url: "https://mail.example.com/thread", title: "Thread")
        #expect(f.controller.isChanged(s.entry(pinned.id)!))
        f.controller.perform(.separate, on: pinned.id)
        let tab = try #require(s.today(space: space).first)
        #expect(tab.liveURL == "https://mail.example.com/thread")
        #expect(f.controller.selectedEntryID == tab.id)
        #expect(s.entry(pinned.id)?.liveURL == "https://mail.example.com")
        #expect(!f.host.loaded.contains(pinned.id))
    }
}

@Suite("Sidebar drops and multi-selection (spec §A.6, §A.9)")
struct SidebarDropTests {
    @Test("A group drop converts across sections and the outline follows; the moved group leaves the multi-selection")
    func groupDrop() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let tabs = try (0..<4).map { try s.addEntry(.today, url: "https://\($0).example", title: "T\($0)", space: space) }
        f.controller.select(tabs[0].id)
        f.controller.perform(.toggleSelection, on: tabs[2].id)
        f.controller.perform(.toggleSelection, on: tabs[3].id)
        #expect(f.controller.multiSelection.ids == [tabs[0].id, tabs[2].id, tabs[3].id])
        #expect(f.controller.outline.selectedRowIndexes.count == 3, "AppKit's selection carries the group into a drag")
        let ids = f.controller.commandTargets(tabs[2].id)
        #expect(f.controller.performDrop(.insert(.pinned(space: space, folder: nil), index: 0, line: .init(boundary: 1, depth: 0)),
                                         ids: ids, copy: false, external: []))
        #expect(s.pinned(space: space).map(\.id) == ids)
        #expect(s.today(space: space).map(\.id) == [tabs[1].id])
        #expect(f.controller.multiSelection.isEmpty)
        #expect(f.rows() == f.expectedRows())
    }

    @Test("Dropping onto a pinned entry after the hold makes a folder with both (§A.6); ⌥ copies; a full grid refuses")
    func dropOnto() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let toasts = RecordingToasts()
        f.controller.toasts = toasts
        let pinned = try s.addEntry(.pinned, url: "https://p.example", title: "P", space: space)
        let tab = try s.addEntry(.today, url: "https://t.example", title: "T", space: space)
        #expect(f.controller.performDrop(.newFolder(with: pinned.id, row: 1), ids: [tab.id], copy: false, external: []))
        let folder = try #require(s.pinned(space: space).first)
        #expect(folder.kind == .folder && s.pinned(space: space).count == 1)
        #expect(s.pinned(space: space, folder: folder.id).map(\.id) == [pinned.id, tab.id])
        #expect(f.rows() == f.expectedRows())
        // ⌥-drag back to Today: a copy, the original stays in the folder.
        #expect(f.controller.performDrop(.insert(.today(space: space), index: .max, line: .init(boundary: 0, depth: 0)),
                                         ids: [tab.id], copy: true, external: []))
        #expect(s.today(space: space).count == 1 && s.entry(tab.id)?.folderID == folder.id)
        // Twelve essentials: one more is refused with a toast, nothing moves.
        for index in 0..<12 { try s.addEntry(.essential, url: "https://e\(index).example", space: space) }
        let before = f.store.currentState()
        #expect(!f.controller.performDrop(.insert(.essentials(profile: f.profile.id), index: 0, line: .init(boundary: 0, depth: 0)),
                                          ids: [pinned.id], copy: false, external: []))
        #expect(f.store.currentState() == before)
        #expect(toasts.shown.last?.id == "essentials-full")
    }

    @Test("URLs dropped from outside open as entries of the target's kind at the drop position; text becomes a search")
    func externalDrop() throws {
        let f = try SidebarFixture()
        let s = f.sidebar, space = f.space.id
        let first = try s.addEntry(.today, url: "https://first.example", space: space)
        #expect(f.controller.performDrop(.insert(.today(space: space), index: 0, line: .init(boundary: 0, depth: 0)), ids: [], copy: false,
                                         external: ["https://a.example", "https://b.example"]))
        #expect(s.today(space: space).map(\.liveURL) == ["https://a.example", "https://b.example", "https://first.example"])
        #expect(f.controller.selectedEntryID == s.today(space: space).first?.id, "the first dropped tab opens")
        #expect(f.host.activated.last == s.today(space: space).first?.id)
        #expect(f.controller.performDrop(.insert(.pinned(space: space, folder: nil), index: .max, line: .init(boundary: 0, depth: 0)),
                                         ids: [], copy: false, external: ["https://p.example"]))
        #expect(s.pinned(space: space).first?.storedURL == "https://p.example")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RoomSidebarTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("room browser", forType: .string)
        #expect(URLFixup.dropURLs(from: pasteboard) == ["https://www.google.com/search?q=room%20browser"])
        pasteboard.clearContents()
        pasteboard.setString("example.com\nhttps://swift.org", forType: .string)
        #expect(URLFixup.dropURLs(from: pasteboard) == ["https://example.com", "https://swift.org"])
        pasteboard.releaseGlobally()
        _ = first
    }
}

final class RecordingToasts: ToastPresenting {
    var shown: [Toast] = []
    func show(_ toast: Toast) { shown.append(toast) }
}

