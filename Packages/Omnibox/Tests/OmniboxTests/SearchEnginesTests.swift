import Foundation
import Model
import Testing
@testable import Omnibox

/// ROADMAP 4.4a task 3: the engines list, %s, the default per profile, the keywords.
@Suite("Search engines (Settings ▸ Search)")
struct SearchEnginesTests {
    let work = UUID(), home = UUID()

    @Test("The built-in list keeps 2.8's engines and 2.4b's site searches")
    func builtIn() {
        let settings = Settings()
        for engine in [SearchEngine.google, .duckDuckGo, .kagi] {
            #expect(SearchEngine(SearchEngines.list(settings).first { $0.id == engine.id }!) == engine)
        }
        let sites = SearchEngines.siteSearches(settings)
        for old in SiteSearch.defaults {
            let site = sites.first { $0.keyword == old.keyword }
            #expect(site?.engine.template == old.engine.template && site?.host == old.host, "\(old.keyword)")
        }
    }

    @Test("Each profile has its own default; without one, the first-run choice; a removed id falls through")
    func defaultPerProfile() throws {
        var settings = Settings()
        settings.searchEngine = "duckduckgo"
        settings.searchEngineByProfile = [work.uuidString: "kagi", home.uuidString: "gone"]
        #expect(SearchEngines.defaultID(for: work, in: settings) == "kagi")
        #expect(SearchEngines.defaultID(for: home, in: settings) == "duckduckgo")
        #expect(SearchEngines.defaultID(for: nil, in: settings) == "duckduckgo")
        #expect(SearchEngines.engine(for: work, in: settings).searchURL(for: "cats") == "https://kagi.com/search?q=cats")
        settings.searchEngine = "gone"
        #expect(SearchEngines.defaultID(for: home, in: settings) == "google")
    }

    @Test("The URL is shown with %s and stored with {searchTerms}; a URL without it is refused")
    func placeholder() throws {
        #expect(SearchEngines.displayURL("https://x.example/?q={searchTerms}") == "https://x.example/?q=%s")
        #expect(SearchEngines.storedURL(" https://x.example/?q=%s ") == "https://x.example/?q={searchTerms}")
        var settings = Settings()
        let engine = SearchEngineSetting(id: SearchEngines.newID(), name: "Example", keyword: "EX",
                                         searchURL: SearchEngines.storedURL("https://x.example/?q=%s"), suggestURL: "")
        try SearchEngines.save(engine, in: &settings)
        let saved = try #require(settings.searchEngines?.last)
        #expect(saved.keyword == "ex" && saved.suggestURL == nil && settings.searchEngines?.count == SearchEngines.builtIn.count + 1)
        #expect(SearchEngines.siteSearches(settings).contains { $0.keyword == "ex" && $0.engine.searchURL(for: "cats") == "https://x.example/?q=cats" })
        var bad = engine
        bad.id = SearchEngines.newID()
        bad.keyword = "other"
        bad.searchURL = "https://x.example/?q=cats"
        #expect(throws: SearchEngines.Problem.urlNeedsPlaceholder) { try SearchEngines.save(bad, in: &settings) }
        bad.searchURL = "ftp://x.example/{searchTerms}"
        #expect(throws: SearchEngines.Problem.urlInvalid) { try SearchEngines.save(bad, in: &settings) }
        bad.searchURL = engine.searchURL
        bad.keyword = "ddg"
        #expect(throws: SearchEngines.Problem.keywordTaken("DuckDuckGo")) { try SearchEngines.save(bad, in: &settings) }
        bad.keyword = "two words"
        #expect(throws: SearchEngines.Problem.keywordHasSpace) { try SearchEngines.save(bad, in: &settings) }
        // Edit keeps the place.
        var edited = saved
        edited.name = "Example 2"
        try SearchEngines.save(edited, in: &settings)
        #expect(settings.searchEngines?.last?.name == "Example 2" && settings.searchEngines?.count == SearchEngines.builtIn.count + 1)
    }

    @Test("Remove: never the last engine, never a default")
    func remove() {
        var settings = Settings()
        settings.searchEngineByProfile = [work.uuidString: "kagi"]
        #expect(SearchEngines.removalBlocked("google", in: settings, profiles: [work, home]) != nil)
        #expect(SearchEngines.removalBlocked("kagi", in: settings, profiles: [work, home]) != nil)
        #expect(SearchEngines.remove("youtube", in: &settings, profiles: [work, home]))
        #expect(!SearchEngines.list(settings).contains { $0.id == "youtube" })
        settings.searchEngines = [SearchEngines.builtIn[0]]
        settings.searchEngineByProfile = [:]
        #expect(!SearchEngines.remove("google", in: &settings, profiles: []))
    }
}
