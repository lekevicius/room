import Foundation
import GRDB

/// Schema migrations. Never edit a shipped migration; append a new one.
public enum Schema {
    public static let v1 = "v1"

    /// Phase 2.4b: history's host key and frecency (`History`, `Frecency`).
    public static let v2 = "v2-history-frecency"

    /// Phase 2.5: history follows the profile (decided 2026-10-03, ROADMAP 2.5).
    public static let v3 = "v3-history-profile"

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(v1, migrate: createV1)
        migrator.registerMigration(v2, migrate: createV2)
        migrator.registerMigration(v3, migrate: createV3)
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
            try rebuildHostV2(db, host)
        }
    }

    /// v2's `History.rebuildHost`, frozen with the migration that uses it
    /// (v3 keys hosts by profile).
    private static func rebuildHostV2(_ db: Database, _ host: String) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT url, frecency, visitCount, typedCount FROM history_url WHERE host = ? ORDER BY frecency DESC",
                                    arguments: [host])
        guard let best = rows.first else {
            try db.execute(sql: "DELETE FROM history_host WHERE host = ?", arguments: [host])
            return
        }
        let top: Double = best["frecency"]
        let sum = top + log(rows.reduce(0.0) { $0 + exp(($1["frecency"] as Double) - top) })
        try db.execute(sql: """
            INSERT OR REPLACE INTO history_host (host, bestURL, bestFrecency, frecency, visitCount, typedCount) VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [host, best["url"] as String, top, sum, rows.reduce(0) { $0 + ($1["visitCount"] as Int) },
                               rows.reduce(0) { $0 + ($1["typedCount"] as Int) }])
    }

    /// `history_url.profileID`: each profile keeps its own history, as in
    /// Chromium and Arc. A URL is unique per profile, not per database, so
    /// `history_url` is rebuilt (SQLite cannot change a UNIQUE constraint in
    /// place) with the same row ids, which keeps `history_visit` pointing at
    /// its URLs; `history_host` is keyed by (profile, host) and recomputed;
    /// the FTS index is recreated over the new table. Rows from v2 belong to
    /// the default profile (the first by position). GRDB runs migrations with
    /// foreign keys off, so dropping the old table cascades nothing.
    static func createV3(_ db: Database) throws {
        let defaultProfile = try DatabaseValue.fetchOne(db, sql: "SELECT id FROM profile ORDER BY position LIMIT 1")
            ?? History.orphanProfile.databaseValue
        try db.create(table: "history_url_v3") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("profileID", .blob).notNull()
            t.column("url", .text).notNull()
            t.column("title", .text)
            t.column("visitCount", .integer).notNull().defaults(to: 0)
            t.column("typedCount", .integer).notNull().defaults(to: 0)
            t.column("lastVisitAt", .integer).notNull()
            t.column("host", .text).notNull().defaults(to: "")
            t.column("frecency", .double).notNull().defaults(to: Frecency.none)
            t.uniqueKey(["profileID", "url"])
        }
        try db.execute(sql: """
            INSERT INTO history_url_v3 (id, profileID, url, title, visitCount, typedCount, lastVisitAt, host, frecency)
            SELECT id, ?, url, title, visitCount, typedCount, lastVisitAt, host, frecency FROM history_url
            """, arguments: [defaultProfile])
        try db.drop(table: "history_fts")
        try db.drop(table: "history_url")
        try db.rename(table: "history_url_v3", to: "history_url")
        try db.create(index: "history_url_frecency", on: "history_url", columns: ["profileID", "frecency"])
        try db.create(index: "history_url_host", on: "history_url", columns: ["profileID", "host", "frecency"])
        try db.create(virtualTable: "history_fts", using: FTS5()) { t in
            t.synchronize(withTable: "history_url")
            t.tokenizer = FTS5TokenizerDescriptor(components: ["trigram"])
            t.column("url")
            t.column("title")
        }

        try db.drop(table: "history_host")
        try db.create(table: "history_host") { t in
            t.column("profileID", .blob).notNull()
            t.column("host", .text).notNull()
            t.column("bestURL", .text).notNull()
            t.column("bestFrecency", .double).notNull()
            t.column("frecency", .double).notNull()
            t.column("visitCount", .integer).notNull()
            t.column("typedCount", .integer).notNull()
            t.primaryKey(["profileID", "host"])
        }
        for row in try Row.fetchAll(db, sql: "SELECT DISTINCT profileID, host FROM history_url") {
            try History.rebuildHost(db, profile: row["profileID"], host: row["host"])
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
