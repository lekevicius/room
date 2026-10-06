import Foundation
import Testing
@testable import Omnibox

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

    @Test("A command's row carries its current key (4.4a: the palette's hint follows a remap)")
    func shortcutHint() {
        let commands = [CommandRegistry.pinTab.with(symbol: nil, shortcut: "⌥⌘P"), CommandRegistry.reload.with(symbol: nil)]
        let result = Omnibox(providers: Omnibox.localProviders).result(for: OmniboxInput(field: ">"), in: OmniboxContext(commands: commands))
        #expect(result.matches.first { $0.action == .command(id: CommandRegistry.pinTab.id) }?.shortcut == "⌥⌘P")
        #expect(result.matches.first { $0.action == .command(id: CommandRegistry.reload.id) }?.shortcut == nil)
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

    @Test("In the chip's mode Enter searches the site and nothing completes inline")
    func mode() throws {
        let youtube = try #require(SiteSearch.defaults.first { $0.keyword == "yt" })
        let result = Omnibox().result(for: OmniboxInput(field: "lofi", siteSearch: youtube), in: OmniboxContext())
        #expect(result.matches.first?.action == .search(query: "lofi", url: "https://www.youtube.com/results?search_query=lofi"))
        #expect(result.matches.first?.detail == "Search YouTube")
        #expect(result.inlineCompletion == nil)
    }
}
