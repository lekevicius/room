#if DEBUG
import AppKit
import Engine

/// Phase 3.7a: `passwords` and `autofill` (`scripts/passwords-autofill.sh`)
/// drive Chrome's password manager and autofill on Room.app over RoomCore
/// through real events only: typing and clicks on the page (`PageDriver`),
/// Return on Chrome's Views bubbles (their default button), Down and Return
/// on the page for the suggestion popups (the keys reach the popup through
/// the page's `RenderWidgetHost` key-press handlers). The fixtures are
/// `research/spikes/phase-3.7` on `http://127.0.0.1:8772` and
/// `http://localhost:8772` (two sites for the password manager) and
/// `https://127.0.0.1:8773` (cards need a secure context; the script passes
/// the certificate's SPKI hash to Chromium).
///
/// `passwords` runs in two launches on the same state and engine
/// directories: `-RoomPasswordsPhase save` (sign in on both sites and accept
/// the save bubble, change one password and accept the update bubble, the
/// sign-up page with its generation offer), then `-RoomPasswordsPhase fill`
/// (after the relaunch: each site's username field, its suggestion popup,
/// Down + Return, the values read back from the DOM, the sign-in; then
/// `chrome://password-manager`). `autofill`: the address save bubble, the
/// update bubble after an edited submit, the suggestion popup on the name
/// field (fill with Down + Return, Esc, a window move), the card save bubble
/// and the card suggestion.
///
/// `capture_screen: <name> x,y,w,h` lines ask the script for a screen
/// capture (Chrome's bubbles are windows of their own whose pixels a window
/// capture of Room's does not hold); captures go to
/// `research/screenshots/phase-3.7a/`.
extension SpikeRunner.Context {
    // MARK: Fixtures

    static let siteA = "http://127.0.0.1:8772"
    static let siteB = "http://localhost:8772"
    static let secureSite = "https://127.0.0.1:8773"

    var shots37: URL {
        let url = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? SpikeRunner.pagesDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "screenshots/phase-3.7a")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func prepare37() async {
        SpikeRunner.record("window_id", window.windowNumber)
        // Room's window in the middle of the screen, so a bubble that opens to
        // the left of the site button stays on the screen.
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.center()
        controller.sidebarWidth = 280
        await activate()
    }

    // MARK: Chrome's windows

    /// Chrome's Views windows that take the mouse: bubbles and popups (the
    /// window's modal anchor ignores the mouse and is fully transparent).
    private func chromeWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && NSStringFromClass(Swift.type(of: $0)).contains("NativeWidget") && !$0.ignoresMouseEvents }
    }

    private func waitForChromeWindow(excluding before: Set<ObjectIdentifier>, _ seconds: Double) async -> NSWindow? {
        var found: NSWindow?
        _ = await waitUntil(seconds) {
            found = self.chromeWindows().first { !before.contains(ObjectIdentifier($0)) && $0.frame.width > 20 }
            return found != nil
        }
        return found
    }

    private var keyWindowName: String {
        guard let key = NSApp.keyWindow else { return "none" }
        return key === window ? "room" : NSStringFromClass(Swift.type(of: key))
    }

    private var chromeWindowIDs: Set<ObjectIdentifier> { Set(chromeWindows().map(ObjectIdentifier.init)) }

    /// Top-left global coordinates (what `screencapture -R` takes).
    private func topLeft(_ rect: NSRect) -> NSRect {
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primary - rect.maxY, width: rect.width, height: rect.height)
    }

    private func describe(_ rect: NSRect) -> String {
        let r = topLeft(rect)
        return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
    }

    /// The site button's frame on the screen (AppKit coordinates).
    private var siteButtonScreenRect: NSRect? {
        let button = session.sidebar.addressField.siteButtonView
        guard let buttonWindow = button.window else { return nil }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Where a bubble sits against the site button: the gap from the button's
    /// bottom edge to the bubble's top edge, and whether the bubble spans the
    /// button horizontally (Chrome's arrow points at the anchor's centre).
    private func anchorRelation(_ bubble: NSWindow) -> String {
        guard let button = siteButtonScreenRect else { return "site button not in a window" }
        let gap = button.minY - bubble.frame.maxY
        let spans = bubble.frame.minX - 1 <= button.midX && button.midX <= bubble.frame.maxX + 1
        return "site_button=\(describe(button)) bubble=\(describe(bubble.frame)) gap_below_button=\(Int(gap))pt spans_button=\(spans)"
    }

    /// A screen capture of Room's window and `extra` (a bubble that reaches
    /// past it), answered by the script.
    private func captureScreen37(_ name: String, including extra: NSWindow? = nil) async {
        var rect = window.frame
        if let extra { rect = rect.union(extra.frame) }
        let r = topLeft(rect)
        let full = "phase-3.7a-\(name)"
        SpikeRunner.record("capture_screen", "\(full) \(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))")
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + full)
        if !(await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }) { SpikeRunner.record("capture_timeout", full) }
    }

    /// Return to Chrome's bubble (its default button: Save, Update), the
    /// bubble made key first; a click on the default button's place when
    /// Return did not close it. Which one worked is the result.
    private func acceptBubble(_ bubble: NSWindow) async -> String {
        bubble.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(150))
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: bubble.windowNumber, context: nil, characters: "\r",
                                            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                bubble.sendEvent(event)
            }
        }
        if await waitUntil(3, { !bubble.isVisible }) { return "return" }
        // The default button is the trailing one at the bubble's bottom (Views' Mac button order).
        let point = NSPoint(x: bubble.frame.width - 52, y: 32)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: bubble.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                bubble.sendEvent(event)
            }
        }
        if await waitUntil(3, { !bubble.isVisible }) { return "click" }
        return "still open"
    }

    // MARK: Typing and keys on the page

    private static let keyCodes37: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49,
        "@": 19, "+": 24,
    ]

    /// Real key presses into whatever has the page's keyboard focus.
    private func typeOnPage(_ text: String) async {
        for character in text {
            let lower = Character(character.lowercased())
            let shifted = character.isUppercase || "@+".contains(character)
            sendKey(window, characters: String(character), charactersIgnoringModifiers: shifted ? String(character) : String(lower),
                    keyCode: Self.keyCodes37[lower] ?? 0, modifiers: shifted ? [.shift] : [])
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    private enum PageKey { case down, enter, escape, tab }

    private func pressOnPage(_ key: PageKey) {
        switch key {
        case .down: sendKey(window, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, modifiers: [.function, .numericPad])
        case .enter: sendKey(window, characters: "\r", keyCode: 36)
        case .escape: sendKey(window, characters: "\u{1b}", keyCode: 53)
        case .tab: sendKey(window, characters: "\t", keyCode: 48)
        }
    }

    /// Empties the field (Chrome may have filled it on load), clicks it (a
    /// real click: focus and a user gesture) and types.
    private func fill(_ page: any WebContents, _ selector: String, _ text: String) async {
        _ = await js(page, "(() => { const e = document.querySelector('\(selector)'); if (e) e.value = ''; return 0 })()")
        await click(page, selector)
        try? await Task.sleep(for: .milliseconds(120))
        await typeOnPage(text)
    }

    private func values(_ page: any WebContents, _ ids: [String]) async -> [String: String] {
        let list = ids.map { "'\($0)'" }.joined(separator: ",")
        let json = await js(page, "Object.fromEntries([\(list)].map(id => [id, document.getElementById(id) ? document.getElementById(id).value : '(none)']))")
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: String] else {
            SpikeRunner.record("error", "field values: \(json.prefix(120))")
            return [:]
        }
        return object
    }

    /// A field's frame on the screen (AppKit coordinates), from the page's layout.
    private func fieldScreenRect(_ page: any WebContents, _ selector: String) async -> NSRect? {
        let json = await js(page, "(() => { const r = document.querySelector('\(selector)').getBoundingClientRect(); return [r.x, r.y, r.width, r.height] })()")
        guard let r = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], r.count == 4 else { return nil }
        let view = page.nativeView
        let top = view.isFlipped ? r[1] : view.bounds.height - r[1]
        let bottom = view.isFlipped ? r[1] + r[3] : view.bounds.height - r[1] - r[3]
        let a = view.convert(NSPoint(x: r[0], y: top), to: nil)
        let b = view.convert(NSPoint(x: r[0] + r[2], y: bottom), to: nil)
        let windowRect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        return window.convertToScreen(windowRect)
    }

    /// The popup against its field: Chrome opens it just below the field's
    /// bottom edge, its left edge at the field's.
    private func popupRelation(_ popup: NSWindow, field: NSRect?) -> String {
        guard let field else { return "popup=\(describe(popup.frame)) field=unknown" }
        return "popup=\(describe(popup.frame)) field=\(describe(field)) below_field_by=\(Int(field.minY - popup.frame.maxY))pt "
            + "left_offset=\(Int(popup.frame.minX - field.minX))pt"
    }

    private func openPage37(_ url: String) async -> (any WebContents)? {
        guard let page = await open(URL(string: url)!) else {
            SpikeRunner.record("error", "could not open \(url)")
            return nil
        }
        try? await Task.sleep(for: .milliseconds(400))
        return page
    }

    /// The bubble Chrome shows after `action` (a submit), with how long it took.
    private func bubbleAfter(_ name: String, _ action: () async -> Void) async -> NSWindow? {
        let before = chromeWindowIDs
        let queries = session.pageDelegate.bubbleAnchorQueries
        let start = ContinuousClock.now
        await action()
        guard let bubble = await waitForChromeWindow(excluding: before, 12) else {
            SpikeRunner.record("\(name)_bubble", "none within 12 s")
            return nil
        }
        let shownMs = ms(since: start)
        try? await Task.sleep(for: .milliseconds(500))  // Views' fade-in
        SpikeRunner.record("\(name)_bubble", String(format: "shown %.0f ms after the submit; ", shownMs) + anchorRelation(bubble)
            + " anchor_queries=\(session.pageDelegate.bubbleAnchorQueries - queries) key_window=\(keyWindowName)")
        return bubble
    }

    /// ⌘T as a typed key: the palette opens (within 2 s), Esc closes it.
    private func paletteCheck() async -> String {
        let keyBefore = keyWindowName
        sendKey(window, characters: "t", keyCode: 17, modifiers: [.command])
        let opened = await waitUntil(2) { AppDelegate.current?.palette?.isOpen ?? false }
        AppDelegate.current?.palette?.dismiss()
        try? await Task.sleep(for: .milliseconds(300))
        return "key_window=\(keyBefore) palette_opened=\(opened) closed=\(!(AppDelegate.current?.palette?.isOpen ?? false)) "
            + "palette_exists=\(AppDelegate.current?.palette != nil) app_active=\(NSApp.isActive) first_responder=\(window.firstResponder.map { NSStringFromClass(Swift.type(of: $0)) } ?? "nil") "
            + "engine_keys=\(session.keyLog.suffix(2))"
    }

    // MARK: passwords

    func passwordsChecks() async {
        await prepare37()
        switch UserDefaults.standard.string(forKey: "RoomPasswordsPhase") {
        case "fill": await passwordFillPhase()
        case "import": await passwordImportPhase()
        default:
            await passwordSavePhase()
        }
    }

    /// 4.3b (`-RoomPasswordsPhase import`): `Profile.importPasswords` on the
    /// fixtures of `research/spikes/phase-4.3`: `passwords-saved.csv` first
    /// (alice with `secret-a0`, standing for a password saved before), then
    /// `passwords.csv` with `.skip` (alice's row conflicts and is kept; bob
    /// and carol added; the malformed row skipped), then again with
    /// `.replace` (alice becomes `secret-a2`). The `fill` phase after a
    /// relaunch is the check that the imported passwords fill.
    private func passwordImportPhase() async {
        let fixtures = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-4.3")
        guard let app = AppDelegate.current, let model = app.store?.sidebar.profiles.first,
              let profile = await app.engineProfile(for: model) else {
            return SpikeRunner.record("error", "import: no engine profile")
        }
        func run(_ label: String, _ file: String, _ policy: PasswordImportConflictPolicy) async {
            guard let csv = try? String(contentsOf: fixtures.appending(path: file), encoding: .utf8) else {
                return SpikeRunner.record("error", "import: \(file) unreadable")
            }
            let start = ContinuousClock.now
            let result = await profile.importPasswords(csv: csv, conflicts: policy)
            let rows = result.rows.map { "\($0.username)@\($0.url)=\($0.reason.rawValue)" }.joined(separator: ",")
            SpikeRunner.record("import_\(label)", "status=\(result.status.rawValue) imported=\(result.imported) conflicts=\(result.conflicts) "
                + "replaced=\(result.replaced) skipped=\(result.skipped) rows=[\(rows)] " + String(format: "%.0f ms", ms(since: start)))
        }
        await run("saved", "passwords-saved.csv", .skip)
        await run("skip", "passwords.csv", .skip)
        await run("replace", "passwords.csv", .replace)
        // A second import while one runs is refused, not queued.
        let other = "url,username,password\nhttp://127.0.0.1:9/,zed,z1\n"
        let first = Task { @MainActor in await profile.importPasswords(csv: other, conflicts: .skip) }
        let second = Task { @MainActor in await profile.importPasswords(csv: other, conflicts: .skip) }
        let (a, b) = (await first.value, await second.value)
        SpikeRunner.record("import_concurrent", "first=\(a.status.rawValue) second=\(b.status.rawValue)")
        let bad = await profile.importPasswords(csv: "title,notes\nx,y\n", conflicts: .skip)
        SpikeRunner.record("import_bad_header", "status=\(bad.status.rawValue)")
    }

    private func signIn(_ page: any WebContents, _ user: String, _ password: String) async {
        await fill(page, "#username", user)
        await fill(page, "#password", password)
        await click(page, "#submit")
    }

    private func passwordSavePhase() async {
        let sites = [("a", Self.siteA, "alice", "secret-a1"), ("b", Self.siteB, "bob", "secret-b1")]
        for (name, site, user, password) in sites {
            guard let page = await openPage37("\(site)/login.html") else { continue }
            let bubble = await bubbleAfter("save_\(name)") { await self.signIn(page, user, password) }
            await waitLoaded(page)
            SpikeRunner.record("save_\(name)_page", "title=\(page.title ?? "nil") url=\(page.url?.absoluteString ?? "nil")")
            guard let bubble else { continue }
            await captureScreen37("save-bubble-\(name)", including: bubble)
            SpikeRunner.record("save_\(name)_accept", await acceptBubble(bubble))
            window.makeKeyAndOrderFront(nil)
        }
        // A changed password on site A: Chrome offers to update the saved one.
        if let page = await openPage37("\(Self.siteA)/login.html") {
            let bubble = await bubbleAfter("update_a") { await self.signIn(page, "alice", "secret-a2") }
            await waitLoaded(page)
            if let bubble {
                await captureScreen37("update-bubble-a", including: bubble)
                // The host keeps working while the bubble is up: the palette opens and closes.
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(200))
                SpikeRunner.record("update_a_host_while_bubble", await paletteCheck() + " bubble_still_up=\(bubble.isVisible)")
                if bubble.isVisible { SpikeRunner.record("update_a_accept", await acceptBubble(bubble)) }
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(300))
                SpikeRunner.record("update_a_host_after_bubble", await paletteCheck())
            }
        }
        await generationCheck()
    }

    /// The sign-up page: Chrome's generation popup on the new-password field
    /// (when Chrome offers generation), then the account saved.
    private func generationCheck() async {
        // Its own origin (the HTTPS twin), so site A's saved logins do not open a suggestion popup here.
        guard let page = await openPage37("\(Self.secureSite)/signup.html") else { return }
        await fill(page, "#username", "carol")
        let before = chromeWindowIDs
        await click(page, "#password")
        let popup = await waitForChromeWindow(excluding: before, 4)
        SpikeRunner.record("generation_popup", popup.map { "shown " + popupRelation($0, field: nil) } ?? "none within 4 s")
        if let popup {
            await captureScreen37("generation-popup", including: popup)
            pressOnPage(.down)
            try? await Task.sleep(for: .milliseconds(150))
            pressOnPage(.enter)
            try? await Task.sleep(for: .milliseconds(600))
            let v = await values(page, ["password", "confirm"])
            SpikeRunner.record("generation_fill", "password_length=\(v["password"]?.count ?? -1) confirm_matches=\(v["password"] == v["confirm"] && v["password"]?.isEmpty == false)")
        } else {
            await typeOnPage("secret-c1")
            await fill(page, "#confirm", "secret-c1")
        }
        let bubble = await bubbleAfter("save_signup") { await self.click(page, "#submit") }
        await waitLoaded(page)
        SpikeRunner.record("save_signup_page", "title=\(page.title ?? "nil")")
        if let bubble {
            await captureScreen37("save-bubble-signup", including: bubble)
            SpikeRunner.record("save_signup_accept", await acceptBubble(bubble))
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func passwordFillPhase() async {
        let sites = [("a", Self.siteA, "alice", "secret-a2"), ("b", Self.siteB, "bob", "secret-b1")]
        for (name, site, user, password) in sites {
            guard let page = await openPage37("\(site)/login.html") else { continue }
            try? await Task.sleep(for: .milliseconds(600))
            let onLoad = await values(page, ["username", "password"])
            SpikeRunner.record("fill_\(name)_on_load", "username=\(onLoad["username"] ?? "nil") password_length=\(onLoad["password"]?.count ?? -1)")
            let field = await fieldScreenRect(page, "#username")
            let before = chromeWindowIDs
            let start = ContinuousClock.now
            await click(page, "#username")
            guard let popup = await waitForChromeWindow(excluding: before, 5) else {
                SpikeRunner.record("fill_\(name)_popup", "none within 5 s")
                continue
            }
            SpikeRunner.record("fill_\(name)_popup", String(format: "shown %.0f ms after the click; ", ms(since: start)) + popupRelation(popup, field: field))
            try? await Task.sleep(for: .milliseconds(300))
            await captureScreen37("fill-popup-\(name)", including: popup)
            pressOnPage(.down)
            try? await Task.sleep(for: .milliseconds(200))
            pressOnPage(.enter)
            _ = await waitUntil(3) { !popup.isVisible }
            try? await Task.sleep(for: .milliseconds(400))
            let filled = await values(page, ["username", "password"])
            SpikeRunner.record("fill_\(name)_values", "username=\(filled["username"] ?? "nil") username_matches=\(filled["username"] == user) password_matches=\(filled["password"] == password) popup_closed=\(!popup.isVisible)")
            await click(page, "#submit")
            await waitLoaded(page)
            try? await Task.sleep(for: .milliseconds(300))
            let done = await js(page, "document.getElementById('done') ? document.getElementById('done').textContent : ''")
            SpikeRunner.record("fill_\(name)_signin", "title=\(page.title ?? "nil") text=\(done)")
            // A sign-in with a saved password: Chrome must not offer to save it again.
            if let again = chromeWindows().first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }) {
                SpikeRunner.record("fill_\(name)_bubble_after_signin", "unexpected: \(describe(again.frame))")
            }
        }
        await passwordManagerPage()
    }

    /// `chrome://password-manager` in a Room tab: the saved sites in its list.
    private func passwordManagerPage() async {
        guard let page = await openPage37("chrome://password-manager/passwords") else { return }
        try? await Task.sleep(for: .seconds(2))
        // The list lives in shadow roots (Polymer): walk them for the text.
        let script = """
        (() => { const out = []; const walk = n => { if (!n) return; if (n.shadowRoot) walk(n.shadowRoot);
          for (const c of n.children || []) walk(c); if (n.nodeType === 1 && !n.children.length && n.textContent) out.push(n.textContent.trim()); };
          walk(document.documentElement); return out.filter(t => t).join(' | ') })()
        """
        let text = await js(page, script)
        let hits = ["127.0.0.1", "localhost"].map { "\($0)=\(text.contains($0))" }.joined(separator: " ")
        SpikeRunner.record("password_manager_page", "title=\(page.title ?? "nil") url=\(page.url?.absoluteString ?? "nil") \(hits) text_chars=\(text.count)")
        if let image = await PageDriver.capture(page, "password manager"), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let file = shots37.appending(path: "phase-3.7a-password-manager.png")
            try? png.write(to: file)
            SpikeRunner.record("capture", "\(file.lastPathComponent) (page)")
        }
    }

    // MARK: autofill

    func autofillChecks() async {
        await prepare37()
        await addressSaveAndUpdate()
        await addressSuggestions()
        await cardSaveAndFill()
    }

    private static let address: [(String, String)] = [
        ("#name", "Room Fixture"), ("#street", "1600 Amphitheatre Parkway"), ("#city", "Mountain View"),
        ("#state", "CA"), ("#zip", "94043"),
    ]

    /// Types the address; the country select is reached with Tab from the ZIP
    /// field and set by typing (a click would open AppKit's menu).
    private func typeAddress(_ page: any WebContents, phone: Bool) async {
        for (selector, text) in Self.address { await fill(page, selector, text) }
        pressOnPage(.tab)
        try? await Task.sleep(for: .milliseconds(150))
        await typeOnPage("U")
        if phone { await fill(page, "#phone", "+1 650-253-0000") }
        await fill(page, "#email", "room.fixture@example.com")
    }

    private func addressSaveAndUpdate() async {
        // First submit without the phone: Chrome offers to save the address.
        if let page = await openPage37("\(Self.siteA)/address.html") {
            await typeAddress(page, phone: false)
            let bubble = await bubbleAfter("address_save") { await self.click(page, "#submit") }
            await waitLoaded(page)
            SpikeRunner.record("address_save_page", "title=\(page.title ?? "nil")")
            if let bubble {
                await captureScreen37("address-save-bubble", including: bubble)
                SpikeRunner.record("address_save_accept", await acceptBubble(bubble))
                window.makeKeyAndOrderFront(nil)
            }
        }
        // The same address with a phone number: Chrome offers to update the saved one.
        if let page = await openPage37("\(Self.siteA)/address.html") {
            await typeAddress(page, phone: true)
            let bubble = await bubbleAfter("address_update") { await self.click(page, "#submit") }
            await waitLoaded(page)
            if let bubble {
                await captureScreen37("address-update-bubble", including: bubble)
                SpikeRunner.record("address_update_accept", await acceptBubble(bubble))
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private static let addressIDs = ["name", "street", "city", "state", "zip", "country", "phone", "email"]

    private func addressSuggestions() async {
        // Fill: Down + Return on the name field's popup.
        guard let page = await openPage37("\(Self.siteA)/address.html") else { return }
        let field = await fieldScreenRect(page, "#name")
        var before = chromeWindowIDs
        let start = ContinuousClock.now
        await click(page, "#name")
        guard let popup = await waitForChromeWindow(excluding: before, 5) else {
            return SpikeRunner.record("address_popup", "none within 5 s")
        }
        SpikeRunner.record("address_popup", String(format: "shown %.0f ms after the click; ", ms(since: start)) + popupRelation(popup, field: field)
            + " class=\(NSStringFromClass(Swift.type(of: popup))) room_key=\(window.isKeyWindow)")
        try? await Task.sleep(for: .milliseconds(300))
        await captureScreen37("address-popup", including: popup)
        pressOnPage(.down)
        try? await Task.sleep(for: .milliseconds(200))
        pressOnPage(.enter)
        _ = await waitUntil(3) { !popup.isVisible }
        try? await Task.sleep(for: .milliseconds(500))
        let filled = await values(page, Self.addressIDs)
        SpikeRunner.record("address_fill", Self.addressIDs.map { "\($0)=\(filled[$0] ?? "nil")" }.joined(separator: " ") + " popup_closed=\(!popup.isVisible)")

        // Esc closes the popup.
        guard let page2 = await openPage37("\(Self.siteA)/address.html") else { return }
        before = chromeWindowIDs
        await click(page2, "#name")
        if let popup2 = await waitForChromeWindow(excluding: before, 5) {
            try? await Task.sleep(for: .milliseconds(300))
            pressOnPage(.escape)
            let closed = await waitUntil(3) { !popup2.isVisible }
            let after = await values(page2, ["name"])
            SpikeRunner.record("address_popup_escape", "closed=\(closed) name_after=\(after["name"] ?? "nil")")
        } else {
            SpikeRunner.record("address_popup_escape", "no popup to close")
        }

        // The popup and a window move.
        guard let page3 = await openPage37("\(Self.siteA)/address.html") else { return }
        before = chromeWindowIDs
        await click(page3, "#name")
        if let popup3 = await waitForChromeWindow(excluding: before, 5) {
            try? await Task.sleep(for: .milliseconds(300))
            let was = popup3.frame
            let fieldBefore = await fieldScreenRect(page3, "#name")
            var frame = window.frame
            frame.origin.x += 60
            frame.origin.y -= 40
            window.setFrame(frame, display: true)
            try? await Task.sleep(for: .milliseconds(600))
            let fieldAfter = await fieldScreenRect(page3, "#name")
            SpikeRunner.record("address_popup_window_move", "moved=+60,-40 popup_visible=\(popup3.isVisible) before=\(describe(was)) after=\(describe(popup3.frame)) "
                + "field_before=\(fieldBefore.map(describe) ?? "nil") field_after=\(fieldAfter.map(describe) ?? "nil") "
                + "any_popup_now=\(chromeWindows().filter { !before.contains(ObjectIdentifier($0)) }.map { describe($0.frame) })")
            pressOnPage(.escape)
            frame.origin.x -= 60
            frame.origin.y += 40
            window.setFrame(frame, display: true)
        } else {
            SpikeRunner.record("address_popup_window_move", "no popup")
        }
    }

    private static let cardIDs = ["cc-name", "cc-number", "cc-exp-month", "cc-exp-year", "cc-csc"]

    private func cardSaveAndFill() async {
        if let page = await openPage37("\(Self.secureSite)/card.html") {
            SpikeRunner.record("card_page_security", "\(page.securityState)")
            for (selector, text) in [("#cc-name", "Room Fixture"), ("#cc-number", "4111111111111111"), ("#cc-exp-month", "12"),
                                     ("#cc-exp-year", "2030"), ("#cc-csc", "123")] {
                await fill(page, selector, text)
            }
            let bubble = await bubbleAfter("card_save") { await self.click(page, "#submit") }
            await waitLoaded(page)
            SpikeRunner.record("card_save_page", "title=\(page.title ?? "nil")")
            if let bubble {
                await captureScreen37("card-save-bubble", including: bubble)
                SpikeRunner.record("card_save_accept", await acceptBubble(bubble))
                window.makeKeyAndOrderFront(nil)
            }
        }
        guard let page = await openPage37("\(Self.secureSite)/card.html") else { return }
        let field = await fieldScreenRect(page, "#cc-number")
        let before = chromeWindowIDs
        await click(page, "#cc-number")
        guard let popup = await waitForChromeWindow(excluding: before, 5) else {
            return SpikeRunner.record("card_popup", "none within 5 s")
        }
        SpikeRunner.record("card_popup", popupRelation(popup, field: field))
        try? await Task.sleep(for: .milliseconds(300))
        await captureScreen37("card-popup", including: popup)
        pressOnPage(.down)
        try? await Task.sleep(for: .milliseconds(200))
        pressOnPage(.enter)
        _ = await waitUntil(3) { !popup.isVisible }
        try? await Task.sleep(for: .milliseconds(800))
        // Anything Chrome asks after the fill (a CVC or re-authentication prompt) is another window.
        let others = chromeWindows().filter { !before.contains(ObjectIdentifier($0)) }
        let filled = await values(page, Self.cardIDs)
        SpikeRunner.record("card_fill", Self.cardIDs.map { "\($0)=\(filled[$0] ?? "nil")" }.joined(separator: " ")
            + " popup_closed=\(!popup.isVisible) other_chrome_windows=\(others.map { describe($0.frame) })")
        for other in others { await captureScreen37("card-after-fill", including: other) }
    }
}
#endif
