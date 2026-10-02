#if DEBUG
import AppKit
import UIKitCore

/// `Room -RoomSnapshotDirectory <dir>` (Debug builds): captures the window in
/// each Phase 1.3 state as PNGs, writes `states.txt` with what the window
/// server reported for each, and quits. Active states are captured first;
/// the app then deactivates itself for the inactive ones.
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
        // Launching from a script does not always make the app frontmost.
        for _ in 0..<30 where !NSApp.isActive {
            NSApp.activate()
            controller.window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(100))
        }
        for state in active { report.append(await capture(state, controller, directory)) }
        NSApp.deactivate()
        try? await Task.sleep(for: .seconds(1))
        for state in inactive { report.append(await capture(state, controller, directory)) }
        try? report.joined(separator: "\n").appending("\n")
            .write(to: directory.appending(path: "states.txt"), atomically: true, encoding: .utf8)
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
