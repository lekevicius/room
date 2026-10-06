import Foundation

/// Space routing (spec §B), as pure functions: which space a link opens in.
///
/// Matching: rules are tried in `position` order, disabled ones skipped, and
/// the first match wins. `contains` looks for the pattern in the full URL
/// string ignoring case; `equals` compares the URL's host with the pattern
/// (ignoring case and a leading "www." on either side; a pattern typed as a
/// URL counts by its host); `regex` runs `NSRegularExpression` over the full
/// URL string (no options: `(?i)` in the pattern for case-insensitive). An
/// invalid regex is refused at entry (`validate`) and never evaluated: a rule
/// that fails to compile here matches nothing.
public enum RoutingRules {
    /// Why a pattern cannot be saved; `message` is the inline error text.
    public enum PatternError: Error, Hashable, Sendable {
        case empty
        case invalidRegex(String)

        public var message: String {
            switch self {
            case .empty: "Enter a pattern."
            case .invalidRegex(let detail): "Not a valid regular expression (\(detail))."
            }
        }
    }

    /// `nil` when `pattern` can be saved for `match`.
    public static func validate(_ match: RoutingMatch, pattern: String) -> PatternError? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard match == .regex else { return nil }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return .invalidRegex(error.localizedDescription.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
        }
    }

    /// A rule set ready to evaluate: the enabled rules in position order,
    /// each regex compiled once (a pattern that does not compile is dropped).
    public struct Evaluator {
        private let compiled: [(rule: RoutingRule, regex: NSRegularExpression?)]

        public init(_ rules: [RoutingRule]) {
            compiled = rules.filter(\.enabled).sorted { $0.position < $1.position }.compactMap { rule in
                guard RoutingRules.validate(rule.match, pattern: rule.pattern) == nil else { return nil }
                guard rule.match == .regex else { return (rule, nil) }
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return nil }
                return (rule, regex)
            }
        }

        /// The first enabled rule matching `url`, or `nil`; with `spaces`,
        /// only rules whose target is one of them.
        public func firstMatch(_ url: String, in spaces: Set<UUID>? = nil) -> RoutingRule? {
            compiled.first { item in
                (spaces?.contains(item.rule.targetSpaceID) ?? true) && RoutingRules.matches(item.rule, url: url, regex: item.regex)
            }?.rule
        }
    }

    /// The first enabled rule matching `url` in position order.
    public static func firstMatch(_ rules: [RoutingRule], url: String) -> RoutingRule? {
        Evaluator(rules).firstMatch(url)
    }

    static func matches(_ rule: RoutingRule, url: String, regex: NSRegularExpression?) -> Bool {
        switch rule.match {
        case .contains:
            return url.range(of: rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) != nil
        case .equals:
            guard let host = hostKey(of: url) else { return false }
            return host == patternHost(rule.pattern)
        case .regex:
            guard let regex else { return false }
            return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
    }

    /// The URL's host, lowercased, without a leading "www.".
    public static func hostKey(of url: String) -> String? {
        guard let host = URL(string: url)?.host(percentEncoded: false), !host.isEmpty else { return nil }
        return stripWWW(host.lowercased())
    }

    /// An `equals` pattern as a host: "www.Example.com", "example.com/" and
    /// "https://example.com/x" all mean "example.com".
    static func patternHost(_ pattern: String) -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains("://"), let host = hostKey(of: trimmed) { return host }
        let bare = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        return stripWWW(bare)
    }

    private static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: Evaluation

    /// Where a link comes from.
    public enum Origin: Hashable, Sendable {
        /// Another app (the URL inbox: `open`, AppleScript, the default browser).
        case external
        /// A page in `space` opening a new tab (⌘-click, a popup, `target=_blank`,
        /// the context menu's Open in New Tab). Peek and in-place navigations
        /// never ask.
        case page(space: UUID)
    }

    /// Why the decision named its space.
    public enum Reason: Hashable, Sendable {
        /// A rule matched.
        case rule(UUID)
        /// External, no rule: Settings ▸ Links' chosen space.
        case chosenDefault
        /// External, no rule: the most recent space.
        case mostRecentSpace
        /// From a page: routing between spaces is off, or no rule moves it.
        case sourceSpace
    }

    public struct Decision: Hashable, Sendable {
        public var space: UUID
        public var reason: Reason
        /// A link from a page goes to another space than its own.
        public var moved: Bool

        public init(space: UUID, reason: Reason, moved: Bool) {
            self.space = space
            self.reason = reason
            self.moved = moved
        }
    }

    /// The space `url` opens in.
    /// - external: the first matching rule's space; else Settings ▸ Links'
    ///   default (`externalLinksSpaceID` when it still exists, else the most
    ///   recent space).
    /// - from a page in space S: with `routeLinksBetweenSpaces` off, S; on,
    ///   the first matching rule's space when it is not S, else S.
    /// A rule whose space no longer exists is skipped (the store deletes them
    /// with their space; this keeps a stale set harmless). `nil` when there
    /// is no space to open in (no rule, no default, no recent space).
    public static func route(_ url: String, from origin: Origin, evaluator: Evaluator, settings: Settings,
                             spaces: Set<UUID>, mostRecentSpace: UUID?) -> Decision? {
        switch origin {
        case .external:
            if let rule = evaluator.firstMatch(url, in: spaces) { return Decision(space: rule.targetSpaceID, reason: .rule(rule.id), moved: false) }
            if let chosen = settings.externalLinksSpaceID, spaces.contains(chosen) {
                return Decision(space: chosen, reason: .chosenDefault, moved: false)
            }
            guard let recent = mostRecentSpace else { return nil }
            return Decision(space: recent, reason: .mostRecentSpace, moved: false)
        case .page(let source):
            guard settings.routeLinksBetweenSpaces, let rule = evaluator.firstMatch(url, in: spaces), rule.targetSpaceID != source else {
                return Decision(space: source, reason: .sourceSpace, moved: false)
            }
            return Decision(space: rule.targetSpaceID, reason: .rule(rule.id), moved: true)
        }
    }

    /// `route` with the rules given as values (tests, one-off checks).
    public static func route(_ url: String, from origin: Origin, rules: [RoutingRule], settings: Settings,
                             spaces: Set<UUID>, mostRecentSpace: UUID?) -> Decision? {
        route(url, from: origin, evaluator: Evaluator(rules), settings: settings, spaces: spaces, mostRecentSpace: mostRecentSpace)
    }
}
