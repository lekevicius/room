import Engine
import Integration

/// Crash reports (6.3, B-105): the engine's Crashpad already catches a crash in
/// any of Room's processes (the app's own included) and writes its minidump;
/// the user's opt-in lets it send them to the collector the build names
/// (`EngineConfiguration.crashUploadURL`). Off, they stay on disk.
final class CrashpadCrashReporter: CrashReporting {
    private let engine: any EngineApplication

    init(engine: any EngineApplication) {
        self.engine = engine
    }

    func start(dsn: String) {
        engine.crashUploadsEnabled = true
    }

    func stop() {
        engine.crashUploadsEnabled = false
    }
}
