import AppKit
import Engine
import RoomCore

/// `EngineApplication` over RoomCore (`RoomApplication`), to the Phase 1.5
/// embryo's depth (ROADMAP 3.1a task 4): initialize, run, terminate,
/// profiles under `Room Profile <name>`, pages with load and history.
///
/// RoomCore creates NSApp from `RoomCoreNSApplication` inside `run()`, so the
/// host must not touch `NSApplication.shared` before then. Until 3.2 installs
/// `RoomAppController` (PLAN §4 Main menu), NSApp's delegate is Chrome's
/// `AppController`: the host's launch work runs from `didFinishLaunching`.
public final class RoomCoreApplication: NSObject, EngineApplication, RoomApplicationDelegate {
    /// The running instance (`RoomCoreNSApplication` reaches it at ⌘Q).
    public private(set) static weak var current: RoomCoreApplication?

    /// Called once RoomCore has launched: NSApp exists, Chrome's own launch
    /// is done, profiles can be created. The host builds its UI here.
    public var didFinishLaunching: (() -> Void)?

    public private(set) var features = EngineFeatures()
    public var profiles: [any Profile] { loadedProfiles }
    public var isTerminating: Bool { terminating }

    /// Prefix of a profile's directory under the user data root; the same
    /// layout as the CEF engine (`CEFApplication.profileDirectoryPrefix`), so
    /// one engine directory serves either engine's profile names.
    public static let profileDirectoryPrefix = "Room Profile "

    private let core: RoomApplication
    private var loadedProfiles: [RoomCoreProfile] = []
    private var pendingProfiles: [String: Task<RoomCoreProfile, any Error>] = [:]
    private var isRunning = false
    private var terminating = false

    /// Must be created before anything touches `NSApplication.shared`.
    override public init() {
        core = RoomApplication.shared
        super.init()
        core.delegate = self
        Self.current = self
    }

    public func initialize(_ configuration: EngineConfiguration) throws {
        try core.initialize(
            arguments: CommandLine.arguments + Self.switches(for: configuration),
            applicationClass: RoomCoreNSApplication.self,
            userDataDirectory: configuration.userDataDirectory)
        features = configuration.features
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

    public func roomApplicationDidFinishLaunching(_ application: RoomApplication) {
        isRunning = true
        didFinishLaunching?()
    }

    // MARK: Termination

    /// Closes every page (no beforeunload handlers at this depth), then lets
    /// Chromium shut down; `run()` returns when it has.
    public func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        closeAllPages()
        completion(true)
        core.tryToTerminate()
    }

    /// Pages are not in a Chrome tab strip (3.2 adds `RoomBrowser` per
    /// window), so Chrome's shutdown does not close them: they go first.
    func closeAllPages() {
        terminating = true
        for profile in loadedProfiles { profile.closeAll() }
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

/// NSApp on RoomCore: Chromium's `RoomCrApplication`, plus the page cleanup
/// ⌘Q needs before Chrome's own orderly quit (the CEF engine's
/// `terminationHandler` counterpart).
public final class RoomCoreNSApplication: RoomCrApplication {
    override public func terminate(_ sender: Any?) {
        RoomCoreApplication.current?.closeAllPages()
        super.terminate(sender)
    }
}
