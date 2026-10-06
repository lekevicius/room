#if DEBUG
import AppKit
import Engine
import Import
import Model
import Store
import UIKitCore

/// Phase 4.3a spike `import` (`scripts/import-check.sh`, tour step `import`
/// in group `appintegration`): `-RoomImportSource research/spikes/phase-4.3`
/// lists the fixtures as detected installs; `-RoomSidebarFixture import`
/// starts from the seed's shape (one space, no entries). Never a real profile.
/// 1. the sheet opens over the window and lists the fixture sources;
/// 2. each fixture is picked: the readers' counts and times; the store is
///    unchanged after all four reads and previews (nothing before the button);
/// 3. Chrome (one new space, the bar into Essentials, history), Safari (a
///    space per folder, history), the Netscape file (into "Space") and Arc's
///    sidebar are imported in turn through the sheet's model: each preview
///    against the store's rows after it, the duplicates, the depth clip,
///    the Essentials cap, Arc's spaces and profiles;
/// 4. the imported history found through `ProfileHistory.search` in the same launch;
/// 5. the rows in the database after a flush; the sheet closes.
extension SpikeRunner.Context {
    func importChecks() async {
        guard let app = AppDelegate.current, let store = app.store, let window = app.windowController?.window else {
            return SpikeRunner.record("error", "import: no store or window")
        }
        let sidebar = store.sidebar
        func settle(_ milliseconds: Int = 300) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func rows(_ kind: EntryKind) -> Int { sidebar.entries.values.count { $0.kind == kind } }
        func sidebarHash() -> Int {
            let state = store.currentState()
            return (try? RoomState(profiles: state.profiles, spaces: state.spaces, entries: state.entries).canonicalJSON().hashValue) ?? 0
        }
        func counts() -> [Int] {
            [sidebar.spaces.count, sidebar.profiles.count, rows(.folder), rows(.pinned), rows(.essential), rows(.today)]
        }
        func describe(_ c: [Int]) -> String {
            "spaces=\(c[0]) profiles=\(c[1]) folders=\(c[2]) pinned=\(c[3]) essentials=\(c[4]) today=\(c[5])"
        }

        // 1. The sheet.
        let hashBefore = sidebarHash()
        let generationBefore = store.persistence.generation
        SpikeRunner.record("state_before", describe(counts()))
        SpikeRunner.record("generation_at_start", "\(store.persistence.generation) dirty=\(store.persistence.isDirty)")
        app.showImportSheet(nil)
        await settle(800)
        SpikeRunner.record("generation_sheet_open", "\(store.persistence.generation) dirty=\(store.persistence.isDirty)")
        guard let model = app.importModel, let sheet = app.importSheet else {
            return SpikeRunner.record("error", "import: the sheet did not open")
        }
        SpikeRunner.record("sheet_open", "shown=\(sheet.isVisible && window.attachedSheet === sheet) picked=\(model.selectedSourceID ?? "none") "
            + "fixtures=\(model.sources.filter { $0.name.hasSuffix("(fixture)") }.map(\.name).joined(separator: ","))")
        // Installs found by directory existence only (nothing read).
        SpikeRunner.record("detected_installs", model.sources.filter { !$0.name.hasSuffix("(fixture)") }.map(\.name).joined(separator: ",").nonEmpty ?? "none")

        func pick(_ kind: BrowserKind, profile: String? = nil) async -> Bool {
            guard let source = model.sources.first(where: { $0.kind == kind && $0.name.hasSuffix("(fixture)") }) else {
                SpikeRunner.record("error", "import: no \(kind.rawValue) fixture listed")
                return false
            }
            model.pick(source.id)
            if let profile, model.selectedProfile != profile { model.selectedProfile = profile }
            let ready = await waitUntil(20) { model.phase == .ready }
            await model.settle()
            _ = await waitUntil(5) { model.plan != nil }
            return ready && model.plan != nil
        }

        // 2. Every fixture read; the counts and times.
        for (kind, name) in [(BrowserKind.chrome, "chrome"), (.safari, "safari"), (.bookmarksFile, "netscape"), (.arc, "arc"), (.firefox, "firefox")] {
            guard await pick(kind) else { continue }
            let scan = model.scan
            var parts: [String] = []
            if let bookmarks = scan?.bookmarks?.value { parts.append("bookmarks=\(bookmarks.links) folders=\(bookmarks.folders) skipped=\(bookmarks.skipped.count)") }
            if let history = scan?.history?.value { parts.append("history=\(history.urls.count) visits=\(history.visits)") }
            if let extensions = scan?.extensions?.value { parts.append("extensions=\(extensions.extensions.count) skipped=\(extensions.skipped.count)") }
            if let sidebar = scan?.sidebar?.value {
                parts.append("arc spaces=\(sidebar.spaces.count) profiles=\(sidebar.profiles.count) essentials=\(sidebar.essentialsCount) "
                    + "pinned=\(sidebar.pinnedLinks) folders=\(sidebar.folders) today=\(sidebar.todayTabs) skipped=\(sidebar.skipped.count)")
            }
            parts.append("errors=\(scan?.errors.count ?? -1)")
            if !model.profiles.isEmpty { parts.append("profiles=\(model.profiles.map(\.name).joined(separator: "/"))") }
            let times = (scan?.seconds ?? [:]).sorted { $0.key < $1.key }.map { String(format: "%@ %.1f ms", $0.key, $0.value * 1000) }
            parts.append("read \(String(format: "%.1f", model.debugReadSeconds * 1000)) ms (\(times.joined(separator: ", "))), "
                + "plan \(String(format: "%.2f", model.debugPlanSeconds * 1000)) ms")
            SpikeRunner.record("read_\(name)", parts.joined(separator: " "))
        }
        SpikeRunner.record("nothing_before_import", "unchanged=\(sidebarHash() == hashBefore) generation \(generationBefore) → "
            + "\(store.persistence.generation) dirty=\(store.persistence.isDirty) \(describe(counts()))")

        func capture(_ name: String) {
            guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
            let url = URL(fileURLWithPath: directory).appending(path: "phase-4.3-import-\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            sheet.displayIfNeeded()
            SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(sheet, to: url)) != nil ? url.lastPathComponent : "failed")
        }

        /// Sets the options, waits for the preview, imports, and records both.
        func runImport(_ label: String, _ configure: () -> Void) async -> ImportPreview? {
            configure()
            await settle(100)
            await model.settle()
            guard let plan = model.plan else {
                SpikeRunner.record("error", "import: no plan for \(label)")
                return nil
            }
            let p = plan.preview
            SpikeRunner.record("\(label)_preview", "spaces=\(p.spaces) profiles=\(p.newProfiles) folders=\(p.folders) pinned=\(p.pinned) "
                + "essentials=\(p.essentials) today=\(p.today) history=\(p.historyURLs) visits=\(p.historyVisits) duplicates=\(p.duplicates) "
                + "flattened=\(p.foldersFlattened) overflow=\(p.essentialsOverflow) skipped=\(p.skipped.count)")
            if label == "chrome" {
                await settle(300)
                capture("preview")
            }
            let before = counts()
            let start = ContinuousClock.now
            await model.performImport()
            let seconds = (ContinuousClock.now - start) / .seconds(1)
            let after = counts()
            let delta = zip(after, before).map { $0 - $1 }
            let expected = [p.spaces, p.newProfiles, p.folders, p.pinned, p.essentials, p.today]
            let history = model.historyResult ?? HistoryImportResult()
            SpikeRunner.record("\(label)_applied", "\(describe(delta)) equal=\(delta == expected) history urls=\(history.urls) "
                + "visits=\(history.visits) expired=\(history.expiredVisits)/\(history.expiredURLs) phase=\(model.phase == .ready ? "ready" : "done") "
                + String(format: "import %.0f ms", seconds * 1000))
            return p
        }

        // 3a. Chrome: one new space, the bar into Essentials, history into the default profile.
        guard let defaultProfile = sidebar.profiles.first else { return SpikeRunner.record("error", "import: no profile") }
        guard await pick(.chrome, profile: "Default") else { return }
        let chrome = await runImport("chrome") {
            model.targetSpace = nil
            model.targetProfile = defaultProfile.id
            model.layout = .oneSpace
            model.barIntoEssentials = true
            model.importBookmarks = true
            model.importHistory = true
        }
        if let toast = app.debugToastCenter?.currentToast, toast.id == "imported" {
            SpikeRunner.record("toast", "\"\(toast.message)\"")
        } else {
            SpikeRunner.record("toast", "none")
        }
        let chromeSpace = sidebar.spaces.first { $0.name == "Google Chrome" }
        SpikeRunner.record("essentials_cap", "essentials=\(sidebar.essentials(profile: defaultProfile.id).count) cap=\(EntryRules.essentialsCap) "
            + "overflow=\(chrome?.essentialsOverflow ?? -1) overflow pinned=\(chromeSpace.map { sidebar.pinned(space: $0.id).prefix(2).map(\.displayTitle).joined(separator: ",") } ?? "none")")
        let depths = sidebar.entries.values.filter { $0.kind == .folder && $0.spaceID == chromeSpace?.id }
            .compactMap { FolderRules.depth(of: $0.id, in: sidebar.entries) }
        let l5 = sidebar.entries.values.first { $0.customLabel == "L5" && $0.spaceID == chromeSpace?.id }
        SpikeRunner.record("depth_clip", "max depth=\(depths.max() ?? 0) flattened=\(chrome?.foldersFlattened ?? -1) L5 holds="
            + (l5.map { sidebar.pinned(space: chromeSpace!.id, folder: $0.id).map(\.displayTitle).joined(separator: ",") } ?? "none"))
        SpikeRunner.record("duplicates", "chrome=\(chrome?.duplicates ?? -1)")

        // 3b. Safari: a space per top-level folder, history.
        guard await pick(.safari) else { return }
        let safari = await runImport("safari") {
            model.targetSpace = nil
            model.layout = .spacePerFolder
            model.barIntoEssentials = false
        }
        SpikeRunner.record("safari_spaces", sidebar.spaces.map(\.name).joined(separator: ","))

        // 3c. The Netscape file into the existing first space.
        guard await pick(.bookmarksFile), let first = sidebar.spaces.first else { return }
        let netscape = await runImport("netscape") {
            model.targetSpace = first.id
            model.layout = .oneSpace
        }
        SpikeRunner.record("netscape_space", "\(first.name) pinned=\(sidebar.pinned(space: first.id).map(\.displayTitle).joined(separator: ","))")

        // 3d. Arc's sidebar.
        guard await pick(.arc) else { return }
        _ = await runImport("arc") { model.targetSpace = nil }
        let arcSpaces = ["Home", "Work", "Side"].compactMap { name in sidebar.spaces.last { $0.name == name } }
        let profileName = { (id: UUID) in sidebar.profiles.first { $0.id == id }?.name ?? "?" }
        SpikeRunner.record("arc_spaces", arcSpaces.map { "\($0.name) icon=\($0.icon ?? "none") colors=\($0.themeColors.joined(separator: "/")) "
            + "profile=\(profileName($0.profileID)) pinned=\(sidebar.pinned(space: $0.id).count) today=\(sidebar.today(space: $0.id).count)" }
            .joined(separator: " | "))
        let workProfiles = sidebar.profiles.filter { $0.name.caseInsensitiveCompare("Work") == .orderedSame }
        SpikeRunner.record("arc_profiles", "profiles=\(sidebar.profiles.map(\.name).joined(separator: ",")) work profiles=\(workProfiles.count) "
            + "work essentials=\(workProfiles.first.map { sidebar.essentials(profile: $0.id).map(\.displayTitle).joined(separator: ",") } ?? "none")")
        _ = (safari, netscape)

        // 3e (4.3b). Firefox's places.sqlite: a new space with its bookmarks, its history.
        if await pick(.firefox) {
            _ = await runImport("firefox") {
                model.targetSpace = nil
                model.targetProfile = defaultProfile.id
                model.layout = .oneSpace
                model.barIntoEssentials = false
                model.importBookmarks = true
                model.importHistory = true
            }
            let space = sidebar.spaces.last { $0.name == "Firefox" }
            SpikeRunner.record("firefox_space", space.map { "\($0.name) pinned=\(sidebar.pinned(space: $0.id).map(\.displayTitle).joined(separator: ","))" } ?? "none")
        }

        // 4. History through the engine in the same launch.
        if let engine = await app.engineProfile(for: defaultProfile), let history = engine.history {
            var found: [String] = []
            for query in ["Typed three times", "Import fixture Gamma", "Swift.org", "Old and new"] {
                let results = await history.search(query, limit: 5)
                found.append("\(query)=\(results.first.map { "\($0.url.absoluteString) visits=\($0.visitCount) typed=\($0.typedCount)" } ?? "none")")
            }
            SpikeRunner.record("history_search", found.joined(separator: " | "))
        } else {
            SpikeRunner.record("history_search", "no engine history")
        }

        // 5. The database; the sheet closes.
        capture("done")
        store.flush()
        let persisted = try? store.persistence.writer.database.loadState().state
        SpikeRunner.record("database", "entries \(persisted?.entries.count ?? -1) of \(sidebar.entries.count), spaces \(persisted?.spaces.count ?? -1) of "
            + "\(sidebar.spaces.count), profiles \(persisted?.profiles.count ?? -1) of \(sidebar.profiles.count)")
        app.closeImportSheet()
        await settle(400)
        SpikeRunner.record("sheet_closed", app.importSheet == nil && window.attachedSheet == nil)

        await importChecks43b(app: app, window: window, defaultProfile: defaultProfile)
    }

    /// 4.3b: passwords from a CSV through the sheet, the extensions' store
    /// pages one at a time (a local page stands for the store:
    /// `-RoomWebStorePage`), the cookies line, the browsers detected on a fake
    /// home (`-RoomImportHome`: the fixtures at their real paths), the
    /// open panel offered when macOS refuses a file, and the sheet reached
    /// from Settings ▸ General and from the first-run card.
    private func importChecks43b(app: AppDelegate, window: NSWindow, defaultProfile: Model.Profile) async {
        guard let store = app.store, let fixtures = UserDefaults.standard.string(forKey: "RoomImportSource") else { return }
        let sidebar = store.sidebar
        func settle(_ milliseconds: Int = 300) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
        func openSheet() async -> ImportSheetModel? {
            app.showImportSheet(nil)
            _ = await waitUntil(3) { app.importModel != nil && window.attachedSheet != nil }
            return app.importModel
        }
        func closeSheet() async {
            app.closeImportSheet()
            _ = await waitUntil(3) { app.importSheet == nil && window.attachedSheet == nil }
        }
        func capture(_ name: String) async {
            guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"), let sheet = app.importSheet else { return }
            await settle(300)
            let url = URL(fileURLWithPath: directory).appending(path: "phase-4.3b-import-\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            sheet.displayIfNeeded()
            SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(sheet, to: url)) != nil ? url.lastPathComponent : "failed")
        }

        // 6. Passwords: a CSV alone (no source picked), through the engine's importer.
        guard let model = await openSheet() else { return SpikeRunner.record("error", "import: the sheet did not reopen") }
        model.choosePasswords(URL(fileURLWithPath: fixtures).appending(path: "passwords.csv"))
        SpikeRunner.record("passwords_chosen", "line=\(model.passwordsLine ?? "nil") phase=\(model.phase == .choosing ? "choosing" : "other") "
            + "can_import=\(model.canImport) profile=\(store.sidebar.profiles.first { $0.id == model.passwordsProfile }?.name ?? "?")")
        await capture("passwords")
        let passwordsStart = ContinuousClock.now
        await model.performImport()
        let result = model.passwordsResult
        SpikeRunner.record("passwords_sheet", "status=\(result?.status.rawValue ?? "none") imported=\(result?.imported ?? -1) "
            + "conflicts=\(result?.conflicts ?? -1) skipped=\(result?.skipped ?? -1) line=\(model.passwordsResultLine ?? "nil") "
            + String(format: "%.0f ms", ms(since: passwordsStart)))
        if let toast = app.debugToastCenter?.currentToast, toast.id == "imported" { SpikeRunner.record("passwords_toast", "\"\(toast.message)\"") }
        await closeSheet()

        // 7. Extensions: the Web Store ones listed (the unpacked one with its reason), their pages one at a time.
        guard let model = await openSheet() else { return }
        if let source = model.sources.first(where: { $0.kind == .chrome && $0.name.hasSuffix("(fixture)") }) {
            model.pick(source.id)
            _ = await waitUntil(20) { model.phase == .ready }
            await model.settle()
            model.importBookmarks = false
            model.importHistory = false
            model.importExtensions = true
            model.targetSpace = sidebar.spaces.first?.id
            await model.settle()
            let skipped = model.scan?.extensions?.value?.skipped.map { "\($0.item): \($0.reason)" }.joined(separator: "; ") ?? "none"
            SpikeRunner.record("extensions_row", "web_store=\(model.webStoreExtensions.map(\.name).joined(separator: ",")) "
                + "chosen=\(model.chosenExtensions.count) skipped=[\(skipped)] can_import=\(model.canImport)")
            await capture("extensions")
            let entriesBefore = Set(sidebar.entries.keys)
            await model.performImport()
            SpikeRunner.record("extensions_import", "pages_to_open=\(model.storePagesOpened) summary=\"\(model.phase == .ready ? "" : app.debugToastCenter?.currentToast?.message ?? "")\"")
            await closeSheet()
            func describePages() -> String {
                guard let pages = app.extensionStorePages else { return "finished" }
                let entry = pages.currentEntry.flatMap { sidebar.entry($0) }
                let space = entry.flatMap { e in sidebar.spaces.first { $0.id == e.spaceID } }?.name ?? "?"
                return "opened=\(pages.sequence.opened.count) pending=\(pages.sequence.pending.count) current=\(pages.sequence.current ?? "none") "
                    + "tab=\(entry?.kind == .today ? "today" : "none") space=\(space) url=\(entry?.liveURL ?? "none")"
            }
            _ = await waitUntil(5) { app.extensionStorePages?.currentEntry != nil }
            let newTabs = sidebar.entries.keys.filter { !entriesBefore.contains($0) }.count
            SpikeRunner.record("store_page_first", describePages() + " new_tabs=\(newTabs)")
            // The next waits: nothing more opens while the first page is open.
            await settle(1500)
            SpikeRunner.record("store_page_waits", "new_tabs=\(sidebar.entries.keys.filter { !entriesBefore.contains($0) }.count) " + describePages())
            // Closing the page (no install) opens the next.
            if let first = app.extensionStorePages?.currentEntry {
                app.sidebar?.close(first)
                _ = await waitUntil(5) { app.extensionStorePages?.currentEntry.map { $0 != first } ?? true }
                SpikeRunner.record("store_page_next", describePages() + " first_tab_gone=\(sidebar.entry(first) == nil)")
            }
            if let second = app.extensionStorePages?.currentEntry {
                app.sidebar?.close(second)
                _ = await waitUntil(5) { app.extensionStorePages == nil }
                let toast = app.debugToastCenter?.currentToast
                SpikeRunner.record("store_pages_done", describePages() + " toast=\(toast?.id == "imported-extensions" ? "\"\(toast!.message)\"" : "none")")
            }
        } else {
            SpikeRunner.record("error", "import: no chrome fixture for the extensions")
            await closeSheet()
        }

        // 8. The cookies line, 9. the browsers on the fake home, the open panel when macOS refuses a file.
        guard let model = await openSheet() else { return }
        SpikeRunner.record("cookies_line", ImportSheetText.cookies)
        let home = AppDelegate.importHome.path
        let detected = model.sources.filter { !$0.name.hasSuffix("(fixture)") }
        SpikeRunner.record("home_detected", "home=\(UserDefaults.standard.string(forKey: "RoomImportHome") != nil ? "fake" : "real") "
            + detected.map { "\($0.name)=~/\($0.location.path.replacingOccurrences(of: home + "/", with: ""))" }.joined(separator: " "))
        if UserDefaults.standard.string(forKey: "RoomImportHome") != nil {
            for kind in [BrowserKind.safari, .arc, .firefox] {
                guard let source = detected.first(where: { $0.kind == kind }) else {
                    SpikeRunner.record("home_\(kind.rawValue)", "not detected")
                    continue
                }
                model.pick(source.id)
                _ = await waitUntil(20) { model.phase == .ready || model.message != nil }
                await model.settle()
                let scan = model.scan
                var parts: [String] = []
                if let b = scan?.bookmarks?.value { parts.append("bookmarks=\(b.links) folders=\(b.folders)") }
                if let h = scan?.history?.value { parts.append("history=\(h.urls.count) visits=\(h.visits)") }
                if let a = scan?.sidebar?.value { parts.append("arc spaces=\(a.spaces.count)") }
                if !model.profiles.isEmpty { parts.append("profiles=\(model.profiles.map(\.name).joined(separator: "/"))") }
                parts.append("errors=\(scan?.errors.count ?? -1) needs_access=\(scan?.needsFileAccess ?? false)")
                SpikeRunner.record("home_\(kind.rawValue)", parts.joined(separator: " "))
            }
        }
        // A Safari folder whose Bookmarks.plist macOS will not open (as without Full Disk Access).
        let locked = FileManager.default.temporaryDirectory.appending(path: "room-import-locked-\(UUID().uuidString)/Safari", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let plist = locked.appending(path: "Bookmarks.plist")
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: fixtures).appending(path: "safari/Bookmarks.plist"), to: plist)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: plist.path)
        model.addChosen(locked)
        _ = await waitUntil(20) { model.phase == .ready }
        await model.settle()
        await capture("permission")
        SpikeRunner.record("permission_denied", "needs_access=\(model.scan?.needsFileAccess ?? false) "
            + "error=\(model.scan?.bookmarks?.failure?.kind == .permissionDenied) message=\(model.message ?? "none")")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.path)
        try? FileManager.default.removeItem(at: locked.deletingLastPathComponent())
        await closeSheet()

        // 10. Settings ▸ General ▸ Import… (the button's action).
        app.showSettings(nil)
        await settle(500)
        app.debugSettingsWindow?.services.showImportSheet()
        _ = await waitUntil(3) { app.importSheet != nil && window.attachedSheet === app.importSheet }
        SpikeRunner.record("settings_import", "sheet=\(app.importSheet != nil && window.attachedSheet === app.importSheet) key_window=\(NSApp.keyWindow === window ? "browser" : "other")")
        await closeSheet()
        app.debugSettingsWindow?.window?.close()

        // 11. The first-run card's "Import from another browser…".
        let firstRunWasDone = store.settings.settings.firstRunDone
        app.showWelcomeCard()
        _ = await waitUntil(3) { app.firstRunCard != nil }
        if let card = app.firstRunCard {
            card.onImport()
            _ = await waitUntil(3) { app.importSheet != nil && window.attachedSheet === app.importSheet }
            SpikeRunner.record("first_run_import", "card=true sheet=\(app.importSheet != nil && window.attachedSheet === app.importSheet)")
            await closeSheet()
        } else {
            SpikeRunner.record("first_run_import", "card=false")
        }
        if firstRunWasDone { store.settings.update { $0.firstRunDone = true } }
        _ = defaultProfile
    }
}

/// B-84 (4.3b, `scripts/import-large.sh`): the generated large profile
/// (`research/spikes/phase-4.3/make-large.py`: 5,000 bookmarks in 200
/// folders, 50,000 URLs with 100,000 visits) through the sheet's model: the
/// read, the plan, the sidebar's write, the history batches, the sidebar's
/// reload after, the summed RSS before and after, and the longest stretch the
/// main thread did not answer (a 5 ms tick on the main actor) during each.
extension SpikeRunner.Context {
    func importLargeChecks() async {
        guard let app = AppDelegate.current, let store = app.store, let window = app.windowController?.window else {
            return SpikeRunner.record("error", "importlarge: no store or window")
        }
        let sidebar = store.sidebar
        /// The main actor's longest gap between 5 ms ticks while `body` runs.
        final class Stall { var max: Double = 0; var running = true }
        func measured(_ label: String, _ body: () async -> Void) async {
            let stall = Stall()
            let ticker = Task { @MainActor in
                var last = ContinuousClock.now
                while stall.running {
                    try? await Task.sleep(for: .milliseconds(5))
                    let now = ContinuousClock.now
                    stall.max = max(stall.max, (now - last) / .milliseconds(1))
                    last = now
                }
            }
            // The ticker takes its first tick before the body runs (a body's synchronous start would otherwise go unseen).
            try? await Task.sleep(for: .milliseconds(20))
            let start = ContinuousClock.now
            await body()
            stall.running = false
            await ticker.value
            SpikeRunner.record("\(label)_time", String(format: "%.0f ms, main thread's longest stall %.0f ms", ms(since: start), stall.max))
        }
        try? await Task.sleep(for: .seconds(2))
        SpikeRunner.record("rss_before", ProcessMemory.snapshot().summary)
        app.showImportSheet(nil)
        _ = await waitUntil(3) { app.importModel != nil && window.attachedSheet != nil }
        guard let model = app.importModel, let source = model.sources.first(where: { $0.name == "large (fixture)" }) else {
            return SpikeRunner.record("error", "importlarge: no large (fixture) source; run make-large.py")
        }
        await measured("read_and_plan") {
            model.pick(source.id)
            _ = await waitUntil(120) { model.phase == .ready }
            await model.settle()
            _ = await waitUntil(60) { model.plan != nil }
        }
        let scan = model.scan
        SpikeRunner.record("read", "bookmarks=\(scan?.bookmarks?.value?.links ?? -1) folders=\(scan?.bookmarks?.value?.folders ?? -1) "
            + "history=\(scan?.history?.value?.urls.count ?? -1) visits=\(scan?.history?.value?.visits ?? -1) errors=\(scan?.errors.count ?? -1) "
            + String(format: "read %.0f ms (%@), plan %.0f ms", model.debugReadSeconds * 1000,
                     (scan?.seconds ?? [:]).sorted { $0.key < $1.key }.map { String(format: "%@ %.0f ms", $0.key, $0.value * 1000) }.joined(separator: ", "),
                     model.debugPlanSeconds * 1000))
        // A replan on an option change (the sheet remakes the plan off the main thread every time).
        await measured("replan") {
            model.barIntoEssentials = true
            await model.settle()
            model.barIntoEssentials = false
            await model.settle()
        }
        SpikeRunner.record("replan", String(format: "the last plan %.0f ms", model.debugPlanSeconds * 1000))
        model.targetSpace = nil
        model.targetProfile = sidebar.profiles.first?.id ?? model.targetProfile
        model.layout = .oneSpace
        await model.settle()
        if let p = model.plan?.preview {
            SpikeRunner.record("preview", "spaces=\(p.spaces) folders=\(p.folders) pinned=\(p.pinned) history=\(p.historyURLs) visits=\(p.historyVisits) "
                + "duplicates=\(p.duplicates) flattened=\(p.foldersFlattened) batches=\(model.plan?.history.count ?? 0)")
        }
        let entriesBefore = sidebar.entries.count
        await measured("import") { await model.performImport() }
        let history = model.historyResult ?? HistoryImportResult()
        SpikeRunner.record("import", "entries \(entriesBefore) → \(sidebar.entries.count) applied=\(model.applied.map { "folders=\($0.folders) pinned=\($0.pinned)" } ?? "none") "
            + String(format: "sidebar write %.0f ms, history %d batches %.0f ms", model.debugApplySeconds * 1000, model.debugHistoryBatches,
                     model.debugHistorySeconds * 1000)
            + " history urls=\(history.urls) visits=\(history.visits) expired=\(history.expiredVisits)/\(history.expiredURLs)")
        app.closeImportSheet()
        try? await Task.sleep(for: .milliseconds(300))
        // The sidebar's full reload with the imported space shown.
        if let space = sidebar.spaces.last(where: { $0.name == "Google Chrome" }) { app.sidebar?.showSpace(space.id) }
        try? await Task.sleep(for: .milliseconds(500))
        var reloads: [Double] = []
        for _ in 0..<5 {
            let start = ContinuousClock.now
            app.sidebar?.reloadFromStore()
            window.contentView?.layoutSubtreeIfNeeded()
            reloads.append(ms(since: start))
            try? await Task.sleep(for: .milliseconds(100))
        }
        SpikeRunner.record("sidebar_reload", reloads.map { String(format: "%.1f", $0) }.joined(separator: ", ") + " ms")
        if let engine = await app.engineProfile(for: sidebar.profiles[0]), let engineHistory = engine.history {
            let found = await engineHistory.search("Large history page 49999", limit: 3)
            SpikeRunner.record("history_found", found.first.map { "\($0.url.absoluteString) visits=\($0.visitCount)" } ?? "none")
        }
        try? await Task.sleep(for: .seconds(2))
        SpikeRunner.record("rss_after", ProcessMemory.snapshot().summary)
        store.flush()
        let start = ContinuousClock.now
        let persisted = try? store.persistence.writer.database.loadState().state
        SpikeRunner.record("database", "entries \(persisted?.entries.count ?? -1) of \(sidebar.entries.count) "
            + String(format: "(load %.0f ms)", ms(since: start)))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
