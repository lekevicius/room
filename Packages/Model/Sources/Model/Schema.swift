import Foundation
import GRDB

/// Schema migrations. Never edit a shipped migration; append a new one.
public enum Schema {
    public static let v1 = "v1"

    /// Phase 2.4b: history's host key and frecency (frozen in `Schema+LegacyHistory.swift`).
    public static let v2 = "v2-history-frecency"

    /// Phase 2.5: history follows the profile (decided 2026-10-03, ROADMAP 2.5).
    public static let v3 = "v3-history-profile"

    /// Phase 2.7b: a split group's pane order (`SplitGroup.members`).
    public static let v4 = "v4-split-members"

    /// Phase 3.7b: each entry's back/forward list as the engine serialised it
    /// (`Entry.navigationState`, a BLOB), so a relaunch, a crash recovery and
    /// every revival of an unloaded entry keep its history. (3.9's drop of
    /// the local history tables, planned as v5 in ROADMAP 3.9, becomes v6.)
    public static let v5 = "v5-entry-navigation-state"

    /// Phase 3.9: the Chapter 2 history tables go (3.5 moved history into the
    /// engine's `HistoryService`); what the engine does not hold is written to
    /// `history-archive.json` beside the database first (`HistoryArchive`, B-66).
    public static let v6 = "v6-drop-local-history"

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(v1, migrate: createV1)
        migrator.registerMigration(v2, migrate: createV2)
        migrator.registerMigration(v3, migrate: createV3)
        migrator.registerMigration(v4, migrate: createV4)
        migrator.registerMigration(v5, migrate: createV5)
        migrator.registerMigration(v6, migrate: createV6)
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
                           arguments: [LegacyHistory.hostKey(for: row["url"]) ?? "", frecency, id])
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
            ?? LegacyHistory.orphanProfile.databaseValue
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
            try LegacyHistory.rebuildHost(db, profile: row["profileID"], host: row["host"])
        }
    }

    /// Foreign keys are deferred: the writer applies a whole-state diff in one
    /// transaction in any order, and SQLite checks references at commit.
    /// Nothing cascades; the store removes dependents itself.
    /// `split_group.members`, the pane order; existing groups take their
    /// members in section order, then position (what the sidebar showed).
    static func createV4(_ db: Database) throws {
        try db.alter(table: "split_group") { t in
            t.add(column: "members", .jsonText).notNull().defaults(to: "[]")
        }
        let rows = try Row.fetchAll(db, sql: "SELECT id, splitGroupID, kind, position FROM entry WHERE splitGroupID IS NOT NULL")
        let order = ["essential": 0, "pinned": 1, "folder": 1, "today": 2]
        let grouped = Dictionary(grouping: rows) { $0["splitGroupID"] as Data? ?? Data() }
        for (group, members) in grouped {
            let sorted = members.sorted {
                (order[$0["kind"] as String? ?? ""] ?? 3, $0["position"] as Int? ?? 0) < (order[$1["kind"] as String? ?? ""] ?? 3, $1["position"] as Int? ?? 0)
            }
            let ids = sorted.compactMap { ($0["id"] as UUID?)?.uuidString }
            let json = String(data: try JSONSerialization.data(withJSONObject: ids), encoding: .utf8) ?? "[]"
            try db.execute(sql: "UPDATE split_group SET members = ? WHERE id = ?", arguments: [json, group])
        }
    }

    /// `entry.navigationState`: existing entries have none (they come back
    /// at their URL, as before).
    static func createV5(_ db: Database) throws {
        try db.alter(table: "entry") { t in
            t.add(column: "navigationState", .blob)
        }
    }

    /// The archive (an error here fails the migration and keeps the tables),
    /// then the tables: the FTS index and its sync triggers, visits, hosts,
    /// URLs. The settings flag `historyImportedProfiles` stays (an archive of
    /// a never-imported profile is imported at the next launch by it).
    static func createV6(_ db: Database) throws {
        try HistoryArchive.write(db)
        for trigger in ["__history_fts_ai", "__history_fts_ad", "__history_fts_au"] {
            try db.execute(sql: "DROP TRIGGER IF EXISTS \(trigger)")
        }
        try db.execute(sql: "DROP TABLE IF EXISTS history_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS history_visit")
        try db.execute(sql: "DROP TABLE IF EXISTS history_host")
        try db.execute(sql: "DROP TABLE IF EXISTS history_url")
    }

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

        // Throwaway local history until the engine's history service (3.5; dropped in v6).
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
