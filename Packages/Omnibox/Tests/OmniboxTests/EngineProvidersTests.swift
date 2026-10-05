import Engine
import Foundation
import Model
import Testing
@testable import Omnibox

@Suite("Engine providers: Chrome's matches in Room's bands (ROADMAP 3.5 task 3)")
struct EngineProvidersTests {
    private func history(_ url: String, relevance: Int, kind: AutocompleteMatchKind = .historyURL, inline: String = "",
                         isDefault: Bool = false, tab: Bool = false) -> AutocompleteMatch {
        AutocompleteMatch(contents: url, description: "Title \(url)", destinationURL: URL(string: url), inlineCompletion: inline,
                          relevance: relevance, kind: kind, provider: .historyQuick, isDeletable: true, hasTabMatch: tab,
                          allowedToBeDefault: isDefault)
    }

    @Test("History matches go into the history band by rank, whatever Chrome's relevance; other kinds are not history")
    func historyBand() {
        let engine = [history("https://a.example/", relevance: 1_500), history("https://b.example/x", relevance: 2_000),
                      AutocompleteMatch(contents: "a", destinationURL: URL(string: "https://www.google.com/search?q=a"), relevance: 1_300,
                                        kind: .searchWhatYouTyped, provider: .search),
                      history("https://c.example/", relevance: 10, kind: .historyTitle)]
        let matches = EngineHistoryProvider.matches(from: engine, input: OmniboxInput(text: "a"), in: OmniboxContext())
        #expect(matches.map(\.action.url) == ["https://a.example/", "https://b.example/x", "https://c.example/"])
        #expect(matches.map(\.relevance) == [1_299, 1_212, 1_124])
        #expect(matches.allSatisfy { Relevance.history.contains($0.relevance) && $0.provider == .history && $0.isDeletable })
        #expect(matches.allSatisfy { $0.inlineCompletion == nil })
    }

    @Test("The engine's default history match completes inline in the inline band; prevented after a deletion")
    func inline() {
        let engine = [history("https://github.com/", relevance: 1_410, inline: "thub.com", isDefault: true), history("https://gist.github.com/", relevance: 900)]
        let matches = EngineHistoryProvider.matches(from: engine, input: OmniboxInput(text: "gi"), in: OmniboxContext())
        #expect(matches[0].inlineCompletion == "thub.com")
        #expect(Relevance.inlineHistory.contains(matches[0].relevance))
        // The host root stands for its host: deleting it deletes the host (2.4b's rule).
        #expect(HistoryProvider.deletedHost(for: matches[0]) == "github.com")
        let result = OmniboxResult(ranking: matches + VerbatimProvider().matches(for: OmniboxInput(text: "gi"), in: OmniboxContext()),
                                   input: OmniboxInput(text: "gi"))
        #expect(result.inlineCompletion == "thub.com")

        let prevented = EngineHistoryProvider.matches(from: engine, input: OmniboxInput(text: "gi", preventsInlineCompletion: true), in: OmniboxContext())
        #expect(prevented.allSatisfy { $0.inlineCompletion == nil && Relevance.history.contains($0.relevance) })
    }

    @Test("A page the engine sees open switches to the entry that shows it")
    func tabMatch() {
        let id = UUID(), space = UUID()
        let context = OmniboxContext(entries: [OmniboxEntry(id: id, kind: .today, title: "Docs", url: "https://docs.example/a", spaceID: space)])
        let matches = EngineHistoryProvider.matches(from: [history("https://docs.example/a", relevance: 900, tab: true)],
                                                    input: OmniboxInput(text: "docs"), in: context)
        #expect(matches.first?.action == .switchToEntry(id: id, space: space, url: "https://docs.example/a"))
    }

    @Test("A site-search chip keeps only that site's history")
    func siteSearch() {
        let site = SiteSearch.defaults.first { $0.keyword == "yt" }!
        let engine = [history("https://www.youtube.com/watch?v=1", relevance: 900), history("https://example.com/", relevance: 1_000)]
        let matches = EngineHistoryProvider.matches(from: engine, input: OmniboxInput(field: "lofi", siteSearch: site), in: OmniboxContext())
        #expect(matches.map(\.action.url) == ["https://www.youtube.com/watch?v=1"])
    }

    @Test("Suggestions: the engine's suggest matches in the search band by rank, what-you-typed left to Room's verbatim row")
    func suggestBand() {
        let engine = (0..<7).map { index in
            AutocompleteMatch(contents: "swift \(index)", destinationURL: URL(string: "https://www.google.com/search?q=swift+\(index)"),
                              relevance: 1_000 - index, kind: .searchSuggest, provider: .search)
        } + [AutocompleteMatch(contents: "swift", destinationURL: URL(string: "https://www.google.com/search?q=swift"), relevance: 1_300,
                               kind: .searchWhatYouTyped, provider: .search)]
        let matches = EngineSuggestProvider.matches(from: engine, input: OmniboxInput(text: "swift"), engine: .google)
        #expect(matches.count == SuggestClient.limit)
        #expect(matches.allSatisfy { $0.provider == .suggest && Relevance.suggest.contains($0.relevance) })
        #expect(matches.first?.action == .search(query: "swift 0", url: "https://www.google.com/search?q=swift+0"))
        #expect(EngineSuggestProvider.matches(from: engine, input: OmniboxInput(field: ">swift"), engine: .google).isEmpty)
    }

    @Test("The switch rule: off never asks the engine for SearchProvider; on asks only for a query in normal mode")
    func switchRule() {
        let query = OmniboxInput(text: "swift docs")
        #expect(EngineProviderChoice.providers(for: query, suggestionsEnabled: false) == .local)
        #expect(!EngineProviderChoice.providers(for: query, suggestionsEnabled: false).contains(.search))
        #expect(EngineProviderChoice.providers(for: query, suggestionsEnabled: true) == AutocompleteProviders.local.union(.search))
        #expect(!EngineProviderChoice.providers(for: OmniboxInput(field: ">re"), suggestionsEnabled: true).contains(.search))
        #expect(!EngineProviderChoice.providers(for: OmniboxInput(text: "github.com/apple"), suggestionsEnabled: true).contains(.search))
        let site = SiteSearch.defaults[0]
        #expect(!EngineProviderChoice.providers(for: OmniboxInput(field: "x", siteSearch: site), suggestionsEnabled: true).contains(.search))
    }

    @Test("Room's engines in the engine's template form")
    func templates() {
        let google = SearchEngine.google.engineTemplate()
        #expect(google.searchURL == "https://www.google.com/search?q={searchTerms}")
        #expect(google.suggestURL == "https://suggestqueries.google.com/complete/search?client=firefox&q={searchTerms}")
        #expect(google.keyword == "room-google")
        let debug = SearchEngine.duckDuckGo.engineTemplate(suggestURL: "http://127.0.0.1:8771/complete/search?q={searchTerms}")
        #expect(debug.keyword == "room-duckduckgo-debug" && debug.suggestURL?.hasPrefix("http://127.0.0.1") == true)
    }
}
