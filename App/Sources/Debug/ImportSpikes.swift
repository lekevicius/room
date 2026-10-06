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
        app.showImportSheet(nil)
        await settle(800)
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
        for (kind, name) in [(BrowserKind.chrome, "chrome"), (.safari, "safari"), (.bookmarksFile, "netscape"), (.arc, "arc")] {
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
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
