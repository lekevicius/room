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

@Suite("First run (ROADMAP 2.8 task 4)")
struct FirstRunTests {
    final class Box {
        var settings = Settings()
        lazy var firstRun = FirstRun(read: { self.settings }, write: { body in body(&self.settings) })
    }

    @Test("A new profile shows the card with both opt-ins off; Done records it once")
    func showsOnce() {
        let box = Box()
        #expect(box.firstRun.isShowing)
        #expect(!box.firstRun.crashReports && !box.firstRun.automaticUpdateChecks)
        box.firstRun.finish()
        #expect(!box.firstRun.isShowing && box.settings.firstRunDone)
        // Declining is the default: finishing without a choice leaves both off.
        #expect(!box.settings.crashReports && !box.settings.automaticUpdateChecks)
    }

    @Test("Choices are written as they are made, to the fields the palette and the services read")
    func choices() {
        let box = Box()
        box.firstRun.searchEngine = "duckduckgo"
        box.firstRun.crashReports = true
        box.firstRun.automaticUpdateChecks = true
        #expect(box.settings.searchEngine == "duckduckgo" && box.settings.crashReports && box.settings.automaticUpdateChecks)
        // Not finished: the card is still there next launch, with the choices kept.
        #expect(box.firstRun.isShowing)
    }

    @Test("Settings brings the card back with the current choices")
    func showAgain() {
        let box = Box()
        box.firstRun.crashReports = true
        box.firstRun.finish()
        box.firstRun.showAgain()
        #expect(box.firstRun.isShowing && box.firstRun.crashReports)
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
