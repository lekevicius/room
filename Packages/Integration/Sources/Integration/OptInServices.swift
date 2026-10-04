import Foundation

/// The updater (Sparkle): starting it reads its schedule; it checks the feed
/// on its own only while `automaticallyChecks` is on.
public protocol UpdateChecking: AnyObject {
    var automaticallyChecks: Bool { get set }
    /// No check is running (the menu item's state).
    var canCheckNow: Bool { get }
    func start() throws
    /// A check the user asked for; it shows its own result.
    func checkNow()
}

/// The crash reporter (Sentry): nothing runs until `start`.
public protocol CrashReporting: AnyObject {
    func start(dsn: String)
    func stop()
}

/// The two services that would talk to the network without being asked,
/// each behind its opt-in (ROADMAP 2.8 task 5, AGENTS.md "no network calls
/// the user did not ask for"): while an opt-in is off its service is not
/// even created, so nothing of it runs at launch, in the background or at
/// quit. A check the user asks for (App ▸ Check for Updates…) creates and
/// starts the updater with its schedule still following the setting.
public final class OptInServices {
    /// The crash reporter's DSN; empty until a Sentry project exists (then crash reports stay off).
    public let dsn: String
    private let makeUpdater: () -> any UpdateChecking
    private let makeCrashReporter: () -> any CrashReporting
    public private(set) var updater: (any UpdateChecking)?
    public private(set) var crashReporter: (any CrashReporting)?
    /// The crash reporter is started.
    public private(set) var isReportingCrashes = false

    public init(dsn: String, makeUpdater: @escaping () -> any UpdateChecking,
                makeCrashReporter: @escaping () -> any CrashReporting) {
        self.dsn = dsn
        self.makeUpdater = makeUpdater
        self.makeCrashReporter = makeCrashReporter
    }

    /// Brings both services in line with the settings, at launch and on every change.
    public func apply(crashReports: Bool, automaticUpdateChecks: Bool) {
        if crashReports, !dsn.isEmpty, !isReportingCrashes {
            let reporter = crashReporter ?? makeCrashReporter()
            crashReporter = reporter
            reporter.start(dsn: dsn)
            isReportingCrashes = true
        } else if !crashReports, isReportingCrashes {
            crashReporter?.stop()
            isReportingCrashes = false
        }
        if automaticUpdateChecks {
            startedUpdater(automaticallyChecks: true)
        } else {
            // Sparkle cannot be stopped; its schedule is turned off. Never created while off.
            updater?.automaticallyChecks = false
        }
    }

    /// App ▸ Check for Updates…: the user asked, so the updater starts if it has not.
    public func checkForUpdates(automaticUpdateChecks: Bool) {
        startedUpdater(automaticallyChecks: automaticUpdateChecks)?.checkNow()
    }

    /// The menu item is enabled unless a check is running.
    public var canCheckForUpdates: Bool { updater?.canCheckNow ?? true }

    /// Crash reports cannot be sent from this build (no DSN yet).
    public var crashReportsUnavailable: Bool { dsn.isEmpty }

    /// The schedule is set before the start, so a start never runs on a stale one.
    @discardableResult
    private func startedUpdater(automaticallyChecks: Bool) -> (any UpdateChecking)? {
        if let updater {
            updater.automaticallyChecks = automaticallyChecks
            return updater
        }
        let updater = makeUpdater()
        updater.automaticallyChecks = automaticallyChecks
        do {
            try updater.start()
        } catch {
            NSLog("Room: the updater did not start: \(error)")
            return nil
        }
        self.updater = updater
        return updater
    }
}

/// Values the build carries in its Info.plist, set in one place (`xcodegen/base.yml`).
public enum BuildConfiguration {
    /// `RoomSentryDSN` (`ROOM_SENTRY_DSN`): empty until the user creates a Sentry project.
    public static func sentryDSN(_ bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "RoomSentryDSN") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// `SUFeedURL` (`ROOM_UPDATE_FEED_URL`): a placeholder until the product name is settled (B-6).
    public static func updateFeedURL(_ bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
    }
}
