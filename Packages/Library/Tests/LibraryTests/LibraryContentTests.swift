import Foundation
import Model
import Testing
@testable import Library

@Suite("Library rows (spec §H)")
struct LibraryContentTests {
    let space = UUID(), profile = UUID()
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func archived(_ title: String, day: Int64, reason: ArchiveReason = .auto) -> ArchivedEntry {
        ArchivedEntry(url: "https://\(title.lowercased()).example/", title: title, spaceID: space, profileID: profile,
                      archivedAt: Timestamp(milliseconds: day * 86_400_000 + 3_600_000), reason: reason)
    }

    @Test("Each section has a header with its count; the Archive groups by day; a collapsed section shows only its header")
    func sections() {
        let rows = LibraryContent.rows(collapsed: [.downloads], archive: [archived("A", day: 10), archived("B", day: 11)],
                                       downloads: [LibraryDownload(id: "1", name: "f.zip", url: URL(string: "https://d.example/f.zip")!,
                                                                   detail: "1 MB", isFinished: true)],
                                       history: [], query: "", calendar: utc)
        guard case .header(.archive, 2, false) = rows[0], case .day = rows[1], case .archived(let first) = rows[2],
              case .day = rows[3], case .archived = rows[4], case .header(.downloads, 1, true) = rows[5],
              case .header(.history, 0, false) = rows[6], case .empty(.history, _) = rows[7] else {
            Issue.record("unexpected rows: \(rows)")
            return
        }
        #expect(first.title == "B", "newest day first")
        #expect(rows.count == 8)
    }

    @Test("A query filters the Archive and Downloads and lists History's matches without day rows, archived ones marked (B-66)")
    func search() {
        let file = HistoryArchive.File(writtenAt: Date(), note: "", engineRetentionDays: 89, profiles: [
            HistoryArchive.Profile(profileID: profile, imported: true, cutoff: nil, tableURLs: 2, urls: [
                HistoryArchive.URLRow(url: "https://old.example/recipes", title: "Old recipes", visitCount: 3, typedCount: 0,
                                      lastVisit: Date(timeIntervalSince1970: 1_000), visits: []),
                HistoryArchive.URLRow(url: "https://new.example/recipes", title: "Recipes", visitCount: 1, typedCount: 0,
                                      lastVisit: Date(timeIntervalSince1970: 2_000), visits: []),
            ]),
            HistoryArchive.Profile(profileID: UUID(), imported: true, cutoff: nil, tableURLs: 1, urls: [
                HistoryArchive.URLRow(url: "https://other.example/recipes", title: "Other profile", visitCount: 1, typedCount: 0,
                                      lastVisit: Date(timeIntervalSince1970: 3_000), visits: []),
            ]),
        ])
        let engine = LibraryHistoryItem(url: URL(string: "https://new.example/recipes")!, title: "Recipes", lastVisit: Date())
        let fromFile = LibraryContent.archivedHistory(file, profile: profile, query: "recipes", excluding: [engine.url], limit: 10)
        #expect(fromFile.map(\.url.absoluteString) == ["https://old.example/recipes"], "the engine's URL and the other profile's are left out")
        #expect(fromFile.allSatisfy { $0.isArchived })
        #expect(LibraryContent.archivedHistory(file, profile: profile, query: "", excluding: [], limit: 10).isEmpty,
                "the file is read for searches only")
        let rows = LibraryContent.rows(collapsed: [], archive: [archived("Recipes", day: 3), archived("Other", day: 3)], downloads: [],
                                       history: [engine] + fromFile, query: "recipes", calendar: utc)
        let summary = LibraryContent.summary(rows)
        #expect(summary.contains("archive=1 ") && summary.contains("history=2 history_archived=1"))
        #expect(!rows.contains { if case .day(.history, _) = $0 { true } else { false } })
    }
}
