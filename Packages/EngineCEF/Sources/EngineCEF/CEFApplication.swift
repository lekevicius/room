import AppKit
import CEFBridge
import Engine

public enum CEFEngineError: Error {
    case libraryLoadFailed
}

/// `EngineApplication` backed by CEF.
public final class CEFApplication: EngineApplication {
    /// The running instance; web contents report beforeunload cancellation here.
    public private(set) static weak var current: CEFApplication?

    public private(set) var features = EngineFeatures()
    /// Never told anything: CEF reports no memory pressure (the host listens
    /// to the system itself, 2.3).
    public weak var delegate: (any EngineApplicationDelegate)?
    /// DevTools remote-debugging port on 127.0.0.1, set before `initialize`;
    /// 0 = off. Docked DevTools needs it (`CEFDevTools`); any local process
    /// can drive the browser through it, so only Debug builds turn it on.
    public var remoteDebuggingPort = 0
    public private(set) var profiles: [any Profile] = []

    /// CEF exposes no registry-controlled-domain API: the bundled Public
    /// Suffix List (Chromium 154's, IDN rules skipped; B-34).
    public func site(of url: URL) -> String? { PublicSuffixList.site(of: url) }

    private var userDataDirectory: URL?
    private var isRunning = false
    private var pendingProfiles: [String: Task<CEFProfile, any Error>] = [:]
    private var terminationCompletions: [(Bool) -> Void] = []
    private var closeObserver: (any NSObjectProtocol)?

    /// Creates the shared `NSApplication` as CEF's subclass. Must run before any
    /// other code touches `NSApp`.
    public init() {
        let app = RoomCEFApplication.shared
        precondition(app is RoomCEFApplication, "NSApp was created before CEFApplication")
        (app as? RoomCEFApplication)?.terminationHandler = { [weak self] in
            self?.tryToTerminate { _ in }
        }
        Self.current = self
    }

    public func initialize(_ configuration: EngineConfiguration) throws {
        guard RoomCEFRuntime.loadLibrary() else { throw CEFEngineError.libraryLoadFailed }
        try RoomCEFRuntime.initialize(
            withUserDataDirectory: configuration.userDataDirectory,
            logFile: configuration.logFile,
            locale: configuration.locale,
            useMockKeychain: !configuration.usesSystemKeychain,
            enabledFeatures: configuration.features.enabled.sorted(),
            disabledFeatures: configuration.features.disabled.sorted(),
            remoteDebuggingPort: remoteDebuggingPort
        )
        features = configuration.features
        userDataDirectory = configuration.userDataDirectory
    }

    public func run() {
        isRunning = true
        RoomCEFRuntime.runMessageLoop()
        isRunning = false
        RoomCEFRuntime.shutdown()
    }

    // MARK: Termination

    /// Closes every browser (beforeunload handlers run), then leaves the
    /// message loop once the last `OnBeforeClose` arrived (cefsimple's order:
    /// CefQuitMessageLoop only after all browsers closed).
    public var isTerminating: Bool { !terminationCompletions.isEmpty }

    public func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        terminationCompletions.append(completion)
        guard terminationCompletions.count == 1 else { return }
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(
                forName: RoomCEFBrowser.didCloseNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishTerminationIfIdle() }
            }
        }
        for browser in RoomCEFBrowser.liveBrowsers() {
            _ = browser.tryClose()
        }
        finishTerminationIfIdle()
    }

    /// A beforeunload dialog answered "stay": termination stops; browsers that
    /// already closed stay closed (Chrome behaves the same).
    func cancelTermination() {
        let completions = terminationCompletions
        terminationCompletions = []
        completions.forEach { $0(false) }
    }

    private func finishTerminationIfIdle() {
        guard !terminationCompletions.isEmpty, RoomCEFBrowser.liveBrowsers().isEmpty else { return }
        let completions = terminationCompletions
        terminationCompletions = []
        RoomCEFRuntime.quitMessageLoop()
        completions.forEach { $0(true) }
    }

    // MARK: Profiles

    public func createProfile(name: String) async throws -> any Profile {
        try await makeProfile(name: name)
    }

    /// `createProfile` returning the concrete type.
    public func makeProfile(name: String) async throws -> CEFProfile {
        guard let userDataDirectory, isRunning else { throw EngineError.notRunning }
        guard Self.isValidProfileName(name) else { throw EngineError.invalidProfileName(name) }
        if let loaded = profiles.first(where: { $0.name == name }) as? CEFProfile { return loaded }
        if let pending = pendingProfiles[name] { return try await pending.value }

        // CEF loads a disk profile only when cache_path is a direct child of
        // root_cache_path (chrome_browser_context.cc); anything deeper silently
        // becomes an off-the-record profile. The prefix keeps our names clear
        // of Chromium's own entries there ("Default", "Local State", …).
        let path = userDataDirectory.appending(path: Self.profileDirectoryPrefix + name, directoryHint: .isDirectory)
        let task = Task<CEFProfile, any Error> {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let context: RoomCEFRequestContext? = await withCheckedContinuation { continuation in
                RoomCEFRequestContext.create(withCachePath: path.path) { continuation.resume(returning: $0) }
            }
            guard let context else { throw EngineError.failed("CefRequestContext::CreateContext failed for \(name)") }
            return CEFProfile(name: name, context: context)
        }
        pendingProfiles[name] = task
        defer { pendingProfiles[name] = nil }
        let profile = try await task.value
        profiles.append(profile)
        return profile
    }

    static let profileDirectoryPrefix = "Room Profile "

    static func isValidProfileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name != "." && name != ".."
            && !name.contains("/") && !name.contains(":") && !name.hasPrefix(".")
    }
}
