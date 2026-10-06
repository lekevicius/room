import Foundation
import Testing
@testable import Model

/// Spec §H: rolling backups, last 10 of today, one a day for 10 days, one a
/// week for a month, one a month for a year (Arc). The planner runs on dates
/// given to it: a fake clock.
@Suite("Backup planner (ROADMAP 4.1b task 6)")
struct BackupPlannerTests {
    static let arc = BackupSchedule(today: 10, days: 10, weeksSpanDays: 31, monthsSpanDays: 365)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }
    /// Tuesday 2026-10-06 18:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_791_309_600)

    static func ago(days: Double = 0, hours: Double = 0, minutes: Double = 0) -> Date {
        now.addingTimeInterval(-(days * 86_400 + hours * 3_600 + minutes * 60))
    }

    @Test("Today: the ten newest stay, older ones of today go")
    func today() {
        // Every 30 min since 06:00 today: 25 backups.
        let dates = (0..<25).map { Self.ago(minutes: Double($0) * 30) }
        let plan = BackupPlanner.plan(dates, now: Self.now, schedule: Self.arc, calendar: Self.calendar)
        #expect(plan.keep == Array(dates.prefix(10)))
        #expect(plan.prune == Array(dates.dropFirst(10)))
    }

    @Test("One a day for the ten days before today: the newest of each day")
    func daily() {
        // Three backups a day (09:00, 13:00, 17:00) on each of the last 14 days, none today.
        var dates: [Date] = []
        for day in 1...14 { for hour in [1.0, 5.0, 9.0] { dates.append(Self.ago(days: Double(day), hours: hour)) } }
        let plan = BackupPlanner.plan(dates, now: Self.now, schedule: Self.arc, calendar: Self.calendar)
        let daily = (1...10).map { Self.ago(days: Double($0), hours: 1) }
        for date in daily { #expect(plan.keep.contains(date)) }
        // Days 1–10 keep one each; the older ones only as weekly or monthly picks.
        for day in 1...10 {
            #expect(plan.keep.filter { Self.calendar.isDate($0, inSameDayAs: Self.ago(days: Double(day))) }.count == 1)
        }
        #expect(plan.prune.contains(Self.ago(days: 1, hours: 5)))
    }

    @Test("One a week for a month and one a month for a year; older than a year goes")
    func weeklyAndMonthly() {
        // One backup a day for 400 days, at 12:00.
        let dates = (1...400).map { Self.ago(days: Double($0), hours: 6) }
        let plan = BackupPlanner.plan(dates, now: Self.now, schedule: Self.arc, calendar: Self.calendar)
        // Beyond the daily span, within the month: one per calendar week.
        let monthAgo = Self.ago(days: 31)
        let weekly = plan.keep.filter { $0 < Self.ago(days: 10, hours: 18) && $0 >= monthAgo }
        let weeks = Set(weekly.map { Self.calendar.dateInterval(of: .weekOfYear, for: $0)!.start })
        #expect(weekly.count == weeks.count)
        #expect(weekly.count >= 3)
        // Beyond the month: one per calendar month, none older than a year.
        let monthly = plan.keep.filter { $0 < monthAgo }
        let months = Set(monthly.map { Self.calendar.dateInterval(of: .month, for: $0)!.start })
        #expect(monthly.count == months.count)
        #expect(monthly.allSatisfy { $0 >= Self.ago(days: 365) })
        #expect(plan.keep.count <= 10 + 10 + 6 + 13)
        #expect(plan.prune.contains(Self.ago(days: 400, hours: 6)))
        #expect(Set(plan.keep).isDisjoint(with: plan.prune))
        #expect(plan.keep.count + plan.prune.count == dates.count)
    }

    @Test("A backup dated after now (the clock moved back) counts as today's")
    func future() {
        let ahead = Self.now.addingTimeInterval(3_600)
        let plan = BackupPlanner.plan([ahead, Self.ago(hours: 1)], now: Self.now, schedule: Self.arc, calendar: Self.calendar)
        #expect(plan.keep == [ahead, Self.ago(hours: 1)])
    }

    @Test("Due when the generation moved since the last backup; never for a state never written")
    func due() {
        #expect(BackupPlanner.isDue(generation: 5, lastBackupGeneration: nil))
        #expect(BackupPlanner.isDue(generation: 6, lastBackupGeneration: 5))
        #expect(!BackupPlanner.isDue(generation: 5, lastBackupGeneration: 5))
        #expect(!BackupPlanner.isDue(generation: 0, lastBackupGeneration: nil))
    }

    @Test("Names carry the date and an optional label; other files are not backups")
    func names() throws {
        let date = Date(timeIntervalSince1970: 1_791_309_600.123)
        let name = RoomBackups.fileName(for: date, label: nil)
        #expect(name == "Room-2026-10-06T18-00-00.123Z.sqlite")
        let parsed = try #require(RoomBackups.parse(name))
        #expect(abs(parsed.date.timeIntervalSince(date)) < 0.001 && parsed.label == nil)
        let labelled = try #require(RoomBackups.parse(RoomBackups.fileName(for: date, label: RoomBackups.beforeRestoreLabel)))
        #expect(labelled.label == "before-restore")
        #expect(RoomBackups.parse("Room.sqlite") == nil)
        #expect(RoomBackups.parse("Room-snapshot.json") == nil)
        #expect(RoomBackups.parse(".Room-2026-10-06T18-00-00.123Z.sqlite.partial") == nil)
    }
}

@Suite("Backup files (ROADMAP 4.1b task 6)")
struct BackupFileTests {
    @Test("A backup is a copy of the database: its counts and generation read back, its state loads, pruning follows the plan")
    func takeReadPrune() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let opened = try storage.open()
        let state = sampleState()
        try storage.makeWriter(for: opened).writeAndWait(state, generation: 4)
        let backups = RoomBackups(stateDirectory: directory.url)
        let now = BackupPlannerTests.now
        let file = try backups.take(from: opened.database, at: now)
        #expect(backups.list() == [file])
        let info = try backups.info(file)
        #expect(info.generation == 4 && info.entries == state.entries.count && info.spaces == 2)
        let loaded = try backups.loadState(file)
        #expect(loaded.generation == 4)
        #expect(loaded.state.canonical() == state.canonical())
        // The navigation states the JSON snapshot drops are in the backup.
        #expect(loaded.state.entries.contains { $0.navigationState != nil })
        // Eleven more today: the two oldest of the twelve go.
        for minute in 1...11 { try backups.take(from: opened.database, at: now.addingTimeInterval(Double(minute) * 60)) }
        let pruned = backups.prune(now: now.addingTimeInterval(720), schedule: BackupPlannerTests.arc,
                                   calendar: BackupPlannerTests.calendar)
        #expect(pruned.count == 2 && pruned.contains { $0.url == file.url })
        #expect(backups.list().count == 10)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
