#if DEBUG
import AppKit
import UIKitCore

/// `Room -RoomSnapshotDirectory <dir>` (Debug builds): captures the window in
/// each Phase 1.3 state as PNGs, writes `states.txt` with what the window
/// server reported for each, and quits. Active states are captured first;
/// a helper window then takes main for the inactive ones.
enum SnapshotRunner {
    static var directory: URL? {
        UserDefaults.standard.string(forKey: "RoomSnapshotDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private struct State {
        var name: String
        var dark: Bool
        var sidebarOpen: Bool
        var contentSize = RoomWindow.defaultContentSize
        var sidebarWidth = 240.0
        var tint: NSColor?
    }

    static func run(_ controller: RoomWindowController, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The window as Dia's reference capture frames it: 1244×818 pt, 280 pt sidebar.
        let dia = NSSize(width: 1244, height: 818)
        let active: [State] = [
            State(name: "light-active-open", dark: false, sidebarOpen: true),
            State(name: "light-active-closed", dark: false, sidebarOpen: false),
            State(name: "dark-active-open", dark: true, sidebarOpen: true),
            State(name: "dark-active-closed", dark: true, sidebarOpen: false),
            State(name: "light-active-tinted", dark: false, sidebarOpen: true, tint: .systemPurple),
            State(name: "light-dia-compare", dark: false, sidebarOpen: true, contentSize: dia, sidebarWidth: 280),
            State(name: "dark-dia-compare", dark: true, sidebarOpen: true, contentSize: dia, sidebarWidth: 280),
        ]
        let inactive: [State] = [
            State(name: "light-inactive-open", dark: false, sidebarOpen: true),
            State(name: "light-inactive-closed", dark: false, sidebarOpen: false),
            State(name: "dark-inactive-open", dark: true, sidebarOpen: true),
            State(name: "dark-inactive-closed", dark: true, sidebarOpen: false),
        ]
        var report: [String] = []
        for state in active {
            // Launching from a script does not always make the app frontmost,
            // macOS may refuse self-activation (scripts/window-snapshots.sh
            // also activates it from outside), and other apps can take focus
            // mid-capture: retry until the window stays main throughout.
            var line = ""
            for _ in 0..<40 {
                for _ in 0..<50 where !isFrontmost(controller) {
                    NSApp.activate()
                    controller.window?.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard isFrontmost(controller) else { continue }
                line = await capture(state, controller, directory)
                if isFrontmost(controller) { break }
            }
            report.append(line)
        }
        // Inactive look: another window of ours takes main, as when a
        // second browser window is in front.
        let sink = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        sink.isReleasedWhenClosed = false
        defer { sink.close() }
        for state in inactive {
            var line = ""
            for _ in 0..<40 {
                sink.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(200))
                guard controller.window?.isMainWindow == false else { continue }
                line = await capture(state, controller, directory)
                if controller.window?.isMainWindow == false { break }
            }
            report.append(line)
        }
        try? report.joined(separator: "\n").appending("\n")
            .write(to: directory.appending(path: "states.txt"), atomically: true, encoding: .utf8)
    }

    private static func isFrontmost(_ controller: RoomWindowController) -> Bool {
        NSApp.isActive && controller.window?.isMainWindow == true
    }

    private static func capture(_ state: State, _ controller: RoomWindowController, _ directory: URL) async -> String {
        guard let window = controller.window else { return "\(state.name): no window" }
        NSApp.appearance = NSAppearance(named: state.dark ? .darkAqua : .aqua)
        window.setContentSize(state.contentSize)
        controller.sidebarWidth = state.sidebarWidth
        controller.isSidebarOpen = state.sidebarOpen
        controller.materialView.setTintColor(state.tint, animated: false)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(800))
        let url = directory.appending(path: "phase-1.3-\(state.name).png")
        let image = try? WindowSnapshot.writePNG(window, to: url)
        let lights = controller.trafficLights.geometry.buttonsRect.map { NSStringFromRect($0) } ?? "none"
        return "\(state.name): appActive=\(NSApp.isActive) main=\(window.isMainWindow) "
            + "image=\(image.map { "\($0.width)x\($0.height)" } ?? "nil") "
            + "card=\(NSStringFromRect(controller.rootView.currentLayout.card)) "
            + "title=\(NSStringFromRect(controller.sidebarView.titleFrame)) lights=\(lights)"
    }
}
#endif
