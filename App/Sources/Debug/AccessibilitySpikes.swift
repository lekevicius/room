#if DEBUG
import AppKit
import Design
import Sidebar
import UIKitCore

/// `a11y` (5.3a, ROADMAP 5.3 task 1): the accessibility self-audit over the
/// real app. The matrix's surfaces (5.2a's states: rows in each state, the
/// header, the footer, the palette's groups, Peek, split, toasts, the
/// downloads popover, the site panel, the prompts, the Library, Settings'
/// sections, the incognito window, the top bar with extensions, the space
/// form) are set up one after another on 5.1a's fixture, and every visible
/// window of the app is walked with `AccessibilityAudit` (in-process, through
/// the elements' own NSAccessibility protocol). One line per surface and one
/// per finding; `a11y_total` is the before → after number.
/// `scripts/a11y-audit.sh` runs it on a throwaway state with suggestions off.
extension SpikeRunner.Context {
    func accessibilityAuditSpike() async {
        AccessibilityAudit.requestTree()
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        window.setContentSize(NSSize(width: 1200, height: 780))
        let downloads = FileManager.default.temporaryDirectory.appending(path: "room-5.3-downloads-\(UUID().uuidString)")
        sidebar.store.settings.update { $0.downloadDirectory = downloads.path; $0.askWhereToSave = false }
        defer { try? FileManager.default.removeItem(at: downloads) }
        guard let first = store.spaces.first,
              let fixture = try? MotionFixture(store: store, first: first, base: Self.server + "find.html", window: sidebar.windowID) else {
            return SpikeRunner.record("error", "a11y: fixture")
        }
        await forgetTestSiteDecisions()
        try? await Task.sleep(for: .seconds(1))
        sidebar.select(fixture.today[2])
        if let page = tabs.contents(for: fixture.today[2]) { await waitLoaded(page, timeout: 15) }
        _ = await waitUntil(10) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        await activate()
        try? await Task.sleep(for: .milliseconds(800))

        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let surfaces: [(String, [MatrixState])] = [
            ("window", [MatrixState(label: "at rest", shoot: { nil })]),
            ("rows", rowStates(fixture)),
            ("header", headerStates()),
            ("footer", footerStates()),
            ("palette", paletteStates()),
            ("peek", peekStates()),
            ("split", splitStates(fixture)),
            ("toasts", toastStates()),
            ("downloads", downloadStates()),
            ("sitepanel", sitePanelStates()),
            ("prompts", promptStates()),
            ("library", libraryStates()),
            ("settings", settingsStates()),
            ("incognito", incognitoStates()),
            ("extensions", await extensionStates()),
            ("spaceform", spaceFormStates()),
        ]
        // `-RoomA11yDump YES`: the trees themselves, one file beside the output (for the record and the next fix).
        let dump = UserDefaults.standard.bool(forKey: "RoomA11yDump")
        var tree: [String] = []
        var total = AccessibilityAudit.Report()
        for (name, states) in surfaces where only.isEmpty || only.contains(name) {
            var surface = AccessibilityAudit.Report()
            for state in states {
                await state.setup()
                try? await Task.sleep(for: .milliseconds(300))
                // The engine's own Views windows (Chromium's bubbles' hosts) are the engine's, not Room's.
                for target in NSApp.windows where target.isVisible && target.windowNumber > 0
                    && !NSStringFromClass(Swift.type(of: target)).hasPrefix("NativeWidget") {
                    let report = AccessibilityAudit.audit(target, dump: dump)
                    if dump { tree += ["== \(name) / \(state.label) / \(NSStringFromClass(Swift.type(of: target))) \"\(target.title)\""] + report.lines }
                    surface.merge(report)
                }
                await state.teardown()
            }
            let new = surface.findings.filter { !total.findings.contains($0) }
            total.merge(surface)
            SpikeRunner.record("a11y_\(name)", "\(states.count) states: \(surface.summary) new=\(new.count)")
            for finding in new { SpikeRunner.record("a11y_finding", "\(name): \(finding)") }
        }
        if dump, let output = UserDefaults.standard.string(forKey: "RoomSpikeOutput") {
            try? tree.joined(separator: "\n").write(toFile: output + ".tree.txt", atomically: true, encoding: .utf8)
        }
        let counts = Dictionary(grouping: total.findings, by: { $0.problem.rawValue }).map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: " ")
        SpikeRunner.record("a11y_total", "\(total.findings.count) findings (\(counts.isEmpty ? "none" : counts)); \(total.interactive) interactive of \(total.elements) elements walked")
    }
}
#endif
