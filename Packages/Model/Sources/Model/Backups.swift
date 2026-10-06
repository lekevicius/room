import Foundation
import GRDB

/// Arc's rolling-backup schedule (spec §H) as numbers: the newest `today`
/// backups taken today, the newest of each of the `days` calendar days before
/// today, the newest of each calendar week back `weeksSpanDays`, the newest
/// of each calendar month back `monthsSpanDays`. The app passes the tokens
/// (`Retention` in Design: 10, 10, 31, 365).
public struct BackupSchedule: Sendable, Equatable {
    public var today: Int
    public var days: Int
    public var weeksSpanDays: Int
    public var monthsSpanDays: Int

    public init(today: Int, days: Int, weeksSpanDays: Int, monthsSpanDays: Int) {
        self.today = today
        self.days = days
        self.weeksSpanDays = weeksSpanDays
        self.monthsSpanDays = monthsSpanDays
    }
}

/// Which backups to keep and whether a new one is due, as pure functions
/// (ROADMAP 4.1b task 6; tested on a fake clock).
public enum BackupPlanner {
    public struct Plan: Equatable, Sendable {
        /// Newest first.
        public var keep: [Date]
        /// Newest first.
        public var prune: [Date]
    }

    /// The schedule applied at `now` to backups taken at `dates`. A backup
    /// dated after `now` (a clock moved back) counts as today's. Backups
    /// older than every span are pruned.
    public static func plan(_ dates: [Date], now: Date, schedule: BackupSchedule, calendar: Calendar) -> Plan {
        let sorted = dates.sorted(by: >)
        let startOfToday = calendar.startOfDay(for: now)
        var keep = Set<Date>()
        keep.formUnion(sorted.filter { $0 >= startOfToday }.prefix(max(schedule.today, 0)))
        func newestPer(_ component: Calendar.Component, since start: Date) {
            var seen = Set<Date>()
            for date in sorted where date < startOfToday && date >= start {
                guard let period = calendar.dateInterval(of: component, for: date) else { continue }
                if seen.insert(period.start).inserted { keep.insert(date) }
            }
        }
        if let start = calendar.date(byAdding: .day, value: -max(schedule.days, 0), to: startOfToday) {
            newestPer(.day, since: start)
        }
        if let start = calendar.date(byAdding: .day, value: -max(schedule.weeksSpanDays, 0), to: now) {
            newestPer(.weekOfYear, since: start)
        }
        if let start = calendar.date(byAdding: .day, value: -max(schedule.monthsSpanDays, 0), to: now) {
            newestPer(.month, since: start)
        }
        return Plan(keep: sorted.filter { keep.contains($0) }, prune: sorted.filter { !keep.contains($0) })
    }

    /// A backup is due when the state moved since the last one: its
    /// generation differs from the newest backup's (none yet: any written
    /// state). A state never written (generation 0) is not backed up.
    public static func isDue(generation: Int64, lastBackupGeneration: Int64?) -> Bool {
        generation > 0 && generation != lastBackupGeneration
    }
}

/// One backup file in `<state>/Backups/`: `Room-<UTC timestamp>.sqlite`, or
/// `Room-<timestamp>-<label>.sqlite` (`before-restore`).
public struct BackupFile: Sendable, Equatable, Identifiable {
    public var url: URL
    public var date: Date
    public var label: String?
    public var id: URL { url }

    public init(url: URL, date: Date, label: String?) {
        self.url = url
        self.date = date
        self.label = label
    }
}

/// What the Restore list shows of a backup, read from the file.
public struct BackupInfo: Sendable, Equatable {
    public var file: BackupFile
    public var generation: Int64
    public var entries: Int
    public var spaces: Int
    public var archived: Int
}

/// The rolling backups of the state database (spec §H): `VACUUM INTO` copies
/// of `Room.sqlite` in `<state>/Backups/`, pruned by `BackupPlanner`.
public struct RoomBackups: Sendable {
    public static let directoryName = "Backups"
    public static let beforeRestoreLabel = "before-restore"

    public let directory: URL

    public init(stateDirectory: URL) {
        directory = stateDirectory.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    // MARK: Names

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter
    }

    /// `Room-2026-10-06T14-05-09.123Z.sqlite` (ISO 8601 with `-` for `:`,
    /// which Finder shows as `/`), `…Z-before-restore.sqlite` with a label.
    public static func fileName(for date: Date, label: String?) -> String {
        "Room-" + formatter().string(from: date) + (label.map { "-" + $0 } ?? "") + ".sqlite"
    }

    /// The date and label a backup's name carries; `nil` for any other file.
    public static func parse(_ name: String) -> (date: Date, label: String?)? {
        guard name.hasPrefix("Room-"), name.hasSuffix(".sqlite") else { return nil }
        let body = name.dropFirst("Room-".count).dropLast(".sqlite".count)
        // The timestamp is 24 characters: yyyy-MM-ddTHH-mm-ss.SSSZ.
        guard body.count >= 24 else { return nil }
        let stamp = String(body.prefix(24))
        guard let date = formatter().date(from: stamp) else { return nil }
        let rest = body.dropFirst(24)
        guard rest.isEmpty || rest.hasPrefix("-") else { return nil }
        return (date, rest.isEmpty ? nil : String(rest.dropFirst()))
    }

    // MARK: Files

    /// Every backup, newest first.
    public func list() -> [BackupFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            Self.parse(name).map { BackupFile(url: directory.appending(path: name), date: $0.date, label: $0.label) }
        }.sorted { $0.date > $1.date }
    }

    /// Copies the database (`VACUUM INTO`, a consistent snapshot taken on the
    /// writer connection, so it waits for a state write in progress and the
    /// next one waits for it) to a new backup dated `date`. The copy is made
    /// under a temporary name and renamed, so a half-written file is never
    /// listed, and is switched to rollback journaling so it opens read-only.
    @discardableResult
    public func take(from database: RoomDatabase, at date: Date, label: String? = nil) throws -> BackupFile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.fileName(for: date, label: label)
        let target = directory.appending(path: name)
        let partial = directory.appending(path: "." + name + ".partial")
        try? FileManager.default.removeItem(at: partial)
        try database.pool.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [partial.path])
        }
        do {
            let queue = try DatabaseQueue(path: partial.path)
            try queue.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA journal_mode = DELETE") }
            try queue.close()
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: partial, to: target)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        return BackupFile(url: target, date: date, label: label)
    }

    /// The generation and counts stored in a backup (opened read-only).
    public func info(_ file: BackupFile) throws -> BackupInfo {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: file.url.path, configuration: configuration)
        defer { try? queue.close() }
        return try queue.read { db in
            BackupInfo(file: file, generation: try RoomDatabase.generation(db),
                       entries: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry") ?? 0,
                       spaces: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM space") ?? 0,
                       archived: (try? Int.fetchOne(db, sql: "SELECT COUNT(*) FROM archive")) ?? 0)
        }
    }

    /// The state a backup holds. Read from a migrated temporary copy, so a
    /// backup made by an older schema reads like a current one and the
    /// backup itself is never written.
    public func loadState(_ file: BackupFile) throws -> (state: RoomState, generation: Int64) {
        let scratch = FileManager.default.temporaryDirectory.appending(path: "Room-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appending(path: RoomStorage.databaseName)
        try FileManager.default.copyItem(at: file.url, to: copy)
        let database = try RoomDatabase(url: copy)
        defer { try? database.pool.close() }
        return try database.loadState()
    }

    /// Deletes the backups the schedule no longer keeps at `now`; returns them.
    @discardableResult
    public func prune(now: Date, schedule: BackupSchedule, calendar: Calendar) -> [BackupFile] {
        let files = list()
        let plan = BackupPlanner.plan(files.map(\.date), now: now, schedule: schedule, calendar: calendar)
        let doomed = Set(plan.prune)
        let pruned = files.filter { doomed.contains($0.date) }
        for file in pruned { try? FileManager.default.removeItem(at: file.url) }
        return pruned
    }
}
