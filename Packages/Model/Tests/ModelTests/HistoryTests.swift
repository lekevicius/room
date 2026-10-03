import Foundation
import GRDB
import Testing
@testable import Model

/// A history over a fresh database file.
private struct HistoryFixture {
    let directory: TemporaryDirectory
    let database: RoomDatabase
    let history: History

    init() throws {
        directory = try TemporaryDirectory()
        database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        history = History(database: database)
    }
}

private let day: TimeInterval = 86_400
private let now = Date(timeIntervalSince1970: 1_790_000_000)

@Suite("Frecency")
struct FrecencyTests {
    @Test("A visit is worth half after the half-life")
    func halfLife() {
        let stored = Frecency.adding(1, at: now, to: Frecency.none)
        #expect(abs(Frecency.current(stored, at: now) - 1) < 1e-9)
        #expect(abs(Frecency.current(stored, at: now.addingTimeInterval(Frecency.halfLife)) - 0.5) < 1e-9)
    }

    @Test("Visits add up, and the stored value orders rows as their current frecency does at any time")
    func orderIsTimeInvariant() {
        // Ten link visits a month ago against two typed visits yesterday.
        var old = Frecency.none
        for index in 0..<10 { old = Frecency.adding(HistoryTransition.link.weight, at: now.addingTimeInterval(-30 * day + Double(index)), to: old) }
        var fresh = Frecency.none
        for index in 0..<2 { fresh = Frecency.adding(HistoryTransition.typed.weight, at: now.addingTimeInterval(-day + Double(index)), to: fresh) }
        #expect(abs(Frecency.current(old, at: now) - 5) < 0.01)
        for later in [0.0, 10, 100, 1_000] {
            let at = now.addingTimeInterval(later * day)
            #expect((old > fresh) == (Frecency.current(old, at: at) > Frecency.current(fresh, at: at)))
        }
    }

    @Test("A typed visit outweighs a link, a search results page weighs less")
    func weights() {
        #expect(HistoryTransition.typed.weight > HistoryTransition.link.weight)
        #expect(HistoryTransition.generated.weight < HistoryTransition.link.weight)
        #expect(!HistoryTransition.reload.isVisit)
    }
}

@Suite("History recording")
struct HistoryRecordingTests {
    @Test("Visits count per URL; typed visits are counted apart; the title is kept")
    func counts() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        try history.recordVisitNow(url: "https://www.github.com/", title: nil, transition: .typed, at: now)
        try history.recordVisitNow(url: "https://www.github.com/", title: "GitHub", transition: .link, at: now.addingTimeInterval(60))
        let row = try #require(try history.row(url: "https://www.github.com/"))
        #expect(row.visitCount == 2)
        #expect(row.typedCount == 1)
        #expect(row.title == "GitHub")
        #expect(row.host == "github.com")
        #expect(row.lastVisitAt == Timestamp(now.addingTimeInterval(60)))
        #expect(try history.visits(url: "https://www.github.com/").map(\.1) == [.typed, .link])
    }

    @Test("Reloads and internal URLs are not recorded")
    func ignored() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        try history.recordVisitNow(url: "https://example.com/", title: nil, transition: .link, at: now)
        try history.recordVisitNow(url: "https://example.com/", title: nil, transition: .reload, at: now)
        try history.recordVisitNow(url: "about:blank", title: nil, transition: .typed, at: now)
        try history.recordVisitNow(url: "data:text/html,hi", title: nil, transition: .link, at: now)
        #expect(try history.count() == 1)
        #expect(try history.row(url: "https://example.com/")?.visitCount == 1)
    }

    @Test("The asynchronous recorder stores the visit and a later title")
    func asynchronous() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        await withCheckedContinuation { continuation in
            history.recordVisit(url: "https://swift.org/", title: nil, transition: .link, at: now) { _ in continuation.resume() }
        }
        history.setTitle("Swift.org", for: "https://swift.org/")
        // Writes are serial: a write queued after the title runs after it.
        await withCheckedContinuation { continuation in
            history.recordVisit(url: "https://example.com/", title: nil, transition: .link, at: now) { _ in continuation.resume() }
        }
        #expect(try history.row(url: "https://swift.org/")?.title == "Swift.org")
    }

    @Test("Deleting a URL or a host removes it from search")
    func delete() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        for url in ["https://github.com/", "https://github.com/apple/swift", "https://gitlab.com/"] {
            try history.recordVisitNow(url: url, title: nil, transition: .link, at: now)
        }
        try history.delete(url: "https://gitlab.com/")
        #expect(try history.search("gitlab", limit: 10).isEmpty)
        try history.delete(host: "github.com")
        #expect(try history.search("git", limit: 10).isEmpty)
        #expect(try history.count() == 0)
        // Visits go with their URL (cascade).
        let visits = try fixture.database.pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history_visit") }
        #expect(visits == 0)
    }

    @Test("v2 backfills host and frecency of rows recorded before it")
    func migrationBackfill() throws {
        let queue = try DatabaseQueue()
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v1)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO history_url (url, title, visitCount, typedCount, lastVisitAt) VALUES ('https://www.apple.com/mac', 'Mac', 1, 1, 0)")
            try db.execute(sql: "INSERT INTO history_visit (urlID, visitedAt, transition) VALUES (1, ?, 'typed')", arguments: [Timestamp(now)])
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let row = try queue.read { db in try Row.fetchOne(db, sql: "SELECT host, frecency FROM history_url") }
        #expect(row?["host"] == "apple.com")
        let frecency: Double = try #require(row?["frecency"])
        #expect(abs(Frecency.current(frecency, at: now) - 2) < 1e-6)
    }
}

@Suite("History search")
struct HistorySearchTests {
    /// Three sites, Wikipedia the most frecent.
    private func seeded() throws -> HistoryFixture {
        let fixture = try HistoryFixture()
        try fixture.history.importRows([
            HistoryImport(url: "https://en.wikipedia.org/wiki/Room", title: "Room - Wikipedia",
                          visits: (0..<5).map { (now.addingTimeInterval(Double(-$0) * 3_600), .link) }),
            HistoryImport(url: "https://github.com/apple/swift", title: "apple/swift: The Swift Programming Language",
                          visits: [(now, .typed)]),
            HistoryImport(url: "https://www.swift.org/documentation/", title: "Documentation | Swift.org",
                          visits: [(now.addingTimeInterval(-40 * day), .link)]),
        ])
        return fixture
    }

    @Test("Substrings match in the URL or the title, case-insensitively (trigram)")
    func substrings() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("ikip", limit: 10).map(\.url) == ["https://en.wikipedia.org/wiki/Room"])
        #expect(try fixture.history.search("PROGRAMMING", limit: 10).map(\.url) == ["https://github.com/apple/swift"])
    }

    @Test("Every word must match; results come most frecent first")
    func wordsAndOrder() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("swift", limit: 10).map(\.url) == ["https://github.com/apple/swift", "https://www.swift.org/documentation/"])
        #expect(try fixture.history.search("swift docu", limit: 10).map(\.url) == ["https://www.swift.org/documentation/"])
        // A short word filters the indexed ones.
        #expect(try fixture.history.search("swift gi", limit: 10).map(\.url) == ["https://github.com/apple/swift"])
        #expect(try fixture.history.search("swift zz", limit: 10).isEmpty)
    }

    @Test("Text of one or two characters matches host prefixes only")
    func shortText() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("gi", limit: 10).map(\.url) == ["https://github.com/apple/swift"])
        // "www." is not part of the host key.
        #expect(try fixture.history.search("sw", limit: 10).map(\.url) == ["https://www.swift.org/documentation/"])
        #expect(try fixture.history.search("ki", limit: 10).isEmpty)
    }

    @Test("Results past the frecent scan come from the index")
    func pastTheScan() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        var rows = (0..<(History.frecentScan + 10)).map { index in
            HistoryImport(url: "https://site\(index).example.com/", title: "Common page", visits: [(now, .typed)])
        }
        rows.append(HistoryImport(url: "https://rare.example.net/", title: "Needle", visits: [(now.addingTimeInterval(-300 * day), .link)]))
        try fixture.history.importRows(rows)
        #expect(try fixture.history.search("needle", limit: 5).map(\.url) == ["https://rare.example.net/"])
        #expect(try fixture.history.search("common", limit: 5).count == 5)
    }

    @Test("Hosts aggregate their URLs and name the most frecent one")
    func hosts() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        try fixture.history.recordVisitNow(url: "https://github.com/", title: "GitHub", transition: .link, at: now.addingTimeInterval(-10 * day))
        let hosts = try fixture.history.hosts(prefix: "Git", limit: 5)
        #expect(hosts.map(\.host) == ["github.com"])
        #expect(hosts.first?.bestURL == "https://github.com/apple/swift")
        #expect(hosts.first?.visitCount == 2)
        #expect(hosts.first?.typedCount == 1)
        #expect(try fixture.history.hosts(prefix: "s", limit: 5).map(\.host) == ["swift.org"])
    }
}
