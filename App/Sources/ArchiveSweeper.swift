import AppKit
import Design
import Model
import Store
import Tabs

/// When the archive sweep runs (spec §A.7): once at launch, then every
/// `Timing.archiveSweepInterval` (10 min) while Room is idle. Idle means no
/// key or mouse press in Room for `Timing.archiveIdleAfter` (60 s; the
/// window's input monitor stamps `TabController.lastUserInput`): a sweep
/// that falls due while the user is working waits, checked once a minute,
/// so rows never vanish under the pointer. The rules are `ArchivePolicy`'s
/// (Model), the run is `TabController.sweepArchive` (Tabs). Each sweep
/// then applies the Archive's retention (B-80, `ArchiveRetention` over the
/// `Retention` tokens).
@MainActor
final class ArchiveSweeper {
    private weak var tabs: TabController?
    private let store: RoomStore
    private var timer: Timer?
    private var lastSweep: TimeInterval
    /// The entries each sweep archived, newest last (DEBUG spikes read it).
    private(set) var log: [(at: Timestamp, archived: [UUID])] = []
    /// What the last sweep's retention did (B-80; DEBUG spikes read it).
    private(set) var lastRetention = ArchiveRetention.Plan()

    init(tabs: TabController, store: RoomStore) {
        self.tabs = tabs
        self.store = store
        lastSweep = ProcessInfo.processInfo.systemUptime
    }

    /// The launch sweep, then the idle timer.
    func start() {
        sweep()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weakSelf = MainActorWeak(self)] _ in
            MainActor.assumeIsolated { weakSelf.value?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let uptime = ProcessInfo.processInfo.systemUptime
        guard uptime - lastSweep >= Timing.archiveSweepInterval else { return }
        if let input = tabs?.lastUserInput, uptime - input < Timing.archiveIdleAfter { return }
        sweep()
    }

    /// Runs one sweep now on the store's clock; returns what it archived.
    @discardableResult
    func sweep() -> [UUID] {
        lastSweep = ProcessInfo.processInfo.systemUptime
        let now = store.sidebar.clock()
        let archived = tabs?.sweepArchive(now: now) ?? []
        // The Archive's retention (B-80): old rows go, older than a week lose their back/forward list.
        let retention = store.sidebar.applyArchiveRetention(now: now, rows: Retention.archiveRows,
                                                            navigationState: Retention.archiveNavigationState)
        if !retention.isEmpty {
            NSLog("Room: Archive retention: %ld rows pruned, %ld navigation states dropped", retention.prune.count,
                  retention.dropNavigationState.count)
        }
        lastRetention = retention
        log.append((now, archived))
        return archived
    }
}
