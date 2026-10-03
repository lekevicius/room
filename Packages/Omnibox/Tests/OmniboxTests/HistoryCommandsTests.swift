import Foundation
import Model
import Testing
@testable import Omnibox

private let now = Date(timeIntervalSince1970: 1_790_000_000)
private let day: TimeInterval = 86_400

/// A history database in a temporary directory.
/// The profile the history fixtures record in (and the contexts' active one).
let historyProfile = UUID()

final class HistoryFixture {
    let directory: URL
    let history: History

    init(_ rows: [HistoryImport] = []) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomOmniboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        history = History(database: try RoomDatabase(url: directory.appending(path: "Room.sqlite")))
        try history.importRows(rows, profile: historyProfile)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var omnibox: Omnibox { Omnibox(providers: Omnibox.localProviders + [HistoryProvider(history: history)]) }
}

private func visits(_ count: Int, _ transition: HistoryTransition = .link, daysAgo: Double = 0) -> [(at: Date, transition: HistoryTransition)] {
    (0..<count).map { (now.addingTimeInterval(-daysAgo * day - Double($0) * 60), transition) }
}

@Suite("History provider (spec §C group 4, inline completion)")
struct HistoryProviderTests {
    let context = OmniboxContext(activeProfileID: historyProfile, now: now)

    @Test("Rows rank by match quality and frecency inside the history band, and are deletable")
    func ranking() throws {
        let fixture = try HistoryFixture([
            HistoryImport(url: "https://swift.org/blog/", title: "Blog | Swift.org", visits: visits(1, daysAgo: 60)),
            HistoryImport(url: "https://forums.swift.org/", title: "Swift Forums", visits: visits(8)),
        ])
        let matches = HistoryProvider(history: fixture.history).matches(for: OmniboxInput(text: "swift"), in: context)
            .filter { $0.inlineCompletion == nil }
        #expect(matches.map(\.action.url) == ["https://forums.swift.org/", "https://swift.org/blog/"])
        #expect(matches.allSatisfy { Relevance.history.contains($0.relevance) && $0.isDeletable && $0.group == .history })
        #expect(matches[0].relevance > matches[1].relevance)
        #expect(matches[0].title == "Swift Forums")
        #expect(matches[0].detail == "forums.swift.org")
    }

    @Test("A host completes inline when it was typed before or visited three times; one link visit is not enough")
    func inlineHost() throws {
        let fixture = try HistoryFixture([
            HistoryImport(url: "https://www.github.com/apple/swift", title: "apple/swift", visits: visits(1, .typed)),
            HistoryImport(url: "https://news.ycombinator.com/", title: "Hacker News", visits: visits(3)),
            HistoryImport(url: "https://gitlab.com/", title: "GitLab", visits: visits(1, daysAgo: 30)),
            HistoryImport(url: "https://nebula.tv/", title: "Nebula", visits: visits(1)),
        ])
        let omnibox = fixture.omnibox
        let gi = omnibox.result(for: OmniboxInput(text: "gi"), in: context)
        #expect(gi.inlineCompletion == "thub.com")
        #expect(gi.matches.first?.action == .navigate(url: "https://www.github.com/"))
        #expect(Relevance.inlineHistory.contains(gi.matches.first?.relevance ?? 0))
        #expect(omnibox.result(for: OmniboxInput(text: "new"), in: context).inlineCompletion == "s.ycombinator.com")
        // Only a link visit: listed, not completed.
        let neb = omnibox.result(for: OmniboxInput(text: "neb"), in: context)
        #expect(neb.inlineCompletion == nil)
        #expect(neb.matches.contains { $0.action.url == "https://nebula.tv/" })
    }

    @Test("A more frecent host reached only through links does not keep a typed one from completing")
    func inlineSkipsIneligible() throws {
        let fixture = try HistoryFixture([
            HistoryImport(url: "https://example.org/", title: "Example", visits: visits(2)),
            HistoryImport(url: "https://example.com/", title: "Example", visits: visits(1, .typed, daysAgo: 20)),
        ])
        #expect(fixture.omnibox.result(for: OmniboxInput(text: "exa"), in: context).inlineCompletion == "mple.com")
    }

    @Test("Inline completion beats the verbatim search, then drops after a deletion")
    func inlineBeatsVerbatim() throws {
        let fixture = try HistoryFixture([HistoryImport(url: "https://github.com/", title: "GitHub", visits: visits(2, .typed))])
        let omnibox = fixture.omnibox
        let typed = omnibox.result(for: OmniboxInput(text: "github"), in: context)
        #expect(typed.matches.first?.provider == .history)
        #expect(typed.inlineCompletion == ".com")
        // The search for what was typed is still offered.
        #expect(typed.matches.contains { if case .search(let query, _) = $0.action { query == "github" } else { false } })
        let deleting = omnibox.result(for: OmniboxInput(text: "github", preventsInlineCompletion: true), in: context)
        #expect(deleting.inlineCompletion == nil)
        #expect(deleting.matches.first?.provider == .verbatim)
    }

    @Test("Typed text with a path completes to the most frecent URL it starts")
    func inlinePath() throws {
        let fixture = try HistoryFixture([
            HistoryImport(url: "https://developer.apple.com/documentation/appkit", title: "AppKit", visits: visits(4)),
            HistoryImport(url: "https://developer.apple.com/documentation/swiftui", title: "SwiftUI", visits: visits(1)),
        ])
        let result = fixture.omnibox.result(for: OmniboxInput(text: "developer.apple.com/documentation/a"), in: context)
        #expect(result.inlineCompletion == "ppkit")
        #expect(result.matches.first?.action == .navigate(url: "https://developer.apple.com/documentation/appkit"))
    }

    @Test("History naming an open tab switches to the tab")
    func historyOpenTab() throws {
        let fixture = try HistoryFixture([HistoryImport(url: "https://github.com/", title: "GitHub", visits: visits(2, .typed))])
        let tab = OmniboxEntry(id: UUID(), kind: .today, title: "GitHub", url: "https://github.com/", spaceID: UUID(), spaceName: "Work")
        let context = OmniboxContext(entries: [tab], activeProfileID: historyProfile, now: now)
        let result = fixture.omnibox.result(for: OmniboxInput(text: "git"), in: context)
        #expect(result.inlineCompletion == "hub.com")
        guard case .switchToEntry(let id, _, _) = result.matches.first?.action else {
            Issue.record("top hit does not switch: \(String(describing: result.matches.first?.action))")
            return
        }
        #expect(id == tab.id)
        #expect(result.matches.filter { $0.action.url == "https://github.com/" }.count == 1)
    }

    @Test("Deleting an inline host match names its host; plain rows name their URL")
    func deletion() throws {
        let fixture = try HistoryFixture([HistoryImport(url: "https://github.com/a", title: "A", visits: visits(1, .typed))])
        let matches = HistoryProvider(history: fixture.history).matches(for: OmniboxInput(text: "git"), in: context)
        let inline = try #require(matches.first { $0.inlineCompletion != nil })
        #expect(HistoryProvider.deletedHost(for: inline) == "github.com")
        let row = try #require(matches.first { $0.inlineCompletion == nil })
        #expect(HistoryProvider.deletedHost(for: row) == nil)
        try fixture.history.delete(host: "github.com", profile: historyProfile)
        #expect(fixture.omnibox.result(for: OmniboxInput(text: "git"), in: context).matches.allSatisfy { $0.provider != .history })
    }

    @Test("History comes from the active space's profile only (ROADMAP 2.5)")
    func otherProfile() throws {
        let fixture = try HistoryFixture([HistoryImport(url: "https://github.com/", title: "GitHub", visits: visits(2, .typed))])
        let provider = HistoryProvider(history: fixture.history)
        #expect(!provider.matches(for: OmniboxInput(text: "git"), in: context).isEmpty)
        let elsewhere = OmniboxContext(activeProfileID: UUID(), now: now)
        #expect(provider.matches(for: OmniboxInput(text: "git"), in: elsewhere).isEmpty)
        #expect(provider.recentMatches(in: elsewhere).isEmpty)
        #expect(provider.recentMatches(in: context).count == 1)
    }

    @Test("Eight rows at most with history, open tabs and the kept search row")
    func cap() throws {
        let fixture = try HistoryFixture((0..<12).map {
            HistoryImport(url: "https://docs\($0).example.com/", title: "Docs \($0)", visits: visits(1))
        })
        let tabs = (0..<4).map { OmniboxEntry(id: UUID(), kind: .today, title: "Docs tab \($0)", url: "https://tab\($0).example.org/",
                                              spaceID: nil) }
        let result = fixture.omnibox.result(for: OmniboxInput(text: "docs"), 
                                            in: OmniboxContext(entries: tabs, activeProfileID: historyProfile, now: now))
        #expect(result.matches.count == OmniboxResult.limit)
        #expect(result.matches.contains { $0.keepsSlot })
        #expect(result.matches.map(\.group) == result.matches.map(\.group).sorted())
    }
}

@Suite("Commands (spec §C group 6, `>` mode)")
struct CommandsTests {
    let context = OmniboxContext(commands: CommandRegistry.all)

    @Test("`>` alone lists every command A–Z; only commands answer")
    func listAll() {
        let result = Omnibox(providers: Omnibox.localProviders).result(for: OmniboxInput(field: ">"), in: context)
        #expect(result.matches.count == OmniboxResult.limit)
        let titles = CommandRegistry.all.map(\.title)
        #expect(titles == titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(result.matches.map(\.title) == Array(titles.prefix(OmniboxResult.limit)))
        #expect(result.matches.allSatisfy { $0.provider == .commands })
    }

    @Test("Words and keywords find commands; the best word match is the top hit")
    func matching() {
        let omnibox = Omnibox(providers: Omnibox.localProviders)
        #expect(omnibox.result(for: OmniboxInput(field: ">rel"), in: context).matches.first?.action == .command(id: "reload"))
        #expect(omnibox.result(for: OmniboxInput(field: "> hide"), in: context).matches.first?.action == .command(id: "toggle-sidebar"))
        #expect(omnibox.result(for: OmniboxInput(field: ">copy md"), in: context).matches.isEmpty)
        #expect(omnibox.result(for: OmniboxInput(field: ">copy mark"), in: context).matches.map(\.title) == ["Copy URL as Markdown"])
    }

    @Test("Without `>`, a command shows only for three letters or more that start its words, in the last group")
    func normalMode() {
        let omnibox = Omnibox(providers: Omnibox.localProviders)
        #expect(!omnibox.result(for: OmniboxInput(text: "re"), in: context).matches.contains { $0.provider == .commands })
        let result = omnibox.result(for: OmniboxInput(text: "reload"), in: context)
        #expect(result.matches.first?.provider == .verbatim)
        let commands = result.matches.filter { $0.provider == .commands }
        #expect(commands.map(\.title).contains("Reload"))
        #expect(result.matches.last?.group == .commands)
        // A substring alone is not enough outside `>` mode.
        #expect(!omnibox.result(for: OmniboxInput(text: "oad"), in: context).matches.contains { $0.provider == .commands })
    }

    @Test("Per-space commands carry their space")
    func perSpace() {
        let id = UUID()
        let focus = CommandRegistry.focus(space: id, name: "Work")
        #expect(focus.title == "Focus on Work")
        #expect(CommandRegistry.space(in: focus.id)?.space == id)
        #expect(CommandRegistry.space(in: focus.id)?.focus == true)
        #expect(CommandRegistry.space(in: CommandRegistry.move(toSpace: id, name: "Work").id)?.focus == false)
        #expect(CommandRegistry.space(in: CommandRegistry.reload.id) == nil)
    }
}

@Suite("Site search keywords (spec §C)")
struct SiteSearchTests {
    let context = OmniboxContext()

    @Test("A typed keyword offers its site under the verbatim search")
    func hint() {
        let result = Omnibox().result(for: OmniboxInput(text: "yt"), in: context)
        #expect(result.matches.first?.action == .search(query: "yt", url: SearchEngine.google.searchURL(for: "yt")))
        let hint = result.matches.first { $0.action == .enterSiteSearch(keyword: "yt") }
        #expect(hint?.title == "Search YouTube")
        #expect(hint?.group == .search)
        #expect(SiteSearch.matching("YT ", in: SiteSearch.defaults)?.name == "YouTube")
        #expect(SiteSearch.matching("ytx", in: SiteSearch.defaults) == nil)
    }

    @Test("In the chip's mode Enter searches the site, and history shows only that site")
    func mode() throws {
        let youtube = try #require(SiteSearch.defaults.first { $0.keyword == "yt" })
        let fixture = try HistoryFixture([
            HistoryImport(url: "https://www.youtube.com/watch?v=1", title: "lofi beats", visits: visits(2)),
            HistoryImport(url: "https://lofi.example.com/", title: "lofi elsewhere", visits: visits(5)),
        ])
        let result = fixture.omnibox.result(for: OmniboxInput(field: "lofi", siteSearch: youtube),
                                            in: OmniboxContext(activeProfileID: historyProfile, now: now))
        #expect(result.matches.first?.action == .search(query: "lofi", url: "https://www.youtube.com/results?search_query=lofi"))
        #expect(result.matches.first?.detail == "Search YouTube")
        #expect(result.inlineCompletion == nil)
        #expect(result.matches.dropFirst().map(\.action.url) == ["https://www.youtube.com/watch?v=1"])
    }
}
