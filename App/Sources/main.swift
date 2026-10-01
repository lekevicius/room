import AppKit
import Engine
import Infra
#if canImport(EngineCEF)
import EngineCEF
#endif

// The engine creates NSApp (CEF needs its own NSApplication subclass), so it
// must be constructed before anything touches NSApplication.shared.
#if canImport(EngineCEF)
let engine: any EngineApplication = CEFApplication()
#else
let engine: any EngineApplication = NoEngineApplication()
#endif

let delegate = AppDelegate(engine: engine)
NSApplication.shared.delegate = delegate

do {
    let configuration = EngineConfiguration(
        userDataDirectory: try AppPaths.ensureDirectory(AppPaths.engineUserData),
        logFile: try AppPaths.ensureDirectory(AppPaths.logs).appending(path: "engine.log"),
        // Ad-hoc dev builds would hit a login-keychain prompt on every launch.
        usesSystemKeychain: CodeSignature.teamIdentifier != nil
    )
    try engine.initialize(configuration)
} catch {
    NSLog("Room: engine failed to initialize: \(error)")
    exit(1)
}

engine.run()
exit(0)
