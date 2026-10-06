import Foundation
import GRDB
import Synchronization

/// Hooks around each write, called on the writer queue (the kill-test
/// harness logs content hashes through them).
public protocol StateWriterObserver: Sendable {
    func stateWriter(willWrite state: RoomState, generation: Int64)
    func stateWriter(didCommit generation: Int64)
}

public enum WriteOutcome: Equatable, Sendable {
    case committed
    /// A newer generation is already on disk; nothing was written.
    case stale
}

/// Writes whole-state snapshots to the database, one transaction each, on a
/// serial queue. Only the difference from the last committed state is
/// written. A write whose generation is not newer than the committed one is
/// dropped, so a stale snapshot never lands after a newer one. After each
/// commit the state is also written as a JSON snapshot (atomic rename).
public final class StateWriter: Sendable {
    public let database: RoomDatabase
    public let snapshotURL: URL?
    private let queue = DispatchQueue(label: "Room.StateWriter", qos: .utility)
    private let committed: Mutex<(state: RoomState, generation: Int64)>
    private let observer: (any StateWriterObserver)?

    public init(database: RoomDatabase, snapshotURL: URL?, committed state: RoomState, generation: Int64,
                observer: (any StateWriterObserver)? = nil) {
        self.database = database
        self.snapshotURL = snapshotURL
        self.committed = Mutex((state, generation))
        self.observer = observer
    }

    public var committedGeneration: Int64 { committed.withLock { $0.generation } }

    /// Queues a write; `completion` runs on the writer queue.
    public func write(_ state: RoomState, generation: Int64, cleanExit: Bool = false,
                      completion: (@Sendable (Result<WriteOutcome, any Error>) -> Void)? = nil) {
        queue.async {
            let result = Result { try self.perform(state, generation: generation, cleanExit: cleanExit) }
            if case .failure(let error) = result { NSLog("Room: state write \(generation) failed: \(error)") }
            completion?(result)
        }
    }

    /// Writes after everything already queued and waits for it.
    @discardableResult
    public func writeAndWait(_ state: RoomState, generation: Int64, cleanExit: Bool = false) throws -> WriteOutcome {
        try queue.sync { try perform(state, generation: generation, cleanExit: cleanExit) }
    }

    /// Waits until every queued write has finished.
    public func drain() { queue.sync {} }

    private func perform(_ state: RoomState, generation: Int64, cleanExit: Bool) throws -> WriteOutcome {
        dispatchPrecondition(condition: .onQueue(queue))
        let previous = committed.withLock { $0 }
        guard generation > previous.generation else {
            if cleanExit { try markCleanExit() }
            return .stale
        }
        observer?.stateWriter(willWrite: state, generation: generation)
        try database.pool.write { db in
            // The database may hold a newer generation than this writer knows
            // (another writer, a restored file); never move it backwards.
            let onDisk = try RoomDatabase.generation(db)
            guard generation > onDisk else { throw StateWriterError.generationBehindDatabase(generation, onDisk) }
            try Self.apply(from: previous.state, to: state, in: db)
            try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)",
                           arguments: [KVKey.generation, String(generation)])
            if cleanExit {
                try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, '0')", arguments: [KVKey.running])
            }
        }
        committed.withLock { $0 = (state, generation) }
        observer?.stateWriter(didCommit: generation)
        writeSnapshot(state, generation: generation)
        return .committed
    }

    private func markCleanExit() throws {
        try database.pool.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, '0')", arguments: [KVKey.running])
        }
    }

    private func writeSnapshot(_ state: RoomState, generation: Int64) {
        guard let snapshotURL else { return }
        do {
            try StateSnapshot(generation: generation, state: state).encoded().write(to: snapshotURL, options: .atomic)
        } catch {
            NSLog("Room: JSON snapshot \(generation) failed: \(error)")
        }
    }

    // MARK: Diff

    static func apply(from old: RoomState, to new: RoomState, in db: Database) throws {
        try sync(old.profiles, new.profiles, in: db)
        try sync(old.spaces, new.spaces, in: db)
        try sync(old.splitGroups, new.splitGroups, in: db)
        try sync(old.entries, new.entries, in: db)
        try sync(old.windows, new.windows, in: db)
        try syncWindowSpaces(old.windowSpaces, new.windowSpaces, in: db)
        try syncArchive(old.archive, new.archive, in: db)
        if old.settings != new.settings {
            let json = String(decoding: try JSONEncoder().encode(new.settings), as: UTF8.self)
            try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", arguments: [KVKey.settings, json])
        }
    }

    private static func sync<Record: Identifiable & Hashable & PersistableRecord>(
        _ old: [Record], _ new: [Record], in db: Database
    ) throws where Record.ID == UUID {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var seen = Set<UUID>()
        for record in new {
            seen.insert(record.id)
            if before[record.id] != record { try record.upsert(db) }
        }
        let removed = before.keys.filter { !seen.contains($0) }
        if !removed.isEmpty { _ = try Record.deleteAll(db, keys: removed) }
    }

    /// Archive rows are written once and edited only by the retention (B-80:
    /// the navigation state dropped; a restore deletes the row, archiving the
    /// entry again makes a new one), so rows compare by their small columns
    /// and whether a state is present: the navigation-state blobs of thousands
    /// of rows are not compared on every write.
    private static func syncArchive(_ old: [ArchivedEntry], _ new: [ArchivedEntry], in db: Database) throws {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var seen = Set<UUID>()
        for row in new {
            seen.insert(row.id)
            if let previous = before[row.id], previous.archivedAt == row.archivedAt, previous.reason == row.reason,
               previous.url == row.url, previous.title == row.title, previous.spaceID == row.spaceID,
               previous.profileID == row.profileID, previous.faviconID == row.faviconID,
               (previous.navigationState == nil) == (row.navigationState == nil) { continue }
            try row.upsert(db)
        }
        let removed = before.keys.filter { !seen.contains($0) }
        if !removed.isEmpty { _ = try ArchivedEntry.deleteAll(db, keys: removed) }
    }

    private static func syncWindowSpaces(_ old: [WindowSpace], _ new: [WindowSpace], in db: Database) throws {
        struct Key: Hashable { var window: UUID; var space: UUID }
        let before = Dictionary(old.map { (Key(window: $0.windowID, space: $0.spaceID), $0) }, uniquingKeysWith: { _, last in last })
        var seen = Set<Key>()
        for row in new {
            let key = Key(window: row.windowID, space: row.spaceID)
            seen.insert(key)
            if before[key] != row { try row.upsert(db) }
        }
        for key in before.keys where !seen.contains(key) {
            _ = try WindowSpace.deleteOne(db, key: ["windowID": key.window, "spaceID": key.space])
        }
    }
}

public enum StateWriterError: Error, Equatable {
    case generationBehindDatabase(Int64, Int64)
}

/// The JSON backup written after every commit.
public struct StateSnapshot: Codable, Sendable, Equatable {
    public var generation: Int64
    public var state: RoomState

    public init(generation: Int64, state: RoomState) {
        self.generation = generation
        self.state = state
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // The archive and the entries' navigation states stay out of the
        // snapshot: it is rewritten after every commit, and the states made a
        // 500-entry snapshot 5.66 MB (B-73). A recovery from the snapshot
        // starts with an empty Archive and no back/forward lists; the database
        // backups (`RoomBackups`, 4.1b) keep both.
        var state = state.canonical()
        state.archive = []
        for index in state.entries.indices { state.entries[index].navigationState = nil }
        return try encoder.encode(StateSnapshot(generation: generation, state: state))
    }

    public static func read(from url: URL) throws -> StateSnapshot {
        try JSONDecoder().decode(StateSnapshot.self, from: Data(contentsOf: url))
    }
}
