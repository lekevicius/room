import AppKit
import Infra
import RoomCore

// Room on RoomCore (Phase 1.5 embryo): the Phase 1.3 window with a page from
// our Chromium fork. RoomCore creates NSApp from RoomHostApplication inside
// run(), so nothing here may touch NSApplication.shared before that.

let host = HostController()
let core = RoomApplication.shared
core.delegate = host

do {
    // Separate from the CEF build's Engine directory: different engine,
    // different profile format.
    let userData = try AppPaths.ensureDirectory(
        AppPaths.applicationSupport.appending(path: "RoomCore", directoryHint: .isDirectory))
    try core.initialize(
        arguments: CommandLine.arguments,
        applicationClass: RoomHostApplication.self,
        userDataDirectory: userData
    )
} catch {
    NSLog("Room: RoomCore failed to initialize: \(error)")
    exit(1)
}

exit(core.run())
