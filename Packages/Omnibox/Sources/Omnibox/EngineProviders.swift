import Foundation
import Engine
import Model

// Phase 3.5: on an engine with an omnibox (RoomCore), Chrome's history and
// search suggestions feed the palette. The engine's matches are mapped into
// Room's bands here; Room's scorer (`OmniboxResult`), groups, commands and
// site search stay as they are. Chrome's relevance is not Room's: matches are
// placed in a band by their rank inside the provider, and only the best
// history match Chrome allows to be default may take the inline band (B-65).

/// Which of the engine's providers a keystroke asks (ROADMAP 3.5 task 2):
/// the profile's own data always; the default engine's suggestions only
/// while the suggestions switch is on (CLAUDE.md: the switch is the only
/// thing that may turn a suggestion request on), never for commands or a
/// site-search chip, and never for text that is surely a URL (it is a page,
/// not a query: 2.4b's rule).
public enum EngineProviderChoice {
    public static func providers(for input: OmniboxInput, suggestionsEnabled: Bool) -> AutocompleteProviders {
        var providers = AutocompleteProviders.local
        guard suggestionsEnabled, input.mode == .normal, !input.isEmpty else { return providers }
        if case .url(_, confident: true) = URLFixup.classify(input.trimmed) { return providers }
        providers.insert(.search)
        return providers
    }
}

/// The engine's history matches (Chrome's HistoryQuick and HistoryURL
/// providers: typed and visited pages) as the palette's history group: by
/// rank into `Relevance.history`, the engine's inline completion into
/// `Relevance.inlineHistory`, a page open in an entry as a switch to it.
public enum EngineHistoryProvider {
    /// History rows kept per keystroke.
    public static let limit = OmniboxResult.limit

    /// The host a deletable history match stands for, when it is an inline host match
    /// (its id is `history:host:<host>`; deleting it deletes the host's history).
    public static func deletedHost(for match: OmniboxMatch) -> String? {
        let prefix = "history:host:"
        return match.id.hasPrefix(prefix) ? String(match.id.dropFirst(prefix.count)) : nil
    }

    public static func matches(from engine: [AutocompleteMatch], input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        guard !input.isEmpty else { return [] }
        let siteHost: String?
        switch input.mode {
        case .commands: return []
        case .siteSearch(let site): siteHost = site.host
        case .normal: siteHost = nil
        }
        var history = engine.enumerated().filter { _, match in
            guard match.kind.isHistory, match.destinationURL != nil else { return false }
            guard let siteHost else { return true }
            let host = bare(match.destinationURL?.host() ?? "")
            return host == siteHost || host.hasSuffix("." + siteHost)
        }
        history = Array(history.prefix(limit))
        // The best history match allowed to be default completes inline (B-65, the user 2026-10-18:
        // with suggestions on, Chrome's default is often its verbatim search, which hid the completion),
        // only in normal mode with inline completion allowed.
        let inlineOffset: Int? = if input.mode == .normal, !input.preventsInlineCompletion {
            history.first { completes(input.text, $0.element) }?.offset
        } else { nil }
        return history.enumerated().map { rank, element in
            let (offset, engineMatch) = element
            let url = engineMatch.destinationURL!.absoluteString
            let display = VerbatimProvider.displayURL(url)
            let title = engineMatch.description.isEmpty ? display : engineMatch.description
            let isInline = offset == inlineOffset
            // A site root that completes inline stands for its host (deleting it deletes the host, 2.4b's rule).
            let hostRoot = isInline ? hostRootKey(engineMatch.destinationURL!) : nil
            var match = OmniboxMatch(id: hostRoot.map { "history:host:\($0)" } ?? "history:\(url)", provider: .history,
                                     relevance: rankedRelevance(rank, count: limit, in: Relevance.history),
                                     action: action(for: engineMatch, url: url, context: context),
                                     title: title, detail: title == display ? nil : display, icon: .site(url: url),
                                     isDeletable: engineMatch.isDeletable)
            if isInline {
                // Chrome's relevance of a default URL match runs ~1100…1600: placed in the inline band.
                match.relevance = Relevance.scaled(Double(engineMatch.relevance - 1100) / 500, in: Relevance.inlineHistory)
                match.inlineCompletion = engineMatch.inlineCompletion
            }
            return match
        }
    }

    /// Whether `match` may complete `text` inline: allowed to be default, and its completion made for this
    /// text (Chrome carries matches over from the previous keystroke while its providers run; their
    /// completions belong to the old text: 5.5a's IME run put "日本.0.0.1:8770" in the field).
    static func completes(_ text: String, _ match: AutocompleteMatch) -> Bool {
        guard match.allowedToBeDefault, !match.inlineCompletion.isEmpty else { return false }
        return match.fillIntoEdit.isEmpty || (text + match.inlineCompletion).lowercased() == match.fillIntoEdit.lowercased()
    }

    /// ⌘Y with nothing typed: the engine's history pages (most recent first), in its order.
    public static func recentMatches(from entries: [HistoryEntry], limit: Int = OmniboxResult.limit) -> [OmniboxMatch] {
        entries.prefix(limit).enumerated().map { index, entry in
            let url = entry.url.absoluteString
            let display = VerbatimProvider.displayURL(url)
            let title = entry.title.isEmpty ? display : entry.title
            return OmniboxMatch(id: "history:\(url)", provider: .history, relevance: Relevance.history.upperBound - index,
                                action: .navigate(url: url), title: title, detail: title == display ? nil : display,
                                icon: .site(url: url), isDeletable: true)
        }
    }

    /// The rank's place in `band`: the first at the top, then evenly down over `count` slots.
    static func rankedRelevance(_ rank: Int, count: Int, in band: ClosedRange<Int>) -> Int {
        Relevance.scaled(1 - Double(rank) / Double(max(1, count)), in: band)
    }

    /// A page the engine sees open in a tab, and that is an entry the palette
    /// can switch to: "Switch to Tab" (the entry, found by its normalised URL).
    static func action(for match: AutocompleteMatch, url: String, context: OmniboxContext) -> MatchAction {
        guard match.hasTabMatch else { return .navigate(url: url) }
        let key = URLNormalization.normalized(url)
        for index in 0..<min(context.entries.count, context.keys.count) where context.keys[index].normalizedURLs.contains(key) {
            let entry = context.entries[index]
            guard entry.id != context.currentEntryID else { continue }
            return .switchToEntry(id: entry.id, space: entry.spaceID, url: entry.url)
        }
        return .navigate(url: url)
    }

    static func hostRootKey(_ url: URL) -> String? {
        guard let host = url.host(), url.path().isEmpty || url.path() == "/", url.query() == nil else { return nil }
        return bare(host)
    }

    static func bare(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}

/// The engine's search suggestions (Chrome's SearchProvider, asked only while
/// the switch is on) as the palette's search group: by rank into
/// `Relevance.suggest`, at most `SuggestClient.limit`. What-you-typed is
/// Room's own verbatim row and is left out.
public enum EngineSuggestProvider {
    public static func matches(from engine: [AutocompleteMatch], input: OmniboxInput, engine searchEngine: SearchEngine) -> [OmniboxMatch] {
        guard input.mode == .normal, !input.isEmpty else { return [] }
        let typed = input.trimmed.lowercased()
        let suggestions = engine.filter { match in
            guard match.provider == .search else { return false }
            switch match.kind {
            case .searchSuggest, .searchHistory: return match.contents.lowercased() != typed
            case .navSuggest: return match.destinationURL != nil
            default: return false
            }
        }.prefix(SuggestClient.limit)
        return suggestions.enumerated().map { rank, match in
            let relevance = EngineHistoryProvider.rankedRelevance(rank, count: SuggestClient.limit, in: Relevance.suggest)
            if match.kind == .navSuggest, let url = match.destinationURL?.absoluteString {
                return OmniboxMatch(id: "suggest:\(url)", provider: .suggest, relevance: relevance, action: .navigate(url: url),
                                    title: match.contents, icon: .url)
            }
            let url = match.destinationURL?.absoluteString ?? searchEngine.searchURL(for: match.contents)
            return OmniboxMatch(id: "suggest:\(match.contents)", provider: .suggest, relevance: relevance,
                                action: .search(query: match.contents, url: url), title: match.contents, icon: .search)
        }
    }
}

extension SearchEngine {
    /// The engine's omnibox form of this engine (`{searchTerms}` templates);
    /// `suggestURL` replaces the endpoint (DEBUG: the tour's logging server).
    public func engineTemplate(suggestURL override: String? = nil) -> SearchEngineTemplate {
        func chrome(_ template: String) -> String { template.replacingOccurrences(of: "{query}", with: "{searchTerms}") }
        return SearchEngineTemplate(name: name, keyword: "room-\(id)" + (override == nil ? "" : "-debug"), searchURL: chrome(template),
                                    suggestURL: override ?? suggestTemplate.map(chrome))
    }
}
