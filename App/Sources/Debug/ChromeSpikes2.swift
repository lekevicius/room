#if DEBUG
import AppKit
import Card
import Chrome
import Design
import Engine
import Observation
import Tabs
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif

/// Phase 2.6b: `chromesurfaces2` (`scripts/chrome-surfaces.sh --session 2.6b`)
/// exercises every member of the three delegate tables in `docs/engine-api.md`
/// on the engine: the 2.6a checks again (without their captures), then downloads,
/// find (with the keystroke-to-match measurement), zoom, print, the status
/// pill, the site panel, the engine withdrawing a dialog and a permission
/// prompt, a crashed renderer, element fullscreen, the certificate
/// interstitial's empty state (B-25), the DevTools pane (open time, resize,
/// console), audio, keys and navigation. Each page the tab controller takes
/// on gets recording proxies in front of it, so `delegate_calls` lists what
/// the engine actually called. Captures (`-RoomSpikeCaptures2b YES`) are named
/// `phase-2.6b-<name>-<appearance>`.
extension SpikeRunner.Context {
    private var app: AppDelegate? { AppDelegate.current }

    func chromeSurfaces2() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        controller.activityOverride = true
        let recorder = DelegateRecorder.shared
        recorder.install(tabs: tabs, profiles: Array(tabs.engineProfiles.values), downloads: app?.downloads?.list)
        // Downloads go to a throwaway folder, never ~/Downloads.
        let downloadFolder = FileManager.default.temporaryDirectory.appending(path: "room-2.6b-downloads-\(UUID().uuidString)")
        // The setting comes back as it was: later runs on the same state (the grand tour) read it.
        let downloadDirectoryWas = sidebar.store.settings.settings.downloadDirectory
        defer { sidebar.store.settings.update { $0.downloadDirectory = downloadDirectoryWas } }
        sidebar.store.settings.update { $0.downloadDirectory = downloadFolder.path }
        await activate()
        await forgetTestSiteDecisions()
        // `-RoomSpikeOnly downloads,fullscreen` runs only those checks (reruns while fixing).
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        func runs(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
        // The 2.6a members (dialogs, auth, certificate, permissions, files, menus, popups).
        if runs("dialogs") { await dialogsCheck() }
        if runs("auth") { await authCheck() }
        if runs("certificate") { await certificateCheck() }
        if runs("permissions") { await permissionsCheck() }
        if runs("files") { await filesCheck() }
        if runs("menus") { await contextMenuCheck() }
        if runs("popups") { await popupsCheck() }
        // 2.6b.
        if runs("downloads") { await downloadsCheck(folder: downloadFolder) }
        // 3.4a, on a state an earlier run downloaded into (only when asked):
        // the list a relaunch restores (B-28), and a quit with a download in
        // flight (the host's decision; Chrome's prompt never shows).
        if only.contains("downloadsrestore") { await downloadsRestoreCheck() }
        if only.contains("downloadquit") { await downloadQuitCheck() }
        if runs("find") { await findCheck() }
        if runs("zoom") { await zoomCheck() }
        // Real sites over the network: only when asked (`-RoomSpikeOnly security`, 3.3a).
        if only.contains("security") { await securityCheck() }
        // One public HSTS host with a bad certificate: only when asked (`-RoomSpikeOnly hsts`, 3.4a, B-24).
        if only.contains("hsts") { await hstsCheck() }
        if runs("print") { await printCheck() }
        if runs("status") { await statusPillCheck() }
        if runs("sitepanel") { await sitePanelCheck() }
        if runs("dismissals") { await dismissalsCheck() }
        if runs("crash") { await crashCheck() }
        if runs("fullscreen") { await fullscreenCheck() }
        if runs("devtools") { await devToolsPaneCheck() }
        if runs("keys") { await audioAndKeysCheck() }
        SpikeRunner.record("delegate_calls", recorder.summary)
        try? FileManager.default.removeItem(at: downloadFolder)
    }

    /// A window capture for 2.6b (the script answers it; popovers are child
    /// windows and come along). `screen`: the window's screen rect instead, so
    /// child windows of their own (RoomCore's print preview) show too.
    func captureB(_ name: String, screen: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures2b") else { return }
        let full = "phase-2.6b-\(name)-\(appearanceSuffix)"
        if screen {
            let frame = window.frame
            let top = (NSScreen.screens.first?.frame.height ?? 0) - frame.maxY
            SpikeRunner.record("capture_screen", "\(full) \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        } else {
            SpikeRunner.record("capture", full)
        }
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + full)
        if !(await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }) { SpikeRunner.record("capture_timeout", full) }
    }

    // MARK: Downloads

    private func downloadsCheck(folder: URL) async {
        guard let app, let downloads = app.downloads, let page = await openTest("downloads.html") else { return }
        let list = downloads.list
        let button = sidebar.downloadsButton
        // The launch's profile request can finish after the spike started and set the list again.
        tabs.engineProfile(for: page)?.downloadsDelegate = DelegateRecorder.shared
        await click(page, "#slow")
        _ = await waitUntil(5) { list.rows.contains { $0.item.suggestedFilename.contains("slow") } }
        try? await Task.sleep(for: .milliseconds(1500))
        let slow = list.rows.first { $0.item.suggestedFilename.contains("slow") }
        SpikeRunner.record("download_begin", "rows=\(list.rows.count) destination=\(slow?.destination?.path.replacingOccurrences(of: folder.path, with: "<folder>") ?? "nil") "
            + "ring=\(button.progress.map { String(format: "%.2f", $0) } ?? "nil") detail=\(slow.map { DownloadRules.detail(for: $0.item) } ?? "nil")")
        downloads.togglePopover()
        _ = await waitUntil(3) { downloads.popover.isShown }
        try? await Task.sleep(for: .milliseconds(400))
        await captureB("downloads-popover")
        downloads.popover.close()
        // Names: the same file twice is numbered.
        await click(page, "#small")
        // Not `allSatisfy` alone: true before the first row exists (then the second click came 14 ms
        // after the first and Blink dropped it as a duplicate navigation, 3.4b).
        _ = await waitUntil(5) {
            let small = list.rows.filter { $0.item.suggestedFilename.contains("small") }
            return !small.isEmpty && small.allSatisfy { $0.item.state == .complete }
        }
        await click(page, "#again")
        _ = await waitUntil(5) { list.rows.filter { $0.item.suggestedFilename.contains("small") }.count == 2 }
        _ = await waitUntil(5) { list.rows.filter { $0.item.suggestedFilename.contains("small") }.allSatisfy { $0.item.state == .complete } }
        let names = list.rows.filter { $0.item.suggestedFilename.contains("small") }.compactMap { $0.destination?.lastPathComponent }
        SpikeRunner.record("download_names", names.joined(separator: " | ") + " on disk=\(names.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) })")
        // Unknown size: the ring spins.
        await click(page, "#unknown")
        _ = await waitUntil(5) { list.rows.contains { $0.item.suggestedFilename.contains("unknown") && $0.item.receivedBytes > 0 } }
        SpikeRunner.record("download_unknown_size", "total=\(list.rows.first { $0.item.suggestedFilename.contains("unknown") }?.item.totalBytes.map(String.init) ?? "nil") ring=\(button.progress.map { String(format: "%.2f", $0) } ?? "nil")")
        // Pause, resume, cancel (Profile's controls through the list).
        await click(page, "#cancel")
        _ = await waitUntil(5) { list.rows.contains { $0.item.suggestedFilename.contains("cancel") && $0.item.receivedBytes > 0 } }
        if let id = list.rows.first(where: { $0.item.suggestedFilename.contains("cancel") })?.id {
            list.pause(id)
            let paused = await waitUntil(5) { list.row(id)?.item.isPaused == true }
            list.resume(id)
            let resumed = await waitUntil(5) { list.row(id)?.item.isPaused == false }
            list.cancel(id)
            let cancelled = await waitUntil(5) { list.row(id)?.item.state == .cancelled }
            SpikeRunner.record("download_controls", "paused=\(paused) resumed=\(resumed) cancelled=\(cancelled) file left=\(list.row(id)?.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)")
        }
        _ = await waitUntil(15) { list.rows.allSatisfy { $0.item.state != .inProgress } }
        SpikeRunner.record("download_complete", "states=\(list.rows.map { "\($0.item.suggestedFilename):\($0.item.state)" }.joined(separator: ",")) "
            + "badge=\(button.badgeCount) ring=\(button.progress.map { String(format: "%.2f", $0) } ?? "nil") slow size=\(slow?.destination.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? -1)")
        await captureB("downloads-badge")
        downloads.togglePopover()
        _ = await waitUntil(3) { downloads.popover.isShown }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("download_seen", "badge after opening=\(button.badgeCount)")
        list.clear()
        SpikeRunner.record("download_clear", "rows=\(list.rows.count)")
        downloads.popover.close()
    }

    /// B-28: the engine's history replays earlier sessions' downloads into
    /// the list at launch (RoomCore: Chrome's DownloadHistory).
    private func downloadsRestoreCheck() async {
        guard let downloads = app?.downloads else { return }
        let list = downloads.list
        _ = await waitUntil(10) { !list.rows.isEmpty }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("download_restored", "rows=\(list.rows.count) "
            + list.rows.map { "\($0.destination?.lastPathComponent ?? $0.item.suggestedFilename):\($0.item.state):canResume=\($0.item.canResume)" }.joined(separator: ","))
        downloads.togglePopover()
        _ = await waitUntil(3) { downloads.popover.isShown }
        try? await Task.sleep(for: .milliseconds(400))
        await captureB("downloads-restored")
        downloads.popover.close()
    }

    /// Starts the slow download and leaves it running: the spike's quit then
    /// runs Chrome's close path with a download in flight.
    private func downloadQuitCheck() async {
        guard let downloads = app?.downloads, let page = await openTest("downloads.html") else { return }
        let list = downloads.list
        await click(page, "#slow")
        let started = await waitUntil(5) { list.rows.contains { $0.item.suggestedFilename.contains("slow") && $0.item.receivedBytes > 0 } }
        if let id = list.rows.first(where: { $0.item.suggestedFilename.contains("slow") })?.id {
            list.pause(id)
            _ = await waitUntil(5) { list.row(id)?.item.isPaused == true }
            SpikeRunner.record("download_paused_can_resume", "\(list.row(id)?.item.canResume ?? false)")
            list.resume(id)
            _ = await waitUntil(5) { list.row(id)?.item.isPaused == false }
        }
        SpikeRunner.record("download_in_flight_at_quit", "started=\(started) in progress=\(list.rows.filter { $0.item.state == .inProgress }.count)")
    }

    // MARK: Find

    /// Keystroke in the find field → the engine's first result with a highlighted match.
    private func findCheck() async {
        guard let app, let find = app.find, let page = await openTest("find.html") else { return }
        try? await Task.sleep(for: .milliseconds(500))
        var firstMatch: [Double] = []
        var final: [Double] = []
        var samples: [String] = []
        for word in ["lighthouse", "harbour", "gulls", "quay"] {
            // ⌘F through the menu: the bar opens with the keyboard in its field.
            sendKey("f", keyCode: 3, [.command])
            _ = await waitUntil(2) { find.isVisible }
            for (index, character) in word.enumerated() {
                let start = ContinuousClock.now
                let timing = FindTiming(page: page)
                type(String(character))
                let gotMatch = await waitUntil(5) { timing.firstMatch != nil }
                _ = await waitUntil(5) { timing.final != nil }
                if gotMatch, let at = timing.firstMatch {
                    firstMatch.append(ms(between: start, and: at))
                    samples.append(String(format: "%@:%.0f", String(word.prefix(index + 1)), ms(between: start, and: at)))
                }
                if let at = timing.final { final.append(ms(between: start, and: at)) }
                if index == word.count - 1, word == "lighthouse" {
                    try? await Task.sleep(for: .milliseconds(200))
                    SpikeRunner.record("find_count", "\"\(find.countText)\" result=\(page.findResult.map { "\($0.activeMatch)/\($0.matchCount) final=\($0.isFinal)" } ?? "nil")")
                    await captureB("find-bar")
                    find.findNext(forward: true)
                    _ = await waitUntil(3) { page.findResult?.activeMatch == 2 }
                    let next = find.countText
                    sendKey("G", keyCode: 5, [.command, .shift])
                    _ = await waitUntil(3) { page.findResult?.activeMatch == 1 }
                    SpikeRunner.record("find_step", "⌘G → \"\(next)\", ⇧⌘G → \"\(find.countText)\"")
                }
            }
            find.close()
            try? await Task.sleep(for: .milliseconds(200))
        }
        SpikeRunner.record("find_keystroke_to_match", SpikeRunner.stats(firstMatch))
        SpikeRunner.record("find_samples_ms", samples.joined(separator: " "))
        SpikeRunner.record("find_keystroke_to_final", SpikeRunner.stats(final))
        SpikeRunner.record("find_closed", "bar=\(find.isVisible) result=\(page.findResult.map { "\($0)" } ?? "nil") focus=\(focusName)")
    }

    private var trafficLightsState: String {
        let frame = window.standardWindowButton(.closeButton)?.frame ?? .zero
        return "close=\(NSStringFromRect(frame)) toolbar=\(window.toolbar?.isVisible.description ?? "none")"
    }

    private var focusName: String { window.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil" }

    private func ms(between start: ContinuousClock.Instant, and end: ContinuousClock.Instant) -> Double {
        let d = end - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    // MARK: Zoom and print

    private func zoomCheck() async {
        // B-27: another loaded page of the same host, in the background (Chrome's zoom is per host).
        let sibling = session.newPage(URL(string: "http://127.0.0.1:8766/status.html"), hidden: true, select: false)
        if let sibling { await waitLoaded(sibling) }
        guard let app, let zoom = app.zoom, let page = await openTest("find.html") else { return }
        focusPage(page)
        // ⌘= reaches the page first; unhandled, it comes back to the main menu (handleUnhandledKeyEvent).
        sendKey("=", keyCode: 24, [.command])
        _ = await waitUntil(3) { abs(page.zoomFactor - 1.1) < 0.001 }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("zoom_in", "factor=\(page.zoomFactor) indicator=\"\(zoom.labelText)\" page devicePixelRatio=\(await js(page, "window.devicePixelRatio"))")
        SpikeRunner.record("zoom_same_host_page", "a background page of the same host: factor=\(sibling.map { "\($0.zoomFactor)" } ?? "nil") (B-27)")
        await captureB("zoom-indicator")
        sendKey("-", keyCode: 27, [.command])
        sendKey("-", keyCode: 27, [.command])
        _ = await waitUntil(3) { abs(page.zoomFactor - 0.9) < 0.001 }
        let out = page.zoomFactor
        sendKey("0", keyCode: 29, [.command])
        _ = await waitUntil(3) { abs(page.zoomFactor - 1) < 0.001 }
        SpikeRunner.record("zoom_out_reset", "after ⌘- ⌘- \(out), after ⌘0 \(page.zoomFactor)")
        let hidden = await waitUntil(3) { !zoom.isVisible }
        SpikeRunner.record("zoom_indicator_hides", hidden)
        SpikeRunner.record("zoom_same_host_page_after_reset", "factor=\(sibling.map { "\($0.zoomFactor)" } ?? "nil")")
        sibling?.close()
    }

    // MARK: Security state (the header's site icon, 2.3)

    /// The padlock states: a real HTTPS site, a page on the loopback test
    /// server, a plain-HTTP real site, a self-signed HTTPS page.
    private func securityCheck() async {
        for (name, url) in [("https", "https://example.com/"), ("loopback_http", "http://127.0.0.1:8766/find.html"),
                            ("http", "http://neverssl.com/"), ("self_signed", "https://127.0.0.1:8767/secure.html")] {
            guard let page = await open(URL(string: url)!) else { continue }
            await waitLoaded(page)
            try? await Task.sleep(for: .milliseconds(500))
            SpikeRunner.record("security_\(name)", "\(page.url?.absoluteString ?? "nil") level=\(page.securityState.level) mixed=\(page.securityState.hasMixedContent)")
        }
    }

    /// B-24: a preloaded HSTS host with a certificate for another name
    /// (badssl.com's test host; one request) shows the interstitial without
    /// Visit … Anyway; the loopback self-signed page offers it.
    private func hstsCheck() async {
        for (name, url) in [("hsts", "https://subdomain.preloaded-hsts.badssl.com/"), ("plain", Self.secureServer + "secure.html")] {
            guard let page = session.newPage(URL(string: url)!) else { continue }
            var state = await waitForDialog()
            if case .certificate(let error)? = prompts.visibleDialog?.dialog {
                state += " code=\(error.code) \(error.description) overridable=\(error.isOverridable)"
            }
            let proceed = button(identifier: "certificate-proceed", in: presenter?.dialogView)
            SpikeRunner.record("certificate_\(name)", state + " visit_anyway=\(proceed != nil)")
            await captureB("certificate-\(name)")
            pressReturn()  // Go Back
            _ = await waitUntil(5) { self.prompts.visibleDialog == nil }
            try? await Task.sleep(for: .milliseconds(500))
            _ = page
        }
    }

    /// RoomCore (3.3b) opens Chrome's print preview: a Views dialog in
    /// a child window over Room's window (B-29). The spike waits for that
    /// window, has the screen rect captured, then dismisses the preview with
    /// Esc, as a person would, and waits for the window to go. A system print
    /// panel run app-modally instead (Chapter 2's engine) is found by a timer
    /// in the common modes, recorded as `print_panel` and aborted.
    private func printCheck() async {
        // A local page that does not change under the preview (Chrome closes
        // its preview when the initiator navigates, pushState included).
        guard let page = await openTest("status.html") else { SpikeRunner.record("error", "no page to print"); return }
        let windowsBefore = Set(NSApp.windows.map { ObjectIdentifier($0) })
        let watch = ModalWatch(window: window)
        watch.start()
        let start = ContinuousClock.now
        page.print()
        var preview: NSWindow?
        _ = await waitUntil(16) {
            preview = NSApp.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 200 }
            return watch.done || preview != nil
        }
        guard let preview else {
            try? await Task.sleep(for: .milliseconds(500))
            SpikeRunner.record("print_panel", watch.seen ?? "none in 15 s")
            return
        }
        let shownAfter = ms(since: start)
        // The preview renders its first page a moment later; its window's state meanwhile.
        var states: [String] = []
        for _ in 0..<40 {
            let pageVisibility = await js(page, "document.visibilityState")
            let state = "visible=\(preview.isVisible) parent=\(preview.parent == nil ? "none" : "set") active=\(NSApp.isActive) page=\(pageVisibility) inWindow=\(page.nativeView.window === window) key=\(window.isKeyWindow)"
            if states.last?.hasSuffix(state) != true { states.append(String(format: "%.0fms %@", ms(since: start), state)) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        SpikeRunner.record("print_preview_states", states.joined(separator: "; ") + " hidesOnDeactivate=\(preview.hidesOnDeactivate)")
        // The preview's window, up its parents (the dialog's own, the modal host's widget, Room's window).
        var chain: [String] = []
        var ancestor = preview.parent
        while let current = ancestor {
            chain.append(current === window ? "Room's window" : "\(Swift.type(of: current))")
            ancestor = current.parent
        }
        let parent = chain.isEmpty ? "none" : chain.joined(separator: " ← ")
        let order = NSApp.orderedWindows.firstIndex(of: preview).map(String.init) ?? "-"
        let roomOrder = NSApp.orderedWindows.firstIndex(of: window).map(String.init) ?? "-"
        SpikeRunner.record("print_preview_window", "level \(preview.level.rawValue) order \(order) (Room's window \(roomOrder)) occlusion visible=\(preview.occlusionState.contains(.visible)) key=\(preview.isKeyWindow)")
        SpikeRunner.record("print_preview", String(format: "%@ after %.0f ms, parent %@, frame %@ over the window %@", "\(Swift.type(of: preview))",
                                                    shownAfter, parent, NSStringFromRect(preview.frame), NSStringFromRect(window.frame)))
        await captureB("print-preview", screen: true)
        let escStart = ContinuousClock.now
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: preview.windowNumber, context: nil, characters: "\u{1b}",
                                            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                NSApp.sendEvent(event)
            }
        }
        let gone = await waitUntil(5) { !preview.isVisible || !NSApp.windows.contains(preview) }
        SpikeRunner.record("print_preview_dismissed", String(format: "%@ by Esc after %.0f ms", gone ? "closed" : "still open", ms(since: escStart)))
        if !gone { SpikeRunner.record("error", "print: the preview did not close on Esc") }
    }

    // MARK: Status pill

    private func statusPillCheck() async {
        guard let app, let pill = app.statusPill, let page = await openTest("status.html") else { return }
        if await PageDriver.evaluate(page, "1", "status: probe whether the engine runs script") == nil {
            // RoomCore until 3.3b: the first link's fixed place in the fixture; the hovered link only.
            PageDriver.hover(page, at: CGPoint(x: 680, y: 56), "hover #short by point")
            let arrived = await waitUntil(3) { pill.state.status != nil }
            SpikeRunner.record("status_pill_by_point", "arrived=\(arrived) status=\(pill.state.status ?? "nil") visible=\(await waitUntil(3) { pill.state.isVisible })")
            PageDriver.hover(page, at: CGPoint(x: 300, y: 300), "hover off the link")
            let cleared = await waitUntil(3) { pill.state.status == nil }
            SpikeRunner.record("status_pill_cleared", "\(cleared)")
            return
        }
        var arrivals: [Double] = []
        var shown: [Double] = []
        for selector in ["#short", "#long", "#corner"] {
            await hover(page, nil)
            _ = await waitUntil(3) { !pill.state.isVisible }
            try? await Task.sleep(for: .milliseconds(300))
            let start = ContinuousClock.now
            await hover(page, selector)
            if await waitUntil(3, { pill.state.status != nil }) { arrivals.append(ms(since: start)) }
            if await waitUntil(3, { pill.state.isVisible }), let at = pill.state.shownAt, let asked = pill.state.requestedAt {
                shown.append((at - asked) * 1000)
            }
            if selector == "#long" {
                try? await Task.sleep(for: .milliseconds(150))
                await captureB("status-pill")
                _ = await waitUntil(3) { pill.state.width == .full }
                try? await Task.sleep(for: .milliseconds(150))
                SpikeRunner.record("status_pill_full", "width=\(pill.state.width) frame=\(pill.pillView.map { NSStringFromRect($0.frame) } ?? "nil")")
                await captureB("status-pill-full")
            }
            if selector == "#corner" {
                // The pointer on the pill's corner: it moves bottom-right (a posted move reaches the pill's monitor).
                let pillFrame = pill.pillView?.frame ?? .zero
                let host = pill.pillView?.superview
                let before = pill.state.side
                var dodged = before
                var dodgedFrame: String?
                if let host {
                    let point = host.convert(NSPoint(x: pillFrame.midX, y: pillFrame.midY), to: nil)
                    postMouseMoved(at: point)
                    // Polled tightly: the page also sees the move and clears its status
                    // text, so the pill leaves (back to the leading side) soon after it moved.
                    let deadline = Date().addingTimeInterval(1)
                    while pill.state.side != .trailing, Date() < deadline { try? await Task.sleep(for: .milliseconds(1)) }
                    dodgedFrame = pill.pillView.map { NSStringFromRect($0.frame) }
                    dodged = pill.state.side
                }
                try? await Task.sleep(for: .milliseconds(150))
                SpikeRunner.record("status_pill_dodge", "\(before) → \(dodged) frame=\(dodgedFrame ?? "nil")")
                await captureB("status-pill-dodged")
            }
        }
        await hover(page, nil)
        let hidden = await waitUntil(2) { !pill.state.isVisible }
        SpikeRunner.record("status_hover_to_status_text", SpikeRunner.stats(arrivals))
        SpikeRunner.record("status_text_to_pill", SpikeRunner.stats(shown) + " (configured \(Int(Timing.statusPillDelay * 1000)) ms)")
        SpikeRunner.record("status_pill_hides", hidden)
    }

    /// The pointer over an element (a real mouse move on the page's view: Chromium reports the link as
    /// status text), or away from links.
    private func hover(_ page: any WebContents, _ selector: String?) async {
        var point = CGPoint(x: 600, y: 20)
        if let selector {
            guard let center = await PageDriver.center(of: selector, in: page, "hover \(selector)") else { return }
            point = center
        }
        PageDriver.hover(page, at: point, "hover \(selector ?? "away")")
    }

    private func postMouseMoved(at point: NSPoint) {
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            NSApp.postEvent(event, atStart: false)
        }
    }

    // MARK: Site panel

    private func sitePanelCheck() async {
        guard let app, let page = await openTest("permissions.html") else { return }
        _ = await js(page, "document.cookie = 'room=1; max-age=3600'; localStorage.setItem('room', '1'); document.cookie")
        app.showSitePanel()
        _ = await waitUntil(3) { app.sitePanel.isShown }
        guard let model = app.sitePanel.model else { return SpikeRunner.record("site_panel", "not shown") }
        let before = model.rows.map { "\($0.rawValue)=\(model.setting($0))" }.joined(separator: ",")
        model.set(.allow, for: .popups)
        model.set(.block, for: .geolocation)
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("site_panel", "origin=\(model.origin.absoluteString) before[\(before)] after[\(model.rows.map { "\($0.rawValue)=\(model.setting($0))" }.joined(separator: ","))] needsReload=\(model.needsReload)")
        await captureB("site-panel")
        model.reload()
        await waitLoaded(page)
        SpikeRunner.record("site_panel_page_sees", await js(page, Self.permissionStatesScript))
        await model.clearSiteData()
        SpikeRunner.record("site_panel_clear", "cleared=\(model.siteDataCleared) cookie=\(await js(page, "document.cookie")) storage=\(await js(page, "localStorage.getItem('room')"))")
        await model.resetPermissions()
        SpikeRunner.record("site_panel_reset", "stored=\(model.hasStoredSettings) geolocation=\(model.setting(.geolocation))")
        app.sitePanel.close()
    }

    // MARK: The engine withdrawing prompts

    private func dismissalsCheck() async {
        let recorder = DelegateRecorder.shared
        guard let page = await openTest("dialogs.html") else { return }
        let before = recorder.count("webContentsDidDismissJavaScriptDialogs")
        Task { await self.click(page, "#alert") }
        _ = await waitForDialog()
        page.load(URL(string: Self.server + "status.html")!)
        let gone = await waitUntil(5) { self.prompts.visibleDialog == nil }
        await waitLoaded(page)
        SpikeRunner.record("dialog_dismissed_by_navigation", "sheet gone=\(gone) dismiss calls \(before)→\(recorder.count("webContentsDidDismissJavaScriptDialogs")) title=\(page.title ?? "nil")")
        await captureB("dialog-dismissed-by-navigation")

        guard let permissions = await openTest("permissions.html") else { return }
        let dismissBefore = recorder.count("webContentsDidDismissPermissionPrompt")
        Task { await self.click(permissions, "#geo") }
        let asked = await waitUntil(8) { self.prompts.visiblePermission != nil }
        try? await Task.sleep(for: .milliseconds(300))
        permissions.load(URL(string: Self.server + "status.html")!)
        let withdrawn = await waitUntil(5) { self.prompts.visiblePermission == nil }
        await waitLoaded(permissions)
        SpikeRunner.record("permission_dismissed_by_navigation", "asked=\(asked) popover gone=\(withdrawn) dismiss calls \(dismissBefore)→\(recorder.count("webContentsDidDismissPermissionPrompt"))")
        await captureB("permission-dismissed-by-navigation")
    }

    // MARK: A crashed renderer

    private func crashCheck() async {
        guard let app, let page = await openTest("status.html") else { return }
        let calls = DelegateRecorder.shared.count("processGone")
        page.load(URL(string: "chrome://crash")!)
        var shown = await waitUntil(8) { app.promptPresenter?.crashView != nil }
        var how = "chrome://crash"
        if !shown {
            how = "chrome://kill"
            page.load(URL(string: "chrome://kill")!)
            shown = await waitUntil(8) { app.promptPresenter?.crashView != nil }
        }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("process_gone", "via \(how): view=\(shown) calls \(calls)→\(DelegateRecorder.shared.count("processGone")) status=\(DelegateRecorder.shared.lastDetail("processGone") ?? "nil") focus=\(focusName)")
        await captureB("crashed-page")
        pressReturn()  // Reload
        let gone = await waitUntil(8) { app.promptPresenter?.crashView == nil }
        await waitLoaded(page)
        SpikeRunner.record("process_gone_reload", "view gone=\(gone) title=\(page.title ?? "nil")")
    }

    // MARK: Element fullscreen

    private func fullscreenCheck() async {
        guard let page = await openTest("fullscreen.html") else { return }
        try? await Task.sleep(for: .milliseconds(500))
        let enters = DelegateRecorder.shared.count("webContentsDidRequestEnterFullscreen")
        let lightsBefore = trafficLightsState
        if await PageDriver.evaluate(page, "1", "fullscreen: probe whether the engine runs script") == nil {
            // RoomCore until 3.3b: the button's fixed place in the fixture.
            PageDriver.click(page, at: CGPoint(x: 680, y: 56), "click #enter by point")
        } else {
            await click(page, "#enter")
        }
        let entered = await waitUntil(8) { self.window.styleMask.contains(.fullScreen) && self.controller.rootView.isPageFullscreen }
        try? await Task.sleep(for: .milliseconds(1200))
        SpikeRunner.record("element_fullscreen_enter", "window fullscreen=\(entered) enter calls \(enters)→\(DelegateRecorder.shared.count("webContentsDidRequestEnterFullscreen")) "
            + "card=\(NSStringFromRect(controller.cardView.frame)) window=\(NSStringFromSize(window.contentLayoutRect.size)) page says \(await js(page, "document.getElementById('log').textContent"))")
        await captureB("element-fullscreen")
        page.exitFullscreen()
        let left = await waitUntil(8) { !self.window.styleMask.contains(.fullScreen) && !self.controller.rootView.isPageFullscreen }
        try? await Task.sleep(for: .milliseconds(800))
        SpikeRunner.record("traffic_lights_after_fullscreen", "before \(lightsBefore) after \(trafficLightsState)")
        SpikeRunner.record("element_fullscreen_exit", "window back=\(left) exit calls=\(DelegateRecorder.shared.count("webContentsDidRequestExitFullscreen")) sidebar=\(controller.isSidebarOpen) card=\(NSStringFromRect(controller.cardView.frame))")
        window.setContentSize(NSSize(width: 1244, height: 818))
    }

    // MARK: DevTools

    private func devToolsPaneCheck() async {
        guard let page = await openTest("find.html"), let container = app?.pageHostContainer else { return }
        guard page.devTools != nil else {
            return SpikeRunner.record("error", "devtools: this engine hosts no DevTools for the page (RoomCore: 3.3b)")
        }
        var loaded: [Double] = []
        var attached: [Double] = []
        for round in 0..<4 {
            let start = ContinuousClock.now
            session.host.toggleDevTools()
            guard await waitUntil(10, { devToolsFrontend(page) != nil }),
                  let frontend = devToolsFrontend(page) else { break }
            await waitLoaded(frontend, timeout: 10)
            loaded.append(ms(since: start))
            for _ in 0..<100 {
                if await js(frontend, Self.frontendAttached) == "true" { attached.append(ms(since: start)); break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            if round == 0 {
                // Drag the divider 150 pt up.
                let before = container.devToolsFraction
                let paneTop = container.bounds.height - DevToolsSplit.paneHeight(fraction: before, height: container.bounds.height)
                drag(in: container, from: NSPoint(x: container.bounds.midX, y: paneTop), to: NSPoint(x: container.bounds.midX, y: paneTop - 150))
                try? await Task.sleep(for: .milliseconds(500))
                SpikeRunner.record("devtools_resize", String(format: "fraction %.3f → %.3f", before, container.devToolsFraction))
                await captureB("devtools-pane")
            }
            session.host.toggleDevTools()
            _ = await waitUntil(5) { page.devTools?.isOpen == false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        SpikeRunner.record("devtools_open_to_frontend_loaded", SpikeRunner.stats(loaded))
        SpikeRunner.record("devtools_open_to_attached", SpikeRunner.stats(attached))
        // ⌥⌘J: the console.
        sendKey("j", keyCode: 38, [.command, .option])
        let opened = await waitUntil(10) { page.devTools?.isOpen == true }
        if let frontend = devToolsFrontend(page) {
            await waitLoaded(frontend, timeout: 10)
            var panel = "none"
            for _ in 0..<50 {
                panel = await js(frontend, "(async () => { try { const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js'); return UI.InspectorView.InspectorView.instance().tabbedPane.selectedTabId; } catch (e) { return 'error ' + e } })()")
                if panel.contains("console") { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            SpikeRunner.record("devtools_console", "opened=\(opened) panel=\(panel)")
            // ⌥⌘C with DevTools open: the element picker on the Elements panel (open(in:tool:)).
            app?.inspectElements(nil)
            var picker = "none"
            for _ in 0..<25 {
                picker = await js(frontend, "(async () => { try { const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js'); "
                    + "const a = UI.ActionRegistry.ActionRegistry.instance().getAction('elements.toggle-element-search'); "
                    + "return UI.InspectorView.InspectorView.instance().tabbedPane.selectedTabId + ' picker=' + a.toggled(); } catch (e) { return 'error ' + e } })()")
                if picker.contains("elements picker=true") { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            SpikeRunner.record("devtools_element_picker", "panel=\(picker)")
        }
        session.host.toggleDevTools()
        _ = await waitUntil(5) { page.devTools?.isOpen == false }
        // Restore the default share for later runs.
        container.devToolsFraction = DevToolsMetrics.defaultFraction
        UserDefaults.standard.removeObject(forKey: "RoomDevToolsFraction")
    }

    /// The front-end has a page target (it attached over the debugging port).
    private static let frontendAttached = "(async () => { try { const SDK = await import('devtools://devtools/bundled/core/sdk/sdk.js'); "
        + "return !!SDK.TargetManager.TargetManager.instance().primaryPageTarget(); } catch (e) { return false; } })()"

    /// A mouse drag through the window, as a person's (the divider tracks it).
    private func drag(in view: NSView, from start: NSPoint, to end: NSPoint) {
        let points = [start] + (1...6).map { i in NSPoint(x: start.x, y: start.y + (end.y - start.y) * CGFloat(i) / 6) }
        for (index, point) in points.enumerated() {
            let type: NSEvent.EventType = index == 0 ? .leftMouseDown : .leftMouseDragged
            if let event = NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.sendEvent(event)
            }
        }
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: view.convert(end, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            NSApp.sendEvent(up)
        }
    }

    // MARK: Audio, keys

    private func audioAndKeysCheck() async {
        let recorder = DelegateRecorder.shared
        guard let page = await openTest("audio.html") else { return }
        await click(page, "#play")
        let audible = await waitUntil(5) { page.isAudible }
        let quiet = await waitUntil(6) { !page.isAudible }
        page.isMuted = true
        page.isMuted = false
        SpikeRunner.record("audio", "audible=\(audible) stopped=\(quiet) audible calls=\(recorder.count("didChangeAudible")) muted calls=\(recorder.count("didChangeMuted"))")
        // A reserved key (⌘L) never reaches the page; ⌘= does and comes back unhandled.
        focusPage(page)
        let edits = session.addressFocusRequest
        sendKey("l", keyCode: 37, [.command])
        _ = await waitUntil(2) { self.session.addressFocusRequest > edits }
        SpikeRunner.record("keys", "reserved calls=\(recorder.count("isReservedKeyEvent")) ⌘L reached the app=\(session.addressFocusRequest > edits) "
            + "unhandled calls=\(recorder.count("handleUnhandledKeyEvent")) consumed calls=\(recorder.count("didConsumeKey")))")
        // ⇧⌘C and ⌥⇧⌘C: the page does not take them; the menu copies with a toast. The clipboard is put back after.
        let saved = NSPasteboard.general.string(forType: .string)
        focusPage(page)
        sendKey("C", keyCode: 8, [.command, .shift])
        try? await Task.sleep(for: .milliseconds(300))
        let url = NSPasteboard.general.string(forType: .string)
        sendKey("C", keyCode: 8, [.command, .shift, .option])
        try? await Task.sleep(for: .milliseconds(300))
        let markdown = NSPasteboard.general.string(forType: .string)
        SpikeRunner.record("copy_url", "⇧⌘C → \(url ?? "nil"), ⌥⇧⌘C → \(markdown ?? "nil")")
        NSPasteboard.general.clearContents()
        if let saved { NSPasteboard.general.setString(saved, forType: .string) }
    }
}

/// Watches a page's find results for the first one with a highlighted match
/// and the first final one, stamping the moment each arrives.
@MainActor
final class FindTiming {
    private(set) var firstMatch: ContinuousClock.Instant?
    private(set) var final: ContinuousClock.Instant?
    private weak var page: (any WebContents)?

    init(page: any WebContents) {
        self.page = page
        watch()
    }

    private func watch() {
        guard let page else { return }
        let ref = PageBox(page)
        withObservationTracking {
            _ = page.findResult
        } onChange: { [weak self] in
            let now = ContinuousClock.now
            Task { @MainActor in
                guard let self, let page = ref.page, let result = page.findResult else { self?.watch(); return }
                if self.firstMatch == nil, result.activeMatch > 0 { self.firstMatch = now }
                if self.final == nil, result.isFinal { self.final = now }
                if self.final == nil { self.watch() }
            }
        }
    }
}

/// Finds an app-modal panel or a sheet from a timer that also fires inside
/// the panel's modal loop, notes it and cancels it.
@MainActor
final class ModalWatch {
    private weak var window: NSWindow?
    private let began = Date()
    private(set) var seen: String?
    private(set) var done = false
    private var timer: Timer?

    init(window: NSWindow) {
        self.window = window
    }

    func start() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let elapsed = Int(Date().timeIntervalSince(began) * 1000)
        if let panel = NSApp.modalWindow {
            seen = "modal \(String(describing: Swift.type(of: panel))) after \(elapsed) ms"
            NSApp.abortModal()
        } else if let window, let sheet = window.attachedSheet {
            seen = "sheet \(String(describing: Swift.type(of: sheet))) after \(elapsed) ms"
            window.endSheet(sheet, returnCode: .cancel)
        } else if elapsed < 15_000 {
            return
        }
        done = true
        timer?.invalidate()
    }
}

@MainActor
final class PageBox {
    weak var page: (any WebContents)?
    init(_ page: any WebContents) { self.page = page }
}

/// Stands in front of the tab controller as every page's UI and navigation
/// delegate and in front of the downloads list as every profile's downloads
/// delegate: each call is counted, then forwarded unchanged.
@MainActor
final class DelegateRecorder: WebContentsUIDelegate, NavigationDelegate, DownloadsDelegate {
    static let shared = DelegateRecorder()
    private weak var tabs: TabController?
    private weak var downloads: DownloadList?
    private var counts: [String: Int] = [:]
    private var details: [String: String] = [:]

    func install(tabs: TabController, profiles: [any Profile], downloads: DownloadList?) {
        self.tabs = tabs
        self.downloads = downloads
        tabs.debugDidAdopt = { [weak self] page in
            page.uiDelegate = self
            page.navigationDelegate = self
        }
        for id in tabs.loadedEntryIDs { if let page = tabs.contents(for: id) { page.uiDelegate = self; page.navigationDelegate = self } }
        for profile in profiles { profile.downloadsDelegate = self }
    }

    func count(_ name: String) -> Int { counts[name, default: 0] }
    func lastDetail(_ name: String) -> String? { details[name] }

    /// The recorder when a spike installed it (chromesurfaces2, the tour's chrome26b).
    static var active: DelegateRecorder? { shared.tabs == nil ? nil : shared }

    var summary: String {
        counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    private func note(_ name: String, _ detail: String? = nil) {
        counts[name, default: 0] += 1
        if let detail { details[name] = detail }
    }

    private var target: (any WebContentsUIDelegate)? { tabs }

    // MARK: WebContentsUIDelegate

    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        note("didCreate", "\(disposition)")
        if let target { target.webContents(webContents, didCreate: newContents, targetURL: targetURL, disposition: disposition) } else { newContents.close() }
    }
    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
        note("webContentsDidRequestEnterFullscreen")
        target?.webContentsDidRequestEnterFullscreen(webContents, origin: origin)
    }
    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        note("webContentsDidRequestExitFullscreen")
        target?.webContentsDidRequestExitFullscreen(webContents)
    }
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        note("didChangeStatusText")
        target?.webContents(webContents, didChangeStatusText: text)
    }
    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        note("willShowContextMenu", "link=\(element.linkURL?.absoluteString ?? "nil") text=\(element.linkText ?? "nil") "
            + "media=\(element.mediaType) editable=\(element.isEditable) misspelled=\(element.misspelledWord ?? "nil") "
            + "suggestions=\(element.dictionarySuggestions) items=\(menu.items.count)")
        return target?.webContents(webContents, willShowContextMenu: menu, for: element) ?? false
    }
    func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?, completion: @escaping () -> Void) {
        note("runJavaScriptAlert")
        guard let target else { return completion() }
        target.webContents(webContents, runJavaScriptAlert: message, origin: origin, completion: completion)
    }
    func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?, completion: @escaping (Bool) -> Void) {
        note("runJavaScriptConfirm")
        guard let target else { return completion(false) }
        target.webContents(webContents, runJavaScriptConfirm: message, origin: origin, completion: completion)
    }
    func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?,
                     completion: @escaping (String?) -> Void) {
        note("runJavaScriptPrompt")
        guard let target else { return completion(nil) }
        target.webContents(webContents, runJavaScriptPrompt: message, defaultText: defaultText, origin: origin, completion: completion)
    }
    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        note("runBeforeUnloadDialog")
        guard let target else { return completion(true) }
        target.webContents(webContents, runBeforeUnloadDialogForReload: isReload, completion: completion)
    }
    func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {
        note("webContentsDidDismissJavaScriptDialogs")
        target?.webContentsDidDismissJavaScriptDialogs(webContents)
    }
    func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest], quietReason: PermissionQuietReason?,
                     completion: @escaping (PermissionResponse) -> Void) {
        note("willAskForPermission", requests.map { "\($0.kind)" }.joined(separator: "+"))
        guard let target else { return completion(.dismissed) }
        target.webContents(webContents, willAskForPermission: requests, quietReason: quietReason, completion: completion)
    }
    func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {
        note("webContentsDidDismissPermissionPrompt")
        target?.webContentsDidDismissPermissionPrompt(webContents)
    }
    func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge, completion: @escaping (URLCredential?) -> Void) {
        note("didReceiveAuthChallenge")
        guard let target else { return completion(nil) }
        target.webContents(webContents, didReceiveAuthChallenge: challenge, completion: completion)
    }
    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        note("didFailCertificateCheck", "\(error.code)")
        guard let target else { return completion(false) }
        target.webContents(webContents, didFailCertificateCheck: error, completion: completion)
    }
    func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest, completion: @escaping ([URL]?) -> Void) {
        note("runFileChooser")
        guard let target else { return completion(nil) }
        target.webContents(webContents, runFileChooser: request, completion: completion)
    }
    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        note("isReservedKeyEvent")
        return target?.webContents(webContents, isReservedKeyEvent: event) ?? false
    }
    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        note("handleUnhandledKeyEvent")
        return target?.webContents(webContents, handleUnhandledKeyEvent: event) ?? false
    }
    func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo) {
        note("didConsumeKey")
        target?.webContents(webContents, didConsumeKey: key)
    }
    func webContents(_ webContents: any WebContents, didChangeAudible isAudible: Bool) {
        note("didChangeAudible", "\(isAudible)")
        target?.webContents(webContents, didChangeAudible: isAudible)
    }
    func webContents(_ webContents: any WebContents, didChangeMuted isMuted: Bool) {
        note("didChangeMuted", "\(isMuted)")
        target?.webContents(webContents, didChangeMuted: isMuted)
    }
    func webContents(_ webContents: any WebContents, didChangeSecurityState state: SecurityState) {
        note("didChangeSecurityState", "\(state.level)")
        target?.webContents(webContents, didChangeSecurityState: state)
    }
    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        note("processGone", "\(status)")
        target?.webContents(webContents, processGone: status)
    }
    func webContentsDidClose(_ webContents: any WebContents) {
        note("webContentsDidClose")
        target?.webContentsDidClose(webContents)
    }
    // 3.4b
    func webContentsDidBecomeUnresponsive(_ webContents: any WebContents, completion: @escaping (UnresponsiveRendererAction) -> Void) {
        note("webContentsDidBecomeUnresponsive")
        guard let target else { return completion(.wait) }
        target.webContentsDidBecomeUnresponsive(webContents, completion: completion)
    }
    func webContentsDidBecomeResponsive(_ webContents: any WebContents) {
        note("webContentsDidBecomeResponsive")
        target?.webContentsDidBecomeResponsive(webContents)
    }
    func webContents(_ webContents: any WebContents, shouldOpenExternalURL request: ExternalURLRequest, completion: @escaping (Bool) -> Void) {
        note("shouldOpenExternalURL", request.url.absoluteString)
        guard let target else { return completion(false) }
        target.webContents(webContents, shouldOpenExternalURL: request, completion: completion)
    }
    func webContents(_ webContents: any WebContents, didAddInfoBar infoBar: InfoBar) {
        note("didAddInfoBar", "\(infoBar.kind) \(infoBar.message)")
        target?.webContents(webContents, didAddInfoBar: infoBar)
    }
    func webContents(_ webContents: any WebContents, didRemoveInfoBar infoBar: InfoBar) {
        note("didRemoveInfoBar")
        target?.webContents(webContents, didRemoveInfoBar: infoBar)
    }
    func webContents(_ webContents: any WebContents, didChangeCaptureState state: CaptureState) {
        note("didChangeCaptureState", "\(state.rawValue)")
        target?.webContents(webContents, didChangeCaptureState: state)
    }

    // MARK: NavigationDelegate

    func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        note("decidePolicy")
        return tabs?.webContents(webContents, decidePolicyFor: action) ?? action.disposition
    }
    func webContents(_ webContents: any WebContents, didCommitNavigation url: URL, transition: PageTransition) {
        note("didCommitNavigation")
        tabs?.webContents(webContents, didCommitNavigation: url, transition: transition)
    }

    // MARK: DownloadsDelegate

    func profile(_ profile: any Profile, willBeginDownload item: DownloadItem, completion: @escaping (URL?) -> Void) {
        note("willBeginDownload")
        guard let downloads else { return completion(nil) }
        downloads.profile(profile, willBeginDownload: item, completion: completion)
    }
    func profile(_ profile: any Profile, didUpdateDownload item: DownloadItem) {
        note("didUpdateDownload")
        downloads?.profile(profile, didUpdateDownload: item)
    }
}
extension SpikeRunner.Context {
    /// The DevTools front-end page, where the engine exposes it (RoomCore's
    /// adopted one).
    func devToolsFrontend(_ page: any WebContents) -> (any WebContents)? {
        #if ROOM_ENGINE_ROOMCORE
        (page.devTools as? RoomCoreDevTools)?.frontendPage
        #else
        nil
        #endif
    }
}
#endif
