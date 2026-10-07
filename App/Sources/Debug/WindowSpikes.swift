#if DEBUG
import AppKit
import Engine
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 4.8a spike `windows` (`Room -RoomSpike windows`; the tour's step
/// `windows` through `scripts/windows-check.sh`, which serves
/// `research/spikes` on :8777 and runs three launches on one state).
/// Sections (`-RoomSpikeOnly` picks one per launch): `main` (⌘N; a pinned
/// entry renamed in window 1 read back from window 2's row; a Today tab per
/// window; a pinned page navigated in window 1 then selected in window 2
/// moves with its history while window 1 falls back to its most recent
/// entry; ⌘1 in window 2; "Open in New Window" from the context menu; the
/// drag out below and past the threshold; a second space and a frame of its
/// own for window 2; the state recorded for the relaunch), `relaunch` (every
/// window back with its frame, active space and Today tabs, only the front
/// one loaded; closing window 2 archives its Today tab with `windowClosed`;
/// closing the last window keeps the app, ⌘N and the Dock reopen it),
/// `memory` (ten live pages in one window, then over two windows: summed RSS
/// and renderers, on the release framework for the numbers).
extension SpikeRunner.Context {
    func windowsChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        if runs("main") { await windowsMain() }
        if runs("relaunch") { await windowsRelaunch() }
        if runs("memory") { await windowsMemory() }
    }

    static let windowsBase = "http://127.0.0.1:8777/phase-4.8/"

    private func frameText(_ frame: NSRect?) -> String {
        frame.map { String(format: "%.0f,%.0f %.0fx%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "nil"
    }

    private func keyWindowIndex(_ app: AppDelegate) -> String {
        guard let key = NSApp.keyWindow, let index = app.windows.all.firstIndex(where: { $0.window === key }) else { return "none" }
        return "\(index + 1)"
    }

    private func pressMenuKey(_ window: NSWindow?, _ character: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command) -> Bool {
        if let window {
            PageDriver.key(window, characters: character, keyCode: keyCode, modifiers: modifiers)
            return true
        }
        // No window: the menu bar takes the key equivalent itself.
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
                                           isARepeat: false, keyCode: keyCode) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    private func waitPage(_ tabs: TabController?, _ entry: UUID, url: String? = nil, timeout: Double = 15) async -> (any WebContents)? {
        _ = await waitUntil(timeout) {
            guard let page = tabs?.contents(for: entry) else { return false }
            return !page.isLoading && page.url != nil && (url == nil || page.url?.absoluteString.hasSuffix(url!) == true)
        }
        return tabs?.contents(for: entry)
    }

    /// One turn of the main queue (the losing window's fallback runs on it).
    private func nextTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        try? await Task.sleep(for: .milliseconds(50))
    }

    // MARK: main

    func windowsMain() async {
        await activate()
        guard let app = AppDelegate.current, let store = app.store, let w1 = app.windows.all.first, let s1 = w1.sidebar, let t1 = w1.tabs else {
            return SpikeRunner.record("error", "no window")
        }
        let base = Self.windowsBase
        let space = s1.activeSpaceID
        guard let pinA = try? store.sidebar.addEntry(.pinned, url: base + "a.html", title: "Pinned A", space: space),
              let pinB = try? store.sidebar.addEntry(.pinned, url: base + "b.html", title: "Pinned B", space: space),
              let pinC = try? store.sidebar.addEntry(.pinned, url: base + "c.html", title: "Pinned C", space: space) else {
            return SpikeRunner.record("error", "no fixture entries")
        }
        // Window 1: C, then B navigated to its second page (history to keep).
        s1.select(pinC.id)
        _ = await waitPage(t1, pinC.id)
        try? await Task.sleep(for: .milliseconds(30))
        s1.select(pinB.id)
        guard let first = await waitPage(t1, pinB.id) else { return SpikeRunner.record("error", "pinned B did not load in window 1") }
        first.load(URL(string: base + "next-b.html")!, transition: .link, fromAddressBar: false)
        _ = await waitPage(t1, pinB.id, url: "next-b.html")
        _ = await waitUntil(3) { first.canGoBack }
        SpikeRunner.record("pinned_window1", "url=\(first.url?.lastPathComponent ?? "nil") canGoBack=\(first.canGoBack) loaded_w1=\(t1.loadedEntryIDs.count)")

        // ⌘N through the menu's key path.
        let start = ContinuousClock.now
        let frame1 = w1.window?.frame
        _ = pressMenuKey(w1.window, "n", keyCode: 45)
        _ = await waitUntil(5) { app.windows.all.count == 2 }
        guard app.windows.all.count == 2, let w2 = app.windows.all.last, let s2 = w2.sidebar, let t2 = w2.tabs else {
            return SpikeRunner.record("new_window", "failed windows=\(app.windows.all.count)")
        }
        let newMs = ms(since: start)
        _ = await waitUntil(3) { NSApp.keyWindow === w2.window }
        let frame2 = w2.window?.frame
        let offset = (frame1 != nil && frame2 != nil) ? String(format: "%.0f,%.0f", frame2!.minX - frame1!.minX, frame1!.maxY - frame2!.maxY) : "nil"
        SpikeRunner.record("new_window", String(format: "by ⌘N windows=%d in %.1f ms ", app.windows.all.count, newMs)
            + "key=\(keyWindowIndex(app)) active_is_new=\(app.activeWindow === w2) frame1=\(frameText(frame1)) frame2=\(frameText(frame2)) "
            + "cascade=\(offset) same_space=\(s2.activeSpaceID == space) today=\(store.sidebar.today(space: space, window: w2.id).count) "
            + "selected=\(s2.selectedEntryID.map { _ in "some" } ?? "none") card_empty=\(w2.pageHost.contents == nil) "
            + "rows=\(store.windows.windows.count) title=\"\(w2.window?.title ?? "")\" window_menu=\(windowMenuTitles().count)")

        // A rename of a shared entry in window 1, read back from window 2's row.
        let before2 = s2.debugRowTitle(for: pinA.id) ?? "nil"
        let renameStart = ContinuousClock.now
        try? store.sidebar.rename(pinA.id, to: "Renamed in window 1")
        let renameMs = ms(since: renameStart)
        SpikeRunner.record("shared_rename", "window2_row \"\(before2)\"→\"\(s2.debugRowTitle(for: pinA.id) ?? "nil")\" "
            + "window1_row=\"\(s1.debugRowTitle(for: pinA.id) ?? "nil")\" " + String(format: "in %.2f ms (same turn)", renameMs))

        // Today tabs per window: two in window 2 (one stays, one opens in a new window later).
        guard let tab2 = t2.openNewTab(url: base + "d.html", transition: .link) else { return SpikeRunner.record("error", "no Today tab in window 2") }
        _ = await waitPage(t2, tab2)
        guard let tab2b = t2.openBackgroundTab(url: base + "e.html", transition: .link) else { return SpikeRunner.record("error", "no second Today tab") }
        _ = await waitPage(t2, tab2b)
        SpikeRunner.record("today_per_window", "window2_today=\(store.sidebar.today(space: space, window: w2.id).count) "
            + "window1_today=\(store.sidebar.today(space: space, window: w1.id).count) tab_window=\(store.sidebar.entry(tab2)?.windowID == w2.id ? "2" : "?") "
            + "listed_window2=\(s2.debugIsListed(tab2)) listed_window1=\(s1.debugIsListed(tab2)) "
            + "pinned_listed_both=\(s1.debugIsListed(pinB.id) && s2.debugIsListed(pinB.id))")

        // The pinned page selected in window 2 moves there with its history.
        app.windows.focus(w2)
        let moveStart = ContinuousClock.now
        s2.select(pinB.id)
        let moved = await waitPage(t2, pinB.id, url: "next-b.html")
        let moveMs = ms(since: moveStart)
        _ = await waitUntil(3) { moved?.canGoBack == true }
        await nextTurn()
        _ = await waitUntil(5) { s1.selectedEntryID == pinC.id && w1.pageHost.contents != nil }
        var history = "nil"
        if let moved { history = await js(moved, "history.length") }
        SpikeRunner.record("pinned_move", String(format: "in %.0f ms ", moveMs)
            + "window1_page_closed=\(first.state == .closed) window1_holds=\(t1.contents(for: pinB.id) != nil) "
            + "window1_selected=\(s1.selectedEntryID == pinC.id ? "C (its MRU)" : s1.selectedEntryID?.uuidString ?? "none") "
            + "window1_card_shows_mru=\(w1.pageHost.contents != nil && w1.pageHost.contents === t1.contents(for: pinC.id)) "
            + "window2_url=\(moved?.url?.lastPathComponent ?? "nil") window2_canGoBack=\(moved?.canGoBack ?? false) history_length=\(history) "
            + "window2_card=\(w2.pageHost.contents != nil && w2.pageHost.contents === moved) owners=\(app.windows.owners.owners[pinB.id] == w2.id ? "2" : "?")")
        if let moved, moved.canGoBack {
            moved.goBack()
            _ = await waitPage(t2, pinB.id, url: "b.html")
            SpikeRunner.record("pinned_move_back", "url=\(moved.url?.lastPathComponent ?? "nil")")
            moved.goForward()
            _ = await waitPage(t2, pinB.id, url: "next-b.html")
        }

        // ⌘1 in window 2: its first entry (the first pinned: A); window 1's selection stays.
        app.windows.focus(w2)
        _ = await waitUntil(3) { NSApp.keyWindow === w2.window }
        let expected = store.sidebar.sidebarOrder(space: s2.activeSpaceID, window: w2.id).first?.id
        _ = pressMenuKey(w2.window, "1", keyCode: 18)
        _ = await waitUntil(3) { s2.selectedEntryID == expected }
        SpikeRunner.record("cmd1_window2", "key=\(keyWindowIndex(app)) selected_first=\(s2.selectedEntryID != nil && s2.selectedEntryID == expected) "
            + "is_pinA=\(expected == pinA.id) window1_selection_kept=\(s1.selectedEntryID == pinC.id)")

        // ⌃Tab's list is the window's own.
        let recent2 = s2.recentEntries(limit: 10).map(\.id)
        let recent1 = s1.recentEntries(limit: 10).map(\.id)
        SpikeRunner.record("switcher_per_window", "window2_has_its_tab=\(recent2.contains(tab2)) window1_has_window2_tab=\(recent1.contains(tab2))")

        // "Open in New Window" from window 2's context menu on its second Today tab.
        let menu = s2.debugContextMenu(for: tab2b)
        let item = menu?.items.first { $0.title == CommandName.openInNewWindow }
        let frameW2 = w2.window?.frame
        if let menu, let item { menu.performActionForItem(at: menu.index(of: item)) }
        _ = await waitUntil(5) { app.windows.all.count == 3 }
        let w3 = app.windows.all.count == 3 ? app.windows.all.last : nil
        let w3Page = await waitPage(w3?.tabs, tab2b)
        let frame3 = w3?.window?.frame
        SpikeRunner.record("open_in_new_window", "item=\(item != nil) enabled=\(item?.isEnabled ?? false) windows=\(app.windows.all.count) "
            + "selected=\(w3?.sidebar?.selectedEntryID == tab2b) tab_window=\(store.sidebar.entry(tab2b)?.windowID == w3?.id ? "3" : "?") "
            + "window2_lists=\(s2.debugIsListed(tab2b)) window3_lists=\(w3?.sidebar?.debugIsListed(tab2b) ?? false) "
            + "page=\(w3Page?.url?.lastPathComponent ?? "nil") window2_holds=\(t2.contents(for: tab2b) != nil) "
            + "cascade=\(frameW2 != nil && frame3 != nil ? String(format: "%.0f,%.0f", frame3!.minX - frameW2!.minX, frameW2!.maxY - frame3!.maxY) : "nil")")

        // The drag out (spec §A.9): a Today tab of window 1 dropped 20 pt past its edge, then 100 pt.
        app.windows.focus(w1)
        guard let drag = t1.openNewTab(url: base + "a.html", transition: .link), let w1Frame = w1.window?.frame else {
            return SpikeRunner.record("error", "no drag tab")
        }
        _ = await waitPage(t1, drag)
        let near = NSPoint(x: w1Frame.maxX + 20, y: w1Frame.midY)
        s1.debugDragEnded(drag, at: near)
        try? await Task.sleep(for: .milliseconds(200))
        let countNear = app.windows.all.count
        // Left of the window, where a window of its size fits on the screen.
        let point = NSPoint(x: w1Frame.minX - 100, y: w1Frame.maxY - 40)
        let past = DragOutRule.opensWindow(at: point, windowFrame: w1Frame)
        s1.debugDragEnded(drag, at: point)
        _ = await waitUntil(5) { app.windows.all.count == countNear + 1 }
        let w4 = app.windows.all.count == countNear + 1 ? app.windows.all.last : nil
        _ = await waitPage(w4?.tabs, drag)
        await nextTurn()
        let frame4 = w4?.window?.frame
        SpikeRunner.record("drag_out", "near(20pt)_windows=\(countNear) past(\(past ? "beyond" : "inside") 40pt)_windows=\(app.windows.all.count) "
            + "drop=\(String(format: "%.0f,%.0f", point.x, point.y)) frame=\(frameText(frame4)) top_left_at_drop=\(frame4.map { abs($0.minX - point.x) < 2 && abs($0.maxY - point.y) < 2 } ?? false) "
            + "selected=\(w4?.sidebar?.selectedEntryID == drag) kind=\(store.sidebar.entry(drag)?.kind.rawValue ?? "nil") "
            + "tab_window=\(store.sidebar.entry(drag)?.windowID == w4?.id ? "4" : "?") window1_selected=\(s1.selectedEntryID == pinC.id ? "C" : "other")")

        // A Today tab of window 1 that stays; window 2 on a second space with a frame of its own.
        app.windows.focus(w1)
        let tab1 = t1.openNewTab(url: base + "c.html", transition: .link)
        if let tab1 { _ = await waitPage(t1, tab1) }
        let second = try? store.sidebar.createSpace(name: "Second", profile: store.sidebar.profiles[0].id)
        if let second { s2.showSpace(second.id, animated: false) }
        w2.window?.setFrame(NSRect(x: 260, y: 140, width: 1100, height: 720), display: true)
        try? await Task.sleep(for: .milliseconds(300))
        store.flush()
        for (index, session) in app.windows.all.enumerated() {
            let record = store.windows.window(session.id)
            let todays = store.sidebar.todayEntries(window: session.id).compactMap { $0.currentURL.flatMap { URL(string: $0)?.lastPathComponent } }
            SpikeRunner.record("saved_window_\(index + 1)", "id=\(session.id.uuidString.prefix(8)) frame=\(frameText(record?.frame)) "
                + "space=\(record?.activeSpaceID.flatMap { store.sidebar.space($0)?.name } ?? "nil") today=\(todays) loaded=\(session.tabs?.loadedEntryIDs.count ?? 0)")
        }
        SpikeRunner.record("saved", "windows=\(app.windows.all.count) rows=\(store.windows.windows.count) tab1=\(tab1 != nil) key=\(keyWindowIndex(app))")
    }

    private func windowMenuTitles() -> [String] {
        (NSApp.windowsMenu?.items ?? []).filter { $0.target is NSWindow || ($0.representedObject as? NSWindow) != nil }.map(\.title)
    }

    // MARK: relaunch

    func windowsRelaunch() async {
        await activate()
        guard let app = AppDelegate.current, let store = app.store, let front = app.windows.all.first else { return SpikeRunner.record("error", "no window") }
        // Wait for the front window's selection to load (its profile arrives after launch).
        _ = await waitUntil(15) { front.tabs?.loadedEntryIDs.isEmpty == false && front.tabs?.current?.isLoading == false }
        for (index, session) in app.windows.all.enumerated() {
            let record = store.windows.window(session.id)
            let todays = store.sidebar.todayEntries(window: session.id).compactMap { $0.currentURL.flatMap { URL(string: $0)?.lastPathComponent } }
            let shown = session.window?.frame
            SpikeRunner.record("restored_window_\(index + 1)", "id=\(session.id.uuidString.prefix(8)) frame=\(frameText(shown)) stored=\(frameText(record?.frame)) "
                + "frame_matches=\(shown != nil && record?.frame != nil && abs(shown!.minX - record!.frame!.minX) < 1 && abs(shown!.width - record!.frame!.width) < 1 && abs(shown!.maxY - record!.frame!.maxY) < 1) "
                + "space=\(session.sidebar.flatMap { store.sidebar.space($0.activeSpaceID)?.name } ?? "nil") today=\(todays) "
                + "loaded=\(session.tabs?.loadedEntryIDs.count ?? 0) selection_shown=\(session.selectionShown)")
        }
        let withD = app.windows.all.first { session in store.sidebar.todayEntries(window: session.id).contains { $0.currentURL?.hasSuffix("d.html") == true } }
        let withDIndex = withD.flatMap { session in app.windows.all.firstIndex { $0 === session } }.map { "\($0 + 1)" } ?? "none"
        SpikeRunner.record("restored", "windows=\(app.windows.all.count) rows=\(store.windows.windows.count) key=\(keyWindowIndex(app)) "
            + "loaded_windows=\(app.windows.all.filter { !($0.tabs?.loadedEntryIDs.isEmpty ?? true) }.count) today_d_in_window=\(withDIndex) "
            + "today_d_in_front=\(store.sidebar.todayEntries(window: front.id).contains { $0.currentURL?.hasSuffix("d.html") == true })")

        // Closing the window with the d.html Today tab archives it (windowClosed).
        if let withD, let dEntry = store.sidebar.todayEntries(window: withD.id).first(where: { $0.currentURL?.hasSuffix("d.html") == true }) {
            let count = app.windows.all.count
            withD.window?.performClose(nil)
            _ = await waitUntil(5) { app.windows.all.count == count - 1 }
            let row = store.sidebar.archive[dEntry.id]
            let libraryRow = store.sidebar.archivedByDay().flatMap(\.rows).first { $0.id == dEntry.id }
            SpikeRunner.record("close_window", "windows \(count)→\(app.windows.all.count) rows=\(store.windows.windows.count) "
                + "entry_gone=\(store.sidebar.entry(dEntry.id) == nil) archived=\(row?.reason.rawValue ?? "no") library_row=\(libraryRow?.displayTitle ?? "none") "
                + "windowClosed_rows=\(store.sidebar.archivedCount(reason: .windowClosed))")
            // Restorable from the Library into the window that asks.
            if let restored = app.restoreArchived(dEntry.id) {
                SpikeRunner.record("close_window_restore", "restored=\(store.sidebar.entry(restored)?.windowID == app.activeWindow?.id ? "into the active window" : "elsewhere")")
            }
        } else {
            SpikeRunner.record("close_window", "no window with d.html")
        }

        // Closing every window keeps the app; ⌘N reopens one on the last state, and so does the Dock.
        for session in app.windows.all { session.window?.performClose(nil) }
        _ = await waitUntil(5) { app.windows.all.isEmpty }
        let kept = store.windows.windows.first
        let visible = NSApp.windows.filter { $0 is RoomWindow && $0.isVisible }.count
        SpikeRunner.record("close_last", "windows=\(app.windows.all.count) visible=\(visible) app_running=\(NSApp.isRunning) rows_kept=\(store.windows.windows.count) "
            + "kept_frame=\(frameText(kept?.frame))")
        let took = pressMenuKey(nil, "n", keyCode: 45)
        _ = await waitUntil(5) { app.windows.all.count == 1 }
        let reopened = app.windows.all.first
        SpikeRunner.record("reopen_cmd_n", "menu_took=\(took) windows=\(app.windows.all.count) same_row=\(reopened?.id == kept?.id) "
            + "frame=\(frameText(reopened?.window?.frame)) visible=\(reopened?.window?.isVisible ?? false)")
        reopened?.window?.performClose(nil)
        _ = await waitUntil(5) { app.windows.all.isEmpty }
        _ = app.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        _ = await waitUntil(5) { app.windows.all.count == 1 }
        SpikeRunner.record("reopen_dock", "windows=\(app.windows.all.count) visible=\(app.windows.all.first?.window?.isVisible ?? false)")
    }

    // MARK: memory

    /// Ten live pages (`typicalSites`) in one window (`-RoomWindowsMemoryWindows 1`)
    /// or over two windows (2, the default: five each, one shown in each card),
    /// each on a fresh launch (pages closed earlier leave renderers behind,
    /// B-56): summed RSS over the process tree after loading and 8 s (the
    /// `memory` spike's method).
    func windowsMemory() async {
        await activate()
        guard let app = AppDelegate.current, let store = app.store, let w1 = app.windows.all.first, let s1 = w1.sidebar, let t1 = w1.tabs else {
            return SpikeRunner.record("error", "no window")
        }
        let count = UserDefaults.standard.integer(forKey: "RoomWindowsMemoryWindows") == 1 ? 1 : 2
        _ = await open(URL(string: "about:blank")!)
        try? await Task.sleep(for: .seconds(3))
        let baseline = ProcessMemory.snapshot()
        SpikeRunner.record("memory_baseline_\(count)", baseline.summary)
        // The baseline's blank page goes, so the counts below are the ten pages.
        if let blank = t1.currentEntryID {
            s1.select(nil)
            t1.unload(blank)
            store.sidebar.archive([blank], reason: .manual)
        }
        let space = s1.activeSpaceID
        var sessions = [w1]
        if count == 2 {
            app.newRoomWindow(nil)
            _ = await waitUntil(5) { app.windows.all.count == 2 }
            guard let w2 = app.windows.all.last, w2 !== w1 else { return SpikeRunner.record("error", "no second window") }
            sessions.append(w2)
        }
        let sites = Self.typicalSites
        var groups: [(WindowSession, [UUID])] = []
        for (index, session) in sessions.enumerated() {
            let share = count == 1 ? sites : Array(index == 0 ? sites.prefix(5) : sites.suffix(5))
            let ids = share.compactMap { url -> UUID? in
                guard let entry = try? store.sidebar.addEntry(.today, url: url, space: space, window: session.id) else { return nil }
                session.tabs?.loadInBackground(entry)
                return entry.id
            }
            // One page shown in each card.
            if let first = ids.first { session.sidebar?.select(first) }
            groups.append((session, ids))
        }
        let start = Date()
        _ = await waitUntil(90) { groups.allSatisfy { session, ids in ids.allSatisfy { session.tabs?.contents(for: $0)?.isLoading == false } } }
        let seconds = Int(Date().timeIntervalSince(start))
        try? await Task.sleep(for: .seconds(8))
        var loaded = 0
        for (session, ids) in groups { loaded += ids.filter { session.tabs?.contents(for: $0)?.isLoading == false }.count }
        let snapshot = ProcessMemory.snapshot()
        let pages = groups.enumerated().map { "pages_window\($0.offset + 1)=\($0.element.0.tabs?.loadedEntryIDs.count ?? 0)" }.joined(separator: " ")
        SpikeRunner.record("memory_windows_\(count)", snapshot.summary + String(format: " above_baseline=%.0fMB", snapshot.totalMB - baseline.totalMB)
            + " loaded=\(loaded)/10 load_s=\(seconds) \(pages) windows=\(app.windows.all.count)")
    }
}
#endif
