import Foundation
import Model

/// Row text rules (spec §I.3).
public enum EntryLabel {
    /// Label shown for an entry, `customLabel ?? currentTitle ?? storedTitle
    /// ?? domain` (spec §I.3): the user's label; then the live page's title,
    /// except that a permanent entry away from its stored URL ("changed",
    /// `EntryRules.isChanged`) keeps its stored title so the row stays put;
    /// then the domain. Unread counters are never shown (`withoutCounter`).
    public static func title(_ entry: Entry) -> String {
        if let label = entry.customLabel, !label.isEmpty { return label }
        let candidates: [String?] = entry.kind.isPermanent && EntryRules.isChanged(entry)
            ? [entry.storedTitle, entry.liveTitle]
            : [entry.liveTitle, entry.storedTitle]
        for case let title? in candidates {
            let shown = withoutCounter(title)
            if !shown.isEmpty { return shown }
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
        guard let close = counterEnd(title) else { return title }
        return title[title.index(after: close)...].trimmingCharacters(in: .whitespaces)
    }

    /// The unread count a title leads with ("(3) Inbox" → 3, "(99+) Chat" → 99);
    /// `nil` without one, or for "(0)". The row shows it as a dot (spec §I.3).
    public static func unreadCount(_ title: String?) -> Int? {
        guard let title, let close = counterEnd(title) else { return nil }
        let digits = title[title.index(after: title.startIndex)..<close].filter(\.isNumber)
        guard let count = Int(digits), count > 0 else { return nil }
        return count
    }

    /// Whether the entry's row shows the unread dot: its live page's title leads with a counter
    /// (only for a loaded page: an unloaded entry's last title is stale).
    public static func hasUnread(_ entry: Entry, isLoaded: Bool) -> Bool {
        isLoaded && entry.kind != .folder && unreadCount(entry.liveTitle) != nil
    }

    /// The index of the ")" closing a leading "(digits)" or "(digits+)".
    private static func counterEnd(_ title: String) -> String.Index? {
        guard title.hasPrefix("("), let close = title.firstIndex(of: ")") else { return nil }
        var inside = title[title.index(after: title.startIndex)..<close]
        if inside.hasSuffix("+") { inside = inside.dropLast() }
        guard !inside.isEmpty, inside.count <= 6, inside.allSatisfy(\.isASCII), inside.allSatisfy(\.isNumber) else { return nil }
        return close
    }

    /// `[title](url)` for "Copy URL as Markdown"; brackets in the title are escaped.
    public static func markdown(title: String, url: String) -> String {
        let escaped = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(escaped)](\(url))"
    }
}
