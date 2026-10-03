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
    private(set) var store: RoomStore?
    private(set) var windowController: RoomWindowController?
    private var settingsWindow: SettingsWindowController?
    private var pageHost: PageHost?
    /// The card's content view (DEBUG spikes read what it shows).
    var pageHostContainer: PageContainerView? { pageHost?.container }
    #if DEBUG
    /// The card's host (split spikes read its panes and time focus changes).
    var debugPageHost: PageHost? { pageHost }
    #endif
    private(set) var pageDelegate: PageUIDelegate?
    private(set) var overlays: OverlaySpike?
    private(set) var sidebar: SidebarController?
    /// The window's pages: entries on the engine (Phase 2.3).
    private(set) var tabs: TabController?
    private(set) var switcher: TabSwitcher?
    /// ⌘T / ⌘L (Phase 2.4).
    private(set) var palette: PaletteController?
    private var toastCenter: ToastCenter?
    private(set) var promptPresenter: PagePromptPresenter?
    /// Downloads across the window's profiles: the footer button and its popover (2.6b).
    private(set) var downloads: DownloadsUI?
    /// Over the card's page (2.6b): find, the zoom indicator, the status pill.
    private(set) var find: FindController?
    private(set) var zoom: ZoomIndicator?
    private(set) var statusPill: StatusPill?
    /// The site panel on the header's site button (2.6b).
    let sitePanel = SitePanel()
    /// Peek over the card (2.7a).
    private(set) var peek: PeekPresenter?
    /// The last press in the window: Peek's 2 s gesture window and where its open animation starts.
    private var inputMonitor: Any?
    private var lastClick: (point: CGPoint, time: TimeInterval)?
    /// The hidden sidebar's overlay header, keep-open checks and toasts (2.7a).
    private(set) var hiddenSidebar: HiddenSidebar?
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

    /// Every model profile's engine profile (a CEF request context at
    /// `<root>/Room Profile <name>`, ROADMAP 2.5 task 4): the tab controller
    /// loads the selected entry once its profile exists. Then the DEBUG runners.
    private func startSession() async {
        guard let controller = windowController, let pageHost, let tabs, let pageDelegate else { return }
        do {
            let profiles = store?.sidebar.profiles ?? []
            for model in profiles where tabs.engineProfiles[model.id] == nil {
                let profile = try await engine.createProfile(name: TabController.engineProfileName(for: model))
                profile.downloadsDelegate = downloads?.list
                if tabs.engineProfiles[model.id] == nil { tabs.setEngineProfile(profile, for: model.id) }
            }
            // The Phase 1.4 overlay spikes (DEBUG `SpikeRunner`).
            overlays = OverlaySpike(rootView: controller.rootView)
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
           SnapshotRunner.directory != nil || SpikeRunner.requested != nil || SidebarFixtures.requested != nil
            || HistoryFixture.requestedRows != nil {
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
        if let rows = HistoryFixture.requestedRows, let profile = store.sidebar.profiles.first {
            HistoryFixture.populate(store.history, rows: rows, profile: profile.id)
        }
        #endif
        let sidebar = SidebarController(store: store, windowID: windowID)
        let tabs = TabController(store: store)
        tabs.engine = engine
        let pageDelegate = PageUIDelegate(host: pageHost)
        // A profile made after launch (a new space's "New Profile…") gets its engine profile on first use.
        tabs.requestEngineProfile = { [weak self, weak tabs] model in
            Task { @MainActor in
                guard let self, let tabs else { return }
                do {
                    let profile = try await self.engine.createProfile(name: TabController.engineProfileName(for: model))
                    profile.downloadsDelegate = self.downloads?.list
                    tabs.setEngineProfile(profile, for: model.id)
                } catch {
                    NSLog("Room: no engine profile for \(model.name): \(error)")
                }
            }
        }
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
        // The window's title (Window menu, Mission Control) is not drawn: set after the switch's frame.
        sidebar.onSpaceChange = { [weak controller] space in
            DispatchQueue.main.async { controller?.spaceTitle = space.name }
        }
        // The window's tint follows the active space's theme (spec §B), crossfading with the slide.
        sidebar.onTintChange = { [weak controller] theme, animated in
            controller?.materialView.setTint(theme.map(SpaceTint.init), animated: animated)
        }
        controller.materialView.setTint(sidebar.activeSpace?.theme.map(SpaceTint.init), animated: false)
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
        let downloads = DownloadsUI(button: sidebar.downloadsButton, rootView: rootView, toasts: toasts, settings: store.settings)
        downloads.pageFavicon = { [weak tabs] in tabs?.current?.favicon }
        self.downloads = downloads
        installPagePrompts(pageDelegate, pageHost: pageHost, sidebar: sidebar, tabs: tabs, rootView: rootView)
        let palette = PaletteController(hostView: rootView, tabs: tabs, sidebar: sidebar)
        palette.contentRect = { [weak rootView, weak pageHost] in
            // In a split, over the focused pane (⇧⌘= "focuses the palette inside it", spec §D).
            guard let rootView else { return .zero }
            guard let split = pageHost?.splitView, split.isSplit, split.window != nil else { return rootView.currentLayout.card }
            return split.focusedPane.convert(split.focusedPane.bounds, to: rootView)
        }
        palette.addressFieldRect = { [weak rootView, weak sidebar] in
            // Docked on the header field only while the sidebar shows it (spec §C).
            guard let rootView, rootView.isSidebarOpen, let field = sidebar?.addressField, field.window != nil else { return nil }
            return field.convert(field.bounds, to: rootView)
        }
        palette.favicon = { [weak tabs] id in
            let state = tabs?.pageState(for: id)
            return (state?.favicon, state?.isLoaded ?? false)
        }
        palette.siteFavicon = { [weak tabs] url in tabs?.favicon(forURL: url) }
        palette.commands = { [weak self] in self?.paletteCommands() ?? [] }
        palette.onCommand = { [weak self] id in self?.runPaletteCommand(id) }
        let settings = store.settings
        palette.searchEngine = { [weak settings] in SearchEngine.named(settings?.settings.searchEngine) }
        palette.suggestionsEnabled = { [weak settings] in settings?.settings.searchSuggestions ?? false }
        var proxy: String?
        #if DEBUG
        // The no-network check routes suggestion requests through a logging proxy (spike-results 2.4b).
        proxy = UserDefaults.standard.string(forKey: "RoomSuggestProxy")
        #endif
        palette.suggest = SuggestClient(transport: URLSessionSuggestTransport(proxy: proxy), debounce: .seconds(Timing.suggestDebounce))
        observeSuggestionsSwitch(settings, palette: palette)
        tabs.onNewTab = { [weak palette] in palette?.toggleNew() }
        tabs.onEditAddress = { [weak palette] docked in palette?.toggleEdit(docked: docked) }
        rootView.onLayout = { [weak self, weak toasts, weak palette] in
            toasts?.updateAnchor()
            palette?.layout()
            self?.peek?.layout()
        }
        self.palette = palette
        hiddenSidebar = HiddenSidebar(controller: controller, tabs: tabs, sidebar: sidebar, palette: palette, toasts: toasts)
        installSplit(pageHost: pageHost, sidebar: sidebar, tabs: tabs, palette: palette, store: store)
        installToolbar(controller, tabs: tabs, settings: store.settings)
        trackFocusedPage(tabs)
        // The glass and the rows' hosting view are built before the first ⌘T.
        DispatchQueue.main.async { [weak palette] in palette?.prewarm() }
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
        // The other spaces' lists are built after the first frame, one per turn,
        // so a switch never waits on a list (ROADMAP 2.5 exit).
        DispatchQueue.main.async { [weak sidebar] in sidebar?.prepareSpaces() }
    }

    /// The page's prompts in the card, the permission popover on the header's
    /// site button, and Room's context-menu items (ROADMAP 2.6 task 2).
    private func installPagePrompts(_ pageDelegate: PageUIDelegate, pageHost: PageHost, sidebar: SidebarController, tabs: TabController,
                                    rootView: BrowserWindowView) {
        let chrome = pageDelegate.chrome
        promptPresenter = PagePromptPresenter(
            prompts: chrome.prompts, crashes: chrome.crashes, host: pageHost.container.promptLayer,
            permissionAnchor: { [weak rootView, weak sidebar] in
                // The site button while the sidebar shows it; otherwise the card's corner.
                guard let rootView, rootView.isSidebarOpen, let button = sidebar?.addressField.siteButtonView, button.window != nil else {
                    return nil
                }
                return (button, button.bounds)
            },
            pageHost: { [weak pageHost] id in
                guard let contents = pageHost?.contents, ObjectIdentifier(contents) == id else { return nil }
                guard let url = contents.url, ["http", "https"].contains(url.scheme) else { return nil }
                return url.host()
            },
            focusPage: { [weak pageHost] in pageHost?.focusPage() })
        let fullscreen = windowController.map(PageFullscreen.init)
        fullscreen?.host = pageHost
        pageDelegate.fullscreen = fullscreen
        windowController?.onFullscreenChange = { [weak fullscreen] isFullscreen in
            if !isFullscreen { fullscreen?.windowDidExitFullscreen() }
        }
        // Find, zoom and the status pill over the page (ROADMAP 2.6 task 3).
        let tools = pageHost.container.toolLayer
        let find = FindController(host: tools)
        find.onClose = { [weak pageHost] in pageHost?.focusPage() }
        let zoom = ZoomIndicator(host: tools)
        zoom.topOffset = { [weak find] in
            FindMetrics.inset + (find?.isVisible == true ? FindMetrics.height + Spacing.xs : 0)
        }
        let statusPill = StatusPill(host: tools)
        // Every pane's tool layer (2.7b: one per split pane) re-places the pill and the indicator.
        let layoutTools = { [weak statusPill, weak zoom] in
            statusPill?.layout()
            zoom?.layout()
        }
        tools.onLayout = layoutTools
        pageHost.splitView.onNewPane = { pane in pane.container.toolLayer.onLayout = layoutTools }
        installPeek(tabs: tabs, pageHost: pageHost, rootView: rootView, tools: { [weak statusPill, weak zoom] in
            statusPill?.layout()
            zoom?.layout()
        })
        pageDelegate.onStatusText = { [weak statusPill] text in statusPill?.setStatus(text) }
        pageDelegate.onPageClosed = { [weak find] page in find?.pageClosed(page) }
        self.find = find
        self.zoom = zoom
        self.statusPill = statusPill
        pageHost.onShow = { [weak self, weak fullscreen] contents in
            fullscreen?.cardDidShow(contents)
            self?.focusPageSurfaces()
        }
        find.setPage(pageHost.contents)
        sidebar.addressField.onSiteButton = { [weak self] in self?.showSitePanel() }
        chrome.prompts.setCurrentPage(pageHost.contents)
        chrome.isPeekAvailable = true
        chrome.performMenuAction = { [weak tabs] action, page in
            switch action {
            case .openLinkInNewTab(let url), .openImageInNewTab(let url):
                tabs?.openLink(url, from: page)
            case .openLinkInPeek(let url):
                tabs?.openPeek(url, from: page)
            case .copyLink(let url), .copyImageAddress(let url):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }

    /// View ▸ Show Toolbar (spec §E): Back, Forward, Reload and the full URL; a click on it is ⌘L.
    private func installToolbar(_ controller: RoomWindowController, tabs: TabController, settings: SettingsStore) {
        let toolbar = controller.rootView.toolbarView
        toolbar.navigation.onBack = { [weak tabs] in tabs?.focusedPage?.goBack() }
        toolbar.navigation.onForward = { [weak tabs] in tabs?.focusedPage?.goForward() }
        toolbar.navigation.onReload = { [weak tabs] in
            guard let page = tabs?.focusedPage else { return }
            page.isLoading ? page.stop() : page.reload()
        }
        toolbar.onURLClick = { [weak tabs] in tabs?.openLocation() }
        controller.showsToolbar = settings.settings.showsToolbar
    }

    /// ⌘S, View ▸ Hide Sidebar / Show Sidebar (spec §E).
    @objc func hideOrShowSidebar(_ sender: Any?) {
        windowController?.toggleSidebarVisibility(sender)
    }

    /// ⌥⌘S, View ▸ Keep Sidebar Open: pins the hidden sidebar's overlay (spec §E); nothing to pin while it is docked.
    @objc func keepSidebarOpen(_ sender: Any?) {
        windowController?.toggleSidebarOverlayPin(sender)
    }

    /// View ▸ Show Toolbar.
    @objc func toggleToolbar(_ sender: Any?) {
        guard let controller = windowController, let settings = store?.settings else { return }
        controller.showsToolbar.toggle()
        let shows = controller.showsToolbar
        settings.update { $0.showsToolbar = shows }
    }

    /// Back/Forward/Reload in the overlay's header (and the toolbar) follow the focused page.
    private func trackFocusedPage(_ tabs: TabController) {
        let page = withObservationTracking {
            let page = tabs.focusedPage
            _ = (page?.canGoBack, page?.canGoForward, page?.isLoading, page?.url)
            return page
        } onChange: { [weak self, weak tabs] in
            Task { @MainActor in
                guard let self, let tabs else { return }
                self.trackFocusedPage(tabs)
            }
        }
        hiddenSidebar?.update(page)
        if let toolbar = windowController?.rootView.toolbarView {
            toolbar.navigation.update(canGoBack: page?.canGoBack ?? false, canGoForward: page?.canGoForward ?? false,
                                      isLoading: page?.isLoading ?? false, hasPage: page != nil)
            toolbar.setURL(page?.url?.absoluteString)
        }
    }

    /// Peek over the card (spec §A.4, §I.6): the presenter, its page's own
    /// tool and prompt layers, and the input monitor its rules read.
    private func installPeek(tabs: TabController, pageHost: PageHost, rootView: BrowserWindowView, tools: @escaping () -> Void) {
        let peek = PeekPresenter(rootView: rootView)
        peek.overlay.container.toolLayer.onLayout = tools
        peek.onClose = { [weak tabs] in tabs?.closeShownPeek() }
        peek.onExpand = { [weak tabs] in tabs?.expandShownPeek() }
        peek.onSplit = { [weak tabs] in tabs?.splitShownPeek() }
        peek.onFocus = { [weak self, weak pageHost] contents, _ in
            self?.focusPageSurfaces()
            if contents == nil { pageHost?.focusPage() }
        }
        peek.recentClick = { [weak self] in
            guard let click = self?.lastClick, ProcessInfo.processInfo.systemUptime - click.time < Timing.peekGestureWindow else { return nil }
            return click.point
        }
        tabs.peekDisplay = peek
        let settings = store?.settings
        tabs.isPeekEnabled = { [weak settings] in settings?.settings.peekOffSiteLinks ?? true }
        self.peek = peek
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) {
            [weak self, weak tabs, weak rootView] event in
            tabs?.lastUserInput = event.timestamp
            if event.type == .leftMouseDown, let rootView, event.window === rootView.window {
                self?.lastClick = (rootView.convert(event.locationInWindow, from: nil), event.timestamp)
            }
            return event
        }
    }

    /// Split view (spec §D): focus follows a press in a pane, the resizers'
    /// sizes and the pane headers' commands go to the store and the sidebar,
    /// the card's drop zones take sidebar entries while one is dragged, and a
    /// new pane the palette was dismissed on goes again.
    private func installSplit(pageHost: PageHost, sidebar: SidebarController, tabs: TabController, palette: PaletteController,
                              store: RoomStore) {
        let split = pageHost.splitView
        pageHost.onFocusPane = { [weak sidebar] entry in sidebar?.select(entry) }
        split.onRatios = { [weak store] group, ratios in try? store?.sidebar.setSplitRatios(group, ratios) }
        split.onClosePane = { [weak sidebar] entry in sidebar?.close(entry) }
        split.onMovePane = { [weak sidebar] group, from, to in sidebar?.movePane(in: group, from: from, to: to) }
        split.onLayoutMenu = { [weak self] entry, button in self?.showPaneLayoutMenu(entry, at: button) }
        split.dropOverlay.panes = { [weak split, weak tabs] in
            guard let split else { return [] }
            if split.isSplit { return zip(split.paneFrames, split.panes).map { ($0, $1.entry) } }
            return [(split.bounds, tabs?.currentEntryID)]
        }
        split.dropOverlay.onDrop = { [weak sidebar] id, pane, zone in
            guard let sidebar else { return }
            guard let pane else { return sidebar.select(id) }
            switch zone {
            case .left: sidebar.dropIntoSplit(id, edge: .left, of: pane)
            case .right: sidebar.dropIntoSplit(id, edge: .right, of: pane)
            case .top: sidebar.dropIntoSplit(id, edge: .top, of: pane)
            case .bottom: sidebar.dropIntoSplit(id, edge: .bottom, of: pane)
            case .center: sidebar.dropReplacingPane(id, pane: pane)
            }
        }
        sidebar.onEntryDrag = { [weak split] active in split?.dropOverlay.isHidden = !active }
        // ⇧⌘= opened the palette on an empty pane: dismissed without a page, the pane goes (spec §D).
        let previousClose = palette.onClose
        palette.onClose = { [weak sidebar] in
            previousClose?()
            DispatchQueue.main.async {
                guard let sidebar, let id = sidebar.selectedEntryID, sidebar.selectedSplit != nil,
                      let entry = sidebar.store.sidebar.entry(id), entry.currentURL == nil else { return }
                sidebar.close(id)
            }
        }
    }

    /// A pane header's layout button: the three layouts and Separate All Tabs.
    private func showPaneLayoutMenu(_ entry: UUID, at button: NSView) {
        guard let sidebar, let group = sidebar.store.sidebar.splitGroup(of: entry) else { return }
        let menu = NSMenu()
        for (title, layout, tag) in [(CommandName.layoutGrid, SplitLayout.grid, 0), (CommandName.layoutSideBySide, .hbox, 1),
                                     (CommandName.layoutStacked, .vbox, 2)] {
            let item = menu.addItem(withTitle: title, action: #selector(paneLayoutChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.representedObject = group.id
            item.state = group.layout == layout ? .on : .off
        }
        menu.addItem(.separator())
        let separate = menu.addItem(withTitle: CommandName.separateAllTabs, action: #selector(paneLayoutChosen(_:)), keyEquivalent: "")
        separate.target = self
        separate.tag = -1
        separate.representedObject = group.id
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
    }

    @objc private func paneLayoutChosen(_ sender: NSMenuItem) {
        guard let group = sender.representedObject as? UUID, let store else { return }
        if sender.tag < 0 { return store.sidebar.dissolveSplitGroup(group) }
        try? store.sidebar.setSplitLayout(group, Self.splitLayout(tag: sender.tag))
    }

    private static func splitLayout(tag: Int) -> SplitLayout {
        switch tag {
        case 0: .grid
        case 1: .hbox
        default: .vbox
        }
    }

    /// The focused page (Peek's if it shows, else the card's) owns the
    /// prompts, the find bar, the zoom indicator and the status pill, in its
    /// own container (2.7b: the focused split pane).
    private func focusPageSurfaces() {
        guard let pageHost else { return }
        let (page, container): ((any WebContents)?, PageContainerView) = if let peek, let contents = peek.contents {
            (contents, peek.overlay.container)
        } else {
            (pageHost.contents, pageHost.container)
        }
        promptPresenter?.setHost(container.promptLayer)
        pageDelegate?.chrome.prompts.setCurrentPage(page)
        find?.setHost(container.toolLayer)
        find?.setPage(page)
        zoom?.setHost(container.toolLayer)
        zoom?.setPage(page)
        statusPill?.setHost(container.toolLayer)
        statusPill?.reset()
    }

    /// The Settings switch holds at once (CLAUDE.md): turned off, the open
    /// palette drops its suggestions and the client sends nothing more.
    private func observeSuggestionsSwitch(_ settings: SettingsStore, palette: PaletteController) {
        withObservationTracking {
            _ = settings.settings.searchSuggestions
        } onChange: { [weak self, weak settings, weak palette] in
            Task { @MainActor in
                guard let self, let settings, let palette else { return }
                palette.suggestionsSettingChanged()
                self.observeSuggestionsSwitch(settings, palette: palette)
            }
        }
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

    /// ⌘Y: the palette on recent history (shortcuts.md, until Chapter 3).
    @objc func showHistory(_ sender: Any?) {
        palette?.toggleHistory()
    }

    /// ⌘,: Settings (Search only until 2.8).
    @objc func showSettings(_ sender: Any?) {
        guard let store else { return }
        if settingsWindow == nil { settingsWindow = SettingsWindowController(settings: store.settings) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// ⌘W: the multi-selection or the selected entry, per spec §A.3.
    @objc func closeTab(_ sender: Any?) {
        // A Peek over the page closes first (spec §I.6, shortcuts.md: Esc, ⌘W).
        if tabs?.closeShownPeek() == true { return }
        sidebar?.closeCommandTargets()
    }

    /// ⌘O: Peek becomes a Today tab under its entry (spec §I.6).
    @objc func expandPeek(_ sender: Any?) { tabs?.expandShownPeek() }

    /// ⇧⌘O: Peek into a split with its entry (spec §I.6).
    @objc func splitPeek(_ sender: Any?) { tabs?.splitShownPeek() }

    // Split view (spec §D, docs/shortcuts.md).

    /// ⇧⌘= / ⌃⇧=: an empty pane beside the focused one, the palette on it.
    @objc func newSplitPane(_ sender: Any?) { sidebar?.newSplitPane() }

    /// ⌃⇧-: the focused pane leaves the split.
    @objc func removeSplitPane(_ sender: Any?) { sidebar?.removeFocusedPane() }

    /// ⌥⌘G (tag 0), ⌥⌘V (1), ⌥⌘H (2).
    @objc func setSplitLayout(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.setSplitLayout(Self.splitLayout(tag: item.tag))
    }

    /// ⌥⌘U.
    @objc func unsplit(_ sender: Any?) { sidebar?.unsplit() }

    /// ⌃⇧1…4 (the item's tag).
    @objc func focusSplitPane(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.focusPane(number: item.tag)
    }

    /// ⌃⇧] (tag 1), ⌃⇧[ (tag −1).
    @objc func focusAdjacentPane(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.focusAdjacentPane(item.tag)
    }

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

    /// ⌃1…⌃9, ⌃0 (the item's tag is the digit; spec §B).
    @objc func selectSpaceByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.showSpace(digit: item.tag)
    }

    /// ⌥⌘→ (tag 1) and ⌥⌘← (tag −1), wrapping around.
    @objc func selectAdjacentSpace(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        sidebar?.showAdjacentSpace(item.tag)
    }

    /// File ▸ New Space (the form in the sidebar; with the sidebar hidden, in its pinned overlay).
    @objc func newSpace(_ sender: Any?) {
        hiddenSidebar?.revealForSpaceForm()
        sidebar?.newSpace()
    }

    /// ⌘D: pin / unpin the selected entry or the multi-selection.
    @objc func togglePin(_ sender: Any?) { sidebar?.togglePin() }

    /// ⇧⌘D: add to / remove from Essentials.
    @objc func toggleEssentials(_ sender: Any?) { sidebar?.toggleEssentials() }

    /// ⇧⌘K: Clear (staggered slide-out, Undo toast).
    @objc func clearTodayTabs(_ sender: Any?) { sidebar?.clearTodayTabs() }

    @objc func reloadPage(_ sender: Any?) {
        tabs?.focusedPage?.reload()
    }

    @objc func goBack(_ sender: Any?) {
        tabs?.focusedPage?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        tabs?.focusedPage?.goForward()
    }

    /// ⇧⌘J: the downloads popover (spec §G).
    @objc func showDownloads(_ sender: Any?) {
        downloads?.togglePopover()
    }

    /// ⌘F (spec §C): the find bar at the card's top-right.
    @objc func showFindBar(_ sender: Any?) { find?.showFindBar() }

    /// ⌘G (tag 1) and ⇧⌘G (tag −1).
    @objc func findNext(_ sender: Any?) {
        find?.findNext(forward: (sender as? NSMenuItem)?.tag != -1)
    }

    /// ⌘= (tag 1), ⌘- (tag −1), ⌘0 (tag 0).
    @objc func zoomPage(_ sender: Any?) {
        guard let page = tabs?.focusedPage, let item = sender as? NSMenuItem else { return }
        switch item.tag {
        case 1: zoom?.zoomIn(page)
        case -1: zoom?.zoomOut(page)
        default: zoom?.reset(page)
        }
    }

    /// The site panel for the page in the card: its origin's permissions and
    /// site data in the page's own profile (ROADMAP 2.6 task 3).
    func showSitePanel() {
        if sitePanel.isShown { return sitePanel.close() }
        guard let tabs, let page = tabs.current, let origin = SitePanelRules.origin(of: page.url),
              let profile = tabs.engineProfile(for: page), let rootView = windowController?.rootView else { return }
        let model = SitePanelModel(origin: origin, security: page.securityState, profile: profile) { [weak page] in page?.reload() }
        if rootView.isSidebarOpen, let button = sidebar?.addressField.siteButtonView, button.window != nil {
            sitePanel.show(model, relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        } else {
            // No header (hidden sidebar): the card's top-left corner, as the permission popover.
            let card = rootView.currentLayout.card
            sitePanel.show(model, relativeTo: NSRect(x: card.minX + 12, y: card.minY, width: 24, height: 1), of: rootView, preferredEdge: .maxY)
        }
    }

    /// ⌘P: the system print panel (CEF's; ROADMAP 2.6 task 3).
    @objc func printPage(_ sender: Any?) { tabs?.focusedPage?.print() }

    /// ⇧⌘C (tag 0) and ⌥⇧⌘C (tag 1): Copy URL / as Markdown with a toast (spec §F).
    @objc func copyPageURL(_ sender: Any?) {
        sidebar?.copySelectedURL(markdown: (sender as? NSMenuItem)?.tag == 1)
    }

    @objc func toggleDevTools(_ sender: Any?) {
        pageHost?.toggleDevTools()
    }

    /// ⌥⌘J: DevTools on the console.
    @objc func showJavaScriptConsole(_ sender: Any?) { pageHost?.openDevTools(.console) }

    /// ⌥⌘C: DevTools with the element picker on.
    @objc func inspectElements(_ sender: Any?) { pageHost?.openDevTools(.elementPicker) }

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
            return tabs?.shownPeek != nil || sidebar?.canCloseCommandTargets == true
        case #selector(reopenClosedTab(_:)):
            return sidebar?.canReopenClosedTab == true
        case #selector(selectSpaceByNumber(_:)):
            guard let spaces = store?.sidebar.spaces else { return false }
            let index = menuItem.tag == 0 ? 9 : menuItem.tag - 1
            if spaces.indices.contains(index) { menuItem.title = spaces[index].name }
            return spaces.indices.contains(index)
        case #selector(selectAdjacentSpace(_:)):
            return (store?.sidebar.spaces.count ?? 0) > 1
        case #selector(toggleMute(_:)):
            let muted = sidebar?.selectedEntryID.flatMap { tabs?.pageState(for: $0).isMuted } ?? false
            menuItem.title = muted ? CommandName.unmuteTab : CommandName.muteTab
            return sidebar?.selectedHasPage == true
        case #selector(toggleDevTools(_:)):
            menuItem.title = pageHost?.isDevToolsOpen == true ? "Close Developer Tools" : "Developer Tools"
            return tabs?.current != nil
        case #selector(reloadPage(_:)), #selector(showFindBar(_:)), #selector(findNext(_:)), #selector(printPage(_:)),
             #selector(showJavaScriptConsole(_:)), #selector(inspectElements(_:)):
            return tabs?.focusedPage != nil
        case #selector(zoomPage(_:)):
            guard let page = tabs?.focusedPage else { return false }
            switch menuItem.tag {
            case 1: return page.zoomFactor < ZoomRules.steps.last! - 0.001
            case -1: return page.zoomFactor > ZoomRules.steps.first! + 0.001
            default: return !ZoomRules.isDefault(page.zoomFactor)
            }
        case #selector(expandPeek(_:)):
            return tabs?.shownPeek != nil
        case #selector(splitPeek(_:)):
            return tabs?.shownPeek != nil
        case #selector(newSplitPane(_:)):
            return sidebar?.selectedEntryID != nil
        case #selector(removeSplitPane(_:)), #selector(unsplit(_:)):
            return sidebar?.selectedSplit != nil
        case #selector(setSplitLayout(_:)):
            let split = sidebar?.selectedSplit
            menuItem.state = split.map { $0.layout == Self.splitLayout(tag: menuItem.tag) } == true ? .on : .off
            // Outside a split it splits the selected entry with the next one (Zen).
            return sidebar?.selectedEntryID != nil
        case #selector(focusSplitPane(_:)):
            return (sidebar?.selectedSplit?.members.count ?? 0) >= menuItem.tag
        case #selector(focusAdjacentPane(_:)):
            return sidebar?.selectedSplit != nil
        case #selector(hideOrShowSidebar(_:)):
            // Enabled whenever the window exists and no page is in element fullscreen (ROADMAP 2.7b).
            menuItem.title = windowController?.isSidebarOpen == false ? "Show Sidebar" : "Hide Sidebar"
            return windowController.map { !$0.rootView.isPageFullscreen } ?? false
        case #selector(keepSidebarOpen(_:)):
            menuItem.state = windowController?.reveal.isPinned == true ? .on : .off
            return windowController.map { !$0.rootView.isPageFullscreen } ?? false
        case #selector(toggleToolbar(_:)):
            menuItem.state = windowController?.showsToolbar == true ? .on : .off
            return windowController != nil
        case #selector(copyPageURL(_:)):
            return sidebar?.selectedHasURL == true
        case #selector(goBack(_:)):
            return tabs?.focusedPage?.canGoBack == true
        case #selector(goForward(_:)):
            return tabs?.focusedPage?.canGoForward == true
        default:
            return true
        }
    }
}

extension SpaceTint {
    /// A space's theme as the window draws it: its palette, a darker variant
    /// for dark mode (`ThemePalette.darkVariant`), its opacity in the tint range.
    init(_ theme: SpaceTheme) {
        func colors(_ hexes: [String]) -> [NSColor] {
            hexes.compactMap(HSLColor.init(hex:)).map { NSColor(srgbRed: $0.rgb.red, green: $0.rgb.green, blue: $0.rgb.blue, alpha: 1) }
        }
        let range = Double(Materials.tintOpacityRange.lowerBound)...Double(Materials.tintOpacityRange.upperBound)
        self.init(light: colors(theme.colors), dark: colors(ThemePalette.darkVariant(theme.colors)),
                  alpha: CGFloat(ThemePalette.tintAlpha(opacity: theme.opacity, range: range)))
    }
}
