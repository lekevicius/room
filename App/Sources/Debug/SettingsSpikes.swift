#if DEBUG
import AppKit
import Chrome
import Design
import Engine
import Model
import Omnibox
import Sidebar
import Store
import UIKitCore

/// Phase 4.4a spike `settings` (`scripts/settings-check.sh`, tour step
/// `settings`): two launches on one state, `-RoomSpikeOnly set` then `verify`.
///
/// `set`: 1. the defaults (menu, reserved set); 2. Pin (⌘D) remapped to ⌥⌘P
/// in Settings ▸ Shortcuts by a real key press into the row's recorder: the
/// stored override, the menu item, the palette's hint, the sidebar's context
/// menu; 3. on the `keys` page (1.4's fixture: every keydown it sees is in
/// the DOM) the old ⌘D reaches the page and pins nothing, ⌥⌘P pins; 4. a
/// conflict (⌘P, Print's) marks both rows, Cancel keeps both, the prompt's
/// confirmation moves the key; macOS's keys refused; 5. a reserved action
/// (Reopen Closed Tab, ⇧⌘T) remapped to ⌥⌘T: ⇧⌘T now reaches the page and
/// reopens nothing, ⌥⌘T never reaches the page and reopens the closed tab;
/// 6. every General, Search, Downloads and Appearance setting set through the
/// store, applied where it shows (toolbar, sidebar side, the palette's engine
/// and keyword); 7. the save panel per download (needs the 2.6 server on
/// :8766): a chosen file, then a cancelled panel.
/// `verify` (the relaunch): every setting read back, the remapped keys in the
/// menu and the reserved set, then Reset All and the settings put back.
/// `appicon` (Chapter 5, on its own): Settings ▸ Appearance with an alternate
/// icon chosen, the Dock's image checked and captured as
/// `app-icon-picker-<light|dark>.png` (`-RoomSpikeAppearance`), then Room's own
/// again; Dusk is left stored, so a second run on the state reads it applied at launch.
extension SpikeRunner.Context {
    private var settingsApp: AppDelegate? { AppDelegate.current }

    static let spikeEngine = SearchEngineSetting(id: "custom-spike", name: "Spike Search", keyword: "spk",
                                                 searchURL: "http://127.0.0.1:8770/site.html?q={searchTerms}")
    static let spikeDownloads = "/tmp/room-4/settings-downloads"

    /// The values phase `set` stores and phase `verify` reads back (each away from its default).
    static func spikeSettings(_ settings: inout Settings, profile: UUID?) {
        settings.permanentCloseBehavior = .switchOnly
        settings.archiveAfterHours = 24
        settings.peekOffSiteLinks = false
        settings.routeLinksBetweenSpaces = true
        settings.showsToolbar = true
        settings.sidebarSide = .right
        settings.appearance = .dark
        settings.searchSuggestions = false
        settings.searchEngines = SearchEngines.list(settings).filter { $0.id != spikeEngine.id } + [spikeEngine]
        if let profile { settings.searchEngineByProfile = [profile.uuidString: spikeEngine.id] }
        settings.downloadDirectory = spikeDownloads
        settings.askWhereToSave = true
        settings.pdfsOpenInRoom = false
    }

    func settingsChecks() async {
        guard let app = settingsApp, let store = app.store, let sidebar = app.sidebar else {
            return SpikeRunner.record("error", "settings: no store or sidebar")
        }
        switch UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "set" {
        case "verify": await settingsVerify(app: app, store: store)
        case "appicon": await settingsAppIcon(app: app, store: store)
        default: await settingsSet(app: app, store: store, sidebar: sidebar)
        }
    }

    // MARK: Helpers

    /// The main menu item of action `id`: its key as the menu shows it.
    func menuKey(_ id: String) -> String {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.identifier?.rawValue == id { return item }
                if let submenu = item.submenu, let found = find(submenu) { return found }
            }
            return nil
        }
        guard let menu = NSApp.mainMenu, let item = find(menu) else { return "missing" }
        return describe(item)
    }

    func describe(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "none" }
        var modifiers = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
        var key = item.keyEquivalent
        let unshifted = Dictionary(uniqueKeysWithValues: MenuKey.shiftedUS.map { ($1, $0) })
        if let base = unshifted[key] {
            key = base
            modifiers.insert(.shift)
        } else if key != key.lowercased() {
            key = key.lowercased()
            modifiers.insert(.shift)
        }
        return ReservedShortcuts.Shortcut(.character(key), modifiers).description
    }

    /// A key press the way the window would get it: through the application when Room is
    /// active and `target` is key, else straight to the window (the Claude app may be in front).
    @discardableResult
    func press(_ characters: String, ignoring: String? = nil, code: UInt16, _ flags: NSEvent.ModifierFlags, in target: NSWindow) -> String {
        let viaApp = NSApp.isActive && target.isKeyWindow
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: target.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: ignoring ?? characters, isARepeat: false, keyCode: code)
            else { continue }
            if viaApp {
                NSApp.sendEvent(event)
            } else if type == .keyDown {
                if !target.performKeyEquivalent(with: event) { target.firstResponder?.keyDown(with: event) }
            } else {
                target.firstResponder?.keyUp(with: event)
            }
        }
        return viaApp ? "app" : "window"
    }

    /// The page's keydown log (keys.html) after `count` entries.
    func pageKeys(_ page: any WebContents, after count: Int) async -> [String] {
        // The engine answers the script's value as JSON: here a string holding the array's JSON.
        let json = await js(page, "JSON.stringify(JSON.parse(document.documentElement.dataset.keys || '[]').slice(\(count)))")
        let inner = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed) as? String) ?? json
        return (try? JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String]) ?? []
    }

    /// Settings at `section` as a PNG in the capture directory (evidence, not an assertion).
    func captureSettings(_ app: AppDelegate, _ section: SettingsWindowController.Section, _ name: String, file: String? = nil) async {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
              let settingsWindow = app.debugSettingsWindow, let window = settingsWindow.window else { return }
        settingsWindow.select(section)
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))
        let url = URL(fileURLWithPath: directory).appending(path: file ?? "phase-4.4a-settings-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        window.displayIfNeeded()
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    func pageKeyCount(_ page: any WebContents) async -> Int {
        Int(await js(page, "JSON.parse(document.documentElement.dataset.keys || '[]').length")) ?? 0
    }

    // MARK: set

    private func settingsSet(app: AppDelegate, store: RoomStore, sidebar: SidebarController) async {
        let pin = "togglePin:", reopen = "reopenClosedTab:", print = "printPage:"
        typealias Shortcut = ReservedShortcuts.Shortcut
        func reserved() -> Set<Shortcut> { app.pageDelegate?.reservedKeys ?? [] }
        let optionP = Shortcut(.character("p"), [.command, .option]), optionT = Shortcut(.character("t"), [.command, .option])
        let shiftT = Shortcut(.character("t"), [.command, .shift])
        SpikeRunner.record("defaults", "overrides=\(store.settings.settings.shortcutOverrides.count) pin=\(menuKey(pin)) reopen=\(menuKey(reopen)) "
            + "reserved=\(reserved().count) has ⇧⌘T=\(reserved().contains(shiftT))")

        // 1. The keys page in a Today tab.
        guard let page = await open(SpikeRunner.page("keys.html")), let entryID = tabs.currentEntryID else {
            return SpikeRunner.record("error", "settings: keys.html did not open")
        }
        try? await Task.sleep(for: .milliseconds(400))

        // 2. Settings ▸ Shortcuts: a real key press into Pin's recorder.
        app.showSettings(nil)
        guard let settingsWindow = app.debugSettingsWindow, let window = settingsWindow.window else {
            return SpikeRunner.record("error", "settings: no Settings window")
        }
        settingsWindow.select(.shortcuts)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let shortcuts = settingsWindow.shortcuts
        let recording = shortcuts.startRecording(pin)
        let pressed = ContinuousClock.now
        let path = press("π", ignoring: "p", code: 35, [.command, .option], in: window)
        _ = await waitUntil(3) { store.settings.settings.shortcutOverrides[pin] != nil && self.menuKey(pin) == "⌥⌘P" }
        let toMenu = ContinuousClock.now - pressed
        SpikeRunner.record("remap_timing", String(format: "key press → stored and in the menu %.1f ms (polled every 20 ms); menu apply %.2f ms",
                                                  Double(toMenu.components.attoseconds) / 1e15 + Double(toMenu.components.seconds) * 1000,
                                                  app.lastShortcutsApplyMilliseconds))
        let paletteHint = app.paletteCommands().first { $0.id == CommandRegistry.pinTab.id }?.shortcut ?? "none"
        let contextItem = sidebar.debugContextMenu(for: entryID)?.items.first { $0.title == "Pin Tab" }
        SpikeRunner.record("remap_pin", "recording=\(recording) via=\(path) stored=\(store.settings.settings.shortcutOverrides[pin] ?? "none") "
            + "menu=\(menuKey(pin)) palette command=\(paletteHint) sidebar=\(contextItem.map(describe) ?? "missing")")
        // The palette's row for the command, as drawn.
        window.orderOut(nil)
        self.window.makeKeyAndOrderFront(nil)
        if let palette = app.palette {
            palette.toggleNew()
            palette.setText(">pin")
            try? await Task.sleep(for: .milliseconds(300))
            let row = palette.debugRows.first { $0.title == "Pin Tab" }
            SpikeRunner.record("palette_hint", "row=\(row?.title ?? "missing") hint=\(row?.hint ?? "none")")
            palette.toggleNew()
            if palette.isOpen { press("\u{1b}", code: 53, [], in: self.window) }
        }

        // 3. The old ⌘D reaches the page and pins nothing; ⌥⌘P pins.
        try? await Task.sleep(for: .milliseconds(300))
        sidebar.select(entryID)
        // A click in the page gives its document the keyboard (1.4's keys spike does the same).
        await click(page, "#t")
        focusPage(page)
        var before = await pageKeyCount(page)
        let viaD = press("d", code: 2, [.command], in: self.window)
        try? await Task.sleep(for: .milliseconds(600))
        let sawD = await pageKeys(page, after: before)
        SpikeRunner.record("old_key", "via=\(viaD) page saw=\(sawD) reached the page=\(sawD.contains("⌘d/KeyD")) "
            + "kind=\(store.sidebar.entry(entryID)?.kind.rawValue ?? "gone")")
        focusPage(page)
        before = await pageKeyCount(page)
        press("π", ignoring: "p", code: 35, [.command, .option], in: self.window)
        let pinned = await waitUntil(3) { store.sidebar.entry(entryID)?.kind == .pinned }
        let sawP = await pageKeys(page, after: before)
        SpikeRunner.record("new_key", "pinned=\(pinned) page saw=\(sawP)")
        focusPage(page)
        press("π", ignoring: "p", code: 35, [.command, .option], in: self.window)
        let unpinned = await waitUntil(3) { store.sidebar.entry(entryID)?.kind == .today }
        SpikeRunner.record("new_key_again", "unpinned=\(unpinned)")
        SpikeRunner.record("key_log", (app.pageDelegate?.keyLog.suffix(8) ?? []).joined(separator: " | "))

        // 4. A conflict, then refusals.
        let check = shortcuts.propose(Shortcut(.character("p"), .command), for: pin)
        let marked = shortcuts.markedIDs.sorted()
        SpikeRunner.record("conflict", "check=\(check) pending=\(shortcuts.pending != nil) marked=\(marked) message=\(shortcuts.message)")
        shortcuts.reveal(pin)
        await captureSettings(app, .shortcuts, "shortcuts-conflict")
        app.debugSettingsWindow?.window?.orderOut(nil)
        self.window.makeKeyAndOrderFront(nil)
        shortcuts.cancelPending()
        SpikeRunner.record("conflict_cancel", "pin=\(menuKey(pin)) print=\(menuKey(print)) marked=\(shortcuts.markedIDs.count)")
        shortcuts.propose(Shortcut(.character("p"), .command), for: pin)
        shortcuts.confirmPending()
        _ = await waitUntil(2) { self.menuKey(pin) == "⌘P" }
        SpikeRunner.record("conflict_resolved", "pin=\(menuKey(pin)) print=\(menuKey(print)) conflicts=\(app.shortcutTable.conflicts.count) "
            + "message=\(shortcuts.message)")
        shortcuts.reset(print)
        shortcuts.propose(optionP, for: pin)
        _ = await waitUntil(2) { self.menuKey(print) == "⌘P" && self.menuKey(pin) == "⌥⌘P" }
        var refusals: [String] = []
        for key in [Shortcut(.character("q"), .command), Shortcut(.character("h"), .command), Shortcut(.character("k"), [])] {
            if case .refused(let reason) = shortcuts.propose(key, for: pin) { refusals.append("\(key): \(reason)") } else { refusals.append("\(key): accepted") }
        }
        let quit = shortcuts.propose(optionT, for: "terminate:")
        SpikeRunner.record("refused", refusals.joined(separator: " | ") + " | Quit to ⌥⌘T: \(quit) | pin=\(menuKey(pin)) print=\(menuKey(print))")

        // 5. A reserved action under a new key.
        shortcuts.propose(optionT, for: reopen)
        _ = await waitUntil(2) { self.menuKey(reopen) == "⌥⌘T" }
        SpikeRunner.record("reserved_set", "has ⌥⌘T=\(reserved().contains(optionT)) has ⇧⌘T=\(reserved().contains(shiftT)) count=\(reserved().count) "
            + "menu=\(menuKey(reopen))")
        if let other = await open(SpikeRunner.page("audio.html")), let otherID = tabs.currentEntryID {
            _ = other
            sidebar.select(otherID)
            sidebar.closeCommandTargets()
            _ = await waitUntil(3) { store.sidebar.entry(otherID) == nil }
            sidebar.select(entryID)
            try? await Task.sleep(for: .milliseconds(300))
            let count = store.sidebar.entries.count
            await click(page, "#t")
            focusPage(page)
            before = await pageKeyCount(page)
            let viaShiftT = press("T", code: 17, [.command, .shift], in: self.window)
            try? await Task.sleep(for: .milliseconds(800))
            let sawShiftT = await pageKeys(page, after: before)
            let reopenedByOld = store.sidebar.entries.count > count
            focusPage(page)
            before = await pageKeyCount(page)
            press("†", ignoring: "t", code: 17, [.command, .option], in: self.window)
            let reopened = await waitUntil(3) { store.sidebar.entries.count > count }
            try? await Task.sleep(for: .milliseconds(500))
            let reopenedCount = store.sidebar.entries.count - count
            let sawOptionT = await pageKeys(page, after: before)
            SpikeRunner.record("reserved_remap", "via=\(viaShiftT) ⇧⌘T page saw=\(sawShiftT) reopened by ⇧⌘T=\(reopenedByOld) "
                + "⌥⌘T page saw=\(sawOptionT) reopened by ⌥⌘T=\(reopened) tabs reopened=\(reopenedCount)")
            SpikeRunner.record("key_log_reserved", (app.pageDelegate?.keyLog.suffix(6) ?? []).joined(separator: " | "))
        } else {
            SpikeRunner.record("error", "settings: audio.html did not open")
        }

        // 6. Every other setting through the store, applied where it shows.
        let profile = store.sidebar.space(sidebar.activeSpaceID)?.profileID
        store.settings.update { Self.spikeSettings(&$0, profile: profile) }
        try? await Task.sleep(for: .milliseconds(500))
        let engine = app.palette?.searchEngine()
        var keyword = "none"
        if let palette = app.palette {
            palette.toggleNew()
            palette.setText("spk")
            try? await Task.sleep(for: .milliseconds(300))
            keyword = palette.result.matches.first { $0.title == "Search Spike Search" }?.detail ?? "none"
            palette.toggleNew()
        }
        app.showSettings(nil)
        for (section, name) in [(SettingsWindowController.Section.general, "general"), (.search, "search"), (.downloads, "downloads")] {
            await captureSettings(app, section, name)
        }
        app.debugSettingsWindow?.window?.orderOut(nil)
        self.window.makeKeyAndOrderFront(nil)
        SpikeRunner.record("applied", "toolbar=\(app.windowController?.showsToolbar ?? false) sidebar=\(app.windowController?.rootView.sidebarEdge == .right ? "right" : "left") "
            + "palette engine=\(engine?.name ?? "nil") keyword row=\(keyword) suggestions=\(store.settings.settings.searchSuggestions)")

        // 7. The save panel per download (the 2.6 server).
        try? FileManager.default.removeItem(atPath: Self.spikeDownloads)
        try? FileManager.default.createDirectory(atPath: Self.spikeDownloads, withIntermediateDirectories: true)
        if let downloads = app.downloads {
            // The reopened tab took the card: the keys page again, for its gesture.
            sidebar.select(entryID)
            try? await Task.sleep(for: .milliseconds(500))
            let list = downloads.list
            tabs.engineProfile(for: page)?.downloadsDelegate = list
            func trigger(_ name: String) async {
                _ = await PageDriver.evaluateWithGesture(page, "const a=document.createElement('a');a.href='http://127.0.0.1:8766/download?name=\(name)&size=2000';"
                    + "document.body.append(a);a.click();0", "download \(name)")
            }
            func panel() async -> NSSavePanel? {
                _ = await waitUntil(8) { NSApp.windows.contains { $0 is NSSavePanel && $0.isVisible } }
                return NSApp.windows.compactMap { $0 as? NSSavePanel }.first { $0.isVisible }
            }
            await trigger("spike-ask.bin")
            if let shown = await panel() {
                let proposed = shown.nameFieldStringValue
                SpikeRunner.record("save_panel", "shown=true sheet=\(shown.sheetParent != nil) proposed=\(proposed) in=\(shown.directoryURL?.path ?? "nil")")
                // As the panel's Save button ends it (`ok:` on the in-process panel raised, and its fields
                // set from code are not what it answers: 4.4a); the file is the panel's answer.
                if let parent = shown.sheetParent { parent.endSheet(shown, returnCode: .OK) } else { shown.ok(nil) }
                let answered = shown.url
                let done = await waitUntil(10) { list.rows.contains { $0.destination == answered && $0.item.state == .complete } }
                SpikeRunner.record("save_panel_ok", "answered=\(answered?.lastPathComponent ?? "nil") complete=\(done) "
                    + "file=\(answered.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) rows=\(list.rows.count)")
            } else {
                SpikeRunner.record("save_panel", "shown=false (the 2.6 server on :8766?)")
            }
            let rowsBefore = list.rows.count
            await trigger("spike-cancel.bin")
            if let shown = await panel() {
                if let parent = shown.sheetParent { parent.endSheet(shown, returnCode: .cancel) } else { shown.cancel(nil) }
                try? await Task.sleep(for: .milliseconds(1500))
                SpikeRunner.record("save_panel_cancel", "rows \(rowsBefore) → \(list.rows.count) listed=\(list.rows.contains { $0.item.suggestedFilename.contains("spike-cancel") })")
            } else {
                SpikeRunner.record("save_panel_cancel", "shown=false")
            }
        }
        store.flush()
        SpikeRunner.record("stored", "overrides=\(store.settings.settings.shortcutOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })")
    }

    // MARK: appicon (Chapter 5)

    private func settingsAppIcon(app: AppDelegate, store: RoomStore) async {
        let dark = NSApp.effectiveAppearance.isDark
        // A second run on the same state shows the choice applied at launch.
        SpikeRunner.record("dock_at_launch", "choice=\(store.settings.settings.appIcon.rawValue) applied=\(app.debugAppliedAppIcon ?? "bundle")")
        store.settings.update { $0.appIcon = .dusk }
        try? await Task.sleep(for: .milliseconds(300))
        let rendition = AppIconImages.image(.dusk, dark: dark)
        SpikeRunner.record("dock_alternate", "choice=\(store.settings.settings.appIcon.rawValue) dark=\(dark) "
            + "rendered=\(rendition != nil) applied=\(app.debugAppliedAppIcon ?? "bundle")")
        let missing = AppIconChoice.allCases.flatMap { choice in [false, true].map { (choice, $0) } }
            .filter { AppIconImages.url($0.0, dark: $0.1) == nil }.map { AppIconImages.resourceName($0.0, dark: $0.1) }
        SpikeRunner.record("rendered_pngs", "\(AppIconChoice.allCases.count * 2 - missing.count) of \(AppIconChoice.allCases.count * 2) missing=\(missing)")
        app.showSettings(nil)
        // The pane renders before the capture's own 400 ms (a blank capture under load otherwise).
        app.debugSettingsWindow?.select(.appearance)
        try? await Task.sleep(for: .seconds(2))
        let file = "app-icon-picker-\(dark ? "dark" : "light").png"
        await captureSettings(app, .appearance, "appicon", file: file)
        // With the display asleep or the screen locked the window server's capture is blank:
        // the pane drawn in process too (no toolbar, no materials).
        if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
           let view = app.debugSettingsWindow?.window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appending(path: file.replacingOccurrences(of: ".png", with: "-drawn.png"))
            SpikeRunner.record("capture_appicon_drawn", (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil ? url.lastPathComponent : "failed")
        }
        app.debugSettingsWindow?.window?.orderOut(nil)
        store.settings.update { $0.appIcon = .room }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("dock_room", "choice=\(store.settings.settings.appIcon.rawValue) applied=\(app.debugAppliedAppIcon ?? "bundle")")
        // Dusk again, stored for the next run's launch.
        store.settings.update { $0.appIcon = .dusk }
        store.flush()
    }

    // MARK: verify (the relaunch)

    private func settingsVerify(app: AppDelegate, store: RoomStore) async {
        let current = store.settings.settings
        var expected = current
        let profile = store.sidebar.space(app.sidebar?.activeSpaceID ?? UUID())?.profileID
        Self.spikeSettings(&expected, profile: profile)
        let fields: [(String, Bool, String)] = [
            ("permanentCloseBehavior", current.permanentCloseBehavior == expected.permanentCloseBehavior, current.permanentCloseBehavior.rawValue),
            ("archiveAfterHours", current.archiveAfterHours == expected.archiveAfterHours, "\(current.archiveAfterHours)"),
            ("peekOffSiteLinks", current.peekOffSiteLinks == expected.peekOffSiteLinks, "\(current.peekOffSiteLinks)"),
            ("routeLinksBetweenSpaces", current.routeLinksBetweenSpaces == expected.routeLinksBetweenSpaces, "\(current.routeLinksBetweenSpaces)"),
            ("showsToolbar", current.showsToolbar == expected.showsToolbar, "\(current.showsToolbar)"),
            ("sidebarSide", current.sidebarSide == expected.sidebarSide, current.sidebarSide.rawValue),
            ("appearance", current.appearance == expected.appearance, current.appearance.rawValue),
            ("searchSuggestions", current.searchSuggestions == expected.searchSuggestions, "\(current.searchSuggestions)"),
            ("searchEngines", current.searchEngines == expected.searchEngines, "\(SearchEngines.list(current).count) engines, last \(SearchEngines.list(current).last?.keyword ?? "-")"),
            ("searchEngineByProfile", current.searchEngineByProfile == expected.searchEngineByProfile, "\(current.searchEngineByProfile.values.sorted())"),
            ("downloadDirectory", current.downloadDirectory == expected.downloadDirectory, current.downloadDirectory ?? "nil"),
            ("askWhereToSave", current.askWhereToSave == expected.askWhereToSave, "\(current.askWhereToSave)"),
            ("pdfsOpenInRoom", current.pdfsOpenInRoom == expected.pdfsOpenInRoom, "\(current.pdfsOpenInRoom)"),
        ]
        SpikeRunner.record("relaunch", fields.map { "\($0.0)=\($0.2)\($0.1 ? "" : " (MISMATCH)")" }.joined(separator: " "))
        SpikeRunner.record("relaunch_equal", "\(fields.allSatisfy(\.1)) (\(fields.filter(\.1).count) of \(fields.count))")
        SpikeRunner.record("relaunch_applied", "toolbar=\(app.windowController?.showsToolbar ?? false) sidebar=\(app.windowController?.rootView.sidebarEdge == .right ? "right" : "left") "
            + "palette engine=\(app.palette?.searchEngine().name ?? "nil")")
        let optionT = ReservedShortcuts.Shortcut(.character("t"), [.command, .option])
        let shiftT = ReservedShortcuts.Shortcut(.character("t"), [.command, .shift])
        let reserved = app.pageDelegate?.reservedKeys ?? []
        SpikeRunner.record("relaunch_keys", "pin=\(menuKey("togglePin:")) reopen=\(menuKey("reopenClosedTab:")) print=\(menuKey("printPage:")) "
            + "reserved has ⌥⌘T=\(reserved.contains(optionT)) has ⇧⌘T=\(reserved.contains(shiftT))")

        // Reset All in Settings ▸ Shortcuts.
        app.showSettings(nil)
        guard let shortcuts = app.debugSettingsWindow?.shortcuts else { return SpikeRunner.record("error", "settings: no Settings window") }
        app.debugSettingsWindow?.select(.shortcuts)
        shortcuts.resetAll()
        _ = await waitUntil(2) { self.menuKey("togglePin:") == "⌘D" }
        let after = app.pageDelegate?.reservedKeys ?? []
        SpikeRunner.record("reset_all", "overrides=\(store.settings.settings.shortcutOverrides.count) pin=\(menuKey("togglePin:")) "
            + "reopen=\(menuKey("reopenClosedTab:")) reserved has ⇧⌘T=\(after.contains(shiftT)) has ⌥⌘T=\(after.contains(optionT)) "
            + "equals the defaults=\(after == Set(ReservedShortcuts.all))")
        app.debugSettingsWindow?.window?.orderOut(nil)

        // The settings back to their defaults for the steps after this one.
        let defaults = Settings()
        store.settings.update {
            $0.permanentCloseBehavior = defaults.permanentCloseBehavior
            $0.archiveAfterHours = defaults.archiveAfterHours
            $0.peekOffSiteLinks = defaults.peekOffSiteLinks
            $0.routeLinksBetweenSpaces = defaults.routeLinksBetweenSpaces
            $0.showsToolbar = defaults.showsToolbar
            $0.sidebarSide = defaults.sidebarSide
            $0.appearance = defaults.appearance
            $0.searchSuggestions = defaults.searchSuggestions
            $0.searchEngines = defaults.searchEngines
            $0.searchEngineByProfile = defaults.searchEngineByProfile
            $0.downloadDirectory = defaults.downloadDirectory
            $0.askWhereToSave = defaults.askWhereToSave
            $0.pdfsOpenInRoom = defaults.pdfsOpenInRoom
        }
        store.flush()
        SpikeRunner.record("restored", "defaults=\(store.settings.settings.searchEngines == nil && !store.settings.settings.askWhereToSave)")
    }
}
#endif
