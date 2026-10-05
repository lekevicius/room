import Foundation
import Engine
import Model
import Store

/// The Chapter 2 history into the engine's history service, once per
/// profile (ROADMAP 3.5 task 5). Since schema v6 (Phase 3.9) the local
/// tables are gone: a profile 3.5 never imported has its rows in
/// `history-archive.json` (`HistoryArchive`, written by v6 before the drop),
/// and this imports them from there, with titles and visits (times and
/// transitions, so visit and typed counts follow), in batches. The flag is
/// the profile's id in `Settings.historyImportedProfiles`; a profile the
/// archive does not list has nothing to import and is flagged at once.
public enum HistoryMigration {
    /// URLs per engine call.
    public static let batchSize = 2_000

    public struct Report: Sendable, Equatable {
        public var result: HistoryImportResult
        /// URLs read from the archive for the profile.
        public var localURLs: Int
        public var seconds: Double
    }

    /// Imports `profile`'s archived history into `history` unless it was done.
    /// Returns `nil` when the flag was already set (nothing read, nothing sent)
    /// or the archive exists but does not read (tried again next launch).
    @MainActor
    public static func run(store: RoomStore, profile: UUID, into history: any ProfileHistory) async -> Report? {
        guard !store.settings.settings.historyImportedProfiles.contains(profile) else { return nil }
        let start = ContinuousClock.now
        var report = Report(result: HistoryImportResult(), localURLs: 0, seconds: 0)
        let archiveURL = store.historyArchiveURL
        var rows: [HistoryArchive.URLRow] = []
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            guard let archive = HistoryArchive.read(from: archiveURL) else {
                // Not flagged: the next launch tries again.
                NSLog("Room: history migration could not read %@", archiveURL.path)
                return nil
            }
            rows = archive.profiles.first { $0.profileID == profile && !$0.imported }?.urls ?? []
        }
        report.localURLs = rows.count
        var index = 0
        while index < rows.count {
            let batch = rows[index..<min(index + batchSize, rows.count)]
            let entries = batch.compactMap(HistoryImportEntry.init)
            if !entries.isEmpty { report.result = report.result + (await history.importEntries(entries)) }
            index += batchSize
        }
        store.settings.update { $0.historyImportedProfiles.append(profile) }
        let elapsed = ContinuousClock.now - start
        report.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return report
    }
}

extension HistoryImportEntry {
    /// An archived row as an engine import; `nil` for a URL the engine cannot hold.
    init?(_ row: HistoryArchive.URLRow) {
        guard let url = URL(string: row.url), url.scheme != nil else { return nil }
        self.init(url: url, title: row.title, visits: row.visits.map { HistoryVisit(time: $0.time, transition: PageTransition(archived: $0.transition)) })
    }
}

extension PageTransition {
    /// A transition as v1–v5 stored it (`history_visit.transition`).
    init(archived: String) {
        self = switch archived {
        case "typed": .typed
        case "link": .link
        case "bookmark": .bookmark
        case "generated": .generated
        case "keyword": .keyword
        case "formSubmit": .formSubmit
        case "reload": .reload
        default: .other
        }
    }
}
