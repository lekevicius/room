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
/// The profile the single-profile tests record in.
private let testProfile = UUID()
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
        try history.recordVisitNow(url: "https://www.github.com/", title: nil, transition: .typed, profile: testProfile, at: now)
        try history.recordVisitNow(url: "https://www.github.com/", title: "GitHub", transition: .link, profile: testProfile, at: now.addingTimeInterval(60))
        let row = try #require(try history.row(url: "https://www.github.com/", profile: testProfile))
        #expect(row.visitCount == 2)
        #expect(row.typedCount == 1)
        #expect(row.title == "GitHub")
        #expect(row.host == "github.com")
        #expect(row.lastVisitAt == Timestamp(now.addingTimeInterval(60)))
        #expect(try history.visits(url: "https://www.github.com/", profile: testProfile).map(\.1) == [.typed, .link])
    }

    @Test("Reloads and internal URLs are not recorded; a fragment is the same page")
    func ignored() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        try history.recordVisitNow(url: "https://example.com/", title: nil, transition: .link, profile: testProfile, at: now)
        try history.recordVisitNow(url: "https://example.com/", title: nil, transition: .reload, profile: testProfile, at: now)
        // A fragment is the same page.
        try history.recordVisitNow(url: "https://example.com/#top", title: nil, transition: .link, profile: testProfile, at: now)
        try history.recordVisitNow(url: "about:blank", title: nil, transition: .typed, profile: testProfile, at: now)
        try history.recordVisitNow(url: "data:text/html,hi", title: nil, transition: .link, profile: testProfile, at: now)
        #expect(try history.count() == 1)
        #expect(try history.row(url: "https://example.com/", profile: testProfile)?.visitCount == 2)
    }

    @Test("The asynchronous recorder stores the visit and a later title")
    func asynchronous() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        await withCheckedContinuation { continuation in
            history.recordVisit(url: "https://swift.org/", title: nil, transition: .link, profile: testProfile, at: now) { _ in continuation.resume() }
        }
        history.setTitle("Swift.org", for: "https://swift.org/", profile: testProfile)
        // Writes are serial: a write queued after the title runs after it.
        await withCheckedContinuation { continuation in
            history.recordVisit(url: "https://example.com/", title: nil, transition: .link, profile: testProfile, at: now) { _ in continuation.resume() }
        }
        #expect(try history.row(url: "https://swift.org/", profile: testProfile)?.title == "Swift.org")
    }

    @Test("Deleting a URL or a host removes it from search")
    func delete() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        for url in ["https://github.com/", "https://github.com/apple/swift", "https://gitlab.com/"] {
            try history.recordVisitNow(url: url, title: nil, transition: .link, profile: testProfile, at: now)
        }
        try history.delete(url: "https://gitlab.com/", profile: testProfile)
        #expect(try history.search("gitlab", profile: testProfile, limit: 10).isEmpty)
        try history.delete(host: "github.com", profile: testProfile)
        #expect(try history.search("git", profile: testProfile, limit: 10).isEmpty)
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

    @Test("v3 gives earlier history to the default profile; visits, hosts and the index follow")
    func profileBackfill() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "Room.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        let first = UUID(), second = UUID()
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v2)
        try queue.write { db in
            // The default profile is the first by position, not by insertion.
            try db.execute(sql: "INSERT INTO profile (id, name, position) VALUES (?, 'Work', 1), (?, 'Default', 0)", arguments: [second, first])
            try db.execute(sql: """
                INSERT INTO history_url (url, title, visitCount, typedCount, lastVisitAt, host, frecency)
                VALUES ('https://en.wikipedia.org/wiki/Vilnius', 'Vilnius', 2, 1, 0, 'en.wikipedia.org', 1.0)
                """)
            try db.execute(sql: "INSERT INTO history_visit (urlID, visitedAt, transition) VALUES (1, 0, 'typed'), (1, 1, 'link')")
            try db.execute(sql: """
                INSERT INTO history_host (host, bestURL, bestFrecency, frecency, visitCount, typedCount)
                VALUES ('en.wikipedia.org', 'https://en.wikipedia.org/wiki/Vilnius', 1.0, 1.0, 2, 1)
                """)
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        try queue.close()

        let database = try RoomDatabase(url: url)
        let history = History(database: database)
        let row = try #require(try history.row(url: "https://en.wikipedia.org/wiki/Vilnius", profile: first))
        #expect(row.visitCount == 2)
        #expect(try history.visits(url: row.url, profile: first).map(\.1) == [.typed, .link])
        #expect(try history.search("ilniu", profile: first, limit: 5).map(\.url) == [row.url])
        #expect(try history.hosts(prefix: "en.wiki", profile: first, limit: 5).map(\.visitCount) == [2])
        #expect(try history.search("ilniu", profile: second, limit: 5).isEmpty)
        #expect(try database.foreignKeyViolations() == 0)
    }
}

@Suite("History per profile")
struct HistoryProfileTests {
    @Test("Each profile keeps its own rows, hosts and deletions")
    func separate() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        let history = fixture.history
        let home = UUID(), work = UUID()
        try history.recordVisitNow(url: "https://github.com/", title: "GitHub", transition: .typed, profile: home, at: now)
        try history.recordVisitNow(url: "https://github.com/", title: "GitHub", transition: .link, profile: work, at: now)
        try history.recordVisitNow(url: "https://linear.app/", title: "Linear", transition: .typed, profile: work, at: now)
        #expect(try history.count() == 3)
        #expect(try history.row(url: "https://github.com/", profile: home)?.typedCount == 1)
        #expect(try history.row(url: "https://github.com/", profile: work)?.typedCount == 0)
        #expect(try history.search("linear", profile: home, limit: 5).isEmpty)
        #expect(try history.search("lin", profile: work, limit: 5).map(\.url) == ["https://linear.app/"])
        #expect(try history.hosts(prefix: "li", profile: home, limit: 5).isEmpty)
        #expect(try history.mostFrecent(profile: home, limit: 5).map(\.url) == ["https://github.com/"])
        try history.delete(host: "github.com", profile: work)
        #expect(try history.row(url: "https://github.com/", profile: home) != nil)
        #expect(try history.hosts(prefix: "git", profile: home, limit: 5).count == 1)
        try history.delete(url: "https://github.com/", profile: home)
        #expect(try history.count(profile: home) == 0)
        #expect(try history.count(profile: work) == 1)
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
        ], profile: testProfile)
        return fixture
    }

    @Test("Substrings match in the URL or the title, case-insensitively (trigram)")
    func substrings() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("ikip", profile: testProfile, limit: 10).map(\.url) == ["https://en.wikipedia.org/wiki/Room"])
        #expect(try fixture.history.search("PROGRAMMING", profile: testProfile, limit: 10).map(\.url) == ["https://github.com/apple/swift"])
    }

    @Test("Every word must match; results come most frecent first")
    func wordsAndOrder() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("swift", profile: testProfile, limit: 10).map(\.url) == ["https://github.com/apple/swift", "https://www.swift.org/documentation/"])
        #expect(try fixture.history.search("swift docu", profile: testProfile, limit: 10).map(\.url) == ["https://www.swift.org/documentation/"])
        // A short word filters the indexed ones.
        #expect(try fixture.history.search("swift gi", profile: testProfile, limit: 10).map(\.url) == ["https://github.com/apple/swift"])
        #expect(try fixture.history.search("swift zz", profile: testProfile, limit: 10).isEmpty)
    }

    @Test("Text of one or two characters matches host prefixes only")
    func shortText() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        #expect(try fixture.history.search("gi", profile: testProfile, limit: 10).map(\.url) == ["https://github.com/apple/swift"])
        // "www." is not part of the host key.
        #expect(try fixture.history.search("sw", profile: testProfile, limit: 10).map(\.url) == ["https://www.swift.org/documentation/"])
        #expect(try fixture.history.search("ki", profile: testProfile, limit: 10).isEmpty)
    }

    @Test("Results past the frecent scan come from the index")
    func pastTheScan() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        var rows = (0..<(History.frecentScan + 10)).map { index in
            HistoryImport(url: "https://site\(index).example.com/", title: "Common page", visits: [(now, .typed)])
        }
        rows.append(HistoryImport(url: "https://rare.example.net/", title: "Needle", visits: [(now.addingTimeInterval(-300 * day), .link)]))
        try fixture.history.importRows(rows, profile: testProfile)
        #expect(try fixture.history.search("needle", profile: testProfile, limit: 5).map(\.url) == ["https://rare.example.net/"])
        #expect(try fixture.history.search("common", profile: testProfile, limit: 5).count == 5)
    }

    @Test("Hosts aggregate their URLs and name the most frecent one")
    func hosts() throws {
        let fixture = try seeded()
        defer { fixture.directory.cleanup() }
        try fixture.history.recordVisitNow(url: "https://github.com/", title: "GitHub", transition: .link, profile: testProfile, at: now.addingTimeInterval(-10 * day))
        let hosts = try fixture.history.hosts(prefix: "Git", profile: testProfile, limit: 5)
        #expect(hosts.map(\.host) == ["github.com"])
        #expect(hosts.first?.bestURL == "https://github.com/apple/swift")
        #expect(hosts.first?.visitCount == 2)
        #expect(hosts.first?.typedCount == 1)
        #expect(try fixture.history.hosts(prefix: "s", profile: testProfile, limit: 5).map(\.host) == ["swift.org"])
        // Deleting the best URL hands the host to the next one; deleting the last removes the host.
        try fixture.history.delete(url: "https://github.com/apple/swift", profile: testProfile)
        let after = try fixture.history.hosts(prefix: "git", profile: testProfile, limit: 5)
        #expect(after.first?.bestURL == "https://github.com/" && after.first?.visitCount == 1 && after.first?.typedCount == 0)
        try fixture.history.delete(url: "https://github.com/", profile: testProfile)
        #expect(try fixture.history.hosts(prefix: "git", profile: testProfile, limit: 5).isEmpty)
    }

    @Test("A host's frecency is the sum of its URLs'")
    func hostFrecency() throws {
        let fixture = try HistoryFixture()
        defer { fixture.directory.cleanup() }
        try fixture.history.recordVisitNow(url: "https://a.example/1", title: nil, transition: .link, profile: testProfile, at: now)
        try fixture.history.recordVisitNow(url: "https://a.example/2", title: nil, transition: .link, profile: testProfile, at: now)
        try fixture.history.recordVisitNow(url: "https://b.example/", title: nil, transition: .typed, profile: testProfile, at: now.addingTimeInterval(-1))
        let hosts = try fixture.history.hosts(prefix: "", profile: testProfile, limit: 5) + fixture.history.hosts(prefix: "a", profile: testProfile, limit: 5)
        let a = try #require(hosts.first { $0.host == "a.example" })
        #expect(abs(Frecency.current(a.frecency, at: now) - 2) < 1e-6)
    }
}
