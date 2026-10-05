import Foundation
import GRDB

// The Chapter 2 history code the shipped migrations v2 and v3 call, frozen
// here when v6 dropped the tables and the `History` reader/writer (Phase 3.9).
// A database at v1–v5 still runs v2–v5 before v6 archives and drops the
// tables, so these must keep computing exactly what they did; never change
// them, and never use them outside `Schema`.

/// How a recorded navigation started (v1–v5's `history_visit.transition`).
enum HistoryTransition: String, Hashable, Sendable, CaseIterable {
    case typed, link, bookmark, generated, keyword, formSubmit, reload, other

    /// Frecency weight of one visit (a link is 1).
    var weight: Double {
        switch self {
        case .typed: 2
        case .bookmark: 1.5
        case .link, .other: 1
        case .generated, .keyword, .formSubmit: 0.3
        case .reload: 0
        }
    }
}

/// The decayed-visit logarithm v2 backfilled into `history_url.frecency`.
enum Frecency {
    static let halfLife: TimeInterval = 30 * 86_400
    static let none = -1_000.0
    /// 2026-01-01T00:00:00Z.
    static let epoch: TimeInterval = 1_767_225_600

    static var rate: Double { log(2) / halfLife }

    static func adding(_ weight: Double, at date: Date, to stored: Double) -> Double {
        guard weight > 0 else { return stored }
        let visit = log(weight) + rate * (date.timeIntervalSince1970 - epoch)
        let high = max(stored, visit), low = min(stored, visit)
        return high + log1p(exp(low - high))
    }
}

enum LegacyHistory {
    /// v3's owner for rows found without any profile.
    static let orphanProfile = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static let recordedSchemes: Set<String> = ["http", "https", "file"]

    /// The host key: lowercased, without "www." (`nil` for URLs history did not keep).
    static func hostKey(for url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(),
              recordedSchemes.contains(scheme) else { return nil }
        let host = components.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// v3's per-profile host aggregate from its URLs.
    static func rebuildHost(_ db: Database, profile: DatabaseValue, host: String) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT url, frecency, visitCount, typedCount FROM history_url WHERE profileID = ? AND host = ? ORDER BY frecency DESC
            """, arguments: [profile, host])
        guard let best = rows.first else {
            try db.execute(sql: "DELETE FROM history_host WHERE profileID = ? AND host = ?", arguments: [profile, host])
            return
        }
        let top: Double = best["frecency"]
        let sum = top + log(rows.reduce(0.0) { $0 + exp(($1["frecency"] as Double) - top) })
        try db.execute(sql: """
            INSERT OR REPLACE INTO history_host (profileID, host, bestURL, bestFrecency, frecency, visitCount, typedCount)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [profile, host, best["url"] as String, top, sum, rows.reduce(0) { $0 + ($1["visitCount"] as Int) },
                               rows.reduce(0) { $0 + ($1["typedCount"] as Int) }])
    }
}
