import AppKit
import Chrome
import Design
import Engine
import FakeEngine
import Infra
import Model
import Sidebar
import Store
import SwiftUI
import UIKitCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let engine: any EngineApplication
    private var store: RoomStore?
    private var windowController: RoomWindowController?
    private var pageHost: PageHost?
    private(set) var session: DebugSession?
    private(set) var overlays: OverlaySpike?
    private(set) var sidebar: SidebarController?
    private(set) var sidebarPages: SidebarPages?
    private var toastCenter: ToastCenter?
    /// Pages behind the sidebar until Phase 2.3 puts entries on CEF.
    private let fakeEngine = FakeApplication()
    private var debugPanel: NSPanel?

    init(engine: any EngineApplication) {
        self.engine = engine
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The address field's full-URL tooltip appears after 600 ms (spec §C).
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": Int(Timing.urlTooltipDelay * 1000)])
        NSApp.mainMenu = MainMenu.make()
        store = Self.openStore()
        if Self.quitRequested {
            NSApp.terminate(nil)
            return
        }
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
            installDebugPanel(DebugToolbar(session: session, overlays: overlays))
            if let start = UserDefaults.standard.string(forKey: "RoomStartURL") {
                session.newPage(DebugSession.url(from: start))
            }
        } catch {
            NSLog("Room: no engine profile (\(error)); the window stays empty")
        }
        #if DEBUG
        if let directory = SnapshotRunner.directory {
            if SidebarFixtures.requested != nil, let sidebar, let sidebarPages {
                await SidebarSnapshotRunner.run(controller, sidebar: sidebar, pages: sidebarPages, into: directory)
            } else {
                await SnapshotRunner.run(controller, session: session, into: directory)
            }
            NSApp.terminate(nil)
        } else if let session, let spike = SpikeRunner.requested {
            await SpikeRunner.run(spike, session: session, controller: controller, overlays: overlays)
        }
        #endif
    }

    /// The Chapter 1 debug toolbar (CEF pages, DevTools, overlay spikes)
    /// moved out of the sidebar into a utility panel (Debug ▸ Show Debug
    /// Toolbar) when the sidebar tree arrived in Phase 2.2.
    private func installDebugPanel(_ toolbar: some View) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = "Debug Toolbar"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: toolbar.padding(.top, 12))
        panel.contentView = hosting
        debugPanel = panel
    }

    @objc func showDebugToolbar(_ sender: Any?) {
        guard let panel = debugPanel else { return }
        if !panel.isVisible, let frame = windowController?.window?.frame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX + 8, y: frame.maxY))
        }
        panel.makeKeyAndOrderFront(nil)
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
            windowController = controller
            let pageHost = PageHost(controller: controller)
            self.pageHost = pageHost
            if let store {
                let windowID = bind(controller, to: store)
                installSidebar(in: controller, store: store, windowID: windowID, pageHost: pageHost)
            }
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
        if SnapshotRunner.directory != nil || SpikeRunner.requested != nil || SidebarFixtures.requested != nil {
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
            presentStoreError(error, directory: directory)
            return nil
        }
    }

    /// The database could not be opened and was left untouched (never
    /// treated as corruption): say so, and let the user quit or go on
    /// without saving.
    private static func presentStoreError(_ error: any Error, directory: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Room can't open its sidebar"
        if case RoomStorage.OpenError.inUse = error {
            alert.informativeText = "Another copy of Room is using \(directory.path). Quit it and open Room again. "
                + "If you continue, nothing you change in this window is saved."
        } else {
            alert.informativeText = "\(error)\n\nIf you continue, nothing you change in this window is saved."
        }
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Without Saving")
        if alert.runModal() == .alertFirstButtonReturn { quitRequested = true }
    }

    /// Set when the user chose Quit in the store error alert.
    private static var quitRequested = false

    /// Restores the window's saved sidebar width/visibility and frame and
    /// keeps the store up to date as the user changes them.
    @discardableResult
    private func bind(_ controller: RoomWindowController, to store: RoomStore) -> UUID {
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
        return windowID
    }

    /// The sidebar tree (Phase 2.2) with FakeEngine pages behind it, and toasts.
    private func installSidebar(in controller: RoomWindowController, store: RoomStore, windowID: UUID, pageHost: PageHost) {
        #if DEBUG
        if let fixture = SidebarFixtures.requested { SidebarFixtures.populate(store, fixture, window: windowID) }
        #endif
        let sidebar = SidebarController(store: store, windowID: windowID)
        do {
            try fakeEngine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        } catch {
            NSLog("Room: FakeEngine: \(error)")
        }
        guard let profile = try? fakeEngine.profile(named: "Default") else { return }
        let pages = SidebarPages(profile: profile, pageHost: pageHost, store: store)
        pages.sidebar = sidebar
        sidebar.host = pages
        controller.sidebarView.headerView = sidebar.addressField
        controller.sidebarView.bodyView = sidebar.bodyView
        sidebar.onSpaceChange = { [weak controller] space in controller?.spaceTitle = space.name }
        let rootView = controller.rootView
        let toasts = ToastCenter(hostView: rootView) { [weak rootView] in
            guard let rootView else { return ToastCenter.Anchor(rect: .zero, alignment: .center) }
            let layout = rootView.currentLayout
            if rootView.isSidebarOpen {
                // Bottom-centre of the sidebar, above its footer.
                var rect = layout.sidebar
                rect.size.height -= SidebarMetrics.footerHeight
                return ToastCenter.Anchor(rect: rect, alignment: .center)
            }
            // Bottom-left of the window.
            return ToastCenter.Anchor(rect: CGRect(x: layout.card.minX, y: 0, width: SidebarMetrics.defaultWidth,
                                                   height: rootView.bounds.height - CardMetrics.inset), alignment: .leading)
        }
        rootView.onLayout = { [weak toasts] in toasts?.updateAnchor() }
        sidebar.toasts = toasts
        self.sidebar = sidebar
        sidebarPages = pages
        toastCenter = toasts
        if let id = sidebar.selectedEntryID, let entry = store.sidebar.entry(id) { pages.activate(entry) }
    }

    /// Final state write; called at quit (both termination paths).
    func shutdown() {
        store?.close()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    // MARK: Menu actions (end of the responder chain)

    /// ⌘T: a new Today tab (a URL prompt until the palette, Phase 2.4).
    @objc func newPage(_ sender: Any?) {
        sidebarPages?.newTab()
    }

    /// ⌘L: navigate the selected tab (a URL prompt until the palette, Phase 2.4).
    @objc func openLocation(_ sender: Any?) {
        sidebarPages?.editAddress()
    }

    /// ⌘D: pin / unpin the selected entry or the multi-selection.
    @objc func togglePin(_ sender: Any?) { sidebar?.togglePin() }

    /// ⇧⌘D: add to / remove from Essentials.
    @objc func toggleEssentials(_ sender: Any?) { sidebar?.toggleEssentials() }

    /// ⇧⌘K: Clear (staggered slide-out, Undo toast).
    @objc func clearTodayTabs(_ sender: Any?) { sidebar?.clearTodayTabs() }

    @objc func navigateSelectedPage(_ sender: Any?) {
        sidebarPages?.navigateSelected()
    }

    @objc func toggleAudioInSelectedPage(_ sender: Any?) {
        sidebarPages?.toggleAudioInSelected()
    }

    @objc func closePage(_ sender: Any?) {
        session?.closeCurrent()
    }

    @objc func reloadPage(_ sender: Any?) {
        pageHost?.contents?.reload()
    }

    @objc func goBack(_ sender: Any?) {
        pageHost?.contents?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        pageHost?.contents?.goForward()
    }

    @objc func toggleDevTools(_ sender: Any?) {
        pageHost?.toggleDevTools()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePin(_:)):
            menuItem.title = sidebar?.pinCommandTitle ?? CommandName.pinTab
            return sidebar?.pinCommandTitle != nil
        case #selector(toggleEssentials(_:)):
            menuItem.title = sidebar?.essentialsCommandTitle ?? CommandName.addToEssentials
            return sidebar?.essentialsCommandTitle != nil
        case #selector(clearTodayTabs(_:)):
            return sidebar?.canClearToday == true
        default:
            return true
        }
    }
}
