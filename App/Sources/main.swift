import AppKit
import Engine
import Infra
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#elseif canImport(EngineCEF)
import EngineCEF
#endif

// The engine is picked by the ROOM_ENGINE build setting (PLAN §4 Engine
// selection): `roomcore` (scheme "Room (RoomCore)") compiles with
// ROOM_ENGINE_ROOMCORE; the CEF scheme links EngineCEF; CI links neither.
//
// The engine creates NSApp (CEF and Chromium need their own NSApplication
// subclass), so it must be constructed before anything touches
// NSApplication.shared.
#if ROOM_ENGINE_ROOMCORE
let roomCore = RoomCoreApplication()
let engine: any EngineApplication = roomCore
#elseif canImport(EngineCEF)
let cefApplication = CEFApplication()
#if DEBUG
// Docked DevTools connects its front-end through this port (127.0.0.1 only).
cefApplication.remoteDebuggingPort = UserDefaults.standard.integer(forKey: "RoomDevToolsPort").nonZero ?? 9339
#endif
let engine: any EngineApplication = cefApplication
#else
let engine: any EngineApplication = NoEngineApplication()
#endif

#if ROOM_ENGINE_ROOMCORE
// RoomCore creates NSApp inside run(); until 3.2 installs RoomAppController
// (PLAN §4 Main menu) NSApp's delegate is Chrome's AppController, so the app
// delegate is created and started once RoomCore has launched. It is never
// NSApp.delegate here: links from other apps and Dock reopen still go to
// Chrome's controller (3.2).
var roomCoreDelegate: AppDelegate?
roomCore.didFinishLaunching = {
    let delegate = AppDelegate(engine: roomCore)
    roomCoreDelegate = delegate
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
}
#else
let delegate = AppDelegate(engine: engine)
NSApplication.shared.delegate = delegate
#endif

do {
    #if ROOM_ENGINE_ROOMCORE
    // ~/Library/Application Support/Room/RoomCore, separate from the CEF
    // engine's directory (different engine, different profile format).
    var engineDirectory = AppPaths.applicationSupport.appending(path: "RoomCore", directoryHint: .isDirectory)
    #else
    var engineDirectory = AppPaths.engineUserData
    #endif
    #if DEBUG
    // Spikes that write site data (the Phase 2.5 cookie check) use a throwaway engine root.
    if let override = UserDefaults.standard.string(forKey: "RoomEngineDirectory") {
        engineDirectory = URL(fileURLWithPath: override, isDirectory: true)
    }
    #endif
    #if ROOM_ENGINE_ROOMCORE
    // RoomCore logs to RoomCore.log in its data root and decides the keychain
    // by the build's code signature: a team-signed build uses "Room Safe
    // Storage" in the login keychain, an ad-hoc build the mock keychain
    // (PLAN §4 Keychain).
    let configuration = EngineConfiguration(
        userDataDirectory: try AppPaths.ensureDirectory(engineDirectory),
        usesSystemKeychain: true
    )
    #else
    let configuration = EngineConfiguration(
        userDataDirectory: try AppPaths.ensureDirectory(engineDirectory),
        logFile: try AppPaths.ensureDirectory(AppPaths.logs).appending(path: "engine.log"),
        // CEF 154's stable API cannot rename the "Chromium Safe Storage"
        // keychain item, so a signed build would share (and prompt for) the
        // item of any unbranded Chromium on the machine; ad-hoc builds would
        // prompt on every launch. CEF builds use the mock keychain; RoomCore
        // brands its own "Room Safe Storage" item.
        usesSystemKeychain: false
    )
    #endif
    try engine.initialize(configuration)
} catch {
    NSLog("Room: engine failed to initialize: \(error)")
    exit(1)
}

engine.run()
// CEF's terminate path leaves the run loop without applicationWillTerminate;
// RoomCore's run() returns after Chromium shut down.
#if ROOM_ENGINE_ROOMCORE
roomCoreDelegate?.shutdown()
#else
delegate.shutdown()
#endif
exit(0)

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
