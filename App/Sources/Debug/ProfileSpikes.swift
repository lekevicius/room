#if DEBUG
import AppKit
import Engine
import Model
import Store

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
        default: await profilesEngine()
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
