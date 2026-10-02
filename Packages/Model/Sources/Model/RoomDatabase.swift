import Foundation
import GRDB

/// The one SQLite database (WAL) in `~/Library/Application Support/Room/`.
public final class RoomDatabase: Sendable {
    public let url: URL
    public let pool: DatabasePool

    /// How long a statement waits for another connection's lock (a second
    /// Room instance writing the same file) before failing with SQLITE_BUSY.
    public static let defaultBusyTimeout: TimeInterval = 5

    /// Opens (creating if needed) and migrates to the latest schema.
    public init(url: URL, busyTimeout: TimeInterval = RoomDatabase.defaultBusyTimeout) throws {
        self.url = url
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.label = "Room"
        configuration.busyMode = .timeout(busyTimeout)
        // Default synchronous mode (FULL): a committed write survives a crash
        // of the process and of the machine.
        pool = try DatabasePool(path: url.path, configuration: configuration)
        try Schema.migrator.migrate(pool)
    }

    /// `PRAGMA integrity_check` lines; `["ok"]` when the file is sound.
    public func integrityCheck() throws -> [String] {
        try pool.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
    }

    /// Rows that violate a foreign key (empty when consistent).
    public func foreignKeyViolations() throws -> Int {
        try pool.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count }
    }

    /// Generation of the last committed state write (0 = never written).
    public func generation() throws -> Int64 {
        try pool.read { db in try Self.generation(db) }
    }

    static func generation(_ db: Database) throws -> Int64 {
        try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.generation])
            .flatMap(Int64.init) ?? 0
    }

    /// The persisted state and its generation.
    public func loadState() throws -> (state: RoomState, generation: Int64) {
        try pool.read { db in
            var state = RoomState()
            state.profiles = try Profile.order(Column("position")).fetchAll(db)
            state.spaces = try Space.order(Column("position")).fetchAll(db)
            state.entries = try Entry.order(Column("position")).fetchAll(db)
            state.splitGroups = try SplitGroup.fetchAll(db)
            state.windows = try WindowState.order(Column("position")).fetchAll(db)
            state.windowSpaces = try WindowSpace.fetchAll(db)
            if let json = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.settings]) {
                state.settings = (try? JSONDecoder().decode(Settings.self, from: Data(json.utf8))) ?? Settings()
            }
            return (state, try Self.generation(db))
        }
    }

    /// Marks the app as running and returns whether it already was, i.e.
    /// whether the previous session ended without a clean quit.
    @discardableResult
    public func beginSession() throws -> Bool {
        try pool.write { db in
            let wasRunning = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.running]) == "1"
            try db.execute(sql: "INSERT OR REPLACE INTO kv (key, value) VALUES (?, '1')", arguments: [KVKey.running])
            return wasRunning
        }
    }
}
