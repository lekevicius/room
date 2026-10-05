#if DEBUG
import AppKit
import Chrome
import Engine
import Model
import Store
import Tabs
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
import RoomCore
#endif

/// Phase 3.7b spikes (`scripts/session-lifecycle.sh`, which serves
/// `research/spikes` on `http://127.0.0.1:8774`, `-RoomFixtureBase`):
///
/// - `session` in launches on one state and engine directory
///   (`-RoomSessionPhase`): `build` opens the ten typical sites as Today
///   tabs, navigates each twice (`phase-3.7/step.html?e=<i>&s=1`, then
///   `s=2`), records the size of each entry's navigation state after the
///   real page and after the two steps, and the cost of the store's write
///   (twenty flushes changing one entry's state, twenty changing a title),
///   then quits cleanly. `crash` does the same, then navigates the last
///   entry once more (`s=3`) and asks the script to `kill -9` it at once
///   (`kill_now:`), so the last navigation's write is inside the loss
///   window. `check` (the next launch) selects every entry with a state:
///   the restored page's URL and `canGoBack`, then Back; then ⌘W and ⇧⌘T on
///   a Today entry, ⌘W (reset and unload) on a changed pinned entry, and a
///   discarded page's revival, each with Back.
/// - `discardpolicy` (`--use-fake-device-for-media-stream`): a selected
///   page and background pages (plain ×3, a typed-into form, a playing tone,
///   video Picture-in-Picture, a capturing page); each page's
///   `discardBlockers`; the idle sweep with the policy's clock 61 min ahead
///   (the plain pages go, the others stay with the engine's reasons); the
///   renderer count before and after (B-56); then memory pressure: Chrome's
///   urgent discarding asked directly with the host's policy off (it must
///   discard no Room page), simulated critical pressure through Chromium's
///   own notification with the policy off (no page changes), then on (the
///   plain pages go oldest first, the blocked ones stay).
/// - `spelling`: a misspelled word typed into `form.html`'s text area: the
///   context menu's misspelled word and suggestions, the first suggestion
///   applied through the menu's command and read back from the DOM, Add to
///   Dictionary once (the word is unlearned again afterwards), Look Up.
extension SpikeRunner.Context {
    static var fixtureBase: String { UserDefaults.standard.string(forKey: "RoomFixtureBase") ?? "http://127.0.0.1:8774" }

    private var roomStore: RoomStore { sidebar.store }

    private func fixture(_ path: String) -> URL { URL(string: "\(Self.fixtureBase)/\(path)")! }

    private func stepURL(_ entry: String, _ step: Int) -> URL { fixture("phase-3.7/step.html?e=\(entry)&s=\(step)") }

    private static let keyCodes37b: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, " ": 49,
    ]

    /// Real key presses into whatever has the page's keyboard focus.
    private func typeKeys(_ text: String) async {
        for character in text {
            let lower = Character(character.lowercased())
            PageDriver.key(window, characters: String(character), charactersIgnoringModifiers: String(lower),
                           keyCode: Self.keyCodes37b[lower] ?? 0, modifiers: character.isUppercase ? [.shift] : [])
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private func milliseconds(_ block: () -> Void) -> Double {
        let start = ContinuousClock.now
        block()
        return ms(since: start)
    }

    /// Navigates `page` as a link and waits for the commit (and the load, unless `load` is false).
    @discardableResult
    private func navigate(_ page: any WebContents, to url: URL, load: Bool = true) async -> Bool {
        page.load(url, transition: .link, fromAddressBar: false)
        let committed = await waitUntil(20) { page.url?.absoluteString == url.absoluteString }
        if load { await waitLoaded(page) }
        return committed
    }

    // MARK: session

    func sessionChecks() async {
        let phase = UserDefaults.standard.string(forKey: "RoomSessionPhase") ?? "build"
        SpikeRunner.record("phase", phase)
        switch phase {
        case "build": await sessionBuild(crash: false)
        case "crash": await sessionBuild(crash: true)
        case "check": await sessionCheck()
        default: SpikeRunner.record("error", "unknown -RoomSessionPhase \(phase)")
        }
    }

    private func sessionBuild(crash: Bool) async {
        let space = sidebar.activeSpaceID
        var ids: [UUID] = []
        var firstSizes: [Double] = [], afterSizes: [Double] = []
        var stepOneState: Data?
        for (index, site) in Self.typicalSites.enumerated() {
            guard let entry = try? store.addEntry(.today, url: site, space: space) else { continue }
            sidebar.select(entry.id)
            guard let page = tabs.contents(for: entry.id) else {
                SpikeRunner.record("error", "session: no page for \(site)")
                continue
            }
            await waitLoaded(page, timeout: 30)
            try? await Task.sleep(for: .milliseconds(800))
            let first = page.navigationState?.count ?? 0
            let one = await navigate(page, to: stepURL("\(index)", 1))
            if index == 0 { stepOneState = page.navigationState }
            let two = await navigate(page, to: stepURL("\(index)", 2))
            try? await Task.sleep(for: .milliseconds(300))
            let after = page.navigationState?.count ?? 0
            firstSizes.append(Double(first))
            afterSizes.append(Double(after))
            ids.append(entry.id)
            SpikeRunner.record("entry_\(index)", "\(URL(string: site)?.host() ?? site) state after the site \(first) B, after two steps \(after) B "
                + "(steps committed \(one)/\(two)) canGoBack=\(page.canGoBack) url=\(page.url?.absoluteString ?? "nil")")
        }
        func sizes(_ values: [Double]) -> String {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return "n=0" }
            return String(format: "n=%d min=%.0f median=%.0f max=%.0f sum=%.0f B", sorted.count, sorted.first!, sorted[sorted.count / 2],
                          sorted.last!, sorted.reduce(0, +))
        }
        SpikeRunner.record("state_size_real_page", sizes(firstSizes))
        SpikeRunner.record("state_size_after_two_steps", sizes(afterSizes))
        // The states reach the store through the delegate (per turn) and the store's debounce.
        try? await Task.sleep(for: .seconds(1))
        let stored = ids.compactMap { store.entry($0)?.navigationState?.count }
        SpikeRunner.record("stored_states", "\(stored.count) of \(ids.count): \(stored.map(String.init).joined(separator: ","))")

        // The write: twenty flushes changing one entry's state (the debounced
        // transaction with its JSON snapshot), twenty changing a title.
        if let first = ids.first, let current = store.entry(first)?.navigationState, let older = stepOneState {
            var stateWrites: [Double] = [], titleWrites: [Double] = []
            for round in 0..<20 {
                try? store.setNavigationState(first, round.isMultiple(of: 2) ? older : current)
                stateWrites.append(milliseconds { roomStore.flush() })
            }
            try? store.setNavigationState(first, current)
            roomStore.flush()
            let live = store.entry(first)
            for round in 0..<20 {
                try? store.setLivePage(first, url: live?.liveURL, title: "\(live?.liveTitle ?? "") \(round)")
                titleWrites.append(milliseconds { roomStore.flush() })
            }
            try? store.setLivePage(first, url: live?.liveURL, title: live?.liveTitle)
            roomStore.flush()
            let directory = roomStore.storage.directory
            let database = (try? FileManager.default.attributesOfItem(atPath: directory.appending(path: "Room.sqlite").path)[.size] as? Int) ?? 0
            let snapshotFile = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.first { $0.hasSuffix(".json") }
            let snapshot = snapshotFile.flatMap { try? FileManager.default.attributesOfItem(atPath: directory.appending(path: $0).path)[.size] as? Int } ?? 0
            SpikeRunner.record("write_state_change", SpikeRunner.stats(stateWrites))
            SpikeRunner.record("write_title_change", SpikeRunner.stats(titleWrites))
            SpikeRunner.record("store_files", "Room.sqlite \(database) B, snapshot \(snapshotFile ?? "none") \(snapshot) B, entries \(store.entries.count)")
        }
        guard crash, let last = ids.last, let page = tabs.contents(for: last) else { return }
        // One more step on the selected entry, then the kill right after its commit.
        let committed = await navigate(page, to: stepURL("\(ids.count - 1)", 3), load: false)
        SpikeRunner.record("last_step", "committed=\(committed) at \(String(format: "%.3f", Date().timeIntervalSince1970)) url=\(page.url?.absoluteString ?? "nil")")
        SpikeRunner.record("kill_now", ProcessInfo.processInfo.processIdentifier)
        try? await Task.sleep(for: .seconds(60))
        SpikeRunner.record("error", "session: not killed")
    }

    private func sessionCheck() async {
        SpikeRunner.record("unclean_exit", roomStore.uncleanExit)
        SpikeRunner.record("previous_exit", AppDelegate.current?.previousExitSummary ?? "nil")
        let space = sidebar.activeSpaceID
        let entries = store.today(space: space).filter { $0.navigationState != nil }
        SpikeRunner.record("entries_with_state", "\(entries.count) of \(store.today(space: space).count)")
        var passed = 0
        for (index, entry) in entries.enumerated() {
            let start = ContinuousClock.now
            sidebar.select(entry.id)
            guard let page = tabs.contents(for: entry.id) else {
                SpikeRunner.record("restore_\(index)", "no page")
                continue
            }
            let restoredAtOnce = page.canGoBack
            await waitLoaded(page, timeout: 20)
            let loadedMs = ms(since: start)
            let url = page.url?.absoluteString ?? "nil"
            let canGoBack = page.canGoBack
            var back = "not tried"
            if canGoBack {
                page.goBack()
                _ = await waitUntil(15) { page.url?.absoluteString != url }
                await waitLoaded(page)
                back = page.url?.absoluteString ?? "nil"
            }
            let ok = canGoBack && back != url && back != "nil"
            if ok { passed += 1 }
            SpikeRunner.record("restore_\(index)", "url=\(url) canGoBack=\(canGoBack) (at creation \(restoredAtOnce)) back→\(back) "
                + String(format: "loaded in %.0f ms", loadedMs) + " title=\(page.title ?? "nil") ok=\(ok)")
        }
        SpikeRunner.record("restore_passed", "\(passed) of \(entries.count)")

        // ⌘W on a Today entry with history, then ⇧⌘T.
        if let entry = store.today(space: space).first(where: { $0.navigationState != nil }), tabs.contents(for: entry.id) != nil {
            sidebar.select(entry.id)
            try? await Task.sleep(for: .milliseconds(300))
            let url = tabs.contents(for: entry.id)?.url?.absoluteString ?? "nil"
            sidebar.close(entry.id)
            let removed = await waitUntil(5) { self.store.entry(entry.id) == nil }
            sidebar.reopenClosedTab()
            _ = await waitUntil(5) { self.store.entry(entry.id) != nil && self.tabs.contents(for: entry.id) != nil }
            if let page = tabs.contents(for: entry.id) {
                await waitLoaded(page)
                let canGoBack = page.canGoBack
                page.goBack()
                _ = await waitUntil(10) { page.url?.absoluteString != url }
                await waitLoaded(page)
                SpikeRunner.record("cmdW_reopen_today", "removed=\(removed) reopened url=\(url) canGoBack=\(canGoBack) back→\(page.url?.absoluteString ?? "nil")")
            } else {
                SpikeRunner.record("cmdW_reopen_today", "removed=\(removed) not reopened")
            }
        }

        // ⌘W on a changed pinned entry (reset-unload-switch): unloaded with
        // its history; the next page starts at the stored URL with the old page behind it.
        if let pinned = try? store.addEntry(.pinned, url: stepURL("pinned", 0).absoluteString, title: "Pinned step", space: space) {
            sidebar.select(pinned.id)
            if let page = tabs.contents(for: pinned.id) {
                await waitLoaded(page)
                await navigate(page, to: stepURL("pinned", 1))
                try? await Task.sleep(for: .milliseconds(300))
                sidebar.close(pinned.id, behavior: .resetUnloadSwitch)
                let unloaded = await waitUntil(5) { page.state == .closed }
                sidebar.select(pinned.id)
                if let again = tabs.contents(for: pinned.id) {
                    await waitLoaded(again)
                    let url = again.url?.absoluteString ?? "nil"
                    let canGoBack = again.canGoBack
                    again.goBack()
                    _ = await waitUntil(10) { again.url?.absoluteString != url }
                    await waitLoaded(again)
                    SpikeRunner.record("cmdW_pinned_unload", "unloaded=\(unloaded) reselected url=\(url) canGoBack=\(canGoBack) back→\(again.url?.absoluteString ?? "nil")")
                }
            }
        }

        // A discarded background page comes back with its history (3.3a).
        let background = store.today(space: space).filter {
            $0.id != sidebar.selectedEntryID && tabs.contents(for: $0.id)?.state == .alive && tabs.contents(for: $0.id)?.canGoBack == true
        }
        if let target = background.first, let page = tabs.contents(for: target.id) {
            let url = page.url?.absoluteString ?? "nil"
            do {
                try page.discard()
            } catch {
                SpikeRunner.record("discard_revival", "discard failed: \(error)")
            }
            try? await Task.sleep(for: .milliseconds(500))
            let state = page.state
            sidebar.select(target.id)
            await waitLoaded(page)
            let canGoBack = page.canGoBack
            page.goBack()
            _ = await waitUntil(10) { page.url?.absoluteString != url }
            await waitLoaded(page)
            SpikeRunner.record("discard_revival", "state after discard=\(state) revived url=\(url) canGoBack=\(canGoBack) back→\(page.url?.absoluteString ?? "nil")")
        }
    }

    // MARK: discardpolicy

    #if ROOM_ENGINE_ROOMCORE
    private func spikeBrowser() -> RoomBrowser? {
        tabs.engineProfiles.values.compactMap { ($0 as? RoomCoreProfile)?.spikeBrowsers.first }.first
    }

    private func spikeAction(_ action: String) -> Int {
        (spikeBrowser()?.perform(NSSelectorFromString("roomSpikeAction:"), with: action)?.takeUnretainedValue() as? NSNumber)?.intValue ?? -99
    }
    #endif

    func discardPolicyChecks() async {
        var pages: [(name: String, page: any WebContents)] = []
        func add(_ name: String, _ url: URL) async -> (any WebContents)? {
            guard let page = await open(url) else {
                SpikeRunner.record("error", "discardpolicy: \(name) did not open")
                return nil
            }
            try? await Task.sleep(for: .milliseconds(400))
            pages.append((name, page))
            return page
        }
        for name in ["plain1", "plain2", "plain3"] { _ = await add(name, stepURL(name, 0)) }
        if let form = await add("form", fixture("phase-3.7/form.html")) {
            await click(form, "#name")
            try? await Task.sleep(for: .milliseconds(150))
            await typeKeys("Room")
            try? await Task.sleep(for: .milliseconds(300))
            SpikeRunner.record("form_typed", await js(form, "document.querySelector('#name').value"))
        }
        if let tone = await add("tone", fixture("phase-3.7/tone.html")) {
            await click(tone, "#play")
            SpikeRunner.record("tone_audible", await waitUntil(5) { tone.isAudible })
        }
        if let pip = await add("pip", fixture("phase-3.7/pip.html")) {
            try? await Task.sleep(for: .milliseconds(500))
            await click(pip, "#video-pip")
            try? await Task.sleep(for: .seconds(2))
            SpikeRunner.record("pip_state", await js(pip, "document.querySelector('#log').textContent"))
        }
        if let capture = await add("capture", fixture("phase-2.6/capture.html")) {
            await click(capture, "#start")
            let prompted = await waitUntil(8) { self.prompts.visiblePermission != nil }
            if prompted { prompts.respondToPermission(.granted) }
            let capturing = await waitUntil(10) { !capture.captureState.isEmpty }
            SpikeRunner.record("capture_state", "prompted=\(prompted) capturing=\(capturing) page=\(await js(capture, "document.querySelector('#log').textContent"))")
        }
        guard let selected = await add("selected", stepURL("selected", 0)) else { return }
        try? await Task.sleep(for: .seconds(2))
        let names = Dictionary(uniqueKeysWithValues: pages.compactMap { item in tabs.entryID(for: item.page).map { ($0, item.name) } })
        func label(_ ids: [UUID]) -> String { ids.map { names[$0] ?? "?" }.joined(separator: ",") }
        for (name, page) in pages where page !== selected {
            SpikeRunner.record("blockers_\(name)", page.discardBlockers.names.joined(separator: ",").nilIfEmpty ?? "none")
        }
        #if ROOM_ENGINE_ROOMCORE
        SpikeRunner.record("auto_discardable_pages", spikeAction("auto-discardable-count"))
        #endif

        // The idle sweep, the policy's clock 61 minutes ahead (2.3's limits:
        // Today 60 min).
        let before = ProcessMemory.snapshot()
        let clock = tabs.now
        tabs.now = { Date().addingTimeInterval(61 * 60) }
        let idle = tabs.discardIdlePages()
        tabs.now = clock
        SpikeRunner.record("idle_discarded", label(idle))
        SpikeRunner.record("idle_kept", tabs.keptByEngine.map { "\(names[$0.key] ?? "?")=\($0.value.names.joined(separator: "+"))" }.sorted().joined(separator: " "))
        SpikeRunner.record("states_after_idle", pages.map { "\($0.name)=\($0.page.state)" }.joined(separator: " "))
        try? await Task.sleep(for: .seconds(4))
        let at4 = ProcessMemory.snapshot()
        try? await Task.sleep(for: .seconds(6))
        let at10 = ProcessMemory.snapshot()
        SpikeRunner.record("b56_renderers", "before \(before.renderers) (\(Int(before.totalMB)) MB), 4 s after \(at4.renderers) (\(Int(at4.totalMB)) MB), "
            + "10 s after \(at10.renderers) (\(Int(at10.totalMB)) MB), discarded \(idle.count)")

        // Back for the pressure part: the plain pages alive again, oldest first.
        for name in ["plain1", "plain2", "plain3"] {
            guard let page = pages.first(where: { $0.name == name })?.page, let id = tabs.entryID(for: page) else { continue }
            sidebar.select(id)
            await waitLoaded(page)
            try? await Task.sleep(for: .milliseconds(300))
        }
        if let id = tabs.entryID(for: selected) { sidebar.select(id) }
        try? await Task.sleep(for: .seconds(1))
        func states() -> String { pages.map { "\($0.name)=\($0.page.state)" }.joined(separator: " ") }
        SpikeRunner.record("states_before_pressure", states())

        var discards: [(String, String, Double)] = []
        let pressureStart = ContinuousClock.now
        tabs.debugDidDiscard = { [weak self] id, reason in
            guard let self else { return }
            discards.append((names[id] ?? "?", reason, self.ms(since: pressureStart)))
        }
        #if ROOM_ENGINE_ROOMCORE
        // Chrome's own urgent discarding, asked directly: no Room page may go.
        tabs.respondsToMemoryPressure = false
        let urgent = spikeAction("pm-urgent-discard")
        try? await Task.sleep(for: .seconds(1))
        SpikeRunner.record("pm_urgent_discard", "discarded=\(urgent) states=\(states())")
        // Simulated critical pressure through Chromium's notification, the host's policy off.
        let simulated = spikeAction("memory-pressure-critical")
        try? await Task.sleep(for: .seconds(6))
        SpikeRunner.record("pressure_policy_off", "simulated=\(simulated) host heard=\(tabs.memoryPressure) states=\(states()) discards=\(discards.count)")
        _ = spikeAction("memory-pressure-none")
        try? await Task.sleep(for: .milliseconds(500))
        // The same with the policy on.
        tabs.respondsToMemoryPressure = true
        _ = spikeAction("memory-pressure-critical")
        try? await Task.sleep(for: .seconds(6))
        _ = spikeAction("memory-pressure-none")
        #else
        tabs.handleMemoryPressure(.critical)
        try? await Task.sleep(for: .seconds(6))
        tabs.handleMemoryPressure(.none)
        #endif
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("pressure_discards", discards.map { "\($0.0)@\(Int($0.2))ms(\($0.1))" }.joined(separator: " "))
        SpikeRunner.record("states_after_pressure", states())
        SpikeRunner.record("pressure_level_after", tabs.memoryPressure)
        tabs.debugDidDiscard = nil
        if let tone = pages.first(where: { $0.name == "tone" })?.page { await click(tone, "#stop") }
    }

    // MARK: spelling

    func spellingChecks() async {
        guard let page = await open(fixture("phase-3.7/form.html")) else { return }
        await click(page, "#notes")
        try? await Task.sleep(for: .milliseconds(200))
        let word = "misspeled"
        await typeKeys("This is \(word) ")
        try? await Task.sleep(for: .seconds(1.5))
        SpikeRunner.record("typed", await js(page, "document.querySelector('#notes').value"))
        let chrome = session.pageDelegate.chrome
        let presentMenu = chrome.presentMenu
        defer { chrome.presentMenu = presentMenu }
        let elementScript = "(() => { const t = document.querySelector('#notes'); const r = t.getBoundingClientRect(); "
            + "return [r.x + 8 + 8.6 * \(8 + word.count / 2), r.y + 14] })()"
        func wordPoint() async -> CGPoint? {
            guard let json = await PageDriver.evaluate(page, elementScript, "spelling"),
                  let point = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], point.count == 2 else { return nil }
            return CGPoint(x: point[0], y: point[1])
        }
        // The menu on the word: what the engine says about it, then its first suggestion (IDC_SPELLCHECK_SUGGESTION_0).
        let suggest = MenuDriver()
        var offered: [String] = []
        chrome.presentMenu = { menu, point, view in suggest.show(menu, at: point, in: view) }
        suggest.chooseTag = 41_000
        suggest.onOpen = { menu in
            offered = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            suggest.offered = menu.menu.item(withTag: 41_000) != nil
            suggest.finish()
        }
        guard let point = await wordPoint() else { return }
        Task { PageDriver.click(page, at: point, button: .rightMouseDown, "right-click the word") }
        _ = await waitUntil(8) { suggest.closed }
        SpikeRunner.record("menu_on_word", offered.joined(separator: " | "))
        if let recorder = DelegateRecorder.active { SpikeRunner.record("menu_element", recorder.lastDetail("willShowContextMenu") ?? "nil") }
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("after_suggestion", "offered=\(suggest.offered) value=\(await js(page, "document.querySelector('#notes').value"))")

        // Add to Dictionary on a made-up word (unlearned again at the end).
        let madeUp = "roomzorbify"
        _ = await js(page, "(() => { const t = document.querySelector('#notes'); t.value = 'Say \(madeUp) now'; return 0 })()")
        await click(page, "#notes")
        try? await Task.sleep(for: .seconds(1.5))
        let learn = MenuDriver()
        var learnItems: [String] = []
        chrome.presentMenu = { menu, point, view in learn.show(menu, at: point, in: view) }
        learn.chooseTag = 41_110
        learn.onOpen = { menu in
            learnItems = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            learn.offered = menu.menu.item(withTag: 41_110) != nil
            learn.finish()
        }
        let madeUpScript = "(() => { const t = document.querySelector('#notes'); const r = t.getBoundingClientRect(); return [r.x + 8 + 8.6 * 8, r.y + 14] })()"
        if let json = await PageDriver.evaluate(page, madeUpScript, "learn"),
           let p = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], p.count == 2 {
            Task { PageDriver.click(page, at: CGPoint(x: p[0], y: p[1]), button: .rightMouseDown, "right-click the made-up word") }
            _ = await waitUntil(8) { learn.closed }
        }
        try? await Task.sleep(for: .milliseconds(600))
        let learned = NSSpellChecker.shared.hasLearnedWord(madeUp)
        SpikeRunner.record("add_to_dictionary", "menu=\(learnItems.joined(separator: " | ")) offered=\(learn.offered) learned by macOS=\(learned)")
        if learned { NSSpellChecker.shared.unlearnWord(madeUp) }
        SpikeRunner.record("unlearned", !NSSpellChecker.shared.hasLearnedWord(madeUp))

        // Look Up on a correct word (IDC_CONTENT_CONTEXT_LOOK_UP): offered and run.
        _ = await js(page, "(() => { const t = document.querySelector('#notes'); t.value = 'library'; t.select(); return 0 })()")
        let look = MenuDriver()
        var lookItems: [String] = []
        chrome.presentMenu = { menu, point, view in look.show(menu, at: point, in: view) }
        look.chooseTag = 50_165
        look.onOpen = { menu in
            lookItems = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            look.offered = menu.menu.item(withTag: 50_165) != nil
            look.finish()
        }
        let lookScript = "(() => { const t = document.querySelector('#notes'); const r = t.getBoundingClientRect(); return [r.x + 30, r.y + 14] })()"
        if let json = await PageDriver.evaluate(page, lookScript, "look up"),
           let p = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], p.count == 2 {
            Task { PageDriver.click(page, at: CGPoint(x: p[0], y: p[1]), button: .rightMouseDown, "right-click a selected word") }
            _ = await waitUntil(8) { look.closed }
        }
        try? await Task.sleep(for: .seconds(1))
        SpikeRunner.record("look_up", "menu=\(lookItems.joined(separator: " | ")) offered=\(look.offered) windows=\(NSApp.windows.filter(\.isVisible).count)")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
