import Foundation
import GRDB

/// Opens the database in a directory, recovering from the JSON snapshot only
/// when the file is damaged: SQLite reports it corrupt or not a database, or
/// the integrity check finds faults (`PRAGMA quick_check` at every launch,
/// the full `integrity_check` only after an unclean exit; B-42). Any other failure (above all a
/// database another process holds locked) fails the open and leaves the file
/// where it is.
public struct RoomStorage: Sendable {
    public static let databaseName = "Room.sqlite"
    public static let snapshotName = "Room-snapshot.json"

    public let directory: URL
    /// Passed to `RoomDatabase` (tests shorten it).
    public let busyTimeout: TimeInterval

    public init(directory: URL, busyTimeout: TimeInterval = RoomDatabase.defaultBusyTimeout) {
        self.directory = directory
        self.busyTimeout = busyTimeout
    }

    /// Why `open()` failed without touching the database file.
    public enum OpenError: Error, CustomStringConvertible {
        /// Another connection kept the database locked past the busy timeout
        /// (typically a second Room instance using the same directory).
        case inUse(path: String, underlying: String)
        /// SQLite failed for a reason other than damage or locking.
        case unreadable(path: String, underlying: String)

        public var description: String {
            switch self {
            case .inUse(let path, let underlying): "The database at \(path) is in use by another process (\(underlying))"
            case .unreadable(let path, let underlying): "The database at \(path) could not be opened (\(underlying))"
            }
        }
    }

    public var databaseURL: URL { directory.appending(path: Self.databaseName) }
    public var snapshotURL: URL { directory.appending(path: Self.snapshotName) }

    public struct Opened: Sendable {
        public let database: RoomDatabase
        public let state: RoomState
        public let generation: Int64
        /// The previous session did not quit cleanly.
        public let uncleanExit: Bool
        /// The database was unusable and was rebuilt (from the snapshot if
        /// there was one); the broken file was moved aside.
        public let recovery: Recovery?
        /// Which check the open ran (`nil` after a recovery).
        public var check: IntegrityCheck? = nil
    }

    /// The check run when a database opens.
    public enum IntegrityCheck: Sendable, Equatable {
        /// `PRAGMA quick_check`: page and record structure, no index cross-check.
        case quick
        /// `PRAGMA integrity_check`: everything, O(N log N) in the rows (0.35–0.56 s at
        /// 50k history rows, B-42).
        case full
    }

    /// The rule (B-42): the full check only when the previous session ended
    /// without a clean quit (a crash, a kill, a power loss); otherwise the quick
    /// one. Damage the quick check misses surfaces as `SQLITE_CORRUPT` from the
    /// load, which recovers the same way.
    public static func integrityCheck(afterUncleanExit unclean: Bool) -> IntegrityCheck {
        unclean ? .full : .quick
    }

    public enum Recovery: Sendable, Equatable {
        case fromSnapshot(generation: Int64, movedAside: URL)
        case empty(movedAside: URL)
    }

    /// Opens, checks and loads. Marks the session as running. Throws
    /// `OpenError` when the database is locked or fails for a reason other
    /// than damage; only damage moves it aside (`Opened.recovery`).
    public func open() throws -> Opened {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var opened: RoomDatabase?
        do {
            let database = try RoomDatabase(url: databaseURL, busyTimeout: busyTimeout)
            opened = database
            let check = Self.integrityCheck(afterUncleanExit: try database.previousSessionRunning())
            let result = switch check {
            case .quick: try database.quickCheck()
            case .full: try database.integrityCheck()
            }
            guard result == ["ok"] else {
                try? database.pool.close()
                return try recover()
            }
            let loaded = try database.loadState()
            let unclean = try database.beginSession()
            refreshSnapshot(loaded.state, generation: loaded.generation)
            return Opened(database: database, state: loaded.state, generation: loaded.generation,
                          uncleanExit: unclean, recovery: nil, check: check)
        } catch let error as DatabaseError {
            try? opened?.pool.close()
            switch error.resultCode {
            case .SQLITE_CORRUPT, .SQLITE_NOTADB:
                return try recover()
            case .SQLITE_BUSY, .SQLITE_LOCKED:
                throw OpenError.inUse(path: databaseURL.path, underlying: "\(error)")
            default:
                throw OpenError.unreadable(path: databaseURL.path, underlying: "\(error)")
            }
        }
    }

    private func recover() throws -> Opened {
        let aside = try moveDatabaseAside()
        let database = try RoomDatabase(url: databaseURL, busyTimeout: busyTimeout)
        guard let snapshot = try? StateSnapshot.read(from: snapshotURL) else {
            try database.beginSession()
            return Opened(database: database, state: RoomState(), generation: 0, uncleanExit: true,
                          recovery: .empty(movedAside: aside))
        }
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        try writer.writeAndWait(snapshot.state, generation: max(snapshot.generation, 1))
        let loaded = try database.loadState()
        try database.beginSession()
        return Opened(database: database, state: loaded.state, generation: loaded.generation, uncleanExit: true,
                      recovery: .fromSnapshot(generation: snapshot.generation, movedAside: aside))
    }

    /// The snapshot is written after each commit, so a kill between the two
    /// leaves it one generation behind; repeated kills could stack that up.
    /// At open it is brought level with the database (or rewritten if
    /// unreadable), so it never trails by more than one generation.
    private func refreshSnapshot(_ state: RoomState, generation: Int64) {
        guard generation > 0 else { return }
        if let snapshot = try? StateSnapshot.read(from: snapshotURL), snapshot.generation >= generation { return }
        do {
            try StateSnapshot(generation: generation, state: state).encoded().write(to: snapshotURL, options: .atomic)
        } catch {
            NSLog("Room: JSON snapshot refresh failed: \(error)")
        }
    }

    /// Moves `Room.sqlite` and its `-wal`/`-shm` into `Corrupt/<timestamp>/`.
    private func moveDatabaseAside() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = directory.appending(path: "Corrupt/\(stamp)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = directory.appending(path: Self.databaseName + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.moveItem(at: source, to: target.appending(path: Self.databaseName + suffix))
        }
        return target
    }

    /// The writer for an opened database, continuing from its generation.
    public func makeWriter(for opened: Opened, observer: (any StateWriterObserver)? = nil) -> StateWriter {
        StateWriter(database: opened.database, snapshotURL: snapshotURL, committed: opened.state,
                    generation: opened.generation, observer: observer)
    }
}
