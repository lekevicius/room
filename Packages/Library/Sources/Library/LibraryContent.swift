import Foundation
import Model

/// The Library's three sections (spec §H; ROADMAP 4.1a): collapsible, in this order.
public enum LibrarySection: String, CaseIterable, Sendable {
    case archive, downloads, history

    public var title: String {
        switch self {
        case .archive: "Archive"
        case .downloads: "Downloads"
        case .history: "History"
        }
    }
}

/// One History row: from the engine's history, or (`isArchived`) from
/// `history-archive.json`, the Chapter 2 visits the engine does not hold (B-66).
public struct LibraryHistoryItem: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var lastVisit: Date?
    public var isArchived: Bool

    public init(url: URL, title: String, lastVisit: Date?, isArchived: Bool = false) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.isArchived = isArchived
    }

    public var host: String {
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// One Downloads row (the host's list, `DownloadList`).
public struct LibraryDownload: Hashable, Sendable {
    public var id: String
    public var name: String
    public var url: URL
    public var detail: String
    public var isFinished: Bool

    public init(id: String, name: String, url: URL, detail: String, isFinished: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.detail = detail
        self.isFinished = isFinished
    }
}

/// What the Library's table shows, row by row.
public enum LibraryRow: Hashable, Sendable {
    case header(LibrarySection, count: Int, collapsed: Bool)
    case day(LibrarySection, Date)
    case archived(ArchivedEntry)
    case download(LibraryDownload)
    case history(LibraryHistoryItem)
    case empty(LibrarySection, String)
}

/// The rows from the data, as pure functions (tested; the controller only draws them).
public enum LibraryContent {
    /// Every row in order: each section's header with its count, then (unless
    /// collapsed) its rows: the Archive by day; Downloads newest first;
    /// History by day without a query, or the query's matches (the engine's,
    /// then the archived file's, marked) with one.
    public static func rows(collapsed: Set<LibrarySection>, archive: [ArchivedEntry], downloads: [LibraryDownload],
                            history: [LibraryHistoryItem], query: String, calendar: Calendar = .current) -> [LibraryRow] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        var rows: [LibraryRow] = []
        // Archive
        let archived = ArchiveSearch.matching(archive, text: query)
        rows.append(.header(.archive, count: archived.count, collapsed: collapsed.contains(.archive)))
        if !collapsed.contains(.archive) {
            if archived.isEmpty {
                rows.append(.empty(.archive, searching ? "No archived tabs match" : "Tabs you archive, clear or leave unused show here"))
            }
            for group in ArchiveSearch.byDay(archived, calendar: calendar) {
                rows.append(.day(.archive, group.day))
                rows += group.rows.map(LibraryRow.archived)
            }
        }
        // Downloads
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let shownDownloads = downloads.filter { download in
            words.allSatisfy { "\(download.name) \(download.url.absoluteString)".range(of: $0, options: [.caseInsensitive]) != nil }
        }
        rows.append(.header(.downloads, count: shownDownloads.count, collapsed: collapsed.contains(.downloads)))
        if !collapsed.contains(.downloads) {
            if shownDownloads.isEmpty { rows.append(.empty(.downloads, searching ? "No downloads match" : "No downloads")) }
            rows += shownDownloads.map(LibraryRow.download)
        }
        // History
        rows.append(.header(.history, count: history.count, collapsed: collapsed.contains(.history)))
        if !collapsed.contains(.history) {
            if history.isEmpty { rows.append(.empty(.history, searching ? "No history matches" : "No history this week")) }
            if searching {
                rows += history.map(LibraryRow.history)
            } else {
                var lastDay: Date?
                for item in history {
                    let day = calendar.startOfDay(for: item.lastVisit ?? .distantPast)
                    if day != lastDay {
                        rows.append(.day(.history, day))
                        lastDay = day
                    }
                    rows.append(.history(item))
                }
            }
        }
        return rows
    }

    /// `history-archive.json`'s URLs of `profile` (every profile's when nil)
    /// whose title or URL contain every word of `query`, most recent first,
    /// marked archived (B-66: read by the Library's search and nowhere else);
    /// URLs the engine already returned are left out.
    public static func archivedHistory(_ file: HistoryArchive.File?, profile: UUID?, query: String, excluding: Set<URL>,
                                       limit: Int) -> [LibraryHistoryItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let file, !words.isEmpty else { return [] }
        var result: [LibraryHistoryItem] = []
        for entry in file.profiles where profile == nil || entry.profileID == profile {
            for row in entry.urls {
                let haystack = "\(row.title ?? "") \(row.url)"
                guard words.allSatisfy({ haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }),
                      let url = URL(string: row.url), !excluding.contains(url) else { continue }
                result.append(LibraryHistoryItem(url: url, title: row.title ?? row.url, lastVisit: row.lastVisit, isArchived: true))
            }
        }
        result.sort { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
        return Array(result.prefix(limit))
    }

    /// Per-kind counts of the rows (the spike's and the tour's line).
    public static func summary(_ rows: [LibraryRow]) -> String {
        var archived = 0, downloads = 0, history = 0, historyArchived = 0, days = 0
        var reasons: [ArchiveReason: Int] = [:]
        for row in rows {
            switch row {
            case .archived(let entry):
                archived += 1
                reasons[entry.reason, default: 0] += 1
            case .download: downloads += 1
            case .history(let item):
                history += 1
                if item.isArchived { historyArchived += 1 }
            case .day: days += 1
            case .header, .empty: break
            }
        }
        let byReason = ArchiveReason.allCases.map { "\($0.rawValue)=\(reasons[$0] ?? 0)" }.joined(separator: " ")
        return "archive=\(archived) (\(byReason)) downloads=\(downloads) history=\(history) history_archived=\(historyArchived) days=\(days)"
    }
}
