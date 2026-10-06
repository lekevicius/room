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
        // A file left mostly free pages (v6 dropping the history tables: 99 % of a
        // 50k-row state, 3.9) gives them back once; a no-op on every later open.
        let pages = try pool.read { db in
            (try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0, try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0)
        }
        if pages.1 > 256, pages.1 * 2 > pages.0 { try pool.vacuum() }
    }

    /// The profiles stored in the database at `url`, read without migrating
    /// or writing anything (4.4b: the app moves the engine's profile
    /// directories before the engine and the store open). Empty when there
    /// is no file; throws when it cannot be read.
    public static func storedProfiles(at url: URL) throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        defer { try? queue.close() }
        return try queue.read { db in try Profile.order(Column("position")).fetchAll(db) }
    }

    /// The settings stored in the database at `url`, read without migrating
    /// or writing anything (4.7a: the app passes the engine's launch-time
    /// switches before the store opens). The defaults when there is no file
    /// or no settings row; throws when the file cannot be read.
    public static func storedSettings(at url: URL) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else { return Settings() }
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        defer { try? queue.close() }
        return try queue.read { db in
            guard try db.tableExists("kv"),
                  let json = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.settings])
            else { return Settings() }
            return (try? JSONDecoder().decode(Settings.self, from: Data(json.utf8))) ?? Settings()
        }
    }

    /// `PRAGMA integrity_check` lines; `["ok"]` when the file is sound.
    public func integrityCheck() throws -> [String] {
        try pool.read { db in try String.fetchAll(db, sql: "PRAGMA integrity_check") }
    }

    /// `PRAGMA quick_check` lines: the integrity check without the index
    /// cross-checks, O(N) instead of O(N log N); `["ok"]` when sound.
    public func quickCheck() throws -> [String] {
        try pool.read { db in try String.fetchAll(db, sql: "PRAGMA quick_check") }
    }

    /// Whether the previous session left the running flag set (it ended
    /// without a clean quit). Reads only; `beginSession` sets the flag.
    public func previousSessionRunning() throws -> Bool {
        try pool.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.running]) == "1"
        }
    }

    /// The schema's object names (tables, indexes, triggers) containing `text`
    /// (the 3.9 spikes check v6 left no history table).
    public func schemaNames(containing text: String) throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE name LIKE ? ORDER BY name", arguments: ["%\(text)%"])
        }
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
            state.archive = try ArchivedEntry.order(Column("archivedAt").desc).fetchAll(db)
            state.routingRules = try RoutingRule.order(Column("position")).fetchAll(db)
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

    /// Rows in the `archive` table (schema v7; spikes and diagnostics).
    public func archivedRowCount() throws -> Int {
        try pool.read { db in try ArchivedEntry.fetchCount(db) }
    }

    // MARK: Favicon cache (outside the state pipeline)

    public func favicons() throws -> [Favicon] {
        try pool.read { db in try Favicon.fetchAll(db) }
    }

    /// Inserts or replaces the row for `favicon.host`; returns its id.
    public func saveFavicon(_ favicon: Favicon) throws -> Int64? {
        var record = favicon
        return try pool.write { db in
            if record.id == nil { try record.insert(db) } else { try record.update(db) }
            return record.id
        }
    }
}
