import Foundation
import Model
import Testing
@testable import Omnibox

@Suite("URL fixup (spec §A.5, §C)")
struct URLFixupTests {
    @Test("Bare hosts get a scheme; URLs pass", arguments: [
        ("example.com", "https://example.com"),
        ("example.com/path?q=1", "https://example.com/path?q=1"),
        ("https://example.com/x", "https://example.com/x"),
        ("http://intranet.local:8080", "http://intranet.local:8080"),
        ("localhost:3000", "http://localhost:3000"),
        ("about:blank", "about:blank"),
    ])
    func accepted(text: String, url: String) {
        #expect(URLFixup.url(from: text) == url)
    }

    @Test("Not URLs", arguments: ["", "   ", "hello world", "nodot", "https://", ".com", "example..com"])
    func refused(text: String) {
        #expect(URLFixup.url(from: text) == nil)
    }

    @Test("Surely a URL: scheme, port, path, localhost, IP, known or country TLD", arguments: [
        "github.com", "https://node.js", "localhost:3000", "192.168.1.1", "example.lt", "node.js/docs", "intranet.local",
    ])
    func confident(text: String) {
        guard case .url(_, let confident) = URLFixup.classify(text) else {
            Issue.record("\(text) is not a URL")
            return
        }
        #expect(confident)
    }

    @Test("Could be a query: an unknown TLD on a bare name")
    func unsure() {
        #expect(URLFixup.classify("node.js") == .url("https://node.js", confident: false))
    }

    @Test("Queries: words, a single word without a dot, a leading ?")
    func queries() {
        #expect(URLFixup.classify("hello world") == .query("hello world"))
        #expect(URLFixup.classify("swift") == .query("swift"))
        #expect(URLFixup.classify("?github.com") == .query("github.com"))
    }

    @Test("Search URLs escape the query, including & + = ? #")
    func searchURL() {
        #expect(URLFixup.searchURL(for: " room browser ") == "https://www.google.com/search?q=room%20browser")
        #expect(SearchEngine.duckDuckGo.searchURL(for: "a&b+c=d?#") == "https://duckduckgo.com/?q=a%26b%2Bc%3Dd%3F%23")
    }
}

@Suite("Verbatim provider (spec §C top hit, search)")
struct VerbatimTests {
    let context = OmniboxContext(searchEngine: .google)

    @Test("A query: search is the top hit, and it keeps its slot")
    func query() {
        let result = Omnibox().result(for: OmniboxInput(text: "swift concurrency"), in: context)
        #expect(result.matches.count == 1)
        #expect(result.matches[0].action == .search(query: "swift concurrency", url: "https://www.google.com/search?q=swift%20concurrency"))
        #expect(result.matches[0].group == .topHit)
        #expect(result.matches[0].relevance == Relevance.verbatimSearch)
    }

    @Test("A sure URL: open it; searching for it is the alternative in the search group")
    func url() {
        let result = Omnibox().result(for: OmniboxInput(text: "github.com"), in: context)
        #expect(result.matches.map(\.action) == [.navigate(url: "https://github.com"),
                                                  .search(query: "github.com", url: "https://www.google.com/search?q=github.com")])
        #expect(result.matches.map(\.group) == [.topHit, .search])
        #expect(result.matches[0].title == "github.com")
    }

    @Test("An unsure URL: search first, the URL second")
    func unsure() {
        let result = Omnibox().result(for: OmniboxInput(text: "node.js"), in: context)
        #expect(result.matches.map(\.action) == [.search(query: "node.js", url: "https://www.google.com/search?q=node.js"),
                                                  .navigate(url: "https://node.js")])
    }

    @Test("Empty input: no rows")
    func empty() {
        #expect(Omnibox().result(for: OmniboxInput(text: "   "), in: context).isEmpty)
    }
}

@Suite("Open tabs and pinned providers (spec §C groups 2, 3)")
struct EntryProviderTests {
    let work = UUID(), home = UUID()
    let now = Date(timeIntervalSince1970: 2_000_000)

    func entry(_ kind: EntryKind, _ title: String, _ url: String, space: UUID?, hoursAgo: Double? = nil) -> OmniboxEntry {
        OmniboxEntry(id: UUID(), kind: kind, title: title, url: url, storedURL: kind.isPermanent ? url : nil, spaceID: space,
                     spaceName: space == work ? "Work" : (space == home ? "Home" : nil),
                     lastActiveAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) })
    }

    func context(_ entries: [OmniboxEntry], current: UUID? = nil) -> OmniboxContext {
        OmniboxContext(entries: entries, activeSpaceID: work, currentEntryID: current, now: now)
    }

    @Test("Today tabs from every space; the chip names another space only")
    func acrossSpaces() {
        let here = entry(.today, "Swift Forums", "https://forums.swift.org/", space: work)
        let there = entry(.today, "Swift.org", "https://www.swift.org/", space: home)
        let matches = OpenTabsProvider().matches(for: OmniboxInput(text: "swift"), in: context([here, there]))
        #expect(Set(matches.map(\.action)) == [.switchToEntry(id: here.id, space: work, url: here.url),
                                                .switchToEntry(id: there.id, space: home, url: there.url)])
        #expect(matches.first { $0.icon == .entry(here.id) }?.spaceName == nil)
        #expect(matches.first { $0.icon == .entry(there.id) }?.spaceName == "Home")
        #expect(matches.allSatisfy { $0.group == .openTabs })
    }

    @Test("The entry in the card is never suggested")
    func notCurrent() {
        let current = entry(.today, "Swift", "https://swift.org", space: work)
        #expect(OpenTabsProvider().matches(for: OmniboxInput(text: "swift"), in: context([current], current: current.id)).isEmpty)
    }

    @Test("Pinned entries in every space and essentials; Today tabs are not pinned matches")
    func pinned() {
        let pin = entry(.pinned, "Linear", "https://linear.app/team", space: home)
        let essential = entry(.essential, "Gmail", "https://mail.google.com/", space: nil)
        let tab = entry(.today, "Linear docs", "https://linear.app/docs", space: work)
        let entries = [pin, essential, tab]
        #expect(PinnedProvider().matches(for: OmniboxInput(text: "linear"), in: context(entries)).map(\.icon) == [.entry(pin.id)])
        #expect(PinnedProvider().matches(for: OmniboxInput(text: "mail"), in: context(entries)).map(\.icon) == [.entry(essential.id)])
        #expect(PinnedProvider().matches(for: OmniboxInput(text: "gmail"), in: context(entries)).first?.spaceName == nil)
    }

    @Test("Every word must match the title or the URL")
    func allWords() {
        let tab = entry(.today, "Pull requests · room", "https://github.com/lekevicius/room/pulls", space: work)
        #expect(OpenTabsProvider().matches(for: OmniboxInput(text: "room pulls"), in: context([tab])).count == 1)
        #expect(OpenTabsProvider().matches(for: OmniboxInput(text: "room issues"), in: context([tab])).isEmpty)
    }

    @Test("A host prefix outranks a title substring; recency breaks ties")
    func ranking() {
        let host = entry(.today, "Home", "https://github.com/", space: work, hoursAgo: 48)
        let substring = entry(.today, "Learning git basics", "https://example.com/", space: work, hoursAgo: 0)
        let older = entry(.today, "GitHub", "https://github.com/a", space: work, hoursAgo: 100)
        let matches = OpenTabsProvider().matches(for: OmniboxInput(text: "git"), in: context([substring, older, host]))
            .sorted { $0.relevance > $1.relevance }
        #expect(matches.map(\.icon) == [.entry(host.id), .entry(older.id), .entry(substring.id)])
        #expect(matches.allSatisfy { Relevance.openTabs.contains($0.relevance) })
    }

    @Test("A tab at exactly the typed URL is the top hit, deduped against the verbatim URL")
    func exactTab() {
        let tab = entry(.today, "GitHub", "https://github.com/", space: home)
        let result = Omnibox().result(for: OmniboxInput(text: "github.com"), in: context([tab]))
        #expect(result.matches.first?.action == .switchToEntry(id: tab.id, space: home, url: tab.url))
        #expect(!result.matches.contains { $0.action == .navigate(url: "https://github.com") })
        #expect(result.matches.contains { if case .search = $0.action { true } else { false } })
    }
}

@Suite("Scorer (spec §C): bands, dedupe, groups, 8 rows")
struct ScorerTests {
    func match(_ id: String, _ provider: ProviderKind, _ relevance: Int, url: String? = nil, keepsSlot: Bool = false,
               inline: String? = nil) -> OmniboxMatch {
        OmniboxMatch(id: id, provider: provider, relevance: relevance, action: .navigate(url: url ?? "https://\(id).example"),
                     title: id, icon: .url, inlineCompletion: inline, keepsSlot: keepsSlot)
    }

    @Test("Bands: an exact entry beats the sure URL, which beats a query's search, which beats tabs, pinned and history")
    func bands() {
        #expect(Relevance.exactEntry > Relevance.inlineHistory.upperBound)
        #expect(Relevance.inlineHistory.lowerBound > Relevance.verbatimURL)
        #expect(Relevance.verbatimURL > Relevance.verbatimSearch)
        #expect(Relevance.verbatimSearch > Relevance.history.upperBound)
        #expect(Relevance.verbatimSearch > Relevance.openTabs.upperBound)
        #expect(Relevance.openTabs.lowerBound > Relevance.pinned.lowerBound)
        #expect(Relevance.suggest.upperBound < Relevance.pinned.lowerBound)
    }

    @Test("The most relevant match is the top hit; the rest follow in group order")
    func groups() {
        let result = OmniboxResult(ranking: [
            match("search", .verbatim, 1300),
            match("pin", .pinned, 1050),
            match("tab", .openTabs, 1010),
            match("hist", .history, 1100),
            match("cmd", .commands, 1250),
        ], input: OmniboxInput(text: "x"))
        #expect(result.matches.map(\.id) == ["search", "tab", "pin", "hist", "cmd"])
        #expect(result.matches.map(\.group) == [.topHit, .openTabs, .pinned, .history, .commands])
    }

    @Test("Within a group, relevance order")
    func withinGroup() {
        let result = OmniboxResult(ranking: [match("top", .verbatim, 1300), match("a", .openTabs, 1001), match("b", .openTabs, 1100)],
                                   input: OmniboxInput(text: "x"))
        #expect(result.matches.map(\.id) == ["top", "b", "a"])
    }

    @Test("Dedupe by normalised URL keeps the most relevant (trailing slash, fragment, host case ignored)")
    func dedupe() {
        let result = OmniboxResult(ranking: [
            match("pin", .pinned, 1000, url: "https://Example.com/#top"),
            match("tab", .openTabs, 1100, url: "https://example.com/"),
            match("other", .openTabs, 1050, url: "https://example.com/?q=1"),
        ], input: OmniboxInput(text: "x"))
        #expect(result.matches.map(\.id) == ["tab", "other"])
    }

    @Test("At most 8 rows; the search row keeps its slot")
    func limit() {
        var candidates = (0..<20).map { match("tab\($0)", .openTabs, 1199 - $0) }
        candidates.append(match("url", .verbatim, 1400))
        candidates.append(match("search", .verbatim, Relevance.verbatimAlternative, keepsSlot: true))
        let result = OmniboxResult(ranking: candidates, input: OmniboxInput(text: "x"))
        #expect(result.matches.count == 8)
        #expect(result.matches.first?.id == "url")
        #expect(result.matches.last?.id == "search")
        #expect(result.matches.dropFirst().dropLast().map(\.id) == (0..<6).map { "tab\($0)" })
    }

    @Test("Inline completion comes from a history top hit only, and not after a deletion")
    func inline() {
        let history = match("h", .history, 1420, inline: "hub.com")
        let tab = match("t", .openTabs, 1450, inline: "hub.com")
        #expect(OmniboxResult(ranking: [history], input: OmniboxInput(text: "git")).inlineCompletion == "hub.com")
        #expect(OmniboxResult(ranking: [tab, history], input: OmniboxInput(text: "git")).inlineCompletion == nil)
        #expect(OmniboxResult(ranking: [history], input: OmniboxInput(text: "git", preventsInlineCompletion: true)).inlineCompletion == nil)
    }

    @Test("⇥ jumps to the next group's first row and wraps; ⇧⇥ to the group start, then the previous group")
    func tabCycling() {
        let result = OmniboxResult(ranking: [
            match("top", .verbatim, 1400),
            match("t1", .openTabs, 1100), match("t2", .openTabs, 1050),
            match("p1", .pinned, 1000),
        ], input: OmniboxInput(text: "x"))
        #expect(result.matches.map(\.id) == ["top", "t1", "t2", "p1"])
        #expect(result.groupStart(after: 0) == 1)
        #expect(result.groupStart(after: 2) == 3)
        #expect(result.groupStart(after: 3) == 0)
        #expect(result.groupStart(after: 2, backwards: true) == 1)
        #expect(result.groupStart(after: 1, backwards: true) == 0)
        #expect(result.groupStart(after: 0, backwards: true) == 3)
    }

    @Test("Inline host completion: the input as a prefix of the host or host + path")
    func inlineSuffix() {
        #expect(InlineCompletion.suffix(completing: "git", with: "https://www.github.com/") == "hub.com")
        #expect(InlineCompletion.suffix(completing: "www.git", with: "https://www.github.com/") == "hub.com")
        #expect(InlineCompletion.suffix(completing: "github.com/le", with: "https://github.com/lekevicius") == "kevicius")
        #expect(InlineCompletion.suffix(completing: "hub", with: "https://github.com/") == nil)
        #expect(InlineCompletion.suffix(completing: "github.com", with: "https://github.com/") == nil)
    }
}
