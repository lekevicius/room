#if DEBUG
import AppKit
import Design
import Engine
import Model
import Sidebar
import Store
import Tabs

/// Phase 2.5 spikes on the live engine (`Room -RoomSpike <name>`):
/// - `spaces` (with `-RoomSidebarFixture spaces500`): builds every space's
///   list, times a list's full reload, loads ten pages in each of the five
///   spaces, then times 60 switches by ⌃digit key events: key to the
///   switch, the switch's own code, key to the first display frame after it
///   (the slide's first frame), and how many lists loaded meanwhile (0).
/// - `spacecaptures` (with `-RoomSidebarFixture spaces`, run by
///   `scripts/spaces-capture.sh`): asks the script for window-server
///   captures (`capture: <name>`, waits for `<output>.ack-<name>`) of the
///   footer, a themed space light and dark, the form, and a slowed slide.
/// - `cookies` (with `-RoomSidebarFixture spaces`, a throwaway
///   `-RoomEngineDirectory` and the cookie page served on 127.0.0.1:8765,
///   `scripts/spaces-cookies.sh`): one cookie per profile, checked from a
///   space of each profile and after a cross-profile move.
extension SpikeRunner.Context {
    func ms(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
        let d = end - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// The ⌃digit key codes (US layout), digit → key code.
    static let digitKeyCodes: [Int: UInt16] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 0: 29]

    // MARK: Switch timing (ROADMAP 2.5 exit)

    func spacesMeasure() async {
        let spaces = store.spaces
        SpikeRunner.record("spaces", spaces.count)
        SpikeRunner.record("entries", store.entries.values.filter { $0.kind != .folder }.count)
        let prepareStart = ContinuousClock.now
        let prepared = await waitUntil(15) { self.sidebar.debugPreparedSpaces == spaces.count }
        SpikeRunner.record("lists_prepared_after_launch", "\(prepared) in \(String(format: "%.0f", ms(prepareStart, .now))) ms of waiting")
        SpikeRunner.record("list_build_load_warm_up_per_space", SpikeRunner.stats(sidebar.debugPrepareTimes.map {
            Double($0.components.seconds) * 1000 + Double($0.components.attoseconds) / 1e15
        }))

        // The first switch to each space after launch: its list's rows are made on first display.
        var cold: [Double] = [], coldSync: [Double] = []
        var coldPhases: [String: [Double]] = [:]
        sidebar.debugSwitchPhase = { name, duration in
            coldPhases[name, default: []].append(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
        }
        for space in spaces.dropFirst() {
            let timing = await timedTurn { sidebar.showSpace(space.id) }
            cold.append(timing.turn)
            coldSync.append(timing.sync)
            try? await Task.sleep(for: .milliseconds(400))
        }
        sidebar.debugSwitchPhase = nil
        SpikeRunner.record("first_switch_to_each_space_turn", SpikeRunner.stats(cold))
        SpikeRunner.record("first_switch_to_each_space_code", SpikeRunner.stats(coldSync))
        for name in ["list", "slide", "footer", "essentials", "tint_title", "card"] {
            SpikeRunner.record("first_switch_phase_\(name)", SpikeRunner.stats(coldPhases[name] ?? []))
        }
        sidebar.showSpace(spaces[0].id, animated: false)

        // What a switch would pay without a prepared list: one space's full reload.
        var reload: [Double] = []
        for _ in 0..<5 {
            for space in spaces where space.id != sidebar.activeSpaceID {
                let start = ContinuousClock.now
                sidebar.debugReloadPane(space.id)
                reload.append(ms(start, .now))
            }
        }
        SpikeRunner.record("outline_full_reload_one_space", SpikeRunner.stats(reload) + " (\(store.sidebarOrder(space: spaces[1].id).count + 3) rows)")

        // Ten loaded pages per space.
        let loadStart = Date()
        for space in spaces {
            sidebar.showSpace(space.id, animated: false)
            let pages = store.today(space: space.id).prefix(10)
            for entry in pages {
                sidebar.select(entry.id)
                if let page = tabs.contents(for: entry.id) { await waitLoaded(page, timeout: 30) }
            }
            if let first = pages.first { sidebar.select(first.id) }
        }
        sidebar.showSpace(spaces[0].id, animated: false)
        SpikeRunner.record("load_s", Int(Date().timeIntervalSince(loadStart)))
        try? await Task.sleep(for: .seconds(3))
        SpikeRunner.record("loaded_pages", tabs.loadedEntryIDs.count)
        SpikeRunner.record("rss_50_loaded", ProcessMemory.snapshot().summary)

        guard let view = window.contentView else { return }
        let ticks = FrameTicks(view: view)
        var started: ContinuousClock.Instant?, ended: ContinuousClock.Instant?
        sidebar.debugSwitchTiming = { begin in
            if begin { started = .now } else { ended = .now }
        }
        var keyToSwitch: [Double] = [], switchCode: [Double] = [], keyToFrame: [Double] = []
        var phases: [String: [Double]] = [:]
        sidebar.debugSwitchPhase = { name, duration in
            phases[name, default: []].append(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
        }
        var missed = 0
        let loadsBefore = sidebar.debugPaneLoads
        for _ in 0..<60 {
            let current = spaces.firstIndex { $0.id == sidebar.activeSpaceID } ?? 0
            var target = Int.random(in: 0..<spaces.count)
            while target == current { target = Int.random(in: 0..<spaces.count) }
            let digit = target + 1
            started = nil
            ended = nil
            let keyTime = ContinuousClock.now
            sendKey("\(digit)", keyCode: Self.digitKeyCodes[digit]!, [.control])
            _ = await waitUntil(2) { ended != nil }
            guard let begin = started, let end = ended else {
                missed += 1
                continue
            }
            keyToSwitch.append(ms(keyTime, begin))
            switchCode.append(ms(begin, end))
            if let tick = await ticks.firstTick(after: end, timeout: 1) { keyToFrame.append(ms(keyTime, tick)) }
            try? await Task.sleep(for: .milliseconds(450))
        }
        sidebar.debugSwitchTiming = nil
        sidebar.debugSwitchPhase = nil
        for name in ["list", "slide", "footer", "essentials", "tint_title", "card"] {
            SpikeRunner.record("switch_phase_\(name)", SpikeRunner.stats(phases[name] ?? []))
        }
        SpikeRunner.record("display_frame_interval", ticks.intervalDescription)
        ticks.stop()
        SpikeRunner.record("switches_missed", missed)
        SpikeRunner.record("ctrl_digit_key_to_switch", SpikeRunner.stats(keyToSwitch))
        SpikeRunner.record("switch_main_thread_code", SpikeRunner.stats(switchCode))
        SpikeRunner.record("ctrl_digit_key_to_first_slide_frame", SpikeRunner.stats(keyToFrame))
        SpikeRunner.record("lists_loaded_during_switches", sidebar.debugPaneLoads - loadsBefore)
        SpikeRunner.record("rss_after_switching", ProcessMemory.snapshot().summary)
    }

    // MARK: Captures (window server, by the script)

    /// Asks `scripts/spaces-capture.sh` for a capture of the window and waits for it.
    func requestCapture(_ name: String) async {
        try? await Task.sleep(for: .milliseconds(600))
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + name)
        SpikeRunner.record("capture", name)
        let done = await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }
        if !done { SpikeRunner.record("capture_timeout", name) }
    }

    func spaceCaptures() async {
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        // The active look even when macOS refuses to activate a script-launched app.
        controller.activityOverride = true
        NSApp.appearance = NSAppearance(named: .aqua)
        _ = await waitUntil(15) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        let spaces = store.spaces
        guard spaces.count >= 4 else { return SpikeRunner.record("error", "needs the spaces fixture") }
        let (home, work, reading) = (spaces[0], spaces[1], spaces[2])
        // Every space's selected page, loaded.
        for space in spaces {
            sidebar.showSpace(space.id, animated: false)
            if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        }
        sidebar.showSpace(home.id, animated: false)
        try? await Task.sleep(for: .seconds(2))

        sidebar.debugHoverSpaceIcon(reading.id)
        await requestCapture("phase-2.5-footer-spaces-light")
        sidebar.debugHoverSpaceIcon(nil)

        sidebar.showSpace(work.id, animated: false)
        await requestCapture("phase-2.5-themed-space-light")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await requestCapture("phase-2.5-themed-space-dark")
        sidebar.showSpace(reading.id, animated: false)
        await requestCapture("phase-2.5-themed-space-reading-dark")
        NSApp.appearance = NSAppearance(named: .aqua)

        sidebar.debugShowSpaceForm(edit: reading.id)
        try? await Task.sleep(for: .milliseconds(500))
        await requestCapture("phase-2.5-space-form-edit-light")
        sidebar.debugDismissSpaceForm()
        sidebar.debugShowSpaceForm(edit: nil)
        try? await Task.sleep(for: .milliseconds(500))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        await requestCapture("phase-2.5-space-form-new-dark")
        sidebar.debugDismissSpaceForm()
        NSApp.appearance = NSAppearance(named: .aqua)

        // A slide slowed 24× (6 s): captured near its middle, both lists and the new page in the card.
        sidebar.showSpace(home.id, animated: false)
        try? await Task.sleep(for: .seconds(1))
        sidebar.debugSetSlideSlowdown(24)
        sidebar.showSpace(work.id)
        try? await Task.sleep(for: .milliseconds(1_800))
        SpikeRunner.record("capture", "phase-2.5-mid-slide-light")
        try? await Task.sleep(for: .seconds(6))
        sidebar.debugSetSlideSlowdown(1)
    }

    // MARK: Cookies per profile (ROADMAP 2.5 exit)

    func cookiesCheck() async {
        sidebar.confirmations = { _ in true }
        let spaces = store.spaces
        guard spaces.count >= 3 else { return SpikeRunner.record("error", "needs the spaces fixture") }
        let (home, work, reading) = (spaces[0], spaces[1], spaces[2])
        SpikeRunner.record("profiles", store.profiles.map { "\($0.name)=\($0.id.uuidString.prefix(8))" }.joined(separator: " "))
        SpikeRunner.record("spaces", spaces.map { space in
            "\(space.name):\(store.profiles.first { $0.id == space.profileID }?.name ?? "?")"
        }.joined(separator: " "))
        let base = "http://127.0.0.1:8765/cookies.html"
        func open(_ space: Space, _ query: String) async -> (id: UUID?, cookie: String) {
            sidebar.showSpace(space.id, animated: false)
            guard let page = session.newPage(URL(string: base + query)) else { return (nil, "no page") }
            await waitLoaded(page, timeout: 20)
            let cookie = await js(page, "document.cookie")
            return (tabs.currentEntryID, cookie)
        }
        let homeSet = await open(home, "?set=home")
        SpikeRunner.record("default_profile_after_set", homeSet.cookie)
        let workSet = await open(work, "?set=work")
        SpikeRunner.record("work_profile_after_set", workSet.cookie)
        SpikeRunner.record("work_profile_reread", await open(work, "").cookie)
        SpikeRunner.record("reading_space_same_profile_as_default", await open(reading, "").cookie)
        // The Default space's tab, on a page that sets nothing, moved to Work: it loads again in Work's jar.
        if let id = homeSet.id, let page = tabs.contents(for: id) {
            sidebar.showSpace(home.id, animated: false)
            sidebar.select(id)
            page.load(URL(string: base)!, transition: .typed, fromAddressBar: true)
            await waitLoaded(page, timeout: 20)
            SpikeRunner.record("before_move", await js(page, "document.cookie"))
            sidebar.moveSelected(toSpace: work.id)
            try? await Task.sleep(for: .milliseconds(300))
            if let moved = tabs.contents(for: id) {
                await waitLoaded(moved, timeout: 20)
                SpikeRunner.record("after_move_to_work", "same_page=\(moved === page) cookie=\(await js(moved, "document.cookie"))")
            }
            SpikeRunner.record("moved_entry_profile_is_work", store.entry(id)?.profileID == work.profileID)
        }
        let root = UserDefaults.standard.string(forKey: "RoomEngineDirectory") ?? ""
        let dirs = (try? FileManager.default.contentsOfDirectory(atPath: root))?.filter { $0.hasPrefix("Room Profile") }.sorted() ?? []
        SpikeRunner.record("engine_profile_directories", dirs.joined(separator: ", "))
        let history = tabs.store.history
        SpikeRunner.record("history_rows", "Default=\((try? history.count(profile: home.profileID)) ?? -1) "
            + "Work=\((try? history.count(profile: work.profileID)) ?? -1)")
    }
}
#endif
