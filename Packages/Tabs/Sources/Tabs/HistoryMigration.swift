import Foundation
import Engine
import Model
import Store

/// The Chapter 2 history into the engine's history service, once per
/// profile (ROADMAP 3.5 task 5): every URL of the profile's `history_url`
/// rows with its title and visits (their times and transitions, so visit and
/// typed counts follow), in batches. The flag is the profile's id in
/// `Settings.historyImportedProfiles` (a settings key, no schema change);
/// afterwards the store records nothing more for an engine that keeps
/// history (`TabController.recordsLocalHistory`), and 3.9 drops the tables.
public enum HistoryMigration {
    /// URLs per engine call.
    public static let batchSize = 2_000

    public struct Report: Sendable, Equatable {
        public var result: HistoryImportResult
        /// URLs read from the local table.
        public var localURLs: Int
        public var seconds: Double
    }

    /// Imports `profile`'s local history into `history` unless it was done.
    /// Returns `nil` when the flag was already set (nothing read, nothing sent).
    @MainActor
    public static func run(store: RoomStore, profile: UUID, into history: any ProfileHistory) async -> Report? {
        guard !store.settings.settings.historyImportedProfiles.contains(profile) else { return nil }
        let start = ContinuousClock.now
        var report = Report(result: HistoryImportResult(), localURLs: 0, seconds: 0)
        var cursor: Int64 = 0
        while true {
            let batch: (rows: [HistoryImport], nextID: Int64?)
            do {
                batch = try store.history.exportBatch(profile: profile, afterID: cursor, limit: batchSize)
            } catch {
                // Not flagged: the next launch tries again.
                NSLog("Room: history migration stopped reading the local table: \(error)")
                return nil
            }
            report.localURLs += batch.rows.count
            let entries = batch.rows.compactMap(HistoryImportEntry.init)
            if !entries.isEmpty { report.result = report.result + (await history.importEntries(entries)) }
            guard let next = batch.nextID else { break }
            cursor = next
        }
        store.settings.update { $0.historyImportedProfiles.append(profile) }
        let elapsed = ContinuousClock.now - start
        report.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return report
    }
}

extension HistoryImportEntry {
    /// A local row as an engine import; `nil` for a URL the engine cannot hold.
    init?(_ row: HistoryImport) {
        guard let url = URL(string: row.url), url.scheme != nil else { return nil }
        self.init(url: url, title: row.title, visits: row.visits.map { HistoryVisit(time: $0.at, transition: PageTransition($0.transition)) })
    }
}

extension PageTransition {
    init(_ transition: HistoryTransition) {
        self = switch transition {
        case .typed: .typed
        case .link: .link
        case .bookmark: .bookmark
        case .generated: .generated
        case .keyword: .keyword
        case .formSubmit: .formSubmit
        case .reload: .reload
        case .other: .other
        }
    }
}
