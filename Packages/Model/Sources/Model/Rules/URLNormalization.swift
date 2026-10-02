import Foundation

/// URL comparison for the "changed" state of permanent entries (spec §A.1):
/// a trailing slash and the `#fragment` are ignored, a `?query` difference
/// counts. Scheme and host compare case-insensitively, as URLs do.
public enum URLNormalization {
    public static func normalized(_ string: String) -> String {
        guard var components = URLComponents(string: string), components.scheme != nil else {
            return stripFragmentAndSlash(string)
        }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        if let host = components.host { components.host = host.lowercased() }
        if components.query?.isEmpty == true { components.query = nil }
        if components.path.hasSuffix("/") { components.path.removeLast() }
        return components.string ?? stripFragmentAndSlash(string)
    }

    public static func isSame(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static func stripFragmentAndSlash(_ string: String) -> String {
        var result = string.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? string
        if result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
