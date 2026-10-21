#if DEBUG
import AppKit
import Chrome
import Engine
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 5.6b spike `details2` (`scripts/details2-check.sh`) on a throwaway
/// state, the pages on the test servers (:8765, :8766). Sections
/// (`-RoomSpikeOnly` picks):
/// - `band` (B-32): the sidebar hidden, a double-click and a press-drag at
///   the card's top go to the page; the window keeps its frame;
/// - `commands` (B-11): ⌘S with the page focused: a page that handles it
///   (an editor saving) keeps it, one that does not hands it to the menu;
/// - `hint` (spec §E): the "Sidebar hidden" toast on the first splitter snap
///   only (stored in the state's settings), with the key the Shortcuts table
///   has; the hidden sidebar's toasts (a background tab, a new space, a
///   download);
/// - `dock`: the Dock menu's items performed through NSApp's delegate, the
///   windows listed in the Window menu, Zoom and the tiling items, Services;
/// - `incognito` (B-98): two incognito windows of one profile, one twin; one
///   closed, the other goes on; the last closed ends the twin;
/// - `thumbs` (B-119): the cost of a page snapshot per tab, for the ⌃Tab switcher.
/// `-RoomSpikeCaptureDirectory` keeps in-process captures named `phase-5.6b-<name>-<appearance>.png`.
/// A capture's result, read while it may still be running (B-119's background pages).
@MainActor private final class OpenedMenu {
    var titles: [String] = []
}

@MainActor private final class CaptureBox {
    var image: NSImage?
    var done = false
}

extension SpikeRunner.Context {
    func details2Checks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: details2Appearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = 280
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(details2Appearance) app=\(Bundle.main.bundlePath)")
        if runs("band") { await details2Band() }
        if runs("commands") { await details2CommandS() }
        if runs("hint") { await details2Hint() }
        if runs("dock") { await details2Dock() }
        if runs("incognito") { await details2Incognito() }
        if runs("thumbs") { await details2Thumbs() }
        controller.isSidebarOpen = true
    }

    private var details2Appearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let details2Base = "http://127.0.0.1:8766/"

    func details2Capture(_ name: String, of target: NSWindow? = nil) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let target = target ?? window
        target.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.6b-\(name)-\(details2Appearance).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(target, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: band (B-32)

    func details2Band() async {
        guard let page = await open(URL(string: Self.details2Base + "find.html?band")!) else { return SpikeRunner.record("error", "band: no page") }
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        _ = await js(page, "window.__dbl = 0; window.__downs = 0; window.__moves = 0; window.__ups = 0; window.__pressed = false; "
            + "addEventListener('dblclick', () => __dbl++); addEventListener('mousedown', () => { __downs++; __pressed = true }); "
            + "addEventListener('mousemove', () => { if (__pressed) __moves++ }); addEventListener('mouseup', () => { __ups++; __pressed = false }); 0")
        details2Capture("hidden-card-top")
        let root = controller.rootView
        let card = root.currentLayout.card
        // 10 pt under the card's top: inside the old 5 % band and the window's 52 pt titlebar.
        let top = CGPoint(x: card.midX, y: card.minY + 10)
        let hit = window.contentView?.superview?.hitTest(root.convert(top, to: nil)).map { String(describing: Swift.type(of: $0)) } ?? "nil"
        let frameBefore = window.frame
        post(.mouseMoved, at: top)
        post(.leftMouseDown, at: top, clickCount: 1)
        post(.leftMouseUp, at: top, clickCount: 1)
        post(.leftMouseDown, at: top, clickCount: 2)
        post(.leftMouseUp, at: top, clickCount: 2)
        try? await Task.sleep(for: .milliseconds(900))
        let frameAfterDouble = window.frame
        SpikeRunner.record("band_double_click", "hit=\(hit) page dblclick=\(await js(page, "__dbl")) downs=\(await js(page, "__downs")) "
            + "window zoomed=\(window.isZoomed) frame kept=\(frameAfterDouble == frameBefore) (\(NSStringFromRect(frameBefore)) → \(NSStringFromRect(frameAfterDouble)))")
        // A press at the top moved 40 pt: the page's (a text selection), not a window drag.
        if window.frame != frameBefore { window.setFrame(frameBefore, display: true) }
        _ = await js(page, "__downs = 0; __moves = 0; __ups = 0; 0")
        post(.leftMouseDown, at: top, clickCount: 1)
        for step in 1...8 { post(.leftMouseDragged, at: CGPoint(x: top.x + CGFloat(step * 5), y: top.y + CGFloat(step)), clickCount: 1) }
        post(.leftMouseUp, at: CGPoint(x: top.x + 40, y: top.y + 8), clickCount: 1)
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("band_press_drag", "page downs=\(await js(page, "__downs")) drag moves=\(await js(page, "__moves")) ups=\(await js(page, "__ups")) "
            + "window frame kept=\(window.frame == frameBefore)")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: commands (B-11: ⌘S page-first)

    func details2CommandS() async {
        guard let page = await open(URL(string: Self.details2Base + "find.html?commands")!) else { return SpikeRunner.record("error", "commands: no page") }
        controller.isSidebarOpen = true
        func pressCommandS() async {
            focusPage(page)
            try? await Task.sleep(for: .milliseconds(150))
            PageDriver.key(window, characters: "s", charactersIgnoringModifiers: "s", keyCode: 1, modifiers: [.command])
            try? await Task.sleep(for: .milliseconds(700))
        }
        // A web editor saving with ⌘S: the page handles it, the sidebar stays.
        _ = await js(page, "window.__saves = 0; window.__editor = e => { if (e.metaKey && e.key === 's') { e.preventDefault(); __saves++ } }; "
            + "addEventListener('keydown', __editor); 0")
        await pressCommandS()
        let editorSaves = await js(page, "__saves")
        let editorOpen = controller.isSidebarOpen
        // No handler: the page hands it back and the menu's Hide Sidebar runs.
        _ = await js(page, "removeEventListener('keydown', __editor); window.__seen = 0; addEventListener('keydown', e => { if (e.metaKey && e.key === 's') __seen++ }); 0")
        await pressCommandS()
        let seen = await js(page, "__seen")
        let hidden = !controller.isSidebarOpen
        await pressCommandS()
        SpikeRunner.record("command_s", "editor: page saves=\(editorSaves) sidebar stays=\(editorOpen); plain page: page saw=\(seen) sidebar hidden=\(hidden), "
            + "again docked=\(controller.isSidebarOpen)")
        controller.isSidebarOpen = true
    }

    // MARK: hint and the hidden sidebar's toasts (spec §E)

    func details2Hint() async {
        guard let app = AppDelegate.current, let session = app.windows.session(for: window), let toasts = session.toasts else {
            return SpikeRunner.record("error", "hint: no window session")
        }
        let settings = sidebar.store.settings
        let before = settings.settings.sidebarHiddenHintShown
        func snapClosed() async -> String {
            controller.isSidebarOpen = true
            try? await Task.sleep(for: .milliseconds(300))
            toasts.dismiss(id: toasts.currentToast?.id ?? "")
            try? await Task.sleep(for: .milliseconds(300))
            controller.debugSnapSidebarClosed()
            try? await Task.sleep(for: .milliseconds(400))
            let toast = toasts.currentToast
            return "hidden=\(!controller.isSidebarOpen) toast=\(toast.map { "\($0.id) \"\($0.message)\"" } ?? "none")"
        }
        let first = await snapClosed()
        details2Capture("hint")
        let second = await snapClosed()
        SpikeRunner.record("hint_once", "stored before=\(before) first snap: \(first); second snap: \(second); stored after=\(settings.settings.sidebarHiddenHintShown)")
        // The key follows the Shortcuts table (a remap, then no key).
        settings.update { $0.sidebarHiddenHintShown = false; $0.shortcutOverrides["hideOrShowSidebar:"] = "⌥⌘B" }
        let remapped = await snapClosed()
        settings.update { $0.sidebarHiddenHintShown = false; $0.shortcutOverrides["hideOrShowSidebar:"] = "" }
        let noKey = await snapClosed()
        settings.update { $0.sidebarHiddenHintShown = true; $0.shortcutOverrides["hideOrShowSidebar:"] = nil }
        SpikeRunner.record("hint_key", "remapped: \(remapped); no key: \(noKey)")
        // ⌘S (the menu) hides without the hint.
        settings.update { $0.sidebarHiddenHintShown = false }
        controller.isSidebarOpen = true
        toasts.dismiss(id: toasts.currentToast?.id ?? "")
        try? await Task.sleep(for: .milliseconds(300))
        app.hideOrShowSidebar(nil)
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("hint_menu_hide", "hidden=\(!controller.isSidebarOpen) toast=\(toasts.currentToast?.id ?? "none") stored=\(settings.settings.sidebarHiddenHintShown)")
        settings.update { $0.sidebarHiddenHintShown = true }

        // The hidden sidebar's toasts: a background tab, a new space, a download.
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        toasts.dismiss(id: toasts.currentToast?.id ?? "")
        try? await Task.sleep(for: .milliseconds(300))
        _ = tabs.openBackgroundTab(url: Self.details2Base + "find.html?background")
        try? await Task.sleep(for: .milliseconds(300))
        let background = toasts.currentToast.map { "\($0.id) \"\($0.message)\"" } ?? "none"
        details2Capture("hidden-background-toast")
        toasts.dismiss(id: toasts.currentToast?.id ?? "")
        try? await Task.sleep(for: .milliseconds(300))
        app.showSpaceWindow(nil, from: sidebar)
        _ = await waitUntil(3) { app.spaceWindow?.window?.isVisible == true }
        app.spaceWindow?.model.name = "Hidden Toast"
        _ = app.spaceWindow?.commit()
        try? await Task.sleep(for: .milliseconds(400))
        let space = toasts.currentToast.map { "\($0.id) \"\($0.message)\"" } ?? "none"
        app.spaceWindow?.close()
        if let first = store.spaces.first { sidebar.showSpace(first.id) }
        toasts.dismiss(id: toasts.currentToast?.id ?? "")
        try? await Task.sleep(for: .milliseconds(300))
        let folder = FileManager.default.temporaryDirectory.appending(path: "room-5.6b-downloads-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        sidebar.store.settings.update { $0.downloadDirectory = folder.path; $0.askWhereToSave = false }
        if tabs.current == nil { _ = await open(URL(string: Self.details2Base + "find.html?download")!) }
        _ = tabs.current.map { page in page.load(URL(string: Self.details2Base + "download?size=1")!) }
        _ = await waitUntil(15) { toasts.currentToast?.id == "download-complete" }
        let download = toasts.currentToast.map { "\($0.id) \"\($0.message)\" action=\($0.action?.title ?? "none")" } ?? "none"
        try? await Task.sleep(for: .milliseconds(500))
        details2Capture("hidden-download-toast")
        SpikeRunner.record("hidden_toasts", "background tab: \(background); new space: \(space); download: \(download)")
        try? FileManager.default.removeItem(at: folder)
        controller.isSidebarOpen = true
    }

    // MARK: dock: the Dock menu, the Window menu, Services

    func details2Dock() async {
        guard let app = AppDelegate.current else { return }
        let windowsBefore = app.windows.all.count
        guard let menu = app.applicationDockMenu(NSApp) else { return SpikeRunner.record("dock_menu", "none") }
        let items = menu.items.map { $0.isSeparatorItem ? "—" : "\($0.title) [\($0.action.map(NSStringFromSelector) ?? "nil")]" }
        SpikeRunner.record("dock_menu", "items=\(items.joined(separator: ", ")) delegate=\(NSApp.delegate === app)")
        func perform(_ title: String) -> Bool {
            guard let item = menu.items.first(where: { $0.title == title }), let action = item.action else { return false }
            return NSApp.sendAction(action, to: item.target, from: item)
        }
        let newWindow = perform("New Window")
        _ = await waitUntil(3) { app.windows.all.count > windowsBefore }
        let afterNew = app.windows.all.count
        let newIncognito = perform("New Incognito Window")
        _ = await waitUntil(5) { app.windows.all.contains { $0.isIncognito } }
        let afterIncognito = app.windows.all.count
        try? await Task.sleep(for: .milliseconds(400))
        // The Dock lists the app's windows from the Window menu (AppKit): every Room window there.
        let windowsMenu = NSApp.windowsMenu
        windowsMenu?.update()
        let listed = app.windows.all.map { session -> String in
            let window = session.window
            let inMenu = windowsMenu?.items.contains { $0.target === window } ?? false
            return "\"\(window?.title ?? "?")\" listed=\(inMenu) excluded=\(window?.isExcludedFromWindowsMenu ?? true)"
        }
        SpikeRunner.record("dock_actions", "New Window: sent=\(newWindow) windows \(windowsBefore)→\(afterNew); New Incognito Window: sent=\(newIncognito) "
            + "windows→\(afterIncognito) incognito=\(app.windows.all.contains { $0.isIncognito }); listed: \(listed.joined(separator: "; "))")
        // Back to the spike's window alone.
        // (`close()`: a window opened with the sidebar hidden has no close button to press.)
        for session in app.windows.all where session.window !== window { session.window?.close() }
        let alone = await waitUntil(5) { app.windows.all.count == 1 }
        SpikeRunner.record("dock_cleanup", "windows=\(app.windows.all.count) alone=\(alone) left=\(app.windows.all.map { "\($0.window?.title ?? "?") incognito=\($0.isIncognito) visible=\($0.window?.isVisible ?? false)" })")
        await activate()
        try? await Task.sleep(for: .milliseconds(400))

        // The Window menu: its items (AppKit adds the tiling ones), Zoom both ways.
        windowsMenu?.update()
        // AppKit adds its tiling items as the menu opens: open it for a moment (a timer in the tracking loop reads it and closes it).
        let opened = OpenedMenu()
        if let windowsMenu {
            let weakMenu = MainActorWeak(windowsMenu), box = MainActorWeak(opened)
            let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
                MainActor.assumeIsolated {
                    guard let menu = weakMenu.value else { return }
                    box.value?.titles = menu.items.filter { !$0.isSeparatorItem }
                        .map { $0.title + ($0.submenu.map { " ▸ \($0.items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: "/"))" } ?? "") }
                    menu.cancelTracking()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            windowsMenu.popUp(positioning: nil, at: NSPoint(x: 400, y: 400), in: window.contentView)
        }
        SpikeRunner.record("window_menu_opened", opened.titles.joined(separator: ", "))
        let titles = (windowsMenu?.items ?? []).filter { !$0.isSeparatorItem && !($0.target is NSWindow) }
            .map { $0.title + ($0.submenu.map { " ▸ \($0.items.filter { !$0.isSeparatorItem }.map(\.title).joined(separator: "/"))" } ?? "") }
        SpikeRunner.record("window_menu", titles.joined(separator: ", "))
        let frame = window.frame
        let zoomItem = windowsMenu?.items.first { $0.action == #selector(NSWindow.performZoom(_:)) }
        let zoomEnabled = zoomItem.map { item in NSApp.target(forAction: item.action!, to: item.target, from: item) != nil } ?? false
        if let zoomItem, let action = zoomItem.action { NSApp.sendAction(action, to: zoomItem.target, from: zoomItem) }
        _ = await waitUntil(3) { self.window.frame != frame }
        try? await Task.sleep(for: .milliseconds(500))
        let zoomed = window.frame
        if let zoomItem, let action = zoomItem.action { NSApp.sendAction(action, to: zoomItem.target, from: zoomItem) }
        _ = await waitUntil(3) { self.window.frame == frame }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("window_zoom", "enabled=\(zoomEnabled) \(NSStringFromRect(frame)) → \(NSStringFromRect(zoomed)) → back=\(window.frame == frame)")

        // With the sidebar hidden (its traffic lights hidden too, B-114): Zoom, Minimize and Close Window still act.
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(500))
        let hiddenButtons = window.standardWindowButton(.closeButton)?.isHidden == true
        if let zoomItem, let action = zoomItem.action { NSApp.sendAction(action, to: zoomItem.target, from: zoomItem) }
        let hiddenZoomed = await waitUntil(3) { self.window.frame != frame }
        if let zoomItem, let action = zoomItem.action { NSApp.sendAction(action, to: zoomItem.target, from: zoomItem) }
        _ = await waitUntil(3) { self.window.frame == frame }
        window.performMiniaturize(nil)
        let minimized = await waitUntil(3) { self.window.isMiniaturized }
        window.deminiaturize(nil)
        _ = await waitUntil(3) { !self.window.isMiniaturized }
        try? await Task.sleep(for: .milliseconds(500))
        app.newRoomWindow(nil)
        _ = await waitUntil(3) { app.windows.all.count == 2 }
        let extra = app.windows.all.first { $0.window !== window }
        extra?.controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        extra?.window?.performClose(nil)
        let closed = await waitUntil(3) { app.windows.all.count == 1 }
        controller.isSidebarOpen = true
        // Minimize with the sidebar docked, for comparison.
        window.performMiniaturize(nil)
        let dockedMinimized = await waitUntil(3) { self.window.isMiniaturized }
        window.deminiaturize(nil)
        _ = await waitUntil(3) { !self.window.isMiniaturized }
        SpikeRunner.record("window_minimize_docked", "acts=\(dockedMinimized)")
        SpikeRunner.record("window_hidden_sidebar", "buttons hidden=\(hiddenButtons) Zoom acts=\(hiddenZoomed) Minimize acts=\(minimized) Close Window acts=\(closed)")
        if !closed { extra?.window?.close() }
        await activate()

        // Services: the menu is the app's; a page's selection offers text to it.
        await activate()
        guard let page = await open(URL(string: Self.details2Base + "find.html?services")!) else { return }
        focusPage(page)
        try? await Task.sleep(for: .milliseconds(300))
        let selected = await js(page, "(() => { const r = document.createRange(); r.selectNodeContents(document.querySelector('h1')); getSelection().removeAllRanges(); getSelection().addRange(r); return getSelection().toString().length })()")
        try? await Task.sleep(for: .milliseconds(1200))
        let responder = window.firstResponder
        let pageRequestor = responder?.validRequestor(forSendType: .string, returnType: nil)
        let servicesMenu = NSApp.servicesMenu
        SpikeRunner.record("services", "menu set=\(servicesMenu != nil) in app menu=\(NSApp.mainMenu?.items.first?.submenu?.item(withTitle: "Services")?.submenu === servicesMenu) "
            + "page responder=\(responder.map { String(describing: Swift.type(of: $0)) } ?? "nil") selected=\(selected) chars window key=\(window.isKeyWindow) app active=\(NSApp.isActive) sends text=\(pageRequestor != nil) "
            + "services items=\(servicesMenu?.items.count ?? -1)")
    }

    // MARK: incognito (B-98)

    func details2Incognito() async {
        guard let app = AppDelegate.current, let profileID = store.profiles.first?.id else { return }
        let regularProbe = app.engineProfiles[profileID] as? RoomCoreProfileProbe
        app.newIncognitoWindow(nil)
        _ = await waitUntil(5) { app.windows.all.filter(\.isIncognito).count == 1 }
        app.newIncognitoWindow(nil)
        _ = await waitUntil(5) { app.windows.all.filter(\.isIncognito).count == 2 }
        let incognito = app.windows.all.filter(\.isIncognito)
        guard incognito.count == 2, let a = incognito.first, let b = incognito.last, let ta = a.tabs, let tb = b.tabs,
              let ca = a.incognito, let cb = b.incognito else {
            return SpikeRunner.record("incognito_two", "failed: incognito windows=\(incognito.count)")
        }
        let frames = "\(NSStringFromRect(a.window?.frame ?? .zero)) \(NSStringFromRect(b.window?.frame ?? .zero))"
        SpikeRunner.record("incognito_two", "windows=\(app.windows.all.count) incognito=2 same twin=\(ca.twin === cb.twin) same store=\(ca.store === cb.store) "
            + "rows=\(ca.store.windows.windows.count) cascaded=\(a.window?.frame != b.window?.frame) (\(frames)) main store rows=\(app.store?.windows.windows.count ?? -1)")
        let url = "http://127.0.0.1:8765/cookies.html"
        guard let ia = ta.openNewTab(url: url), let pa = await waitTabPage(ta, ia), let ib = tb.openNewTab(url: url), let pb = await waitTabPage(tb, ib) else {
            return SpikeRunner.record("incognito_pages", "failed")
        }
        _ = await js(pa, "document.cookie = 'room_b98=shared; path=/'; 0")
        let seenInB = await js(pb, "document.cookie")
        let todayA = ca.store.sidebar.today(space: a.sidebar?.activeSpaceID ?? UUID(), window: a.id).count
        let todayB = ca.store.sidebar.today(space: b.sidebar?.activeSpaceID ?? UUID(), window: b.id).count
        SpikeRunner.record("incognito_pages", "today A=\(todayA) B=\(todayB) cookie set in A seen in B=\(seenInB)")
        details2Capture("incognito-two", of: b.window)
        // A closes: B and its page go on, the twin stays.
        a.window?.performClose(nil)
        _ = await waitUntil(5) { app.windows.all.filter(\.isIncognito).count == 1 }
        try? await Task.sleep(for: .milliseconds(800))
        let bAlive = await js(pb, "document.cookie")
        SpikeRunner.record("incognito_close_one", "incognito=\(app.windows.all.filter(\.isIncognito).count) twin alive=\(regularProbe?.twinExists ?? false) "
            + "B's page answers=\(bAlive) rows=\(cb.store.windows.windows.count) A's tabs gone=\(cb.store.sidebar.today(space: a.sidebar?.activeSpaceID ?? UUID(), window: a.id).isEmpty)")
        // The last one closes: the twin ends.
        b.window?.performClose(nil)
        _ = await waitUntil(5) { !app.windows.all.contains { $0.isIncognito } }
        let gone = await waitUntil(20) { regularProbe?.twinExists == false }
        SpikeRunner.record("incognito_close_last", "incognito=\(app.windows.all.filter(\.isIncognito).count) twin gone=\(gone) reader folder left=\(FileManager.default.fileExists(atPath: cb.readerFolder.path))")
        // A new one: a new twin without the cookie.
        app.newIncognitoWindow(nil)
        _ = await waitUntil(5) { app.windows.all.contains { $0.isIncognito } }
        if let again = app.windows.all.first(where: \.isIncognito), let tc = again.tabs, let ic = tc.openNewTab(url: url), let pc = await waitTabPage(tc, ic) {
            SpikeRunner.record("incognito_reopen", "new twin=\(again.incognito?.twin !== ca.twin) cookie=\(await js(pc, "document.cookie"))")
            again.window?.performClose(nil)
            _ = await waitUntil(5) { !app.windows.all.contains { $0.isIncognito } }
        } else {
            SpikeRunner.record("incognito_reopen", "failed")
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: thumbs (B-119)

    func details2Thumbs() async {
        let paths = ["find.html?t1", "status.html", "menu.html", "dialogs.html", "media.html"]
        var ids: [UUID] = []
        for path in paths {
            guard let page = await open(URL(string: Self.details2Base + path)!), let id = tabs.entryID(for: page) else { continue }
            ids.append(id)
        }
        try? await Task.sleep(for: .seconds(1))
        var shown: [Double] = []
        var sizes: Set<String> = []
        for id in ids {
            sidebar.select(id)
            try? await Task.sleep(for: .milliseconds(500))
            guard let page = tabs.contents(for: id) else { continue }
            for _ in 0..<3 {
                let start = ContinuousClock.now
                if let image = try? await page.captureViewport() { shown.append(ms(since: start)); sizes.insert(NSStringFromSize(image.size)) }
            }
        }
        // A page not on screen: what the switcher would need for every other row.
        var background: [String] = []
        var backgroundMs: [Double] = []
        if let selected = ids.last { sidebar.select(selected) }
        try? await Task.sleep(for: .milliseconds(500))
        for id in ids.dropLast() {
            guard let page = tabs.contents(for: id) else { continue }
            let start = ContinuousClock.now
            let box = CaptureBox()
            Task { @MainActor in
                box.image = try? await page.captureViewport()
                box.done = true
            }
            _ = await waitUntil(3) { box.done }
            let result = box.image
            let elapsed = ms(since: start)
            backgroundMs.append(elapsed)
            background.append(result.map { "ok \(NSStringFromSize($0.size))" } ?? String(format: "none in %.0f ms", elapsed))
        }
        // The downscale a thumbnail needs (to 240 pt wide).
        var scales: [Double] = []
        if let page = tabs.current, let image = try? await page.captureViewport() {
            for _ in 0..<5 {
                let start = ContinuousClock.now
                let width: CGFloat = 240, height = (width * image.size.height / max(image.size.width, 1)).rounded()
                let thumb = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                    image.draw(in: rect)
                    return true
                }
                _ = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
                scales.append(ms(since: start))
            }
        }
        SpikeRunner.record("thumbs_capture_shown", SpikeRunner.stats(shown) + " sizes=\(sizes.sorted())")
        SpikeRunner.record("thumbs_capture_background", SpikeRunner.stats(backgroundMs) + " results=\(background)")
        SpikeRunner.record("thumbs_downscale", SpikeRunner.stats(scales))
    }
}
#endif
