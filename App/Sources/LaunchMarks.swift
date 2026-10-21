import AppKit
import Darwin

/// 5.4a: the launch broken down. Each mark is the time since the process
/// started (the kernel's start time, as the relaunch spike's totals), so the
/// steps from `main` to the selected page's load add up to what the relaunch
/// and cold-launch measurements report. DEBUG only: in Release every call is
/// empty. The relaunch spike prints the marks (`launch_mark`);
/// `-RoomLaunchMarksFile <path>` writes them at the quit (the cold-launch script).
enum LaunchMarks {
    #if DEBUG
    private(set) static var marks: [(name: String, seconds: Double)] = []
    private static let start: Double = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let started = info.kp_proc.p_un.__p_starttime
        return Double(started.tv_sec) + Double(started.tv_usec) / 1e6
    }()
    #endif

    /// Records `name` the first time it is reached (later windows and profiles do not move it).
    static func mark(_ name: String) {
        #if DEBUG
        guard !marks.contains(where: { $0.name == name }) else { return }
        marks.append((name, Date().timeIntervalSince1970 - start))
        #endif
    }

    /// Marks `name` once the current Core Animation transaction is committed (its frame is on its way).
    static func markCommit(_ name: String) {
        #if DEBUG
        CATransaction.setCompletionBlock { mark(name) }
        #endif
    }

    /// `-RoomLaunchMarksFile <path>`: the marks as `name<TAB>milliseconds` lines.
    static func writeIfRequested() {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "RoomLaunchMarksFile") else { return }
        let lines = marks.map { String(format: "%@\t%.1f", $0.name, $0.seconds * 1000) }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        #endif
    }
}
