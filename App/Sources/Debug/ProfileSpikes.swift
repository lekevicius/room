#if DEBUG
import AppKit
import Engine
import Model
import Omnibox
import Store
import UIKitCore

/// Phase 4.4b spike `profiles` (`scripts/profiles-check.sh`, tour step
/// `settings2`): the three engine members and Settings ▸ Spaces & Profiles
/// and Privacy. Needs the test servers (:8765 cookies, :8766 permissions).
///
/// `engine` (the engine step's smoke run, on the engine alone): a profile
/// made, a page with a cookie in it closed, `deleteProfile` refused while the
/// page was open and the directory gone after; Clear browsing data for the
/// last hour on the default profile (an imported visit three hours old stays,
/// this hour's visit and cookie go); a permission stored through
/// `setPermissionSetting`, listed by `contentSettings(ofType:)` and read by
/// the page.
extension SpikeRunner.Context {
    static let cookiePage = "http://127.0.0.1:8765/cookies.html"
    static let permissionsPage = "http://127.0.0.1:8766/permissions.html"

    func profilesChecks() async {
        switch UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "engine" {
        case "set": await profilesSet()
        case "verify": await profilesVerify()
        default: await profilesEngine()
        }
    }

    func settleProfiles(_ milliseconds: Int = 400) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    /// Settings at `section` as a PNG in the capture directory (evidence, not an assertion).
    func captureProfiles(_ app: AppDelegate, _ section: SettingsWindowController.Section, _ name: String) async {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
              let settingsWindow = app.debugSettingsWindow, let window = settingsWindow.window else { return }
        settingsWindow.select(section)
        window.orderFront(nil)
        await settleProfiles(600)
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.4b-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        window.displayIfNeeded()
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    /// A new Today tab in the shown space, selected, once its profile's
    /// engine profile exists (a profile made this launch gets it on first use).
    func openShown(_ url: String) async -> (any WebContents)? {
        guard let entry = try? store.addEntry(.today, url: url, space: sidebar.activeSpaceID) else { return nil }
        sidebar.select(entry.id)
        guard await waitUntil(15, { session.tabs.contents(for: entry.id) != nil }), let page = session.tabs.contents(for: entry.id) else { return nil }
        await waitLoaded(page, timeout: 20)
        return page
    }

    /// The page's cookies after loading the cookie page (without `?set=`) in the shown space.
    func cookieInShownSpace() async -> String {
        guard let page = await openShown(Self.cookiePage) else { return "no page" }
        return await js(page, "document.cookie")
    }

    /// Phase `set` (first launch): a second profile with a space and a fixture
    /// cookie; spaces reordered as Settings ▸ Spaces moves them; the profile
    /// renamed through Settings' path; the routing sheet from a space's row.
    private func profilesSet() async {
        guard let app = AppDelegate.current, let tabs = app.tabs else { return SpikeRunner.record("error", "profiles: no app") }
        let services = app.profileServices()
        guard let work = app.newProfile(named: "Work"), let office = try? store.createSpace(name: "Office", profile: work.id) else {
            return SpikeRunner.record("error", "profiles: no Work profile or Office space")
        }
        SpikeRunner.record("work_profile", "id=\(work.id.uuidString) name=\(work.name)")
        // Reorder as the Settings rows' up and down buttons do; the footer follows the store.
        let before = store.spaces.map(\.name)
        try? store.moveSpace(office.id, to: 0)
        let moved = store.spaces.map(\.name)
        try? store.moveSpace(office.id, to: store.spaces.count - 1)
        SpikeRunner.record("reorder", "before=\(before) up=\(moved) back=\(store.spaces.map(\.name)) positions=\(store.spaces.map(\.position))")
        // The fixture cookie in Office (2.5's page), in Work's cookie jar.
        sidebar.showSpace(office.id, animated: false)
        guard let page = await openShown(Self.cookiePage + "?set=work") else { return SpikeRunner.record("error", "no cookie page") }
        let engineName = tabs.engineProfiles[work.id]?.name ?? "none"
        SpikeRunner.record("cookie_set", "cookie=\(await js(page, "document.cookie")) engine profile=\(engineName == work.id.uuidString ? "the id" : engineName)")
        // Rename through Settings ▸ Spaces' row: only the label changes.
        let refusal = services.rename(work.id, "Office Profile")
        let empty = services.rename(work.id, "  ")
        SpikeRunner.record("renamed", "refusal=\(refusal ?? "none") empty refused=\(empty ?? "no") name=\(store.profiles.first { $0.id == work.id }?.name ?? "?") "
            + "space profile kept=\(store.space(office.id)?.profileID == work.id)")
        SpikeRunner.record("directories_set", profileDirectories().map { $0.replacingOccurrences(of: work.id.uuidString, with: "<work id>") }.joined(separator: ", "))
        // Settings ▸ Spaces, then a space's Routing… (a new rule for it when it has none).
        app.showSettings(section: .spaces)
        await settleProfiles(600)
        await captureProfiles(app, .spaces, "spaces")
        services.routingRules(office.id)
        await settleProfiles(800)
        let settingsWindow = app.debugSettingsWindow?.window
        if let sheet = app.routingSheet, let editor = app.routingModel {
            SpikeRunner.record("space_routing", "shown=\(sheet.isVisible) on settings=\(settingsWindow?.attachedSheet === sheet) editing=\(editor.editing == .new) "
                + "target=\(store.space(editor.target ?? UUID())?.name ?? "none")")
            app.closeRoutingRules()
        } else {
            SpikeRunner.record("space_routing", "shown=false")
        }
        settingsWindow?.orderOut(nil)
        // Office stays shown: Chromium's last used profile is Work's at the quit.
        sidebar.showSpace(office.id, animated: false)
        await settleProfiles(1000)
    }

    /// Phase `verify` (the relaunch, after the wrapper put Work's directory
    /// back under its legacy name): the one-time move, the cookie, Clear
    /// browsing data for the last hour, a permission through Settings' path,
    /// a profile deleted, the palette's Settings ▸ Privacy.
    private func profilesVerify() async {
        guard let app = AppDelegate.current, let tabs = app.tabs,
              let work = store.profiles.first(where: { $0.name == "Office Profile" }),
              let office = store.spaces.first(where: { $0.name == "Office" }) else {
            return SpikeRunner.record("error", "profiles: no renamed profile or Office space")
        }
        let services = app.profileServices()
        let workID = work.id.uuidString
        let moves = EngineProfileMigration.moved.map { "\($0.from) → \($0.to.replacingOccurrences(of: workID, with: "<work id>"))" }
        SpikeRunner.record("moved_at_launch", "\(moves) local state updated=\(EngineProfileMigration.localStateUpdated)")
        let directories = profileDirectories()
        SpikeRunner.record("directories_verify", "id=\(directories.contains("Room Profile " + workID)) legacy=\(directories.contains("Room Profile Office Profile")) "
            + "all=\(directories.map { $0.replacingOccurrences(of: workID, with: "<work id>") })")
        if let root = spikeEngineRoot, let data = try? Data(contentsOf: root.appending(path: "Local State")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let profile = json["profile"] as? [String: Any] {
            let last = (profile["last_used"] as? String ?? "none").replacingOccurrences(of: workID, with: "<work id>")
            SpikeRunner.record("local_state", "last_used=\(last)")
        }
        // 1. The cookie survived the rename and the move.
        sidebar.showSpace(office.id, animated: false)
        await settleProfiles(600)
        SpikeRunner.record("cookie_after_relaunch", "cookie=\(await cookieInShownSpace()) engine profile=\(tabs.engineProfiles[work.id]?.name == workID ? "the id" : "other")")
        // 2. Clear browsing data, last hour, through Settings' path: this hour's visit and the cookie go, a visit 3 h old stays.
        if let engineProfile = await services.engineProfile(work.id), let history = engineProfile.history {
            let old = URL(string: "http://127.0.0.1:8765/page.html?old=work")!
            let fresh = URL(string: Self.cookiePage + "?set=work")!
            _ = await history.importEntries([HistoryImportEntry(url: old, title: "Old",
                                                                visits: [HistoryVisit(time: Date().addingTimeInterval(-3 * 3600), transition: .typed)])])
            let before = "fresh=\(await history.visits(for: fresh) != nil) old=\(await history.visits(for: old) != nil)"
            let start = ContinuousClock.now
            let line = await services.clearBrowsingData(work.id, [.history, .cookiesAndSiteData], .lastHour)
            let elapsed = ms(since: start)
            let toast = app.debugToastCenter?.currentToast?.message ?? "none"
            let after = "fresh=\(await history.visits(for: fresh) != nil) old=\(await history.visits(for: old) != nil)"
            SpikeRunner.record("clear_hour", "before: \(before); after: \(after) cookie=\(await cookieInShownSpace()) in \(String(format: "%.0f", elapsed)) ms; "
                + "line=\(line) toast=\(toast)")
        } else {
            SpikeRunner.record("clear_hour", "no engine history")
        }
        // 3. A permission stored through Settings' path, read by the page; then reset.
        let home = store.spaces.first { $0.profileID == store.profiles.first?.id }
        if let home, let defaultProfile = await services.engineProfile(home.profileID) {
            sidebar.showSpace(home.id, animated: false)
            defaultProfile.setPermissionSetting(.block, for: .notifications, origin: URL(string: "http://127.0.0.1:8766")!)
            let listed = defaultProfile.contentSettings(ofType: .notifications)
            SpikeRunner.record("permission_listed", listed.map { "\($0.pattern)=\($0.setting)" }.joined(separator: "; "))
            app.showSettings(section: .privacy)
            await settleProfiles(800)
            await captureProfiles(app, .privacy, "privacy")
            app.debugSettingsWindow?.window?.orderOut(nil)
            if let page = await openShown(Self.permissionsPage) {
                SpikeRunner.record("permission_page", await js(page, Self.permissionStatesScript))
                if let entry = listed.first, let origin = entry.origin { defaultProfile.setPermissionSetting(nil, for: .notifications, origin: origin) }
                page.reload()
                await waitLoaded(page)
                SpikeRunner.record("permission_reset", "listed=\(defaultProfile.contentSettings(ofType: .notifications).count) page=\(await js(page, Self.permissionStatesScript))")
            }
        }
        // 4. A profile made, given a space and pages, deleted.
        if let doomed = app.newProfile(named: "Doomed"), let space = try? store.createSpace(name: "Doomed Space", profile: doomed.id) {
            sidebar.showSpace(space.id, animated: false)
            let pinned = try? store.addEntry(.pinned, url: Self.cookiePage + "?set=pinned", space: space.id)
            _ = await openShown(Self.cookiePage + "?set=doomed")
            if let pinned { sidebar.select(pinned.id) }
            await settleProfiles(1500)
            let directory = "Room Profile " + doomed.id.uuidString
            let entries = store.entries.values.filter { $0.spaceID == space.id }.map(\.id)
            let counts = app.profileDeletionCounts(doomed.id)
            let dirBefore = profileDirectories().contains(directory)
            let start = ContinuousClock.now
            let outcome = await app.deleteProfile(doomed.id)
            let elapsed = ms(since: start)
            let archived = entries.filter { store.archive[$0]?.reason == .spaceDeleted }.count
            SpikeRunner.record("delete_profile", "counts=\(counts.spaces) spaces \(counts.entries) tabs dir before=\(dirBefore) outcome=\(outcome) "
                + "in \(String(format: "%.0f", elapsed)) ms dir after=\(profileDirectories().contains(directory)) archived=\(archived) of \(entries.count) "
                + "profile gone=\(!store.profiles.contains { $0.id == doomed.id }) space gone=\(store.space(space.id) == nil) "
                + "engine profiles=\(app.engine.profiles.count) shown space=\(store.space(sidebar.activeSpaceID)?.name ?? "none")")
            SpikeRunner.record("delete_default_refused", "\(await app.deleteProfile(store.profiles[0].id))")
        }
        // 5. The palette's Settings ▸ Privacy.
        app.debugSettingsWindow?.window?.orderOut(nil)
        let commands = app.paletteCommands().map(\.title).filter { $0.hasPrefix("Settings ▸") }
        app.runPaletteCommand(CommandRegistry.settingsSection(7, title: "Privacy").id)
        await settleProfiles(800)
        let window = app.debugSettingsWindow?.window
        SpikeRunner.record("palette_section", "commands=\(commands.count) visible=\(window?.isVisible ?? false) title=\(window?.title ?? "none")")
        window?.orderOut(nil)
        // 6. Chromium's own site data list (the bounded attempt): a Today tab.
        app.profileServices().openPage(SettingsPages.allSiteData)
        await settleProfiles(3000)
        if let page = tabs.current {
            await waitLoaded(page, timeout: 15)
            try? await Task.sleep(for: .seconds(2))
            // Settings' WebUI draws inside custom elements' shadow roots: the light DOM's text is empty.
            let script = "(() => { const ui = document.querySelector('settings-ui'); "
                + "return JSON.stringify({ui: !!ui, shadow: !!(ui && ui.shadowRoot), light: document.body ? document.body.innerText.length : -1}) })()"
            let dom = await js(page, script)
            let image = await PageDriver.capture(page, "all site data")
            var luma = "none"
            if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = cg.dataProvider?.data,
               let bytes = CFDataGetBytePtr(data) {
                // Distinct greys in a sampled grid: a blank page has one (evidence, not an assertion).
                var seen = Set<UInt8>()
                for y in stride(from: 0, to: cg.height, by: max(1, cg.height / 40)) {
                    for x in stride(from: 0, to: cg.width, by: max(1, cg.width / 40)) {
                        seen.insert(bytes[y * cg.bytesPerRow + x * (cg.bitsPerPixel / 8) + 1] / 16)
                    }
                }
                luma = "\(seen.count) levels"
            }
            SpikeRunner.record("all_site_data", "url=\(page.url?.absoluteString ?? "nil") title=\(page.title ?? "nil") state=\(page.state) dom=\(dom) viewport=\(luma)")
            if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"), let image,
               let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: directory).appending(path: "phase-4.4b-all-site-data.png")
                SpikeRunner.record("capture_all_site_data", (try? png.write(to: url)) != nil ? url.lastPathComponent : "failed")
            }
        }
    }

    /// The engine root of this launch (`-RoomEngineDirectory` or `<state>/engine`).
    var spikeEngineRoot: URL? { AppDelegate.debugEngineDirectory }

    func profileDirectories() -> [String] {
        guard let root = spikeEngineRoot?.path else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasPrefix("Room Profile ") }.sorted()
    }

    /// Waits until `page` reports closed.
    func waitClosed(_ page: any WebContents, timeout: Double = 10) async -> Bool {
        await waitUntil(timeout) { page.state == .closed }
    }

    private func profilesEngine() async {
        guard let app = AppDelegate.current, let tabs = app.tabs, let defaultProfile = tabs.profile else {
            return SpikeRunner.record("error", "profiles: no app, tabs or default profile")
        }
        let engine = app.engine
        // 1. deleteProfile
        do {
            let doomed = try await engine.createProfile(name: "Spike Doomed")
            let directory = "Room Profile Spike Doomed"
            let made = profileDirectories().contains(directory)
            let page = try doomed.createWebContents(WebContentsConfiguration(hostWindow: window))
            page.load(URL(string: Self.cookiePage + "?set=doomed")!, transition: .typed, fromAddressBar: true)
            await waitLoaded(page, timeout: 20)
            let cookie = await js(page, "document.cookie")
            var refused = "no"
            do { try await engine.deleteProfile(doomed) } catch { refused = "\(error)" }
            page.close()
            let closed = await waitClosed(page)
            let start = ContinuousClock.now
            var result = "deleted"
            do { try await engine.deleteProfile(doomed) } catch { result = "\(error)" }
            let elapsed = ms(since: start)
            let listed = engine.profiles.contains { $0 === doomed }
            SpikeRunner.record("engine_delete", "dir_made=\(made) cookie=\(cookie) refused_while_open=\(refused) closed=\(closed) "
                + "result=\(result) in \(String(format: "%.0f", elapsed)) ms listed=\(listed) dir_left=\(profileDirectories().contains(directory))")
        } catch {
            SpikeRunner.record("engine_delete", "error \(error)")
        }
        // 2. clearBrowsingData for the last hour
        if let history = defaultProfile.history {
            let old = URL(string: "http://127.0.0.1:8765/page.html?old=1")!
            let imported = await history.importEntries([HistoryImportEntry(url: old, title: "Old visit",
                                                                           visits: [HistoryVisit(time: Date().addingTimeInterval(-3 * 3600), transition: .typed)])])
            guard let page = await open(URL(string: Self.cookiePage + "?set=hour")!) else { return SpikeRunner.record("error", "no cookie page") }
            let cookieBefore = await js(page, "document.cookie")
            try? await Task.sleep(for: .seconds(1))
            let fresh = URL(string: Self.cookiePage + "?set=hour")!
            let freshBefore = await history.visits(for: fresh) != nil
            let start = ContinuousClock.now
            await defaultProfile.clearBrowsingData([.history, .cookiesAndSiteData], since: .lastHour)
            let elapsed = ms(since: start)
            // The page without `?set=` sets nothing: it shows what the jar has.
            page.load(URL(string: Self.cookiePage)!, transition: .typed, fromAddressBar: true)
            await waitLoaded(page)
            SpikeRunner.record("engine_clear_hour", "imported=\(imported.urls) cookie_before=\(cookieBefore) fresh_before=\(freshBefore) "
                + "in \(String(format: "%.0f", elapsed)) ms; after: cookie=\(await js(page, "document.cookie")) "
                + "fresh_visit=\(await history.visits(for: fresh) != nil) old_visit=\(await history.visits(for: old) != nil)")
        }
        // 3. contentSettings and the page
        let origin = URL(string: "http://127.0.0.1:8766")!
        defaultProfile.setPermissionSetting(.block, for: .notifications, origin: origin)
        defaultProfile.setPermissionSetting(.allow, for: .geolocation, origin: origin)
        let listed = defaultProfile.contentSettings(ofType: .notifications)
            .map { "\($0.pattern)=\($0.setting) origin=\($0.origin?.absoluteString ?? "nil") embedded=\($0.isEmbedded)" }
        SpikeRunner.record("engine_content_settings", "notifications: \(listed.joined(separator: "; ")) | geolocation: "
            + defaultProfile.contentSettings(ofType: .geolocation).map { "\($0.pattern)=\($0.setting)" }.joined(separator: "; "))
        if let page = await open(URL(string: Self.permissionsPage)!) {
            SpikeRunner.record("engine_permission_page", await js(page, Self.permissionStatesScript))
            if let entry = defaultProfile.contentSettings(ofType: .notifications).first, let url = entry.origin {
                defaultProfile.setPermissionSetting(nil, for: .notifications, origin: url)
            }
            page.reload()
            await waitLoaded(page)
            SpikeRunner.record("engine_permission_reset", "listed=\(defaultProfile.contentSettings(ofType: .notifications).count) page=\(await js(page, Self.permissionStatesScript))")
        }
    }
}
#endif
