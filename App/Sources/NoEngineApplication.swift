#if !canImport(EngineCEF) && !ROOM_ENGINE_ROOMCORE
import AppKit
import Engine

/// Stand-in used when the app is compiled without an engine (CI compile check).
final class NoEngineApplication: EngineApplication {
    func initialize(_ configuration: EngineConfiguration) throws {}

    func run() {
        NSApplication.shared.run()
    }

    func tryToTerminate(_ completion: @escaping (Bool) -> Void) {
        completion(true)
        NSApplication.shared.stop(nil)
    }

    var isTerminating: Bool { false }

    var features: EngineFeatures { EngineFeatures() }

    var profiles: [any Profile] { [] }

    func createProfile(name: String) async throws -> any Profile {
        throw EngineError.notSupported("NoEngineApplication.createProfile")
    }

    func site(of url: URL) -> String? { PublicSuffixList.site(of: url) }
}
#endif
