import Foundation

/// Sites as Chromium counts them for "same site" (spec §A.4 "same eTLD+1"):
/// the registrable domain, the public suffix plus one label, by the Public
/// Suffix List with its private section (`Resources/public_suffix_list.dat`,
/// Chromium 154's copy, as `net::SchemefulSite` uses
/// `INCLUDE_PRIVATE_REGISTRIES`). An IP address, `localhost` or any host
/// without a registrable domain is its own site.
///
/// The bundled list behind `EngineApplication.site(of:)` for engines without
/// Chromium's `net::registry_controlled_domains` (CEF, the fake). It skips the
/// list's IDN rules (hosts arrive in punycode; B-34): RoomCore uses Chromium's
/// own table, which updates with Chromium.
nonisolated public enum PublicSuffixList {
    /// The site of `host` (lower-cased, without a trailing dot).
    public static func site(ofHost host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasPrefix("[") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return host }
        return registrableDomain(host) ?? host
    }

    /// The site of a URL; `nil` without a host (`about:`, `data:`, `file:`).
    public static func site(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return site(ofHost: host)
    }

    public static func isSameSite(_ a: URL, _ b: URL) -> Bool {
        guard let siteA = site(of: a), let siteB = site(of: b) else { return false }
        return siteA == siteB
    }

    /// The public suffix plus one label, or `nil` when `host` is itself a
    /// public suffix (or a single label such as `localhost`).
    public static func registrableDomain(_ host: String) -> String? {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, !labels.contains("") else { return nil }
        let suffixCount = publicSuffixLabelCount(labels)
        guard labels.count > suffixCount else { return nil }
        return labels.suffix(suffixCount + 1).joined(separator: ".")
    }

    /// How many trailing labels form the public suffix (PSL algorithm: the
    /// longest matching rule, exceptions first, `*` when nothing matches).
    static func publicSuffixLabelCount(_ labels: [String]) -> Int {
        let rules = Rules.shared
        var best = 1
        for count in 1...labels.count {
            let candidate = labels.suffix(count).joined(separator: ".")
            if rules.exceptions.contains(candidate) { return count - 1 }
            if rules.exact.contains(candidate) { best = max(best, count) }
            if count > 1 {
                let wildcard = "*." + labels.suffix(count - 1).joined(separator: ".")
                if rules.exact.contains(wildcard) { best = max(best, count) }
            }
        }
        return best
    }

    private final class Rules: Sendable {
        static let shared = Rules()
        let exact: Set<String>
        let exceptions: Set<String>

        init() {
            var exact = Set<String>(), exceptions = Set<String>()
            if let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                for line in text.split(separator: "\n") where !line.hasPrefix("//") && !line.isEmpty {
                    if line.hasPrefix("!") { exceptions.insert(String(line.dropFirst())) } else { exact.insert(String(line)) }
                }
            }
            self.exact = exact
            self.exceptions = exceptions
        }
    }
}
