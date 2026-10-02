import AppKit
import Engine
import SwiftUI
import UIKitCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine: any EngineApplication
    private var windowController: RoomWindowController?
    private var pageHost: PageHost?
    private(set) var session: DebugSession?
    private(set) var overlays: OverlaySpike?

    init(engine: any EngineApplication) {
        self.engine = engine
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        showWindow()
        NSApp.activate()
        Task { await startSession() }
    }

    /// The default profile and the debug session in the window (Chapter 1).
    private func startSession() async {
        guard let controller = windowController, let pageHost else { return }
        do {
            let profile = try await engine.createProfile(name: "Default")
            let session = DebugSession(profile: profile, host: pageHost)
            let overlays = OverlaySpike(rootView: controller.rootView)
            self.session = session
            self.overlays = overlays
            installToolbar(DebugToolbar(session: session, overlays: overlays), in: controller)
            if let start = UserDefaults.standard.string(forKey: "RoomStartURL") {
                session.newPage(DebugSession.url(from: start))
            }
        } catch {
            NSLog("Room: no engine profile (\(error)); the window stays empty")
        }
        #if DEBUG
        if let directory = SnapshotRunner.directory {
            await SnapshotRunner.run(controller, session: session, into: directory)
            NSApp.terminate(nil)
        } else if let session, let spike = SpikeRunner.requested {
            await SpikeRunner.run(spike, session: session, controller: controller, overlays: overlays)
        }
        #endif
    }

    private func installToolbar(_ toolbar: some View, in controller: RoomWindowController) {
        let hosting = NSHostingView(rootView: toolbar)
        let content = controller.sidebarView.contentView
        hosting.frame = NSRect(x: 0, y: 52, width: content.bounds.width, height: max(0, content.bounds.height - 52))
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
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
            pageHost = PageHost(controller: controller)
        }
        windowController?.showWindow(nil)
    }

    // MARK: Menu actions (end of the responder chain)

    @objc func newPage(_ sender: Any?) {
        session?.newPage(nil)
        session?.addressFocusRequest += 1
    }

    @objc func openLocation(_ sender: Any?) {
        session?.addressFocusRequest += 1
    }

    @objc func closePage(_ sender: Any?) {
        session?.closeCurrent()
    }

    @objc func reloadPage(_ sender: Any?) {
        session?.current?.reload()
    }

    @objc func goBack(_ sender: Any?) {
        session?.current?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        session?.current?.goForward()
    }

    @objc func toggleDevTools(_ sender: Any?) {
        pageHost?.toggleDevTools()
    }
}
