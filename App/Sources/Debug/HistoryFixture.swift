#if DEBUG
import Foundation
import Model
import Store

/// `Room -RoomHistoryRows 50000` (Debug builds, with a throwaway state
/// directory): fills history with synthetic rows for the ROADMAP 2.4
/// measurement (keystroke to local results with 50k history rows).
/// Deterministic: the same rows every run. Hosts follow a steep power law
/// (a few sites hold most visits, as in real history), paths and titles are
/// word salad, visits span a year, 10% typed, 10% search results pages.
enum HistoryFixture {
    static var requestedRows: Int? {
        let rows = UserDefaults.standard.integer(forKey: "RoomHistoryRows")
        return rows > 0 ? rows : nil
    }

    static func populate(_ history: History, rows: Int, profile: UUID, now: Date = Date()) {
        // Fills up to `rows`: a state directory other runs used (the grand tour, Phase 2.9) has some history already.
        guard let existing = try? history.count(profile: profile), existing < rows else { return }
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
        var imports: [HistoryImport] = []
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
            guard seen.insert(path).inserted else { continue }
            let count = 1 + Int(-log(max(1e-9, random.double())) * 2.5)
            let visits: [(at: Date, transition: HistoryTransition)] = (0..<min(count, 30)).map { _ in
                let age = random.double() * random.double() * 365 * 86_400
                let transition: HistoryTransition = isSearch ? .generated : (random.int(10) == 0 ? .typed : .link)
                return (now.addingTimeInterval(-age), transition)
            }
            imports.append(HistoryImport(url: path, title: title, visits: visits))
        }
        let start = ContinuousClock.now
        do {
            try history.importRows(imports, profile: profile)
            NSLog("Room: history fixture: \(rows) rows, \(imports.reduce(0) { $0 + $1.visits.count }) visits in \(ContinuousClock.now - start)")
        } catch {
            NSLog("Room: history fixture failed: \(error)")
        }
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
