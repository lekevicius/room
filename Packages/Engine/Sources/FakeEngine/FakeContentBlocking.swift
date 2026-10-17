import Foundation
import Engine

/// The blocker for tests and previews: reads the configured list files and
/// custom rules, keeps the `||host^` network rules (a request to that host or
/// a subdomain is blocked, `@@||host^` allows it again) and the `##selector`
/// rules; everything else in a list is ignored. Allowed sites and the
/// enabled switch behave as in RoomCore.
@MainActor
public final class FakeContentBlocking: ContentBlocking {
    public private(set) var configuration = ContentBlockingConfiguration()
    /// Every configuration applied, in order.
    public private(set) var appliedConfigurations: [ContentBlockingConfiguration] = []
    public private(set) var blockedHosts: Set<String> = []
    public private(set) var allowedHosts: Set<String> = []
    public private(set) var hideSelectors: [String] = []

    public init() {}

    public func apply(_ configuration: ContentBlockingConfiguration) async -> ContentBlockingReport {
        self.configuration = configuration
        appliedConfigurations.append(configuration)
        var problems: [String] = []
        var texts: [String] = []
        for list in configuration.lists {
            if let text = try? String(contentsOf: list.fileURL, encoding: .utf8) {
                texts.append(list.isHostsFormat ? Self.hostsAsRules(text) : text)
            } else {
                problems.append("unreadable list \(list.fileURL.path)")
            }
        }
        texts.append(configuration.customRules)
        blockedHosts = []
        allowedHosts = []
        hideSelectors = []
        for line in texts.joined(separator: "\n").split(whereSeparator: \.isNewline) {
            let rule = line.trimmingCharacters(in: .whitespaces)
            if rule.hasPrefix("@@||"), rule.hasSuffix("^") {
                allowedHosts.insert(String(rule.dropFirst(4).dropLast()).lowercased())
            } else if rule.hasPrefix("||"), rule.hasSuffix("^") {
                blockedHosts.insert(String(rule.dropFirst(2).dropLast()).lowercased())
            } else if rule.hasPrefix("##") {
                hideSelectors.append(String(rule.dropFirst(2)))
            }
        }
        return ContentBlockingReport(problems: problems)
    }

    public func wouldBlock(_ url: URL, from source: URL, type: ContentBlockingRequestType) -> Bool {
        guard configuration.isEnabled, let host = url.host()?.lowercased() else { return false }
        if let site = PublicSuffixList.site(of: source), configuration.allowedSites.contains(site) {
            return false
        }
        func matches(_ hosts: Set<String>) -> Bool {
            hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        return matches(blockedHosts) && !matches(allowedHosts)
    }

    private static func hostsAsRules(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(separator: "#", maxSplits: 1).first?.split(whereSeparator: \.isWhitespace) ?? []
            guard let host = fields.last, !host.isEmpty, !line.hasPrefix("!") else { return nil }
            return "||\(host)^"
        }.joined(separator: "\n")
    }
}
