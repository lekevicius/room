import Foundation
import Model

/// History (spec §C group 4): the FTS5 index ranked by frecency and match
/// quality, and the only source of inline completion. It queries its
/// database on every keystroke (the context snapshot does not hold history).
///
/// Inline completion completes a host ("gi" → github.com) or, once the
/// typed text has a path, a whole URL, from the most frecent candidate that
/// the user typed before or visited a few times (Chromium's HistoryURL
/// provider inlines typed URLs; one visit through a link is not enough).
public struct HistoryProvider: OmniboxProvider {
    public let history: History
    /// Rows fetched per keystroke before scoring.
    public var fetchLimit = OmniboxResult.limit

    public init(history: History) {
        self.history = history
    }

    public var kind: ProviderKind { .history }

    /// Visits it takes without a typed one before a URL completes inline.
    static let inlineVisits = 3
    /// The decayed visit weight at which frecency counts as half its share of the score.
    static let frecencyHalf = 4.0

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        let text = input.trimmed
        guard !text.isEmpty else { return [] }
        switch input.mode {
        case .commands:
            return []
        case .siteSearch(let site):
            let rows = (try? history.search(text, limit: fetchLimit * 3)) ?? []
            return rows.filter { $0.host == site.host || $0.host.hasSuffix("." + site.host) }.prefix(fetchLimit).map { match(for: $0, text: text, context: context) }
        case .normal:
            break
        }
        let rows = (try? history.search(text, limit: fetchLimit)) ?? []
        var matches = rows.map { match(for: $0, text: text, context: context) }
        // After a deletion nothing completes, and nothing takes the inline band
        // either: the verbatim row is the top hit again.
        if !input.preventsInlineCompletion, let inline = inlineMatch(for: text, rows: rows, context: context) {
            matches.removeAll { $0.dedupeKey == inline.dedupeKey }
            matches.append(inline)
        }
        return matches
    }

    /// The most frecent pages, for ⌘Y with nothing typed (shortcuts.md: History is the palette's history group until Chapter 3).
    public func recentMatches(in context: OmniboxContext, limit: Int = OmniboxResult.limit) -> [OmniboxMatch] {
        let rows = (try? history.mostFrecent(limit: limit)) ?? []
        return rows.enumerated().map { index, row in
            var match = match(for: row, text: "", context: context)
            match.relevance = Relevance.history.upperBound - index
            return match
        }
    }

    // MARK: Rows

    private func match(for row: HistoryRow, text: String, context: OmniboxContext) -> OmniboxMatch {
        let terms = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let display = VerbatimProvider.displayURL(row.url)
        let keys = EntryKeys(title: row.title ?? "", urls: [row.url])
        // The index matched the scheme or a word in the query string: a weak match.
        let quality = EntryMatching.quality(terms: terms, keys: keys) ?? 0.3
        let relevance = Relevance.scaled(quality * 0.6 + frecencyFraction(row.frecency, now: context.now) * 0.4, in: Relevance.history)
        let title = row.title.flatMap { $0.isEmpty ? nil : $0 } ?? display
        return OmniboxMatch(id: "history:\(row.url)", provider: .history, relevance: relevance, action: .navigate(url: row.url),
                            title: title, detail: title == display ? nil : display, icon: .site(url: row.url), isDeletable: true)
    }

    /// 0…1: the decayed visit weight `w` as w / (w + frecencyHalf).
    func frecencyFraction(_ stored: Double, now: Date) -> Double {
        let weight = Frecency.current(stored, at: now)
        return weight / (weight + Self.frecencyHalf)
    }

    // MARK: Inline completion

    private func inlineMatch(for text: String, rows: [HistoryRow], context: OmniboxContext) -> OmniboxMatch? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let typed = Self.stripped(text.lowercased())
        guard !typed.isEmpty else { return nil }
        if !typed.contains("/") {
            // The host: the site root, at the scheme and "www." its most frecent page uses.
            // The most frecent host the user typed or visited often enough (a more
            // frecent one reached only through links does not block it).
            guard let host = (try? history.hosts(prefix: typed, limit: 5))?
                    .first(where: { $0.typedCount > 0 || $0.visitCount >= Self.inlineVisits }),
                  let components = URLComponents(string: host.bestURL), let scheme = components.scheme, let name = components.host,
                  case let url = "\(scheme)://\(name)/",
                  let completion = InlineCompletion.suffix(completing: text, with: url)
            else { return nil }
            return OmniboxMatch(id: "history:host:\(host.host)", provider: .history,
                                relevance: Relevance.scaled(frecencyFraction(host.frecency, now: context.now), in: Relevance.inlineHistory),
                                action: .navigate(url: url), title: VerbatimProvider.displayURL(url), icon: .site(url: url),
                                inlineCompletion: completion, isDeletable: true)
        }
        // A path: the most frecent URL it is a prefix of.
        for row in rows where row.typedCount > 0 || row.visitCount >= Self.inlineVisits {
            guard let completion = InlineCompletion.suffix(completing: text, with: row.url) else { continue }
            var match = match(for: row, text: text, context: context)
            match.relevance = Relevance.scaled(frecencyFraction(row.frecency, now: context.now), in: Relevance.inlineHistory)
            match.inlineCompletion = completion
            return match
        }
        return nil
    }

    /// Typed text without a scheme or "www." (what host keys and bare URLs start with).
    static func stripped(_ text: String) -> String {
        var typed = text
        for prefix in ["https://", "http://"] where typed.hasPrefix(prefix) {
            typed.removeFirst(prefix.count)
            break
        }
        if typed.hasPrefix("www.") { typed.removeFirst(4) }
        return typed
    }

    /// The host a deletable history match stands for, when it is an inline host match.
    public static func deletedHost(for match: OmniboxMatch) -> String? {
        let prefix = "history:host:"
        return match.id.hasPrefix(prefix) ? String(match.id.dropFirst(prefix.count)) : nil
    }
}
