import Foundation

/// Typed text → a URL (spec §A.5, §C): adds a scheme to bare hosts and
/// refuses text that is not a URL. "Edit Pinned URL…", drops from outside
/// and the palette's verbatim row all go through it.
public enum URLFixup {
    private static let schemes: Set<String> = ["http", "https", "file", "about", "data", "chrome", "view-source"]

    public static func url(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let colon = trimmed.firstIndex(of: ":") {
            let scheme = trimmed[..<colon].lowercased()
            if schemes.contains(scheme) {
                guard let components = URLComponents(string: trimmed) else { return nil }
                if scheme == "http" || scheme == "https" { guard components.host?.isEmpty == false else { return nil } }
                return trimmed
            }
        }
        // A bare host (with optional port, path, query): needs a dot or be localhost.
        guard let components = URLComponents(string: "https://" + trimmed), let host = components.host, !host.isEmpty else {
            return nil
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isLocal = host == "localhost" || host.hasSuffix(".localhost")
        guard isLocal || (labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }) else { return nil }
        let scheme = isLocal ? "http://" : "https://"
        return scheme + trimmed
    }

    /// A Google search for `text` (the default engine until the first-run
    /// choice, 2.8; drops of plain text on the sidebar use it, spec §A.9).
    public static func searchURL(for text: String) -> String {
        SearchEngine.google.searchURL(for: text)
    }

    /// What the palette does with typed text (spec §C top hit).
    public enum Classification: Equatable, Sendable {
        /// Navigate. `confident` when nothing about the text reads as a
        /// query (a scheme, a port, a path, localhost, an IP address or a
        /// well-known or country-code top-level domain): the URL is the top hit. Otherwise
        /// ("node.js") the search is, with the URL as the alternative.
        case url(String, confident: Bool)
        /// Search for the text. A leading "?" forces a search and is dropped.
        case query(String)
    }

    public static func classify(_ text: String) -> Classification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("?") { return .query(trimmed.dropFirst().trimmingCharacters(in: .whitespaces)) }
        guard let url = url(from: trimmed) else { return .query(trimmed) }
        return .url(url, confident: isConfident(typed: trimmed, url: url))
    }

    private static func isConfident(typed: String, url: String) -> Bool {
        guard let components = URLComponents(string: url) else { return false }
        let scheme = typed.firstIndex(of: ":").map { typed[..<$0].lowercased() }
        if let scheme, schemes.contains(scheme) { return true }
        guard let host = components.host?.lowercased() else { return true }
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if components.port != nil || !components.path.isEmpty || components.query != nil { return true }
        let labels = host.split(separator: ".")
        if labels.count == 4, labels.allSatisfy({ UInt8($0) != nil }) { return true }
        guard let tld = labels.last else { return false }
        return knownTopLevelDomains.contains(String(tld)) || countryCodes.contains(String(tld))
    }

    /// Country-code TLDs: ISO 3166 regions plus the few that differ ("uk",
    /// "eu", "ac", "su"). Not every two-letter ending: "node.js" is a query.
    static let countryCodes: Set<String> = Set(Locale.Region.isoRegions.map { $0.identifier.lowercased() }
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }).union(["uk", "eu", "ac", "su"])

    /// Generic top-level domains common enough that "name.tld" is a site,
    /// not a query.
    static let knownTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "name", "pro",
        "io", "dev", "app", "ai", "page", "site", "online", "tech", "blog", "news", "shop", "store", "cloud",
        "xyz", "live", "world", "today", "email", "design", "studio", "art", "wiki",
        "local", "test", "internal", "lan", "arpa",
    ]
}

/// A search engine's query URL (spec §C; the suggest endpoints and the
/// Settings choice are 2.4b/2.8). Google is the default until the first-run
/// choice (user decision, 2026-10-03).
public struct SearchEngine: Hashable, Sendable {
    public var name: String
    /// The query URL with `{query}` where the escaped text goes.
    public var template: String

    public init(name: String, template: String) {
        self.name = name
        self.template = template
    }

    public static let google = SearchEngine(name: "Google", template: "https://www.google.com/search?q={query}")
    public static let duckDuckGo = SearchEngine(name: "DuckDuckGo", template: "https://duckduckgo.com/?q={query}")
    public static let kagi = SearchEngine(name: "Kagi", template: "https://kagi.com/search?q={query}")

    public func searchURL(for text: String) -> String {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        let escaped = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return template.replacingOccurrences(of: "{query}", with: escaped)
    }
}
