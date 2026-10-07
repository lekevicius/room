#if DEBUG
import AppKit
import Integration
import Model
import Omnibox
import Palette
import Sidebar
import UIKitCore

/// Phase 2.8b: `appintegration2` (`scripts/app-integration.sh --session 2.8b`,
/// which serves `research/spikes/phase-2.7/` on 127.0.0.1:8770 and the dev
/// update feed and crash endpoint of `research/spikes/phase-2.8/` on :8771,
/// launches Room with a link, and answers `capture:` and `open_url:`
/// requests). Checks, each selectable with `-RoomSpikeOnly`:
/// - `coldurl`: the link Room was launched with: queued before the store and
///   engine were up, then opened; event → page requested → page loaded.
/// - `optins`: at launch neither Sparkle nor Sentry exists; then each opt-in on
///   and off against the local endpoints, a check the user asks for (Sparkle's
///   window captured), and the feed server's log read by the script.
/// - `firstrun`: the card docked left and right and in the hidden sidebar's
///   overlay; the engine choice reaching the palette; Done; Show Welcome Card.
/// - `settings`: Settings ▸ General (the default browser) and ▸ Privacy, the App menu open.
/// - `runningurl`: a link from `open`, from AppleScript's `open location`, and from
///   another process's `NSWorkspace.open(_:withApplicationAt:)`, each timed.
/// - `closedwindow`: a link after ⇧⌘W brings the window back with the tab.
/// Captures are named `phase-2.8b-<name>-<appearance>`.
extension SpikeRunner.Context {
    private var app2: AppDelegate? { AppDelegate.current }

    func appIntegration2() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        await activate()
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        func runs(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
        if runs("coldurl") { await coldURLCheck() }
        if runs("optins") { optInsAtLaunch() }
        if runs("firstrun") { await firstRunCheck() }
        if runs("settings") { await settings2Check() }
        if runs("runningurl") { await runningURLCheck() }
        if runs("closedwindow") { await closedWindowCheck() }
        if runs("optins") { await optInsToggleCheck() }
    }

    private func capture2(_ name: String, windowNumber: Int? = nil) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures28b") else { return }
        let full = "phase-2.8b-\(name)-\(appearanceSuffix)"
        SpikeRunner.record("capture", windowNumber.map { "\(full)@\($0)" } ?? full)
        _ = await waitUntil(20) { FileManager.default.fileExists(atPath: Self.ackPath2(full)) }
    }

    private static func ackPath2(_ name: String) -> String {
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        return output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + name).path
    }

    private static func ms(_ from: Date, _ to: Date) -> String { String(format: "%.1f ms", to.timeIntervalSince(from) * 1000) }

    /// The page of the selected entry finished loading `url` (or `timeout` passed): when.
    private func loaded(_ url: URL, timeout: Double = 15) async -> Date? {
        let done = await waitUntil(timeout) {
            guard let page = app2?.tabs?.current, let shown = page.url else { return false }
            return shown.absoluteString == url.absoluteString && !page.isLoading
        }
        return done ? Date() : nil
    }

    // MARK: Links (ROADMAP 2.8 task 3)

    private func coldURLCheck() async {
        guard let app = app2 else { return }
        let launched = Self.processStartDate()
        let log = app.debugIncomingLog
        guard let event = log.first(where: { $0.event != "requested" }) else {
            return SpikeRunner.record("cold_url", "no link arrived with the launch")
        }
        guard let requested = log.first(where: { $0.event == "requested" && $0.url == event.url }) else {
            return SpikeRunner.record("cold_url", "\(event.url) \(event.event), never opened")
        }
        let page = await loaded(event.url)
        SpikeRunner.record("cold_url", "\(event.url) arrived \(event.event) (inbox closed: \(event.event == "queued")) "
            + "at launch+\(Self.ms(launched, event.at)); requested at launch+\(Self.ms(launched, requested.at))")
        SpikeRunner.record("cold_url_event_to_requested", Self.ms(event.at, requested.at))
        SpikeRunner.record("cold_url_requested_to_loaded", page.map { Self.ms(requested.at, $0) } ?? "not loaded")
        let entry = app.sidebar?.selectedEntryID.flatMap { app.store?.sidebar.entry($0) }
        SpikeRunner.record("cold_url_entry", "kind=\(entry.map { "\($0.kind)" } ?? "nil") selected=\(entry?.liveURL ?? "nil")")
    }

    /// Asks the script to hand Room `url` by `method` and waits for the tab; returns the timings.
    private func openFromOutside(_ method: String, _ url: URL) async -> (sent: Date?, event: Date?, requested: Date?, loaded: Date?) {
        guard let app = app2 else { return (nil, nil, nil, nil) }
        let name = "open-\(method)-\(url.query ?? "")"
        SpikeRunner.record("open_url", "\(name) \(method) \(url.absoluteString)")
        let ack = Self.ackPath2(name)
        _ = await waitUntil(20) { FileManager.default.fileExists(atPath: ack) }
        let sent = (try? String(contentsOfFile: ack, encoding: .utf8)).flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .map { Date(timeIntervalSince1970: $0) }
        _ = await waitUntil(15) { app.debugIncomingLog.contains { $0.event == "requested" && $0.url == url } }
        let event = app.debugIncomingLog.first { $0.event != "requested" && $0.url == url }?.at
        let requested = app.debugIncomingLog.first { $0.event == "requested" && $0.url == url }?.at
        let page = requested == nil ? nil : await loaded(url)
        return (sent, event, requested, page)
    }

    private func runningURLCheck() async {
        for method in ["open", "applescript", "workspace"] {
            let url = URL(string: Self.site28 + "site.html?running-\(method)")!
            let t = await openFromOutside(method, url)
            func span(_ a: Date?, _ b: Date?) -> String { (a != nil && b != nil) ? Self.ms(a!, b!) : "—" }
            SpikeRunner.record("running_url_\(method)", "sent→event \(span(t.sent, t.event)), event→requested \(span(t.event, t.requested)), "
                + "requested→loaded \(span(t.requested, t.loaded)); selected=\(app2?.tabs?.current?.url?.absoluteString ?? "nil")")
        }
        await capture2("running-url")
    }

    private func closedWindowCheck() async {
        window.performClose(nil)
        _ = await waitUntil(2) { !window.isVisible }
        SpikeRunner.record("closed_window", "visible after ⇧⌘W: \(window.isVisible)")
        let url = URL(string: Self.site28 + "site.html?after-close")!
        let t = await openFromOutside("open", url)
        // Since 4.8a the closed window's session is torn down and the link reopens the kept window row as a new
        // window: read the app's window now, not the closed one.
        let shown = app2?.windowController?.window ?? window
        SpikeRunner.record("closed_window_link", "window visible=\(shown.isVisible) main=\(shown.isMainWindow) new_window=\(shown !== window) "
            + "tab=\(app2?.tabs?.current?.url?.absoluteString ?? "nil") event→requested "
            + "\(t.event != nil && t.requested != nil ? Self.ms(t.event!, t.requested!) : "—")")
        await activate()
    }

    // MARK: First run (ROADMAP 2.8 task 4)

    private func cardState() -> String {
        guard let app = app2, let card = app.firstRunCard, card.superview != nil, let sidebar = app.sidebar else { return "absent" }
        let inWindow = card.convert(card.bounds, to: nil)
        let footer = sidebar.downloadsButton.convert(sidebar.downloadsButton.bounds, to: nil)
        return "shown frame=\(NSStringFromRect(card.frame)) in window=\(NSStringFromRect(inWindow)) above footer=\(inWindow.minY >= footer.maxY)"
    }

    private func firstRunCheck() async {
        guard let app = app2, let store = app.store, let firstRun = app.firstRun else { return }
        let root = controller.rootView
        SpikeRunner.record("first_run_launch", "done=\(store.settings.settings.firstRunDone) card=\(cardState())")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))
        await capture2("firstrun-left")
        store.settings.update { $0.sidebarSide = .right }
        _ = await waitUntil(2) { root.sidebarEdge == .right }
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("first_run_right", cardState())
        await capture2("firstrun-right")
        store.settings.update { $0.sidebarSide = .left }
        _ = await waitUntil(2) { root.sidebarEdge == .left }
        // Hidden sidebar: the card is in the overlay (pinned open, as Show Welcome Card does).
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        app.hiddenSidebar?.revealForSpaceForm()
        let shown = await waitUntil(2) { controller.reveal.isShown && !root.isOverlayAnimating }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("first_run_overlay", "overlay shown=\(shown) card=\(cardState()) in overlay="
            + "\(app.firstRunCard.map { $0.isDescendant(of: root.overlayView) } ?? false)")
        await capture2("firstrun-overlay")
        if controller.reveal.isPinned { controller.reveal.togglePin() }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))

        // The engine choice is the field the palette reads.
        let before = app.palette?.searchEngine().id ?? "nil"
        firstRun.searchEngine = "duckduckgo"
        SpikeRunner.record("first_run_engine", "palette before=\(before) after choice=\(app.palette?.searchEngine().id ?? "nil") "
            + "stored=\(store.settings.settings.searchEngine)")
        firstRun.searchEngine = "google"

        // Done: the card goes, the list takes the space back, the store remembers.
        let start = ContinuousClock.now
        firstRun.finish()
        let gone = await waitUntil(2) { app.firstRunCard == nil && app.sidebar?.bodyView.accessoryView == nil }
        SpikeRunner.record("first_run_done", "card gone=\(gone) in \(String(format: "%.0f", ms(since: start))) ms; stored done=\(store.settings.settings.firstRunDone)")
        // Settings ▸ General ▸ Show Welcome Card.
        app.showWelcomeCard()
        let back = await waitUntil(2) { app.firstRunCard?.superview != nil }
        SpikeRunner.record("first_run_show_again", "card back=\(back) done=\(store.settings.settings.firstRunDone) \(cardState())")
        firstRun.finish()
        _ = await waitUntil(2) { app.firstRunCard == nil }
    }

    // MARK: Settings (2.8b sections) and the App menu

    private func settings2Check() async {
        guard let app = app2 else { return }
        SpikeRunner.record("default_browser", "isDefault=\(app.defaultBrowser.isDefault) http handler="
            + "\(DefaultBrowser.handler(for: "http")?.lastPathComponent ?? "nil") https handler=\(DefaultBrowser.handler(for: "https")?.lastPathComponent ?? "nil")")
        app.showSettings(nil)
        try? await Task.sleep(for: .milliseconds(500))
        guard let settings = app.debugSettingsWindow, let settingsWindow = settings.window else {
            return SpikeRunner.record("error", "no Settings window")
        }
        for section in [SettingsWindowController.Section.general, .privacy] {
            settings.select(section)
            try? await Task.sleep(for: .milliseconds(400))
            SpikeRunner.record("settings_\(section.rawValue)", "title=\(settingsWindow.title) size=\(NSStringFromSize(settingsWindow.frame.size))")
            await capture2("settings-\(section.rawValue)", windowNumber: settingsWindow.windowNumber)
        }
        settingsWindow.close()
        await activate()
        // The App menu with Check for Updates… and Set as Default Browser….
        if let menu = NSApp.mainMenu?.items.first?.submenu {
            menu.update()
            for title in ["Check for Updates…", "Set as Default Browser…"] {
                let item = menu.item(withTitle: title)
                SpikeRunner.record("app_menu_item", "\(title) enabled=\(item?.isEnabled ?? false) target=\(item?.target.map { "\(Swift.type(of: $0))" } ?? "nil") "
                    + "validated=\(item?.action.map { AppDelegate.validators[$0] != nil } ?? false)")
            }
            if UserDefaults.standard.bool(forKey: "RoomSpikeCaptures28b") {
                let driver = MenuCaptureDriver(menu: menu, name: "phase-2.8b-menu-app-\(appearanceSuffix)", ackPath: Self.ackPath2)
                let timer = Timer(timeInterval: 0.1, target: driver, selector: #selector(MenuCaptureDriver.tick(_:)), userInfo: nil, repeats: true)
                RunLoop.main.add(timer, forMode: .common)
                menu.popUp(positioning: nil, at: NSPoint(x: 80, y: 4), in: controller.rootView)
                timer.invalidate()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: Opt-ins (ROADMAP 2.8 task 5)

    /// Sparkle's window on screen (any visible window but Room's own).
    private func sparkleWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0 !== window && !($0 is NSPanel) && $0.title != "General" && $0.title != "Privacy" }
    }

    private func describe(_ shown: NSWindow) -> String {
        "\(Swift.type(of: shown)) \"\(shown.title)\" \(NSStringFromSize(shown.frame.size))"
    }

    private func optInsAtLaunch() {
        guard let app = app2, let optIns = app.optIns, let settings = app.store?.settings.settings else {
            return SpikeRunner.record("opt_ins_launch", "no services (no store)")
        }
        SpikeRunner.record("opt_ins_launch", "crashReports=\(settings.crashReports) automaticUpdateChecks=\(settings.automaticUpdateChecks); "
            + "updater created=\(optIns.updater != nil) crash reporter created=\(optIns.crashReporter != nil) reporting=\(optIns.isReportingCrashes)")
    }

    private func optInsToggleCheck() async {
        guard let app = app2, let store = app.store, let optIns = app.optIns else { return }
        SpikeRunner.record("opt_ins_marker", String(format: "%.3f ", Date().timeIntervalSince1970) + "toggles start")
        store.settings.update { $0.automaticUpdateChecks = true }
        _ = await waitUntil(2) { optIns.updater != nil }
        SpikeRunner.record("opt_in_updates_on", "updater created=\(optIns.updater != nil) automatic=\(optIns.updater?.automaticallyChecks ?? false)")
        // With no earlier check in its defaults Sparkle checks at once; its window shows what it found.
        let scheduled = await waitUntil(5) { sparkleWindow() != nil }
        SpikeRunner.record("update_scheduled_window", scheduled ? describe(sparkleWindow()!) : "none in 5 s")
        if let shown = sparkleWindow() {
            try? await Task.sleep(for: .milliseconds(600))
            await capture2("sparkle-scheduled", windowNumber: shown.windowNumber)
            shown.close()
        }
        store.settings.update { $0.automaticUpdateChecks = false }
        _ = await waitUntil(2) { optIns.updater?.automaticallyChecks == false }
        SpikeRunner.record("opt_in_updates_off", "automatic=\(optIns.updater?.automaticallyChecks ?? false)")
        _ = await waitUntil(5) { optIns.canCheckForUpdates }
        SpikeRunner.record("opt_ins_marker", String(format: "%.3f ", Date().timeIntervalSince1970) + "manual check")
        // A check the user asks for: Sparkle fetches the dev feed and shows its window.
        SpikeRunner.record("update_check_can", "\(optIns.canCheckForUpdates)")
        app.checkForAppUpdates(nil)
        // The progress window ("Checking for updates…") comes first; the result replaces it.
        let appeared = await waitUntil(10) { sparkleWindow().map { $0.frame.height > 200 } ?? false }
        SpikeRunner.record("update_check_window", appeared ? describe(sparkleWindow()!) : "none in 10 s")
        if let shown = sparkleWindow() {
            try? await Task.sleep(for: .milliseconds(600))
            await capture2("sparkle-check", windowNumber: shown.windowNumber)
            shown.close()
        }
        try? await Task.sleep(for: .seconds(1))
        SpikeRunner.record("opt_ins_marker", String(format: "%.3f ", Date().timeIntervalSince1970) + "crash reports")
        store.settings.update { $0.crashReports = true }
        _ = await waitUntil(2) { optIns.isReportingCrashes || optIns.crashReportsUnavailable }
        SpikeRunner.record("opt_in_crash_on", "dsn set=\(!optIns.dsn.isEmpty) reporting=\(optIns.isReportingCrashes)")
        try? await Task.sleep(for: .seconds(2))
        store.settings.update { $0.crashReports = false }
        _ = await waitUntil(2) { !optIns.isReportingCrashes }
        SpikeRunner.record("opt_in_crash_off", "reporting=\(optIns.isReportingCrashes)")
        SpikeRunner.record("opt_ins_marker", String(format: "%.3f ", Date().timeIntervalSince1970) + "toggles end")
        await activate()
    }
}

// MARK: The no-request check (ROADMAP 2.8 exit criterion)

/// `netcheck` (`scripts/netlog-check.sh`, which records the engine's net-log, a
/// logging endpoint and `nettop` around it): a first launch with every
/// opt-in declined (the first-run card left as it is and finished), idle
/// (8 s, or `-RoomNetcheckIdleSeconds`);
/// a short browse on the local test site (two hosts, a same-site
/// navigation, a reload); idle; quit. Each phase is stamped in seconds
/// since 1970 so the script can sort the requests into launch, browse,
/// idle and quit.
extension SpikeRunner.Context {
    private func stamp(_ phase: String) {
        SpikeRunner.record("phase", String(format: "%@ %.3f", phase, Date().timeIntervalSince1970))
    }

    func netCheck() async {
        guard let app = AppDelegate.current, let tabs = app.tabs, let settings = app.store?.settings.settings else { return }
        SpikeRunner.record("phase", String(format: "launch %.3f", Self.processStartDate().timeIntervalSince1970))
        SpikeRunner.record("opt_ins", "crashReports=\(settings.crashReports) automaticUpdateChecks=\(settings.automaticUpdateChecks) "
            + "searchSuggestions=\(settings.searchSuggestions) first-run card shown=\(app.firstRunCard != nil) "
            + "updater created=\(app.optIns?.updater != nil) crash reporter created=\(app.optIns?.crashReporter != nil)")
        stamp("launch_idle")
        // 8 s by default (2.8b); `-RoomNetcheckIdleSeconds 600` for 3.1b's ten-minute idle on RoomCore.
        let idle = UserDefaults.standard.double(forKey: "RoomNetcheckIdleSeconds")
        try? await Task.sleep(for: .seconds(idle > 0 ? idle : 8))
        // Declined: nothing switched on, Done.
        app.firstRun?.finish()
        stamp("browse")
        for url in ["http://127.0.0.1:8770/site.html", "http://localhost:8770/other.html"] {
            tabs.openNewTab(url: url)
            if let page = tabs.current { await waitLoaded(page) }
            try? await Task.sleep(for: .seconds(2))
        }
        tabs.navigateSelected(to: "http://localhost:8770/offsite.html")
        if let page = tabs.current { await waitLoaded(page) }
        try? await Task.sleep(for: .seconds(2))
        tabs.current?.reload()
        if let page = tabs.current { await waitLoaded(page) }
        stamp("browse_idle")
        try? await Task.sleep(for: .seconds(8))
        // 3.5: `-RoomSuggestionsOff YES` types three queries in the palette with the switch off
        // (on RoomCore Chrome's omnibox answers them): the net-log must show nothing for the typing.
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff"), let palette = app.palette {
            app.store?.settings.update { $0.searchSuggestions = false }
            SpikeRunner.record("suggestions", "off; engine autocomplete=\(palette.usesEngineAutocomplete)")
            stamp("typing")
            for query in ["swift concurrency", "weather in vilnius", "room browser"] {
                palette.toggleNew()
                for character in query {
                    type(String(character))
                    try? await Task.sleep(for: .milliseconds(60))
                }
                try? await Task.sleep(for: .milliseconds(1_200))
                SpikeRunner.record("typed", "\(query): providers=\(palette.lastEngineProviders.map(Self.describe) ?? "none") "
                    + "suggest rows=\(palette.result.matches.filter { $0.provider == .suggest }.count)")
                palette.dismiss()
                try? await Task.sleep(for: .milliseconds(200))
            }
            stamp("typing_idle")
            try? await Task.sleep(for: .seconds(4))
        }
        SpikeRunner.record("opt_ins_end", "updater created=\(app.optIns?.updater != nil) crash reporter created=\(app.optIns?.crashReporter != nil)")
        stamp("quit")
    }
}
#endif
