import Foundation
import Integration
import Model
import Testing

@Suite("URL inbox (ROADMAP 2.8 task 3)")
struct URLInboxTests {
    @Test("Links before the store and engine are up wait, and open in order once they are")
    func queuedUntilOpen() {
        let inbox = URLInbox()
        let first = URL(string: "https://example.com/a")!, second = URL(string: "http://example.org/b")!
        #expect(inbox.receive([first]) == [first])
        inbox.receive([second])
        #expect(inbox.pending == [first, second] && !inbox.isOpen)
        var delivered: [[URL]] = []
        inbox.open { delivered.append($0) }
        #expect(delivered == [[first, second]] && inbox.pending.isEmpty)
    }

    @Test("After the engine is up a link is handed on at once, nothing is queued")
    func deliveredWhenOpen() {
        let inbox = URLInbox()
        var delivered: [[URL]] = []
        inbox.open { delivered.append($0) }
        #expect(delivered.isEmpty)
        let link = URL(string: "https://example.com/")!
        inbox.receive([link])
        #expect(delivered == [[link]] && inbox.pending.isEmpty)
    }

    @Test("Web pages and files are Room's; other schemes and hostless URLs are dropped")
    func schemes() {
        let inbox = URLInbox()
        let file = URL(fileURLWithPath: "/tmp/page.html")
        let taken = inbox.receive([URL(string: "mailto:a@example.com")!, URL(string: "https:///nohost")!, file,
                                   URL(string: "ftp://example.com/")!, URL(string: "HTTPS://Example.com/")!])
        #expect(taken == [file, URL(string: "HTTPS://Example.com/")!])
        #expect(inbox.receive([URL(string: "room-unknown:x")!]).isEmpty)
    }
}

@Suite("Onboarding (5.7b, B-121)")
struct OnboardingTests {
    final class Box {
        var settings = Settings()
        var writes = 0
        lazy var onboarding = Onboarding(read: { self.settings }, write: { body in self.writes += 1; body(&self.settings) })
    }

    @Test("It shows on a first launch only: a new state, never one that finished or skipped it (or the card before it)")
    func showsAtLaunch() {
        var settings = Settings()
        #expect(Onboarding.showsAtLaunch(settings))
        settings.firstRunDone = true
        #expect(!Onboarding.showsAtLaunch(settings))
    }

    @Test("Skip at any step writes that it is done and nothing else: the opt-ins stay off, the engine and appearance as they were",
          arguments: Onboarding.Step.allCases)
    func skipWritesOnlyDone(at step: Onboarding.Step) {
        let box = Box()
        for _ in 0..<step.rawValue { box.onboarding.next() }
        #expect(box.onboarding.step == step && box.writes == 0)
        let before = box.settings
        box.onboarding.skip()
        #expect(box.onboarding.ending == .skipped(at: step))
        #expect(box.settings.firstRunDone && box.writes == 1)
        var expected = before
        expected.firstRunDone = true
        #expect(box.settings == expected)
        #expect(!box.settings.crashReports && !box.settings.automaticUpdateChecks)
        #expect(!Onboarding.showsAtLaunch(box.settings))
        // Ended: nothing moves it on.
        box.onboarding.next()
        #expect(box.onboarding.ending == .skipped(at: step) && box.writes == 1)
    }

    @Test("Continue without a choice skips a step; past the last it is finished and done")
    func continueToTheEnd() {
        let box = Box()
        #expect(box.onboarding.isFirst)
        for expected in Onboarding.Step.allCases.dropFirst() {
            box.onboarding.next()
            #expect(box.onboarding.step == expected && box.onboarding.ending == nil)
        }
        #expect(box.onboarding.isLast && !box.settings.firstRunDone)
        box.onboarding.next()
        #expect(box.onboarding.ending == .finished && box.settings.firstRunDone)
        #expect(!box.settings.crashReports && !box.settings.automaticUpdateChecks)
    }

    @Test("Choices are written as they are made: closing halfway keeps them, and the next launch shows it again")
    func choices() {
        let box = Box()
        box.onboarding.searchEngine = "duckduckgo"
        box.onboarding.crashReports = true
        box.onboarding.automaticUpdateChecks = true
        box.onboarding.appearance = .dark
        #expect(box.settings.searchEngine == "duckduckgo" && box.settings.crashReports && box.settings.automaticUpdateChecks)
        #expect(box.settings.appearance == .dark)
        #expect(Onboarding.showsAtLaunch(box.settings))
    }

    @Test("From the Help menu it starts at the welcome with the current choices, and leaves done alone until it ends")
    func restart() {
        let box = Box()
        box.onboarding.crashReports = true
        box.onboarding.next()
        box.onboarding.skip()
        box.onboarding.restart()
        #expect(box.onboarding.step == .welcome && box.onboarding.ending == nil)
        #expect(box.settings.firstRunDone && box.onboarding.crashReports)
        box.onboarding.back()
        #expect(box.onboarding.step == .welcome)
    }
}

@Suite("Opt-in services (ROADMAP 2.8 task 5)")
struct OptInServicesTests {
    final class Log {
        var events: [String] = []
    }

    final class FakeUpdater: UpdateChecking {
        let log: Log
        init(log: Log) { self.log = log; log.events.append("updater.create") }
        var automaticallyChecks = false {
            didSet { log.events.append("updater.automatic=\(automaticallyChecks)") }
        }
        var canCheckNow = true
        func start() throws { log.events.append("updater.start") }
        func checkNow() { log.events.append("updater.check") }
    }

    final class FakeReporter: CrashReporting {
        let log: Log
        init(log: Log) { self.log = log; log.events.append("reporter.create") }
        func start(dsn: String) { log.events.append("reporter.start \(dsn)") }
        func stop() { log.events.append("reporter.stop") }
    }

    func services(dsn: String = "https://key@sentry.example/1") -> (OptInServices, Log) {
        let log = Log()
        return (OptInServices(dsn: dsn, makeUpdater: { FakeUpdater(log: log) }, makeCrashReporter: { FakeReporter(log: log) }), log)
    }

    @Test("Both declined: neither service is created at launch nor on any later apply")
    func declined() {
        let (services, log) = services()
        services.apply(crashReports: false, automaticUpdateChecks: false)
        services.apply(crashReports: false, automaticUpdateChecks: false)
        #expect(log.events.isEmpty)
        #expect(services.updater == nil && services.crashReporter == nil && !services.isReportingCrashes)
    }

    @Test("Crash reports: started once when opted in, stopped when opted out, never without a DSN")
    func crashReports() {
        let (services, log) = services()
        services.apply(crashReports: true, automaticUpdateChecks: false)
        services.apply(crashReports: true, automaticUpdateChecks: false)
        services.apply(crashReports: false, automaticUpdateChecks: false)
        #expect(log.events == ["reporter.create", "reporter.start https://key@sentry.example/1", "reporter.stop"])
        let (noDSN, noDSNLog) = self.services(dsn: "")
        noDSN.apply(crashReports: true, automaticUpdateChecks: false)
        #expect(noDSNLog.events.isEmpty && noDSN.crashReportsUnavailable && !noDSN.isReportingCrashes)
    }

    @Test("Automatic checks: the schedule is set before the updater starts; off turns the schedule off")
    func automaticChecks() {
        let (services, log) = services()
        services.apply(crashReports: false, automaticUpdateChecks: true)
        #expect(log.events == ["updater.create", "updater.automatic=true", "updater.start"])
        log.events = []
        services.apply(crashReports: false, automaticUpdateChecks: false)
        #expect(log.events == ["updater.automatic=false"])
    }

    @Test("A check the user asks for starts the updater with its schedule still off")
    func manualCheck() {
        let (services, log) = services()
        services.apply(crashReports: false, automaticUpdateChecks: false)
        services.checkForUpdates(automaticUpdateChecks: false)
        #expect(log.events == ["updater.create", "updater.automatic=false", "updater.start", "updater.check"])
        #expect(services.updater?.automaticallyChecks == false)
    }
}
