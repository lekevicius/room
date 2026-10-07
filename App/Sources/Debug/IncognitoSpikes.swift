#if DEBUG
import AppKit
import Engine
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 4.8b spike `incognito` (`Room -RoomSpike incognito`; the tour's step
/// `incognito` through `scripts/incognito-check.sh`, which serves
/// `research/spikes` on :8777 and the 2.5 cookie page on :8765).
/// Sections (`-RoomSpikeOnly` picks): `engine` the two members on RoomCore
/// directly (a page moved between two windows' Browsers keeps its history
/// and view; the off-the-record twin made, a cookie set in it absent from
/// the regular profile, the twin closed and gone, a new twin without it).
extension SpikeRunner.Context {
    static let incognitoBase = "http://127.0.0.1:8777/phase-4.8/"
    static let incognitoCookies = "http://127.0.0.1:8765/cookies.html"

    func incognitoChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        if runs("engine") { await incognitoEngine() }
        if runs("main") { await incognitoMain() }
        if only.contains("idle") { await incognitoIdle() }
    }

    static let incognitoLoginA = "http://127.0.0.1:8772/login.html"
    static let incognitoLoginB = "http://localhost:8772/login.html"

    /// ⇧⌘N through the menu's key path from `window`; the incognito session.
    func pressNewIncognito(_ app: AppDelegate, from window: NSWindow?) async -> (session: WindowSession?, by: String, ms: Double) {
        let start = ContinuousClock.now
        let before = app.windows.all.count
        if let window {
            PageDriver.key(window, characters: "N", charactersIgnoringModifiers: "N", keyCode: 45, modifiers: [.command, .shift])
        }
        var by = "menu key"
        if await !waitUntil(3, { app.windows.all.count > before }) {
            by = "call (the key did not reach the menu)"
            app.newIncognitoWindow(nil)
        }
        _ = await waitUntil(5) { app.windows.all.contains { $0.isIncognito } }
        if !app.windows.all.contains(where: { $0.isIncognito }) {
            by += " (windows=\(app.windows.all.count), regular=\(app.windows.regular.count))"
        }
        return (app.windows.all.first { $0.isIncognito }, by, ms(since: start))
    }

    /// Types `text` into the page with the keyboard (Chrome's password
    /// manager saves only what the user typed).
    func typeInto(_ page: any WebContents, _ selector: String, _ text: String, window: NSWindow) async {
        _ = await js(page, "(() => { const e = document.querySelector('\(selector)'); if (e) e.value = ''; return 0 })()")
        if let point = await PageDriver.center(of: selector, in: page, "incognito: \(selector)") {
            PageDriver.click(page, at: point, "incognito: click \(selector)")
        }
        try? await Task.sleep(for: .milliseconds(120))
        for character in text {
            let lower = Character(character.lowercased())
            PageDriver.key(window, characters: String(character), charactersIgnoringModifiers: String(lower),
                           keyCode: Self.keyCodes37[lower] ?? 0, modifiers: character.isUppercase ? [.shift] : [])
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Chrome's Views bubbles and popups on screen (the password save bubble is one).
    func chromeBubbles() -> Set<ObjectIdentifier> {
        Set(NSApp.windows.filter { $0.isVisible && NSStringFromClass(Swift.type(of: $0)).contains("NativeWidget") && !$0.ignoresMouseEvents
            && $0.frame.width > 20 }.map(ObjectIdentifier.init))
    }

    /// Signs in on `url` in `page`'s window and reports whether a bubble appeared within `seconds`.
    func signInShowsBubble(_ page: any WebContents, window: NSWindow, user: String, password: String, seconds: Double) async -> (shown: Bool, ms: Double) {
        window.makeKeyAndOrderFront(nil)
        _ = await waitUntil(3) { NSApp.keyWindow === window }
        await typeInto(page, "#username", user, window: window)
        await typeInto(page, "#password", password, window: window)
        let before = chromeBubbles()
        let start = ContinuousClock.now
        if let point = await PageDriver.center(of: "#submit", in: page, "incognito: submit") { PageDriver.click(page, at: point, "incognito: submit") }
        let shown = await waitUntil(seconds) { !self.chromeBubbles().subtracting(before).isEmpty }
        let elapsed = ms(since: start)
        // Close what showed (Esc to the bubble) so it does not cover the next checks.
        for bubble in NSApp.windows where chromeBubbles().subtracting(before).contains(ObjectIdentifier(bubble)) { bubble.orderOut(nil) }
        return (shown, elapsed)
    }

    func captureIncognito(_ window: NSWindow?, _ name: String) {
        guard let window, let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.8b-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        window.displayIfNeeded()
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: main

    func incognitoMain() async {
        guard let app = AppDelegate.current, let store = app.store, let w1 = app.windows.all.first, let s1 = w1.sidebar, let t1 = w1.tabs,
              let window1 = w1.window, let profileID = store.sidebar.space(s1.activeSpaceID)?.profileID else {
            return SpikeRunner.record("error", "main: no window")
        }
        _ = await activeEngineProfile(app)
        let baseline = ProcessMemory.snapshot()
        SpikeRunner.record("baseline", baseline.summary)
        let rowsBefore = store.windows.windows.count

        // ⇧⌘N.
        let (opened, by, openMs) = await pressNewIncognito(app, from: window1)
        guard let inc = opened, let si = inc.sidebar, let ti = inc.tabs, let ctx = inc.incognito, let windowI = inc.window else {
            return SpikeRunner.record("incognito_window", "failed by \(by) windows=\(app.windows.all.count)")
        }
        _ = await waitUntil(3) { NSApp.keyWindow === windowI }
        let windowMenu = NSApp.windowsMenu?.items.map(\.title) ?? []
        SpikeRunner.record("incognito_window", String(format: "by %@ in %.1f ms ", by, openMs)
            + "title=\"\(windowI.title)\" appearance=\(windowI.appearance?.name.rawValue ?? "nil") "
            + "tint=\(ctx.store.sidebar.spaces.first?.themeColors.joined(separator: ",") ?? "nil") badge=\(inc.controller.sidebarView.badgeText ?? "nil") "
            + "key=\(NSApp.keyWindow === windowI) windows=\(app.windows.all.count) store_rows=\(store.windows.windows.count)/\(rowsBefore) "
            + "window_menu_lists=\(windowMenu.contains("Incognito")) ephemeral=\(ctx.store.isEphemeral)")
        SpikeRunner.record("incognito_sidebar", "rows=\(si.debugRowKinds.joined(separator: ",")) essentials_shown=\(si.debugEssentialsShown) "
            + "spaces=\(ctx.store.sidebar.spaces.count) pinned=\(ctx.store.sidebar.pinned(space: si.activeSpaceID).count) "
            + "essentials=\(ctx.store.sidebar.essentials(profile: profileID).count) regular_rows=\(s1.debugRowKinds.first ?? "nil")")

        // A cookie set in incognito, absent from the regular profile.
        guard let secretID = ti.openNewTab(url: Self.incognitoCookies + "?set=incognito-main", transition: .typed),
              let secret = await waitTabPage(ti, secretID) else { return SpikeRunner.record("error", "no incognito page") }
        let secretCookie = await js(secret, "document.cookie")
        guard let plainID = t1.openNewTab(url: Self.incognitoCookies, transition: .typed), let plain = await waitTabPage(t1, plainID) else {
            return SpikeRunner.record("error", "no regular page")
        }
        SpikeRunner.record("cookie", "incognito=\(secretCookie) regular=\(await js(plain, "document.cookie")) "
            + "twin_history=\(ctx.twin.history == nil ? "none" : "some") regular_today=\(store.sidebar.today(space: s1.activeSpaceID, window: w1.id).count)")
        // Nothing of it in the regular profile's history or Room's store.
        try? await Task.sleep(for: .milliseconds(1500))
        let rows = await app.engineProfiles[profileID]?.history?.entries(from: nil, to: nil, limit: 500) ?? []
        let stored = store.currentState().entries.filter { ($0.currentURL ?? "").contains("incognito-main") }.count
        SpikeRunner.record("history", "regular_rows=\(rows.count) incognito_rows=\(rows.filter { $0.url.absoluteString.contains("incognito-main") }.count) "
            + "regular_cookie_page_rows=\(rows.filter { $0.url.absoluteString.hasPrefix(Self.incognitoCookies) }.count) store_entries=\(stored) "
            + "incognito_today=\(ctx.store.sidebar.today(space: si.activeSpaceID).count)")

        // Signing in: the regular window offers to save; the incognito window does not (3.7a inverted).
        if let regularLogin = t1.openNewTab(url: Self.incognitoLoginA, transition: .typed), let page = await waitTabPage(t1, regularLogin) {
            let regular = await signInShowsBubble(page, window: window1, user: "alice", password: "secret-a1", seconds: 12)
            SpikeRunner.record("login_regular", String(format: "save_bubble=%@ after %.0f ms", regular.shown ? "true" : "false", regular.ms))
        }
        if let incognitoLogin = ti.openNewTab(url: Self.incognitoLoginB, transition: .typed), let page = await waitTabPage(ti, incognitoLogin) {
            let incognito = await signInShowsBubble(page, window: windowI, user: "bob", password: "secret-b1", seconds: 8)
            await waitLoaded(page)
            SpikeRunner.record("login_incognito", String(format: "save_bubble=%@ (waited %.0f ms) submitted_to=%@", incognito.shown ? "true" : "false",
                                                         incognito.ms, page.url?.path ?? "nil"))
        }

        // "Open Link in Incognito Window" from a regular page's context menu (B-50).
        app.windows.focus(w1)
        _ = await waitUntil(3) { NSApp.keyWindow === window1 }
        if let linkID = t1.openNewTab(url: Self.incognitoBase + "a.html", transition: .typed), let page = await waitTabPage(t1, linkID) {
            var itemTitle = "none"
            let present = w1.pageDelegate.chrome.presentMenu
            w1.pageDelegate.chrome.presentMenu = { menu, _, _ in
                if let index = menu.menu.items.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("incognito") }) {
                    itemTitle = menu.menu.items[index].title
                    menu.menu.performActionForItem(at: index)
                } else {
                    itemTitle = "missing among \(menu.menu.items.map(\.title).filter { !$0.isEmpty }.prefix(8).joined(separator: "|"))"
                    menu.menuDidClose(menu.menu)
                }
            }
            let todayBefore = ctx.store.sidebar.today(space: si.activeSpaceID).count
            let regularBefore = store.sidebar.today(space: s1.activeSpaceID, window: w1.id).count
            let start = ContinuousClock.now
            if let point = await PageDriver.center(of: "#next", in: page, "incognito: link") {
                PageDriver.click(page, at: point, button: .rightMouseDown, "incognito: right-click the link")
            }
            _ = await waitUntil(10) { ctx.store.sidebar.today(space: si.activeSpaceID).count > todayBefore }
            let landedMs = ms(since: start)
            w1.pageDelegate.chrome.presentMenu = present
            let landed = si.selectedEntryID.flatMap { ti.contents(for: $0) }
            if let landed { await waitLoaded(landed, timeout: 15) }
            SpikeRunner.record("open_link_incognito", String(format: "in %.0f ms ", landedMs) + "item=\"\(itemTitle)\" "
                + "incognito_today=\(todayBefore)→\(ctx.store.sidebar.today(space: si.activeSpaceID).count) "
                + "regular_today=\(regularBefore)→\(store.sidebar.today(space: s1.activeSpaceID, window: w1.id).count) "
                + "url=\(landed?.url?.lastPathComponent ?? "nil") in_incognito_window=\(landed?.nativeView.window === windowI) "
                + "key=\(NSApp.keyWindow === windowI ? "incognito" : "other") windows=\(app.windows.all.count)")
        }

        // Extensions: the fixture's action in the incognito header only when allowed in incognito.
        await incognitoExtensions(app: app, store: store, regular: w1, incognito: inc, profileID: profileID)

        // The look, in both system appearances (the window is dark in both).
        let appearance = NSApp.appearance
        for (name, value) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: value)
            app.windows.focus(inc)
            try? await Task.sleep(for: .milliseconds(400))
            captureIncognito(windowI, "incognito-\(name)")
            captureIncognito(window1, "regular-\(name)")
        }
        NSApp.appearance = appearance

        // Closing the window ends its pages and the twin.
        let twinPages = (ctx.twin as? RoomCoreProfileProbe)?.openPages ?? -1
        let rendererOpen = ProcessMemory.snapshot().renderers
        let incognitoEntries = ctx.store.sidebar.today(space: si.activeSpaceID).count
        let closeStart = ContinuousClock.now
        inc.controller.window?.performClose(nil)
        _ = await waitUntil(5) { !app.windows.all.contains { $0.isIncognito } }
        let closedMs = ms(since: closeStart)
        let twinAfter = (ctx.twin as? RoomCoreProfileProbe)?.openPages ?? -1
        let regularProbe = app.engineProfiles[profileID] as? RoomCoreProfileProbe
        let gone = await waitUntil(20) { regularProbe?.twinExists == false }
        let goneMs = ms(since: closeStart)
        _ = await waitUntil(10) { ProcessMemory.snapshot().renderers <= rendererOpen - 1 }
        try? await Task.sleep(for: .seconds(2))
        let rendererAfter = ProcessMemory.snapshot().renderers
        SpikeRunner.record("close_incognito", String(format: "window closed in %.0f ms ", closedMs)
            + "windows=\(app.windows.all.count) entries=\(incognitoEntries) twin_pages=\(twinPages)→\(twinAfter) "
            + String(format: "twin_gone=%@ after %.0f ms ", gone ? "true" : "false", goneMs)
            + "renderers=\(baseline.renderers)(launch)→\(rendererOpen)(open)→\(rendererAfter)(closed) "
            + "store_rows=\(store.windows.windows.count) reader_folder_left=\(FileManager.default.fileExists(atPath: ctx.readerFolder.path))")

        // Reopened: a new twin, the cookie gone.
        let (again, _, _) = await pressNewIncognito(app, from: window1)
        if let again, let ta = again.tabs, let id = ta.openNewTab(url: Self.incognitoCookies, transition: .typed), let page = await waitTabPage(ta, id) {
            SpikeRunner.record("reopen_incognito", "new_twin=\(again.incognito?.twin !== ctx.twin) cookie=\(await js(page, "document.cookie")) "
                + "today=\(again.incognito?.store.sidebar.today(space: again.sidebar?.activeSpaceID ?? UUID()).count ?? -1)")
            again.controller.window?.performClose(nil)
            _ = await waitUntil(5) { !app.windows.all.contains { $0.isIncognito } }
        } else {
            SpikeRunner.record("reopen_incognito", "failed")
        }
    }

    func waitTabPage(_ tabs: TabController, _ entry: UUID, timeout: Double = 20) async -> (any WebContents)? {
        _ = await waitUntil(timeout) { tabs.contents(for: entry).map { !$0.isLoading && $0.url != nil } ?? false }
        return tabs.contents(for: entry)
    }

    /// The fixture extension (3.6) loaded and pinned in the regular profile:
    /// absent from the incognito header until "Allow in incognito", then
    /// present, then absent again.
    func incognitoExtensions(app: AppDelegate, store: RoomStore, regular: WindowSession, incognito: WindowSession, profileID: UUID) async {
        guard let center = app.extensions, let section = center.section(profile: profileID) else {
            return SpikeRunner.record("extensions_incognito", "skipped: no extensions")
        }
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        guard let id = try? await section.extensions.loadUnpacked(at: fixture) else {
            return SpikeRunner.record("extensions_incognito", "failed: the fixture did not load")
        }
        _ = await waitUntil(5) { center.section(profile: profileID)?.installed.first { $0.id == id }?.isPinned == true }
        let regularField = regular.sidebar?.extensionBar, incognitoField = incognito.sidebar?.extensionBar
        func shows(_ field: ExtensionBarView?) -> Bool { field?.extensionActionIDs.contains(id) ?? false }
        _ = await waitUntil(5) { shows(regularField) }
        let before = "regular=\(shows(regularField)) incognito=\(shows(incognitoField))"
        store.settings.update { $0.setAllowsInIncognito(true, id, profile: profileID) }
        let allowedShown = await waitUntil(10) { shows(incognitoField) }
        let engineAllowed = (section.extensions as? RoomCoreExtensionsProbe)?.allowedInIncognito(id) ?? false
        store.settings.update { $0.setAllowsInIncognito(false, id, profile: profileID) }
        let disallowedGone = await waitUntil(10) { !shows(incognitoField) }
        let engineDisallowed = !((section.extensions as? RoomCoreExtensionsProbe)?.allowedInIncognito(id) ?? true)
        SpikeRunner.record("extensions_incognito", "disallowed: \(before); allowed: incognito=\(allowedShown) engine=\(engineAllowed); "
            + "disallowed again: gone=\(disallowedGone) engine=\(engineDisallowed) regular=\(shows(regularField))")
    }

    // MARK: idle (the net-log launch)

    /// An incognito window opened at launch and left idle (`-RoomIncognitoIdle`
    /// seconds, default 20) while the engine's net-log records.
    func incognitoIdle() async {
        guard let app = AppDelegate.current else { return }
        SpikeRunner.record("phase", String(format: "launch %.3f", Self.processStartDate().timeIntervalSince1970))
        let (session, by, openMs) = await pressNewIncognito(app, from: app.windows.all.first?.window)
        SpikeRunner.record("phase", String(format: "idle %.3f", Date().timeIntervalSince1970))
        SpikeRunner.record("idle_incognito", String(format: "opened=%@ by %@ in %.0f ms", session != nil ? "true" : "false", by, openMs))
        let asked = UserDefaults.standard.double(forKey: "RoomIncognitoIdle")
        let seconds = asked > 0 ? asked : 20
        try? await Task.sleep(for: .seconds(seconds))
        SpikeRunner.record("phase", String(format: "quit %.3f", Date().timeIntervalSince1970))
        SpikeRunner.record("idle_done", "\(Int(seconds)) s with the incognito window open=\(app.windows.all.contains { $0.isIncognito })")
    }

    /// The engine profile of the active window's space (waits for its delivery).
    func activeEngineProfile(_ app: AppDelegate) async -> (any Engine.Profile)? {
        guard let session = app.activeWindow, let sidebar = session.sidebar, let store = app.store,
              let profileID = store.sidebar.space(sidebar.activeSpaceID)?.profileID else { return nil }
        _ = await waitUntil(15) { session.tabs?.engineProfiles[profileID] != nil }
        return session.tabs?.engineProfiles[profileID]
    }

    /// A scratch host view for a page the spike made itself, in `window`'s content.
    @discardableResult
    func hostScratch(_ page: any WebContents, in window: NSWindow?) -> Bool {
        guard let content = window?.contentView else { return false }
        let view = page.nativeView
        view.removeFromSuperview()
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        content.addSubview(view)
        return true
    }

    // MARK: engine

    func incognitoEngine() async {
        #if ROOM_ENGINE_ROOMCORE
        guard let app = AppDelegate.current, let w1 = app.windows.all.first,
              let profile = await activeEngineProfile(app) as? RoomCoreProfile else {
            return SpikeRunner.record("error", "engine: no RoomCore profile")
        }
        app.newRoomWindow(nil)
        _ = await waitUntil(5) { app.windows.all.count == 2 }
        guard let w2 = app.windows.all.last, w2 !== w1, let window1 = w1.window, let window2 = w2.window else {
            return SpikeRunner.record("error", "engine: no second window")
        }
        // A page in window 1's Browser with two entries.
        guard let page = try? profile.makeWebContents(WebContentsConfiguration(hostWindow: window1)) else {
            return SpikeRunner.record("error", "engine: no page")
        }
        hostScratch(page, in: window1)
        page.load(URL(string: Self.incognitoBase + "a.html")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(page, timeout: 15)
        page.load(URL(string: Self.incognitoBase + "next-a.html")!, transition: .link, fromAddressBar: false)
        _ = await waitUntil(15) { !page.isLoading && page.url?.lastPathComponent == "next-a.html" && page.canGoBack }
        let chromiumView = page.nativeView.subviews.first
        func browsers() -> String {
            profile.spikeBrowsers.map { browser in
                let name = browser.window === window1 ? "w1" : browser.window === window2 ? "w2" : "other"
                return "\(name):\(browser.webContents.count)"
            }.joined(separator: ",")
        }
        let before = "browsers=\(browsers()) url=\(page.url?.lastPathComponent ?? "nil") canGoBack=\(page.canGoBack) history=\(await js(page, "history.length"))"
        SpikeRunner.record("engine_before_move", before)
        let start = ContinuousClock.now
        var moveError = "none"
        do { try page.move(toHostWindow: window2) } catch { moveError = "\(error)" }
        hostScratch(page, in: window2)
        let moveMs = ms(since: start)
        await nextRunLoopTurn()
        let sameView = page.nativeView.subviews.first.map { $0 === chromiumView } ?? false
        let history = await js(page, "history.length")
        let capture = try? await page.captureViewport()
        SpikeRunner.record("engine_move", String(format: "in %.1f ms ", moveMs)
            + "error=\(moveError) browsers=\(browsers()) host_window=\(page.configuration.hostWindow === window2 ? "w2" : "?") "
            + "url=\(page.url?.lastPathComponent ?? "nil") canGoBack=\(page.canGoBack) history=\(history) "
            + "same_chromium_view=\(sameView) view_in_w2=\(page.nativeView.window === window2) "
            + "capture=\(capture.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "failed") state=\(page.state)")
        page.goBack()
        _ = await waitUntil(15) { !page.isLoading && page.url?.lastPathComponent == "a.html" }
        SpikeRunner.record("engine_move_back", "url=\(page.url?.lastPathComponent ?? "nil") canGoForward=\(page.canGoForward)")
        var refused = "none"
        page.close()
        _ = await waitUntil(5) { page.state == .closed }
        do { try page.move(toHostWindow: window1) } catch { refused = "\(error)" }
        SpikeRunner.record("engine_move_closed", "refused=\(refused)")

        // The off-the-record twin.
        let twinStart = ContinuousClock.now
        guard let twin = try? profile.makeOffTheRecord() else { return SpikeRunner.record("engine_twin", "failed") }
        let twinMs = ms(since: twinStart)
        let again = (try? profile.makeOffTheRecord()) === twin
        let nested: String
        do { _ = try twin.offTheRecord(); nested = "allowed" } catch { nested = "\(error)" }
        SpikeRunner.record("engine_twin", String(format: "made in %.1f ms ", twinMs)
            + "exists=\(profile.hasOffTheRecordProfile) same_on_second_call=\(again) twin_of_twin=\(nested) history=\(twin.history == nil ? "none" : "some")")
        guard let secret = try? twin.makeWebContents(WebContentsConfiguration(hostWindow: window2)),
              let regular = try? profile.makeWebContents(WebContentsConfiguration(hostWindow: window1)) else {
            return SpikeRunner.record("error", "engine: no twin page")
        }
        hostScratch(secret, in: window2)
        hostScratch(regular, in: window1)
        secret.load(URL(string: Self.incognitoCookies + "?set=incognito-engine")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(secret, timeout: 15)
        regular.load(URL(string: Self.incognitoCookies)!, transition: .typed, fromAddressBar: true)
        await waitLoaded(regular, timeout: 15)
        SpikeRunner.record("engine_cookie", "twin=\(await js(secret, "document.cookie")) regular=\(await js(regular, "document.cookie"))")
        let rows = await profile.history?.entries(from: nil, to: nil, limit: 200) ?? []
        SpikeRunner.record("engine_history", "regular_rows=\(rows.count) incognito_rows=\(rows.filter { $0.url.absoluteString.contains("incognito-engine") }.count)")

        secret.close()
        _ = await waitUntil(5) { secret.state == .closed }
        let closeStart = ContinuousClock.now
        profile.closeOffTheRecord()
        let gone = await waitUntil(20) { !profile.hasOffTheRecordProfile }
        SpikeRunner.record("engine_twin_closed", String(format: "gone=%@ after %.0f ms", gone ? "true" : "false", ms(since: closeStart)))
        guard let next = try? profile.makeOffTheRecord(), let fresh = try? next.makeWebContents(WebContentsConfiguration(hostWindow: window2)) else {
            return SpikeRunner.record("engine_new_twin", "failed")
        }
        hostScratch(fresh, in: window2)
        fresh.load(URL(string: Self.incognitoCookies)!, transition: .typed, fromAddressBar: true)
        await waitLoaded(fresh, timeout: 15)
        SpikeRunner.record("engine_new_twin", "new_object=\(next !== twin) cookie=\(await js(fresh, "document.cookie"))")

        // "Open Link in Incognito Window" from a regular page (patches/0014's
        // hook answers the twin's Browser, B-50): didCreate with the
        // off-the-record disposition, a page of the twin, then moved.
        let probe = IncognitoProbeDelegate()
        regular.uiDelegate = probe
        regular.load(URL(string: Self.incognitoBase + "a.html")!, transition: .typed, fromAddressBar: true)
        await waitLoaded(regular, timeout: 15)
        window1.makeKeyAndOrderFront(nil)
        if let point = await PageDriver.center(of: "#next", in: regular, "incognito: the link") {
            PageDriver.click(regular, at: point, button: .rightMouseDown, "incognito: right-click the link")
        }
        _ = await waitUntil(10) { probe.created != nil }
        if let created = probe.created {
            await waitLoaded(created.page, timeout: 15)
            let inTwin = next.webContents.contains { $0 === created.page }
            let twinBrowsersBefore = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            var moved = "none"
            do { try created.page.move(toHostWindow: window2); hostScratch(created.page, in: window2) } catch { moved = "\(error)" }
            await nextRunLoopTurn()
            let twinBrowsersAfter = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            SpikeRunner.record("engine_otr_open", "menu_item=\(probe.itemTitle ?? "none") disposition=\(created.disposition) in_twin=\(inTwin) "
                + "in_regular=\(profile.webContents.contains { $0 === created.page }) url=\(created.page.url?.lastPathComponent ?? "nil") "
                + "referrer=\(await js(created.page, "document.referrer")) opener=\(await js(created.page, "String(window.opener === null)")) "
                + "twin_browsers_before=\(twinBrowsersBefore) move_error=\(moved) twin_browsers_after=\(twinBrowsersAfter)")
            created.page.close()
        } else {
            SpikeRunner.record("engine_otr_open", "failed: menu_item=\(probe.itemTitle ?? "none") items=\(probe.titles.prefix(12).joined(separator: "|"))")
        }
        // Again with no page of the twin open: the hook makes the twin a
        // Browser in the opener's window, which the move empties and closes.
        fresh.close()
        _ = await waitUntil(5) { next.webContents.isEmpty }
        await nextRunLoopTurn()
        let second = IncognitoProbeDelegate()
        regular.uiDelegate = second
        window1.makeKeyAndOrderFront(nil)
        _ = await waitUntil(3) { NSApp.keyWindow === window1 }
        if let point = await PageDriver.center(of: "#next", in: regular, "incognito: the link again") {
            PageDriver.click(regular, at: point, button: .rightMouseDown, "incognito: right-click the link again")
        }
        _ = await waitUntil(10) { second.created != nil }
        if let created = second.created {
            await waitLoaded(created.page, timeout: 15)
            let before = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            var moved = "none"
            do { try created.page.move(toHostWindow: window2); hostScratch(created.page, in: window2) } catch { moved = "\(error)" }
            _ = await waitUntil(3) { next.spikeBrowsers.allSatisfy { $0.window === window2 } }
            let after = next.spikeBrowsers.map { $0.window === window1 ? "w1:\($0.webContents.count)" : $0.window === window2 ? "w2:\($0.webContents.count)" : "other" }
            SpikeRunner.record("engine_otr_open_no_twin_page", "disposition=\(created.disposition) in_twin=\(next.webContents.contains { $0 === created.page }) "
                + "url=\(created.page.url?.lastPathComponent ?? "nil") twin_browsers_before=\(before) move_error=\(moved) twin_browsers_after=\(after) "
                + "state=\(created.page.state) history=\(await js(created.page, "history.length"))")
            created.page.close()
        } else {
            SpikeRunner.record("engine_otr_open_no_twin_page", "failed: menu_item=\(second.itemTitle ?? "none") items=\(second.titles.count) twin_pages=\(next.webContents.count) key=\(NSApp.keyWindow === window1 ? "w1" : "other")")
        }
        regular.close()
        profile.closeOffTheRecord()
        let goneAgain = await waitUntil(20) { !profile.hasOffTheRecordProfile }
        SpikeRunner.record("engine_twin_closed_again", "gone=\(goneAgain)")
        #else
        SpikeRunner.record("error", "engine: RoomCore only")
        #endif
    }

    /// One turn of the main queue.
    func nextRunLoopTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}

/// Answers the engine's context menu with "Open Link in Incognito Window" and
/// records the page it opens (the `engine` section).
@MainActor
final class IncognitoProbeDelegate: WebContentsUIDelegate {
    private(set) var created: (page: any WebContents, disposition: Disposition)?
    private(set) var itemTitle: String?
    private(set) var titles: [String] = []

    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        titles = menu.items.map(\.title)
        if let item = menu.items.first(where: { $0.title.localizedCaseInsensitiveContains("incognito") }) {
            itemTitle = item.title
            menu.select(item.id)
        } else {
            menu.cancel()
        }
        return true
    }

    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        created = (newContents, disposition)
    }
}

/// What the spikes read from RoomCore's concrete objects (no protocol member).
@MainActor protocol RoomCoreProfileProbe {
    var openPages: Int { get }
    var twinExists: Bool { get }
}

@MainActor protocol RoomCoreExtensionsProbe {
    func allowedInIncognito(_ id: String) -> Bool
}

#if ROOM_ENGINE_ROOMCORE
extension RoomCoreProfile: RoomCoreProfileProbe {
    var openPages: Int { webContents.count }
    var twinExists: Bool { hasOffTheRecordProfile }
}

extension RoomCoreExtensions: RoomCoreExtensionsProbe {
    func allowedInIncognito(_ id: String) -> Bool { isAllowedInIncognito(id) }
}
#endif
#endif
