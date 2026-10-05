import Foundation

/// Relevance bands, Chromium-like (0…1500; `macos-ui-stack.md` §5.2). Every
/// provider scores inside its band; the highest match overall is the top hit
/// (the Enter default), the rest are shown by group (spec §C).
public enum Relevance {
    /// An open tab or entry whose URL is exactly what was typed: switch to it
    /// rather than open a second copy (spec §C top hit "exact tab match").
    public static let exactEntry = 1450
    /// History that completes the input inline beats the verbatim URL
    /// (Chromium's HistoryURL inline band); 1410…1449.
    public static let inlineHistory = 1410...1449
    /// What you typed, when it is surely a URL.
    public static let verbatimURL = 1400
    /// What you typed, when it reads as a query: search for it.
    public static let verbatimSearch = 1300
    /// History by match quality and frecency (below the verbatim search so a
    /// query stays a query unless history completes it inline).
    public static let history = 600...1299
    /// Open tabs (Today, every space), by match quality and recency.
    public static let openTabs = 1000...1199
    /// Pinned entries and essentials (Chromium's bookmark band).
    public static let pinned = 900...1099
    /// The verbatim alternative that is not the top hit: the URL of
    /// "node.js", the search for "github.com". Kept in the cap regardless.
    public static let verbatimAlternative = 850
    /// Search suggestions.
    public static let suggest = 500...899
    /// Commands in `>` mode (they are the only rows there); in normal mode
    /// they score 400…700, below everything (`CommandsProvider`).
    public static let commands = 400...1300

    /// `fraction` (0…1) placed in `band`.
    public static func scaled(_ fraction: Double, in band: ClosedRange<Int>) -> Int {
        let clamped = min(1, max(0, fraction))
        return band.lowerBound + Int((Double(band.upperBound - band.lowerBound) * clamped).rounded())
    }
}

/// The palette's rows: the top hit first, then each group's matches by
/// relevance; at most `limit` rows.
public struct OmniboxResult: Hashable, Sendable {
    public static let limit = 8

    public private(set) var matches: [OmniboxMatch]
    /// The top hit's completion of the input (spec §C: history only).
    public private(set) var inlineCompletion: String?

    public init() {
        matches = []
        inlineCompletion = nil
    }

    public var isEmpty: Bool { matches.isEmpty }

    /// The scorer (one for every provider, spec §C): dedupe by normalised
    /// URL keeping the most relevant, the top hit by relevance, then the
    /// most relevant others up to the limit (rows that keep a slot first),
    /// shown in group order.
    public init(ranking candidates: [OmniboxMatch], input: OmniboxInput, limit: Int = OmniboxResult.limit) {
        // Stable order: relevance, then group, then the order providers gave.
        let ordered = candidates.enumerated().sorted { lhs, rhs in
            if lhs.element.relevance != rhs.element.relevance { return lhs.element.relevance > rhs.element.relevance }
            if lhs.element.group != rhs.element.group { return lhs.element.group < rhs.element.group }
            return lhs.offset < rhs.offset
        }.map(\.element)
        var seen: [String: Int] = [:]
        var unique: [OmniboxMatch] = []
        for match in ordered {
            guard let index = seen[match.dedupeKey] else {
                seen[match.dedupeKey] = unique.count
                unique.append(match)
                continue
            }
            // History naming a page that is open in an entry switches to that
            // entry (Chromium's tab match): "gi" completing to github.com
            // with a GitHub tab open selects the tab instead of a second copy.
            if case .switchToEntry = match.action, unique[index].provider == .history, case .navigate = unique[index].action {
                unique[index].action = match.action
                unique[index].spaceName = match.spaceName
            }
        }
        for match in ordered where match.keepsSlot {
            if let index = unique.firstIndex(where: { $0.dedupeKey == match.dedupeKey }) { unique[index].keepsSlot = true }
        }
        guard var top = unique.first, limit > 0 else {
            matches = []
            inlineCompletion = nil
            return
        }
        top.group = .topHit
        var rest = Array(unique.dropFirst())
        let reserved = rest.filter(\.keepsSlot).prefix(limit - 1)
        let free = max(0, limit - 1 - reserved.count)
        let chosenIDs = Set(reserved.map(\.id)).union(rest.filter { !$0.keepsSlot }.prefix(free).map(\.id))
        rest = rest.filter { chosenIDs.contains($0.id) }
        // Group order; within a group the relevance order above is kept (stable sort).
        rest.sort { $0.group < $1.group }
        let inline = input.preventsInlineCompletion || top.provider != .history ? nil : top.inlineCompletion
        // Inline text only ever completes the top hit.
        top.inlineCompletion = inline
        for index in rest.indices { rest[index].inlineCompletion = nil }
        matches = [top] + rest
        inlineCompletion = inline
    }

    /// ⇥ / ⇧⇥: the first row of the next (previous) group, wrapping (spec §C).
    public func groupStart(after index: Int, backwards: Bool = false) -> Int? {
        guard !matches.isEmpty else { return nil }
        let starts = matches.indices.filter { $0 == 0 || matches[$0].group != matches[$0 - 1].group }
        let current = matches.indices.contains(index) ? matches[index].group : matches[0].group
        let currentStart = starts.last { matches[$0].group == current } ?? 0
        guard let position = starts.firstIndex(of: currentStart) else { return starts.first }
        if backwards {
            // From inside a group, ⇧⇥ goes to that group's first row first.
            if index > currentStart { return currentStart }
            return starts[(position - 1 + starts.count) % starts.count]
        }
        return starts[(position + 1) % starts.count]
    }
}

/// Inline completion (spec §C: "inline host completion from history only";
/// the provider is 2.4b's history). The text the URL adds after the input,
/// when the input is a prefix of its host (scheme and "www." ignored) or of
/// the whole URL without its scheme.
public enum InlineCompletion {
    public static func suffix(completing input: String, with url: String) -> String? {
        let typed = input.lowercased()
        guard !typed.isEmpty, !typed.contains(where: \.isWhitespace) else { return nil }
        for candidate in candidates(for: url) where candidate.lowercased().hasPrefix(typed) && candidate.count > typed.count {
            return String(candidate.dropFirst(typed.count))
        }
        return nil
    }

    /// The URL's forms a user types: host (with and without "www."), then
    /// host + path, each without a trailing slash.
    private static func candidates(for url: String) -> [String] {
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else { return [] }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        var forms = [bare, host]
        if !path.isEmpty { forms += [bare + path, host + path] }
        return forms
    }
}

/// The pipeline: every provider's matches through the one scorer.
/// Asynchronous providers (2.4b's search suggest) deliver later; the palette
/// ranks the synchronous matches plus whatever has arrived with
/// `OmniboxResult(ranking:input:)`, so the rows only ever grow in place.
public struct Omnibox: Sendable {
    public var providers: [any OmniboxProvider]

    public init(providers: [any OmniboxProvider] = Omnibox.localProviders) {
        self.providers = providers
    }

    /// The providers that need nothing but the context (history comes from
    /// the engine's autocomplete, `EngineHistoryProvider`, since 3.5).
    public static let localProviders: [any OmniboxProvider] = [VerbatimProvider(), OpenTabsProvider(), PinnedProvider(),
                                                               SiteSearchProvider(), CommandsProvider()]

    /// Every provider's matches, unranked. Commands mode asks only the
    /// commands (an empty query lists them all); a site-search chip asks the
    /// verbatim search and history (spec §C). `excluded`: kinds another
    /// source answers (the engine's history on RoomCore, Phase 3.5).
    public func candidates(for input: OmniboxInput, in context: OmniboxContext, excluding excluded: Set<ProviderKind> = []) -> [OmniboxMatch] {
        var kinds: Set<ProviderKind>
        switch input.mode {
        case .commands: kinds = [.commands]
        case .siteSearch: kinds = [.verbatim, .history]
        case .normal: kinds = Set(ProviderKind.allCases)
        }
        kinds.subtract(excluded)
        guard !input.isEmpty || input.mode == .commands else { return [] }
        return providers.filter { kinds.contains($0.kind) }.flatMap { $0.matches(for: input, in: context) }
    }

    public func result(for input: OmniboxInput, in context: OmniboxContext) -> OmniboxResult {
        OmniboxResult(ranking: candidates(for: input, in: context), input: input)
    }
}
