import AppKit
import CEFBridge
import Engine

public enum CEFEngineError: Error {
    case libraryLoadFailed
}

/// `EngineApplication` backed by CEF.
public final class CEFApplication: EngineApplication {
    /// Creates the shared `NSApplication` as CEF's subclass. Must run before any
    /// other code touches `NSApp`.
    public init() {
        let app = RoomCEFApplication.shared
        precondition(app is RoomCEFApplication, "NSApp was created before CEFApplication")
        (app as? RoomCEFApplication)?.terminationHandler = { [weak self] in
            self?.tryToTerminate { _ in }
        }
    }

    public func initialize(_ configuration: EngineConfiguration) throws {
        guard RoomCEFRuntime.loadLibrary() else { throw CEFEngineError.libraryLoadFailed }
        try RoomCEFRuntime.initialize(
            withUserDataDirectory: configuration.userDataDirectory,
            logFile: configuration.logFile,
            locale: configuration.locale
        )
    }

    public func run() {
        RoomCEFRuntime.runMessageLoop()
        RoomCEFRuntime.shutdown()
    }

    public func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        // No browsers exist yet (Phase 1.1); Phase 1.4 closes them first.
        RoomCEFRuntime.quitMessageLoop()
        completion(true)
    }
}
