#if DEBUG
import AppKit
import Design
import Engine
import Model
import Omnibox
import Palette
import Sidebar
import Store
import Tabs
#if canImport(EngineCEF)
import EngineCEF
#endif

/// Phase 2.4a spikes on the live engine (`Room -RoomSpike <name>`):
/// - `palette` (with `-RoomSidebarFixture demo`, optionally
///   `-RoomSpikeCaptureDirectory <dir>`): ⌘T / ⌘L / Enter / ⌘Enter /
///   ⌥Enter / Esc / ⇥ through real key events into the field editor, a URL
///   opened and edited through the palette alone, then captures of the
///   palette (empty, with results, ⌘L, docked on the header field) in light
///   and dark, rendered in-process like 2.3's (B-9, B-18).
/// - `palettemeasure` (with `-RoomSidebarFixture 500`): open-to-first-frame
///   and keystroke-to-rows with the three 2.4a providers.
extension SpikeRunner.Context {
    var palette: PaletteController? { (NSApp.delegate as? AppDelegate)?.palette }

    /// The spike session counts ⌘T/⌘L for the keyboard spike; here they open the palette.
    func restorePaletteHooks() {
        guard let palette else { return }
        tabs.onNewTab = { [weak palette] in palette?.toggleNew() }
        tabs.onEditAddress = { [weak palette] docked in palette?.toggleEdit(docked: docked) }
    }

    func type(_ text: String) {
        for character in text {
            let string = String(character)
            sendKey(string, keyCode: Self.keyCodes[character.lowercased().first ?? " "] ?? 0, character.isUppercase ? [.shift] : [])
        }
    }

    /// US key positions, so AppKit's key-equivalent matching sees a plausible event.
    private static let keyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, ".": 47, "/": 44, " ": 49, "-": 27, ":": 41,
    ]

    func press(_ name: String) {
        switch name {
        case "⌘T": sendKey("t", keyCode: 17, [.command])
        case "⌘L": sendKey("l", keyCode: 37, [.command])
        case "↩": sendKey("\r", keyCode: 36, [])
        case "⌘↩": sendKey("\r", keyCode: 36, [.command])
        case "⌥↩": sendKey("\r", keyCode: 36, [.option])
        case "⎋": sendKey("\u{1b}", keyCode: 53, [])
        case "⇥": sendKey("\t", keyCode: 48, [])
        case "⌫": sendKey("\u{7f}", keyCode: 51, [])
        case "⇧⌫": sendKey("\u{7f}", keyCode: 51, [.shift])
        case "↓": sendKey(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: 125, [.numericPad, .function])
        default: break
        }
    }

    private var fieldIsFirstResponder: Bool {
        (window.firstResponder as? NSTextView)?.delegate is NSTextField && palette?.isOpen == true
    }

    private var responderName: String { window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil" }

    // MARK: Behaviour on CEF

    func paletteChecks() async {
        restorePaletteHooks()
        guard let palette else { return SpikeRunner.record("error", "no palette") }
        if let id = store.today(space: sidebar.activeSpaceID).first(where: { $0.currentURL?.contains("wikipedia") == true })?.id {
            sidebar.select(id)
        }
        if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        let todayBefore = store.today(space: sidebar.activeSpaceID).count

        press("⌘T")
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("cmd_t_opens", "open=\(palette.isOpen) mode=\(String(describing: palette.mode)) field_first_responder=\(fieldIsFirstResponder)")
        SpikeRunner.record("cmd_t_no_tab_yet", store.today(space: sidebar.activeSpaceID).count == todayBefore)
        type("example.com")
        SpikeRunner.record("typed", "\(palette.typedText) top=\(String(describing: palette.result.matches.first?.action))")
        press("↩")
        try? await Task.sleep(for: .milliseconds(200))
        let opened = store.today(space: sidebar.activeSpaceID).last
        if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        SpikeRunner.record("enter_new_tab", "closed=\(!palette.isOpen) today=\(store.today(space: sidebar.activeSpaceID).count - todayBefore) "
            + "selected=\(sidebar.selectedEntryID == opened?.id) page=\(tabs.current?.url?.absoluteString ?? "nil") responder=\(responderName)")

        press("⌘L")
        try? await Task.sleep(for: .milliseconds(200))
        let editor = window.firstResponder as? NSTextView
        SpikeRunner.record("cmd_l_prefill", "mode=\(String(describing: palette.mode)) text=\(palette.typedText) "
            + "selected=\(editor.map { NSStringFromRange($0.selectedRange) } ?? "none") of \((palette.typedText as NSString).length)")
        type("en.wikipedia.org/wiki/Command_palette")
        press("↩")
        try? await Task.sleep(for: .milliseconds(300))
        if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        SpikeRunner.record("cmd_l_enter_navigates_current", "page=\(tabs.current?.url?.absoluteString ?? "nil") "
            + "same_entry=\(sidebar.selectedEntryID == opened?.id) today=\(store.today(space: sidebar.activeSpaceID).count - todayBefore)")

        press("⌘L")
        try? await Task.sleep(for: .milliseconds(200))
        press("↩")
        let reloading = await waitUntil(5) { self.tabs.current?.isLoading == true }
        if let page = tabs.current { await waitLoaded(page, timeout: 30) }
        SpikeRunner.record("cmd_l_unchanged_enter_reloads", "loading_seen=\(reloading) page=\(tabs.current?.url?.absoluteString ?? "nil")")

        press("⌘L")
        try? await Task.sleep(for: .milliseconds(200))
        type("typo")
        press("⎋")
        let restored = palette.typedText
        press("⎋")
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("escape", "first_restores=\(restored == tabs.current?.url?.absoluteString) second_closes=\(!palette.isOpen) "
            + "responder=\(responderName)")

        press("⌘T")
        press("⌘T")
        SpikeRunner.record("cmd_t_again_closes", !palette.isOpen)
        press("⌘L")
        press("⌘T")
        SpikeRunner.record("cmd_t_closes_cmd_l", !palette.isOpen)

        let selectedBefore = sidebar.selectedEntryID
        let countBefore = store.today(space: sidebar.activeSpaceID).count
        press("⌘T")
        type("swift.org")
        press("⌥↩")
        try? await Task.sleep(for: .milliseconds(300))
        let background = store.today(space: sidebar.activeSpaceID).last
        SpikeRunner.record("option_enter_background", "added=\(store.today(space: sidebar.activeSpaceID).count - countBefore) "
            + "selection_kept=\(sidebar.selectedEntryID == selectedBefore) page=\(background.flatMap { tabs.contents(for: $0.id) }?.url?.absoluteString ?? "nil")")

        press("⌘T")
        type("ar")
        let groups = palette.result.matches.map { "\($0.group)" }.joined(separator: ",")
        press("⇥")
        let afterTab = palette.highlightedIndex ?? -1
        press("⌘↩")
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("tab_cycles_groups", "groups=\(groups) highlighted_after_tab=\(afterTab) cmd_enter_closed=\(!palette.isOpen) "
            + "today=\(store.today(space: sidebar.activeSpaceID).count - countBefore)")

        tabs.editAddress()
        try? await Task.sleep(for: .milliseconds(200))
        let field = sidebar.addressField.convert(sidebar.addressField.bounds, to: controller.rootView)
        SpikeRunner.record("header_click_docked", "presentation=\(palette.presentation) panel=\(palette.debugPanel.map { NSStringFromRect($0.frame) } ?? "none") "
            + "field=\(NSStringFromRect(field))")
        press("⎋")

        await paletteCaptures()
    }

    // MARK: Captures

    private func paletteCaptures() async {
        guard let palette, let directoryPath = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        if let id = store.today(space: sidebar.activeSpaceID).first(where: { $0.currentURL?.contains("wikipedia") == true })?.id {
            sidebar.select(id)
        }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let suffix = dark ? "dark" : "light"
            var pageImage: NSImage?
            if let page = tabs.current {
                await waitLoaded(page, timeout: 30)
                try? await Task.sleep(for: .seconds(2))
                #if canImport(EngineCEF)
                pageImage = try? await (page as? CEFWebContents)?.captureViewport()
                #endif
            }
            let states: [(String, () -> Void)] = [
                ("empty", { self.press("⌘T") }),
                ("results", { self.press("⌘T"); self.type("ar") }),
                ("edit", { self.press("⌘L") }),
                ("docked", { self.tabs.editAddress() }),
            ]
            for (name, show) in states {
                show()
                try? await Task.sleep(for: .milliseconds(400))
                palette.debugPanel?.displayIfNeeded()
                SpikeRunner.record("capture_\(name)_\(suffix)", writeComposite(page: pageImage, pageView: tabs.current?.nativeView,
                                                                              overlay: palette.debugPanel,
                                                                              to: directory.appending(path: "phase-2.4a-palette-\(name)-\(suffix).png")))
                palette.dismiss()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    // MARK: Measurements (ROADMAP 2.4: open-to-first-frame; keystroke-to-rows on the 500 fixture)

    func paletteMeasure() async {
        restorePaletteHooks()
        guard let palette else { return SpikeRunner.record("error", "no palette") }
        let entries = store.entries.values.filter { $0.kind != .folder }.count
        SpikeRunner.record("entries", entries)
        SpikeRunner.record("history_rows", (try? tabs.store.history.count()) ?? -1)
        // The no-network check types with suggestions off (`-RoomSuggestionsOff YES`).
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { tabs.store.settings.update { $0.searchSuggestions = false } }
        SpikeRunner.record("suggestions", tabs.store.settings.settings.searchSuggestions ? "on" : "off")
        if let page = tabs.current { await waitLoaded(page, timeout: 20) }
        try? await Task.sleep(for: .seconds(1))

        var openSync: [Double] = [], openTurn: [Double] = [], firstFrame: [Double] = []
        // One display link, running before the opens: a link created after
        // the open added its own start-up latency to "next frame" (2.4b).
        let ticks = FrameTicks(view: controller.rootView)
        try? await Task.sleep(for: .milliseconds(200))
        for _ in 0..<40 {
            let start = ContinuousClock.now
            let timing = await timedTurn { palette.toggleNew() }
            openSync.append(timing.sync)
            openTurn.append(timing.turn)
            // The first frame that starts after the turn committed the panel.
            let committed = start + .microseconds(Int(timing.turn * 1000))
            if let frame = await ticks.firstTick(after: committed, timeout: 0.25) {
                firstFrame.append(Double((frame - start).components.attoseconds) / 1e15 + Double((frame - start).components.seconds) * 1000)
            }
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(150))
        }
        SpikeRunner.record("display_frame_interval", ticks.intervalDescription)
        ticks.stop()
        SpikeRunner.record("palette_open_call", SpikeRunner.stats(openSync))
        SpikeRunner.record("palette_open_turn", SpikeRunner.stats(openTurn))
        SpikeRunner.record("palette_open_to_next_frame", firstFrame.isEmpty ? "no display-link frame (window occluded)" : SpikeRunner.stats(firstFrame))

        var queries: [Double] = [], firstQueries: [Double] = [], nextIsFirst = false
        var phases: [String: [Double]] = [:]
        func ms(_ duration: Duration) -> Double { Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000 }
        palette.onQueryTimed = { duration in
            let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
            queries.append(ms)
            if nextIsFirst { firstQueries.append(ms) }
        }
        palette.onQueryPhases = { snapshot, providers, rows in
            let key = nextIsFirst ? "first" : "later"
            phases["\(key)_snapshot", default: []].append(ms(snapshot))
            phases["\(key)_providers", default: []].append(ms(providers))
            phases["\(key)_rank_and_rows", default: []].append(ms(rows))
            nextIsFirst = false
        }
        var keyTurn: [Double] = [], firstKey: [Double] = [], laterKeys: [Double] = [], rows: [Int] = []
        var firstKeyBeforeDisplay: [Double] = [], laterKeysBeforeDisplay: [Double] = [], firstKeyLog: [String] = []
        var historyRows: [Int] = [], inline = 0
        // Sidebar entries (2.4a) and history: hosts, words, a path, common
        // trigrams ("com", "the"), a miss.
        let texts = ["today tab 3", "pinned 4", "github", "swift docs", "news", "rust kernel", "developer.apple.com/sw", "wiki",
                     "com", "the", "zzz", "google search", "app", "example.org/article"]
        SpikeRunner.record("queries", texts.joined(separator: " | "))
        // The no-network check compares the proxy and net-log against this window.
        SpikeRunner.record("typing_start_epoch_ms", Int(Date().timeIntervalSince1970 * 1000))
        // `-RoomPaletteTypingDelay <ms>`: the pause between ⌘T and the first key (2.4b: 100 ms, inside the 120 ms open animation).
        let typingDelay = max(0, UserDefaults.standard.integer(forKey: "RoomPaletteTypingDelay"))
        // `-RoomPaletteSpinBeforeFirstKey YES`: diagnostic, the first key runs on a performance core.
        let spinBeforeFirstKey = UserDefaults.standard.bool(forKey: "RoomPaletteSpinBeforeFirstKey")
        SpikeRunner.record("spin_before_first_key", spinBeforeFirstKey)
        SpikeRunner.record("typing_delay_ms", typingDelay == 0 ? 100 : typingDelay)
        for text in texts {
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(typingDelay == 0 ? 100 : typingDelay))
            for (index, character) in text.enumerated() {
                nextIsFirst = index == 0
                if index == 0, spinBeforeFirstKey {
                    // Diagnostic: 25 ms of busy main thread first, so the scheduler has moved it to a performance core.
                    let until = ContinuousClock.now + .milliseconds(25)
                    while ContinuousClock.now < until {}
                }
                let timing = await timedTurn { self.type(String(character)) }
                keyTurn.append(timing.turn)
                if index == 0 { firstKey.append(timing.turn) } else { laterKeys.append(timing.turn) }
                if index == 0 { firstKeyBeforeDisplay.append(timing.beforeDisplay) } else { laterKeysBeforeDisplay.append(timing.beforeDisplay) }
                if index == 0 { firstKeyLog.append(String(format: "%@ %.1f/%.1f/%.1f", String(character), timing.turn, timing.sync, queries.last ?? -1)) }
                rows.append(palette.result.matches.count)
                historyRows.append(palette.result.matches.filter { $0.provider == .history }.count)
                if palette.result.inlineCompletion != nil { inline += 1 }
            }
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(100))
        }
        palette.onQueryTimed = nil
        SpikeRunner.record("typing_end_epoch_ms", Int(Date().timeIntervalSince1970 * 1000))
        SpikeRunner.record("keystrokes", keyTurn.count)
        SpikeRunner.record("keystroke_to_rows_turn", SpikeRunner.stats(keyTurn))
        SpikeRunner.record("keystroke_to_rows_first_key", SpikeRunner.stats(firstKey))
        SpikeRunner.record("keystroke_to_rows_later_keys", SpikeRunner.stats(laterKeys))
        // Up to the run loop's display pass: the rest of a turn is AppKit's layout, drawing and the Core Animation commit.
        SpikeRunner.record("keystroke_before_display_first_key", SpikeRunner.stats(firstKeyBeforeDisplay))
        SpikeRunner.record("keystroke_before_display_later_keys", SpikeRunner.stats(laterKeysBeforeDisplay))
        SpikeRunner.record("first_keys_turn_sync_query_ms", firstKeyLog.joined(separator: ", "))
        SpikeRunner.record("keystroke_query_only", SpikeRunner.stats(queries))
        SpikeRunner.record("keystroke_query_only_first_key", SpikeRunner.stats(firstQueries))
        for key in phases.keys.sorted() { SpikeRunner.record("query_phase_\(key)", SpikeRunner.stats(phases[key] ?? [])) }
        palette.onQueryPhases = nil
        SpikeRunner.record("rows_per_keystroke", "min \(rows.min() ?? 0) max \(rows.max() ?? 0)")
        SpikeRunner.record("history_rows_per_keystroke", "min \(historyRows.min() ?? 0) max \(historyRows.max() ?? 0) "
            + "mean \(String(format: "%.1f", Double(historyRows.reduce(0, +)) / Double(max(1, historyRows.count))))")
        SpikeRunner.record("keystrokes_with_inline_completion", inline)
    }
}

/// A display link that runs for the whole measurement and remembers when
/// each frame started; `firstTick(after:)` finds the first frame after an
/// instant (`nil` if none comes: occluded window).
final class FrameTicks: NSObject {
    private var link: CADisplayLink?
    private var times: [ContinuousClock.Instant] = []
    private var intervals: [Double] = []

    init(view: NSView) {
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        times.append(.now)
        if times.count > 600 { times.removeFirst(times.count - 600) }
        intervals.append((link.targetTimestamp - link.timestamp) * 1000)
    }

    func firstTick(after instant: ContinuousClock.Instant, timeout: Double) async -> ContinuousClock.Instant? {
        let deadline = ContinuousClock.now + .milliseconds(Int(timeout * 1000))
        while ContinuousClock.now < deadline {
            if let tick = times.first(where: { $0 > instant }) { return tick }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    /// The display's frame interval as the link reported it (8.3 ms at 120 Hz).
    var intervalDescription: String {
        guard !intervals.isEmpty else { return "no frames (window occluded)" }
        let sorted = intervals.sorted()
        return String(format: "median %.2f ms (min %.2f, max %.2f, %d frames)", sorted[sorted.count / 2], sorted.first!, sorted.last!,
                      sorted.count)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
#endif
