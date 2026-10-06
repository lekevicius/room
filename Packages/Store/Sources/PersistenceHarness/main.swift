import CryptoKit
import Foundation
import Model
import Store
import Synchronization

// Kill -9 test of the persistence pipeline (ROADMAP Phase 2.1 exit criterion).
//
//   room-persistence-harness run [--dir D] [--kills 100] [--debounce-ms 300] [--seed N]
//   room-persistence-harness writer <dir> [--debounce-ms 300] [--seed N]
//
// `writer` opens a RoomStore and mutates it continuously through the real
// stores and Persistence. Before each transaction it prints
// `begin <generation> <sha256 of the state>`, after the commit
// `commit <generation> <microseconds>`. `run` starts writers, SIGKILLs them at
// random points (some right after a `begin`, i.e. mid-transaction), and after
// every kill reopens the directory and checks: no recovery needed,
// `PRAGMA integrity_check` = ok, no foreign-key violations, the database's
// generation is at least the last acknowledged commit and at most the last
// begun one, and its content hashes to exactly what was begun for that
// generation (no torn or mixed write). The JSON snapshot must decode and
// match its generation's hash too.

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func hash(_ state: RoomState) -> String {
    let data = (try? state.canonicalJSON()) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// The JSON snapshot leaves the Archive (schema v7, 4.1a) and the entries'
/// navigation states (B-73, 4.1b) out: it is checked against the state's
/// hash without them (`StateSnapshot.encoded`).
func snapshotHash(_ state: RoomState) -> String {
    var state = state
    state.archive = []
    for index in state.entries.indices { state.entries[index].navigationState = nil }
    return hash(state)
}

/// Deterministic random numbers (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Writer

/// Prints with write(2) so nothing sits in a stdio buffer when SIGKILL lands.
func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

final class HashLogger: StateWriterObserver {
    private let started = Mutex<ContinuousClock.Instant?>(nil)

    func stateWriter(willWrite state: RoomState, generation: Int64) {
        emit("begin \(generation) \(hash(state)) \(snapshotHash(state))")
        started.withLock { $0 = .now }
    }

    func stateWriter(didCommit generation: Int64) {
        let elapsed = started.withLock { $0.map { ContinuousClock.now - $0 } } ?? .zero
        emit("commit \(generation) \(elapsed.components.attoseconds / 1_000_000_000_000 + elapsed.components.seconds * 1_000_000)")
    }
}

/// Random mutations over every store, with errors (cap, depth) ignored.
@MainActor
final class Mutator {
    let store: RoomStore
    var random: SeededGenerator
    let window: UUID

    init(store: RoomStore, seed: UInt64) {
        self.store = store
        random = SeededGenerator(state: seed)
        window = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 240, space: store.sidebar.spaces.first?.id).id
    }

    var sidebar: SidebarStore { store.sidebar }

    func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[Int.random(in: 0..<items.count, using: &random)] }

    func url() -> String { "https://site\(Int.random(in: 0..<40, using: &random)).example/\(Int.random(in: 0..<1000, using: &random))" }

    func randomContainer() -> Container? {
        guard let space = pick(sidebar.spaces) else { return nil }
        switch Int.random(in: 0..<3, using: &random) {
        case 0: return .essentials(profile: space.profileID)
        case 1:
            let folder = pick(sidebar.entries.values.filter { $0.kind == .folder && $0.spaceID == space.id })
            return .pinned(space: space.id, folder: Bool.random(using: &random) ? folder?.id : nil)
        default: return .today(space: space.id)
        }
    }

    func step() {
        guard let space = pick(sidebar.spaces) else { return }
        let entry = pick(Array(sidebar.entries.values))
        let roll = Int.random(in: 0..<100, using: &random)
        do {
            switch roll {
            case 0..<20 where sidebar.entries.count < 300:
                try sidebar.addEntry(.today, url: url(), title: "Tab \(roll)", space: space.id, at: Int.random(in: 0..<5, using: &random))
            case 20..<26:
                try sidebar.addEntry(.pinned, url: url(), title: "Pinned", space: space.id)
            case 26..<28:
                try sidebar.addEntry(.essential, url: url(), space: space.id)
            case 28..<31:
                let parent = pick(sidebar.entries.values.filter { $0.kind == .folder && $0.spaceID == space.id })
                try sidebar.addFolder(name: "Folder", space: space.id, parent: parent?.id)
            case 31..<45:
                if let entry, let container = randomContainer() {
                    try sidebar.move(entry.id, to: container, at: Int.random(in: 0..<10, using: &random))
                }
            case 45..<52:
                if let entry { try sidebar.rename(entry.id, to: Bool.random(using: &random) ? "Renamed \(roll)" : nil) }
            case 52..<64:
                if let entry {
                    try sidebar.setLivePage(entry.id, url: url(), title: "Live \(roll)")
                    // The page's serialised back/forward list (schema v5, 3.7b): 1–8 KB, as engines write.
                    if Bool.random(using: &random) {
                        let size = Int.random(in: 1_024...8_192, using: &random)
                        try sidebar.setNavigationState(entry.id, Data((0..<size).map { _ in UInt8.random(in: 0...255, using: &random) }))
                    }
                }
            case 64..<72:
                if let entry {
                    try sidebar.markActive(entry.id)
                    store.windows.select(entry.id, space: entry.spaceID ?? space.id, window: window)
                }
            case 72..<80:
                if let entry { try sidebar.remove(entry.id) }
            case 80..<82:
                // "Archive" (schema v7): the entry leaves for the Archive in the same write.
                if let entry { sidebar.archive([entry.id], reason: .manual) }
            case 82..<84:
                if let row = pick(Array(sidebar.archive.keys)) { try sidebar.restore(archived: row, activeSpace: space.id) }
            case 84..<86:
                let removed = sidebar.clearToday(space: space.id)
                if Bool.random(using: &random) { sidebar.restore(removed) }
            case 86..<88 where sidebar.spaces.count < 5:
                try sidebar.createSpace(name: "Space \(roll)", profile: space.profileID)
            case 88:
                try sidebar.deleteSpace(space.id)
            case 89:
                try sidebar.updateSpace(space.id) { $0.pinnedCollapsed.toggle(); $0.themeColors = ["#\(roll)\(roll)\(roll)"] }
            case 90:
                // Routing rules (schema v8): added up to a few, else one removed or toggled.
                if sidebar.routingRules.count < 4 {
                    try sidebar.addRoutingRule(pick(RoutingMatch.allCases)!, pattern: "site\(roll)", target: space.id, at: 0)
                } else if let rule = pick(sidebar.routingRules) {
                    if Bool.random(using: &random) { sidebar.removeRoutingRule(rule.id) } else { try sidebar.updateRoutingRule(rule.id) { $0.enabled.toggle() } }
                }
            case 91..<95:
                store.windows.setSidebarWidth(Double(Int.random(in: 180...500, using: &random)), window: window)
                store.windows.setSidebarVisible(Bool.random(using: &random), window: window)
                store.windows.setActiveSpace(space.id, window: window)
            case 95..<97:
                let behavior = pick(PermanentCloseBehavior.allCases)!
                store.settings.update { $0.permanentCloseBehavior = behavior }
            case 97..<99:
                let members = Array(sidebar.today(space: space.id).prefix(2)).map(\.id)
                if members.count == 2 { try sidebar.createSplitGroup(members) }
            default:
                if let entry, entry.kind == .folder { try sidebar.setFolderCollapsed(entry.id, !entry.isCollapsed) }
            }
        } catch {
            // Refused by a domain rule: the point is the write traffic.
        }
    }
}

@MainActor
func runWriter(directory: URL, debounce: Duration, seed: UInt64) -> Never {
    let store: RoomStore
    do { store = try RoomStore.open(directory: directory, debounce: debounce, observer: HashLogger()) } catch {
        fail("writer open: \(error)")
    }
    emit("ready \(store.persistence.generation)")
    let mutator = Mutator(store: store, seed: seed)
    Task {
        while true {
            for _ in 0..<Int.random(in: 1...20, using: &mutator.random) { mutator.step() }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 1...4, using: &mutator.random)))
        }
    }
    dispatchMain()
}

// MARK: - Driver

/// Lines from the writer's stdout, shared with the pipe's reading thread.
final class WriterLog: Sendable {
    struct State {
        var buffer = Data()
        var ready = false
        var begins: [Int64: String] = [:]
        /// The same state's hash without the Archive (the snapshot's content).
        var snapshotBegins: [Int64: String] = [:]
        var lastBegin: Int64 = 0
        var lastCommit: Int64?
        var commitMicros: [Int] = []
        var lines = 0
    }

    let state = Mutex(State())

    func append(_ data: Data) {
        state.withLock { state in
            state.buffer.append(data)
            while let newline = state.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: state.buffer[state.buffer.startIndex..<newline], as: UTF8.self)
                state.buffer.removeSubrange(state.buffer.startIndex...newline)
                state.lines += 1
                let parts = line.split(separator: " ")
                switch parts.first {
                case "ready": state.ready = true
                case "begin" where parts.count == 4:
                    let generation = Int64(parts[1])!
                    state.begins[generation] = String(parts[2])
                    state.snapshotBegins[generation] = String(parts[3])
                    state.lastBegin = max(state.lastBegin, generation)
                case "commit" where parts.count == 3:
                    state.lastCommit = max(state.lastCommit ?? 0, Int64(parts[1])!)
                    state.commitMicros.append(Int(parts[2])!)
                default: break
                }
            }
        }
    }

    func waitFor(timeout: Duration, _ condition: (State) -> Bool) -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if state.withLock({ condition($0) }) { return true }
            usleep(100)
        }
        return false
    }
}

struct Outcome {
    var dbGeneration: Int64
    var lastAcked: Int64?
    var lastBegun: Int64
    var killedMidWrite: Bool
    var snapshotGeneration: Int64?
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    /// The reopen found a generation older than the last acknowledged one:
    /// an acknowledged write was lost (the one real failure B-79 counts).
    var behindAck = false
}

func verify(directory: URL, log: WriterLog, killedMidWrite: Bool) -> Result<Outcome, Failure> {
    let storage = RoomStorage(directory: directory)
    // Read before opening: `open()` brings a lagging snapshot level.
    let snapshotExists = FileManager.default.fileExists(atPath: storage.snapshotURL.path)
    let snapshotRead = snapshotExists ? try? StateSnapshot.read(from: storage.snapshotURL) : nil
    let opened: RoomStorage.Opened
    do { opened = try storage.open() } catch { return .failure(Failure(description: "reopen failed: \(error)")) }
    if let recovery = opened.recovery { return .failure(Failure(description: "needed recovery: \(recovery)")) }
    guard opened.uncleanExit else { return .failure(Failure(description: "unclean exit not detected")) }
    do {
        let integrity = try opened.database.integrityCheck()
        guard integrity == ["ok"] else { return .failure(Failure(description: "integrity_check: \(integrity)")) }
        let violations = try opened.database.foreignKeyViolations()
        guard violations == 0 else { return .failure(Failure(description: "\(violations) foreign-key violations")) }
    } catch { return .failure(Failure(description: "check failed: \(error)")) }
    let (begins, snapshotBegins, lastCommit, lastBegin) = log.state.withLock {
        ($0.begins, $0.snapshotBegins, $0.lastCommit, $0.lastBegin)
    }
    let generation = opened.generation
    if let lastCommit, generation < lastCommit {
        return .failure(Failure(description: "generation \(generation) on disk, but \(lastCommit) was acknowledged", behindAck: true))
    }
    if generation > lastBegin { return .failure(Failure(description: "generation \(generation) on disk was never begun (last \(lastBegin))")) }
    if generation == 0 {
        guard opened.state.isEmpty else { return .failure(Failure(description: "generation 0 with content")) }
    } else {
        guard let expected = begins[generation] else { return .failure(Failure(description: "no begin line for generation \(generation)")) }
        let actual = hash(opened.state)
        guard actual == expected else { return .failure(Failure(description: "content of generation \(generation) does not match its begin hash")) }
    }
    var snapshotGeneration: Int64?
    if snapshotExists {
        guard let snapshot = snapshotRead else { return .failure(Failure(description: "snapshot does not decode")) }
        guard snapshot.generation == generation || snapshot.generation == generation - 1 else {
            return .failure(Failure(description: "snapshot generation \(snapshot.generation) vs database \(generation)"))
        }
        guard snapshotBegins[snapshot.generation] == hash(snapshot.state) else { return .failure(Failure(description: "snapshot content mismatch")) }
        snapshotGeneration = snapshot.generation
    }
    return .success(Outcome(dbGeneration: generation, lastAcked: lastCommit, lastBegun: lastBegin,
                            killedMidWrite: killedMidWrite, snapshotGeneration: snapshotGeneration))
}

@MainActor
func runDriver() -> Never {
    let kills = Int(option("--kills") ?? "100")!
    let debounceMS = option("--debounce-ms") ?? "300"
    var random = SeededGenerator(state: UInt64(option("--seed") ?? "") ?? UInt64.random(in: 1...UInt64.max))
    let directory = option("--dir").map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory.appending(path: "room-kill-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let executable = Bundle.main.executableURL!
    let log = WriterLog()
    var outcomes: [Outcome] = []
    var failures: [String] = []
    var behindAck = 0
    let start = ContinuousClock.now
    print("directory \(directory.path), \(kills) kills, debounce \(debounceMS) ms")

    for round in 1...kills {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["writer", directory.path, "--debounce-ms", debounceMS, "--seed", String(random.next() >> 1)]
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in log.append(handle.availableData) }
        log.state.withLock { $0.ready = false }
        do { try process.run() } catch { fail("spawn: \(error)") }
        guard log.waitFor(timeout: .seconds(20), { $0.ready }) else { fail("writer \(round) never became ready") }

        // 40%: kill right after a transaction begins (0–3 ms in); otherwise
        // at a uniformly random time 20–1500 ms after the writer is up.
        let midWrite = Int.random(in: 0..<100, using: &random) < 40
        if midWrite {
            let seen = log.state.withLock { $0.lastBegin }
            _ = log.waitFor(timeout: .seconds(5)) { $0.lastBegin > seen }
            usleep(UInt32(Int.random(in: 0...3000, using: &random)))
        } else {
            usleep(UInt32(Int.random(in: 20_000...1_500_000, using: &random)))
        }
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        log.append(pipe.fileHandleForReading.readDataToEndOfFile())
        let inFlight = log.state.withLock { $0.lastBegin > ($0.lastCommit ?? 0) }

        switch verify(directory: directory, log: log, killedMidWrite: inFlight) {
        case .success(let outcome):
            outcomes.append(outcome)
            let note: String
            if outcome.dbGeneration == outcome.lastAcked {
                note = "acked"
            } else if outcome.dbGeneration == outcome.lastBegun {
                note = "committed, ack lost"
            } else {
                note = "rolled back"
            }
            let suffix = inFlight ? ", killed mid-write" : ""
            print("kill \(round): generation \(outcome.dbGeneration) (\(note))\(suffix)")
        case .failure(let message):
            if message.behindAck { behindAck += 1 }
            failures.append("kill \(round): \(message)")
            print("kill \(round): FAIL \(message)")
        }
    }

    let elapsed = ContinuousClock.now - start
    let micros = log.state.withLock { $0.commitMicros }.sorted()
    let midWrite = outcomes.filter(\.killedMidWrite).count
    let rolledBack = outcomes.filter { $0.killedMidWrite && $0.dbGeneration < $0.lastBegun }.count
    // Ahead of the last ack: the commit landed and the kill beat its
    // acknowledgement (informational, B-79). Behind it: a lost write (counted
    // in `verify`, which also fails the round).
    let aheadOfAck = outcomes.filter { $0.dbGeneration > ($0.lastAcked ?? 0) }.count
    let snapshotBehind = outcomes.filter { outcome in outcome.snapshotGeneration.map { $0 < outcome.dbGeneration } ?? false }.count
    let size = ((try? FileManager.default.attributesOfItem(atPath: directory.appending(path: RoomStorage.databaseName).path)[.size]) as? Int) ?? 0
    let finalState = try? RoomStorage(directory: directory).open().state
    let entries = finalState?.entries.count ?? -1
    let archived = finalState?.archive.count ?? -1
    func percentile(_ p: Double) -> Double {
        micros.isEmpty ? 0 : Double(micros[min(micros.count - 1, Int(Double(micros.count) * p))]) / 1000
    }
    print("""
    summary: \(kills) kills in \(elapsed), \(failures.count) failures
      kills with a transaction in flight: \(midWrite) (rolled back to the previous generation: \(rolledBack))
      reopened ahead of the last ack (committed, ack not yet read; informational): \(aheadOfAck)
      reopened behind the last ack (an acknowledged write lost): \(behindAck)
      final generation \(outcomes.last?.dbGeneration ?? 0), \(log.state.withLock { $0.commitMicros.count }) commits, \(entries) entries, \(archived) archived, database \(size / 1024) KB
      commit time median \(percentile(0.5)) ms, p95 \(percentile(0.95)) ms, max \(percentile(1)) ms
      snapshots one generation behind the database: \(snapshotBehind)
    """)
    if !failures.isEmpty {
        failures.forEach { print($0) }
        exit(1)
    }
    exit(0)
}

switch arguments.first {
case "writer":
    guard arguments.count >= 2 else { fail("writer <dir>") }
    let debounce = Duration.milliseconds(Int(option("--debounce-ms") ?? "300")!)
    runWriter(directory: URL(fileURLWithPath: arguments[1]), debounce: debounce, seed: UInt64(option("--seed") ?? "1")!)
case "run":
    runDriver()
default:
    fail("usage: room-persistence-harness run [--dir D] [--kills N] [--debounce-ms MS] [--seed N] | writer <dir>")
}
