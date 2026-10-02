import GRDB

/// Schema migrations. Never edit a shipped migration; append a new one.
public enum Schema {
    public static let v1 = "v1"

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(v1, migrate: createV1)
        return migrator
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
