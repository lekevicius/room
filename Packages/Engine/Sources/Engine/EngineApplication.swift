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

    public init(
        userDataDirectory: URL,
        logFile: URL? = nil,
        locale: String? = nil,
        usesSystemKeychain: Bool = true
    ) {
        self.userDataDirectory = userDataDirectory
        self.logFile = logFile
        self.locale = locale
        self.usesSystemKeychain = usesSystemKeychain
    }
}

/// The browser process: owns the main loop and process-wide state.
///
/// Phase 1.1 subset; Phase 1.2 adds profiles and features.
public protocol EngineApplication: AnyObject {
    /// Starts the engine. Must be called once, before `run()`.
    func initialize(_ configuration: EngineConfiguration) throws

    /// Runs the main loop until termination, then shuts the engine down.
    func run()

    /// Closes everything the engine owns and leaves the main loop.
    /// `completion(false)` means termination was cancelled (e.g. a beforeunload handler).
    func tryToTerminate(_ completion: @escaping (Bool) -> Void)
}
