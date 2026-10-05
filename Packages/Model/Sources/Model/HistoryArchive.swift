import Foundation
import GRDB

/// `history-archive.json` beside `Room.sqlite`: what schema v6 drops with the
/// Chapter 2 history tables and the engine's history does not hold (B-66).
///
/// Phase 3.5 imported each profile's local history into Chromium's
/// `HistoryService` once (the profile's id in `Settings.historyImportedProfiles`);
/// Chromium keeps 90 days, so visits older than 89 days at the import were
/// left out. v6 writes, per profile:
/// - an imported profile: every URL with a visit older than
///   `engineRetentionDays` before the migration, with those visits;
/// - a profile never imported: every URL with every visit, so the first
///   launch on an engine with history can still import them from here
///   (`HistoryArchive.Profile.imported == false`).
///
/// The file is written only when the tables held any row. JSON, readable by a
/// person and by a later archive view (B-66: the user decides on one).
public enum HistoryArchive {
    public static let fileName = "history-archive.json"
    /// Chromium's history keeps 90 days; the 3.5 import left out what was older than 89.
    public static let engineRetentionDays = 89

    public struct File: Codable, Sendable, Equatable {
        public var format = 1
        public var writtenAt: Date
        public var note: String
        public var engineRetentionDays: Int
        public var profiles: [Profile]

        public init(writtenAt: Date, note: String, engineRetentionDays: Int, profiles: [Profile]) {
            self.writtenAt = writtenAt
            self.note = note
            self.engineRetentionDays = engineRetentionDays
            self.profiles = profiles
        }
    }

    public struct Profile: Codable, Sendable, Equatable {
        public var profileID: UUID
        /// Whether 3.5's import ran for this profile (its URLs then carry only the visits it left out).
        public var imported: Bool
        /// For an imported profile: the visits kept here are older than this.
        public var cutoff: Date?
        /// URLs in the dropped table for this profile, archived or not.
        public var tableURLs: Int
        public var urls: [URLRow]

        public init(profileID: UUID, imported: Bool, cutoff: Date?, tableURLs: Int, urls: [URLRow]) {
            self.profileID = profileID
            self.imported = imported
            self.cutoff = cutoff
            self.tableURLs = tableURLs
            self.urls = urls
        }
    }

    public struct URLRow: Codable, Sendable, Equatable {
        public var url: String
        public var title: String?
        /// The row's own counts over all its visits (the table's columns).
        public var visitCount: Int
        public var typedCount: Int
        public var lastVisit: Date
        /// The visits this archive holds (for an imported profile, the old ones only).
        public var visits: [Visit]

        public init(url: String, title: String?, visitCount: Int, typedCount: Int, lastVisit: Date, visits: [Visit]) {
            self.url = url
            self.title = title
            self.visitCount = visitCount
            self.typedCount = typedCount
            self.lastVisit = lastVisit
            self.visits = visits
        }
    }

    public struct Visit: Codable, Sendable, Equatable {
        public var time: Date
        /// `typed`, `link`, `bookmark`, `generated`, `keyword`, `formSubmit`, `other`.
        public var transition: String

        public init(time: Date, transition: String) {
            self.time = time
            self.transition = transition
        }
    }

    public enum ArchiveError: Error {
        /// History rows exist but the database has no file to write beside (an in-memory database).
        case noDatabaseFile
    }

    /// The archive's place beside the database file.
    public static func url(besideDatabaseAt databasePath: String) -> URL {
        URL(fileURLWithPath: databasePath).deletingLastPathComponent().appending(path: fileName)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Reads an archive (`nil` when there is none or it does not decode).
    public static func read(from url: URL) -> File? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(File.self, from: data)
    }

    /// What v6 archives from the v5 history tables of `db` (nil when the tables hold no row).
    static func make(_ db: Database, now: Date) throws -> File? {
        guard try db.tableExists("history_url"), try Int.fetchOne(db, sql: "SELECT count(*) FROM history_url") ?? 0 > 0 else { return nil }
        var imported = Set<UUID>()
        if let json = try String.fetchOne(db, sql: "SELECT value FROM kv WHERE key = ?", arguments: [KVKey.settings]),
           let settings = try? JSONDecoder().decode(Settings.self, from: Data(json.utf8)) {
            imported = Set(settings.historyImportedProfiles)
        }
        let cutoff = now.addingTimeInterval(-Double(engineRetentionDays) * 86_400)
        let cutoffTime = Timestamp(cutoff)
        var profiles: [Profile] = []
        for profileValue in try DatabaseValue.fetchAll(db, sql: "SELECT DISTINCT profileID FROM history_url ORDER BY profileID") {
            guard let profileID = UUID.fromDatabaseValue(profileValue) else { continue }
            let wasImported = imported.contains(profileID)
            let tableURLs = try Int.fetchOne(db, sql: "SELECT count(*) FROM history_url WHERE profileID = ?", arguments: [profileValue]) ?? 0
            // An imported profile: only the URLs with a visit before the cutoff, with those visits.
            let visitFilter = wasImported ? "AND v.visitedAt < ?" : ""
            var arguments: StatementArguments = [profileValue]
            if wasImported { arguments += [cutoffTime] }
            let visitRows = try Row.fetchAll(db, sql: """
                SELECT u.id, u.url, u.title, u.visitCount, u.typedCount, u.lastVisitAt, v.visitedAt, v.transition
                FROM history_url u JOIN history_visit v ON v.urlID = u.id
                WHERE u.profileID = ? \(visitFilter)
                ORDER BY u.id, v.visitedAt
                """, arguments: arguments)
            var urls: [URLRow] = []
            var currentID: Int64?
            for row in visitRows {
                let id: Int64 = row["id"]
                let visit = Visit(time: (row["visitedAt"] as Timestamp).date, transition: row["transition"])
                if id == currentID {
                    urls[urls.count - 1].visits.append(visit)
                } else {
                    currentID = id
                    urls.append(URLRow(url: row["url"], title: row["title"], visitCount: row["visitCount"], typedCount: row["typedCount"],
                                       lastVisit: (row["lastVisitAt"] as Timestamp).date, visits: [visit]))
                }
            }
            if !wasImported {
                // A never-imported URL without a visit row still belongs to the history (its counts say so).
                let withoutVisits = try Row.fetchAll(db, sql: """
                    SELECT url, title, visitCount, typedCount, lastVisitAt FROM history_url u
                    WHERE u.profileID = ? AND NOT EXISTS (SELECT 1 FROM history_visit v WHERE v.urlID = u.id) ORDER BY u.id
                    """, arguments: [profileValue])
                urls += withoutVisits.map {
                    URLRow(url: $0["url"], title: $0["title"], visitCount: $0["visitCount"], typedCount: $0["typedCount"],
                           lastVisit: ($0["lastVisitAt"] as Timestamp).date, visits: [])
                }
            }
            profiles.append(Profile(profileID: profileID, imported: wasImported, cutoff: wasImported ? cutoff : nil,
                                    tableURLs: tableURLs, urls: urls))
        }
        let note = "Room's Chapter 2 history tables were dropped by schema v6 (Phase 3.9). Profiles whose history 3.5 imported "
            + "into the engine keep here only the visits older than \(engineRetentionDays) days, which the engine does not keep (B-66); "
            + "profiles never imported keep every URL, and Room imports them into the engine's history at the next launch."
        return File(writtenAt: now, note: note, engineRetentionDays: engineRetentionDays, profiles: profiles)
    }

    /// v6's step before the drop: writes the archive beside the database file
    /// (atomically; an error fails the migration, so the tables stay).
    /// Returns the file's URL, or nil when there was nothing to archive.
    @discardableResult
    static func write(_ db: Database, now: Date = Date()) throws -> URL? {
        guard let file = try make(db, now: now) else { return nil }
        let path = try String.fetchOne(db, sql: "SELECT file FROM pragma_database_list WHERE name = 'main'") ?? ""
        guard !path.isEmpty else { throw ArchiveError.noDatabaseFile }
        let url = url(besideDatabaseAt: path)
        try encoder.encode(file).write(to: url, options: .atomic)
        let archived = file.profiles.reduce(0) { $0 + $1.urls.count }
        let visits = file.profiles.reduce(0) { $0 + $1.urls.reduce(0) { $0 + $1.visits.count } }
        NSLog("Room: schema v6: %ld URLs (%ld visits) of %ld archived to %@", archived, visits,
              file.profiles.reduce(0) { $0 + $1.tableURLs }, url.path)
        return url
    }
}
