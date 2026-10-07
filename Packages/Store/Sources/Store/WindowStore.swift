import Foundation
import Model
import Observation

/// The only writer of window state: frame, sidebar width and visibility,
/// active space, and the selected entry per space per window.
@Observable
public final class WindowStore {
    /// Ordered by position.
    public private(set) var windows: [WindowState]
    @ObservationIgnored private var selections: [SelectionKey: UUID]
    @ObservationIgnored weak var persistence: Persistence?

    struct SelectionKey: Hashable {
        var window: UUID
        var space: UUID
    }

    init(state: RoomState) {
        windows = state.windows.sorted { $0.position < $1.position }
        selections = [:]
        for row in state.windowSpaces {
            if let entry = row.selectedEntryID { selections[SelectionKey(window: row.windowID, space: row.spaceID)] = entry }
        }
    }

    public func window(_ id: UUID) -> WindowState? { windows.first { $0.id == id } }

    /// The first stored window, or a new one showing `space`.
    @discardableResult
    public func restoreOrCreateWindow(defaultSidebarWidth: Double, space: UUID?) -> WindowState {
        if let first = windows.first { return first }
        let window = WindowState(sidebarWidth: defaultSidebarWidth, activeSpaceID: space, position: windows.count)
        windows.append(window)
        persistence?.scheduleWrite()
        return window
    }

    /// A new window (⌘N, the drag out, "Open in New Window", 4.8a) at the
    /// end of the order, showing `space`, with `frame` when given.
    @discardableResult
    public func createWindow(frame: CGRect?, sidebarWidth: Double, sidebarVisible: Bool = true, space: UUID?) -> WindowState {
        var window = WindowState(sidebarWidth: sidebarWidth, sidebarVisible: sidebarVisible, activeSpaceID: space,
                                 position: (windows.map(\.position).max() ?? -1) + 1)
        window.frame = frame
        windows.append(window)
        persistence?.scheduleWrite()
        return window
    }

    /// A window closed (not at quit: a quit keeps every window for the next
    /// launch): its row and its selections go; the others keep their order.
    public func removeWindow(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows.remove(at: index)
        for key in selections.keys where key.window == id { selections[key] = nil }
        for i in windows.indices { windows[i].position = i }
        persistence?.scheduleWrite()
    }

    /// The key window at quit goes first (4.8a): the next launch makes it key
    /// and loads only its selection (spec §H).
    public func moveToFront(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }), index > 0 else { return }
        windows.insert(windows.remove(at: index), at: 0)
        for i in windows.indices { windows[i].position = i }
        persistence?.scheduleWrite()
    }

    public func setSidebarWidth(_ width: Double, window: UUID) { update(window) { $0.sidebarWidth = width } }

    public func setSidebarVisible(_ visible: Bool, window: UUID) { update(window) { $0.sidebarVisible = visible } }

    public func setFrame(_ frame: CGRect?, window: UUID) { update(window) { $0.frame = frame } }

    public func setActiveSpace(_ space: UUID?, window: UUID) { update(window) { $0.activeSpaceID = space } }

    public func selectedEntry(space: UUID, window: UUID) -> UUID? {
        selections[SelectionKey(window: window, space: space)]
    }

    /// Every space's selected entry in every window (the archive sweep never takes them).
    public var selectedEntries: Set<UUID> { Set(selections.values) }

    /// The windows remembering `entry` as a space's selection (a page moved
    /// away from a window leaves it there for its MRU, 4.8a).
    public func windows(selecting entry: UUID) -> [UUID] {
        selections.filter { $0.value == entry }.map(\.key.window)
    }

    public func select(_ entry: UUID?, space: UUID, window: UUID) {
        let key = SelectionKey(window: window, space: space)
        guard selections[key] != entry else { return }
        selections[key] = entry
        persistence?.scheduleWrite()
    }

    private func update(_ id: UUID, _ body: (inout WindowState) -> Void) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        var window = windows[index]
        body(&window)
        guard window != windows[index] else { return }
        windows[index] = window
        persistence?.scheduleWrite()
    }

    /// Restore Sidebar… (4.1b): the windows' active spaces and selections
    /// become `state`'s. The window on screen (`current`) keeps its id, frame
    /// and sidebar; the backup's first window maps onto it when its id differs
    /// (a backup from another state directory).
    func replace(with state: RoomState, keeping current: UUID?) {
        var restored = state.windows.sorted { $0.position < $1.position }
        var rows = state.windowSpaces
        if let current, !restored.contains(where: { $0.id == current }), let first = restored.first {
            restored[0].id = current
            for index in rows.indices where rows[index].windowID == first.id { rows[index].windowID = current }
        }
        for index in restored.indices {
            guard let now = window(restored[index].id) else { continue }
            restored[index].frame = now.frame
            restored[index].sidebarWidth = now.sidebarWidth
            restored[index].sidebarVisible = now.sidebarVisible
        }
        if let current, !restored.contains(where: { $0.id == current }), var now = window(current) {
            now.activeSpaceID = state.spaces.first?.id
            now.position = restored.count
            restored.append(now)
        }
        windows = restored
        selections = [:]
        for row in rows {
            if let entry = row.selectedEntryID { selections[SelectionKey(window: row.windowID, space: row.spaceID)] = entry }
        }
        persistence?.scheduleWrite()
    }

    /// Keeps references valid after the sidebar removed entries or spaces.
    func sidebarDidChange(_ change: SidebarChange, firstSpace: UUID?) {
        guard !change.removedEntries.isEmpty || !change.removedSpaces.isEmpty else { return }
        var changed = false
        for (key, entry) in selections where change.removedEntries.contains(entry) || change.removedSpaces.contains(key.space) {
            selections[key] = nil
            changed = true
        }
        for index in windows.indices {
            if let active = windows[index].activeSpaceID, change.removedSpaces.contains(active) {
                windows[index].activeSpaceID = firstSpace
                changed = true
            }
        }
        if changed { persistence?.scheduleWrite() }
    }

    var stateWindowSpaces: [WindowSpace] {
        selections.map { WindowSpace(windowID: $0.key.window, spaceID: $0.key.space, selectedEntryID: $0.value) }
    }
}

/// The only writer of user settings.
@Observable
public final class SettingsStore {
    public private(set) var settings: Settings
    @ObservationIgnored weak var persistence: Persistence?

    init(settings: Settings) {
        self.settings = settings
    }

    public func update(_ body: (inout Settings) -> Void) {
        var copy = settings
        body(&copy)
        guard copy != settings else { return }
        settings = copy
        persistence?.scheduleWrite()
    }
}
