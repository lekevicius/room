import AppKit
import Design
import Engine
import Infra
import Store
import SwiftUI
import UIKitCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine: any EngineApplication
    private var store: RoomStore?
    private var windowController: RoomWindowController?
    private var pageHost: PageHost?
    private(set) var session: DebugSession?
    private(set) var overlays: OverlaySpike?

    init(engine: any EngineApplication) {
        self.engine = engine
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        store = Self.openStore()
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
            if let store { bind(controller, to: store) }
            windowController = controller
            pageHost = PageHost(controller: controller)
        }
        windowController?.showWindow(nil)
    }

    // MARK: Store

    /// `~/Library/Application Support/Room/Room.sqlite`. `-RoomStateDirectory`
    /// overrides it; DEBUG snapshot and spike runs use a throwaway directory
    /// so they never touch the user's sidebar.
    private static func openStore() -> RoomStore? {
        var directory = AppPaths.applicationSupport
        if let override = UserDefaults.standard.string(forKey: "RoomStateDirectory") {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        }
        #if DEBUG
        if SnapshotRunner.directory != nil || SpikeRunner.requested != nil {
            directory = FileManager.default.temporaryDirectory.appending(path: "Room-\(UUID().uuidString)", directoryHint: .isDirectory)
        }
        #endif
        do {
            let store = try RoomStore.open(directory: directory)
            if store.uncleanExit { NSLog("Room: the previous session did not quit cleanly") }
            if let recovery = store.recovery { NSLog("Room: database rebuilt at launch: \(recovery)") }
            return store
        } catch {
            NSLog("Room: cannot open the state database in \(directory.path): \(error); nothing will be saved")
            return nil
        }
    }

    /// Restores the window's saved sidebar width/visibility and frame and
    /// keeps the store up to date as the user changes them.
    private func bind(_ controller: RoomWindowController, to store: RoomStore) {
        let firstSpace = store.sidebar.spaces.first
        let record = store.windows.restoreOrCreateWindow(defaultSidebarWidth: Double(SidebarMetrics.defaultWidth),
                                                         space: firstSpace?.id)
        let windowID = record.id
        controller.sidebarWidth = CGFloat(record.sidebarWidth)
        controller.isSidebarOpen = record.sidebarVisible
        if let frame = record.frame { controller.restoreFrame(frame) }
        controller.spaceTitle = record.activeSpaceID.flatMap { store.sidebar.space($0)?.name } ?? firstSpace?.name ?? ""
        controller.onSidebarStateChange = { [weak store] width, isOpen in
            store?.windows.setSidebarWidth(Double(width), window: windowID)
            store?.windows.setSidebarVisible(isOpen, window: windowID)
        }
        controller.onFrameChange = { [weak store] frame in store?.windows.setFrame(frame, window: windowID) }
        controller.onWillClose = { [weak store] in store?.flush() }
    }

    /// Final state write; called at quit (both termination paths).
    func shutdown() {
        store?.close()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
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
