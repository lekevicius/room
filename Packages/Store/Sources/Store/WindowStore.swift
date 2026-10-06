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

    public func setSidebarWidth(_ width: Double, window: UUID) { update(window) { $0.sidebarWidth = width } }

    public func setSidebarVisible(_ visible: Bool, window: UUID) { update(window) { $0.sidebarVisible = visible } }

    public func setFrame(_ frame: CGRect?, window: UUID) { update(window) { $0.frame = frame } }

    public func setActiveSpace(_ space: UUID?, window: UUID) { update(window) { $0.activeSpaceID = space } }

    public func selectedEntry(space: UUID, window: UUID) -> UUID? {
        selections[SelectionKey(window: window, space: space)]
    }

    /// Every space's selected entry in every window (the archive sweep never takes them).
    public var selectedEntries: Set<UUID> { Set(selections.values) }

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
