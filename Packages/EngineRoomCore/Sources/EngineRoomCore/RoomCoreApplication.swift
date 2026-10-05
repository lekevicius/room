import AppKit
import Engine
import RoomCore

/// `EngineApplication` over RoomCore (`RoomApplication`), to the Phase 1.5
/// embryo's depth (ROADMAP 3.1a task 4): initialize, run, terminate,
/// profiles under `Room Profile <name>`, pages with load and history.
///
/// RoomCore creates NSApp from `RoomCoreNSApplication` inside `run()`, so the
/// host must not touch `NSApplication.shared` before then; it hands its
/// `NSApplicationDelegate` to `applicationDelegate` instead, which RoomCore
/// installs as NSApp's delegate as soon as NSApp exists (Chrome's
/// `AppController` is never installed, PLAN §4 Main menu, 3.2b).
public final class RoomCoreApplication: NSObject, EngineApplication, RoomApplicationDelegate {
    /// The running instance.
    public private(set) static weak var current: RoomCoreApplication?

    /// NSApp's delegate from the moment `run()` creates NSApp (links from
    /// other apps, Dock reopen, `applicationShouldTerminate`). Held weakly,
    /// as AppKit does. Set before `run()`.
    public weak var applicationDelegate: (any NSApplicationDelegate)? {
        get { core.applicationDelegate }
        set { core.applicationDelegate = newValue }
    }

    public private(set) var features = EngineFeatures()
    public var profiles: [any Profile] { loadedProfiles }
    /// Hears Chromium's memory pressure (`base::MemoryPressureListener`, 3.7b).
    public weak var delegate: (any EngineApplicationDelegate)?

    /// Chromium's registrable domain (`net::registry_controlled_domains`,
    /// private registries included), so the list updates with Chromium.
    public func site(of url: URL) -> String? {
        guard var host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return RoomApplication.site(forHost: host)
    }
    /// Chromium's `browser_shutdown::IsTryingToQuit()`: true while a quit
    /// closes the pages, false again after a beforeunload "stay".
    public var isTerminating: Bool { core.isTerminating }

    /// Prefix of a profile's directory under the user data root (the
    /// Chapter 2 layout, `Room Profile <name>`).
    public static let profileDirectoryPrefix = "Room Profile "

    private let core: RoomApplication
    private var loadedProfiles: [RoomCoreProfile] = []
    private var pendingProfiles: [String: Task<RoomCoreProfile, any Error>] = [:]
    private var isRunning = false

    /// Must be created before anything touches `NSApplication.shared`.
    override public init() {
        core = RoomApplication.shared
        super.init()
        core.delegate = self
        Self.current = self
    }

    public func initialize(_ configuration: EngineConfiguration) throws {
        try core.initialize(
            arguments: Self.productArguments(CommandLine.arguments) + Self.switches(for: configuration),
            applicationClass: RoomCoreNSApplication.self,
            userDataDirectory: configuration.userDataDirectory)
        features = configuration.features
    }

    /// The process's arguments as the engine may see them. DevTools is the
    /// host's pane, so the product never opens a remote-debugging port: a
    /// Release build drops `--remote-debugging-*` (Debug keeps them for the
    /// spikes' DevTools-protocol client, ROADMAP 3.3b).
    static func productArguments(_ arguments: [String]) -> [String] {
        #if DEBUG
        arguments
        #else
        arguments.filter { !$0.hasPrefix("--remote-debugging-") }
        #endif
    }

    /// Chromium switches for `configuration`. RoomCore adds its own defaults
    /// (a log file in the data root, the mock keychain for builds without a
    /// team signature) when these do not say otherwise.
    static func switches(for configuration: EngineConfiguration) -> [String] {
        var switches: [String] = []
        if let logFile = configuration.logFile {
            switches += ["--enable-logging", "--log-file=\(logFile.path)"]
        }
        if let locale = configuration.locale {
            switches.append("--lang=\(locale)")
        }
        if !configuration.usesSystemKeychain {
            switches.append("--use-mock-keychain")
        }
        if !configuration.features.enabled.isEmpty {
            switches.append("--enable-features=" + configuration.features.enabled.sorted().joined(separator: ","))
        }
        if !configuration.features.disabled.isEmpty {
            switches.append("--disable-features=" + configuration.features.disabled.sorted().joined(separator: ","))
        }
        return switches
    }

    public func run() {
        _ = core.run()
        isRunning = false
    }

    // MARK: RoomApplicationDelegate

    /// Before NSApp's delegate hears `applicationDidFinishLaunching`.
    public func roomApplicationDidFinishLaunching(_ application: RoomApplication) {
        isRunning = true
    }

    /// The quit is past its point of no return: every Browser is closed.
    /// Pages the host created without a window (in no Browser) close now.
    public func roomApplicationWillTerminate(_ application: RoomApplication) {
        for profile in loadedProfiles { profile.closeAll() }
    }

    /// Chromium's memory-pressure notification (each change, and repeated
    /// while a moderate or critical level lasts). RoomCore discards no Room
    /// page for it; the host's policy does.
    public func roomApplication(_ application: RoomApplication, didChangeMemoryPressure level: RoomMemoryPressureLevel) {
        let mapped: MemoryPressureLevel = switch level {
        case .critical: .critical
        case .moderate: .moderate
        default: .none
        }
        delegate?.engineApplication(self, didChangeMemoryPressure: mapped)
    }

    // MARK: Termination

    /// Chrome's close path (`BrowserCloseManager` through RoomCore's
    /// `RoomAppController`): beforeunload handlers run on every window's
    /// pages; a "stay" gives `completion(false)` with every page still open;
    /// otherwise `completion(true)` once every Browser is closed
    /// (`chrome::OnAppExiting`), before the run loop stops. `run()` returns
    /// after Chromium shut down.
    public func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        core.tryToTerminate { terminating in
            MainActor.assumeIsolated { completion(terminating) }
        }
    }

    // MARK: Profiles

    public func createProfile(name: String) async throws -> any Profile {
        try await makeProfile(name: name)
    }

    /// `createProfile` returning the concrete type.
    public func makeProfile(name: String) async throws -> RoomCoreProfile {
        guard isRunning else { throw EngineError.notRunning }
        guard Self.isValidProfileName(name) else { throw EngineError.invalidProfileName(name) }
        if let loaded = loadedProfiles.first(where: { $0.name == name }) { return loaded }
        if let pending = pendingProfiles[name] { return try await pending.value }
        let core = core
        let task = Task<RoomCoreProfile, any Error> { @MainActor in
            guard let profile = await core.createProfile(Self.profileDirectoryPrefix + name) else {
                throw EngineError.failed("RoomApplication.createProfile failed for \(name)")
            }
            return RoomCoreProfile(name: name, profile: profile)
        }
        pendingProfiles[name] = task
        defer { pendingProfiles[name] = nil }
        let profile = try await task.value
        if let loaded = loadedProfiles.first(where: { $0.name == name }) { return loaded }
        loadedProfiles.append(profile)
        return profile
    }

    nonisolated static func isValidProfileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name != "." && name != ".."
            && !name.contains("/") && !name.contains(":") && !name.hasPrefix(".")
    }
}

/// NSApp on RoomCore: Chromium's `RoomCrApplication`, which asks NSApp's
/// delegate `applicationShouldTerminate` at ⌘Q before Chrome's close path.
public final class RoomCoreNSApplication: RoomCrApplication {}
