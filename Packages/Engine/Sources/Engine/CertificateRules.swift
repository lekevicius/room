import Foundation

/// When a certificate error may be clicked through (ROADMAP 2.6: the
/// interstitial proceeds only for non-HSTS hosts).
nonisolated public enum CertificateRules {
    /// Errors Chrome lets a person bypass on a host without HSTS: name,
    /// date, authority, weak algorithms and keys, name constraints, validity
    /// length, missing transparency. Revoked, invalid, pinning and
    /// interception errors are never bypassed.
    public static let overridableCodes: Set<Int> = [-200, -201, -202, -208, -210, -211, -212, -213, -214]

    /// `strictTransportSecurity`: whether the host has an HSTS policy
    /// (Chromium's `strict_enforcement`), or `nil` when the engine cannot
    /// tell (Chapter 2's engine never passed it, and would have bypassed
    /// even an HSTS host); without the flag only hosts that no HSTS policy
    /// can cover may proceed: IP addresses (HSTS ignores them) and
    /// local names (`localhost`, `.localhost`, `.test`, `.local`,
    /// `.internal`, `.home.arpa`). RoomCore passes the flag (Chapter 3).
    public static func isOverridable(code: Int, host: String, strictTransportSecurity: Bool?) -> Bool {
        guard overridableCodes.contains(code) else { return false }
        switch strictTransportSecurity {
        case true?: return false
        case false?: return true
        case nil: return isLocal(host)
        }
    }

    static func isLocal(_ host: String) -> Bool {
        var host = host.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }
        if isIPAddress(host) { return true }
        if host == "localhost" { return true }
        return [".localhost", ".test", ".local", ".internal", ".home.arpa"].contains { host.hasSuffix($0) }
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }
}
