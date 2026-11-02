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
    /// An update was downloaded and installs when Room quits (5.13: updates download on their own
    /// while checks are automatic): its version, and what installs it and relaunches now.
    var onReadyToInstall: ((_ version: String, _ installNow: @escaping @MainActor () -> Void) -> Void)? { get set }
}

/// The crash reporter (6.3: the engine's Crashpad, uploading to the user's
/// own collector): nothing is sent until `start`.
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
    /// The crash collector's DSN; empty until the user's collector exists (then crash reports stay off).
    public let dsn: String
    private let makeUpdater: () -> any UpdateChecking
    private let makeCrashReporter: () -> any CrashReporting
    public private(set) var updater: (any UpdateChecking)?
    public private(set) var crashReporter: (any CrashReporting)?
    /// The crash reporter is started.
    public private(set) var isReportingCrashes = false
    /// A downloaded update waits for a restart (the sidebar's banner, 5.13); passed to the updater.
    public var onUpdateReady: ((_ version: String, _ installNow: @escaping @MainActor () -> Void) -> Void)? {
        didSet { updater?.onReadyToInstall = onUpdateReady }
    }

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
        updater.onReadyToInstall = onUpdateReady
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
    /// `RoomCrashDSN` (`ROOM_CRASH_DSN`): empty until the user's crash collector exists.
    public static func crashDSN(_ bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "RoomCrashDSN") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// `SUFeedURL` (`ROOM_UPDATE_FEED_URL`): a placeholder until the product name is settled (B-6).
    public static func updateFeedURL(_ bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
    }
}

/// The crash collector's addresses (6.3, B-105; `tools/crash-collector/`). Its DSN has Sentry's
/// shape, `https://<key>@<host>/<project>`, so GlitchTip or Bugsink can take its place by a
/// host name (research/notes/crash-reporting.md).
public enum CrashCollector {
    /// Where Crashpad posts a minidump: `https://<host>/api/<project>/minidump/?sentry_key=<key>`;
    /// `nil` for an empty or malformed DSN.
    public static func minidumpURL(dsn: String) -> URL? {
        guard let components = URLComponents(string: dsn), let scheme = components.scheme, let host = components.host,
              let key = components.user, !key.isEmpty else { return nil }
        let project = components.path.split(separator: "/").last.map(String.init) ?? ""
        guard !project.isEmpty else { return nil }
        var url = URLComponents()
        url.scheme = scheme
        url.host = host
        url.port = components.port
        url.path = "/api/\(project)/minidump/"
        url.queryItems = [URLQueryItem(name: "sentry_key", value: key)]
        return url.url
    }
}
