import Foundation
import Model

/// A source of suggestions. Synchronous and pure over the input and the
/// context snapshot; 2.4b's history provider holds its database reader,
/// and search suggest delivers asynchronously (see `Omnibox`).
public protocol OmniboxProvider: Sendable {
    var kind: ProviderKind { get }
    func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch]
}

/// What you typed (spec §C top hit / group 5): the URL it fixes up to and a
/// search for it, one as the top hit and the other as the alternative.
public struct VerbatimProvider: OmniboxProvider {
    public init() {}

    public var kind: ProviderKind { .verbatim }

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        let text = input.trimmed
        guard !text.isEmpty else { return [] }
        if case .siteSearch(let site) = input.mode {
            // The chip's site: always a search there (spec §C "Search YouTube").
            return [OmniboxMatch(id: "verbatim:search", provider: .verbatim, relevance: Relevance.verbatimSearch,
                                 action: .search(query: text, url: site.engine.searchURL(for: text)), title: text,
                                 detail: "Search \(site.name)", icon: .search, keepsSlot: true)]
        }
        let engine = context.searchEngine
        func search(_ query: String, relevance: Int) -> OmniboxMatch {
            OmniboxMatch(id: "verbatim:search", provider: .verbatim, relevance: relevance,
                         action: .search(query: query, url: engine.searchURL(for: query)), title: query,
                         detail: "Search \(engine.name)", icon: .search, keepsSlot: true)
        }
        func navigate(_ url: String, relevance: Int) -> OmniboxMatch {
            OmniboxMatch(id: "verbatim:url", provider: .verbatim, relevance: relevance, action: .navigate(url: url),
                         title: Self.displayURL(url), detail: "Open", icon: .url)
        }
        switch URLFixup.classify(text) {
        case .query(let query):
            guard !query.isEmpty else { return [] }
            return [search(query, relevance: Relevance.verbatimSearch)]
        case .url(let url, confident: true):
            return [navigate(url, relevance: Relevance.verbatimURL), search(text, relevance: Relevance.verbatimAlternative)]
        case .url(let url, confident: false):
            return [search(text, relevance: Relevance.verbatimSearch), navigate(url, relevance: Relevance.verbatimAlternative)]
        }
    }

    /// The URL without "https://" and a lone trailing slash (row titles).
    static func displayURL(_ url: String) -> String {
        var text = url
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        if text.hasSuffix("/"), text.dropLast().contains("/") == false { text.removeLast() }
        return text
    }
}

/// Today tabs in every space (spec §C group 2: icon, title, space chip;
/// Enter switches, ⌘Enter opens a copy).
public struct OpenTabsProvider: OmniboxProvider {
    public init() {}

    public var kind: ProviderKind { .openTabs }

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        EntryMatching.matches(for: input, in: context, provider: .openTabs, kinds: [.today], band: Relevance.openTabs,
                              exactRelevance: Relevance.exactEntry)
    }
}

/// Pinned entries in every space and the profile's essentials (spec §C
/// group 3: Enter switches to the space and selects; ⌘Enter opens a copy).
public struct PinnedProvider: OmniboxProvider {
    public init() {}

    public var kind: ProviderKind { .pinned }

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        EntryMatching.matches(for: input, in: context, provider: .pinned, kinds: [.pinned, .essential], band: Relevance.pinned,
                              exactRelevance: Relevance.exactEntry - 10)
    }
}

/// Matching typed text against entries: every word of the input must occur
/// in the title or the URL; the score rewards host prefixes, then title
/// prefixes and word starts, then plain substrings, plus recency.
enum EntryMatching {
    static func matches(for input: OmniboxInput, in context: OmniboxContext, provider: ProviderKind, kinds: Set<EntryKind>,
                        band: ClosedRange<Int>, exactRelevance: Int) -> [OmniboxMatch] {
        let text = input.trimmed
        let terms = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let typedURL: String? = if case .url(let url, _) = URLFixup.classify(text) { URLNormalization.normalized(url) } else { nil }
        // One byte search per word rejects the entries it is not in at all (most
        // of them); a single letter matches word starts only.
        let needles = terms.map { Array($0.utf8) }
        let initial: Character? = terms.count == 1 && terms[0].count == 1 ? terms[0].first : nil
        var matches: [OmniboxMatch] = []
        // Indices, not `zip`: its iterator was half of a one-letter query's entry matching in Debug builds (2.6a profile).
        let entries = context.entries, allKeys = context.keys
        for index in 0..<min(entries.count, allKeys.count) {
            let keys = allKeys[index]
            if typedURL == nil, let initial, !keys.initials.contains(initial) { continue }
            let entry = entries[index]
            guard kinds.contains(entry.kind), entry.id != context.currentEntryID else { continue }
            let relevance: Int
            if let typedURL, keys.normalizedURLs.contains(typedURL) {
                relevance = exactRelevance
            } else {
                if let initial, !keys.initials.contains(initial) { continue }
                guard needles.allSatisfy(keys.haystackContains), let quality = quality(terms: terms, keys: keys) else { continue }
                let recency = recencyFraction(entry.lastActiveAt, now: context.now)
                let space = entry.spaceID == nil || entry.spaceID == context.activeSpaceID ? 1.0 : 0.0
                relevance = Relevance.scaled(quality * 0.85 + recency * 0.1 + space * 0.05, in: band)
            }
            let otherSpace = entry.spaceID != nil && entry.spaceID != context.activeSpaceID
            matches.append(OmniboxMatch(id: "\(provider.rawValue):\(entry.id)", provider: provider, relevance: relevance,
                                        action: .switchToEntry(id: entry.id, space: entry.spaceID, url: entry.url),
                                        title: entry.title, detail: entry.url.map(VerbatimProvider.displayURL), icon: .entry(entry.id),
                                        spaceName: otherSpace ? entry.spaceName : nil,
                                        normalizedURL: entry.url == nil ? nil : keys.normalizedURLs.first))
        }
        return matches
    }

    /// 0…1, or `nil` when some word matches nothing. The mean over words of
    /// the best place each one matches.
    static func quality(terms: [String], keys: EntryKeys) -> Double? {
        let title = keys.title, hosts = keys.hosts, bareURLs = keys.bareURLs
        var total = 0.0
        for term in terms {
            let score: Double
            if hosts.contains(where: { $0.hasPrefix(term) }) {
                score = 1
            } else if title.hasPrefix(term) {
                score = 0.9
            } else if isWordStart(term, in: title) || hosts.contains(where: { isWordStart(term, in: $0, separators: ".-") }) {
                score = 0.75
            } else if bareURLs.contains(where: { $0.contains(term) }) {
                score = 0.55
            } else if title.contains(term) {
                score = 0.5
            } else {
                return nil
            }
            total += score
        }
        return total / Double(terms.count)
    }

    private static func isWordStart(_ term: String, in text: String, separators: String = " -_/.:|·—") -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: term, range: searchStart..<text.endIndex) {
            if range.lowerBound == text.startIndex || separators.contains(text[text.index(before: range.lowerBound)]) { return true }
            searchStart = text.index(after: range.lowerBound)
        }
        return false
    }

    /// 1 for an entry used just now, halving every 24 hours; 0 if never used.
    static func recencyFraction(_ date: Date?, now: Date) -> Double {
        guard let date else { return 0 }
        let days = max(0, now.timeIntervalSince(date)) / 86_400
        return pow(0.5, days)
    }
}
