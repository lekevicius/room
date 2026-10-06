import AppKit
import Design
import Model
import Store

/// Rolling backups of the state database (spec §H, ROADMAP 4.1b task 6): a
/// `VACUUM INTO` copy in `<state>/Backups/` at launch once the state is open
/// and then every `Timing.backupInterval` (30 min), each only when the state's
/// generation moved since the last backup (`BackupPlanner.isDue`), pruned by
/// Arc's schedule (`BackupPlanner.plan` over the `Retention` tokens) after
/// each. The copy runs off the main thread on the database's writer
/// connection; Restore Sidebar… takes its "before restore" backup with
/// `takeNow`, synchronously.
@MainActor
final class BackupScheduler {
    private let store: RoomStore
    private var timer: Timer?
    /// The generation the newest backup holds (`nil`: none read yet).
    private(set) var lastBackupGeneration: Int64?
    private var running = false
    /// Each backup taken this session (DEBUG spikes and the launch line read it).
    private(set) var log: [(file: BackupFile, generation: Int64, milliseconds: Double)] = []

    static var schedule: BackupSchedule {
        BackupSchedule(today: Retention.backupsToday, days: Retention.backupDays,
                       weeksSpanDays: Retention.backupWeeksSpanDays, monthsSpanDays: Retention.backupMonthsSpanDays)
    }

    init(store: RoomStore) {
        self.store = store
    }

    /// The launch backup (when due), then the timer.
    func start() {
        let backups = store.backups
        if let newest = backups.list().first {
            lastBackupGeneration = (try? backups.info(newest))?.generation
        }
        backupIfDue()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Timing.backupInterval, repeats: true) { [weakSelf = MainActorWeak(self)] _ in
            MainActor.assumeIsolated { weakSelf.value?.backupIfDue() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A backup off the main thread when the state moved since the last one.
    func backupIfDue() {
        guard !running else { return }
        let generation = store.persistence.writer.committedGeneration
        guard BackupPlanner.isDue(generation: generation, lastBackupGeneration: lastBackupGeneration) else { return }
        running = true
        let backups = store.backups
        let database = store.persistence.writer.database
        let schedule = Self.schedule
        let weakSelf = MainActorWeak(self)
        Task.detached(priority: .utility) {
            let start = ContinuousClock.now
            let result = Result { try backups.take(from: database, at: Date()) }
            let elapsed = ContinuousClock.now - start
            let info = (try? result.get()).flatMap { try? backups.info($0) }
            let pruned = backups.prune(now: Date(), schedule: schedule, calendar: .current)
            await MainActor.run {
                weakSelf.value?.finished(result, info: info, pruned: pruned.count, elapsed: elapsed)
            }
        }
    }

    private func finished(_ result: Result<BackupFile, any Error>, info: BackupInfo?, pruned: Int, elapsed: Duration) {
        running = false
        let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        switch result {
        case .success(let file):
            let generation = info?.generation ?? store.persistence.writer.committedGeneration
            lastBackupGeneration = generation
            log.append((file, generation, milliseconds))
            NSLog("Room: backup %@ (generation %lld, %ld entries) in %.1f ms; %ld pruned", file.url.lastPathComponent,
                  generation, info?.entries ?? -1, milliseconds, pruned)
        case .failure(let error):
            NSLog("Room: backup failed: \(error)")
        }
    }

    /// A backup now, on the main thread (Restore Sidebar…'s "before restore").
    @discardableResult
    func takeNow(label: String?) throws -> BackupFile {
        let file = try store.backups.take(from: store.persistence.writer.database, at: Date(), label: label)
        lastBackupGeneration = (try? store.backups.info(file))?.generation
        return file
    }
}
