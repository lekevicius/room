import Engine
import FakeEngine
import Foundation
import Model
import Testing
@testable import Tabs

/// Writes `rows` as `profile`'s never-imported section of the store's history archive (what schema v6 leaves).
private func writeArchive(_ f: TabsFixture, profile: UUID, imported: Bool = false, _ rows: [HistoryArchive.URLRow]) throws {
    let file = HistoryArchive.File(writtenAt: Date(), note: "test", engineRetentionDays: HistoryArchive.engineRetentionDays,
                                   profiles: [HistoryArchive.Profile(profileID: profile, imported: imported, cutoff: nil,
                                                                     tableURLs: rows.count, urls: rows)])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(file).write(to: f.store.historyArchiveURL)
}

private func row(_ url: String, _ title: String, _ visits: [(Date, String)]) -> HistoryArchive.URLRow {
    HistoryArchive.URLRow(url: url, title: title, visitCount: visits.count, typedCount: visits.filter { $0.1 == "typed" }.count,
                          lastVisit: visits.map(\.0).max() ?? Date(), visits: visits.map { HistoryArchive.Visit(time: $0.0, transition: $0.1) })
}

@Suite("History on an engine that keeps it (ROADMAP 3.5 task 5; from the v6 archive since 3.9)")
struct HistoryMigrationTests {
    @Test("A never-imported profile's archived history goes into the engine's once, with titles and visits; the second run reads nothing")
    func importsOnce() async throws {
        let f = try TabsFixture()
        // ISO 8601 in the archive keeps whole seconds.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let profile = f.space.profileID
        try writeArchive(f, profile: profile, [
            row("https://github.com/", "GitHub", [(now.addingTimeInterval(-3_600), "typed"), (now, "link")]),
            row("https://example.org/page", "Example", [(now.addingTimeInterval(-60), "link")]),
            // Older than the engine keeps (90 days): counted, not imported.
            row("https://old.example/", "Old", [(now.addingTimeInterval(-200 * 86_400), "link")]),
        ])
        let history = FakeHistory()
        history.now = { now }

        let report = try #require(await HistoryMigration.run(store: f.store, profile: profile, into: history))
        #expect(report.localURLs == 3)
        #expect(report.result == HistoryImportResult(urls: 2, visits: 3, expiredVisits: 1, expiredURLs: 1))
        let github = try #require(await history.visits(for: URL(string: "https://github.com/")!))
        #expect(github.entry.title == "GitHub")
        #expect(github.entry.visitCount == 2 && github.entry.typedCount == 1)
        #expect(github.visits.map(\.transition) == [.typed, .link])
        #expect(f.store.settings.settings.historyImportedProfiles == [profile])

        // Next launch: the flag holds, nothing is read or sent.
        #expect(await HistoryMigration.run(store: f.store, profile: profile, into: history) == nil)
        #expect(history.importCalls == [3])
    }

    @Test("A batch boundary keeps every row and its visits")
    func batches() async throws {
        let f = try TabsFixture()
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let rows = (0..<(HistoryMigration.batchSize + 5)).map { index in
            row("https://site\(index).example/", "Site \(index)", [(now.addingTimeInterval(-Double(index)), "link")])
        }
        try writeArchive(f, profile: f.space.profileID, rows)
        let history = FakeHistory()
        history.now = { now }
        let report = try #require(await HistoryMigration.run(store: f.store, profile: f.space.profileID, into: history))
        #expect(report.result.urls == rows.count)
        #expect(history.importCalls == [HistoryMigration.batchSize, 5])
    }

    @Test("Without an archive, or with only an imported profile's old visits in it, nothing is sent and the profile is flagged")
    func nothingToImport() async throws {
        let f = try TabsFixture()
        let history = FakeHistory()
        let report = try #require(await HistoryMigration.run(store: f.store, profile: f.space.profileID, into: history))
        #expect(report.localURLs == 0 && history.importCalls.isEmpty)
        #expect(f.store.settings.settings.historyImportedProfiles == [f.space.profileID])

        let g = try TabsFixture()
        try writeArchive(g, profile: g.space.profileID, imported: true,
                         [row("https://old.example/", "Old", [(Date().addingTimeInterval(-200 * 86_400), "link")])])
        let report2 = try #require(await HistoryMigration.run(store: g.store, profile: g.space.profileID, into: history))
        #expect(report2.localURLs == 0 && history.importCalls.isEmpty)
    }

    @Test("An archive that does not read leaves the profile unflagged (the next launch tries again)")
    func unreadableArchive() async throws {
        let f = try TabsFixture()
        try Data("not json".utf8).write(to: f.store.historyArchiveURL)
        #expect(await HistoryMigration.run(store: f.store, profile: f.space.profileID, into: FakeHistory()) == nil)
        #expect(f.store.settings.settings.historyImportedProfiles.isEmpty)
    }
}

/// Records the engine's requests for the address field.
final class FocusRequests: WebContentsUIDelegate {
    private(set) var pages: [ObjectIdentifier] = []
    func webContentsDidRequestFocusOnLocationBar(_ webContents: any WebContents) { pages.append(ObjectIdentifier(webContents)) }
}

@Suite("The engine's focus-the-location-bar command (ROADMAP 3.5 task 4)")
struct FocusLocationBarTests {
    @Test("Reaches the window's UI delegate for the page it shows, not for a page in the background")
    func shownPageOnly() async throws {
        let f = try TabsFixture()
        let shown = try f.today("https://shown.example/"), background = try f.today("https://background.example/")
        f.sidebar.select(background.id)
        f.sidebar.select(shown.id)
        await f.settle()
        let recorder = FocusRequests()
        f.tabs.pageUIDelegate = recorder
        let shownPage = try #require(f.page(shown.id)), backgroundPage = try #require(f.page(background.id))
        backgroundPage.simulateFocusLocationBarRequest()
        shownPage.simulateFocusLocationBarRequest()
        #expect(recorder.pages == [ObjectIdentifier(shownPage)])
    }
}

/// Answers where the engine's bubbles point.
final class BubbleAnchorAnswer: WebContentsUIDelegate {
    let rect = CGRect(x: 12, y: 700, width: 16, height: 28)
    func bubbleAnchorRect(for webContents: any WebContents) -> CGRect? { rect }
}

@Suite("Chrome's bubbles point at the window's site button (ROADMAP 3.7a, PLAN §4 hybrid UI)")
struct BubbleAnchorTests {
    @Test("The engine's question reaches the window's UI delegate through the tab controller")
    func answeredByTheWindow() async throws {
        let f = try TabsFixture()
        let entry = try f.today("https://site.example/")
        f.sidebar.select(entry.id)
        await f.settle()
        let page = try #require(f.page(entry.id))
        #expect(page.simulateBubbleAnchorQuery() == nil)
        let answer = BubbleAnchorAnswer()
        f.tabs.pageUIDelegate = answer
        #expect(page.simulateBubbleAnchorQuery() == answer.rect)
    }
}
