import Foundation
import GRDB

/// Another browser's SQLite database, read safely: the file (with its
/// `-wal`, `-shm` or `-journal` when present) is copied into a temporary
/// directory first and the copy is opened read-only with GRDB; the original
/// is never opened (Chrome locks its live database). A copy whose journal
/// needs a rollback cannot be opened read-only; it is opened read-write
/// instead, which rolls the copy back to its last commit. The copy is
/// removed when the read ends.
enum SQLiteCopy {
    static func read<T>(_ url: URL, format: ImportFormat, _ body: (Database) throws -> T) throws(ImportError) -> T {
        let fileManager = FileManager.default
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw fileManager.fileExists(atPath: url.path) ? ImportError(.permissionDenied, format, url.lastPathComponent)
                : ImportError(.unreadable, format, "no file at \(url.path)")
        }
        let directory = fileManager.temporaryDirectory.appending(path: "room-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: directory) }
        let copy = directory.appending(path: url.lastPathComponent)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: copy)
            for suffix in ["-wal", "-shm", "-journal"] {
                let side = URL(fileURLWithPath: url.path + suffix)
                if fileManager.fileExists(atPath: side.path) {
                    try fileManager.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
        } catch {
            throw ImportError(.unreadable, format, "the copy failed (\(error.localizedDescription))")
        }
        func open(readonly: Bool) throws -> DatabaseQueue {
            var configuration = Configuration()
            configuration.readonly = readonly
            configuration.label = "room.import"
            return try DatabaseQueue(path: copy.path, configuration: configuration)
        }
        do {
            var queue: DatabaseQueue
            do {
                let readonly = try open(readonly: true)
                // Opening is lazy about the header: a query proves the file is a database.
                _ = try readonly.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sqlite_master") }
                queue = readonly
            } catch {
                queue = try open(readonly: false)
            }
            return try queue.read(body)
        } catch let error as ImportError {
            throw error
        } catch let error as DatabaseError {
            throw ImportError(.malformed, format, error.message ?? "\(error.resultCode)")
        } catch {
            throw ImportError(.malformed, format, "\(error)")
        }
    }
}

/// Chrome's `History` (Chrome, Brave, Edge, Vivaldi, Arc; the schema of
/// `components/history/core/browser/url_database.cc` and `visit_database.cc`):
/// `urls` (url, title, visit_count, typed_count, last_visit_time, hidden) and
/// `visits` (url → urls.id, visit_time, transition), times in WebKit
/// microseconds. Hidden rows (subframes) and subframe visits are skipped;
/// a URL left without visits keeps its row's last visit as its one visit.
public enum ChromeHistoryReader {
    public static func read(at url: URL) throws(ImportError) -> ImportedHistory {
        try SQLiteCopy.read(url, format: .chromeHistory) { db in
            guard try db.tableExists("urls"), try db.tableExists("visits") else {
                throw ImportError(.malformed, .chromeHistory, "no urls or visits table")
            }
            var visitsByURL: [Int64: [ImportedVisit]] = [:]
            let visits = try Row.fetchCursor(db, sql: "SELECT url, visit_time, transition FROM visits ORDER BY visit_time")
            while let row = try visits.next() {
                guard let time = ImportTime.webKit(row["visit_time"] as Int64? ?? 0),
                      let transition = transition(row["transition"] as Int64? ?? 0) else { continue }
                visitsByURL[row["url"] as Int64? ?? 0, default: []].append(ImportedVisit(time: time, transition: transition))
            }
            var result = ImportedHistory()
            let urls = try Row.fetchCursor(db, sql: "SELECT id, url, title, visit_count, typed_count, last_visit_time, hidden FROM urls ORDER BY id")
            while let row = try urls.next() {
                let address: String = row["url"] ?? ""
                guard !address.isEmpty else { continue }
                if (row["hidden"] as Int64? ?? 0) != 0 {
                    result.skipped.append(SkippedItem(address, reason: "hidden (a subframe)"))
                    continue
                }
                let last = ImportTime.webKit(row["last_visit_time"] as Int64? ?? 0)
                var visits = visitsByURL[row["id"] as Int64? ?? 0] ?? []
                if visits.isEmpty, let last { visits = [ImportedVisit(time: last, transition: .link)] }
                guard !visits.isEmpty else {
                    result.skipped.append(SkippedItem(address, reason: "no visits"))
                    continue
                }
                result.urls.append(ImportedHistoryURL(url: address, title: row["title"] ?? "", visitCount: Int(row["visit_count"] as Int64? ?? 0),
                                                      typedCount: Int(row["typed_count"] as Int64? ?? 0), lastVisit: last ?? visits.last?.time,
                                                      visits: visits))
            }
            return result
        }
    }

    /// The core of a `ui::PageTransition` (its low byte); `nil` for subframe navigations.
    static func transition(_ value: Int64) -> ImportedTransition? {
        switch value & 0xFF {
        case 0: .link
        case 1: .typed
        case 2: .bookmark
        case 3, 4: nil
        case 5: .generated
        case 7: .formSubmit
        case 8: .reload
        case 9, 10: .keyword
        default: .other
        }
    }
}

/// Safari's `History.db`: `history_items` (url, visit_count) and
/// `history_visits` (history_item → id, visit_time in seconds since
/// 2001-01-01, title, load_successful). Failed loads are not visits; an
/// item without a successful visit is skipped. The title is the latest
/// visit's that has one; Safari keeps no typed count.
public enum SafariHistoryReader {
    public static func read(at url: URL) throws(ImportError) -> ImportedHistory {
        try SQLiteCopy.read(url, format: .safariHistory) { db in
            guard try db.tableExists("history_items"), try db.tableExists("history_visits") else {
                throw ImportError(.malformed, .safariHistory, "no history_items or history_visits table")
            }
            var visitsByItem: [Int64: [(visit: ImportedVisit, title: String?)]] = [:]
            let visits = try Row.fetchCursor(db, sql: "SELECT history_item, visit_time, title, load_successful FROM history_visits ORDER BY visit_time")
            while let row = try visits.next() {
                guard (row["load_successful"] as Int64? ?? 1) != 0 else { continue }
                let time = ImportTime.safari(row["visit_time"] as Double? ?? 0)
                visitsByItem[row["history_item"] as Int64? ?? 0, default: []].append((ImportedVisit(time: time, transition: .link), row["title"]))
            }
            var result = ImportedHistory()
            let items = try Row.fetchCursor(db, sql: "SELECT id, url, visit_count FROM history_items ORDER BY id")
            while let row = try items.next() {
                let address: String = row["url"] ?? ""
                guard !address.isEmpty else { continue }
                let visits = visitsByItem[row["id"] as Int64? ?? 0] ?? []
                guard let last = visits.last else {
                    result.skipped.append(SkippedItem(address, reason: "no successful visit"))
                    continue
                }
                let title = visits.reversed().lazy.compactMap { $0.title.flatMap { $0.isEmpty ? nil : $0 } }.first ?? ""
                result.urls.append(ImportedHistoryURL(url: address, title: title, visitCount: Int(row["visit_count"] as Int64? ?? 0),
                                                      typedCount: 0, lastVisit: last.visit.time, visits: visits.map(\.visit)))
            }
            return result
        }
    }
}
