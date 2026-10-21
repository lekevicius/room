#if DEBUG
import AppKit
import Darwin
import Engine

/// `openclose` (5.4a task 4): 50 Today tabs opened (each loaded from the
/// test server :8766) and closed, the host's own footprint recorded along
/// the way. With `-RoomSpikeKeepRunning YES` the process stays up for
/// `leaks`, `footprint` and `vmmap` (`scripts/leaks-check.sh`).
extension SpikeRunner.Context {
    func openCloseCycle() async {
        let base = UserDefaults.standard.string(forKey: "RoomLeakBaseURL") ?? "http://127.0.0.1:8766/"
        SpikeRunner.record("footprint_before", Self.footprint())
        for index in 1...50 {
            guard let id = tabs.openNewTab(url: "\(base)?open-close-\(index)") else {
                return SpikeRunner.record("error", "no tab \(index)")
            }
            if let page = tabs.contents(for: id) { await waitLoaded(page, timeout: 15) }
            sidebar.close(id)
            try? await Task.sleep(for: .milliseconds(150))
            if [1, 10, 25, 50].contains(index) { SpikeRunner.record("footprint_after_\(index)", Self.footprint()) }
        }
        try? await Task.sleep(for: .seconds(5))
        SpikeRunner.record("footprint_settled", Self.footprint())
        SpikeRunner.record("loaded_pages", tabs.loadedEntryIDs.count)
        SpikeRunner.record("rss", ProcessMemory.snapshot().summary)
    }

    /// The host process's physical footprint (what Activity Monitor's Memory column shows), in MB.
    static func footprint() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return "unavailable" }
        return String(format: "%.1f MB (peak %.1f MB)", Double(info.phys_footprint) / 1_048_576, Double(info.ledger_phys_footprint_peak) / 1_048_576)
    }
}
#endif
