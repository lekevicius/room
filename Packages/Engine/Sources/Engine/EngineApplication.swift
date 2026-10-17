import Foundation

/// Process-wide settings handed to the engine before it starts.
public struct EngineConfiguration: Sendable {
    /// Root of the engine's on-disk state (profiles, caches).
    public var userDataDirectory: URL
    /// Engine log file; `nil` lets the engine choose.
    public var logFile: URL?
    /// UI locale such as `en-US`; `nil` follows the system.
    public var locale: String?
    /// Whether the engine keeps its encryption key (cookies, passwords) in the
    /// login keychain. Ad-hoc signed builds get a new code identity on every
    /// build, so the keychain prompts on each launch; those use an in-memory key.
    public var usesSystemKeychain: Bool
    /// Chromium feature names (`base::Feature`) forced on or off for this run,
    /// the equivalent of `--enable-features` / `--disable-features`.
    public var features: EngineFeatures

    public init(
        userDataDirectory: URL,
        logFile: URL? = nil,
        locale: String? = nil,
        usesSystemKeychain: Bool = true,
        features: EngineFeatures = EngineFeatures()
    ) {
        self.userDataDirectory = userDataDirectory
        self.logFile = logFile
        self.locale = locale
        self.usesSystemKeychain = usesSystemKeychain
        self.features = features
    }
}

/// Chromium feature overrides. Chromium fixes its feature list at startup, so
/// these are set in `EngineConfiguration` and read back from the application;
/// features not listed keep the engine's default.
nonisolated public struct EngineFeatures: Sendable, Hashable {
    public var enabled: Set<String>
    public var disabled: Set<String>

    public init(enabled: Set<String> = [], disabled: Set<String> = []) {
        self.enabled = enabled
        self.disabled = disabled
    }

    /// `true`/`false` for an overridden feature, `nil` for the engine default.
    public func isEnabled(_ feature: String) -> Bool? {
        if disabled.contains(feature) { return false }
        if enabled.contains(feature) { return true }
        return nil
    }
}

/// The browser process: owns the main loop, process-wide state and the
/// profile registry.
@MainActor
public protocol EngineApplication: AnyObject {
    /// Starts the engine. Must be called once, before `run()`.
    func initialize(_ configuration: EngineConfiguration) throws

    /// Runs the main loop until termination, then shuts the engine down.
    func run()

    /// Closes everything the engine owns and leaves the main loop.
    /// `completion(false)` means termination was cancelled (e.g. a beforeunload handler).
    func tryToTerminate(_ completion: @escaping (Bool) -> Void)

    /// A termination is under way: pages closing now are closed by the
    /// engine, not by the user or the page (Chromium
    /// `browser_shutdown::IsTryingToQuit()`). Becomes `false` again when a
    /// beforeunload handler cancels it.
    var isTerminating: Bool { get }

    /// Feature overrides in effect for this run.
    var features: EngineFeatures { get }

    /// Hears process-wide engine events (memory pressure).
    var delegate: (any EngineApplicationDelegate)? { get set }

    /// Profiles loaded in this run, in creation order.
    var profiles: [any Profile] { get }

    /// Loads the profile stored under `name`, creating it on disk if needed.
    /// Returns the already-loaded profile when called twice with one name.
    /// Valid only while the main loop runs.
    func createProfile(name: String) async throws -> any Profile

    /// Deletes `profile` and its directory (4.4b): the engine lets go of it,
    /// it leaves `profiles`, and its data (cookies, history, passwords,
    /// cache, settings) is removed from disk before this returns. Every page
    /// of the profile must be closed first: with one still open it throws
    /// `EngineError.profileInUse` and changes nothing. RoomCore:
    /// `ProfileManager`'s unload of a profile marked for deletion
    /// (`NukeProfileFromDisk`); the fake forgets it.
    func deleteProfile(_ profile: any Profile) async throws

    /// The site of `url` as the engine counts it for same-site rules (spec
    /// §A.4 "same eTLD+1", Peek): the registrable domain of its host by the
    /// Public Suffix List with the private section, lower-case and in
    /// punycode; an IP address, `localhost` or any host without a
    /// registrable domain is its own site; `nil` without a host (`about:`,
    /// `data:`, `file:`). RoomCore: Chromium's
    /// `net::registry_controlled_domains`; the fake and no engine: the bundled
    /// `PublicSuffixList`.
    func site(of url: URL) -> String?

    /// Room's built-in ad and tracker blocker, one for the whole app (B-30);
    /// `nil` when the engine has none (no engine).
    var contentBlocking: (any ContentBlocking)? { get }
}

/// The system's memory pressure as the engine reports it (Chromium
/// `base::MemoryPressureLevel`).
nonisolated public enum MemoryPressureLevel: Int, Sendable, Hashable, Comparable {
    case none, moderate, critical

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Process-wide engine events.
@MainActor
public protocol EngineApplicationDelegate: AnyObject {
    /// The memory-pressure level changed, or a moderate or critical level
    /// lasts (the engine repeats it). The engine discards none of the host's
    /// pages for it: the host's policy decides (RoomCore). An engine that
    /// never calls it leaves the host to listen to the system itself.
    func engineApplication(_ application: any EngineApplication, didChangeMemoryPressure level: MemoryPressureLevel)
}

public extension EngineApplication {
    var contentBlocking: (any ContentBlocking)? { nil }

    /// Both URLs have a host and the same site (`site(of:)`).
    func isSameSite(_ a: URL, _ b: URL) -> Bool {
        guard let siteA = site(of: a), let siteB = site(of: b) else { return false }
        return siteA == siteB
    }
}
