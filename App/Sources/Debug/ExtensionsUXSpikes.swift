#if DEBUG
import AppKit
import Chrome
import Engine
import Model
import UIKitCore

/// Phase 4.5 spike `extux` (`Room -RoomSpike extux`; the tour's step
/// `extensions` through `scripts/extensions-check.sh`, with the test
/// servers): the unpacked 3.6 fixture (`research/spikes/phase-3.6/extension`,
/// since 4.5 with activeTab, a host permission for 127.0.0.1 and a named
/// command that fetches one local URL) and a second unpacked extension made
/// in the run's state directory. Sections (`-RoomSpikeOnly` picks):
/// `engine` site access on the fixture page (On click: the content script
/// waits for Run; On this site across a reload), the commands, ⇧⌘U and
/// ⇧⌘Y with the sidebar focused (B-70); `header` pin/unpin and the
/// overflow menu; `sitepanel` the site panel's Extensions section (B-30);
/// `pages` the options page in a space of the extension's profile with two
/// profiles (B-67), the shortcuts page, Settings ▸ Shortcuts' rows.
extension SpikeRunner.Context {
    static let extuxPage = URL(string: "http://127.0.0.1:8770/site.html")!

    func extensionsUXChecks() async {
        guard let app = AppDelegate.current, let center = app.extensions, let section = center.sections.first else {
            return SpikeRunner.record("extux", "skipped: the engine has no extensions")
        }
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        let id: String
        do {
            id = try await section.extensions.loadUnpacked(at: fixture)
        } catch {
            return SpikeRunner.record("error", "load unpacked: \(error)")
        }
        _ = await waitUntil(5) { center.sections.first?.installed.first { $0.id == id }?.action?.icon != nil }
        let item = center.sections.first?.installed.first { $0.id == id }
        SpikeRunner.record("fixture", "id=\(id) pinned=\(item?.isPinned ?? false) hosts=\(item?.hostPermissions ?? []) "
            + "directory=\(item?.directory?.path ?? "nil")")
        guard let page = await open(Self.extuxPage) else { return SpikeRunner.record("error", "no fixture page") }
        let ran = await contentScriptRan(page, within: 5)
        SpikeRunner.record("content_script_default", "ran=\(ran)")
        if runs("engine") { await extuxEngine(center: center, section: section, id: id, page: page) }
        if runs("header") { await extuxHeader(center: center, section: section, id: id, page: page) }
        if runs("sitepanel") { await extuxSitePanel(app: app, center: center, section: section, id: id, page: page) }
        if runs("pages") { await extuxPages(app: app, center: center, id: id) }
    }

    /// A PNG of `window` in the capture directory (evidence, not an assertion).
    func captureExtux(_ window: NSWindow?, _ name: String) {
        guard let window, let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.5-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        window.displayIfNeeded()
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: header: pin/unpin, the overflow menu

    func extuxHeader(center: ExtensionsCenter, section: ExtensionsCenter.ProfileSection, id: String, page: any WebContents) async {
        let field = session.sidebar.addressField
        // A second unpacked extension with an action (made in the run's state directory).
        let root = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomStateDirectory") ?? NSTemporaryDirectory())
            .appending(path: "second-extension", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "Room 4.5 second", "version": "1.0", "action": {"default_title": "Second"}}"#
        try? manifest.write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
        guard let second = try? await section.extensions.loadUnpacked(at: root) else { return SpikeRunner.record("error", "second extension not loaded") }
        let ids = { field.extensionActionIDs.map { $0 == id ? "fixture" : $0 == second ? "second" : $0 } }
        _ = await waitUntil(5) { field.extensionActionIDs.count == 2 }
        SpikeRunner.record("header_initial", "buttons=\(ids()) overflow=\(field.overflowActionIDs.count) overflow_button=\(field.overflowButtonView != nil)")
        // Unpin the fixture (Settings ▸ Extensions' Unpin): the header keeps the second, the overflow menu lists the fixture with its badge.
        guard let fixture = center.sections.first?.installed.first(where: { $0.id == id }) else { return }
        center.setPinned(false, fixture, in: section)
        _ = await waitUntil(5) { field.extensionActionIDs == [second] && field.overflowActionIDs == [id] }
        // The badge is the page's (the content script's "T<n>").
        _ = await waitUntil(5) { !(center.overflowActions(profile: section.id, page: page).first?.badgeText ?? "").isEmpty }
        let menu = field.overflowMenu()
        let titles = menu.items.map { $0.attributedTitle?.string ?? $0.title }
        SpikeRunner.record("header_unpinned", "buttons=\(ids()) overflow=\(field.overflowActionIDs.map { $0 == id ? "fixture" : $0 }) "
            + "overflow_button=\(field.overflowButtonView != nil) menu=\(titles) badge=\(center.overflowActions(profile: section.id, page: page).first?.badgeText ?? "nil")")
        captureExtux(window, "header-overflow")
        // A click on the overflow item runs the action: its popup points at the overflow button.
        let events = installPopupHooks()
        let before = events.shown.count
        let start = ContinuousClock.now
        if let index = menu.items.firstIndex(where: { ($0.representedObject as? String) == id && $0.title != "Pin" }) {
            menu.performActionForItem(at: index)
        }
        let shown = await waitUntil(8) { events.shown.count > before }
        let anchoredOnOverflow = field.extensionButton(for: id) != nil && field.extensionButton(for: id) === field.overflowButtonView
        SpikeRunner.record("overflow_run", String(format: "popover=%@ in %.0f ms anchored_on_overflow=%@ shown_id=%@", "\(shown)", ms(since: start),
                                                  "\(anchoredOnOverflow)", events.shown.last?.id == id ? "fixture" : "\(events.shown.last?.id ?? "nil")"))
        if shown {
            capturePopupOverWindow("phase-4.5-overflow-popup", popover: events.popover)
            _ = await closePopupWithEsc(events)
        }
        ExtensionPopups.debugOnShow = nil
        ExtensionPopups.debugOnResize = nil
        ExtensionPopups.debugOnClose = nil
        // The menu's Pin: the fixture comes back at the header's end (ToolbarActionsModel's order).
        let pinMenu = field.overflowMenu()
        if let index = pinMenu.items.firstIndex(where: { ($0.representedObject as? String) == id && $0.title == "Pin" }) {
            pinMenu.performActionForItem(at: index)
        }
        _ = await waitUntil(5) { field.extensionActionIDs == [second, id] }
        SpikeRunner.record("header_repinned", "buttons=\(ids()) overflow=\(field.overflowActionIDs.count) overflow_button=\(field.overflowButtonView != nil) "
            + "installed_order=\((center.sections.first?.installed ?? []).map { $0.id == id ? "fixture" : $0.id == second ? "second" : $0.name })")
        // Back to one button for the later sections.
        if let item = center.sections.first?.installed.first(where: { $0.id == second }) {
            center.setPinned(false, item, in: section)
        }
    }

    // MARK: sitepanel: the Extensions section (B-30)

    func extuxSitePanel(app: AppDelegate, center: ExtensionsCenter, section: ExtensionsCenter.ProfileSection, id: String,
                        page: any WebContents) async {
        await activate()
        center.setSiteAccess(.onClick, id, profile: section.id, host: "127.0.0.1")
        await reloadAndWait(page)
        let ranBefore = await contentScriptRan(page, within: 3)
        if app.sitePanel.isShown { app.sitePanel.close() }
        app.showSitePanel()
        _ = await waitUntil(3) { app.sitePanel.isShown }
        guard let model = app.sitePanel.model?.extensions else { return SpikeRunner.record("error", "site panel: no Extensions section") }
        _ = await waitUntil(3) { model.rows.first { $0.id == id }?.access.wantsToRun == true }
        let row = { model.rows.first { $0.id == id } }
        SpikeRunner.record("site_panel_section", "rows=\(model.rows.map { $0.id == id ? "fixture" : $0.name }) host=\(model.host) "
            + "level=\(row()?.access.level.rawValue ?? -1) run_shown=\(row()?.access.wantsToRun ?? false) ran_before_run=\(ranBefore)")
        try? await Task.sleep(for: .milliseconds(400))
        captureExtux(app.sitePanel.contentView?.window, "site-panel-run")
        let start = ContinuousClock.now
        model.run(id)
        let ran = await contentScriptRan(page, within: 5)
        SpikeRunner.record("site_panel_run", String(format: "ran=%@ in %.0f ms ran_here=%@ keep_offered=%@", "\(ran)", ms(since: start),
                                                    "\(model.ranHere.contains(id))",
                                                    "\(model.ranHere.contains(id) && row()?.access.level == .onClick)"))
        try? await Task.sleep(for: .milliseconds(400))
        captureExtux(app.sitePanel.contentView?.window, "site-panel-after-run")
        // "Always on 127.0.0.1" (the row's offer after Run): remembered across reloads.
        model.setAccess(.onSite, for: id)
        app.sitePanel.close()
        var reloads: [Bool] = []
        for _ in 0..<2 {
            await reloadAndWait(page)
            reloads.append(await contentScriptRan(page, within: 5))
        }
        SpikeRunner.record("site_panel_on_site", "ran_after_reloads=\(reloads) level=\(center.siteAccess(id, profile: section.id, page: page)?.level.rawValue ?? -1) "
            + "wants_to_run=\(center.siteAccess(id, profile: section.id, page: page)?.wantsToRun ?? true)")
        // The Settings popup's path for the shown page's host: back to On all sites.
        let all = center.setSiteAccess(.onAllSites, id, profile: section.id, host: "127.0.0.1")
        SpikeRunner.record("site_access_all", "set=\(all) level=\(center.siteAccess(id, profile: section.id, page: page)?.level.rawValue ?? -1)")
    }

    // MARK: pages: B-67 with two profiles, the shortcuts page, Settings

    func extuxPages(app: AppDelegate, center: ExtensionsCenter, id: String) async {
        guard let section = center.sections.first, let item = section.installed.first(where: { $0.id == id }) else { return }
        // A second profile with a space, shown: the extension is the first profile's.
        guard let work = app.newProfile(named: "Work"), let office = try? store.createSpace(name: "Office", profile: work.id) else {
            return SpikeRunner.record("error", "pages: no Work profile")
        }
        session.sidebar.showSpace(office.id, animated: false)
        _ = await waitUntil(3) { session.sidebar.activeSpaceID == office.id }
        let before = Set(store.spaces.flatMap { store.today(space: $0.id).map(\.id) })
        center.openOptions(item, in: section)
        _ = await waitUntil(5) { session.sidebar.activeSpaceID != office.id }
        let shownSpace = store.space(session.sidebar.activeSpaceID)
        let newEntry = store.today(space: session.sidebar.activeSpaceID).first { !before.contains($0.id) }
        var state = "nil"
        var pageProfile = "nil"
        if let newEntry, await waitUntil(10, { session.tabs.contents(for: newEntry.id) != nil }), let options = session.tabs.contents(for: newEntry.id) {
            await waitLoaded(options)
            for _ in 0..<25 {
                state = await js(options, "document.getElementById('state') ? document.getElementById('state').textContent : ''")
                if state.contains("storage written") { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            let engine = session.tabs.engineProfile(for: options)
            pageProfile = session.tabs.engineProfiles.first { $0.value === engine }.map { $0.key == section.id ? "extension's" : "other" } ?? "unknown"
        }
        SpikeRunner.record("options_page", "profiles=\(store.profiles.count) shown_before=Office shown_after=\(shownSpace?.name ?? "nil") "
            + "space_profile=\(shownSpace?.profileID == section.id ? "extension's" : "other") url=\(newEntry?.currentURL ?? "nil") "
            + "page_profile=\(pageProfile) page_state=\(state)")
        // A profile without a space: an extension page makes an "Extensions" space for it.
        if let spare = app.newProfile(named: "Spare") {
            let count = store.spaces.count
            app.openExtensionPage(URL(string: "chrome://extensions/")!, profile: spare.id)
            _ = await waitUntil(5) { store.spaces.count > count }
            let made = store.spaces.first { $0.profileID == spare.id }
            SpikeRunner.record("extension_page_new_space", "made=\(made?.name ?? "nil") shown=\(made?.id == session.sidebar.activeSpaceID)")
        }
        // Keyboard Shortcuts…: Chrome's page as a tab of the extension's profile.
        center.openShortcutsPage(in: section)
        _ = await waitUntil(5) { store.space(session.sidebar.activeSpaceID)?.profileID == section.id }
        var shortcutsURL = "nil"
        var shortcutsTitle = "nil"
        if let entry = store.today(space: session.sidebar.activeSpaceID).last(where: { ($0.currentURL ?? "").contains("shortcuts") }),
           await waitUntil(10, { session.tabs.contents(for: entry.id) != nil }), let page = session.tabs.contents(for: entry.id) {
            await waitLoaded(page)
            _ = await waitUntil(5) { !(page.title ?? "").isEmpty }
            shortcutsURL = page.url?.absoluteString ?? "nil"
            shortcutsTitle = page.title ?? "nil"
        }
        SpikeRunner.record("shortcuts_page", "url=\(shortcutsURL) title=\(shortcutsTitle) space_profile=\(store.space(session.sidebar.activeSpaceID)?.profileID == section.id ? "extension's" : "other")")
        // Settings ▸ Shortcuts' read-only rows and Settings ▸ Extensions.
        app.showSettings(section: .shortcuts)
        try? await Task.sleep(for: .milliseconds(600))
        let rows = app.debugSettingsWindow?.shortcuts.extensionRows ?? []
        SpikeRunner.record("settings_shortcut_rows", rows.map { "\($0.extensionName): \($0.title) \($0.shortcut) conflicts=\($0.conflicts)" }.joined(separator: "; "))
        captureExtux(app.debugSettingsWindow?.window, "settings-shortcuts")
        app.showSettings(section: .extensions)
        try? await Task.sleep(for: .milliseconds(800))
        captureExtux(app.debugSettingsWindow?.window, "settings-extensions")
        // "Allow in incognito" is stored per profile (4.8b reads it).
        app.store?.settings.update { $0.setAllowsInIncognito(true, id, profile: section.id) }
        SpikeRunner.record("incognito_setting", "stored=\(app.store?.settings.settings.allowsInIncognito(id, profile: section.id) ?? false) "
            + "other_profile=\(app.store?.settings.settings.allowsInIncognito(id, profile: work.id) ?? true)")
        app.debugSettingsWindow?.window?.orderOut(nil)
    }

    /// The fixture's content script marks the page (`data-room-fixture36`).
    func contentScriptRan(_ page: any WebContents, within seconds: Double) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        repeat {
            if await js(page, "document.documentElement.dataset.roomFixture36 || ''").contains("content-script-ran") { return true }
            try? await Task.sleep(for: .milliseconds(200))
        } while ContinuousClock.now < deadline
        return false
    }

    func reloadAndWait(_ page: any WebContents) async {
        page.reload()
        try? await Task.sleep(for: .milliseconds(300))
        await waitLoaded(page)
    }

    private func describe(_ access: ExtensionSiteAccess?) -> String {
        guard let access else { return "nil" }
        let selectable = ExtensionSiteAccess.Level.allCases.filter { access.selectable.contains($0) }.map { "\($0)" }
        return "level=\(access.level) selectable=\(selectable) wantsSite=\(access.wantsSite) canAffect=\(access.canAffect) wantsToRun=\(access.wantsToRun)"
    }

    /// The sidebar's list takes the keyboard (what a click on a row does).
    func focusSidebarList() -> String {
        func outline(in view: NSView) -> NSOutlineView? {
            if let found = view as? NSOutlineView { return found }
            for child in view.subviews { if let found = outline(in: child) { return found } }
            return nil
        }
        guard let content = window.contentView, let list = outline(in: content) else { return "no list" }
        window.makeFirstResponder(list)
        return window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil"
    }

    // MARK: engine: site access, Run, commands with the sidebar focused

    func extuxEngine(center: ExtensionsCenter, section: ExtensionsCenter.ProfileSection, id: String, page: any WebContents) async {
        let engine = section.extensions
        SpikeRunner.record("access_default", describe(engine.siteAccess(for: page, extension: id)))
        // On click: the content script waits for Run.
        let setClick = engine.setSiteAccess(.onClick, for: id, host: "127.0.0.1")
        await reloadAndWait(page)
        let ranOnClick = await contentScriptRan(page, within: 3)
        SpikeRunner.record("access_on_click", "set=\(setClick) ran_after_reload=\(ranOnClick) \(describe(engine.siteAccess(for: page, extension: id)))")
        let start = ContinuousClock.now
        let run = engine.runAction(for: id, in: page)
        let ranAfterRun = await contentScriptRan(page, within: 5)
        SpikeRunner.record("access_run", String(format: "run=%@ ran=%@ in %.0f ms; %@", "\(run)", "\(ranAfterRun)", ms(since: start),
                                                describe(engine.siteAccess(for: page, extension: id))))
        // On this site: runs at once after a reload, twice.
        let setSite = engine.setSiteAccess(.onSite, for: id, host: "127.0.0.1")
        var reloads: [Bool] = []
        for _ in 0..<2 {
            await reloadAndWait(page)
            reloads.append(await contentScriptRan(page, within: 5))
        }
        SpikeRunner.record("access_on_site", "set=\(setSite) ran_after_reloads=\(reloads) \(describe(engine.siteAccess(for: page, extension: id)))")
        // Commands, then the keys with the sidebar's list focused.
        let commands = engine.commands(for: id)
        SpikeRunner.record("commands", commands.map { "\($0.name)=\($0.shortcut.isEmpty ? "none" : $0.shortcut)\($0.isAction ? " action" : "")" }
            .joined(separator: " "))
        await activate()
        let responder = focusSidebarList()
        try? await Task.sleep(for: .milliseconds(300))
        let titleBefore = engine.action(for: id, in: nil)?.title ?? ""
        let keyStart = ContinuousClock.now
        PageDriver.key(window, characters: "U", charactersIgnoringModifiers: "u", keyCode: 32, modifiers: [.command, .shift])
        let commanded = await waitUntil(8) { (engine.action(for: id, in: nil)?.title ?? "").hasPrefix("command:room-named") }
        SpikeRunner.record("command_sidebar_named", String(format: "first_responder=%@ page_has_keyboard=%@ routed=%@ onCommand=%@ in %.0f ms title_before=\"%@\" title=\"%@\"",
                                                           responder, "\(AppDelegate.current?.pageHasKeyboard ?? true)",
                                                           "\(AppDelegate.current?.extensionKeys?.lastRouted.map { "\($0.shortcut) \($0.handled)" } ?? "nil")",
                                                           "\(commanded)", ms(since: keyStart), titleBefore,
                                                           engine.action(for: id, in: nil)?.title ?? "nil"))
        let events = installPopupHooks()
        _ = focusSidebarList()
        let shownBefore = events.shown.count
        let actionStart = ContinuousClock.now
        PageDriver.key(window, characters: "Y", charactersIgnoringModifiers: "y", keyCode: 16, modifiers: [.command, .shift])
        let popup = await waitUntil(8) { events.shown.count > shownBefore }
        SpikeRunner.record("command_sidebar_action", String(format: "popover=%@ in %.0f ms routed=%@", "\(popup)", ms(since: actionStart),
                                                            "\(AppDelegate.current?.extensionKeys?.lastRouted.map { "\($0.shortcut) \($0.handled)" } ?? "nil")"))
        if popup { _ = await closePopupWithEsc(events) }
        ExtensionPopups.debugOnShow = nil
        ExtensionPopups.debugOnResize = nil
        ExtensionPopups.debugOnClose = nil
        // A key no extension has goes on to the menu (⇧⌘C: Copy URL's toast).
        _ = focusSidebarList()
        PageDriver.key(window, characters: "C", charactersIgnoringModifiers: "c", keyCode: 8, modifiers: [.command, .shift])
        SpikeRunner.record("command_sidebar_other_key", "routed=\(AppDelegate.current?.extensionKeys?.lastRouted.map { "\($0.shortcut) \($0.handled)" } ?? "nil") "
            + "(⇧⌘C is not an extension's: the menu has it)")
    }
}
#endif
