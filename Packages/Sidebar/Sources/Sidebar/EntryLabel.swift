import Foundation
import Model

/// Row text rules (spec §I.3).
public enum EntryLabel {
    /// Label shown for an entry: the user's label; then for permanent
    /// entries the stored title (stable while the entry is "changed"), for
    /// Today tabs the live title; then the domain.
    public static func title(_ entry: Entry) -> String {
        if let label = entry.customLabel, !label.isEmpty { return label }
        let candidates: [String?] = entry.kind == .today
            ? [entry.liveTitle, entry.storedTitle]
            : [entry.storedTitle, entry.liveTitle]
        for case let title? in candidates where !title.isEmpty {
            return withoutCounter(title)
        }
        return domain(entry.currentURL) ?? entry.currentURL ?? "New Tab"
    }

    /// The live page's title when it differs from the label (hover sublabel
    /// of a changed permanent entry, spec §I.3).
    public static func currentTitle(_ entry: Entry) -> String? {
        guard let live = entry.liveTitle.map(withoutCounter), !live.isEmpty, live != title(entry) else { return nil }
        return live
    }

    /// Host without a leading "www."; `nil` for strings without a host.
    public static func domain(_ url: String?) -> String? {
        guard let url, let host = URLComponents(string: url)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "(3) Inbox" → "Inbox": titles never show unread counters (spec §I.3).
    public static func withoutCounter(_ title: String) -> String {
        guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return title }
        let inside = title[title.index(after: title.startIndex)..<close]
        guard !inside.isEmpty, inside.allSatisfy(\.isNumber) else { return title }
        return title[title.index(after: close)...].trimmingCharacters(in: .whitespaces)
    }

    /// `[title](url)` for "Copy URL as Markdown"; brackets in the title are escaped.
    public static func markdown(title: String, url: String) -> String {
        let escaped = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(escaped)](\(url))"
    }
}
