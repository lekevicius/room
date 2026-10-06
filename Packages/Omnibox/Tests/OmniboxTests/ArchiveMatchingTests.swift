import Foundation
import Model
import Testing
@testable import Omnibox

@Suite("Archived tabs in the History group (spec §H)")
struct ArchiveMatchingTests {
    let row = ArchivedEntry(url: "https://docs.example.com/guide", title: "The Guide", spaceID: UUID(), profileID: UUID(),
                            archivedAt: Timestamp(Date()), reason: .auto)

    @Test("Every word must match; the row restores, carries the Archived chip and sits in the History group")
    func matching() {
        let matches = ArchiveMatching.matches(for: OmniboxInput(text: "guide docs"), archive: [row], now: Date())
        #expect(matches.count == 1)
        let match = matches[0]
        #expect(match.action == .restoreArchived(id: row.id, url: row.url))
        #expect(match.spaceName == ArchiveMatching.chip && match.group == .history && Relevance.history.contains(match.relevance))
        #expect(ArchiveMatching.matches(for: OmniboxInput(text: "guide nowhere"), archive: [row], now: Date()).isEmpty)
        #expect(ArchiveMatching.matches(for: OmniboxInput(field: ">guide"), archive: [row], now: Date()).isEmpty, "not in commands mode")
    }

    @Test("The same page from the engine's history becomes the archived row: restore and chip (dedupe)")
    func dedupeWithHistory() {
        let archived = ArchiveMatching.matches(for: OmniboxInput(text: "guide"), archive: [row], now: Date())
        let history = OmniboxMatch(id: "engine:1", provider: .history, relevance: 1_290, action: .navigate(url: row.url),
                                   title: "The Guide", icon: .site(url: row.url), isDeletable: true)
        let result = OmniboxResult(ranking: [history] + archived, input: OmniboxInput(text: "guide"))
        let rows = result.matches.filter { $0.action.url == row.url }
        #expect(rows.count == 1)
        #expect(rows.first?.action == .restoreArchived(id: row.id, url: row.url) && rows.first?.spaceName == ArchiveMatching.chip)
    }
}
