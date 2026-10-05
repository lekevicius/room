#if DEBUG
import Engine
import Foundation

/// `Room -RoomHistoryRows 50000` (Debug builds, with a throwaway state and
/// engine directory): fills the engine's history with synthetic rows for the
/// ROADMAP 2.4 measurement (keystroke to rows with 50k history rows).
/// Deterministic: the same rows every run. Hosts follow a steep power law
/// (a few sites hold most visits, as in real history), paths and titles are
/// word salad, visits span 85 days (a year until Phase 3.5: Chromium keeps
/// 90 days, so the import into its history would drop the rest), 10% typed,
/// 10% search results pages.
enum HistoryFixture {
    static let spanDays = 85.0
    /// URLs per engine call (as the 3.5 migration).
    static let batchSize = 2_000

    static var requestedRows: Int? {
        let rows = UserDefaults.standard.integer(forKey: "RoomHistoryRows")
        return rows > 0 ? rows : nil
    }

    /// Fills the engine's history up to `rows` URLs (a state directory other
    /// runs used, the grand tour's, has some already); since 3.9 (schema v6)
    /// the engine's history is the only one. Returns the import's result, or
    /// nil when the history already had `rows`.
    static func populate(_ history: any ProfileHistory, rows: Int, now: Date = Date()) async -> HistoryImportResult? {
        let existing = await history.entries(from: nil, to: nil, limit: 0).count
        guard existing < rows else { return nil }
        var random = SplitMix64(seed: 2_404)
        let words = ["swift", "apple", "room", "browser", "news", "docs", "guide", "api", "design", "music", "video", "travel", "recipe",
                     "garden", "linux", "rust", "kernel", "photo", "maps", "market", "weather", "sport", "chess", "physics", "history",
                     "coffee", "bike", "train", "cloud", "data", "model", "paper", "study", "learn", "build", "code", "review", "issue",
                     "release", "notes", "blog", "forum", "wiki", "shop", "store", "book", "film", "game", "health", "money"]
        let tlds = ["com", "org", "net", "io", "dev", "lt", "co.uk", "de", "app"]
        let famous = ["github.com", "en.wikipedia.org", "www.youtube.com", "news.ycombinator.com", "developer.apple.com", "www.swift.org",
                      "stackoverflow.com", "www.reddit.com", "mail.google.com", "www.google.com"]
        var hosts = famous
        while hosts.count < 2_500 {
            let host = "\(words[random.int(words.count)])\(words[random.int(words.count)])\(hosts.count).\(tlds[random.int(tlds.count)])"
            hosts.append(random.int(3) == 0 ? "www." + host : host)
        }
        var imports: [HistoryImportEntry] = []
        imports.reserveCapacity(rows)
        var seen = Set<String>()
        while imports.count < rows - existing {
            // u³: index 0 (github.com) is the most visited host.
            let u = random.double()
            let host = hosts[min(hosts.count - 1, Int(Double(hosts.count) * u * u * u))]
            let isSearch = host == "www.google.com" || random.int(10) == 0
            let path: String
            let title: String
            if isSearch {
                let query = (0..<(1 + random.int(3))).map { _ in words[random.int(words.count)] }
                path = "https://www.google.com/search?q=" + query.joined(separator: "+") + "&n=\(imports.count)"
                title = query.joined(separator: " ") + " - Google Search"
            } else {
                let parts = (0..<(1 + random.int(3))).map { _ in words[random.int(words.count)] }
                path = "https://\(host)/" + parts.joined(separator: "/") + "/\(imports.count)"
                let titleWords = (0..<(3 + random.int(4))).map { _ in words[random.int(words.count)].capitalized }
                title = titleWords.joined(separator: " ") + " · " + host
            }
            guard seen.insert(path).inserted, let url = URL(string: path) else { continue }
            let count = 1 + Int(-log(max(1e-9, random.double())) * 2.5)
            let visits: [HistoryVisit] = (0..<min(count, 30)).map { _ in
                // Within 85 days (Phase 3.5): Chromium keeps 90 days of history.
                let age = random.double() * random.double() * Self.spanDays * 86_400
                let transition: PageTransition = isSearch ? .generated : (random.int(10) == 0 ? .typed : .link)
                return HistoryVisit(time: now.addingTimeInterval(-age), transition: transition)
            }
            imports.append(HistoryImportEntry(url: url, title: title, visits: visits))
        }
        let start = ContinuousClock.now
        var result = HistoryImportResult()
        var index = 0
        while index < imports.count {
            result = result + (await history.importEntries(Array(imports[index..<min(index + batchSize, imports.count)])))
            index += batchSize
        }
        NSLog("Room: history fixture: %ld URLs, %ld visits into the engine's history in %@", result.urls, result.visits,
              "\(ContinuousClock.now - start)")
        return result
    }
}

/// A small deterministic generator (SplitMix64).
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    mutating func double() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
#endif
