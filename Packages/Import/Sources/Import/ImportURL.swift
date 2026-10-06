import Foundation

/// URLs as the import compares and admits them (Phase 4.3a).
public enum ImportURL {
    /// The key duplicates are found by: the scheme and host lower-cased,
    /// "www." dropped from the host, the scheme's default port dropped, the
    /// trailing slash of an empty path dropped, the fragment dropped. The
    /// path's case, a trailing slash on a non-empty path and the query count.
    /// A string that does not parse as a URL with a host is only trimmed and
    /// stripped of its fragment.
    public static func normalized(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty else {
            return trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        }
        components.scheme = scheme
        var lowered = host.lowercased()
        if lowered.hasPrefix("www.") { lowered.removeFirst(4) }
        components.host = lowered
        if let port = components.port, defaultPorts[scheme] == port { components.port = nil }
        components.fragment = nil
        if components.percentEncodedPath == "/" { components.percentEncodedPath = "" }
        return components.string ?? trimmed
    }

    static let defaultPorts: [String: Int] = ["http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21]

    /// Schemes an imported entry or history row may have; the rest
    /// (`javascript:`, `chrome:`, `about:`, `place:`, `data:` …) are skipped
    /// with a reason.
    public static let admittedSchemes: Set<String> = ["http", "https", "file"]

    /// The URL's scheme when Room cannot open it as an entry, else `nil`.
    public static func refusedScheme(_ string: String) -> String? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased() else {
            return "no scheme"
        }
        return admittedSchemes.contains(scheme) ? nil : scheme
    }
}
