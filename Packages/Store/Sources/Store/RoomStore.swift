import Foundation
import Model

/// The stores and their persistence, opened from one directory.
public final class RoomStore {
    public let sidebar: SidebarStore
    public let windows: WindowStore
    public let settings: SettingsStore
    /// Favicons by host (outside the state pipeline).
    public let favicons: FaviconStore
    /// What schema v6 kept of the Chapter 2 history tables (`HistoryArchive`,
    /// beside the database; absent when there was nothing to keep).
    public var historyArchiveURL: URL { storage.directory.appending(path: HistoryArchive.fileName) }
    public let persistence: Persistence
    public let storage: RoomStorage
    /// The previous session ended without `close()` (crash, kill, power loss).
    public let uncleanExit: Bool
    /// The database was unusable at launch and was rebuilt.
    public let recovery: RoomStorage.Recovery?
    /// The integrity check the open ran (B-42); `nil` after a recovery.
    public let integrityCheck: RoomStorage.IntegrityCheck?

    private var sidebarToken: ObservationToken?

    /// Opens (or creates) the database in `directory`; on first launch seeds
    /// profile "Default" with space "Space" and no entries.
    public static func open(directory: URL, debounce: Duration = .milliseconds(300),
                            observer: (any StateWriterObserver)? = nil) throws -> RoomStore {
        let storage = RoomStorage(directory: directory)
        let opened = try storage.open()
        return RoomStore(storage: storage, opened: opened, writer: storage.makeWriter(for: opened, observer: observer),
                         debounce: debounce)
    }

    private init(storage: RoomStorage, opened: RoomStorage.Opened, writer: StateWriter, debounce: Duration) {
        self.storage = storage
        uncleanExit = opened.uncleanExit
        recovery = opened.recovery
        integrityCheck = opened.check
        let state = opened.state
        sidebar = SidebarStore(state: state)
        windows = WindowStore(state: state)
        settings = SettingsStore(settings: state.settings)
        favicons = FaviconStore(database: writer.database)
        var provider: () -> RoomState = { RoomState() }
        persistence = Persistence(writer: writer, generation: opened.generation, debounce: debounce) { provider() }
        provider = { [unowned self] in currentState() }
        sidebar.persistence = persistence
        windows.persistence = persistence
        settings.persistence = persistence
        sidebarToken = sidebar.observe { [unowned self] change in
            windows.sidebarDidChange(change, firstSpace: sidebar.spaces.first?.id)
        }
        // A Today list without a window is the first window's until the app
        // names its key window (schema v9).
        sidebar.defaultWindow = { [unowned self] in windows.windows.first?.id }
        if state.isEmpty { seed() }
    }

    /// First launch: profile "Default", space "Space", no entries (ROADMAP 2.1).
    private func seed() {
        let profile = sidebar.createProfile(name: "Default")
        _ = try? sidebar.createSpace(name: "Space", profile: profile.id)
    }

    /// Everything the stores hold, as one value for the writer.
    public func currentState() -> RoomState {
        RoomState(
            profiles: sidebar.profiles, spaces: sidebar.spaces, entries: sidebar.stateEntries,
            splitGroups: Array(sidebar.splitGroups.values), windows: windows.windows,
            windowSpaces: windows.stateWindowSpaces, settings: settings.settings, archive: Array(sidebar.archive.values),
            routingRules: sidebar.routingRules)
    }

    /// The rolling backups beside the database (`<state>/Backups/`, 4.1b).
    public var backups: RoomBackups { RoomBackups(stateDirectory: storage.directory) }

    /// Restore Sidebar… (spec §H, 4.1b): spaces, entries, split groups, the
    /// windows' spaces and selections and the Archive become `backup`'s;
    /// profiles and settings stay (profiles only grow). Written at once as
    /// one transaction with the next generation (the writer's counter moves
    /// on, never back). The caller has backed up the current state first and
    /// unloads the pages.
    public func restoreSidebar(from backup: RoomState, window: UUID?, open: [UUID] = []) {
        // The backup's windows map onto the open ones (4.8a): its Today tabs
        // land in the windows on screen.
        let backup = window.map { backup.remappingWindows(onto: open.isEmpty ? [$0] : open, current: $0) } ?? backup
        // Windows first: the sidebar's change then finds the selections pointing at entries that exist.
        windows.replace(with: backup, keeping: window)
        sidebar.replace(with: backup)
        flush()
    }

    /// Writes now and waits (window close).
    public func flush() {
        do { try persistence.flushAndWait() } catch { NSLog("Room: flush failed: \(error)") }
    }

    /// Final write at quit; marks the session as cleanly ended.
    public func close() {
        do { try persistence.flushAndWait(cleanExit: true) } catch { NSLog("Room: final write failed: \(error)") }
    }
}

extension RoomState {
    /// The state with its windows mapped onto `open` (Restore Sidebar… with
    /// several windows on screen, 4.8a): the i-th window by position becomes
    /// the i-th open window, keeping its active space and selections; a
    /// window with no open counterpart is dropped and its Today tabs (and
    /// any Today tab of no window) go to `current`.
    public func remappingWindows(onto open: [UUID], current: UUID) -> RoomState {
        var copy = self
        let sorted = windows.sorted { $0.position < $1.position }
        var mapping: [UUID: UUID] = [:]
        for (index, window) in sorted.enumerated() where index < open.count { mapping[window.id] = open[index] }
        copy.windows = sorted.compactMap { window in
            guard let id = mapping[window.id] else { return nil }
            var mapped = window
            mapped.id = id
            return mapped
        }
        copy.windowSpaces = windowSpaces.compactMap { row in
            guard let id = mapping[row.windowID] else { return nil }
            var mapped = row
            mapped.windowID = id
            return mapped
        }
        for index in copy.entries.indices where copy.entries[index].kind == .today {
            copy.entries[index].windowID = copy.entries[index].windowID.flatMap { mapping[$0] } ?? current
        }
        return copy
    }
}
