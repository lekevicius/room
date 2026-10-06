import Foundation
import GRDB

/// Firefox's `places.sqlite` (4.3b), read through `SQLiteCopy` like Chrome's
/// `History`; the schema Chromium's `chrome/utility/importer/firefox_importer.cc`
/// reads: `moz_places` (id, url, title, visit_count, hidden, typed,
/// last_visit_date), `moz_historyvisits` (place_id, visit_date, visit_type)
/// and `moz_bookmarks` (id, type 1 = link, 2 = folder, 3 = separator; fk →
/// moz_places.id, parent, position, title, dateAdded). Times are
/// microseconds since 1970.
public enum FirefoxPlacesReader {
    /// The roots under `root________`, by `guid` (Firefox 4 and later) or,
    /// in older files without `guid`, by title.
    enum Root: String, CaseIterable {
        case toolbar = "toolbar_____"
        case menu = "menu________"
        case unfiled = "unfiled_____"
        case mobile = "mobile______"

        var legacyTitle: String {
            switch self {
            case .toolbar: "toolbar"
            case .menu: "menu"
            case .unfiled: "unfiled"
            case .mobile: "mobile"
            }
        }
    }

    /// Bookmarks: the toolbar is the bar; the menu's and "Other Bookmarks"
    /// (`unfiled`) children are "other"; mobile is mobile. A link's title is
    /// its own or, when empty, its page's. Separators are left out silently;
    /// a link without a page row and a folder met twice are skipped with a reason.
    public static func bookmarks(at url: URL) throws(ImportError) -> ImportedBookmarks {
        try SQLiteCopy.read(url, format: .firefoxPlaces) { db in
            guard try db.tableExists("moz_bookmarks"), try db.tableExists("moz_places") else {
                throw ImportError(.malformed, .firefoxPlaces, "no moz_bookmarks or moz_places table")
            }
            let hasGUID = try db.columns(in: "moz_bookmarks").contains { $0.name == "guid" }
            struct Item {
                var id: Int64
                var type: Int64
                var title: String
                var url: String?
                var dateAdded: Date?
                var guid: String?
            }
            var children: [Int64: [Item]] = [:]
            var roots: [Root: Int64] = [:]
            var rootID: Int64?
            let rows = try Row.fetchCursor(db, sql: """
                SELECT b.id, b.type, b.parent, b.position, COALESCE(NULLIF(b.title, ''), h.title, '') AS title, h.url, b.dateAdded, \
                \(hasGUID ? "b.guid" : "NULL") AS guid
                FROM moz_bookmarks b LEFT JOIN moz_places h ON b.fk = h.id
                ORDER BY b.parent, b.position
                """)
            var items: [Int64: (parent: Int64, item: Item)] = [:]
            while let row = try rows.next() {
                let item = Item(id: row["id"], type: row["type"] ?? 0, title: row["title"] ?? "", url: row["url"],
                                dateAdded: (row["dateAdded"] as Int64?).flatMap(ImportTime.unixMicroseconds), guid: row["guid"])
                let parent: Int64 = row["parent"] ?? 0
                items[item.id] = (parent, item)
                if item.guid == "root________" || (!hasGUID && parent == 0 && item.type == 2) { rootID = item.id }
                if let guid = item.guid, let root = Root(rawValue: guid) { roots[root] = item.id }
                children[parent, default: []].append(item)
            }
            // Files without guids: the roots are the root folder's children named as Firefox named them.
            if roots.isEmpty, let rootID {
                for item in children[rootID] ?? [] {
                    if let root = Root.allCases.first(where: { $0.legacyTitle == item.title.lowercased() }) { roots[root] = item.id }
                }
            }
            guard !roots.isEmpty else { throw ImportError(.malformed, .firefoxPlaces, "no bookmark roots") }
            var result = ImportedBookmarks()
            var seen: Set<Int64> = []
            func nodes(of folder: Int64, depth: Int) -> [ImportedNode] {
                guard seen.insert(folder).inserted, depth < 64 else {
                    result.skipped.append(SkippedItem(items[folder]?.item.title ?? "folder \(folder)", reason: "a folder inside itself"))
                    return []
                }
                return (children[folder] ?? []).compactMap { item -> ImportedNode? in
                    switch item.type {
                    case 1:
                        guard let url = item.url, !url.isEmpty else {
                            result.skipped.append(SkippedItem(item.title.isEmpty ? "bookmark \(item.id)" : item.title, reason: "no URL"))
                            return nil
                        }
                        return .link(ImportedLink(url: url, title: item.title, dateAdded: item.dateAdded, guid: item.guid))
                    case 2:
                        return .folder(ImportedFolder(title: item.title, children: nodes(of: item.id, depth: depth + 1),
                                                      dateAdded: item.dateAdded, guid: item.guid))
                    default:
                        return nil  // a separator
                    }
                }
            }
            if let toolbar = roots[.toolbar] { result.bar = nodes(of: toolbar, depth: 0) }
            for root in [Root.menu, .unfiled] { if let id = roots[root] { result.other += nodes(of: id, depth: 0) } }
            if let mobile = roots[.mobile] { result.mobile = nodes(of: mobile, depth: 0) }
            return result
        }
    }

    /// History: pages not hidden, with their visits of types link (1), typed
    /// (2) and bookmark (3), as Chromium's Firefox importer keeps them
    /// (embeds, redirects, downloads, framed links and reloads are not
    /// visits). A page left without such a visit is skipped with a reason.
    public static func history(at url: URL) throws(ImportError) -> ImportedHistory {
        try SQLiteCopy.read(url, format: .firefoxPlaces) { db in
            guard try db.tableExists("moz_places"), try db.tableExists("moz_historyvisits") else {
                throw ImportError(.malformed, .firefoxPlaces, "no moz_places or moz_historyvisits table")
            }
            var visitsByPlace: [Int64: [ImportedVisit]] = [:]
            let visits = try Row.fetchCursor(db, sql: "SELECT place_id, visit_date, visit_type FROM moz_historyvisits ORDER BY visit_date")
            while let row = try visits.next() {
                let transition: ImportedTransition? = switch row["visit_type"] as Int64? ?? 0 {
                case 1: .link
                case 2: .typed
                case 3: .bookmark
                default: nil
                }
                guard let transition, let time = (row["visit_date"] as Int64?).flatMap(ImportTime.unixMicroseconds) else { continue }
                visitsByPlace[row["place_id"] as Int64? ?? 0, default: []].append(ImportedVisit(time: time, transition: transition))
            }
            var result = ImportedHistory()
            let places = try Row.fetchCursor(db, sql: "SELECT id, url, title, visit_count, hidden, typed, last_visit_date FROM moz_places ORDER BY id")
            while let row = try places.next() {
                let address: String = row["url"] ?? ""
                guard !address.isEmpty else { continue }
                let visits = visitsByPlace[row["id"] as Int64? ?? 0] ?? []
                if (row["hidden"] as Int64? ?? 0) != 0 {
                    // Bookmarked pages never visited are hidden too; only visited ones are worth a line.
                    if !visits.isEmpty { result.skipped.append(SkippedItem(address, reason: "hidden (a subframe or redirect)")) }
                    continue
                }
                guard let last = visits.last else {
                    if (row["visit_count"] as Int64? ?? 0) > 0 { result.skipped.append(SkippedItem(address, reason: "no link, typed or bookmark visit")) }
                    continue
                }
                result.urls.append(ImportedHistoryURL(url: address, title: row["title"] ?? "", visitCount: visits.count,
                                                      typedCount: visits.count { $0.transition == .typed },
                                                      lastVisit: (row["last_visit_date"] as Int64?).flatMap(ImportTime.unixMicroseconds) ?? last.time,
                                                      visits: visits))
            }
            return result
        }
    }
}
