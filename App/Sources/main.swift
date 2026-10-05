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

let delegate = AppDelegate(engine: engine)
#if ROOM_ENGINE_ROOMCORE
// RoomCore creates NSApp inside run() and installs the delegate as soon as it
// exists (Chrome's AppController is never installed, PLAN §4 Main menu): links
// from other apps, Dock reopen and applicationShouldTerminate are Room's.
roomCore.applicationDelegate = delegate
#else
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
// RoomCore's run() returns after Chromium shut down (the delegate wrote the
// final state before it let the quit proceed; this is a no-op then).
delegate.shutdown()
exit(0)

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
