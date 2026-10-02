#if DEBUG
import AppKit
import Engine
import UIKitCore

/// `Room -RoomSpike <name> -RoomSpikeOutput <file>` (Debug builds): runs one
/// Phase 1.4 measurement against the live engine and writes the result.
enum SpikeRunner {
    static var requested: String? { UserDefaults.standard.string(forKey: "RoomSpike") }

    static func run(_ name: String, session: DebugSession, controller: RoomWindowController, overlays: OverlaySpike?) async {
        NSLog("Room: unknown spike \(name)")
    }
}
#endif
