import Foundation
import Model

/// Settings ▸ Search (ROADMAP 4.4a task 3, spec §C): the engines list (name,
/// keyword, search URL, optional suggestions URL), the default per profile,
/// and the keywords the palette searches with (`yt` + Tab). One list: any
/// engine can be a profile's default, and every engine's keyword is a site
/// search. Pure functions over `Settings`.
public enum SearchEngines {
    /// What `{searchTerms}` looks like to the user (Chrome's and Firefox's `%s`).
    public static let placeholder = "%s"
    static let terms = "{searchTerms}"

    /// Room's engines until the user edits the list: the three Settings offered
    /// since 2.8 and the palette's site searches of 2.4b.
    public static let builtIn: [SearchEngineSetting] = [
        SearchEngineSetting(id: "google", name: "Google", keyword: "google", searchURL: "https://www.google.com/search?q={searchTerms}",
                            suggestURL: "https://suggestqueries.google.com/complete/search?client=firefox&q={searchTerms}"),
        SearchEngineSetting(id: "duckduckgo", name: "DuckDuckGo", keyword: "ddg", searchURL: "https://duckduckgo.com/?q={searchTerms}",
                            suggestURL: "https://duckduckgo.com/ac/?q={searchTerms}&type=list"),
        SearchEngineSetting(id: "kagi", name: "Kagi", keyword: "kagi", searchURL: "https://kagi.com/search?q={searchTerms}",
                            suggestURL: "https://kagi.com/api/autosuggest?q={searchTerms}"),
        SearchEngineSetting(id: "youtube", name: "YouTube", keyword: "yt", searchURL: "https://www.youtube.com/results?search_query={searchTerms}"),
        SearchEngineSetting(id: "wikipedia", name: "Wikipedia", keyword: "wiki",
                            searchURL: "https://en.wikipedia.org/wiki/Special:Search?search={searchTerms}"),
        SearchEngineSetting(id: "github", name: "GitHub", keyword: "gh", searchURL: "https://github.com/search?q={searchTerms}"),
        SearchEngineSetting(id: "maps", name: "Google Maps", keyword: "maps", searchURL: "https://www.google.com/maps/search/{searchTerms}"),
    ]

    public static func list(_ settings: Settings) -> [SearchEngineSetting] {
        let stored = settings.searchEngines ?? []
        return stored.isEmpty ? builtIn : stored
    }

    /// The engine id `profile` searches with: its own choice, else the first-run
    /// choice, else the list's first engine (an id that left the list falls through).
    public static func defaultID(for profile: UUID?, in settings: Settings) -> String {
        let engines = list(settings)
        for candidate in [profile.flatMap { settings.searchEngineByProfile[$0.uuidString] }, settings.searchEngine] {
            if let candidate, engines.contains(where: { $0.id == candidate }) { return candidate }
        }
        return engines[0].id
    }

    public static func defaultEngine(for profile: UUID?, in settings: Settings) -> SearchEngineSetting {
        let id = defaultID(for: profile, in: settings)
        return list(settings).first { $0.id == id } ?? list(settings)[0]
    }

    /// The palette's engine (`{query}` templates) for `profile`.
    public static func engine(for profile: UUID?, in settings: Settings) -> SearchEngine {
        SearchEngine(defaultEngine(for: profile, in: settings))
    }

    /// Every engine with a keyword, as the palette's site searches (keyword + Tab).
    public static func siteSearches(_ settings: Settings) -> [SiteSearch] {
        list(settings).filter { !$0.keyword.isEmpty }.map { engine in
            let host = URL(string: engine.searchURL.replacingOccurrences(of: terms, with: "x"))?.host()?.lowercased() ?? ""
            return SiteSearch(keyword: engine.keyword, name: engine.name, template: SearchEngine.queryTemplate(engine.searchURL),
                              host: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
        }
    }

    // MARK: %s, as the user sees it

    public static func displayURL(_ stored: String) -> String { stored.replacingOccurrences(of: terms, with: placeholder) }
    public static func storedURL(_ display: String) -> String {
        display.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: placeholder, with: terms)
    }

    // MARK: Editing

    public enum Problem: Error, Equatable {
        case emptyName, emptyKeyword, keywordHasSpace, keywordTaken(String), urlInvalid, urlNeedsPlaceholder, suggestURLInvalid

        public var message: String {
            switch self {
            case .emptyName: "Give the engine a name."
            case .emptyKeyword: "Give the engine a keyword: you type it, then Tab, in the palette."
            case .keywordHasSpace: "A keyword is one word."
            case .keywordTaken(let name): "\(name) already has this keyword."
            case .urlInvalid: "The search URL must start with https:// or http://."
            case .urlNeedsPlaceholder: "Put %s in the search URL where the search terms go."
            case .suggestURLInvalid: "The suggestions URL must be an http(s) URL with %s, or empty."
            }
        }
    }

    /// Checks `engine` (URLs in stored form) against `list`, `engine.id` excluded.
    public static func validate(_ engine: SearchEngineSetting, in list: [SearchEngineSetting]) -> Problem? {
        let name = engine.name.trimmingCharacters(in: .whitespaces)
        let keyword = engine.keyword.trimmingCharacters(in: .whitespaces).lowercased()
        if name.isEmpty { return .emptyName }
        if keyword.isEmpty { return .emptyKeyword }
        if keyword.contains(where: \.isWhitespace) { return .keywordHasSpace }
        if let other = list.first(where: { $0.id != engine.id && $0.keyword.lowercased() == keyword }) { return .keywordTaken(other.name) }
        func isWeb(_ text: String) -> Bool {
            guard let url = URL(string: text.replacingOccurrences(of: terms, with: "x")), let scheme = url.scheme?.lowercased() else { return false }
            return (scheme == "https" || scheme == "http") && url.host() != nil
        }
        if !isWeb(engine.searchURL) { return .urlInvalid }
        if !engine.searchURL.contains(terms) { return .urlNeedsPlaceholder }
        if let suggest = engine.suggestURL, !suggest.isEmpty, !(isWeb(suggest) && suggest.contains(terms)) { return .suggestURLInvalid }
        return nil
    }

    /// The engine as stored: trimmed, the keyword lowercased, an empty suggestions URL as none.
    public static func normalized(_ engine: SearchEngineSetting) -> SearchEngineSetting {
        var copy = engine
        copy.name = engine.name.trimmingCharacters(in: .whitespaces)
        copy.keyword = engine.keyword.trimmingCharacters(in: .whitespaces).lowercased()
        copy.searchURL = engine.searchURL.trimmingCharacters(in: .whitespaces)
        let suggest = engine.suggestURL?.trimmingCharacters(in: .whitespaces) ?? ""
        copy.suggestURL = suggest.isEmpty ? nil : suggest
        return copy
    }

    /// Adds `engine`, or replaces the one with its id. Throws its `Problem`.
    public static func save(_ engine: SearchEngineSetting, in settings: inout Settings) throws(Problem) {
        let engine = normalized(engine)
        var engines = list(settings)
        if let problem = validate(engine, in: engines) { throw problem }
        if let index = engines.firstIndex(where: { $0.id == engine.id }) {
            engines[index] = engine
        } else {
            engines.append(engine)
        }
        settings.searchEngines = engines
    }

    /// Why `id` cannot be removed (the last engine, or a profile's default), or nil.
    public static func removalBlocked(_ id: String, in settings: Settings, profiles: [UUID]) -> String? {
        let engines = list(settings)
        if engines.count <= 1 { return "Room needs one search engine." }
        let defaults = Set(profiles.map { defaultID(for: $0, in: settings) } + [defaultID(for: nil, in: settings)])
        if defaults.contains(id) { return "It is a default: choose another default first." }
        return nil
    }

    @discardableResult
    public static func remove(_ id: String, in settings: inout Settings, profiles: [UUID]) -> Bool {
        guard removalBlocked(id, in: settings, profiles: profiles) == nil else { return false }
        settings.searchEngines = list(settings).filter { $0.id != id }
        return true
    }

    /// A new engine's id ("custom-…"), never a built-in's.
    public static func newID() -> String { "custom-" + UUID().uuidString.prefix(8).lowercased() }
}

extension SearchEngine {
    /// The palette's engine for a Settings engine.
    public init(_ setting: SearchEngineSetting) {
        self.init(id: setting.id, name: setting.name, template: Self.queryTemplate(setting.searchURL),
                  suggestTemplate: setting.suggestURL.map(Self.queryTemplate))
    }

    static func queryTemplate(_ stored: String) -> String { stored.replacingOccurrences(of: SearchEngines.terms, with: "{query}") }
}
