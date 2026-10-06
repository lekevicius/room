#if DEBUG
import AppKit
import Chrome
import Model
import Store
import Tabs

/// Phase 4.1b spike `recovery` (`scripts/recovery-check.sh`, the tour step
/// `recovery` in group `lifecycle`), two launches on one state:
/// - `-RoomRecoveryPhase prepare`: the state replaced by two spaces of
///   three Today tabs each on the 2.7 test server ("Recovery Kept", whose
///   second tab is selected and loads, and "Recovery Gone"); a backup taken
///   (`BackupScheduler.takeNow`); "Recovery Gone" deleted and the state
///   written (the commit acknowledged); then `kill_now:` for the script's
///   `kill -9`.
/// - `-RoomRecoveryPhase check -RoomRecoveryBackup <file name>`: the
///   relaunch after the kill: the unclean exit by both counts, no page
///   loaded (the selected entry included, spec §H), the card's empty state,
///   the toast; a click on the selected row loads it; then Restore Sidebar
///   from the backup: "Recovery Gone" is back with its tabs (in the store and
///   in the database), a `-before-restore` backup exists, the generation
///   moved on, the selection shows again.
/// `-RoomRecoveryPhase backups` (no kill) lists what `BackupScheduler` did
/// at launch (the launch backup and its time).
extension SpikeRunner.Context {
    private var app: AppDelegate? { AppDelegate.current }
    static let recoveryKept = "Recovery Kept"
    static let recoveryGone = "Recovery Gone"

    func recoveryChecks() async {
        let phase = UserDefaults.standard.string(forKey: "RoomRecoveryPhase") ?? "prepare"
        SpikeRunner.record("phase", phase)
        switch phase {
        case "prepare": await recoveryPrepare()
        case "check": await recoveryCheck()
        case "backups": await recoveryBackups()
        default: SpikeRunner.record("error", "unknown -RoomRecoveryPhase \(phase)")
        }
    }

    private func recoveryPrepare() async {
        guard let app, let store = app.store, let backups = app.backupScheduler else {
            return SpikeRunner.record("error", "recovery: no store or backups")
        }
        let sidebar = store.sidebar
        // A known state: every entry and every space but the first go, then the two spaces.
        for id in Array(sidebar.entries.keys) { _ = try? sidebar.remove(id) }
        sidebar.clearArchive()
        for space in sidebar.spaces.dropFirst() { _ = try? sidebar.deleteSpace(space.id) }
        sidebar.clearArchive()
        guard let first = sidebar.spaces.first, let profile = sidebar.profiles.first,
              let kept = try? sidebar.createSpace(name: Self.recoveryKept, profile: profile.id),
              let gone = try? sidebar.createSpace(name: Self.recoveryGone, profile: profile.id) else {
            return SpikeRunner.record("error", "recovery: spaces")
        }
        _ = try? sidebar.deleteSpace(first.id)
        sidebar.clearArchive()
        var keptIDs: [UUID] = []
        for (space, name) in [(kept, "kept"), (gone, "gone")] {
            for index in 0..<3 {
                if let entry = try? sidebar.addEntry(.today, url: "http://127.0.0.1:8770/site.html?recovery=\(name)\(index)",
                                                     title: "Recovery \(name) \(index)", space: space.id), space.id == kept.id {
                    keptIDs.append(entry.id)
                }
            }
        }
        self.sidebar.showSpace(kept.id, animated: false)
        self.sidebar.select(keptIDs[1])
        if let page = tabs.contents(for: keptIDs[1]) { await waitLoaded(page, timeout: 20) }
        store.flush()
        SpikeRunner.record("prepared", "spaces=\(sidebar.spaces.map(\.name).joined(separator: ",")) entries=\(sidebar.entries.count) "
            + "selected=\(sidebar.entry(keptIDs[1])?.liveTitle ?? "nil") loaded=\(tabs.loadedEntryIDs.count)")
        do {
            let file = try backups.takeNow(label: nil)
            let info = try store.backups.info(file)
            SpikeRunner.record("backup_taken", "\(file.url.lastPathComponent) entries=\(info.entries) spaces=\(info.spaces) generation=\(info.generation)")
        } catch {
            return SpikeRunner.record("error", "recovery: backup \(error)")
        }
        // The deletion, then the kill right after its commit.
        _ = try? sidebar.deleteSpace(gone.id)
        store.flush()
        let generation = (try? store.persistence.writer.database.generation()) ?? -1
        SpikeRunner.record("deleted", "space_gone=\(sidebar.space(gone.id) == nil) entries=\(sidebar.entries.count) "
            + "archived=\(sidebar.archive.count) generation=\(generation)")
        SpikeRunner.record("kill_now", ProcessInfo.processInfo.processIdentifier)
        try? await Task.sleep(for: .seconds(60))
        SpikeRunner.record("error", "recovery: not killed")
    }

    private func recoveryCheck() async {
        guard let app, let store = app.store else { return SpikeRunner.record("error", "recovery: no store") }
        let sidebar = store.sidebar
        // First, before anything else can load a page.
        let loadedAtLaunch = tabs.loadedEntryIDs.count
        let toast = app.debugToastCenter?.currentToast?.message ?? "none"
        let card = app.pageHostContainer?.pageView?.accessibilityIdentifier() ?? "nil"
        SpikeRunner.record("previous_exit", "store_unclean=\(store.uncleanExit) \(app.previousExitSummary ?? "nil")")
        SpikeRunner.record("crash_recovered", "\(app.crashRecovered) toast=\(toast) logged=\(AppDelegate.launchLog.contains { $0.hasPrefix("crash recovery") })")
        let selected = self.sidebar.selectedEntryID
        SpikeRunner.record("restored_unloaded", "entries=\(sidebar.entries.count) loaded=\(loadedAtLaunch) "
            + "selected=\(selected.flatMap { sidebar.entry($0)?.liveTitle } ?? "nil") card=\(card)")
        // The user's click on the selected row loads it.
        if let selected {
            self.sidebar.select(selected)
            _ = await waitUntil(10) { tabs.loadedEntryIDs.contains(selected) }
        }
        SpikeRunner.record("click_loads", "loaded=\(tabs.loadedEntryIDs.count) selected_loaded=\(selected.map { tabs.loadedEntryIDs.contains($0) } ?? false)")
        // Restore Sidebar from the backup taken before the deletion.
        let name = UserDefaults.standard.string(forKey: "RoomRecoveryBackup") ?? ""
        guard let file = store.backups.list().first(where: { $0.url.lastPathComponent == name }) else {
            return SpikeRunner.record("error", "recovery: no backup named \(name) in \(store.backups.list().map(\.url.lastPathComponent))")
        }
        let generationBefore = (try? store.persistence.writer.database.generation()) ?? -1
        let restored = app.restoreSidebar(from: file)
        try? await Task.sleep(for: .milliseconds(300))
        let gone = sidebar.spaces.first { $0.name == Self.recoveryGone }
        let goneEntries = gone.map { sidebar.today(space: $0.id).count } ?? 0
        let onDisk = (try? store.persistence.writer.database.loadState().state)
        let diskGone = onDisk?.spaces.first { $0.name == Self.recoveryGone }
        let diskEntries = diskGone.map { space in onDisk?.entries.filter { $0.spaceID == space.id }.count ?? 0 } ?? 0
        let generationAfter = (try? store.persistence.writer.database.generation()) ?? -1
        SpikeRunner.record("restore", "ok=\(restored) space_back=\(gone != nil) entries=\(goneEntries) database_space=\(diskGone != nil) "
            + "database_entries=\(diskEntries) generation=\(generationBefore)->\(generationAfter) "
            + "toast=\(app.debugToastCenter?.currentToast?.message ?? "none")")
        let before = store.backups.list().filter { $0.label == RoomBackups.beforeRestoreLabel }
        SpikeRunner.record("before_restore_backup", "count=\(before.count) entries=\(before.first.flatMap { try? store.backups.info($0) }?.entries ?? -1)")
        _ = await waitUntil(10) { !tabs.loadedEntryIDs.isEmpty }
        SpikeRunner.record("after_restore", "spaces=\(sidebar.spaces.map(\.name).joined(separator: ",")) "
            + "active=\(self.sidebar.activeSpace?.name ?? "nil") selected=\(self.sidebar.selectedEntryID.flatMap { sidebar.entry($0)?.liveTitle } ?? "nil") "
            + "loaded=\(tabs.loadedEntryIDs.count) footer_spaces=\(sidebar.spaces.count)")
        await recoveryBackups()
    }

    private func recoveryBackups() async {
        guard let app, let store = app.store, let scheduler = app.backupScheduler else { return }
        _ = await waitUntil(5) { !scheduler.log.isEmpty }
        let files = store.backups.list()
        SpikeRunner.record("backups", "files=\(files.count) " + files.map { file in
            let info = try? store.backups.info(file)
            return "\(file.label ?? "rolling"):\(info?.entries ?? -1)e/\(info?.spaces ?? -1)s/g\(info?.generation ?? -1)"
        }.joined(separator: ","))
        SpikeRunner.record("launch_backup", scheduler.log.first.map {
            String(format: "%@ generation=%lld %.1f ms", $0.file.url.lastPathComponent, $0.generation, $0.milliseconds)
        } ?? "none (the generation had not moved since the newest backup)")
    }
}
#endif
