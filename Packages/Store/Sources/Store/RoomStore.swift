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
            windowSpaces: windows.stateWindowSpaces, settings: settings.settings, archive: Array(sidebar.archive.values))
    }

    /// The rolling backups beside the database (`<state>/Backups/`, 4.1b).
    public var backups: RoomBackups { RoomBackups(stateDirectory: storage.directory) }

    /// Restore Sidebar… (spec §H, 4.1b): spaces, entries, split groups, the
    /// windows' spaces and selections and the Archive become `backup`'s;
    /// profiles and settings stay (profiles only grow). Written at once as
    /// one transaction with the next generation (the writer's counter moves
    /// on, never back). The caller has backed up the current state first and
    /// unloads the pages.
    public func restoreSidebar(from backup: RoomState, window: UUID?) {
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
