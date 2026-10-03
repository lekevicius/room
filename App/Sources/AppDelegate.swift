import AppKit
import Chrome
import Design
import Engine
import FakeEngine
import Infra
import Model
import Omnibox
import Palette
import Sidebar
import Store
import SwiftUI
import Tabs
import UIKitCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let engine: any EngineApplication
    private var store: RoomStore?
    private var windowController: RoomWindowController?
    private var pageHost: PageHost?
    private(set) var pageDelegate: PageUIDelegate?
    private(set) var overlays: OverlaySpike?
    private(set) var sidebar: SidebarController?
    /// The window's pages: entries on the engine (Phase 2.3).
    private(set) var tabs: TabController?
    private(set) var switcher: TabSwitcher?
    /// ⌘T / ⌘L (Phase 2.4).
    private(set) var palette: PaletteController?
    private var toastCenter: ToastCenter?
    private var debugPanel: NSPanel?
    #if DEBUG
    /// Sidebar captures run on FakeEngine pages (no network, stable states).
    private let fakeEngine = FakeApplication()
    #endif

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

    /// The default profile: the tab controller loads the selected entry once
    /// it exists. Then the debug panel, and DEBUG runners.
    private func startSession() async {
        guard let controller = windowController, let pageHost, let tabs, let pageDelegate else { return }
        do {
            let profile = try await engine.createProfile(name: "Default")
            profile.downloadsDelegate = pageDelegate
            if tabs.profile == nil { tabs.profile = profile }
            let overlays = OverlaySpike(rootView: controller.rootView)
            self.overlays = overlays
            installDebugPanel(DebugToolbar(tabs: tabs, pageHost: pageHost, pageDelegate: pageDelegate, overlays: overlays))
            if let start = UserDefaults.standard.string(forKey: "RoomStartURL") {
                tabs.openNewTab(url: URLFixup.url(from: start) ?? URLFixup.searchURL(for: start))
            }
        } catch {
            NSLog("Room: no engine profile (\(error)); the window stays empty")
        }
        #if DEBUG
        guard let sidebar, let profile = tabs.profile else { return }
        if let directory = SnapshotRunner.directory {
            if SidebarFixtures.requested != nil {
                await SidebarSnapshotRunner.run(controller, sidebar: sidebar, tabs: tabs, into: directory)
            } else {
                await SnapshotRunner.run(controller, tabs: tabs, into: directory)
            }
            NSApp.terminate(nil)
        } else if let spike = SpikeRunner.requested {
            let session = SpikeSession(tabs: tabs, sidebar: sidebar, host: pageHost, profile: profile, pageDelegate: pageDelegate)
            await SpikeRunner.run(spike, session: session, controller: controller, overlays: overlays)
        }
        #endif
    }

    /// The Chapter 1 debug toolbar (CEF pages, DevTools, overlay spikes)
    /// moved out of the sidebar into a utility panel (Debug ▸ Show Debug
    /// Toolbar) when the sidebar tree arrived in Phase 2.2. Its SwiftUI view
    /// exists only while the panel is open: hidden, it still re-rendered on
    /// every tab switch (~3 ms each, 2.3 profile).
    private func installDebugPanel(_ toolbar: some View) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = "Debug Toolbar"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        makeDebugToolbar = {
            let view = NSHostingView(rootView: toolbar.padding(.top, 12))
            view.identifier = Self.debugToolbarID
            return view
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { panel.contentView = nil }
        }
        debugPanel = panel
    }

    private var makeDebugToolbar: (() -> NSView)?
    private static let debugToolbarID = NSUserInterfaceItemIdentifier("debug-toolbar")

    @objc func showDebugToolbar(_ sender: Any?) {
        guard let panel = debugPanel else { return }
        if !panel.isVisible, let frame = windowController?.window?.frame {
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX + 8, y: frame.maxY))
        }
        if panel.contentView?.identifier != Self.debugToolbarID, let view = makeDebugToolbar?() { panel.contentView = view }
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
        // An explicit `-RoomStateDirectory` wins (the relaunch measurement reuses one).
        if UserDefaults.standard.string(forKey: "RoomStateDirectory") == nil,
           SnapshotRunner.directory != nil || SpikeRunner.requested != nil || SidebarFixtures.requested != nil {
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

    /// The sidebar tree (Phase 2.2), the tab controller behind it (2.3), the
    /// ⌃Tab switcher and toasts.
    private func installSidebar(in controller: RoomWindowController, store: RoomStore, windowID: UUID, pageHost: PageHost) {
        #if DEBUG
        if let fixture = SidebarFixtures.requested { SidebarFixtures.populate(store, fixture, window: windowID) }
        #endif
        let sidebar = SidebarController(store: store, windowID: windowID)
        let tabs = TabController(store: store)
        tabs.engine = engine
        let pageDelegate = PageUIDelegate(host: pageHost)
        tabs.display = pageHost
        tabs.sidebar = sidebar
        tabs.pageUIDelegate = pageDelegate
        #if DEBUG
        if SidebarFixtures.requested != nil, SnapshotRunner.directory != nil {
            do {
                try fakeEngine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
                tabs.profile = try fakeEngine.profile(named: "Default")
            } catch {
                NSLog("Room: FakeEngine: \(error)")
            }
        }
        #endif
        sidebar.host = tabs
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
        sidebar.toasts = toasts
        let palette = PaletteController(hostView: rootView, tabs: tabs, sidebar: sidebar)
        palette.contentRect = { [weak rootView] in rootView?.currentLayout.card ?? .zero }
        palette.addressFieldRect = { [weak rootView, weak sidebar] in
            // Docked on the header field only while the sidebar shows it (spec §C).
            guard let rootView, rootView.isSidebarOpen, let field = sidebar?.addressField, field.window != nil else { return nil }
            return field.convert(field.bounds, to: rootView)
        }
        palette.favicon = { [weak tabs] id in
            let state = tabs?.pageState(for: id)
            return (state?.favicon, state?.isLoaded ?? false)
        }
        tabs.onNewTab = { [weak palette] in palette?.toggleNew() }
        tabs.onEditAddress = { [weak palette] docked in palette?.toggleEdit(docked: docked) }
        rootView.onLayout = { [weak toasts, weak palette] in
            toasts?.updateAnchor()
            palette?.layout()
        }
        self.palette = palette
        if let window = controller.window {
            switcher = TabSwitcher(window: window, hostView: controller.cardView, sidebar: sidebar, tabs: tabs)
        }
        self.sidebar = sidebar
        self.tabs = tabs
        self.pageDelegate = pageDelegate
        toastCenter = toasts
        tabs.startLifecycle()
        // Only the selected entry loads at launch (spec §H); it waits for the profile.
        tabs.showSelection()
    }

    /// Final state write; called at quit (both termination paths).
    func shutdown() {
        store?.close()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    // MARK: Menu actions (end of the responder chain)

    /// ⌘T: the palette, empty (spec §C); again closes it.
    @objc func newPage(_ sender: Any?) {
        tabs?.newTab()
    }

    /// ⌘L: the palette on the current URL (spec §C); again closes it.
    @objc func openLocation(_ sender: Any?) {
        tabs?.openLocation()
    }

    /// ⌘W: the multi-selection or the selected entry, per spec §A.3.
    @objc func closeTab(_ sender: Any?) { sidebar?.closeCommandTargets() }

    /// ⇧⌘T.
    @objc func reopenClosedTab(_ sender: Any?) { sidebar?.reopenClosedTab() }

    /// ⌘1…⌘9 (the item's tag is the digit).
    @objc func selectTabByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.selectTab(digit: item.tag)
    }

    /// ⇧⌘] and ⌥⌘↓ (tag 1), ⇧⌘[ and ⌥⌘↑ (tag −1).
    @objc func selectAdjacentTab(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.selectAdjacentTab(item.tag)
    }

    /// ⇧⌘M.
    @objc func toggleMute(_ sender: Any?) { sidebar?.toggleMuteSelected() }

    /// ⌘D: pin / unpin the selected entry or the multi-selection.
    @objc func togglePin(_ sender: Any?) { sidebar?.togglePin() }

    /// ⇧⌘D: add to / remove from Essentials.
    @objc func toggleEssentials(_ sender: Any?) { sidebar?.toggleEssentials() }

    /// ⇧⌘K: Clear (staggered slide-out, Undo toast).
    @objc func clearTodayTabs(_ sender: Any?) { sidebar?.clearTodayTabs() }

    @objc func reloadPage(_ sender: Any?) {
        tabs?.current?.reload()
    }

    @objc func goBack(_ sender: Any?) {
        tabs?.current?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        tabs?.current?.goForward()
    }

    @objc func toggleDevTools(_ sender: Any?) {
        pageHost?.toggleDevTools()
    }

    // Debug menu: the lifecycle checks on CEF (spec §H), results in the log.

    @objc func simulateMemoryPressure(_ sender: Any?) {
        let ids = tabs?.handleMemoryPressure(critical: false) ?? []
        NSLog("Room: simulated memory pressure discarded \(ids.count) page(s)")
    }

    @objc func discardBackgroundPages(_ sender: Any?) {
        let ids = tabs?.discardBackgroundPages() ?? []
        NSLog("Room: discarded \(ids.count) background page(s)")
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
        case #selector(closeTab(_:)):
            return sidebar?.canCloseCommandTargets == true
        case #selector(reopenClosedTab(_:)):
            return sidebar?.canReopenClosedTab == true
        case #selector(toggleMute(_:)):
            let muted = sidebar?.selectedEntryID.flatMap { tabs?.pageState(for: $0).isMuted } ?? false
            menuItem.title = muted ? CommandName.unmuteTab : CommandName.muteTab
            return sidebar?.selectedHasPage == true
        case #selector(reloadPage(_:)):
            return tabs?.current != nil
        case #selector(goBack(_:)):
            return tabs?.current?.canGoBack == true
        case #selector(goForward(_:)):
            return tabs?.current?.canGoForward == true
        default:
            return true
        }
    }
}
