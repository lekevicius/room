#if DEBUG
import AppKit
import Chrome
import Engine
import Import
import Library
import Model
import Omnibox
import Sidebar
import Store
import SwiftUI
import Tabs
import UIKitCore

/// 5.0b `-RoomSpike skipped`: the Chapter 4 by-hand steps the user skipped
/// (chapter-4-by-hand.md "Results, 2026-10-21") that no earlier spike drove,
/// each through the code path its click takes: a context menu's item by
/// `performActionForItem`, a sheet's model, the window controller's methods,
/// the toast's own action. Sections (`-RoomSpikeOnly` picks; by phase):
/// `archive` (4.1a steps 2–6; the default), `routing` and `routingverify`
/// (4.2), `importsheet` (4.3a), `search` (4.4a), `extensions` and
/// `extensionsverify` (4.5), `autoplay` (4.6), `print` (4.7b), `windows` and
/// `windowsrelaunch` (4.8). Every line names its by-hand step; the launches
/// are `scripts/skipped-steps.sh`.
extension SpikeRunner.Context {
    func skippedStepsChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        // The palette checks send no query to a search engine (each group's state is its own).
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        if only.isEmpty || only.contains("archive") { await skippedArchive() }
        if only.contains("routing") { await skippedRouting() }
        if only.contains("routingverify") { await skippedRoutingVerify() }
        if only.contains("importsheet") { await skippedImportSheet() }
        if only.contains("search") { await skippedSearch() }
        if only.contains("extensions") { await skippedExtensions() }
        if only.contains("extensionsverify") { await skippedExtensionsVerify() }
        if only.contains("autoplay") { await skippedAutoplay() }
        if only.contains("print") { await skippedPrint() }
        if only.contains("windows") { await skippedWindows() }
        if only.contains("windowsrelaunch") { await skippedWindowsRelaunch() }
    }

    private func pause(_ milliseconds: Int = 400) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

    private func toastLine(_ app: AppDelegate) -> String {
        guard let toast = app.debugToastCenter?.currentToast else { return "none" }
        return "\"\(toast.message)\"" + (toast.action.map { " button=\($0.title)" } ?? "")
    }

    /// The toast's own button, as a click on it does.
    private func pressToastButton(_ app: AppDelegate) async -> Bool {
        guard let center = app.debugToastCenter, center.currentToast?.action != nil else { return false }
        center.queue.performAction()
        await pause()
        return true
    }

    /// Today tabs on 8766's find page, each titled by the page itself so the archive and the palette tell them apart.
    private func skippedTabs(_ names: [String]) async -> [String: UUID] {
        var ids: [String: UUID] = [:]
        for name in names {
            guard let page = await open(URL(string: "http://127.0.0.1:8766/find.html?\(name)")!),
                  let id = tabs.entryID(for: page) else { continue }
            _ = await js(page, "document.title = 'Skipped \(name)'; true")
            ids[name] = id
        }
        _ = await waitUntil(3) { ids.allSatisfy { store.entry($0.value)?.liveTitle?.hasPrefix("Skipped") == true } }
        return ids
    }

    // MARK: 4.1a, steps 2–6

    private func skippedArchive() async {
        guard let app = AppDelegate.current, let room = app.store, let library = app.library, let sweeper = app.archiveSweeper else {
            return SpikeRunner.record("error", "skipped archive: no store, library or sweeper")
        }
        let model = room.sidebar
        let space = sidebar.activeSpaceID
        let ids = await skippedTabs(["a", "b", "c", "d", "e"])
        guard ids.count == 5, let a = ids["a"], let b = ids["b"], let c = ids["c"], let d = ids["d"], let e = ids["e"] else {
            return SpikeRunner.record("error", "skipped archive: five tabs did not open")
        }
        let names = Dictionary(uniqueKeysWithValues: ids.map { ($0.value, $0.key) })
        func order() -> String { model.today(space: space).map { names[$0.id] ?? "?" }.joined() }
        func item(_ menu: NSMenu?, _ title: String) -> NSMenuItem? { menu?.items.first { $0.title == title } }
        func perform(_ menu: NSMenu?, _ title: String) -> Bool {
            guard let menu, let item = item(menu, title), item.isEnabled else { return false }
            menu.performActionForItem(at: menu.index(of: item))
            return true
        }
        // `a` on a second page first: Restore's Back (step 2).
        if let page = tabs.contents(for: a) {
            _ = await js(page, "location.href = 'http://127.0.0.1:8766/find.html?a2'; true")
            _ = await waitUntil(10) { page.url?.query == "a2" && !page.isLoading }
            _ = await js(page, "document.title = 'Skipped a'; true")
        }
        await pause()
        SpikeRunner.record("tabs", "order=\(order()) a_canGoBack=\(tabs.contents(for: a)?.canGoBack ?? false)")

        // Step 3: Archive Tab, Archive Tabs Below, Archive 2 Tabs (the context menu's items), each with its Undo.
        let before = order()
        let one = perform(sidebar.debugContextMenu(for: c), CommandName.archiveTab)
        let oneLine = "item=\(one) gone=\(model.entry(c) == nil) row=\(model.archive[c]?.reason.rawValue ?? "none") toast=\(toastLine(app))"
        let undoOne = await pressToastButton(app)
        SpikeRunner.record("step3_archive_tab", oneLine + " undo=\(undoOne) back=\(model.entry(c) != nil) order \(before)→\(order()) "
            + "row_gone=\(model.archive[c] == nil)")
        let first = model.today(space: space).first?.id ?? a
        let belowCount = model.today(space: space).count - 1
        let below = perform(sidebar.debugContextMenu(for: first), CommandName.archiveBelow)
        let belowLine = "on=\(names[first] ?? "?") item=\(below) archived=\(model.archivedCount(reason: .manual)) of \(belowCount) left=\(order()) "
            + "toast=\(toastLine(app))"
        _ = await pressToastButton(app)
        SpikeRunner.record("step3_archive_below", belowLine + " undo: order=\(order()) manual_rows=\(model.archivedCount(reason: .manual))")
        let lastMenu = sidebar.debugContextMenu(for: model.today(space: space).last!.id)
        SpikeRunner.record("step3_archive_below_last", "enabled=\(item(lastMenu, CommandName.archiveBelow)?.isEnabled ?? true)")
        sidebar.debugClearMultiSelection()
        sidebar.select(b)
        sidebar.debugToggleSelection(d)
        let group = sidebar.debugClickedMenu(for: d)
        let two = perform(group, CommandName.archiveTabs(2))
        SpikeRunner.record("step3_archive_two", "item=\(two) b_gone=\(model.entry(b) == nil) d_gone=\(model.entry(d) == nil) "
            + "manual_rows=\(model.archivedCount(reason: .manual)) toast=\(toastLine(app)) order=\(order())")
        app.debugToastCenter?.dismiss(id: "tabs-archived")
        sidebar.debugClearMultiSelection()

        // Step 2: the Library: the two rows, Restore with Back, ×, Clear Archive's Cancel.
        _ = perform(sidebar.debugContextMenu(for: a), CommandName.archiveTab)
        app.debugToastCenter?.dismiss(id: "tabs-archived")
        room.flush()
        app.showLibrary(section: nil)
        await pause(600)
        SpikeRunner.record("step2_library", "shown=\(app.isLibraryShown) \(library.summary) a_navigation_state=\(model.archive[a]?.navigationState != nil)")
        library.restore(a)
        let restored = model.entry(a)
        if let page = tabs.contents(for: a) { await waitLoaded(page, timeout: 10) }
        await pause()
        SpikeRunner.record("step2_restore", "top=\(model.today(space: space).first?.id == a) selected=\(sidebar.selectedEntryID == a) "
            + "row_gone=\(model.archive[a] == nil) url=\(tabs.contents(for: a)?.url?.query ?? "nil") canGoBack=\(tabs.contents(for: a)?.canGoBack ?? false) "
            + "restored=\(restored != nil)")
        let rowsBefore = model.archivedCount
        library.deleteArchived(b)
        await pause()
        SpikeRunner.record("step2_remove_row", "rows \(rowsBefore)→\(model.archivedCount) b_row=\(model.archive[b] != nil) b_entry=\(model.entry(b) != nil) "
            + "\(library.summary)")
        var asked = ""
        library.confirmations = { message in asked = message; return false }
        library.clearArchive()
        await pause()
        SpikeRunner.record("step2_clear_archive_cancel", "asked=\"\(asked)\" rows=\(model.archivedCount) (d kept=\(model.archive[d] != nil))")
        library.confirmations = nil
        app.hideLibrary()
        await pause()

        // Step 5: ⌘↩ on the palette's Archived row opens a copy and keeps the row.
        restorePaletteHooks()
        if let palette {
            let tabsBefore = model.today(space: space).count
            press("⌘T")
            await pause()
            type("skipped d")
            await pause(800)
            let index = palette.result.matches.firstIndex { if case .restoreArchived(d, _) = $0.action { true } else { false } }
            if let index {
                for _ in 0..<index { press("↓") }
                await pause(200)
                press("⌘↩")
                await pause(800)
                let copy = model.today(space: space).first { $0.id != d && $0.liveURL?.hasSuffix("find.html?d") == true }
                SpikeRunner.record("step5_command_enter", "row=found index=\(index) today \(tabsBefore)→\(model.today(space: space).count) "
                    + "copy=\(copy != nil) copy_selected=\(copy.map { sidebar.selectedEntryID == $0.id } ?? false) row_kept=\(model.archive[d] != nil) "
                    + "palette_open=\(palette.isOpen)")
            } else {
                press("⎋")
                SpikeRunner.record("step5_command_enter", "row=missing rows=\(palette.result.matches.map(\.title))")
            }
        }
        await pause()

        // Step 4: Archive tabs after 24 hours: a tab unused for 13 h stays; at 12 hours it goes.
        let base = model.clock()
        let original = room.settings.settings.archiveAfterHours
        sidebar.select(e)
        sidebar.select(a)
        await pause()
        room.settings.update { $0.archiveAfterHours = 24 }
        model.clock = { Timestamp(milliseconds: base.milliseconds + 13 * 3_600_000) }
        let at24 = sweeper.sweep()
        let keptAt24 = model.entry(e) != nil
        room.settings.update { $0.archiveAfterHours = 12 }
        let at12 = sweeper.sweep()
        SpikeRunner.record("step4_archive_after", "options=\(ArchivePolicy.afterHoursOptions) 24h: archived=\(at24.count) e_kept=\(keptAt24); "
            + "12h: archived=\(at12.count) e_archived=\(at12.contains(e)) selected_a_kept=\(model.entry(a) != nil)")
        model.clock = { Timestamp.now }
        room.settings.update { $0.archiveAfterHours = original }

        // Step 6: Delete Space, the toast left to go, then Restore lands in the active space.
        guard let profile = model.space(space)?.profileID, let gone = try? model.createSpace(name: "Skipped Gone", profile: profile) else {
            return SpikeRunner.record("error", "skipped archive: no second space")
        }
        let goneTabs = (0..<2).compactMap { try? model.addEntry(.today, url: "http://127.0.0.1:8766/find.html?gone\($0)", title: "Skipped gone \($0)", space: gone.id) }
        sidebar.confirmations = { _ in true }
        sidebar.deleteSpace(gone.id)
        await pause()
        let deleteToast = toastLine(app)
        app.debugToastCenter?.dismiss(id: app.debugToastCenter?.currentToast?.id ?? "")
        await pause()
        let rows = goneTabs.map { model.archive[$0.id]?.reason.rawValue ?? "none" }
        SpikeRunner.record("step6_delete_space", "toast=\(deleteToast) space_gone=\(model.space(gone.id) == nil) rows=\(rows) "
            + "toast_after=\(toastLine(app))")
        if let row = goneTabs.first {
            app.showLibrary(section: nil)
            await pause()
            library.restore(row.id)
            await pause()
            let entry = model.entry(row.id)
            SpikeRunner.record("step6_restore_after_toast", "restored=\(entry != nil) space=\(entry?.spaceID == space ? "the active one" : "other") "
                + "selected=\(sidebar.selectedEntryID == row.id) space_still_gone=\(model.space(gone.id) == nil)")
            app.hideLibrary()
        }
        sidebar.confirmations = nil

        // Step 7: History in the Library: rows by day, a click opens a new tab, Delete All from <host>.
        app.showLibrary(section: .history)
        library.loadHistory()
        _ = await waitUntil(5) { library.currentRows.contains { if case .history = $0 { true } else { false } } }
        let items = library.currentRows.compactMap { if case .history(let item) = $0 { item } else { nil } }
        let days = library.currentRows.filter { if case .day(.history, _) = $0 { true } else { false } }.count
        if let item = items.first(where: { $0.url.host == "127.0.0.1" }) {
            let count = model.today(space: sidebar.activeSpaceID).count
            library.onOpen?(item.url)
            _ = await waitUntil(5) { model.today(space: self.sidebar.activeSpaceID).count == count + 1 }
            let opened = model.today(space: sidebar.activeSpaceID).contains { $0.liveURL == item.url.absoluteString && $0.id != a }
            library.deleteHistory(host: item.host)
            _ = await waitUntil(5) { !library.currentRows.contains { if case .history(let row) = $0 { row.host == item.host } else { false } } }
            let left = library.currentRows.filter { if case .history(let row) = $0 { row.host == item.host } else { false } }.count
            SpikeRunner.record("step7_history", "rows=\(items.count) days=\(days) click_opens_tab=\(opened) delete_all_from \(item.host): rows_left=\(left)")
        } else {
            SpikeRunner.record("step7_history", "rows=\(items.count) days=\(days) no 127.0.0.1 row")
        }
        app.hideLibrary()

        // Step 8 (and 5.0a's click check a): Help ▸ Restore Sidebar…'s sheet after a real deletion; the restore; the "before restore" row.
        guard let backups = app.backupScheduler, let kept = try? model.createSpace(name: "Skipped Restore", profile: profile) else { return }
        _ = try? model.addEntry(.today, url: "http://127.0.0.1:8766/find.html?restore", title: "Skipped restore", space: kept.id)
        room.flush()
        _ = try? backups.takeNow(label: nil)
        sidebar.confirmations = { _ in true }
        sidebar.deleteSpace(kept.id)
        sidebar.confirmations = nil
        app.debugToastCenter?.dismiss(id: app.debugToastCenter?.currentToast?.id ?? "")
        room.flush()
        func sheetList() -> RestoreSidebarList? { (app.restoreSheet?.contentViewController as? NSHostingController<RestoreSidebarList>)?.rootView }
        NSApp.sendAction(#selector(AppDelegate.showRestoreSidebar(_:)), to: nil, from: nil)
        await pause(600)
        guard let list = sheetList(), let newest = list.backups.first else { return SpikeRunner.record("step8_sheet", "no sheet or no backup") }
        let dates = list.backups.map(\.file.date)
        SpikeRunner.record("step8_sheet", "shown=\(app.restoreSheet?.isVisible ?? false) backups=\(list.backups.count) newest_first=\(dates == dates.sorted(by: >)) "
            + "newest=\(newest.entries) entries · \(newest.spaces) spaces · \(newest.archived) archived")
        list.onRestore(newest)
        await pause(1200)
        SpikeRunner.record("step8_restore", "space_back=\(model.space(kept.id) != nil) toast=\(toastLine(app)) selected_loaded=\(tabs.current != nil)")
        NSApp.sendAction(#selector(AppDelegate.showRestoreSidebar(_:)), to: nil, from: nil)
        await pause(600)
        let again = sheetList()
        SpikeRunner.record("step8_before_restore_row", "first_label=\(again?.backups.first?.file.label ?? "none") rows=\(again?.backups.count ?? 0)")
        again?.onCancel()
        await pause(300)
    }

    // MARK: 4.6, step 54: autoplay and its line

    private func skippedAutoplay() async {
        let line = PrivacyStatements.lines.first { $0.title == "Autoplay" }?.text ?? "missing"
        SpikeRunner.record("step54_line", line)
        guard let page = await open(URL(string: "http://127.0.0.1:8766/audio.html?autoplay")!) else {
            return SpikeRunner.record("error", "skipped autoplay: no page")
        }
        await pause(600)
        // No gesture yet: `executeJavaScript` carries no user activation.
        // The script runs in an isolated world (the page's own `tone` is not visible): its own quiet WAV.
        let wav = "(() => { const rate = 22050, n = 8820, b = new ArrayBuffer(44 + n * 2), v = new DataView(b); "
            + "const t = (o, s) => { for (let i = 0; i < s.length; i++) v.setUint8(o + i, s.charCodeAt(i)); }; "
            + "t(0, 'RIFF'); v.setUint32(4, 36 + n * 2, true); t(8, 'WAVE'); t(12, 'fmt '); v.setUint32(16, 16, true); "
            + "v.setUint16(20, 1, true); v.setUint16(22, 1, true); v.setUint32(24, rate, true); v.setUint32(28, rate * 2, true); "
            + "v.setUint16(32, 2, true); v.setUint16(34, 16, true); t(36, 'data'); v.setUint32(40, n * 2, true); "
            + "for (let i = 0; i < n; i++) v.setInt16(44 + i * 2, Math.sin(i / rate * 2 * Math.PI * 440) * 300, true); "
            + "return URL.createObjectURL(new Blob([b], { type: 'audio/wav' })); })()"
        let probe = { (muted: Bool) in
            "(() => { const a = new Audio(\(wav)); a.volume = 0.05; a.muted = \(muted); document.body.appendChild(a); "
                + "return a.play().then(() => 'played', e => e.name); })()"
        }
        let unmuted = await js(page, probe(false))
        let muted = await js(page, probe(true))
        let activation = await js(page, "navigator.userActivation ? navigator.userActivation.hasBeenActive : 'n/a'")
        let gesture = await PageDriver.evaluateWithGesture(page, probe(false), "autoplay after a click") ?? "error"
        await pause(300)
        SpikeRunner.record("step54_autoplay", "before any click: unmuted=\(unmuted) muted=\(muted) activated=\(activation); "
            + "after a click: unmuted=\(gesture) audible=\(page.isAudible)")
    }

    // MARK: 4.7b, step 64: printing without the mouse

    private func skippedPrint() async {
        guard let page = await open(URL(string: "http://127.0.0.1:8776/phase-4.7/article2.html")!) else {
            return SpikeRunner.record("error", "skipped print: no page")
        }
        await pause(800)
        // Click into the page, then ⌘P as a key.
        _ = PageDriver.click(page, at: CGPoint(x: 40, y: 200), "click into the page")
        await pause(200)
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        PageDriver.key(window, characters: "p", keyCode: 35, modifiers: .command)
        var preview: NSWindow?
        _ = await waitUntil(15) {
            preview = NSApp.windows.first { !before.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 200 }
            return preview != nil
        }
        guard let preview else { return SpikeRunner.record("step64_print", "⌘P: no preview in 15 s") }
        try? await Task.sleep(for: .milliseconds(2500))
        SpikeRunner.record("step64_cmd_p", "preview=\(Swift.type(of: preview)) key_is_preview=\(NSApp.keyWindow === preview)")
        // Tab: the keyboard stays in the preview (which control has it is the preview's WebUI, not readable here).
        for _ in 0..<3 {
            PageDriver.key(preview, characters: "\t", keyCode: 48)
            try? await Task.sleep(for: .milliseconds(150))
        }
        SpikeRunner.record("step64_tab", "three Tabs: key_is_preview=\(NSApp.keyWindow === preview) preview_visible=\(preview.isVisible)")
        guard NSPrinter.printerNames.isEmpty else {
            // Return prints on the system's default printer here (three real jobs on the laptop, 2026-10-21).
            SpikeRunner.record("step64_return", "not pressed: \(NSPrinter.printerNames.count) printer(s) set up")
            PageDriver.key(preview, characters: "\u{1b}", keyCode: 53)
            let closed = await waitUntil(5) { !preview.isVisible || !NSApp.windows.contains(preview) }
            return SpikeRunner.record("step64_esc_in_preview", "closed=\(closed)")
        }
        PageDriver.key(preview, characters: "\r", keyCode: 36)
        var panel: NSSavePanel?
        _ = await waitUntil(10) {
            panel = NSApp.windows.compactMap { $0 as? NSSavePanel }.first(where: \.isVisible)
                ?? NSApp.windows.compactMap { $0.attachedSheet as? NSSavePanel }.first
            return panel != nil
        }
        guard let panel else { return SpikeRunner.record("step64_return", "no save panel in 10 s") }
        SpikeRunner.record("step64_return", "save panel proposed=\(panel.nameFieldStringValue)")
        // The panel's Esc is out of process (ViewBridge): cancelled as its Cancel does.
        if let parent = panel.sheetParent { parent.endSheet(panel, returnCode: .cancel) } else { panel.cancel(nil) }
        _ = await waitUntil(5) { !panel.isVisible }
        try? await Task.sleep(for: .milliseconds(1500))
        // B-95: the next Esc goes to whichever window has the keyboard now; nothing is made key first.
        let key = NSApp.keyWindow
        let keyName = key === preview ? "preview" : key === window ? "Room's window" : key.map { "\(Swift.type(of: $0))" } ?? "none"
        if let key { PageDriver.key(key, characters: "\u{1b}", keyCode: 53) }
        let closed = await waitUntil(4) { !preview.isVisible || !NSApp.windows.contains(preview) }
        SpikeRunner.record("step64_esc_after_panel", "key_after_panel=\(keyName) esc_closed_preview=\(closed)")
        if !closed {
            preview.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            PageDriver.key(preview, characters: "\u{1b}", keyCode: 53)
            let second = await waitUntil(5) { !preview.isVisible || !NSApp.windows.contains(preview) }
            SpikeRunner.record("step64_esc_in_preview", "closed=\(second)")
        }
    }

    // MARK: 4.8, steps 65, 66, 74 (one launch) and 67, 68 (the relaunch)

    private static let windowPages = "http://127.0.0.1:8776/phase-4.8/"

    private func windowMenuTitles() -> [String] {
        (NSApp.windowsMenu?.items ?? []).filter { $0.target is NSWindow || ($0.representedObject as? NSWindow) != nil }.map(\.title)
    }

    private func pageOf(_ tabs: TabController?, _ entry: UUID, suffix: String? = nil, timeout: Double = 15) async -> (any WebContents)? {
        _ = await waitUntil(timeout) {
            guard let page = tabs?.contents(for: entry) else { return false }
            return !page.isLoading && page.url != nil && (suffix == nil || page.url?.absoluteString.hasSuffix(suffix!) == true)
        }
        return tabs?.contents(for: entry)
    }

    private func skippedWindows() async {
        guard let app = AppDelegate.current, let room = app.store, let w1 = app.windows.all.first, let s1 = w1.sidebar, let t1 = w1.tabs else {
            return SpikeRunner.record("error", "skipped windows: no window")
        }
        let model = room.sidebar
        let base = Self.windowPages
        let space = s1.activeSpaceID
        restorePaletteHooks()
        guard let pinA = try? model.addEntry(.pinned, url: base + "a.html", title: "Skipped Pinned A", space: space),
              let pinB = try? model.addEntry(.pinned, url: base + "b.html", title: "Skipped Pinned B", space: space),
              let pinC = try? model.addEntry(.pinned, url: base + "c.html", title: "Skipped Pinned C", space: space) else {
            return SpikeRunner.record("error", "skipped windows: no entries")
        }
        s1.select(pinA.id)
        _ = await pageOf(t1, pinA.id)
        app.newRoomWindow(nil)
        _ = await waitUntil(5) { app.windows.all.count == 2 }
        guard app.windows.all.count == 2, let w2 = app.windows.all.last, let s2 = w2.sidebar, let t2 = w2.tabs else {
            return SpikeRunner.record("error", "skipped windows: ⌘N made no window")
        }
        await pause(500)

        // Step 66: edits in window 1 show in window 2 at once.
        app.windows.focus(w1)
        _ = await waitUntil(3) { NSApp.keyWindow === w1.window }
        guard let todayID = t1.openNewTab(url: base + "d.html") else { return SpikeRunner.record("error", "skipped windows: no Today tab") }
        _ = await pageOf(t1, todayID)
        s1.select(todayID)
        app.togglePin(nil)  // ⌘D
        await nextMainTurn()
        SpikeRunner.record("step66_pin", "kind=\(model.entry(todayID)?.kind.rawValue ?? "nil") window2_lists=\(s2.debugIsListed(todayID)) "
            + "window2_kind=\(s2.debugRowCellKind(todayID))")
        try? model.move([pinC.id], to: .pinned(space: space, folder: nil), insertingAt: 0)
        await nextMainTurn()
        s2.debugOutline.layoutSubtreeIfNeeded()
        func rowY(_ sidebar: SidebarController, _ id: UUID) -> CGFloat {
            sidebar.debugRowView(for: id).map { sidebar.debugOutline.convert($0.bounds, from: $0).minY } ?? -1
        }
        let page = { (e: Entry) in e.liveURL.flatMap { URL(string: $0)?.lastPathComponent } ?? "?" }
        SpikeRunner.record("step66_reorder", "window2 rows y: C=\(Int(rowY(s2, pinC.id))) A=\(Int(rowY(s2, pinA.id))) "
            + "C_above_A=\(rowY(s2, pinC.id) >= 0 && rowY(s2, pinC.id) < rowY(s2, pinA.id)) store=\(model.pinned(space: space).map(page))")
        s1.select(pinB.id)
        app.toggleEssentials(nil)  // ⇧⌘D
        await nextMainTurn()
        SpikeRunner.record("step66_essential", "kind=\(model.entry(pinB.id)?.kind.rawValue ?? "nil") window1_grid=\(s1.debugEssentialIDs.contains(pinB.id)) "
            + "window2_grid=\(s2.debugEssentialIDs.contains(pinB.id)) window2_grid_shown=\(s2.debugEssentialsShown)")
        // ⌘T in each window: the window's own palette, its own Today list.
        var opened: [String] = []
        for (session, name) in [(w1, "e.html"), (w2, "next-a.html")] {
            app.windows.focus(session)
            _ = await waitUntil(3) { NSApp.keyWindow === session.window }
            guard let win = session.window else { continue }
            PageDriver.key(win, characters: "t", keyCode: 17, modifiers: .command)
            _ = await waitUntil(3) { session.palette?.isOpen == true }
            await pause(300)
            session.palette?.setText(base + name)
            await pause(400)
            let field = session.palette?.isOpen == true
            PageDriver.key(win, characters: "\r", keyCode: 36)
            _ = await waitUntil(5) { model.todayEntries(window: session.id).contains { $0.liveURL?.hasSuffix(name) == true } }
            let mine = model.todayEntries(window: session.id).contains { $0.liveURL?.hasSuffix(name) == true }
            let other = app.windows.all.first { $0 !== session }.map { o in model.todayEntries(window: o.id).contains { $0.liveURL?.hasSuffix(name) == true } } ?? true
            let anywhere = model.entries.values.first { $0.liveURL?.hasSuffix(name) == true }
            opened.append("\(name) palette_open=\(field) own_list=\(mine) other_list=\(other) entry=\(anywhere.map { "\($0.kind.rawValue) window_set=\($0.windowID != nil)" } ?? "none")")
        }
        SpikeRunner.record("step66_cmd_t", opened.joined(separator: "; "))
        // Open in New Window on a pinned entry: a third window, cascaded.
        let menu = s2.debugContextMenu(for: pinA.id)
        let item = menu?.items.first { $0.title == CommandName.openInNewWindow }
        let frame2 = w2.window?.frame
        if let menu, let item { menu.performActionForItem(at: menu.index(of: item)) }
        _ = await waitUntil(5) { app.windows.all.count == 3 }
        let w3 = app.windows.all.count == 3 ? app.windows.all.last : nil
        let page3 = await pageOf(w3?.tabs, pinA.id)
        let frame3 = w3?.window?.frame
        SpikeRunner.record("step66_open_in_new_window_pinned", "item=\(item != nil) windows=\(app.windows.all.count) selected=\(w3?.sidebar?.selectedEntryID == pinA.id) "
            + "still_pinned=\(model.entry(pinA.id)?.kind == .pinned) page=\(page3?.url?.lastPathComponent ?? "nil") "
            + "cascade=\(frame2 != nil && frame3 != nil ? String(format: "%.0f,%.0f", frame3!.minX - frame2!.minX, frame2!.maxY - frame3!.maxY) : "nil")")
        if let w3 { w3.window?.performClose(nil) }
        _ = await waitUntil(5) { app.windows.all.count == 2 }

        // Step 74: a page moved by a click keeps its state (no reload) and comes back.
        app.windows.focus(w1)
        s1.select(pinC.id)
        guard let moving = await pageOf(t1, pinC.id) else { return SpikeRunner.record("error", "skipped windows: C did not load") }
        _ = await js(moving, "document.body.insertAdjacentHTML('beforeend', '<input id=skipped>'); document.getElementById('skipped').value = 'half-filled'; window.__skipped = 74; true")
        app.windows.focus(w2)
        s2.select(pinC.id)
        let there = await pageOf(t2, pinC.id)
        let probe = "[window.__skipped, document.getElementById('skipped') && document.getElementById('skipped').value]"
        var state = "nil"
        if let there { state = await js(there, probe) }
        SpikeRunner.record("step74_move", "same_page=\(there === moving) state=\(state) window1_holds=\(t1.contents(for: pinC.id) != nil)")
        app.windows.focus(w1)
        s1.select(pinC.id)
        let back = await pageOf(t1, pinC.id)
        var stateBack = "nil"
        if let back { stateBack = await js(back, probe) }
        SpikeRunner.record("step74_move_back", "same_page=\(back === moving) state=\(stateBack) window2_holds=\(t2.contents(for: pinC.id) != nil)")

        // Step 65: a pinned entry dragged out (the drag's end, as the outline reports it).
        let frame1 = w1.window?.frame ?? .zero
        let drop = NSPoint(x: frame1.minX + 160, y: frame1.minY + 120)
        let count = app.windows.all.count
        s1.debugDragEnded(pinA.id, at: NSPoint(x: frame1.maxX + 200, y: frame1.midY))
        _ = await waitUntil(5) { app.windows.all.count == count + 1 }
        let w4 = app.windows.all.count == count + 1 ? app.windows.all.last : nil
        let page4 = await pageOf(w4?.tabs, pinA.id)
        SpikeRunner.record("step65_drag_pinned", "windows \(count)→\(app.windows.all.count) still_pinned=\(model.entry(pinA.id)?.kind == .pinned) "
            + "listed window1=\(s1.debugIsListed(pinA.id)) new=\(w4?.sidebar?.debugIsListed(pinA.id) ?? false) selected=\(w4?.sidebar?.selectedEntryID == pinA.id) "
            + "page=\(page4?.url?.lastPathComponent ?? "nil") same_space=\(w4?.sidebar?.activeSpaceID == space)")
        _ = drop
        if let w4 { w4.window?.performClose(nil) }
        _ = await waitUntil(5) { app.windows.all.count == count }

        // Step 68's setup: three windows on three spaces, three sizes, three selections.
        guard let profile = model.space(space)?.profileID,
              let second = try? model.createSpace(name: "Skipped Second", profile: profile),
              let third = try? model.createSpace(name: "Skipped Third", profile: profile) else {
            return SpikeRunner.record("error", "skipped windows: spaces")
        }
        app.newRoomWindow(nil)
        _ = await waitUntil(5) { app.windows.all.count == 3 }
        let sessions = app.windows.all
        for (index, (session, target)) in zip(sessions, [space, second.id, third.id]).enumerated() {
            app.windows.focus(session)
            session.sidebar?.showSpace(target, animated: false)
            if target != space, let id = session.tabs?.openNewTab(url: base + (index == 1 ? "b.html" : "c.html"), inSpace: target) {
                session.sidebar?.select(id)
                _ = await pageOf(session.tabs, id)
            }
            if var frame = session.window?.frame {
                frame.size = NSSize(width: 900 + CGFloat(index) * 80, height: 640 + CGFloat(index) * 40)
                frame.origin.x += CGFloat(index) * 60
                session.window?.setFrame(frame, display: true)
            }
        }
        app.windows.focus(sessions[0])
        await pause(800)
        for (index, session) in app.windows.all.enumerated() {
            let selected = session.sidebar?.selectedEntryID.flatMap { model.entry($0)?.liveURL.flatMap { URL(string: $0)?.lastPathComponent } } ?? "none"
            SpikeRunner.record("step68_saved_\(index + 1)", "space=\(session.sidebar.flatMap { model.space($0.activeSpaceID)?.name } ?? "nil") "
                + "selected=\(selected) size=\(session.window.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil") title=\(session.window?.title ?? "nil")")
        }
        SpikeRunner.record("step68_saved", "windows=\(app.windows.all.count) menu=\(windowMenuTitles())")
        room.flush()
    }

    private func nextMainTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        try? await Task.sleep(for: .milliseconds(80))
    }

    private func skippedWindowsRelaunch() async {
        guard let app = AppDelegate.current, let room = app.store, let front = app.windows.all.first else {
            return SpikeRunner.record("error", "skipped windows relaunch: no window")
        }
        let model = room.sidebar
        _ = await waitUntil(15) { front.tabs?.loadedEntryIDs.isEmpty == false && front.tabs?.current?.isLoading == false }
        await pause(500)
        func describe(_ session: WindowSession) -> String {
            let selected = session.sidebar?.selectedEntryID.flatMap { model.entry($0)?.liveURL.flatMap { URL(string: $0)?.lastPathComponent } } ?? "none"
            return "space=\(session.sidebar.flatMap { model.space($0.activeSpaceID)?.name } ?? "nil") selected=\(selected) "
                + "size=\(session.window.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil") loaded=\(session.tabs?.loadedEntryIDs.count ?? 0) "
                + "shown=\(session.selectionShown) title=\(session.window?.title ?? "nil")"
        }
        for (index, session) in app.windows.all.enumerated() { SpikeRunner.record("step68_restored_\(index + 1)", describe(session)) }
        SpikeRunner.record("step68_restored", "windows=\(app.windows.all.count) menu=\(windowMenuTitles())")
        // A click into a background window loads its selection.
        if let back = app.windows.all.last, back !== front {
            back.window?.makeKeyAndOrderFront(nil)
            _ = await waitUntil(10) { back.selectionShown && back.tabs?.loadedEntryIDs.isEmpty == false && back.tabs?.current?.isLoading == false }
            SpikeRunner.record("step68_background_key", describe(back))
        }

        // Step 67: every window closed; the app stays; the Dock brings the last one back where it was.
        var lastFrame: NSRect?
        var lastSpace: String?
        var lastSelected: UUID?
        var lastToday = 0
        let closedBefore = model.archivedCount(reason: .windowClosed)
        while let session = app.windows.all.last {
            if app.windows.all.count == 1 {
                lastFrame = session.window?.frame
                lastSpace = session.sidebar.flatMap { model.space($0.activeSpaceID)?.name }
                lastSelected = session.sidebar?.selectedEntryID
                lastToday = model.todayEntries(window: session.id).count
            }
            let count = app.windows.all.count
            session.window?.performClose(nil)
            _ = await waitUntil(5) { app.windows.all.count < count }
        }
        await pause(500)
        SpikeRunner.record("step67_closed", "windows=\(app.windows.all.count) visible=\(NSApp.windows.filter { $0.isVisible && $0.className.contains("Room") }.count) "
            + "window_menu=\(windowMenuTitles()) windowClosed_rows \(closedBefore)→\(model.archivedCount(reason: .windowClosed)) last_today=\(lastToday)")
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        _ = await waitUntil(10) { app.windows.all.count == 1 && app.windows.all.first?.window?.isVisible == true }
        let again = app.windows.all.first
        let frame = again?.window?.frame
        let same = frame != nil && lastFrame != nil && abs(frame!.minX - lastFrame!.minX) < 1 && abs(frame!.maxY - lastFrame!.maxY) < 1
            && abs(frame!.width - lastFrame!.width) < 1
        SpikeRunner.record("step67_dock_reopen", "windows=\(app.windows.all.count) same_frame=\(same) "
            + "space=\(again?.sidebar.flatMap { model.space($0.activeSpaceID)?.name } ?? "nil") (was \(lastSpace ?? "nil")) "
            + "selection_kept=\(again?.sidebar?.selectedEntryID == lastSelected && lastSelected != nil)")
    }

    // MARK: 4.2, steps 11–14, 16, 18, 19 (the routing fixture; 2.7's site on :8770)

    private func skippedRouting() async {
        guard let app = AppDelegate.current, let room = app.store, let controller = app.sidebar else {
            return SpikeRunner.record("error", "skipped routing: no store or sidebar")
        }
        let model = room.sidebar
        func space(_ name: String) -> Space? { model.spaces.first { $0.name == name } }
        guard let home = space("Space"), let work = space("Work"), let play = space("Play") else {
            return SpikeRunner.record("error", "skipped routing: not the routing fixture")
        }
        func name(_ id: UUID?) -> String { id.flatMap { model.space($0)?.name } ?? "none" }
        func rules() -> String {
            model.routingRules.map { "\($0.position + 1).\($0.match.rawValue) \($0.pattern)→\(name($0.targetSpaceID))\($0.enabled ? "" : " off")" }
                .joined(separator: " | ")
        }
        let site = "http://127.0.0.1:8770/"

        // Steps 11 and 12: links from another process (`open -a` from the wrapper, LaunchServices' event).
        var sent = 0
        func fromTerminal(_ url: String) async -> String {
            app.debugToastCenter?.dismiss(id: "routed")
            sent += 1
            SpikeRunner.record("send_link", "\(sent) \(url)")
            let arrived = await waitUntil(30) { model.entries.values.contains { $0.liveURL == url } }
            await pause(600)
            guard arrived, let entry = model.entries.values.first(where: { $0.liveURL == url }) else { return "not arrived in 30 s" }
            let toast = app.debugToastCenter?.currentToast.flatMap { $0.id == "routed" ? "\"\($0.message)\" button=\($0.action?.title ?? "none") \(Int($0.effectiveDuration)) s" : nil } ?? "none"
            return "space=\(name(entry.spaceID)) shown=\(name(controller.activeSpaceID)) selected_in_space=\(room.windows.selectedEntries.contains(entry.id)) toast=\(toast) "
                + "incoming=\(app.debugIncomingLog.suffix(2).map(\.event))"
        }
        controller.showSpace(home.id, animated: false)
        await pause(600)
        SpikeRunner.record("step11_rule_contains", await fromTerminal(site + "other.html?route=work"))
        // Step 12: hover keeps the toast past its 5 s; the button switches.
        app.debugToastCenter?.queue.setHovering(true)
        try? await Task.sleep(for: .seconds(6))
        let held = app.debugToastCenter?.currentToast?.id == "routed"
        app.debugToastCenter?.queue.setHovering(false)
        let pressed = await pressToastButton(app)
        let routed = model.entries.values.first { $0.liveURL == site + "other.html?route=work" }
        SpikeRunner.record("step12_switch", "hover_held_6s=\(held) pressed=\(pressed) shown=\(name(controller.activeSpaceID)) "
            + "card=\(app.tabs?.currentEntryID == routed?.id && routed != nil ? "the routed tab" : "other") toast_after=\(toastLine(app))")
        controller.showSpace(home.id, animated: false)
        await pause(400)
        SpikeRunner.record("step11_rule_equals", await fromTerminal("http://localhost:8770/site.html"))
        SpikeRunner.record("step11_no_rule", await fromTerminal(site + "site.html?x"))
        SpikeRunner.record("send_link", "done")
        controller.showSpace(home.id, animated: false)
        await pause(400)

        // Step 16: links between spaces with the setting off (⌘-click), plain and ⇧-clicks on and off.
        guard let homeTab = model.today(space: home.id).first(where: { $0.liveURL == site + "site.html" }) else {
            return SpikeRunner.record("error", "skipped routing: no Home tab")
        }
        controller.select(homeTab.id)
        guard let page = app.tabs?.contents(for: homeTab.id) else { return SpikeRunner.record("error", "skipped routing: Home did not load") }
        await waitLoaded(page)
        await pause(400)
        let links = await js(page, "[...document.querySelectorAll('a')].map(a => a.id + '=' + a.getAttribute('href')).join(' ')")
        SpikeRunner.record("step16_page_links", links)
        func commandClickOffsite(_ on: Bool) async -> String {
            room.settings.update { $0.routeLinksBetweenSpaces = on }
            app.debugToastCenter?.dismiss(id: "routed")
            controller.select(homeTab.id)
            await pause(300)
            let before = Set(model.entries.keys)
            await click(page, "#offsite", modifiers: .command)
            _ = await waitUntil(5) { model.entries.keys.contains { !before.contains($0) } }
            await pause(500)
            guard let id = model.entries.keys.first(where: { !before.contains($0) }), let entry = model.entry(id) else { return "no tab" }
            let today = model.today(space: home.id).map(\.id)
            let under = today.firstIndex(of: id).map { $0 == (today.firstIndex(of: homeTab.id) ?? -2) + 1 } ?? false
            let line = "space=\(name(entry.spaceID)) under_home=\(under) toast=\(toastLine(app)) shown=\(name(controller.activeSpaceID))"
            controller.showSpace(home.id, animated: false)
            _ = try? model.remove(id)
            await pause(300)
            return line
        }
        SpikeRunner.record("step16_command_click_on", await commandClickOffsite(true))
        SpikeRunner.record("step16_command_click_off", await commandClickOffsite(false))
        for on in [true, false] {
            room.settings.update { $0.routeLinksBetweenSpaces = on }
            controller.select(homeTab.id)
            await pause(300)
            if page.url?.lastPathComponent != "site.html" { page.load(URL(string: site + "site.html")!, transition: .link, fromAddressBar: false); await waitLoaded(page) }
            let count = model.entries.count
            await click(page, "#offsite", modifiers: .shift)
            _ = await waitUntil(5) { app.tabs?.shownPeek != nil }
            let peek = app.tabs?.shownPeek
            if let peek { await waitLoaded(peek, timeout: 10) }
            let peekLine = "peek=\(peek != nil) peek_url=\(peek?.url?.absoluteString ?? "nil") entries \(count)→\(model.entries.count)"
            _ = app.tabs?.closeShownPeek()
            await pause(400)
            await click(page, "#onsite")
            _ = await waitUntil(5) { page.url?.lastPathComponent == "other.html" && !page.isLoading }
            SpikeRunner.record("step16_\(on ? "on" : "off")_shift_and_plain", "\(peekLine); plain same-site: in place=\(page.url?.lastPathComponent == "other.html") "
                + "entries=\(model.entries.count) toast=\(toastLine(app))")
            page.load(URL(string: site + "site.html")!, transition: .link, fromAddressBar: false)
            await waitLoaded(page)
        }
        room.settings.update { $0.routeLinksBetweenSpaces = false }

        // Step 18: pinned with ⌘D, its off-site link in Peek, ⌘O (expandPeek:): the first Today tab.
        controller.select(homeTab.id)
        await pause(300)
        PageDriver.key(window, characters: "d", keyCode: 2, modifiers: .command)
        await pause(500)
        if model.entry(homeTab.id)?.kind != .pinned { app.togglePin(nil); await pause(400) }
        SpikeRunner.record("step18_pinned", "kind=\(model.entry(homeTab.id)?.kind.rawValue ?? "nil")")
        for (label, parent) in [("pinned", homeTab.id), ("today", nil as UUID?)] {
            var opener = parent
            if opener == nil {
                // A Today tab with tabs below it.
                let ids = ["t1", "t2", "t3"].compactMap { try? model.addEntry(.today, url: site + "site.html?\($0)", title: "Skipped \($0)", space: home.id).id }
                opener = ids.first
            }
            guard let opener else { continue }
            controller.select(opener)
            guard let openerPage = app.tabs?.contents(for: opener) else { continue }
            await waitLoaded(openerPage)
            await pause(300)
            await click(openerPage, "#offsite", modifiers: label == "pinned" ? [] : .shift)
            _ = await waitUntil(5) { app.tabs?.shownPeek != nil }
            if let peek = app.tabs?.shownPeek { await waitLoaded(peek, timeout: 10) }
            let before = Set(model.entries.keys)
            NSApp.sendAction(#selector(AppDelegate.expandPeek(_:)), to: nil, from: nil)
            _ = await waitUntil(5) { model.entries.keys.contains { !before.contains($0) } }
            await pause(400)
            let new = model.entries.keys.first { !before.contains($0) }
            let today = model.today(space: home.id).map(\.id)
            let index = new.flatMap { today.firstIndex(of: $0) }
            let openerIndex = today.firstIndex(of: opener)
            SpikeRunner.record("step18_open_as_tab_\(label)", "peek_was_shown=\(new != nil) selected=\(controller.selectedEntryID == new && new != nil) "
                + "today_index=\(index.map(String.init) ?? "nil") " + (label == "pinned" ? "first=\(index == 0)" : "under_opener=\(index != nil && openerIndex != nil && index! == openerIndex! + 1)"))
        }

        // Step 14: Add Route for Domain… from a Today tab's and a pinned entry's menu; Cancel adds nothing.
        let count14 = model.routingRules.count
        var lines14: [String] = []
        for id in [model.today(space: home.id).first?.id, homeTab.id].compactMap({ $0 }) {
            let menu = controller.debugContextMenu(for: id)
            let item = menu?.items.first { $0.title == CommandName.addRouteForDomain }
            if let menu, let item, item.isEnabled { menu.performActionForItem(at: menu.index(of: item)) }
            await pause(600)
            let editor = app.routingModel
            lines14.append("\(model.entry(id)?.kind.rawValue ?? "?"): item=\(item?.isEnabled ?? false) sheet=\(app.routingSheet?.isVisible ?? false) "
                + "new=\(editor?.editing == .new) pattern=\(editor?.pattern ?? "nil") target=\(name(editor?.target))")
            editor?.cancelEdit()
            app.closeRoutingRules()
            await pause(400)
        }
        SpikeRunner.record("step14_add_route", lines14.joined(separator: "; ") + " rules \(count14)→\(model.routingRules.count)")

        // Step 13: the sheet from the space's menu: untick, chevrons, edit, a regex, ⊖, Try, Return and Esc, Done.
        controller.onRoutingSettings?(nil)
        await pause(800)
        guard let sheet = app.routingSheet, let editor = app.routingModel, model.routingRules.count >= 3 else {
            return SpikeRunner.record("step13_sheet", "shown=false")
        }
        let r1 = model.routingRules[0].id, r2 = model.routingRules[1].id, r3 = model.routingRules[2].id
        SpikeRunner.record("step13_sheet", "shown=\(sheet.isVisible) attached=\(window.attachedSheet === sheet) rules=\(rules())")
        editor.setEnabled(r2, false)
        let off = model.routingRules.first { $0.id == r2 }?.enabled == false
        editor.setEnabled(r2, true)
        editor.move(r3, by: -1)
        let up = rules()
        editor.move(r3, by: 1)
        SpikeRunner.record("step13_toggle_move", "rule2_off=\(off) back_on=\(model.routingRules.first { $0.id == r2 }?.enabled == true) up: \(up) | down: \(rules())")
        editor.beginEdit(r1)
        editor.match = .equals
        editor.pattern = "example.com"
        let edited = editor.save()
        SpikeRunner.record("step13_edit", "saved=\(edited) rule1=\(model.routingRules.first { $0.id == r1 }.map { "\($0.match.rawValue) \($0.pattern)→\(name($0.targetSpaceID))" } ?? "nil")")
        editor.beginNew(match: .regex, pattern: "", target: home.id)
        editor.pattern = "([a-z"
        let inline = editor.patternError ?? "none"
        let greyed = !editor.canSave
        editor.pattern = "^https://docs\\."
        // Return in the pattern field saves (the sheet's default action).
        PageDriver.key(sheet, characters: "\r", keyCode: 36)
        await pause(400)
        let regexRule = model.routingRules.first { $0.match == .regex && $0.pattern == "^https://docs\\." }
        if regexRule == nil, editor.editing == .new { _ = editor.save() }
        let added = model.routingRules.first { $0.match == .regex && $0.pattern == "^https://docs\\." }
        SpikeRunner.record("step13_regex", "inline=\(inline) save_greyed=\(greyed) saved_by_return=\(regexRule != nil) rules=\(model.routingRules.count)")
        if let added { editor.remove(added.id) }
        // Esc while editing cancels the edit, not the sheet.
        editor.beginNew(match: .contains, pattern: "esc-test", target: home.id)
        PageDriver.key(sheet, characters: "\u{1b}", keyCode: 53)
        await pause(400)
        let removedRegex = added != nil && !model.routingRules.contains { $0.id == added?.id }
        SpikeRunner.record("step13_remove_esc", "removed=\(removedRegex) after_esc editing=\(editor.editing == .none ? "none" : "still") "
            + "sheet_open=\(app.routingSheet != nil) rules=\(model.routingRules.count) no_esc_rule=\(!model.routingRules.contains { $0.pattern == "esc-test" })")
        if editor.editing != .none { editor.cancelEdit() }
        editor.tryText = "localhost:8770"
        let tryPlay = editor.tryResult
        editor.tryText = "apple.com"
        SpikeRunner.record("step13_try", "localhost:8770 → \(tryPlay); apple.com → \(editor.tryResult)")
        app.closeRoutingRules()
        await pause(400)
        room.flush()
        SpikeRunner.record("step13_saved", "rules=\(rules())")

        // Step 19: deleting Work takes its rules; Undo (the toast's button) puts them back in place.
        let before19 = rules()
        controller.confirmations = { _ in true }
        controller.deleteSpace(work.id)
        await pause()
        let gone19 = rules()
        let undone = await pressToastButton(app)
        await pause()
        SpikeRunner.record("step19_delete_space_rules", "before: \(before19) | deleted: \(gone19) | undo=\(undone) space_back=\(model.space(work.id) != nil) after: \(rules()) "
            + "same=\(rules() == before19)")
        controller.confirmations = nil
        _ = play
        room.flush()
    }

    /// Step 13's relaunch: the rules as the sheet left them.
    private func skippedRoutingVerify() async {
        guard let room = AppDelegate.current?.store else { return }
        let model = room.sidebar
        func name(_ id: UUID?) -> String { id.flatMap { model.space($0)?.name } ?? "none" }
        SpikeRunner.record("step13_relaunch", "rules=" + model.routingRules.map { "\($0.position + 1).\($0.match.rawValue) \($0.pattern)→\(name($0.targetSpaceID))\($0.enabled ? "" : " off")" }
            .joined(separator: " | "))
    }

    // MARK: 4.3a, steps 20–24 (the sheet's own lines on the 4.3 fixtures)

    private func skippedImportSheet() async {
        guard let app = AppDelegate.current, let room = app.store else { return SpikeRunner.record("error", "skipped import: no store") }
        let model = room.sidebar
        func counts() -> String { "spaces=\(model.spaces.count) entries=\(model.entries.count)" }
        func waitReady(_ sheet: ImportSheetModel) async {
            _ = await waitUntil(20) { sheet.phase == .ready }
            await sheet.settle()
            _ = await waitUntil(5) { sheet.plan != nil }
        }
        func fixture(_ sheet: ImportSheetModel, _ name: String) -> ImportSource? { sheet.sources.first { $0.name == "\(name) (fixture)" } }
        func paletteRows(_ text: String) async -> String {
            guard let palette else { return "no palette" }
            press("⌘T")
            await pause()
            type(text)
            await pause(900)
            let rows = palette.result.matches.prefix(4).map { "\($0.title) [\($0.group)]" }
            press("⎋")
            await pause(300)
            return rows.joined(separator: " | ")
        }
        restorePaletteHooks()

        // Step 20: from the palette; nothing picked, Import greyed; Chrome's lines and the preview following each change; Cancel.
        let before = counts()
        press("⌘T")
        await pause()
        type("import")
        await pause(800)
        let importRows = palette?.result.matches.prefix(5).map(\.title) ?? []
        let commandIndex = palette?.result.matches.firstIndex { $0.title.hasPrefix("Import from another browser") } ?? -1
        for _ in 0..<max(commandIndex, 0) { press("↓") }
        await pause(200)
        press("↩")
        _ = await waitUntil(5) { app.importModel != nil }
        await pause(600)
        guard let sheet = app.importModel else { return SpikeRunner.record("step20_palette", "no sheet; rows=\(importRows) command_index=\(commandIndex)") }
        SpikeRunner.record("step20_palette", "rows=\(importRows) command_index=\(commandIndex) sheet=\(app.importSheet?.isVisible ?? false) picked=\(sheet.selectedSourceID ?? "none") import_enabled=\(sheet.canImport) "
            + "fixtures=\(sheet.sources.filter { $0.name.hasSuffix("(fixture)") }.map(\.name))")
        guard let chrome = fixture(sheet, "chrome") else { return SpikeRunner.record("error", "skipped import: no chrome fixture") }
        sheet.pick(chrome.id)
        await waitReady(sheet)
        SpikeRunner.record("step20_chrome_lines", "profile=\(sheet.profiles.first { $0.directory == sheet.selectedProfile }?.name ?? "nil") "
            + "bookmarks=\"\(sheet.countLine(sheet.scan?.bookmarks) ?? "nil")\" history=\"\(sheet.historyLine() ?? "nil")\" "
            + "extensions=\"\(sheet.extensionsLine() ?? "nil")\" extensions_ticked=\(sheet.importExtensions) passwords_ticked=\(sheet.importPasswords)")
        var steps: [String] = ["start: \(sheet.previewLine)"]
        sheet.barIntoEssentials = true
        await sheet.settle()
        steps.append("bar into Essentials: \(sheet.previewLine) notes=\(sheet.previewNotes)")
        sheet.layout = .spacePerFolder
        await sheet.settle()
        steps.append("one space per folder: \(sheet.previewLine)")
        sheet.targetSpace = model.spaces.first?.id
        await sheet.settle()
        steps.append("into Space: \(sheet.previewLine)")
        sheet.importHistory = false
        await sheet.settle()
        steps.append("no history: \(sheet.previewLine)")
        SpikeRunner.record("step20_preview", steps.joined(separator: " → "))
        SpikeRunner.record("step20_skipped", "\(sheet.plan?.preview.skipped.count ?? -1) skipped")
        app.closeImportSheet()
        await pause(400)
        SpikeRunner.record("step20_cancel", "sheet_gone=\(app.importSheet == nil) \(before) → \(counts())")

        // Step 21: Choose a File or Folder…'s answer (the panel's completion calls addChosen).
        app.showImportSheet(nil)
        await pause(600)
        guard let sheet2 = app.importModel else { return }
        let root = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-4.3")
        var chosen: [String] = []
        for path in ["safari", "netscape/bookmarks.html", "pages"] {
            sheet2.addChosen(root.appending(path: path))
            await waitReady(sheet2)
            let top = sheet2.sources.first
            chosen.append("\(path): top=\(top?.name ?? "nil") selected=\(sheet2.selectedSourceID == top?.id) "
                + "bookmarks=\"\(sheet2.countLine(sheet2.scan?.bookmarks) ?? "nil")\" history=\"\(sheet2.historyLine() ?? "nil")\" message=\"\(sheet2.message ?? "none")\"")
        }
        SpikeRunner.record("step21_choose", chosen.joined(separator: " | "))
        app.closeImportSheet()
        await pause(400)

        // Step 22: Chrome into a new space with the bar into Essentials: the toast, the space's order, history in the palette.
        app.showImportSheet(nil)
        await pause(600)
        guard let sheet3 = app.importModel, let chrome3 = fixture(sheet3, "chrome"), let profile = model.profiles.first else { return }
        sheet3.pick(chrome3.id)
        await waitReady(sheet3)
        sheet3.targetSpace = nil
        sheet3.targetProfile = profile.id
        sheet3.barIntoEssentials = true
        await sheet3.settle()
        let promised = sheet3.previewLine
        await sheet3.performImport()
        await pause(600)
        let toast = app.debugToastCenter?.currentToast.map { "\"\($0.message)\"" } ?? "none"
        let summary: String = if case .done(let text) = sheet3.phase { text } else { "phase not done" }
        app.closeImportSheet()
        await pause(400)
        let google = model.spaces.first { $0.name == "Google Chrome" }
        let order = google.map { space in model.pinned(space: space.id).map { $0.kind == .folder ? ($0.customLabel ?? "folder") : $0.displayTitle } } ?? []
        SpikeRunner.record("step22_import", "promised=\"\(promised)\" toast=\(toast) summary=\"\(summary)\" space=\(google?.name ?? "none") "
            + "essentials=\(model.essentials(profile: profile.id).count) order=\(order)")
        SpikeRunner.record("step22_palette_typed_three", await paletteRows("typed three"))

        // Step 23: Arc's fixture: Home's contents, Work's own Essentials.
        app.showImportSheet(nil)
        await pause(600)
        if let sheet4 = app.importModel, let arc = fixture(sheet4, "arc") {
            sheet4.pick(arc.id)
            await waitReady(sheet4)
            sheet4.targetSpace = nil
            await sheet4.settle()
            await sheet4.performImport()
            await pause(500)
            app.closeImportSheet()
            await pause(400)
            let home = model.spaces.last { $0.name == "Home" }
            let work = model.spaces.last { $0.name == "Work" }
            let homeLine = home.map { space in
                "pinned=\(model.pinned(space: space.id).map { $0.kind == .folder ? "[\($0.customLabel ?? "folder")]" : $0.displayTitle }) "
                    + "today=\(model.today(space: space.id).map(\.displayTitle))"
            } ?? "no Home"
            let workLine = work.map { space in "profile=\(model.profiles.first { $0.id == space.profileID }?.name ?? "?") essentials="
                + "\(model.essentials(profile: space.profileID).map(\.displayTitle))" } ?? "no Work"
            SpikeRunner.record("step23_arc", "Home \(homeLine); Work \(workLine)")
            if let work {
                sidebar.showSpace(work.id, animated: false)
                await pause(500)
                SpikeRunner.record("step23_work_grid", "shown=\(sidebar.debugEssentialsShown) tiles=\(sidebar.debugEssentialIDs.count)")
            }
        }

        // Step 24: Safari per folder; swift.org from the palette.
        app.showImportSheet(nil)
        await pause(600)
        if let sheet5 = app.importModel, let safari = fixture(sheet5, "safari") {
            sheet5.pick(safari.id)
            await waitReady(sheet5)
            sheet5.targetSpace = nil
            sheet5.layout = .spacePerFolder
            await sheet5.settle()
            await sheet5.performImport()
            await pause(500)
            app.closeImportSheet()
            await pause(400)
            SpikeRunner.record("step24_safari", "spaces=\(model.spaces.map(\.name))")
            SpikeRunner.record("step24_palette_swift", await paletteRows("swift.org"))
        }
    }

    // MARK: 4.4a, step 33: a search engine added through the editor's path and used from the palette

    private func skippedSearch() async {
        guard let app = AppDelegate.current, let room = app.store, let profile = room.sidebar.space(sidebar.activeSpaceID)?.profileID else {
            return SpikeRunner.record("error", "skipped search: no store")
        }
        restorePaletteHooks()
        // The editor's save (SettingsWindow's `save`): %s back to {searchTerms}, the problem shown or the engine stored.
        func save(_ engine: SearchEngineSetting) -> String {
            var stored = engine
            stored.searchURL = SearchEngines.storedURL(engine.searchURL)
            var problem: SearchEngines.Problem?
            room.settings.update { value in
                do throws(SearchEngines.Problem) { try SearchEngines.save(stored, in: &value) } catch { problem = error }
            }
            return problem?.message ?? "saved"
        }
        // MDN's shape on the local server (the check is the engine path, not MDN's page).
        let noPlaceholder = save(SearchEngineSetting(id: "custom-mdn", name: "MDN", keyword: "mdn", searchURL: "http://127.0.0.1:8770/site.html"))
        let saved = save(SearchEngineSetting(id: "custom-mdn", name: "MDN", keyword: "mdn", searchURL: "http://127.0.0.1:8770/site.html?mdn=%s"))
        let engines = SearchEngines.list(room.settings.settings)
        room.settings.update { $0.searchEngineByProfile[profile.uuidString] = "custom-mdn" }
        let blocked = SearchEngines.removalBlocked("custom-mdn", in: room.settings.settings, profiles: room.sidebar.profiles.map(\.id)) ?? "not blocked"
        SpikeRunner.record("step33_add", "without %s: \(noPlaceholder) | with: \(saved) engines=\(engines.map(\.name)) remove while default: \(blocked)")
        press("⌘T")
        await pause()
        type("fetch api")
        await pause(700)
        press("↩")
        _ = await waitUntil(10) { tabs.current?.url?.absoluteString.contains("mdn=") == true }
        SpikeRunner.record("step33_query", "url=\(tabs.current?.url?.absoluteString ?? "nil")")
        // A keyword with Tab: `yt`, Tab, `cats`, Enter; the URL the palette commits is read, not YouTube's page.
        press("⌘T")
        await pause()
        let openForKeyword = palette?.isOpen ?? false
        if !openForKeyword {
            // ⌘T with the keyboard in the results page (the step's own sequence is ⌘T again): its first responder, then the palette directly.
            SpikeRunner.record("step33_cmd_t_from_page", "palette not open; first_responder=\(window.firstResponder.map { "\(Swift.type(of: $0))" } ?? "nil")")
            palette?.toggleNew()
            await pause()
        }
        type("yt")
        await pause(400)
        let ytRows = palette?.result.matches.prefix(3).map { "\($0.title)" } ?? []
        press("⇥")
        await pause(300)
        let chip = palette?.siteSearch.map { "\($0.name)" } ?? "none"
        type("cats")
        await pause(500)
        press("↩")
        _ = await waitUntil(10) { tabs.current?.url?.host?.contains("youtube") == true }
        SpikeRunner.record("step33_keyword", "open=\(openForKeyword) rows=\(ytRows) chip=\(chip) url=\(tabs.current?.url?.absoluteString ?? "nil")")
        room.settings.update { $0.searchEngineByProfile[profile.uuidString] = nil }
        var removed = false
        room.settings.update { removed = SearchEngines.remove("custom-mdn", in: &$0, profiles: room.sidebar.profiles.map(\.id)) }
        SpikeRunner.record("step33_remove", "back to the default; removed=\(removed) engines=\(SearchEngines.list(room.settings.settings).map(\.name))")
    }

    // MARK: 4.5, steps 46 and 47 (the 3.6 fixture unpacked; 2.7's site)

    private func skippedExtensions() async {
        guard let app = AppDelegate.current, let room = app.store, let center = app.extensions, let section = center.sections.first else {
            return SpikeRunner.record("error", "skipped extensions: no extensions")
        }
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        guard let id = try? await section.extensions.loadUnpacked(at: fixture) else { return SpikeRunner.record("error", "skipped extensions: load unpacked") }
        _ = await waitUntil(5) { center.sections.first?.installed.first { $0.id == id }?.action?.icon != nil }
        guard let item = center.sections.first?.installed.first(where: { $0.id == id }) else { return }
        // Step 47: what Details shows (SettingsWindow's `details`), and Allow in incognito stored for the relaunch.
        let size = item.directory.map { ExtensionStatements.directorySize($0) } ?? -1
        SpikeRunner.record("step47_details", "version=\(item.version) source=\(item.isUnpacked ? "Unpacked from \(item.directory?.path ?? "?")" : "other") id=\(item.id) "
            + "size=\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) can=\(item.permissionMessages)")
        room.settings.update { $0.setAllowsInIncognito(true, id, profile: section.id) }
        await pause(500)
        SpikeRunner.record("step47_incognito_set", "stored=\(room.settings.settings.allowsInIncognito(id, profile: section.id)) "
            + "engine=\((section.extensions as? RoomCoreExtensionsProbe)?.allowedInIncognito(id).description ?? "n/a")")

        // Step 46: On click, the site panel's row, its "…" menu (Unpin, Options, Manage Extensions…), Run and Always on, the badge.
        guard let page = await open(URL(string: "http://127.0.0.1:8770/site.html")!) else { return }
        center.setSiteAccess(.onClick, id, profile: section.id, host: "127.0.0.1")
        page.reload()
        await waitLoaded(page)
        app.showSitePanel()
        _ = await waitUntil(3) { app.sitePanel.isShown }
        guard let model = app.sitePanel.model?.extensions else { return SpikeRunner.record("error", "skipped extensions: no site panel section") }
        _ = await waitUntil(3) { model.rows.first { $0.id == id }?.access.wantsToRun == true }
        let row = { model.rows.first { $0.id == id } }
        SpikeRunner.record("step46_row", "name=\(row()?.name ?? "nil") run=\(row()?.access.wantsToRun ?? false) level=\(row()?.access.level.rawValue ?? -1) "
            + "pinned=\(row()?.isPinned ?? false) has_options=\(row()?.hasOptions ?? false)")
        model.togglePin(id)
        let unpinned = await waitUntil(3) { model.refresh(); return row()?.isPinned == false }
        let headerWithout = !(sidebar.extensionBar.extensionActionIDs.contains(id))
        model.togglePin(id)
        _ = await waitUntil(3) { model.refresh(); return row()?.isPinned == true }
        let tabsBefore = room.sidebar.entries.count
        model.openOptions(id)
        _ = await waitUntil(5) { room.sidebar.entries.values.contains { $0.liveURL?.contains("options.html") == true } }
        let options = room.sidebar.entries.values.first { $0.liveURL?.contains("options.html") == true }
        SpikeRunner.record("step46_menu", "unpin=\(unpinned) header_without=\(headerWithout) pinned_again=\(row()?.isPinned ?? false) options_tab=\(options != nil) entries \(tabsBefore)→\(room.sidebar.entries.count)")
        if let options { _ = try? room.sidebar.remove(options.id) }
        sidebar.select(tabs.entryID(for: page))
        await pause(400)
        if !app.sitePanel.isShown { app.showSitePanel(); _ = await waitUntil(3) { app.sitePanel.isShown } }
        app.sitePanel.model?.extensions?.openManagement()
        _ = await waitUntil(5) { app.debugSettingsWindow?.window?.isVisible == true }
        await pause(500)
        SpikeRunner.record("step46_manage", "panel_closed=\(!app.sitePanel.isShown) settings=\(app.debugSettingsWindow?.window?.isVisible ?? false) "
            + "title=\(app.debugSettingsWindow?.window?.title ?? "nil")")
        app.debugSettingsWindow?.window?.close()
        window.makeKeyAndOrderFront(nil)
        await pause(300)
        app.showSitePanel()
        _ = await waitUntil(3) { app.sitePanel.isShown }
        app.sitePanel.model?.extensions?.run(id)
        await pause(800)
        app.sitePanel.model?.extensions?.setAccess(.onSite, for: id)
        app.sitePanel.close()
        page.reload()
        await waitLoaded(page)
        await pause(1200)
        let badge = center.headerActions(profile: section.id, page: page).first { $0.id == id }?.badgeText ?? "none"
        SpikeRunner.record("step46_badge_after_reload", "badge=\(badge) level=\(center.siteAccess(id, profile: section.id, page: page)?.level.rawValue ?? -1)")
        center.setSiteAccess(.onAllSites, id, profile: section.id, host: "127.0.0.1")
        room.flush()
    }

    /// Step 47's relaunch: still ticked, and the engine told at launch.
    private func skippedExtensionsVerify() async {
        guard let app = AppDelegate.current, let room = app.store, let center = app.extensions, let section = center.sections.first else { return }
        _ = await waitUntil(10) { section.extensions.isReady && !section.installed.isEmpty }
        await pause(800)
        let lines = section.installed.map { item in
            "\(item.name): stored=\(room.settings.settings.allowsInIncognito(item.id, profile: section.id)) "
                + "engine=\((section.extensions as? RoomCoreExtensionsProbe)?.allowedInIncognito(item.id).description ?? "n/a")"
        }
        SpikeRunner.record("step47_relaunch", lines.isEmpty ? "no extension" : lines.joined(separator: "; "))
        // Step 73 on the fixture: the incognito window's header has the allowed extension, and its popup opens there.
        guard let item = section.installed.first, let incognito = app.openIncognitoWindow(profileID: section.id) else {
            return SpikeRunner.record("step73_incognito", "no incognito window")
        }
        _ = await waitUntil(5) { incognito.sidebar?.extensionBar.extensionActionIDs.contains(item.id) == true }
        let engine = (section.extensions as? RoomCoreExtensionsProbe)?.allowedInIncognito(item.id).description ?? "n/a"
        if let tabs = incognito.tabs, let id = tabs.openNewTab(url: "http://127.0.0.1:8770/site.html") {
            incognito.sidebar?.select(id)
            if let page = tabs.contents(for: id) { await waitLoaded(page) }
        }
        let events = installPopupHooks()
        incognito.sidebar?.extensionBar.onExtensionAction?(item.id)
        _ = await waitUntil(5) { events.popover != nil }
        await pause(500)
        let parent = events.popover?.window?.parent
        SpikeRunner.record("step73_incognito", "header=\(incognito.sidebar?.extensionBar.extensionActionIDs.contains(item.id) ?? false) engine_after_open=\(engine) "
            + "popup=\(events.popover != nil) over_incognito=\(parent != nil && parent === incognito.window)")
        events.popover?.close()
    }
}
#endif
