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
    let requestedDirectory = UserDefaults.standard.string(forKey: "RoomUserDataDir")
    let userData = try AppPaths.ensureDirectory(
        requestedDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.applicationSupport.appending(path: "RoomCore", directoryHint: .isDirectory))
    // Ad-hoc builds get a new code identity per build, so macOS asks for the
    // login password before every read of the "Room Safe Storage" item, and
    // the cookie store (which needs that key) holds every navigation until it
    // is answered. Team-signed builds keep their identity and use the real
    // keychain.
    var arguments = CommandLine.arguments
    if HostSpike.requested != nil {
        // Preserve BrowserWindow first-hit logs in each spike's captured stderr.
        arguments += ["--enable-logging=stderr", "--log-level=0"]
    }
    if CodeSignature.teamIdentifier == nil {
        arguments.append("--use-mock-keychain")
    }
    try core.initialize(
        arguments: arguments,
        applicationClass: RoomHostApplication.self,
        userDataDirectory: userData
    )
} catch {
    NSLog("Room: RoomCore failed to initialize: \(error)")
    exit(1)
}

exit(core.run())
