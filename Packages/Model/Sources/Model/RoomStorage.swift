import Foundation

/// Opens the database in a directory, recovering from the JSON snapshot when
/// the file cannot be opened or fails `PRAGMA integrity_check`.
public struct RoomStorage: Sendable {
    public static let databaseName = "Room.sqlite"
    public static let snapshotName = "Room-snapshot.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
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
    }

    public enum Recovery: Sendable, Equatable {
        case fromSnapshot(generation: Int64, movedAside: URL)
        case empty(movedAside: URL)
    }

    /// Opens, checks and loads. Marks the session as running.
    public func open() throws -> Opened {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let database = try? RoomDatabase(url: databaseURL),
           (try? database.integrityCheck()) == ["ok"],
           let loaded = try? database.loadState() {
            let unclean = try database.beginSession()
            refreshSnapshot(loaded.state, generation: loaded.generation)
            return Opened(database: database, state: loaded.state, generation: loaded.generation,
                          uncleanExit: unclean, recovery: nil)
        }
        return try recover()
    }

    private func recover() throws -> Opened {
        let aside = try moveDatabaseAside()
        let database = try RoomDatabase(url: databaseURL)
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
