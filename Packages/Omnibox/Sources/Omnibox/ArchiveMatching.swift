import Foundation
import Model

/// Archived tabs in the palette's History group (spec §H: "Archived items
/// also surface in the palette's History group with a chip 'Archived'").
/// Pure over the input and the Archive's rows; the palette adds them to the
/// local candidates, the scorer dedupes them with the engine's history (an
/// archived page's history row takes the restore action and the chip).
public enum ArchiveMatching {
    /// The chip's text.
    public static let chip = "Archived"
    /// At most this many archived rows reach the scorer per keystroke.
    public static let limit = 20

    /// Rows whose title or URL contain every word of the input, scored in
    /// the History band (title and host prefixes first, then recency).
    public static func matches(for input: OmniboxInput, archive: some Sequence<ArchivedEntry>, now: Date) -> [OmniboxMatch] {
        guard input.mode == .normal else { return [] }
        let terms = input.trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var scored: [(match: OmniboxMatch, at: Timestamp)] = []
        for row in archive {
            let title = (row.title ?? "").lowercased()
            let url = row.url.lowercased()
            let host = row.domain.lowercased()
            var quality = 0.0
            var matched = true
            for term in terms {
                if host.hasPrefix(term) || title.hasPrefix(term) {
                    quality += 1
                } else if title.contains(term) || url.contains(term) {
                    quality += 0.6
                } else {
                    matched = false
                    break
                }
            }
            guard matched else { continue }
            let age = max(0, now.timeIntervalSince(row.archivedAt.date))
            let recency = 1 / (1 + age / 86_400 / 7)
            let fraction = (quality / Double(terms.count)) * 0.8 + recency * 0.2
            let match = OmniboxMatch(id: "archived:\(row.id)", provider: .history,
                                     relevance: Relevance.scaled(fraction, in: Relevance.history),
                                     action: .restoreArchived(id: row.id, url: row.url), title: row.displayTitle,
                                     detail: VerbatimProvider.displayURL(row.url), icon: .site(url: row.url), spaceName: chip)
            scored.append((match, row.archivedAt))
        }
        scored.sort { ($0.match.relevance, $0.at) > ($1.match.relevance, $1.at) }
        return scored.prefix(limit).map(\.match)
    }
}
