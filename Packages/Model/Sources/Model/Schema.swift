import GRDB

/// Schema migrations. Never edit a shipped migration; append a new one.
public enum Schema {
    public static let v1 = "v1"

    /// Phase 2.4b: history's host key and frecency (`History`, `Frecency`).
    public static let v2 = "v2-history-frecency"

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(v1, migrate: createV1)
        migrator.registerMigration(v2, migrate: createV2)
        return migrator
    }

    /// `history_url.host` (lowercased, without "www.") and `frecency` (the
    /// decayed-visit logarithm) for ordering, and `history_host`, one row per
    /// host with its summed frecency and most frecent URL, so inline host
    /// completion is a range scan over hosts rather than a grouping of every
    /// URL (Firefox's `moz_origins`). Rows already present are backfilled.
    static func createV2(_ db: Database) throws {
        try db.alter(table: "history_url") { t in
            t.add(column: "host", .text).notNull().defaults(to: "")
            t.add(column: "frecency", .double).notNull().defaults(to: Frecency.none)
        }
        try db.create(index: "history_url_frecency", on: "history_url", columns: ["frecency"])
        try db.create(index: "history_url_host", on: "history_url", columns: ["host", "frecency"])
        try db.create(table: "history_host") { t in
            t.primaryKey("host", .text)
            t.column("bestURL", .text).notNull()
            t.column("bestFrecency", .double).notNull()
            t.column("frecency", .double).notNull()
            t.column("visitCount", .integer).notNull()
            t.column("typedCount", .integer).notNull()
        }
        let rows = try Row.fetchAll(db, sql: "SELECT id, url FROM history_url")
        for row in rows {
            let id: Int64 = row["id"]
            var frecency = Frecency.none
            let visits = try Row.fetchAll(db, sql: "SELECT visitedAt, transition FROM history_visit WHERE urlID = ?", arguments: [id])
            for visit in visits {
                let time: Timestamp = visit["visitedAt"]
                let transition = HistoryTransition(rawValue: visit["transition"]) ?? .other
                frecency = Frecency.adding(transition.weight, at: time.date, to: frecency)
            }
            try db.execute(sql: "UPDATE history_url SET host = ?, frecency = ? WHERE id = ?",
                           arguments: [History.hostKey(for: row["url"]) ?? "", frecency, id])
        }
        for host in try String.fetchAll(db, sql: "SELECT DISTINCT host FROM history_url") {
            try History.rebuildHost(db, host)
        }
    }

    /// Foreign keys are deferred: the writer applies a whole-state diff in one
    /// transaction in any order, and SQLite checks references at commit.
    /// Nothing cascades; the store removes dependents itself.
    static func createV1(_ db: Database) throws {
        try db.create(table: "profile") { t in
            t.primaryKey("id", .blob)
            t.column("name", .text).notNull()
            t.column("position", .integer).notNull()
        }

        try db.create(table: "space") { t in
            t.primaryKey("id", .blob)
            t.column("name", .text).notNull()
            t.column("icon", .text)
            t.column("themeColors", .jsonText).notNull()
            t.column("themeAlgorithm", .text).notNull()
            t.column("themeOpacity", .double).notNull()
            t.column("profileID", .blob).notNull().references("profile", deferred: true)
            t.column("position", .integer).notNull()
            t.column("pinnedCollapsed", .boolean).notNull()
        }

        try db.create(table: "split_group") { t in
            t.primaryKey("id", .blob)
            t.column("layout", .text).notNull()
            t.column("ratios", .jsonText).notNull()
        }

        try db.create(table: "favicon") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("host", .text).notNull().unique()
            t.column("png", .blob).notNull()
            t.column("sha256", .text).notNull()
            t.column("updatedAt", .integer).notNull()
        }

        try db.create(table: "entry") { t in
            t.primaryKey("id", .blob)
            t.column("kind", .text).notNull()
                .check { ["essential", "pinned", "folder", "today"].contains($0) }
            t.column("spaceID", .blob).indexed().references("space", deferred: true)
            t.column("profileID", .blob).notNull().indexed().references("profile", deferred: true)
            t.column("folderID", .blob).indexed().references("entry", deferred: true)
            t.column("splitGroupID", .blob).references("split_group", deferred: true)
            t.column("position", .integer).notNull()
            t.column("storedURL", .text)
            t.column("storedTitle", .text)
            t.column("customLabel", .text)
            t.column("customIcon", .text)
            t.column("faviconID", .integer)
            t.column("isCollapsed", .boolean).notNull()
            t.column("createdAt", .integer).notNull()
            t.column("lastActiveAt", .integer)
            t.column("liveURL", .text)
            t.column("liveTitle", .text)
            // Essentials have no space; everything else has one.
            t.check(sql: "(kind = 'essential') = (spaceID IS NULL)")
        }

        try db.create(table: "window") { t in
            t.primaryKey("id", .blob)
            t.column("frameX", .double)
            t.column("frameY", .double)
            t.column("frameWidth", .double)
            t.column("frameHeight", .double)
            t.column("sidebarWidth", .double).notNull()
            t.column("sidebarVisible", .boolean).notNull()
            t.column("activeSpaceID", .blob).references("space", deferred: true)
            t.column("position", .integer).notNull()
        }

        try db.create(table: "window_space") { t in
            t.column("windowID", .blob).notNull().references("window", deferred: true)
            t.column("spaceID", .blob).notNull().references("space", deferred: true)
            t.column("selectedEntryID", .blob).references("entry", deferred: true)
            t.primaryKey(["windowID", "spaceID"])
        }

        // Throwaway local history until the engine's history service (3.5).
        try db.create(table: "history_url") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("url", .text).notNull().unique()
            t.column("title", .text)
            t.column("visitCount", .integer).notNull().defaults(to: 0)
            t.column("typedCount", .integer).notNull().defaults(to: 0)
            t.column("lastVisitAt", .integer).notNull()
        }

        try db.create(table: "history_visit") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("urlID", .integer).notNull().indexed()
                .references("history_url", onDelete: .cascade)
            t.column("visitedAt", .integer).notNull().indexed()
            t.column("transition", .text).notNull()
        }

        // External-content FTS5 over history_url, kept in sync by triggers;
        // trigram so "ikip" finds wikipedia (palette substring matching).
        try db.create(virtualTable: "history_fts", using: FTS5()) { t in
            t.synchronize(withTable: "history_url")
            t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
            t.column("url")
            t.column("title")
        }

        try db.create(table: "kv") { t in
            t.primaryKey("key", .text)
            t.column("value", .text).notNull()
        }
    }
}

/// Keys of the `kv` table.
public enum KVKey {
    /// Generation of the last committed state write.
    public static let generation = "generation"
    /// "1" while the app runs; a "1" at launch means the last exit was unclean.
    public static let running = "running"
    /// `Settings` as JSON.
    public static let settings = "settings"
}
