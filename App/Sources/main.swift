import AppKit
import Engine
import Infra
#if canImport(EngineCEF)
import EngineCEF
#endif

// The engine creates NSApp (CEF needs its own NSApplication subclass), so it
// must be constructed before anything touches NSApplication.shared.
#if canImport(EngineCEF)
let cefApplication = CEFApplication()
#if DEBUG
// Docked DevTools connects its front-end through this port (127.0.0.1 only).
cefApplication.remoteDebuggingPort = UserDefaults.standard.integer(forKey: "RoomDevToolsPort").nonZero ?? 9339
#endif
let engine: any EngineApplication = cefApplication
#else
let engine: any EngineApplication = NoEngineApplication()
#endif

let delegate = AppDelegate(engine: engine)
NSApplication.shared.delegate = delegate

do {
    var engineDirectory = AppPaths.engineUserData
    #if DEBUG
    // Spikes that write site data (the Phase 2.5 cookie check) use a throwaway engine root.
    if let override = UserDefaults.standard.string(forKey: "RoomEngineDirectory") {
        engineDirectory = URL(fileURLWithPath: override, isDirectory: true)
    }
    #endif
    let configuration = EngineConfiguration(
        userDataDirectory: try AppPaths.ensureDirectory(engineDirectory),
        logFile: try AppPaths.ensureDirectory(AppPaths.logs).appending(path: "engine.log"),
        // CEF 154's stable API cannot rename the "Chromium Safe Storage"
        // keychain item, so a signed build would share (and prompt for) the
        // item of any unbranded Chromium on the machine; ad-hoc builds would
        // prompt on every launch. CEF builds use the mock keychain; RoomCore
        // (Chapter 3) brands its own "Room Safe Storage" item.
        usesSystemKeychain: false
    )
    try engine.initialize(configuration)
} catch {
    NSLog("Room: engine failed to initialize: \(error)")
    exit(1)
}

engine.run()
// CEF's terminate path leaves the run loop without applicationWillTerminate.
delegate.shutdown()
exit(0)

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
