import AppKit
import Chrome
import CrashReports
import Design
import Engine
import FakeEngine
import Infra
import Integration
import Library
import Model
import Omnibox
import Palette
import Sidebar
import Store
import SwiftUI
import Tabs
import UIKitCore
import Updates
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let engine: any EngineApplication
    private(set) var store: RoomStore?
    private(set) var windowController: RoomWindowController?
    private(set) var settingsWindow: SettingsWindowController?
    private(set) var pageHost: PageHost?
    /// The card's content view (DEBUG spikes read what it shows).
    var pageHostContainer: PageContainerView? { pageHost?.container }
    #if DEBUG
    /// The card's host (split spikes read its panes and time focus changes).
    var debugPageHost: PageHost? { pageHost }
    #endif
    private(set) var pageDelegate: PageUIDelegate?
    #if DEBUG
    /// Launch lines the spikes report (the state open time, the history migration).
    static var launchLog: [String] = []
    #endif
    private(set) var overlays: OverlaySpike?
    private(set) var sidebar: SidebarController?
    /// The window's pages: entries on the engine (Phase 2.3).
    private(set) var tabs: TabController?
    /// Chrome extensions per profile: Settings ▸ Extensions, consent, updates (3.6a); nil without an engine.
    private(set) var extensions: ExtensionsCenter?
    private var extensionConsent: ExtensionConsentSheets?
    /// The header's action buttons and popups (3.6b), once the center and the window exist.
    private(set) var extensionPopups: ExtensionPopups?
    /// Extension commands while the sidebar or the palette has the keyboard (4.5, B-70).
    private(set) var extensionKeys: ExtensionKeyRouter?
    private(set) var switcher: TabSwitcher?
    /// The Library in the sidebar (⇧⌘L, ⌘Y; 4.1a, `LibraryUI.swift`).
    var library: LibraryController?
    /// The archive sweep: at launch and every 10 min while idle (spec §A.7, 4.1a).
    private(set) var archiveSweeper: ArchiveSweeper?
    /// Rolling backups: at launch and every 30 min while the state changes (spec §H, 4.1b).
    private(set) var backupScheduler: BackupScheduler?
    /// Help ▸ Restore Sidebar…'s sheet while it shows (`RestoreSidebar.swift`).
    var restoreSheet: NSWindow?
    /// Space routing (spec §B, 4.2): external links and links between spaces; the rules sheet.
    private(set) var spaceRouter: SpaceRouter?
    var routingSheet: NSWindow?
    var routingModel: RoutingRulesModel?
    /// The import sheet while it shows (`ImportUI.swift`, 4.3a).
    var importSheet: NSWindow?
    var importModel: ImportSheetModel?
    /// The other browser's extensions' store pages, opening one at a time (4.3b).
    var extensionStorePages: ExtensionStorePages?
    /// The user's shortcuts (4.4a, `Shortcuts.swift`): defaults plus `Settings.shortcutOverrides`.
    var shortcutTable = ShortcutTable()
    /// How long the last table took to reach the menu bar (the settings spike reads it).
    var lastShortcutsApplyMilliseconds = 0.0
    /// The previous session crashed: every entry was restored unloaded and the toast shown (spec §H, 4.1b).
    private(set) var crashRecovered = false
    /// ⌘T / ⌘L (Phase 2.4).
    private(set) var palette: PaletteController?
    private(set) var toastCenter: ToastCenter?
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
    /// Links from the system, held until the store and the engine are up (ROADMAP 2.8 task 3).
    let inbox = URLInbox()
    /// Whether Room is the default browser, and the request (2.8b).
    let defaultBrowser = DefaultBrowser()
    /// Sparkle and Sentry behind their opt-ins (ROADMAP 2.8 task 5); nil while the store is not open.
    private(set) var optIns: OptInServices?
    /// The first run over Settings and its card in the sidebar (ROADMAP 2.8 task 4).
    private(set) var firstRun: FirstRun?
    private(set) var firstRunCard: FirstRunCardView?
    #if DEBUG
    /// URL ingestion as it happens (the 2.8b spike reads it): each event, whether it was queued, each tab opened.
    private(set) var debugIncomingLog: [(event: String, url: URL, at: Date)] = []
    #endif
    #if DEBUG
    /// Sidebar captures run on FakeEngine pages (no network, stable states).
    private let fakeEngine = FakeApplication()
    #endif

    /// The app delegate (also `NSApp.delegate` on both engines; RoomCore
    /// installs it when it creates NSApp, 3.2b).
    private(set) static weak var current: AppDelegate?
    /// Whether the previous session ended cleanly by both counts: the store's
    /// clean-exit mark and the engine's exit type for every profile it
    /// tracks. Set once the engine profiles exist.
    private(set) var previousExitWasClean: Bool?
    /// The line `logPreviousExit` wrote (the 3.2b quit spikes read it).
    private(set) var previousExitSummary: String?
    /// A quit is waiting for the engine (`applicationShouldTerminate`).
    private var quitInProgress = false
    private var finalStateWritten = false

    init(engine: any EngineApplication) {
        self.engine = engine
        super.init()
        Self.current = self
        engine.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The address field's full-URL tooltip appears after 600 ms (spec §C).
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": Int(Timing.urlTooltipDelay * 1000)])
        NSLog("Room: NSApp.delegate is %@", NSApp.delegate.map { String(describing: type(of: $0)) } ?? "nil")
        NSApp.mainMenu = MainMenu.make(target: self)
        store = Self.openStore()
        if Self.quitRequested {
            NSApp.terminate(nil)
            return
        }
        #if DEBUG
        // Spikes, captures and fixtures run on a throwaway store without the card, unless they ask for it;
        // `-RoomFirstRun YES` shows it even on a state where it was done (the grand tour's one state, Phase 2.9).
        if UserDefaults.standard.bool(forKey: "RoomFirstRun") {
            store?.settings.update { $0.firstRunDone = false }
        } else if SnapshotRunner.directory != nil || SpikeRunner.requested != nil || SidebarFixtures.requested != nil {
            store?.settings.update { $0.firstRunDone = true }
        }
        #endif
        // Before anything else runs: crash reports start here when the user opted in, and only then.
        optIns = makeOptIns()
        applyOptIns()
        showWindow()
        NSApp.activate()
        Task { await startSession() }
    }

    /// Every model profile's engine profile (a Chromium profile at
    /// `<root>/Room Profile <name>`, ROADMAP 2.5 task 4): the tab controller
    /// loads the selected entry once its profile exists. Then the DEBUG runners.
    private func startSession() async {
        guard let controller = windowController, let pageHost, let tabs, let pageDelegate else { return }
        do {
            let profiles = store?.sidebar.profiles ?? []
            for model in profiles where tabs.engineProfiles[model.id] == nil {
                let profile = try await engine.createProfile(name: TabController.engineProfileName(for: model))
                prepare(profile, for: model)
                holdSelectionAfterCrash(profile, tabs: tabs)
                if tabs.engineProfiles[model.id] == nil { tabs.setEngineProfile(profile, for: model.id) }
            }
            // Before the spikes and the user's first query: the Chapter 2 history into the engine's (once per profile).
            await migrateHistory(tabs: tabs)
            #if DEBUG
            // `-RoomHistoryRows N`: the engine's history filled to N URLs (the palette's 50k measurement).
            if let rows = HistoryFixture.requestedRows, let model = store?.sidebar.profiles.first,
               let history = tabs.engineProfiles[model.id]?.history,
               let result = await HistoryFixture.populate(history, rows: rows) {
                Self.launchLog.append("history fixture: \(result.urls) URLs, \(result.visits) visits into the engine's history")
            }
            #endif
            // The Phase 1.4 overlay spikes (DEBUG `SpikeRunner`).
            overlays = OverlaySpike(rootView: controller.rootView)
            if let start = UserDefaults.standard.string(forKey: "RoomStartURL") {
                tabs.openNewTab(url: URLFixup.url(from: start) ?? URLFixup.searchURL(for: start))
            }
            logPreviousExit(tabs.engineProfiles.values.map { $0 })
            if previousExitWasClean == false { announceCrashRecovery() }
        } catch {
            NSLog("Room: no engine profile (\(error)); the window stays empty")
        }
        // The store and the engine are up: links that came with the launch open now, later ones as they come.
        inbox.open { [weak self] urls in self?.openIncoming(urls) }
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

    // MARK: Links from other apps (ROADMAP 2.8 task 3)

    /// Every way a link reaches Room (another app once Room is the default
    /// browser, `open`, Finder's Open With, AppleScript's `open location`). On a
    /// cold launch this runs before `applicationDidFinishLaunching`.
    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        let queued = !inbox.isOpen
        for url in urls { debugIncomingLog.append((queued ? "queued" : "event", url, Date())) }
        #endif
        let taken = inbox.receive(urls)
        if taken.count < urls.count { NSLog("Room: ignored \(urls.count - taken.count) link(s) of a scheme Room does not open") }
    }

    /// Each link as a selected Today tab at the end of the list of the space
    /// the routing rules choose (spec §B, 4.2: a rule, else Settings ▸ Links'
    /// default, the most recent space by default), with the toast when that is
    /// not the shown space; with no window showing (after ⇧⌘W) the window comes back first.
    private func openIncoming(_ urls: [URL]) {
        guard let tabs else { return NSLog("Room: no sidebar to open \(urls.count) link(s) in") }
        if windowController?.window?.isVisible != true { newRoomWindow(nil) }
        for url in urls {
            if let spaceRouter { spaceRouter.openExternal(url) } else { tabs.openNewTab(url: url.absoluteString, transition: .link) }
            #if DEBUG
            debugIncomingLog.append(("requested", url, Date()))
            #endif
        }
    }

    // MARK: Opt-ins (ROADMAP 2.8 task 5)

    private func makeOptIns() -> OptInServices? {
        guard store != nil else { return nil }
        var dsn = BuildConfiguration.sentryDSN()
        var feed: String?
        #if DEBUG
        // The opt-in checks point both at local endpoints (`scripts/app-integration.sh --session 2.8b`).
        if let override = UserDefaults.standard.string(forKey: "RoomSentryDSN") { dsn = override }
        feed = UserDefaults.standard.string(forKey: "RoomUpdateFeedURL")
        #endif
        return OptInServices(dsn: dsn, makeUpdater: { SparkleUpdater(feedOverride: feed) },
                             makeCrashReporter: { SentryCrashReporter() })
    }

    /// The services follow the two settings at once, from the first run's card or Settings ▸ Privacy.
    private func applyOptIns() {
        guard let settings = store?.settings, let optIns else { return }
        let (crashReports, updateChecks) = withObservationTracking {
            (settings.settings.crashReports, settings.settings.automaticUpdateChecks)
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.applyOptIns() }
        }
        optIns.apply(crashReports: crashReports, automaticUpdateChecks: updateChecks)
    }

    // MARK: First run (ROADMAP 2.8 task 4)

    private func installFirstRun(sidebar: SidebarController, settings: SettingsStore) {
        firstRun = FirstRun(read: { [weak settings] in settings?.settings ?? Settings() },
                            write: { [weak settings] body in settings?.update(body) })
        updateFirstRunCard(sidebar: sidebar, settings: settings)
    }

    /// The card shows while the first run is not done: at the first launch and after Settings ▸ Show Welcome Card.
    private func updateFirstRunCard(sidebar: SidebarController, settings: SettingsStore) {
        let showing = withObservationTracking {
            !settings.settings.firstRunDone
        } onChange: { [weakSelf = MainActorWeak(self), weakSidebar = MainActorWeak(sidebar), weakSettings = MainActorWeak(settings)] in
            Task { @MainActor in
                guard let sidebar = weakSidebar.value, let settings = weakSettings.value else { return }
                weakSelf.value?.updateFirstRunCard(sidebar: sidebar, settings: settings)
            }
        }
        let body = sidebar.bodyView
        if showing, firstRunCard == nil, let firstRun {
            let card = FirstRunCardView(firstRun: firstRun, defaultBrowser: defaultBrowser,
                                        crashReportsUnavailable: optIns?.crashReportsUnavailable ?? true,
                                        onImport: { [weak self] in self?.showImportSheet(nil) }) { [weak firstRun] in
                firstRun?.finish()
            }
            firstRunCard = card
            body.accessoryHeight = { [weak card] width in card?.height(forWidth: width) ?? 0 }
            body.accessoryView = card
        } else if !showing, let card = firstRunCard {
            firstRunCard = nil
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fast
                card.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    if body.accessoryView === card { body.accessoryView = nil }
                }
            }
        }
    }

    /// Settings ▸ General ▸ Show Welcome Card: the card again, in sight (the hidden sidebar's overlay is pinned for it).
    func showWelcomeCard() {
        firstRun?.showAgain()
        newRoomWindow(nil)
        if windowController?.isSidebarOpen == false { hiddenSidebar?.revealForSpaceForm() }
    }

    /// App ▸ Check for Updates…, Settings ▸ Privacy ▸ Check Now.
    @objc func checkForAppUpdates(_ sender: Any?) {
        optIns?.checkForUpdates(automaticUpdateChecks: store?.settings.settings.automaticUpdateChecks ?? false)
    }

    /// App ▸ Set as Default Browser…, Settings ▸ General, the first-run card: the system's dialog.
    @objc func makeDefaultBrowser(_ sender: Any?) {
        defaultBrowser.setAsDefault()
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
    /// The state directory this launch opens (`-RoomStateDirectory`, a
    /// DEBUG throwaway, else `~/Library/Application Support/Room`).
    static var stateDirectory: URL {
        var directory = AppPaths.applicationSupport
        if let override = UserDefaults.standard.string(forKey: "RoomStateDirectory") {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        }
        #if DEBUG
        // An explicit `-RoomStateDirectory` wins (the relaunch measurement reuses one).
        if let throwaway = Self.throwawayStateDirectory { directory = throwaway }
        #endif
        return directory
    }

    private static func openStore() -> RoomStore? {
        let directory = stateDirectory
        do {
            let opening = ContinuousClock.now
            let store = try RoomStore.open(directory: directory)
            #if DEBUG
            // `-RoomClock <ISO 8601 date>`: the store's clock starts there and runs on, so
            // fixture entries age without waiting (the archive sweep, 4.1a).
            if let text = UserDefaults.standard.string(forKey: "RoomClock"),
               let start = ISO8601DateFormatter().date(from: text) {
                let offset = start.timeIntervalSinceNow
                store.sidebar.clock = { Timestamp(Date().addingTimeInterval(offset)) }
                debugClockOffset = offset
                NSLog("Room: clock set to %@ (offset %.0f s)", text, offset)
            }
            #endif
            let elapsed = ContinuousClock.now - opening
            let check = store.integrityCheck == .full ? "integrity_check" : store.integrityCheck == .quick ? "quick_check" : "recovered"
            let milliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            NSLog("Room: state opened in %.1f ms (%@)", milliseconds, check)
            #if DEBUG
            Self.launchLog.append(String(format: "state opened in %.1f ms (%@)", milliseconds, check))
            #endif
            if store.uncleanExit { NSLog("Room: the previous session did not quit cleanly") }
            if let recovery = store.recovery { NSLog("Room: database rebuilt at launch: \(recovery)") }
            return store
        } catch {
            NSLog("Room: cannot open the state database in \(directory.path): \(error); nothing will be saved")
            presentStoreError(error, directory: directory)
            return nil
        }
    }

    #if DEBUG
    /// `-RoomClock`'s offset from the real clock (seconds), when given (the archive spike reports it).
    static var debugClockOffset: TimeInterval?
    /// The window's toasts (spikes press their buttons).
    var debugToastCenter: ToastCenter? { toastCenter }

    /// The throwaway state directory of a snapshot, spike or fixture launch
    /// without `-RoomStateDirectory` (nil otherwise). Decided once, before the
    /// engine starts: `main.swift` puts the engine root inside it (B-78).
    static let throwawayStateDirectory: URL? = {
        guard UserDefaults.standard.string(forKey: "RoomStateDirectory") == nil,
              SnapshotRunner.directory != nil || SpikeRunner.requested != nil || SidebarFixtures.requested != nil
                || HistoryFixture.requestedRows != nil
        else { return nil }
        return FileManager.default.temporaryDirectory.appending(path: "Room-\(UUID().uuidString)", directoryHint: .isDirectory)
    }()

    /// The engine root of a DEBUG launch (B-78): `-RoomEngineDirectory` when
    /// given, else `<state>/engine` for `-RoomStateDirectory` or a throwaway
    /// state, else nil (the real root: a launch with neither flag and no spike).
    static var debugEngineDirectory: URL? {
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: "RoomEngineDirectory") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let state = defaults.string(forKey: "RoomStateDirectory") {
            return URL(fileURLWithPath: state, isDirectory: true).appending(path: "engine", directoryHint: .isDirectory)
        }
        return throwawayStateDirectory?.appending(path: "engine", directoryHint: .isDirectory)
    }
    #endif

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
        // A profile made after launch (a new space's "New Profile…") gets its engine profile on first use.
        tabs.requestEngineProfile = { [weak self, weak tabs] model in
            Task { @MainActor in
                guard let self, let tabs else { return }
                do {
                    let profile = try await self.engine.createProfile(name: TabController.engineProfileName(for: model))
                    self.prepare(profile, for: model)
                    self.holdSelectionAfterCrash(profile, tabs: tabs)
                    tabs.setEngineProfile(profile, for: model.id)
                } catch {
                    NSLog("Room: no engine profile for \(model.name): \(error)")
                }
            }
        }
        tabs.display = pageHost
        tabs.window = controller.window
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
        // Space routing (spec §B, 4.2): links a page opens as new tabs follow the rules when the setting is on.
        let router = SpaceRouter(store: store, sidebar: sidebar, tabs: tabs, toasts: toasts)
        spaceRouter = router
        tabs.routeLink = { [weak router] url, source in router?.routePageLink(url, from: source) }
        tabs.onLinkRouted = { [weak router] _, space in router?.announce(space) }
        sidebar.onRoutingSettings = { [weak self] newRule in self?.showRoutingRules(newRule: newRule) }
        // The engine's notices (infobars, the translate offer) as toasts (3.4b).
        pageDelegate.chrome.showNotice = { [weak toasts] toast in toasts?.show(toast) }
        pageDelegate.chrome.dismissNotice = { [weak toasts] id in toasts?.dismiss(id: id) }
        pageDelegate.toasts = toasts
        let downloads = DownloadsUI(button: sidebar.downloadsButton, rootView: rootView, toasts: toasts, settings: store.settings)
        downloads.pageFavicon = { [weak tabs] in tabs?.current?.favicon }
        self.downloads = downloads
        installLibrary(sidebar: sidebar, tabs: tabs, store: store)
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
        palette.onRestoreArchived = { [weak self] id in self?.restoreArchived(id) }
        let settings = store.settings
        // Settings ▸ Search (4.4a): the shown space's profile's engine; every engine's keyword.
        palette.searchEngine = { [weak settings, weak sidebar, weak store] in
            guard let settings else { return .google }
            let profile = sidebar.flatMap { store?.sidebar.space($0.activeSpaceID)?.profileID }
            return SearchEngines.engine(for: profile, in: settings.settings)
        }
        palette.siteSearches = { [weak settings] in settings.map { SearchEngines.siteSearches($0.settings) } ?? SiteSearch.defaults }
        palette.suggestionsEnabled = { [weak settings] in settings?.settings.searchSuggestions ?? false }
        var proxy: String?
        #if DEBUG
        // The no-network check routes suggestion requests through a logging proxy (spike-results 2.4b).
        proxy = UserDefaults.standard.string(forKey: "RoomSuggestProxy")
        #endif
        palette.suggest = SuggestClient(transport: URLSessionSuggestTransport(proxy: proxy), debounce: .seconds(Timing.suggestDebounce))
        // RoomCore (3.5): Chrome's omnibox and history answer the palette; nil without an engine (the local providers and the client above run).
        palette.makeAutocomplete = { [weak tabs] profile in tabs?.engineProfiles[profile]?.makeAutocompleteController() }
        palette.engineHistory = { [weak tabs] profile in tabs?.engineProfiles[profile]?.history }
        pageDelegate.onFocusLocationBar = { [weak tabs, weak palette] _ in
            guard let palette, !palette.isOpen else { return }
            tabs?.openLocation()
        }
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
        applyLookSettings()
        trackFocusedPage(tabs)
        // The glass and the rows' hosting view are built before the first ⌘T.
        DispatchQueue.main.async { [weak palette] in palette?.prewarm() }
        if let window = controller.window {
            switcher = TabSwitcher(window: window, hostView: controller.cardView, sidebar: sidebar, tabs: tabs)
        }
        self.sidebar = sidebar
        self.tabs = tabs
        self.pageDelegate = pageDelegate
        observeShortcuts()
        installExtensionPopups()
        toastCenter = toasts
        installFirstRun(sidebar: sidebar, settings: store.settings)
        // RoomCore reports memory pressure itself (Chromium's listener, 3.7b);
        // without an engine the tab controller listens to macOS's events.
        #if ROOM_ENGINE_ROOMCORE
        tabs.startLifecycle(systemMemoryPressure: false)
        #else
        tabs.startLifecycle(systemMemoryPressure: true)
        #endif
        // The launch sweep (spec §A.7) before anything loads: the selection is never taken.
        let sweeper = ArchiveSweeper(tabs: tabs, store: store)
        archiveSweeper = sweeper
        sweeper.start()
        // Rolling backups (spec §H): one now if the state moved since the last, then every 30 min.
        let backups = BackupScheduler(store: store)
        backupScheduler = backups
        backups.start()
        // Only the selected entry loads at launch (spec §H); it waits for the profile. After a
        // crash (the store's running flag here, the engine's exit type when its profiles arrive)
        // not even that one: every entry is restored unloaded.
        if store.uncleanExit { tabs.holdsSelectionUnloaded = true }
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
        // Chrome's own bubbles (RoomCore, 3.7a) point where the permission popover does.
        pageDelegate.bubbleAnchor = { [weak rootView, weak sidebar] in
            guard let rootView, rootView.window != nil else { return nil }
            if rootView.isSidebarOpen, let button = sidebar?.addressField.siteButtonView, button.window != nil {
                return button.convert(button.bounds, to: nil)
            }
            let card = rootView.currentLayout.card
            return rootView.convert(NSRect(x: card.minX + 12, y: card.minY, width: 24, height: 1), to: nil)
        }
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

    /// Settings ▸ Appearance (v0, ROADMAP 2.8 task 2): the app's appearance and the sidebar's side,
    /// applied now and again whenever either changes.
    private func applyLookSettings() {
        guard let settings = store?.settings else { return }
        let (appearance, side, toolbar) = withObservationTracking {
            (settings.settings.appearance, settings.settings.sidebarSide, settings.settings.showsToolbar)
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.applyLookSettings() }
        }
        #if DEBUG
        // Spikes set the appearance they capture in.
        let spikeAppearance = UserDefaults.standard.string(forKey: "RoomSpikeAppearance") != nil
        #else
        let spikeAppearance = false
        #endif
        if !spikeAppearance {
            NSApp.appearance = switch appearance {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
        windowController?.rootView.sidebarEdge = side == .right ? .right : .left
        // Settings ▸ General ▸ Show the toolbar (4.4a) as View ▸ Show Toolbar.
        if let controller = windowController, controller.showsToolbar != toolbar { controller.showsToolbar = toolbar }
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

    /// A new engine profile's host services: downloads, Room's search engine,
    /// and (RoomCore, 3.6a) its extensions in Settings with their consent
    /// sheets and the daily update check.
    private func prepare(_ profile: any Engine.Profile, for model: Model.Profile) {
        profile.downloadsDelegate = downloads?.list
        applySearchSettings(to: profile, profileID: model.id)
        if let engineExtensions = profile.extensions {
            extensionsCenter().add(profile: model.id, name: model.name, extensions: engineExtensions)
        }
    }

    /// Chrome extensions across profiles (3.6a), made with the first profile that has them.
    private func extensionsCenter() -> ExtensionsCenter {
        if let extensions { return extensions }
        let sheets = ExtensionConsentSheets { [weak self] in self?.windowController?.window }
        let center = ExtensionsCenter(
            consent: sheets,
            openTab: { [weak self] url, profile in self?.openExtensionPage(url, profile: profile) },
            lastUpdateCheck: { [weak self] in self?.store?.settings.settings.extensionsLastUpdateCheck },
            setLastUpdateCheck: { [weak self] date in self?.store?.settings.update { $0.extensionsLastUpdateCheck = date } })
        extensionConsent = sheets
        extensions = center
        installExtensionPopups()
        return center
    }

    /// The header's action buttons and their popovers (3.6b): made once both the
    /// extensions center (the first profile with extensions) and the window exist.
    private func installExtensionPopups() {
        guard extensionPopups == nil, let extensions, let sidebar, let tabs, let rootView = windowController?.rootView else { return }
        extensionPopups = ExtensionPopups(center: extensions, sidebar: sidebar, tabs: tabs, rootView: rootView)
        extensionKeys = ExtensionKeyRouter(
            center: extensions, window: { [weak rootView] in rootView?.window },
            pageHasKeyboard: { [weak self] in self?.pageHasKeyboard ?? false },
            profile: { [weak sidebar] in sidebar?.activeSpace?.profileID },
            page: { [weak tabs] in tabs?.focusedPage })
    }

    /// An extension's page (its options, `chrome://extensions`, its shortcuts
    /// page) as a Today tab in a space of the extension's profile, shown
    /// (B-67, 4.5): the shown space when it is that profile's, else the
    /// profile's first space, else a new "Extensions" space for it.
    func openExtensionPage(_ url: URL, profile: UUID) {
        guard let store, let sidebar, let tabs else { return }
        let spaceID: UUID
        switch ExtensionPageSpace.choose(profile: profile, shownSpace: sidebar.activeSpaceID, spaces: store.sidebar.spaces) {
        case .existing(let id):
            spaceID = id
        case .create(let name):
            guard let space = try? store.sidebar.createSpace(name: name, profile: profile) else { return }
            spaceID = space.id
        }
        if spaceID != sidebar.activeSpaceID { sidebar.showSpace(spaceID, animated: false) }
        tabs.openNewTab(url: url.absoluteString, inSpace: spaceID, transition: .link)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    /// The keyboard is in a page (the card's panes or the Peek's): the
    /// engine's own key path sees the key first there.
    var pageHasKeyboard: Bool {
        guard let responder = windowController?.window?.firstResponder as? NSView else { return false }
        if let pageHost, responder.isDescendant(of: pageHost.splitView) { return true }
        if let peek, responder.isDescendant(of: peek.overlay) { return true }
        return false
    }

    /// The Settings switch holds at once (CLAUDE.md): turned off, the open
    /// palette drops its suggestions and the client sends nothing more.
    private func observeSuggestionsSwitch(_ settings: SettingsStore, palette: PaletteController) {
        withObservationTracking {
            _ = settings.settings.searchSuggestions
            _ = settings.settings.searchEngine
            _ = settings.settings.searchEngines
            _ = settings.settings.searchEngineByProfile
        } onChange: { [weak self, weak settings, weak palette] in
            Task { @MainActor in
                guard let self, let settings, let palette else { return }
                palette.suggestionsSettingChanged()
                for (id, profile) in self.tabs?.engineProfiles ?? [:] { self.applySearchSettings(to: profile, profileID: id) }
                self.observeSuggestionsSwitch(settings, palette: palette)
            }
        }
    }

    /// Room's search engine as the engine profile's default (3.5: Chrome's
    /// SearchProvider asks it, only while the switch is on); on RoomCore the
    /// switch is mirrored into Chrome's search-suggest preference as well.
    /// DEBUG: `-RoomSuggestURL <template>`, or `-RoomSuggestProxy host:port`
    /// (the tour's logging server), points the suggestions at a local endpoint.
    func applySearchSettings(to profile: any Engine.Profile, profileID: UUID) {
        guard let settings = store?.settings.settings else { return }
        var suggestURL: String?
        #if DEBUG
        if let template = UserDefaults.standard.string(forKey: "RoomSuggestURL") {
            suggestURL = template
        } else if let proxy = UserDefaults.standard.string(forKey: "RoomSuggestProxy") {
            suggestURL = "http://\(proxy)/complete/search?client=room&q={searchTerms}"
        }
        #endif
        // Settings ▸ Search (4.4a): this profile's default engine.
        profile.setDefaultSearchEngine(SearchEngines.engine(for: profileID, in: settings).engineTemplate(suggestURL: suggestURL))
        #if ROOM_ENGINE_ROOMCORE
        (profile as? RoomCoreProfile)?.searchSuggestEnabled = settings.searchSuggestions
        #endif
    }

    /// ROADMAP 3.5 task 5: each profile's Chapter 2 history into the engine's
    /// history service, once (the flag is in Settings); since schema v6 from
    /// the rows v6 archived for a profile never imported (`HistoryMigration`).
    /// A no-op without an engine history.
    private func migrateHistory(tabs: TabController) async {
        guard let store else { return }
        #if DEBUG
        // `-RoomHistoryMigration NO`: the launch measurement's "before" runs (3.5).
        if UserDefaults.standard.object(forKey: "RoomHistoryMigration") != nil, !UserDefaults.standard.bool(forKey: "RoomHistoryMigration") {
            Self.launchLog.append("history migration: skipped (-RoomHistoryMigration NO)")
            return
        }
        #endif
        for model in store.sidebar.profiles {
            guard let history = tabs.engineProfiles[model.id]?.history else { continue }
            let line: String
            if let report = await HistoryMigration.run(store: store, profile: model.id, into: history) {
                line = String(format: "history migration: profile %@: %ld archived URLs -> %ld URLs, %ld visits imported "
                              + "(%ld visits, %ld URLs older than the engine keeps) in %.2f s", model.name, report.localURLs,
                              report.result.urls, report.result.visits, report.result.expiredVisits, report.result.expiredURLs, report.seconds)
            } else {
                line = "history migration: profile \(model.name) already imported (flag set); nothing read"
            }
            NSLog("Room: %@", line)
            #if DEBUG
            Self.launchLog.append(line)
            #endif
        }
    }

    /// Crash recovery (spec §H, 4.1b): an engine profile whose last exit was
    /// not clean keeps the launch's selection unloaded (set before the
    /// profile is delivered, which would load it).
    /// `model`'s engine profile, made now when it has none yet (a profile an
    /// import just created, whose history goes in before any page loads; 4.3a).
    func engineProfile(for model: Model.Profile) async -> (any Engine.Profile)? {
        guard let tabs else { return nil }
        if let profile = tabs.engineProfiles[model.id] { return profile }
        do {
            let profile = try await engine.createProfile(name: TabController.engineProfileName(for: model))
            if tabs.engineProfiles[model.id] == nil {
                prepare(profile, for: model)
                holdSelectionAfterCrash(profile, tabs: tabs)
                tabs.setEngineProfile(profile, for: model.id)
            }
            return tabs.engineProfiles[model.id]
        } catch {
            NSLog("Room: no engine profile for \(model.name): \(error)")
            return nil
        }
    }

    private func holdSelectionAfterCrash(_ profile: any Engine.Profile, tabs: TabController) {
        guard !crashRecovered, profile.lastExitWasClean == false else { return }
        tabs.holdsSelectionUnloaded = true
    }

    /// The toast, once per launch, after either count said the last session
    /// did not end cleanly; the card shows its empty state.
    private func announceCrashRecovery() {
        guard !crashRecovered else { return }
        crashRecovered = true
        toastCenter?.show(Toast(id: "crash-recovery", symbol: .reload, message: "Room restarted after a crash"))
        NSLog("Room: crash recovery: every entry restored unloaded (loaded now: %ld)", tabs?.loadedEntryIDs.count ?? -1)
        #if DEBUG
        Self.launchLog.append("crash recovery: toast “Room restarted after a crash”, \(tabs?.loadedEntryIDs.count ?? -1) pages loaded")
        #endif
    }

    /// The store's `uncleanExit` and the engine's exit type, combined: either
    /// one saying the previous session did not end cleanly makes it unclean.
    private func logPreviousExit(_ profiles: [any Engine.Profile]) {
        let engineFlags = profiles.compactMap { profile in profile.lastExitWasClean.map { (profile.name, $0) } }
        let storeClean = !(store?.uncleanExit ?? false)
        let clean = storeClean && engineFlags.allSatisfy(\.1)
        previousExitWasClean = clean
        let summary = "clean=\(clean) (store uncleanExit=\(!storeClean), engine lastExitWasClean "
            + (engineFlags.isEmpty ? "n/a" : engineFlags.map { "\($0.0)=\($0.1)" }.joined(separator: " ")) + ")"
        previousExitSummary = summary
        NSLog("Room: previous exit %@", summary)
    }

    /// Final state write (the store's single-transaction write with the
    /// clean-exit mark); called once at quit, whichever path gets there first.
    func shutdown() {
        guard !finalStateWritten else { return }
        finalStateWritten = true
        store?.close()
        NSLog("Room: final state written")
    }

    /// ⌘Q, the Dock's Quit, logout, Chrome's own quit requests (RoomCore's
    /// NSApp asks here before Chrome's close path). The engine closes its
    /// pages first, beforeunload handlers included: a page answering "stay"
    /// cancels the quit with every page and entry as it was (pages the quit
    /// closes leave their entries alone: `isTerminating`); otherwise the
    /// state is written, and only then does the quit proceed.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitInProgress { return .terminateLater }
        quitInProgress = true
        NSLog("Room: quit requested")
        var answered = false
        var synchronousAnswer: Bool?
        engine.tryToTerminate { [weak self] proceed in
            self?.quitInProgress = false
            if proceed {
                self?.shutdown()
                NSLog("Room: quit proceeds")
            } else {
                NSLog("Room: quit cancelled by a page")
            }
            if answered {
                sender.reply(toApplicationShouldTerminate: proceed)
            } else {
                synchronousAnswer = proceed
            }
        }
        answered = true
        if let synchronousAnswer { return synchronousAnswer ? .terminateNow : .terminateCancel }
        return .terminateLater
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

    /// ⌘,: Settings v0 (General, Appearance, Search, Downloads).
    @objc func showSettings(_ sender: Any?) {
        guard let store else { return }
        if settingsWindow == nil {
            let services = SettingsServices(
                defaultBrowser: defaultBrowser, crashReportsUnavailable: optIns?.crashReportsUnavailable ?? true,
                showWelcomeCard: { [weak self] in self?.showWelcomeCard() },
                checkForUpdates: { [weak self] in self?.checkForAppUpdates(nil) },
                canCheckForUpdates: { [weak self] in self?.optIns?.canCheckForUpdates ?? false },
                extensions: { [weak self] in self?.extensions },
                shownPage: { [weak self] in
                    guard let page = self?.tabs?.focusedPage, let profile = self?.sidebar?.activeSpace?.profileID else { return nil }
                    return (page, profile)
                },
                sidebar: store.sidebar,
                showRoutingRules: { [weak self] in self?.showRoutingRules(over: self?.settingsWindow?.window) },
                showImportSheet: { [weak self] in self?.showImportSheet(nil) },
                profiles: profileServices())
            settingsWindow = SettingsWindowController(settings: store.settings, services: services)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Settings at one section (4.4b: the palette's "Settings ▸ …" and the
    /// app menu's Settings Section items).
    func showSettings(section: SettingsWindowController.Section) {
        showSettings(nil)
        settingsWindow?.select(section)
    }

    /// Room ▸ Settings Section ▸ …: the item's tag is the section's place + 1.
    @objc func showSettingsSection(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 1
        let sections = SettingsWindowController.Section.allCases
        showSettings(section: sections.indices.contains(tag - 1) ? sections[tag - 1] : .general)
    }

    #if DEBUG
    /// The Settings window (spikes capture each section).
    var debugSettingsWindow: SettingsWindowController? { settingsWindow }
    #endif

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

    /// ⌥⌘G (tag 0), ⌥⌘V (1), Stacked (2, no key: ⌥⌘H is Hide Others, B-36).
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

    /// ⌘P: Chrome's print preview over the window (ROADMAP 2.6 task 3, 3.3b).
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

    // Debug menu: the lifecycle checks (spec §H), results in the log.

    @objc func simulateMemoryPressure(_ sender: Any?) {
        let ids = tabs?.handleMemoryPressure(.moderate) ?? []
        tabs?.handleMemoryPressure(.none)
        NSLog("Room: simulated memory pressure discarded \(ids.count) page(s)")
    }

    @objc func discardBackgroundPages(_ sender: Any?) {
        let ids = tabs?.discardBackgroundPages() ?? []
        NSLog("Room: discarded \(ids.count) background page(s)")
    }

    // MARK: Added with the full menu (2.8a)

    /// ⌘N: the window again after ⇧⌘W; a second window is Chapter 4.8 (multi-window).
    @objc func newRoomWindow(_ sender: Any?) {
        showWindow()
        NSApp.activate()
    }

    /// File ▸ Open File… (menu-only: ⌘O is Peek's, docs/shortcuts.md): a new Today tab on the file.
    @objc func openFileInTab(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabs?.openNewTab(url: url.absoluteString)
    }

    /// File ▸ Commands…: the palette in its actions mode (spec §C).
    @objc func showCommands(_ sender: Any?) { palette?.toggleCommands() }

    /// ⇧⌘R (spec §G: Reload ignoring the cache; rename stays Return / double-click).
    @objc func reloadIgnoringCache(_ sender: Any?) { tabs?.focusedPage?.reloadIgnoringCache() }

    /// ⌘.
    @objc func stopLoading(_ sender: Any?) { tabs?.focusedPage?.stop() }

    /// Tab ▸ Switch to Recent Tab (⌃Tab, tag 1) / Switch Back (⌃⇧Tab, tag −1): one step of the
    /// switcher without holding ⌃ (the keys themselves go to `TabSwitcher` first).
    @objc func switchToRecentTab(_ sender: Any?) {
        guard let sidebar, let item = sender as? NSMenuItem else { return }
        let state = TabSwitcherState(items: sidebar.recentEntries(limit: TabSwitcherMetrics.limit).map(\.id), backwards: item.tag < 0)
        guard let target = state.highlighted, target != sidebar.selectedEntryID else { return }
        sidebar.select(target)
    }

    /// Tab ▸ Rename… (spec §I.9): the selected row's inline field; the hidden sidebar's overlay is pinned for it.
    @objc func renameSelected(_ sender: Any?) {
        hiddenSidebar?.revealForSpaceForm()
        sidebar?.renameSelected()
    }

    @objc func duplicateSelected(_ sender: Any?) { sidebar?.duplicateSelected() }
    @objc func unloadSelected(_ sender: Any?) { sidebar?.unloadSelected() }
    @objc func resetSelected(_ sender: Any?) { sidebar?.resetSelected() }

    /// Tab ▸ Close Peek (Esc, ⌘W).
    @objc func closePeek(_ sender: Any?) { tabs?.closeShownPeek() }

    // MARK: Validation

    /// Every Room command validates here (ROADMAP 2.8 task 1); an action
    /// without a case is disabled, so a new item cannot be enabled by accident.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action, let validate = Self.validators[action] else {
            #if DEBUG
            NSLog("Room: no validation for \(menuItem.action.map(NSStringFromSelector) ?? "nil") (\(menuItem.title))")
            #endif
            return false
        }
        return validate(self, menuItem)
    }

    /// Whether a text field or text view is being edited in the key window (⌘← / ⌘→ stay the field's).
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private var hasPage: Bool { tabs?.focusedPage != nil }

    /// Every `.app` action of `MainMenuTable` and the Debug menu (the `menus` spike checks none is missing).
    static let validators: [Selector: (AppDelegate, NSMenuItem) -> Bool] = [
        // App, File
        #selector(showSettings(_:)): { app, _ in app.store != nil },
        #selector(checkForAppUpdates(_:)): { app, _ in app.optIns?.canCheckForUpdates ?? false },
        #selector(makeDefaultBrowser(_:)): { app, item in
            let isDefault = app.defaultBrowser.isDefault
            item.toolTip = isDefault ? "Room is your default browser" : nil
            return !isDefault && !app.defaultBrowser.isAsking
        },
        #selector(newPage(_:)): { app, _ in app.tabs != nil },
        // Help
        #selector(showRestoreSidebar(_:)): { app, _ in app.store != nil && app.backupScheduler != nil && app.restoreSheet == nil },
        #selector(newRoomWindow(_:)): { app, item in
            let shows = app.windowController?.window?.isVisible == true
            item.toolTip = shows ? "A second window comes in Chapter 4.8" : nil
            return !shows && app.store != nil
        },
        #selector(newSpace(_:)): { app, _ in app.sidebar != nil },
        #selector(openLocation(_:)): { app, _ in app.tabs != nil },
        #selector(openFileInTab(_:)): { app, _ in app.tabs?.profile != nil },
        #selector(showCommands(_:)): { app, _ in app.palette != nil },
        #selector(closeTab(_:)): { app, _ in app.tabs?.shownPeek != nil || app.sidebar?.canCloseCommandTargets == true },
        #selector(reopenClosedTab(_:)): { app, _ in app.sidebar?.canReopenClosedTab == true },
        #selector(printPage(_:)): { app, _ in app.hasPage },
        // Edit
        #selector(copyPageURL(_:)): { app, _ in app.sidebar?.selectedHasURL == true },
        #selector(showFindBar(_:)): { app, _ in app.hasPage },
        #selector(findNext(_:)): { app, _ in app.hasPage },
        // View
        #selector(hideOrShowSidebar(_:)): { app, item in
            // Enabled whenever the window exists and no page is in element fullscreen (ROADMAP 2.7b).
            item.title = app.windowController?.isSidebarOpen == false ? "Show Sidebar" : "Hide Sidebar"
            return app.windowController.map { !$0.rootView.isPageFullscreen } ?? false
        },
        #selector(keepSidebarOpen(_:)): { app, item in
            item.state = app.windowController?.reveal.isPinned == true ? .on : .off
            return app.windowController.map { !$0.rootView.isPageFullscreen } ?? false
        },
        #selector(toggleToolbar(_:)): { app, item in
            item.state = app.windowController?.showsToolbar == true ? .on : .off
            return app.windowController != nil
        },
        #selector(reloadPage(_:)): { app, _ in app.hasPage },
        #selector(reloadIgnoringCache(_:)): { app, _ in app.hasPage },
        #selector(stopLoading(_:)): { app, _ in app.tabs?.focusedPage?.isLoading == true },
        #selector(zoomPage(_:)): { app, item in
            guard let page = app.tabs?.focusedPage else { return false }
            switch item.tag {
            case 1: return page.zoomFactor < ZoomRules.steps.last! - 0.001
            case -1: return page.zoomFactor > ZoomRules.steps.first! + 0.001
            default: return !ZoomRules.isDefault(page.zoomFactor)
            }
        },
        #selector(toggleDevTools(_:)): { app, item in
            item.title = app.pageHost?.isDevToolsOpen == true ? "Close Developer Tools" : "Developer Tools"
            return app.tabs?.current != nil
        },
        #selector(showJavaScriptConsole(_:)): { app, _ in app.hasPage },
        #selector(inspectElements(_:)): { app, _ in app.hasPage },
        // History (tag 2: the ⌘← / ⌘→ aliases, outside text fields)
        #selector(goBack(_:)): { app, item in
            (item.tag != 2 || !app.isEditingText) && app.tabs?.focusedPage?.canGoBack == true
        },
        #selector(goForward(_:)): { app, item in
            (item.tag != 2 || !app.isEditingText) && app.tabs?.focusedPage?.canGoForward == true
        },
        #selector(showHistory(_:)): { app, _ in app.library != nil },
        #selector(toggleLibrary(_:)): { app, item in
            item.title = app.isLibraryShown ? "Hide Library" : "Show Library"
            return app.library != nil
        },
        // Tab
        #selector(selectAdjacentTab(_:)): { app, _ in app.sidebar?.selectedEntryID != nil },
        #selector(switchToRecentTab(_:)): { app, _ in (app.sidebar?.recentEntries(limit: 2).count ?? 0) > 1 },
        #selector(selectTabByNumber(_:)): { app, item in app.sidebar?.canSelectTab(digit: item.tag) == true },
        #selector(togglePin(_:)): { app, item in
            item.title = app.sidebar?.pinCommandTitle ?? "Pin Tab"
            return app.sidebar?.pinCommandTitle != nil
        },
        #selector(toggleEssentials(_:)): { app, item in
            item.title = app.sidebar?.essentialsCommandTitle ?? "Add to Essentials"
            return app.sidebar?.essentialsCommandTitle != nil
        },
        #selector(toggleMute(_:)): { app, item in
            let muted = app.sidebar?.selectedEntryID.flatMap { app.tabs?.pageState(for: $0).isMuted } ?? false
            item.title = muted ? CommandName.unmuteTab : CommandName.muteTab
            return app.sidebar?.selectedHasPage == true
        },
        #selector(renameSelected(_:)): { app, _ in app.sidebar?.canRenameSelected == true },
        #selector(duplicateSelected(_:)): { app, _ in app.sidebar?.selectedHasURL == true },
        #selector(unloadSelected(_:)): { app, _ in app.sidebar?.selectedHasPage == true },
        #selector(resetSelected(_:)): { app, _ in app.sidebar?.canResetSelected == true },
        #selector(clearTodayTabs(_:)): { app, _ in app.sidebar?.canClearToday == true },
        #selector(newSplitPane(_:)): { app, _ in app.sidebar?.selectedEntryID != nil },
        #selector(removeSplitPane(_:)): { app, _ in app.sidebar?.selectedSplit != nil },
        #selector(unsplit(_:)): { app, _ in app.sidebar?.selectedSplit != nil },
        #selector(setSplitLayout(_:)): { app, item in
            let split = app.sidebar?.selectedSplit
            item.state = split.map { $0.layout == AppDelegate.splitLayout(tag: item.tag) } == true ? .on : .off
            // Outside a split it splits the selected entry with the next one (Zen).
            return app.sidebar?.selectedEntryID != nil
        },
        #selector(focusSplitPane(_:)): { app, item in (app.sidebar?.selectedSplit?.members.count ?? 0) >= item.tag },
        #selector(focusAdjacentPane(_:)): { app, _ in app.sidebar?.selectedSplit != nil },
        #selector(expandPeek(_:)): { app, _ in app.tabs?.shownPeek != nil },
        #selector(splitPeek(_:)): { app, _ in app.tabs?.shownPeek != nil },
        #selector(closePeek(_:)): { app, _ in app.tabs?.shownPeek != nil },
        // Spaces
        #selector(selectAdjacentSpace(_:)): { app, _ in (app.store?.sidebar.spaces.count ?? 0) > 1 },
        #selector(selectSpaceByNumber(_:)): { app, item in
            guard let spaces = app.store?.sidebar.spaces else { return false }
            let index = item.tag == 0 ? 9 : item.tag - 1
            if spaces.indices.contains(index) { item.title = spaces[index].name }
            return spaces.indices.contains(index)
        },
        // Window
        #selector(showDownloads(_:)): { app, _ in app.downloads != nil },
        // Debug
        #selector(simulateMemoryPressure(_:)): { app, _ in app.tabs != nil },
        #selector(discardBackgroundPages(_:)): { app, _ in app.tabs != nil },
        // The pane header's layout menu.
        #selector(paneLayoutChosen(_:)): { _, _ in true },
    ]
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

// MARK: - Engine events

extension AppDelegate: EngineApplicationDelegate {
    /// Chromium's memory pressure (RoomCore): the window's discard policy
    /// decides what goes (spec §H; RoomCore discards no Room page itself).
    func engineApplication(_ application: any EngineApplication, didChangeMemoryPressure level: MemoryPressureLevel) {
        NSLog("Room: engine memory pressure \(level)")
        tabs?.handleMemoryPressure(level)
    }
}
