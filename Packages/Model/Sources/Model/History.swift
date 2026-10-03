import Foundation
import GRDB

// Local browsing history for the palette (ROADMAP 2.4 tasks 3–4): the
// `history_url` / `history_visit` / `history_fts` tables of schema v1 plus
// v2's `host` and `frecency` columns and v3's `profileID`: every profile
// keeps its own history (Chromium, Arc), so every read and write names one.
// Throwaway until the engine's history service (Chapter 3.5).

/// How a recorded navigation started (the engine's page transition, as history sees it).
public enum HistoryTransition: String, Hashable, Sendable, CaseIterable {
    case typed, link, bookmark, generated, keyword, formSubmit, reload, other

    /// Frecency weight of one visit (Firefox's visit-type bonuses, scaled so
    /// a link is 1): a typed URL is what the user wants back, a search
    /// results page or a form post much less so.
    public var weight: Double {
        switch self {
        case .typed: 2
        case .bookmark: 1.5
        case .link, .other: 1
        case .generated, .keyword, .formSubmit: 0.3
        case .reload: 0
        }
    }

    /// Reloads are not visits (Chromium's history skips them; they would
    /// inflate the page they repeat).
    public var isVisit: Bool { self != .reload }
}

/// Frecency as one number that never needs a decay job: the sum of every
/// visit's weight decayed exponentially from its time, stored as a natural
/// log referenced to a fixed epoch. All rows decay at the same rate, so the
/// stored value orders rows exactly as their current frecency would, and a
/// new visit is one `log(exp(a) + exp(b))`. (Firefox's exponential-decay
/// frecency, `macos-ui-stack.md` §5.2, without the daily recalculation.)
public enum Frecency {
    /// A visit counts half as much after this long.
    public static let halfLife: TimeInterval = 30 * 86_400
    /// The stored value of a row without visits.
    public static let none = -1_000.0
    /// 2026-01-01T00:00:00Z: the reference time of the stored logarithm.
    static let epoch: TimeInterval = 1_767_225_600

    static var rate: Double { log(2) / halfLife }

    /// The stored value after adding a visit of `weight` at `date`.
    public static func adding(_ weight: Double, at date: Date, to stored: Double) -> Double {
        guard weight > 0 else { return stored }
        let visit = log(weight) + rate * (date.timeIntervalSince1970 - epoch)
        let high = max(stored, visit), low = min(stored, visit)
        return high + log1p(exp(low - high))
    }

    /// The decayed visit weight at `now` (1 = one link visit just now).
    public static func current(_ stored: Double, at now: Date) -> Double {
        exp(stored - rate * (now.timeIntervalSince1970 - epoch))
    }
}

/// One history URL as the palette sees it.
public struct HistoryRow: Hashable, Sendable {
    public var id: Int64
    public var profileID: UUID
    public var url: String
    public var title: String?
    /// Lowercased, without "www.".
    public var host: String
    public var visitCount: Int
    public var typedCount: Int
    public var lastVisitAt: Timestamp
    /// The stored frecency logarithm (`Frecency.current` gives its value now).
    public var frecency: Double

    public init(id: Int64, profileID: UUID, url: String, title: String?, host: String, visitCount: Int, typedCount: Int,
                lastVisitAt: Timestamp, frecency: Double) {
        self.id = id
        self.profileID = profileID
        self.url = url
        self.title = title
        self.host = host
        self.visitCount = visitCount
        self.typedCount = typedCount
        self.lastVisitAt = lastVisitAt
        self.frecency = frecency
    }

    init(row: Row) {
        self.init(id: row["id"], profileID: row["profileID"], url: row["url"], title: row["title"], host: row["host"],
                  visitCount: row["visitCount"], typedCount: row["typedCount"], lastVisitAt: row["lastVisitAt"], frecency: row["frecency"])
    }
}

/// A host aggregated over its URLs (inline host completion, spec §C).
public struct HistoryHost: Hashable, Sendable {
    public var host: String
    /// The host's most frecent URL (its scheme is the one to complete to).
    public var bestURL: String
    /// The sum of its URLs' frecencies (stored logarithm).
    public var frecency: Double
    public var visitCount: Int
    public var typedCount: Int
}

/// A row for `History.importRows` (fixtures, the 50k measurement).
public struct HistoryImport: Sendable {
    public var url: String
    public var title: String?
    public var visits: [(at: Date, transition: HistoryTransition)]

    public init(url: String, title: String?, visits: [(at: Date, transition: HistoryTransition)]) {
        self.url = url
        self.title = title
        self.visits = visits
    }
}

/// Reads and writes the history tables. Reads are synchronous (the palette
/// queries on every keystroke; WAL readers never wait for the writer);
/// writes go through the pool's serial writer off the main thread.
public final class History: Sendable {
    private let pool: DatabasePool

    public init(database: RoomDatabase) {
        pool = database.pool
    }

    /// Rows v3 found without any profile to give them to (a database whose
    /// state was never written); no profile ever has this id.
    public static let orphanProfile = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Schemes that are recorded: web pages and files, never `about:`, `data:` or internal pages.
    static let recordedSchemes: Set<String> = ["http", "https", "file"]

    /// The host key: lowercased, without "www." (`nil` for URLs history does not keep).
    public static func hostKey(for url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              recordedSchemes.contains(scheme) else { return nil }
        let host = components.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Writing

    /// A committed main-frame navigation in `profile`'s page (ROADMAP 2.4
    /// task 4). Reloads and URLs history does not keep are ignored.
    /// `completion` runs on an arbitrary queue once the visit is stored (tests wait on it).
    public func recordVisit(url: String, title: String?, transition: HistoryTransition, profile: UUID, at date: Date = Date(),
                            completion: (@Sendable (Result<Void, any Error>) -> Void)? = nil) {
        guard transition.isVisit, Self.hostKey(for: url) != nil else {
            completion?(.success(()))
            return
        }
        pool.asyncWrite({ db in
            try Self.insertVisit(db, url: url, title: title, transition: transition, profile: profile, at: date)
        }, completion: { _, result in completion?(result) })
    }

    /// Returns once every queued write (visits, titles) has finished.
    public func waitForPendingWrites() {
        do { try pool.barrierWriteWithoutTransaction { _ in } } catch { NSLog("Room: history writes not drained: \(error)") }
    }

    /// Synchronous variant (the importer, tests).
    public func recordVisitNow(url: String, title: String?, transition: HistoryTransition, profile: UUID, at date: Date = Date()) throws {
        guard transition.isVisit, Self.hostKey(for: url) != nil else { return }
        try pool.write { db in try Self.insertVisit(db, url: url, title: title, transition: transition, profile: profile, at: date) }
    }

    /// The URL as recorded: without its `#fragment` (one row per page, not per anchor).
    public static func recordedURL(_ url: String) -> String {
        url.firstIndex(of: "#").map { String(url[..<$0]) } ?? url
    }

    private static func insertVisit(_ db: Database, url: String, title: String?, transition: HistoryTransition, profile: UUID,
                                    at date: Date) throws {
        let url = recordedURL(url)
        guard let host = hostKey(for: url) else { return }
        let time = Timestamp(date)
        let typed = transition == .typed ? 1 : 0
        let existing = try Row.fetchOne(db, sql: "SELECT id, frecency FROM history_url WHERE profileID = ? AND url = ?",
                                        arguments: [profile, url])
        let urlID: Int64
        let frecency: Double
        if let existing {
            urlID = existing["id"]
            frecency = Frecency.adding(transition.weight, at: date, to: existing["frecency"])
            try db.execute(sql: """
                UPDATE history_url SET visitCount = visitCount + 1, typedCount = typedCount + ?,
                    lastVisitAt = MAX(lastVisitAt, ?), frecency = ?, title = COALESCE(?, title)
                WHERE id = ?
                """, arguments: [typed, time, frecency, title, urlID])
        } else {
            frecency = Frecency.adding(transition.weight, at: date, to: Frecency.none)
            try db.execute(sql: """
                INSERT INTO history_url (profileID, url, title, visitCount, typedCount, lastVisitAt, host, frecency)
                VALUES (?, ?, ?, 1, ?, ?, ?, ?)
                """, arguments: [profile, url, title, typed, time, host, frecency])
            urlID = db.lastInsertedRowID
        }
        try db.execute(sql: "INSERT INTO history_visit (urlID, visitedAt, transition) VALUES (?, ?, ?)",
                       arguments: [urlID, time, transition.rawValue])
        // The host's aggregate: every visit adds to its frecency; its best URL is the most frecent one.
        if let row = try Row.fetchOne(db, sql: "SELECT bestURL, bestFrecency, frecency FROM history_host WHERE profileID = ? AND host = ?",
                                      arguments: [profile, host]) {
            let bestURL: String = row["bestURL"]
            let bestFrecency: Double = row["bestFrecency"]
            let best = bestURL == url || frecency > bestFrecency ? (url, frecency) : (bestURL, bestFrecency)
            try db.execute(sql: """
                UPDATE history_host SET bestURL = ?, bestFrecency = ?, frecency = ?, visitCount = visitCount + 1,
                    typedCount = typedCount + ? WHERE profileID = ? AND host = ?
                """, arguments: [best.0, best.1, Frecency.adding(transition.weight, at: date, to: row["frecency"]), typed, profile, host])
        } else {
            try db.execute(sql: """
                INSERT INTO history_host (profileID, host, bestURL, bestFrecency, frecency, visitCount, typedCount)
                VALUES (?, ?, ?, ?, ?, 1, ?)
                """, arguments: [profile, host, url, frecency, frecency, typed])
        }
    }

    /// Recomputes a profile's host aggregate from its URLs (after deletions, the v3 backfill).
    static func rebuildHost(_ db: Database, profile: UUID, host: String) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT url, frecency, visitCount, typedCount FROM history_url WHERE profileID = ? AND host = ? ORDER BY frecency DESC
            """, arguments: [profile, host])
        guard let best = rows.first else {
            try db.execute(sql: "DELETE FROM history_host WHERE profileID = ? AND host = ?", arguments: [profile, host])
            return
        }
        // log Σ exp(f): the host's frecency is the sum of its URLs'.
        let top: Double = best["frecency"]
        let sum = top + log(rows.reduce(0.0) { $0 + exp(($1["frecency"] as Double) - top) })
        try db.execute(sql: """
            INSERT OR REPLACE INTO history_host (profileID, host, bestURL, bestFrecency, frecency, visitCount, typedCount)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [profile, host, best["url"] as String, top, sum, rows.reduce(0) { $0 + ($1["visitCount"] as Int) },
                               rows.reduce(0) { $0 + ($1["typedCount"] as Int) }])
    }

    /// The page's title arrived after the commit.
    public func setTitle(_ title: String, for url: String, profile: UUID) {
        let url = Self.recordedURL(url)
        pool.asyncWrite({ db in
            try db.execute(sql: "UPDATE history_url SET title = ? WHERE profileID = ? AND url = ? AND title IS NOT ?",
                           arguments: [title, profile, url, title])
        }, completion: { _, _ in })
    }

    /// Removes a URL and its visits from `profile`'s history (⇧Delete on a history suggestion, spec §C).
    public func delete(url: String, profile: UUID) throws {
        try pool.write { db in
            guard let host = try String.fetchOne(db, sql: "SELECT host FROM history_url WHERE profileID = ? AND url = ?",
                                                 arguments: [profile, url]) else { return }
            try db.execute(sql: "DELETE FROM history_url WHERE profileID = ? AND url = ?", arguments: [profile, url])
            try Self.rebuildHost(db, profile: profile, host: host)
        }
    }

    /// Removes every URL of a host from `profile`'s history (⇧Delete on an
    /// inline host suggestion: it stands for the whole host, so deleting one
    /// URL would bring it straight back).
    public func delete(host: String, profile: UUID) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM history_url WHERE profileID = ? AND host = ?", arguments: [profile, host])
            try db.execute(sql: "DELETE FROM history_host WHERE profileID = ? AND host = ?", arguments: [profile, host])
        }
    }

    /// Bulk insert in one transaction (fixtures and the 50k measurement).
    public func importRows(_ rows: [HistoryImport], profile: UUID) throws {
        try pool.write { db in
            for row in rows {
                for visit in row.visits {
                    try Self.insertVisit(db, url: row.url, title: row.title, transition: visit.transition, profile: profile, at: visit.at)
                }
            }
        }
    }

    // MARK: Reading

    /// URLs in `profile`'s history; every profile's when `nil`.
    public func count(profile: UUID? = nil) throws -> Int {
        try pool.read { db in
            if let profile {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history_url WHERE profileID = ?", arguments: [profile]) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history_url") ?? 0
        }
    }

    public func row(url: String, profile: UUID) throws -> HistoryRow? {
        try pool.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM history_url WHERE profileID = ? AND url = ?", arguments: [profile, url]).map(HistoryRow.init)
        }
    }

    /// Visits recorded for `url` in `profile`, oldest first, as (time, transition).
    public func visits(url: String, profile: UUID) throws -> [(Timestamp, HistoryTransition)] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT v.visitedAt, v.transition FROM history_visit v JOIN history_url u ON u.id = v.urlID
                WHERE u.profileID = ? AND u.url = ? ORDER BY v.visitedAt
                """, arguments: [profile, url]).map { ($0["visitedAt"], HistoryTransition(rawValue: $0["transition"]) ?? .other) }
        }
    }

    /// `profile`'s URLs whose URL or title contains every word of `text` (case-insensitive
    /// substrings, so "ikip" finds Wikipedia), most frecent first.
    ///
    /// Words of three characters or more go through the trigram index; shorter
    /// ones filter its results. Text made only of short words matches host
    /// prefixes ("gi" → github.com). The trigram index answers a rare word
    /// directly; a word in nearly every URL ("com", "http") would make it
    /// return every row only to sort them, so the most frecent rows are
    /// scanned first and the index is consulted only if they hold too few matches.
    public func search(_ text: String, profile: UUID, limit: Int) throws -> [HistoryRow] {
        let terms = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty, limit > 0 else { return [] }
        let indexed = terms.filter { $0.count >= 3 }
        return try pool.read { db in
            guard !indexed.isEmpty else {
                let prefix = terms.joined(separator: " ")
                return try Self.hostPrefixRows(db, prefix: prefix, profile: profile, limit: limit)
            }
            let likes = terms.map { _ in "instr(lower(url || ' ' || COALESCE(title, '')), ?) > 0" }.joined(separator: " AND ")
            // The most frecent rows first: common words are answered here.
            let recent = try Row.fetchAll(db, sql: """
                SELECT * FROM (SELECT * FROM history_url WHERE profileID = ? ORDER BY frecency DESC LIMIT \(Self.frecentScan))
                WHERE \(likes) ORDER BY frecency DESC LIMIT ?
                """, arguments: StatementArguments([profile] + terms + [limit] as [any DatabaseValueConvertible]))
            if recent.count >= limit { return recent.map(HistoryRow.init) }
            let pattern = indexed.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: " AND ")
            let short = terms.filter { $0.count < 3 }
            let shortFilter = short.isEmpty ? "" : " AND " + short.map { _ in "instr(lower(u.url || ' ' || COALESCE(u.title, '')), ?) > 0" }
                .joined(separator: " AND ")
            let rows = try Row.fetchAll(db, sql: """
                SELECT u.* FROM history_fts JOIN history_url u ON u.id = history_fts.rowid
                WHERE history_fts MATCH ? AND u.profileID = ?\(shortFilter) ORDER BY u.frecency DESC LIMIT ?
                """, arguments: StatementArguments([pattern, profile] + short + [limit] as [any DatabaseValueConvertible]))
            return rows.map(HistoryRow.init)
        }
    }

    /// `profile`'s most frecent URLs (⌘Y lists them before anything is typed).
    public func mostFrecent(profile: UUID, limit: Int) throws -> [HistoryRow] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM history_url WHERE profileID = ? ORDER BY frecency DESC LIMIT ?",
                             arguments: [profile, limit]).map(HistoryRow.init)
        }
    }

    /// How many of the most frecent rows `search` scans before the index.
    static let frecentScan = 2_000

    private static func hostPrefixRows(_ db: Database, prefix: String, profile: UUID, limit: Int) throws -> [HistoryRow] {
        guard let upper = prefixUpperBound(prefix) else { return [] }
        // The ids come from the (profileID, host, frecency) index alone; whole
        // rows only for the ones kept. Sorting whole rows read every row of the
        // range from the table (a one-letter prefix is a fifth of the history:
        // 5.8 → 0.5 ms for "g" at 50k rows, 2.6a).
        // A cached statement: one- and two-letter text runs this on every keystroke.
        let statement = try db.cachedStatement(sql: """
            SELECT * FROM history_url WHERE id IN (
                SELECT id FROM history_url WHERE profileID = ? AND host >= ? AND host < ? ORDER BY frecency DESC LIMIT ?
            ) ORDER BY frecency DESC
            """)
        return try Row.fetchAll(statement, arguments: [profile, prefix, upper, limit]).map(HistoryRow.init)
    }

    /// Hosts that start with `prefix` (lowercased, without "www."), most
    /// frecent first, each with its best URL (inline completion, spec §C).
    public func hosts(prefix: String, profile: UUID, limit: Int) throws -> [HistoryHost] {
        let prefix = prefix.lowercased()
        guard !prefix.isEmpty, let upper = Self.prefixUpperBound(prefix) else { return [] }
        return try pool.read { db in
            // Inline completion asks on every keystroke: a cached statement.
            try Row.fetchAll(db.cachedStatement(sql: """
                SELECT * FROM history_host WHERE profileID = ? AND host >= ? AND host < ? ORDER BY frecency DESC LIMIT ?
                """), arguments: [profile, prefix, upper, limit]).map {
                HistoryHost(host: $0["host"], bestURL: $0["bestURL"], frecency: $0["frecency"], visitCount: $0["visitCount"],
                            typedCount: $0["typedCount"])
            }
        }
    }

    /// The smallest string greater than every string with `prefix` (range scans on the host index).
    static func prefixUpperBound(_ prefix: String) -> String? {
        // UTF-8 byte order (SQLite's BINARY collation) is code point order.
        guard let last = prefix.unicodeScalars.last, let next = Unicode.Scalar(last.value + 1) else { return nil }
        var scalars = String.UnicodeScalarView(prefix.unicodeScalars.dropLast())
        scalars.append(next)
        return String(scalars)
    }
}
