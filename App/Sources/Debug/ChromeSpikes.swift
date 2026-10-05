#if DEBUG
import AppKit
import Chrome
import Engine
import Tabs
#if canImport(EngineCEF)
import EngineCEF
#endif

/// Phase 2.6a: the page's prompts, menus and file choosers on CEF
/// (`scripts/chrome-surfaces.sh`, which serves `research/spikes/phase-2.6/`
/// on 127.0.0.1:8766 and its self-signed twin on :8767):
/// - `chromesurfaces`: JavaScript dialogs (Return, Esc, typing into a
///   prompt), `beforeunload` on ⌘W (Stay brings the tab back, Leave closes
///   it), HTTP auth (typed, Tab, Return), the certificate interstitial (Go
///   Back, then Show Details and Visit), permissions (location, notifications,
///   camera and microphone through the popover's buttons), file choosers (the
///   panel's types and modes, cancelled), a right-click on a link and an image
///   (the menu's items; Open Link in New Tab), `window.open` popups and
///   `target=_blank` (new Today tabs; `window.close()` closes the entry).
///   With `-RoomSpikeCaptures YES` it asks the script for window-server
///   captures (`capture:` the window, `capture_screen:` a screen rect for
///   the popover and the menu); `-RoomSpikeAppearance dark` for dark.
extension SpikeRunner.Context {
    var chrome: PageChrome { session.pageDelegate.chrome }
    var prompts: PagePrompts { chrome.prompts }
    var presenter: PagePromptPresenter? { AppDelegate.current?.promptPresenter }

    static let server = "http://127.0.0.1:8766/"
    static let secureServer = "https://127.0.0.1:8767/"

    var appearanceSuffix: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }

    func chromeSurfaces() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        controller.activityOverride = true
        await activate()
        await forgetTestSiteDecisions()
        await dialogsCheck()
        await authCheck()
        await certificateCheck()
        await permissionsCheck()
        await filesCheck()
        await contextMenuCheck()
        await popupsCheck()
    }

    /// Chromium remembers a profile's answers (a certificate exception, a
    /// denied permission); on a state an earlier run used (the grand tour,
    /// Phase 2.9) the checks below would find them and see no prompt. Every
    /// test origin starts with none.
    func forgetTestSiteDecisions() async {
        for profile in tabs.engineProfiles.values {
            for origin in ["http://127.0.0.1:8766", "https://127.0.0.1:8767", "http://localhost:8766"].compactMap(URL.init(string:)) {
                for permission in SitePermission.allCases where profile.permissionSetting(permission, for: origin) != nil {
                    profile.setPermissionSetting(nil, for: permission, origin: origin)
                }
                try? await profile.clearSiteData([.permissions, .httpAuthCredentials], for: origin)
            }
        }
    }

    func openTest(_ path: String, server: String = "http://127.0.0.1:8766/") async -> (any WebContents)? {
        guard let page = await open(URL(string: server + path)!) else {
            SpikeRunner.record("error", "no page for \(path)")
            return nil
        }
        try? await Task.sleep(for: .milliseconds(400))
        return page
    }

    func dialogName(_ dialog: PageDialog?) -> String {
        switch dialog {
        case .alert?: "alert"
        case .confirm?: "confirm"
        case .prompt?: "prompt"
        case .beforeUnload?: "beforeunload"
        case .auth?: "auth"
        case .certificate?: "certificate"
        case nil: "none"
        }
    }

    func waitForDialog() async -> String {
        _ = await waitUntil(8) { self.prompts.visibleDialog != nil }
        try? await Task.sleep(for: .milliseconds(250))
        return dialogName(prompts.visibleDialog?.dialog)
    }

    func pressReturn() { sendKey("\r", keyCode: 36, []) }
    func pressEscape() { sendKey("\u{1b}", keyCode: 53, []) }

    /// Who has the keyboard: the dialog's panel, a field in it, the page.
    private var responderName: String {
        guard let responder = window.firstResponder else { return "nil" }
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView {
            return "field " + (field.accessibilityIdentifier().isEmpty ? String(describing: Swift.type(of: field)) : field.accessibilityIdentifier())
        }
        return String(describing: Swift.type(of: responder))
    }

    // MARK: Captures

    /// Asks the script for a capture of the window (`screen`: of the window's
    /// screen rect, so the popover and menus show) and waits for it.
    private func capture(_ name: String, screen: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures") else { return }
        let full = "phase-2.6a-\(name)-\(appearanceSuffix)"
        if screen {
            // The menu is a window of its own: the window's screen rect (Room is in front).
            let frame = window.frame
            let top = (NSScreen.screens.first?.frame.height ?? 0) - frame.maxY
            SpikeRunner.record("capture_screen", "\(full) \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        } else {
            SpikeRunner.record("capture", full)
        }
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + full)
        if !(await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }) { SpikeRunner.record("capture_timeout", full) }
    }

    // MARK: JavaScript dialogs and beforeunload

    func dialogsCheck() async {
        guard let page = await openTest("dialogs.html") else { return }
        let results = { await self.js(page, "JSON.stringify(window.__results)") }

        Task { await self.click(page, "#confirm") }
        SpikeRunner.record("confirm_dialog", await waitForDialog() + " responder=\(responderName)")
        await capture("js-dialog")
        pressReturn()
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil }
        Task { await self.click(page, "#confirm") }
        _ = await waitForDialog()
        pressEscape()
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil }

        Task { await self.click(page, "#prompt") }
        SpikeRunner.record("prompt_dialog", await waitForDialog() + " responder=\(responderName)")
        type("Grace")
        pressReturn()
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil }

        Task { await self.click(page, "#alert") }
        SpikeRunner.record("alert_dialog", await waitForDialog())
        pressEscape()
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil }
        try? await Task.sleep(for: .milliseconds(300))
        // Expected: confirm true (Return), confirm false (Esc), the typed prompt, the alert acknowledged.
        SpikeRunner.record("dialog_results", await results())
        SpikeRunner.record("focus_after_dialogs", responderName)

        // beforeunload: the page arms it after a click (Chrome asks only after a user gesture).
        await click(page, "#arm")
        _ = await waitUntil(3) { page.title == "Dialogs (armed)" }
        let entry = tabs.entryID(for: page)
        sendKey("w", keyCode: 13, [.command])
        SpikeRunner.record("beforeunload_on_close", await waitForDialog())
        await capture("beforeunload")
        pressEscape()
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil && self.session.current === page }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("beforeunload_stay", "page in card=\(session.current === page) entry kept=\(tabs.entryID(for: page) == entry)")
        sendKey("w", keyCode: 13, [.command])
        _ = await waitForDialog()
        pressReturn()
        let closed = await waitUntil(5) { self.tabs.entryID(for: page) == nil }
        SpikeRunner.record("beforeunload_leave", "page closed=\(closed)")
    }

    // MARK: HTTP auth

    func authCheck() async {
        let start = ContinuousClock.now
        guard let page = session.newPage(URL(string: Self.server + "auth")!) else { return }
        _ = await waitForDialog()
        var challenge = "after \(Int(ms(since: start))) ms: \(dialogName(prompts.visibleDialog?.dialog))"
        if case .auth(let value)? = prompts.visibleDialog?.dialog {
            challenge += " realm=\(value.realm ?? "nil") scheme=\(value.scheme) origin=\(value.origin.absoluteString)"
        }
        challenge += " pending for page=\(prompts.hasPending(ObjectIdentifier(page))) page in card=\(session.current === page)"
        SpikeRunner.record("auth_sheet", challenge + " responder=\(responderName)")
        await capture("auth-sheet")
        type("room")
        sendKey("\t", keyCode: 48, [])
        type("secret")
        pressReturn()
        _ = await waitUntil(8) { page.title == "Signed in as room" }
        SpikeRunner.record("auth_result", "title=\(page.title ?? "nil")")
    }

    // MARK: Certificate errors

    func certificateCheck() async {
        let url = URL(string: Self.secureServer + "secure.html")!
        guard let first = session.newPage(url) else { SpikeRunner.record("error", "no page for first"); return }
        let entry = tabs.entryID(for: first)
        var state = await waitForDialog()
        if case .certificate(let error)? = prompts.visibleDialog?.dialog {
            state += " code=\(error.code) \(error.description) overridable=\(error.isOverridable) chain=\(error.certificateChain.count)"
        }
        // 2.6a carry-over (b): the row reads the host while the interstitial shows.
        state += " row title=\(entry.flatMap { store.entry($0)?.liveTitle } ?? "nil")"
        SpikeRunner.record("certificate_interstitial", state)
        await captureB("certificate-interstitial-row")
        pressReturn()  // Go Back is the default
        _ = await waitUntil(5) { self.prompts.visibleDialog == nil }
        try? await Task.sleep(for: .milliseconds(800))
        // B-25: nothing to go back to: the page goes, the entry stays (titled with the host), the card shows the empty state.
        let emptyState = AppDelegate.current?.pageHostContainer?.pageView?.accessibilityIdentifier() ?? "nil"
        SpikeRunner.record("certificate_go_back", "entry kept=\(entry.flatMap { store.entry($0) } != nil) page closed=\(first.state == .closed) "
            + "row title=\(entry.flatMap { store.entry($0)?.liveTitle } ?? "nil") card=\(emptyState) selected=\(sidebar.selectedEntryID == entry)")
        await captureB("certificate-go-back-empty-state")

        guard let page = session.newPage(url) else { SpikeRunner.record("error", "no page for page"); return }
        _ = await waitForDialog()
        button(titled: "Show Details", in: presenter?.dialogView)?.performClick(nil)
        try? await Task.sleep(for: .milliseconds(300))
        await capture("certificate-interstitial")
        let proceed = button(identifier: "certificate-proceed", in: presenter?.dialogView)
        SpikeRunner.record("certificate_proceed_offered", proceed != nil)
        proceed?.performClick(nil)
        _ = await waitUntil(8) { page.title == "Self-signed page" }
        SpikeRunner.record("certificate_proceed", "title=\(page.title ?? "nil") security=\(page.securityState)")
    }

    // MARK: Permissions

    func permissionsCheck() async {
        guard let page = await openTest("permissions.html") else { return }
        func ask(_ selector: String, answer identifier: String, capturing name: String? = nil) async -> String {
            Task { await self.click(page, selector) }
            guard await waitUntil(8, { self.prompts.visiblePermission != nil }) else { return "no prompt" }
            try? await Task.sleep(for: .milliseconds(400))
            let kinds = prompts.visiblePermission?.requests.map { "\($0.kind)" }.joined(separator: "+") ?? ""
            let shown = presenter?.permissionView?.window?.isVisible == true
            // A window capture takes in the window's child windows: the popover, and nothing of other apps.
            if let name { await capture(name) }
            let buttonView = button(identifier: identifier, in: presenter?.permissionView)
            buttonView?.performClick(nil)
            _ = await waitUntil(5) { self.prompts.visiblePermission == nil }
            return "kinds=\(kinds) popover=\(shown) answered=\(buttonView != nil)"
        }
        SpikeRunner.record("permission_location", await ask("#geo", answer: "permission-allow", capturing: "permission-popover"))
        SpikeRunner.record("permission_notifications", await ask("#notify", answer: "permission-deny"))
        try? await Task.sleep(for: .milliseconds(800))
        SpikeRunner.record("permission_states", await js(page, Self.permissionStatesScript))
        // B-26: the answers are the profile's, not the page's: after a reload
        // the page reads them back, and a denied permission asks no more.
        page.reload()
        await waitLoaded(page)
        SpikeRunner.record("permission_states_after_reload", await js(page, Self.permissionStatesScript))
        Task { await self.click(page, "#notify") }
        let asked = await waitUntil(3) { self.prompts.visiblePermission != nil }
        SpikeRunner.record("permission_notifications_remembered", "prompt=\(asked) page=\(await js(page, "document.getElementById('log').textContent"))")
        SpikeRunner.record("permission_camera", await ask("#camera", answer: "permission-allow-once"))
        try? await Task.sleep(for: .milliseconds(1500))
        // The page mirrors its results into #log (RoomCore's scripts see the DOM, not the page's globals: B-55).
        SpikeRunner.record("permission_page_results", await js(page, "document.getElementById('log').textContent"))
    }

    /// `navigator.permissions.query` for the fixture's two permissions, as the
    /// page sees them (works in the main world and in RoomCore's isolated one).
    static let permissionStatesScript = """
        (async () => { const out = {}; for (const name of ['geolocation', 'notifications']) \
        { out[name] = (await navigator.permissions.query({ name })).state; } return JSON.stringify(out); })()
        """

    // MARK: File choosers

    func filesCheck() async {
        guard let page = await openTest("files.html") else { return }
        for selector in ["#image", "#docs", "#folder"] {
            Task { await self.click(page, selector) }
            let shown = await waitUntil(5) { self.window.attachedSheet != nil }
            var state = "sheet=\(shown)"
            if let panel = window.attachedSheet as? NSOpenPanel {
                state += " types=\(panel.allowedContentTypes.map(\.identifier)) multiple=\(panel.allowsMultipleSelection) "
                    + "folders=\(panel.canChooseDirectories) files=\(panel.canChooseFiles)"
                panel.cancel(nil)
            }
            _ = await waitUntil(3) { self.window.attachedSheet == nil }
            try? await Task.sleep(for: .milliseconds(400))
            SpikeRunner.record("file_chooser_\(selector.dropFirst())", state)
        }
    }

    // MARK: Context menus

    func contextMenuCheck() async {
        guard let page = await openTest("menu.html") else { return }
        let presentMenu = chrome.presentMenu
        defer { chrome.presentMenu = presentMenu }
        let driver = MenuDriver()
        chrome.presentMenu = { menu, point, view in driver.show(menu, at: point, in: view) }

        // A link: Room's items first; Open Link in New Tab opens it below the page.
        let before = store.today(space: sidebar.activeSpaceID).count
        driver.onOpen = { [weak self] menu in
            SpikeRunner.record("context_menu_link", menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | "))
            self?.requestMenuCapture(driver, name: "context-menu")
        }
        driver.choose = 0
        await rightClick(page, "#link")
        _ = await waitUntil(8) { driver.closed }
        _ = await waitUntil(5) { self.store.today(space: self.sidebar.activeSpaceID).count > before }
        let today = store.today(space: sidebar.activeSpaceID)
        let index = today.firstIndex { $0.id == tabs.entryID(for: page) }
        SpikeRunner.record("context_menu_open_link", "today \(before)→\(today.count) below page=\(index.map { today.indices.contains($0 + 1) && today[$0 + 1].currentURL?.hasSuffix("dialogs.html") == true } ?? false) selected stays=\(session.current === page)")

        // An image: its items; closed without a choice (the engine hears cancel).
        let image = MenuDriver()
        chrome.presentMenu = { menu, point, view in image.show(menu, at: point, in: view) }
        image.onOpen = { menu in
            SpikeRunner.record("context_menu_image", menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | "))
            // The main queue does not drain while a menu tracks: close it from the timer itself.
            menu.menu.cancelTracking()
        }
        await rightClick(page, "#image")
        _ = await waitUntil(8) { image.closed }
        SpikeRunner.record("context_menu_image_closed", image.closed)
        if let recorder = DelegateRecorder.active {
            SpikeRunner.record("context_menu_image_element", recorder.lastDetail("willShowContextMenu") ?? "nil")
        }

        // 3.4a: one of the engine's own commands (Chrome's Copy Link
        // Address, IDC_CONTENT_CONTEXT_COPYLINKLOCATION) runs in the engine.
        let copy = MenuDriver()
        chrome.presentMenu = { menu, point, view in copy.show(menu, at: point, in: view) }
        copy.chooseTag = 50104
        copy.onOpen = { menu in
            copy.offered = menu.menu.item(withTag: 50104) != nil
            copy.finish()
        }
        NSPasteboard.general.clearContents()
        await rightClick(page, "#link")
        _ = await waitUntil(8) { copy.closed }
        _ = await waitUntil(3) { NSPasteboard.general.string(forType: .string) != nil }
        SpikeRunner.record("context_menu_engine_command", "offered=\(copy.offered) pasteboard=\(NSPasteboard.general.string(forType: .string) ?? "nil")")
        if let recorder = DelegateRecorder.active {
            SpikeRunner.record("context_menu_link_element", recorder.lastDetail("willShowContextMenu") ?? "nil")
        }

        // A misspelled word in a field: Chrome's spelling suggestions and
        // dictionary actions are the engine's items (focus first: the
        // checker marks a field's words once it is focused).
        await click(page, "#misspelled")
        try? await Task.sleep(for: .milliseconds(1500))
        let spelling = MenuDriver()
        chrome.presentMenu = { menu, point, view in spelling.show(menu, at: point, in: view) }
        spelling.onOpen = { menu in
            SpikeRunner.record("context_menu_misspelled", menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | "))
            menu.menu.cancelTracking()
        }
        await rightClick(page, "#misspelled")
        _ = await waitUntil(8) { spelling.closed }
        if let recorder = DelegateRecorder.active {
            SpikeRunner.record("context_menu_misspelled_element", recorder.lastDetail("willShowContextMenu") ?? "nil")
        }
        // Only the host's menus were on screen: no window of Chrome's menu runner is left.
        SpikeRunner.record("context_menu_windows", NSApp.windows.filter(\.isVisible).map { String(describing: Swift.type(of: $0)) }.joined(separator: ","))
    }

    /// The capture handshake from inside the menu's tracking loop (a timer
    /// in the common modes runs while the menu tracks), then the choice.
    private func requestMenuCapture(_ driver: MenuDriver, name: String) {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures") else { return driver.finish() }
        let full = "phase-2.6a-\(name)-\(appearanceSuffix)"
        let frame = window.frame
        let top = (NSScreen.screens.first?.frame.height ?? 0) - frame.maxY
        SpikeRunner.record("capture_screen", "\(full) \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        driver.waitForFile(output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + full))
    }

    /// A right-click with real mouse events on the page's view (the renderer
    /// asks for its context menu; `PageDriver`). The menu's tracking loop runs
    /// later, from the engine's callback.
    private func rightClick(_ page: any WebContents, _ selector: String) async {
        guard let point = await PageDriver.center(of: selector, in: page, "right-click \(selector)") else { return }
        Task { PageDriver.click(page, at: point, button: .rightMouseDown, "right-click \(selector)") }
    }

    // MARK: Popups

    func popupsCheck() async {
        guard let page = await openTest("popups.html") else { return }
        let before = store.today(space: sidebar.activeSpaceID).count
        await click(page, "#popup")
        _ = await waitUntil(5) { self.store.today(space: self.sidebar.activeSpaceID).count > before }
        let child = session.current
        if let child { await waitLoaded(child) }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("popup_window_open", "today \(before)→\(store.today(space: sidebar.activeSpaceID).count) selected=\(child !== page) title=\(child?.title ?? "nil") opener messages=\(await js(page, "JSON.stringify(window.__messages)"))")
        if let child, child !== page {
            await click(child, "#close")
            let closed = await waitUntil(5) { self.tabs.entryID(for: child) == nil }
            SpikeRunner.record("popup_window_close", "entry closed=\(closed) today=\(store.today(space: sidebar.activeSpaceID).count)")
        }
        if let entry = tabs.entryID(for: page) { sidebar.select(entry) }
        try? await Task.sleep(for: .milliseconds(300))
        let before2 = store.today(space: sidebar.activeSpaceID).count
        await click(page, "#blank")
        _ = await waitUntil(5) { self.store.today(space: self.sidebar.activeSpaceID).count > before2 }
        if let blank = session.current { await waitLoaded(blank) }
        SpikeRunner.record("popup_target_blank", "today \(before2)→\(store.today(space: sidebar.activeSpaceID).count) title=\(session.current?.title ?? "nil")")
    }

    // MARK: View lookup

    func button(titled title: String, in root: NSView?) -> NSButton? {
        findView(in: root) { ($0 as? NSButton)?.title == title } as? NSButton
    }

    func button(identifier: String, in root: NSView?) -> NSButton? {
        findView(in: root) { $0.accessibilityIdentifier() == identifier } as? NSButton
    }

    private func findView(in root: NSView?, where match: (NSView) -> Bool) -> NSView? {
        guard let root else { return nil }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if match(view) { return view }
            queue += view.subviews
        }
        return nil
    }
}

/// Pops a context menu up and drives it from inside its tracking loop: a
/// timer in the common modes runs while the menu tracks.
@MainActor
final class MenuDriver {
    var onOpen: ((ContextMenu) -> Void)?
    /// The item to choose (by index) once captured; `nil` closes without a choice.
    var choose: Int?
    /// The item to choose by tag (the engine's command id), when set.
    var chooseTag: Int?
    /// Whether the item to choose by tag was in the menu.
    var offered = false
    private(set) var closed = false
    private var menu: ContextMenu?
    private var timer: Timer?

    func show(_ menu: ContextMenu, at point: NSPoint, in view: NSView) {
        self.menu = menu
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let opened = Timer(timeInterval: 0.5, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onOpen?(menu) }
                }
                RunLoop.main.add(opened, forMode: .common)
                menu.popUp(at: point, in: view)
                self.closed = true
            }
        }
    }

    /// Waits for the capture script's acknowledgement, then finishes.
    func waitForFile(_ url: URL) {
        let start = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, FileManager.default.fileExists(atPath: url.path) || Date().timeIntervalSince(start) > 20 else { return }
                self.timer?.invalidate()
                self.timer = nil
                self.finish()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Chooses `choose` (if any) and closes the menu.
    func finish() {
        guard let menu else { return }
        if let chooseTag {
            let index = menu.menu.indexOfItem(withTag: chooseTag)
            if index >= 0 { menu.menu.performActionForItem(at: index) }
        } else if let choose, menu.menu.items.indices.contains(choose) {
            menu.menu.performActionForItem(at: choose)
        }
        menu.menu.cancelTracking()
    }
}
#endif
