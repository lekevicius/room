import Foundation

/// Which Today tabs the sweep archives (spec §A.7), as a pure function: a
/// Today tab whose `lastActiveAt` (else its `createdAt`) is older than the
/// "Archive tabs after" setting goes, except the selected one, one playing
/// or capturing, one with unsaved form input (the engine's discard blockers)
/// and one in a split with a permanent member.
public enum ArchivePolicy {
    /// "Never" (5.7a, B-120: the default): the sweep archives nothing.
    public static let never = 0

    /// The options Settings ▸ General offers (hours): 12 h, 24 h, 7 d, 30 d and Never (the default).
    public static let afterHoursOptions = [12, 24, 168, 720, never]

    /// What keeps a loaded page from being archived, from the engine
    /// (`WebContents.discardBlockers` and `isAudible`).
    public struct Exemption: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let audible = Exemption(rawValue: 1 << 0)
        public static let capturing = Exemption(rawValue: 1 << 1)
        /// Unsaved form input or other edits (a beforeunload-worthy page).
        public static let dirtyForm = Exemption(rawValue: 1 << 2)
        /// Picture in Picture: on screen elsewhere.
        public static let pictureInPicture = Exemption(rawValue: 1 << 3)
    }

    /// Today tabs to archive now, in the order given.
    /// - Parameters:
    ///   - today: candidate entries (anything but `.today` is ignored).
    ///   - selected: every space's selected entry in every window; a selected
    ///     entry's split partners are on screen with it and count as selected.
    ///   - exemptions: what the engine reports for loaded pages.
    ///   - entries: every entry by id (to see a split's other members).
    public static func toArchive(today: [Entry], now: Timestamp, afterHours: Int, selected: Set<UUID>,
                                 exemptions: [UUID: Exemption], splitGroups: [UUID: SplitGroup],
                                 entries: [UUID: Entry]) -> [UUID] {
        guard afterHours > never else { return [] }
        let threshold = Int64(max(afterHours, 1)) * 3_600_000
        var onScreen = selected
        for id in selected {
            if let group = entries[id]?.splitGroupID, let split = splitGroups[group] { onScreen.formUnion(split.members) }
        }
        return today.filter { entry in
            guard entry.kind == .today, !onScreen.contains(entry.id) else { return false }
            let used = entry.lastActiveAt ?? entry.createdAt
            guard now.milliseconds - used.milliseconds > threshold else { return false }
            if let exemption = exemptions[entry.id], !exemption.isEmpty { return false }
            if let group = entry.splitGroupID, let split = splitGroups[group],
               split.members.contains(where: { entries[$0]?.kind.isPermanent == true }) {
                return false
            }
            return true
        }.map(\.id)
    }
}

/// How long the Archive keeps its rows (B-80; the app passes the tokens,
/// `Retention.archiveRows` 30 days and `Retention.archiveNavigationState`
/// 7 days; no setting): a row archived longer ago than `rows` is pruned at the
/// sweep, and one older than `navigationState` loses its back/forward list
/// (a restore then opens its URL with no history).
public enum ArchiveRetention {
    public struct Plan: Equatable, Sendable {
        public var prune: Set<UUID> = []
        public var dropNavigationState: Set<UUID> = []
        public var isEmpty: Bool { prune.isEmpty && dropNavigationState.isEmpty }
        public init() {}
    }

    public static func plan(_ rows: some Sequence<ArchivedEntry>, now: Timestamp, rows keep: TimeInterval,
                            navigationState keepState: TimeInterval) -> Plan {
        var plan = Plan()
        let rowLimit = now.milliseconds - Int64(keep * 1000)
        let stateLimit = now.milliseconds - Int64(keepState * 1000)
        for row in rows {
            if row.archivedAt.milliseconds < rowLimit {
                plan.prune.insert(row.id)
            } else if row.navigationState != nil, row.archivedAt.milliseconds < stateLimit {
                plan.dropNavigationState.insert(row.id)
            }
        }
        return plan
    }
}

/// The Library's and the palette's view of the Archive (spec §H).
public enum ArchiveSearch {
    /// Rows whose title, URL or domain contains every word of `text`
    /// (case- and diacritic-insensitive), newest first; all rows for empty text.
    public static func matching(_ rows: some Sequence<ArchivedEntry>, text: String) -> [ArchivedEntry] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let sorted = rows.sorted { ($0.archivedAt, $0.id.uuidString) > ($1.archivedAt, $1.id.uuidString) }
        guard !words.isEmpty else { return sorted }
        return sorted.filter { row in
            let haystack = "\(row.title ?? "") \(row.url)"
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// Rows grouped by the calendar day they were archived on, newest day
    /// first, newest row first inside a day.
    public static func byDay(_ rows: [ArchivedEntry], calendar: Calendar = .current) -> [(day: Date, rows: [ArchivedEntry])] {
        let sorted = rows.sorted { ($0.archivedAt, $0.id.uuidString) > ($1.archivedAt, $1.id.uuidString) }
        var result: [(day: Date, rows: [ArchivedEntry])] = []
        for row in sorted {
            let day = calendar.startOfDay(for: row.archivedAt.date)
            if result.last?.day == day {
                result[result.count - 1].rows.append(row)
            } else {
                result.append((day, [row]))
            }
        }
        return result
    }
}
