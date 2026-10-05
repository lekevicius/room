import AppKit
import Engine
import Infra
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif

// The engine is picked by the ROOM_ENGINE build setting (PLAN §4 Engine
// selection): `roomcore` (the default; target RoomCoreApp, scheme
// "Room (RoomCore)") compiles with ROOM_ENGINE_ROOMCORE; `none` (the Room
// target CI builds, xcodegen/base.yml) links no engine.
//
// The engine creates NSApp (Chromium needs its own NSApplication subclass),
// so it must be constructed before anything touches NSApplication.shared.
#if ROOM_ENGINE_ROOMCORE
let roomCore = RoomCoreApplication()
let engine: any EngineApplication = roomCore
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
    // ~/Library/Application Support/Room/RoomCore: the engine's data root.
    var engineDirectory = AppPaths.engineUserData
    #if DEBUG
    // Spikes that write site data (the Phase 2.5 cookie check) use a throwaway engine root.
    if let override = UserDefaults.standard.string(forKey: "RoomEngineDirectory") {
        engineDirectory = URL(fileURLWithPath: override, isDirectory: true)
    }
    #endif
    // RoomCore logs to RoomCore.log in its data root and decides the keychain
    // by the build's code signature: a team-signed build uses "Room Safe
    // Storage" in the login keychain, an ad-hoc build the mock keychain
    // (PLAN §4 Keychain).
    let configuration = EngineConfiguration(
        userDataDirectory: try AppPaths.ensureDirectory(engineDirectory),
        usesSystemKeychain: true
    )
    try engine.initialize(configuration)
} catch {
    NSLog("Room: engine failed to initialize: \(error)")
    exit(1)
}

engine.run()
// RoomCore's run() returns after Chromium shut down (the delegate wrote the
// final state before it let the quit proceed; this is a no-op then).
delegate.shutdown()
exit(0)
