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
    private func restorePaletteHooks() {
        guard let palette else { return }
        tabs.onNewTab = { [weak palette] in palette?.toggleNew() }
        tabs.onEditAddress = { [weak palette] docked in palette?.toggleEdit(docked: docked) }
    }

    private func type(_ text: String) {
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

    private func press(_ name: String) {
        switch name {
        case "⌘T": sendKey("t", keyCode: 17, [.command])
        case "⌘L": sendKey("l", keyCode: 37, [.command])
        case "↩": sendKey("\r", keyCode: 36, [])
        case "⌘↩": sendKey("\r", keyCode: 36, [.command])
        case "⌥↩": sendKey("\r", keyCode: 36, [.option])
        case "⎋": sendKey("\u{1b}", keyCode: 53, [])
        case "⇥": sendKey("\t", keyCode: 48, [])
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
        if let page = tabs.current { await waitLoaded(page, timeout: 20) }
        try? await Task.sleep(for: .seconds(1))

        var openSync: [Double] = [], openTurn: [Double] = [], firstFrame: [Double] = []
        for _ in 0..<40 {
            let probe = FrameProbe()
            let start = ContinuousClock.now
            let timing = await timedTurn { palette.toggleNew() }
            openSync.append(timing.sync)
            openTurn.append(timing.turn)
            if let panel = palette.debugPanel, let frame = await probe.nextFrame(of: panel, timeout: 0.25) {
                firstFrame.append(Double((frame - start).components.attoseconds) / 1e15 + Double((frame - start).components.seconds) * 1000)
            }
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(150))
        }
        SpikeRunner.record("palette_open_call", SpikeRunner.stats(openSync))
        SpikeRunner.record("palette_open_turn", SpikeRunner.stats(openTurn))
        SpikeRunner.record("palette_open_to_next_frame", firstFrame.isEmpty ? "no display-link frame (window occluded)" : SpikeRunner.stats(firstFrame))

        var queries: [Double] = []
        palette.onQueryTimed = { duration in
            queries.append(Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000)
        }
        var keyTurn: [Double] = [], firstKey: [Double] = [], laterKeys: [Double] = [], rows: [Int] = []
        for text in ["today tab 3", "pinned 4", "folder", "site1", "example.org/article", "tab 39", "zzz", "github.com", "wikipedia"] {
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(100))
            for (index, character) in text.enumerated() {
                let timing = await timedTurn { self.type(String(character)) }
                keyTurn.append(timing.turn)
                if index == 0 { firstKey.append(timing.turn) } else { laterKeys.append(timing.turn) }
                rows.append(palette.result.matches.count)
            }
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(100))
        }
        palette.onQueryTimed = nil
        SpikeRunner.record("keystrokes", keyTurn.count)
        SpikeRunner.record("keystroke_to_rows_turn", SpikeRunner.stats(keyTurn))
        SpikeRunner.record("keystroke_to_rows_first_key", SpikeRunner.stats(firstKey))
        SpikeRunner.record("keystroke_to_rows_later_keys", SpikeRunner.stats(laterKeys))
        SpikeRunner.record("keystroke_query_only", SpikeRunner.stats(queries))
        SpikeRunner.record("rows_per_keystroke", "min \(rows.min() ?? 0) max \(rows.max() ?? 0)")
    }
}

/// The first display-link callback for a view after now (the frame the
/// palette first appears in), or `nil` if none comes (occluded window).
private final class FrameProbe: NSObject {
    private var continuation: CheckedContinuation<ContinuousClock.Instant?, Never>?
    private var link: CADisplayLink?

    func nextFrame(of view: NSView, timeout: Double) async -> ContinuousClock.Instant? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let link = view.displayLink(target: self, selector: #selector(tick))
            self.link = link
            link.add(to: .main, forMode: .common)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(nil) }
        }
    }

    @objc private func tick() { finish(.now) }

    private func finish(_ instant: ContinuousClock.Instant?) {
        link?.invalidate()
        link = nil
        continuation?.resume(returning: instant)
        continuation = nil
    }
}
#endif
