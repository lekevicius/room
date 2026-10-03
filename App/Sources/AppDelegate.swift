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
        rootView.onLayout = { [weak toasts, weak palette] in
            toasts?.updateAnchor()
            palette?.layout()
        }
        self.palette = palette
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
        tools.onLayout = { [weak statusPill, weak zoom] in
            statusPill?.layout()
            zoom?.layout()
        }
        pageDelegate.onStatusText = { [weak statusPill] text in statusPill?.setStatus(text) }
        pageDelegate.onPageClosed = { [weak find] page in find?.pageClosed(page) }
        self.find = find
        self.zoom = zoom
        self.statusPill = statusPill
        pageHost.onShow = { [weak chrome, weak fullscreen, weak find, weak zoom, weak statusPill] contents in
            chrome?.prompts.setCurrentPage(contents)
            fullscreen?.cardDidShow(contents)
            find?.setPage(contents)
            zoom?.setPage(contents)
            statusPill?.reset()
        }
        find.setPage(pageHost.contents)
        sidebar.addressField.onSiteButton = { [weak self] in self?.showSitePanel() }
        chrome.prompts.setCurrentPage(pageHost.contents)
        chrome.performMenuAction = { [weak tabs] action, page in
            switch action {
            case .openLinkInNewTab(let url), .openImageInNewTab(let url):
                tabs?.openLink(url, from: page)
            case .openLinkInPeek:
                break  // Peek is Phase 2.7; the item is disabled until then.
            case .copyLink(let url), .copyImageAddress(let url):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
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

    /// File ▸ New Space (the form in the sidebar).
    @objc func newSpace(_ sender: Any?) { sidebar?.newSpace() }

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
        guard let page = tabs?.current, let item = sender as? NSMenuItem else { return }
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
    @objc func printPage(_ sender: Any?) { tabs?.current?.print() }

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
            return sidebar?.canCloseCommandTargets == true
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
            return tabs?.current != nil
        case #selector(zoomPage(_:)):
            guard let page = tabs?.current else { return false }
            switch menuItem.tag {
            case 1: return page.zoomFactor < ZoomRules.steps.last! - 0.001
            case -1: return page.zoomFactor > ZoomRules.steps.first! + 0.001
            default: return !ZoomRules.isDefault(page.zoomFactor)
            }
        case #selector(copyPageURL(_:)):
            return sidebar?.selectedHasURL == true
        case #selector(goBack(_:)):
            return tabs?.current?.canGoBack == true
        case #selector(goForward(_:)):
            return tabs?.current?.canGoForward == true
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
