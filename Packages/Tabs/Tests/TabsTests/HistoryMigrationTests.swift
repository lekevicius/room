import Engine
import FakeEngine
import Foundation
import Model
import Testing
@testable import Tabs

@Suite("History on an engine that keeps it (ROADMAP 3.5 task 5)")
struct HistoryMigrationTests {
    @Test("The Chapter 2 history goes into the engine's once per profile, with titles and visits; the second run reads nothing")
    func importsOnce() async throws {
        let f = try TabsFixture()
        let now = Date()
        let profile = f.space.profileID
        try f.store.history.importRows([
            HistoryImport(url: "https://github.com/", title: "GitHub", visits: [(now.addingTimeInterval(-3_600), .typed), (now, .link)]),
            HistoryImport(url: "https://example.org/page", title: "Example", visits: [(now.addingTimeInterval(-60), .link)]),
            // Older than the engine keeps (90 days): counted, not imported.
            HistoryImport(url: "https://old.example/", title: "Old", visits: [(now.addingTimeInterval(-200 * 86_400), .link)]),
        ], profile: profile)
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
        let now = Date()
        let rows = (0..<(HistoryMigration.batchSize + 5)).map { index in
            HistoryImport(url: "https://site\(index).example/", title: "Site \(index)", visits: [(now.addingTimeInterval(-Double(index)), .link)])
        }
        try f.store.history.importRows(rows, profile: f.space.profileID)
        let history = FakeHistory()
        history.now = { now }
        let report = try #require(await HistoryMigration.run(store: f.store, profile: f.space.profileID, into: history))
        #expect(report.result.urls == rows.count)
        #expect(history.importCalls == [HistoryMigration.batchSize, 5])
    }

    @Test("With the engine's history, commits are not written to the store's table (Chromium records them)")
    func noLocalRecording() async throws {
        let f = try TabsFixture()
        f.profile.fakeHistory = FakeHistory()
        #expect(!f.tabs.recordsLocalHistory(profile: f.space.profileID))
        f.tabs.openNewTab(url: "https://typed.example/")
        await f.settle()
        try f.store.history.recordVisitNow(url: "https://barrier.invalid/", title: nil, transition: .link, profile: UUID())
        #expect(try f.store.history.row(url: "https://typed.example/", profile: f.space.profileID) == nil)
        #expect(try f.store.history.count(profile: f.space.profileID) == 0)
    }
}
