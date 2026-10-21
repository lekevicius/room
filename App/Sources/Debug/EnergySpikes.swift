#if DEBUG
import AppKit
import Darwin
import Engine

/// `energy` (5.4a task 5): ten loaded pages idle, then the same with the nine
/// background pages discarded, each phase `-RoomEnergySeconds` long (600 by
/// default). The method needs no privileges (`powermetrics` needs root): at
/// each phase's ends every process of this app (the host and its helpers,
/// found by the bundle's path) is read with `proc_pid_rusage(RUSAGE_INFO_V6)`
/// and the phase is the difference: CPU time, the kernel's energy estimate
/// (`ri_energy_nj`), billed energy, idle and interrupt wakeups, summed per
/// process kind. A process that started or exited inside a phase is counted
/// apart (its share is missing from the sums).
extension SpikeRunner.Context {
    func energyChecks() async {
        let seconds = UserDefaults.standard.object(forKey: "RoomEnergySeconds").flatMap { Double("\($0)") } ?? 600
        let space = sidebar.activeSpaceID
        let sites = store.today(space: space).filter { entry in Self.typicalSites.contains { $0 == entry.currentURL } }
        for entry in sites {
            sidebar.select(entry.id)
            if let page = tabs.contents(for: entry.id) { await waitLoaded(page, timeout: 45) }
        }
        if let first = sites.first { sidebar.select(first.id) }
        try? await Task.sleep(for: .seconds(10))
        SpikeRunner.record("energy_seconds", Int(seconds))
        SpikeRunner.record("window", "key=\(window.isKeyWindow) visible=\(window.occlusionState.contains(.visible))")

        SpikeRunner.record("phase_loaded", "\(tabs.loadedEntryIDs.count) pages, \(ProcessMemory.snapshot().summary)")
        let loadedStart = EnergySample.now()
        try? await Task.sleep(for: .seconds(seconds))
        let loadedEnd = EnergySample.now()
        for line in EnergySample.report(from: loadedStart, to: loadedEnd) { SpikeRunner.record("energy_loaded", line) }
        SpikeRunner.record("window_after_loaded", "key=\(window.isKeyWindow) visible=\(window.occlusionState.contains(.visible))")

        let discarded = tabs.discardBackgroundPages()
        try? await Task.sleep(for: .seconds(10))
        SpikeRunner.record("phase_discarded", "\(discarded.count) discarded, \(tabs.loadedEntryIDs.count) loaded, \(ProcessMemory.snapshot().summary)")
        let discardedStart = EnergySample.now()
        try? await Task.sleep(for: .seconds(seconds))
        let discardedEnd = EnergySample.now()
        for line in EnergySample.report(from: discardedStart, to: discardedEnd) { SpikeRunner.record("energy_discarded", line) }
        SpikeRunner.record("phase_end", ProcessMemory.snapshot().summary)
    }
}

/// `proc_pid_rusage` of every process of this app at one moment.
struct EnergySample {
    struct Usage {
        var kind: String
        var cpuNanoseconds: Double
        var energyNanojoules: Double
        var billedEnergy: Double
        var idleWakeups: Double
        var interruptWakeups: Double
    }
    var at: Date
    var processes: [Int32: Usage]

    static func now() -> EnergySample {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let toNanoseconds = Double(timebase.numer) / Double(timebase.denom)
        var processes: [Int32: Usage] = [:]
        for (pid, kind) in ourProcesses() {
            var info = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard result == 0 else { continue }
            processes[pid] = Usage(kind: kind, cpuNanoseconds: Double(info.ri_user_time + info.ri_system_time) * toNanoseconds,
                                   energyNanojoules: Double(info.ri_energy_nj), billedEnergy: Double(info.ri_billed_energy),
                                   idleWakeups: Double(info.ri_pkg_idle_wkups), interruptWakeups: Double(info.ri_interrupt_wkups))
        }
        return EnergySample(at: Date(), processes: processes)
    }

    /// The host and its helpers by the bundle's path, each with its kind (`--type=`, the utility's sub-type).
    static func ourProcesses() -> [(Int32, String)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let bundle = Bundle.main.bundlePath
        var result: [(Int32, String)] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            let command = String(trimmed[space...])
            guard command.contains(bundle) else { continue }
            let kind: String
            if pid == getpid() {
                kind = "host"
            } else if let type = command.range(of: "--type=").map({ command[$0.upperBound...].prefix { $0 != " " } }) {
                if type == "utility", let sub = command.range(of: "--utility-sub-type=").map({ command[$0.upperBound...].prefix { $0 != " " } }) {
                    kind = "utility:" + (sub.split(separator: ".").first.map(String.init) ?? String(sub))
                } else {
                    kind = String(type)
                }
            } else {
                kind = "other"
            }
            result.append((pid, kind))
        }
        return result
    }

    /// Per kind: processes, CPU seconds and % of one core, energy (J and mean mW), billed energy, wakeups per second.
    static func report(from start: EnergySample, to end: EnergySample) -> [String] {
        let seconds = end.at.timeIntervalSince(start.at)
        var sums: [String: (count: Int, cpu: Double, energy: Double, billed: Double, idle: Double, interrupt: Double)] = [:]
        for (pid, after) in end.processes {
            guard let before = start.processes[pid] else { continue }
            var sum = sums[after.kind] ?? (0, 0, 0, 0, 0, 0)
            sum.count += 1
            sum.cpu += after.cpuNanoseconds - before.cpuNanoseconds
            sum.energy += after.energyNanojoules - before.energyNanojoules
            sum.billed += after.billedEnergy - before.billedEnergy
            sum.idle += after.idleWakeups - before.idleWakeups
            sum.interrupt += after.interruptWakeups - before.interruptWakeups
            sums[after.kind] = sum
        }
        var lines = sums.keys.sorted().map { kind -> String in
            let s = sums[kind]!
            return String(format: "%@: %d process(es), CPU %.2f s (%.2f %% of a core), energy %.2f J (%.1f mW), billed %.0f, idle wakeups %.1f/s, interrupt wakeups %.1f/s",
                          kind, s.count, s.cpu / 1e9, s.cpu / 1e9 / seconds * 100, s.energy / 1e9, s.energy / 1e9 / seconds * 1000,
                          s.billed, s.idle / seconds, s.interrupt / seconds)
        }
        let total = sums.values.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.cpu, $0.1 + $1.energy, $0.2 + $1.idle) }
        lines.append(String(format: "all: CPU %.2f s (%.2f %% of a core), energy %.2f J (%.1f mW), idle wakeups %.1f/s over %.0f s",
                            total.0 / 1e9, total.0 / 1e9 / seconds * 100, total.1 / 1e9, total.1 / 1e9 / seconds * 1000, total.2 / seconds, seconds))
        let started = end.processes.keys.filter { start.processes[$0] == nil }.map { "\($0) \(end.processes[$0]!.kind)" }
        let exited = start.processes.keys.filter { end.processes[$0] == nil }.map { "\($0) \(start.processes[$0]!.kind)" }
        lines.append("started inside: [\(started.joined(separator: ", "))]; exited inside: [\(exited.joined(separator: ", "))]")
        return lines
    }
}
#endif
