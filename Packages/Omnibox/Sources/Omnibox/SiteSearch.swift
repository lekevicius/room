import Foundation

/// A site-search keyword (spec §C): `yt` + Tab puts a "YouTube" chip in the
/// field and Enter searches YouTube. Settings ▸ Search will manage the list
/// (Chapter 4.4); until then these defaults.
public struct SiteSearch: Hashable, Sendable, Identifiable {
    public var keyword: String
    /// The site's search page (name and query template).
    public var engine: SearchEngine
    /// The site's host key (lowercased, no "www."): history rows on it are
    /// offered while the chip is shown.
    public var host: String

    public var id: String { keyword }
    public var name: String { engine.name }

    public init(keyword: String, name: String, template: String, host: String) {
        self.keyword = keyword.lowercased()
        engine = SearchEngine(name: name, template: template)
        self.host = host
    }

    /// Keywords of two letters or more that are not common words, so Tab
    /// after them rarely meant "next group".
    public static let defaults: [SiteSearch] = [
        SiteSearch(keyword: "yt", name: "YouTube", template: "https://www.youtube.com/results?search_query={query}", host: "youtube.com"),
        SiteSearch(keyword: "wiki", name: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search={query}",
                   host: "en.wikipedia.org"),
        SiteSearch(keyword: "gh", name: "GitHub", template: "https://github.com/search?q={query}", host: "github.com"),
        SiteSearch(keyword: "maps", name: "Google Maps", template: "https://www.google.com/maps/search/{query}", host: "google.com"),
        SiteSearch(keyword: "ddg", name: "DuckDuckGo", template: "https://duckduckgo.com/?q={query}", host: "duckduckgo.com"),
    ]

    /// The keyword the field's text names exactly (Tab then enters its mode).
    public static func matching(_ text: String, in list: [SiteSearch]) -> SiteSearch? {
        let typed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !typed.isEmpty else { return nil }
        return list.first { $0.keyword == typed }
    }
}

/// The hint row for a typed keyword ("Search YouTube — press Tab"), in the
/// search group under the verbatim search; Enter on it enters the mode too.
public struct SiteSearchProvider: OmniboxProvider {
    public init() {}

    public var kind: ProviderKind { .verbatim }

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        guard input.mode == .normal, let site = SiteSearch.matching(input.text, in: context.siteSearches) else { return [] }
        return [OmniboxMatch(id: "sitesearch:\(site.keyword)", provider: .verbatim, relevance: Relevance.verbatimAlternative - 1,
                             action: .enterSiteSearch(keyword: site.keyword), title: "Search \(site.name)", detail: "Press Tab",
                             icon: .search, keepsSlot: true)]
    }
}
