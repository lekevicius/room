import AppKit
import Engine

/// A pure-Swift engine for unit tests and UI previews. Pages are an
/// `NSTextView` showing the URL; page-side events (link clicks, dialogs,
/// permission requests, crashes) are triggered with the `simulate…` methods
/// on `FakeWebContents` and `FakeProfile`.
public final class FakeApplication: EngineApplication {
    public private(set) var configuration: EngineConfiguration?
    public private(set) var fakeProfiles: [FakeProfile] = []
    public weak var delegate: (any EngineApplicationDelegate)?
    /// The last level `simulateMemoryPressure` reported.
    public private(set) var memoryPressure = MemoryPressureLevel.none

    /// The engine reports memory pressure (RoomCore's `base::MemoryPressureListener`).
    public func simulateMemoryPressure(_ level: MemoryPressureLevel) {
        memoryPressure = level
        delegate?.engineApplication(self, didChangeMemoryPressure: level)
    }
    private var isRunning = false

    public init() {}

    public func initialize(_ configuration: EngineConfiguration) throws {
        guard self.configuration == nil else { throw EngineError.failed("initialize called twice") }
        self.configuration = configuration
    }

    public func run() {
        isRunning = true
        NSApplication.shared.run()
        isRunning = false
    }

    public private(set) var isTerminating = false

    public func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        let open = fakeProfiles.flatMap(\.openWebContents)
        isTerminating = true
        Self.confirmUnload(open[...]) { [weak self] proceed in
            guard proceed else {
                self?.isTerminating = false
                return completion(false)
            }
            for contents in open { contents.closeNow() }
            completion(true)
            if self?.isRunning == true { NSApplication.shared.stop(nil) }
        }
    }

    public var features: EngineFeatures {
        configuration?.features ?? EngineFeatures()
    }

    public var profiles: [any Profile] { fakeProfiles }

    /// The bundled Public Suffix List (RoomCore asks Chromium).
    public func site(of url: URL) -> String? { PublicSuffixList.site(of: url) }

    public func createProfile(name: String) async throws -> any Profile {
        try profile(named: name)
    }

    /// Synchronous `createProfile` for tests and previews.
    public func profile(named name: String) throws -> FakeProfile {
        guard configuration != nil else { throw EngineError.notRunning }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else {
            throw EngineError.invalidProfileName(name)
        }
        if let existing = fakeProfiles.first(where: { $0.name == name }) { return existing }
        let profile = FakeProfile(name: name)
        fakeProfiles.append(profile)
        return profile
    }

    /// Asks each page's beforeunload handler in turn; stops at the first "stay".
    private static func confirmUnload(_ pages: ArraySlice<FakeWebContents>, _ completion: @escaping (Bool) -> Void) {
        guard let first = pages.first else { return completion(true) }
        first.confirmUnload(isReload: false) { proceed in
            guard proceed else { return completion(false) }
            confirmUnload(pages.dropFirst(), completion)
        }
    }
}
