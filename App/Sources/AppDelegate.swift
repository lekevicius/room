import AppKit
import Engine
import UIKitCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine: any EngineApplication
    private var windowController: RoomWindowController?

    init(engine: any EngineApplication) {
        self.engine = engine
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        showWindow()
        NSApp.activate()
        #if DEBUG
        if let directory = SnapshotRunner.directory, let controller = windowController {
            Task {
                await SnapshotRunner.run(controller, into: directory)
                NSApp.terminate(nil)
            }
        }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func showWindow() {
        if windowController == nil {
            let controller = RoomWindowController()
            // Placeholder until Chapter 2's spaces model.
            controller.spaceTitle = "Personal"
            windowController = controller
        }
        windowController?.showWindow(nil)
    }
}
