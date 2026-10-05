#if DEBUG
import AppKit
import Chrome
import Engine
import Tabs

/// Phase 3.4b: `pageservices` (`scripts/chrome-surfaces.sh --session 3.4b`)
/// exercises the members 3.4b added on the real app, through the host's own
/// UI: the unresponsive-page view on a hung page (Wait, then Exit and the
/// crashed view), links to other applications (asked once per scheme; the
/// throwaway `roomtest:` handler records what it was asked to open), the
/// translate offer on a German page as a toast (Translate chosen), an engine
/// infobar (CDP's automation override) as a toast and its withdrawal, the
/// capture state with Chromium's fake devices (the row's indicator, then
/// `stopCapturing`), the media session, and a Chrome device chooser over the
/// window. `-RoomSpikeOnly hang,external,…` runs some; captures
/// (`-RoomSpikeCaptures3b YES`) are `phase-3.4b-<name>-<appearance>`.
///
/// Arguments it needs: `--enable-features=RendererHangWatcher:delay/3s`
/// (hang), `--use-fake-device-for-media-stream` (capture), a remote
/// debugging port and `-RoomSpikeCDPPort` (infobar), `-RoomSpikeExternalLog
/// <file>` (external: the handler's record).
extension SpikeRunner.Context {
    func pageServices() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        controller.activityOverride = true
        let recorder = DelegateRecorder.shared
        recorder.install(tabs: tabs, profiles: Array(tabs.engineProfiles.values), downloads: AppDelegate.current?.downloads?.list)
        await activate()
        await forgetTestSiteDecisions()
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        func runs(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
        if runs("hang") { await hangCheck() }
        if runs("external") { await externalCheck() }
        if runs("translate") { await translateCheck() }
        if runs("infobar") { await infoBarCheck() }
        if runs("capture") { await captureStateCheck() }
        if runs("media") { await mediaSessionCheck() }
        if runs("chooser") { await chooserCheck() }
        SpikeRunner.record("delegate_calls", recorder.summary)
    }

    func capture3b(_ name: String, screen: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures3b") else { return }
        let full = "phase-3.4b-\(name)-\(appearanceSuffix)"
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

    /// A host button by accessibility identifier under `view`.
    private func button(_ identifier: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.accessibilityIdentifier() == identifier { return button }
        for child in view.subviews { if let found = button(identifier, in: child) { return found } }
        return nil
    }

    private func pageLog(_ page: any WebContents) async -> String {
        await js(page, "document.getElementById('log') ? document.getElementById('log').textContent : ''")
    }

    // MARK: The hung page

    private func hangCheck() async {
        guard let page = await openTest("hang.html") else { return }
        let id = ObjectIdentifier(page)
        // The click starts a two-minute loop; the keys after it go unanswered.
        await click(page, "#hang")
        let start = ContinuousClock.now
        try? await Task.sleep(for: .milliseconds(300))
        sendKey("a", keyCode: 0, [])
        let asked = await waitUntil(40) { self.chrome.crashes.isUnresponsive(id) }
        let askedMs = ms(since: start)
        try? await Task.sleep(for: .milliseconds(300))
        await capture3b("unresponsive")
        SpikeRunner.record("hang_unresponsive", "asked=\(asked) after \(String(format: "%.0f", askedMs))ms view=\(button("unresponsive-page-wait", in: presenter?.crashView) != nil)")
        // Wait: the view goes, the page stays (still hung, so it is asked again).
        button("unresponsive-page-wait", in: presenter?.crashView)?.performClick(nil)
        try? await Task.sleep(for: .milliseconds(300))
        let waitedGone = !chrome.crashes.isUnresponsive(id) && presenter?.crashView == nil
        SpikeRunner.record("hang_wait", "view gone=\(waitedGone) state=\(page.state)")
        let againStart = ContinuousClock.now
        sendKey("b", keyCode: 11, [])
        let askedAgain = await waitUntil(40) { self.chrome.crashes.isUnresponsive(id) }
        SpikeRunner.record("hang_asked_again", "\(askedAgain) after \(String(format: "%.0f", ms(since: againStart)))ms")
        // Exit: the renderer ends; the crashed-page view follows.
        button("unresponsive-page-exit", in: presenter?.crashView)?.performClick(nil)
        let crashed = await waitUntil(15) { self.chrome.crashes.status(of: id) != nil }
        try? await Task.sleep(for: .milliseconds(300))
        await capture3b("unresponsive-exited")
        SpikeRunner.record("hang_exit", "crashed view=\(crashed) status=\(chrome.crashes.status(of: id).map { "\($0)" } ?? "nil") "
            + "reload button=\(button("crashed-page-reload", in: presenter?.crashView) != nil)")
        page.reload()
        _ = await waitUntil(10) { !page.isLoading && self.chrome.crashes.status(of: id) == nil }
        SpikeRunner.record("hang_reload", "crash view gone=\(chrome.crashes.status(of: id) == nil) title=\(page.title ?? "nil")")
    }

    // MARK: Links to other applications

    private func externalCheck() async {
        guard let page = await openTest("external.html") else { return }
        let log = UserDefaults.standard.string(forKey: "RoomSpikeExternalLog").map(URL.init(fileURLWithPath:))
        func launches() -> Int {
            guard let log, let text = try? String(contentsOf: log, encoding: .utf8) else { return 0 }
            return text.split(separator: "\n").count
        }
        func externalSheet() async -> ExternalURLRequest? {
            _ = await waitUntil(6) {
                if case .externalApp? = self.prompts.visibleDialog?.dialog { return true }
                return false
            }
            if case .externalApp(let request)? = prompts.visibleDialog?.dialog { return request }
            return nil
        }
        let asked = { DelegateRecorder.shared.count("shouldOpenExternalURL") }
        // 1. Refused: blocked (no launch).
        await click(page, "#roomtest")
        let first = await externalSheet()
        await capture3b("external-sheet")
        prompts.respond(.cancel)
        try? await Task.sleep(for: .seconds(1.5))
        SpikeRunner.record("external_refused", "sheet=\(first.map { "\($0.applicationName) \($0.url.absoluteString) gesture=\($0.isUserGesture) from=\($0.initiatingOrigin?.absoluteString ?? "nil")" } ?? "none") launches=\(launches())")
        // 2. Asked again, opened.
        await click(page, "#roomtest")
        let second = await externalSheet()
        pressReturn()
        let launched = await waitUntil(10) { launches() >= 1 }
        SpikeRunner.record("external_opened", "asked again=\(second != nil) launched=\(launched) launches=\(launches())")
        // 3. The same scheme: not asked, opened.
        let askedBefore = asked()
        await click(page, "#roomtest2")
        _ = await waitUntil(5) { asked() > askedBefore }
        let noSheet = await externalSheet() == nil
        let launchedAgain = await waitUntil(10) { launches() >= 2 }
        SpikeRunner.record("external_same_scheme", "delegate asked=\(asked() > askedBefore) sheet shown=\(!noSheet) launched=\(launchedAgain) launches=\(launches())")
        // 4. No handler: Chrome stops before asking (the host never hears of it).
        let askedBeforeNoHandler = asked()
        await click(page, "#nohandler")
        try? await Task.sleep(for: .seconds(2))
        SpikeRunner.record("external_no_handler", "delegate asked=\(asked() > askedBeforeNoHandler) sheet=\(prompts.visibleDialog != nil)")
    }

    // MARK: The translate offer

    private func translateCheck() async {
        guard let page = await openTest("translate.html") else { return }
        let offered = await waitUntil(20) { self.chrome.notices.contains { if case .translateOffer = $0.kind { true } else { false } } }
        let offer = chrome.notices.first { if case .translateOffer = $0.kind { true } else { false } }
        let toast = session.pageDelegate.toasts?.currentToast
        try? await Task.sleep(for: .milliseconds(200))
        await capture3b("translate-offer")
        SpikeRunner.record("translate_offer", "offered=\(offered) kind=\(offer.map { "\($0.kind)" } ?? "nil") message=\(offer?.message ?? "nil") "
            + "toast=\(toast?.message ?? "nil") button=\(toast?.action?.title ?? "nil")")
        guard let offer, toast?.id == PageChrome.noticeToastID(offer) else { return }
        let removedBefore = DelegateRecorder.shared.count("didRemoveInfoBar")
        toast?.action?.handler()
        let removed = await waitUntil(5) { DelegateRecorder.shared.count("didRemoveInfoBar") > removedBefore }
        let heading = await js(page, "document.querySelector('h1').textContent")
        // The translation itself fetches Google's translate script (the
        // user asked for it); the heading changes when it arrives.
        try? await Task.sleep(for: .seconds(8))
        let after = await js(page, "document.querySelector('h1').textContent + ' | lang=' + document.documentElement.lang")
        SpikeRunner.record("translate_chosen", "offer removed=\(removed) toast now=\(session.pageDelegate.toasts?.currentToast?.message ?? "none") "
            + "heading before=\(heading) after 8 s=\(after)")
    }

    // MARK: An engine infobar

    private func infoBarCheck() async {
        let port = UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort")
        guard port > 0 else {
            SpikeRunner.record("infobar", "skipped: needs --remote-debugging-port=<p> -RoomSpikeCDPPort <p>")
            return
        }
        guard let page = await openTest("status.html") else { return }
        do {
            let cdp = try await SpikeCDP.connect(port: port, pageURL: page.url?.absoluteString ?? "")
            let addedBefore = DelegateRecorder.shared.count("didAddInfoBar")
            try await cdp.call("Emulation.setAutomationOverride", ["enabled": true])
            let added = await waitUntil(5) { DelegateRecorder.shared.count("didAddInfoBar") > addedBefore }
            let notice = chrome.notices.last
            let toast = session.pageDelegate.toasts?.currentToast
            await capture3b("infobar")
            SpikeRunner.record("infobar_added", "added=\(added) kind=\(notice.map { "\($0.kind)" } ?? "nil") message=\(notice?.message ?? "nil") buttons=\(notice?.buttons ?? []) toast=\(toast?.message ?? "nil")")
            let removedBefore = DelegateRecorder.shared.count("didRemoveInfoBar")
            try await cdp.call("Emulation.setAutomationOverride", ["enabled": false])
            let removed = await waitUntil(5) { DelegateRecorder.shared.count("didRemoveInfoBar") > removedBefore }
            try? await Task.sleep(for: .milliseconds(300))
            let toastAfter = session.pageDelegate.toasts?.currentToast
            SpikeRunner.record("infobar_removed", "removed=\(removed) toast dismissed=\(toastAfter == nil || toastAfter?.id != notice.map(PageChrome.noticeToastID)) pending=\(chrome.notices.count)")
        } catch {
            SpikeRunner.record("infobar", "CDP: \(error)")
        }
    }

    // MARK: Capture state

    private func captureStateCheck() async {
        guard let page = await openTest("capture.html") else { return }
        let entry = tabs.entryID(for: page)
        await click(page, "#start")
        // The camera and microphone prompt is the host's popover: Allow.
        let prompted = await waitUntil(8) { self.prompts.visiblePermission != nil }
        let kinds = prompts.visiblePermission?.requests.map { "\($0.kind)" }.joined(separator: "+") ?? "none"
        prompts.respondToPermission(.granted)
        let start = ContinuousClock.now
        let capturing = await waitUntil(10) { page.captureState.contains(.camera) && page.captureState.contains(.microphone) }
        let onMs = ms(since: start)
        try? await Task.sleep(for: .milliseconds(800))
        let row = entry.map { tabs.pageState(for: $0).capture.map { "\($0)" } ?? "none" } ?? "no entry"
        await capture3b("capture-on")
        SpikeRunner.record("capture_on", "prompt=\(prompted) (\(kinds)) state=\(page.captureState.rawValue) after \(String(format: "%.0f", onMs))ms row=\(row) page=\(await pageLog(page))")
        let stopStart = ContinuousClock.now
        page.stopCapturing(.userMedia)
        let stopped = await waitUntil(10) { page.captureState.isEmpty }
        let offMs = ms(since: stopStart)
        try? await Task.sleep(for: .milliseconds(500))
        let rowAfter = entry.map { tabs.pageState(for: $0).capture.map { "\($0)" } ?? "none" } ?? "no entry"
        SpikeRunner.record("capture_off", "stopped=\(stopped) after \(String(format: "%.0f", offMs))ms state=\(page.captureState.rawValue) row=\(rowAfter) page=\(await pageLog(page))")
    }

    // MARK: Media session

    private func mediaSessionCheck() async {
        guard let page = await openTest("media.html") else { return }
        await click(page, "#play")
        let has = await waitUntil(10) { page.mediaSession != nil }
        try? await Task.sleep(for: .milliseconds(500))
        let session = page.mediaSession
        SpikeRunner.record("media_session", "has=\(has) title=\(session?.title ?? "nil") artist=\(session?.artist ?? "nil") album=\(session?.album ?? "nil") "
            + "artwork=\(session?.artworkURL?.absoluteString ?? "nil") state=\(session.map { "\($0.playbackState)" } ?? "nil") audible=\(page.isAudible) page=\(await pageLog(page))")
        page.isMuted = true
    }

    // MARK: A device chooser (Views, over the window)

    private func chooserCheck() async {
        guard let page = await openTest("chooser.html") else { return }
        let windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        await click(page, "#usb")
        let opened = await waitUntil(6) { NSApp.windows.contains { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && $0.className.contains("NativeWidget") } }
        try? await Task.sleep(for: .milliseconds(600))
        let bubble = NSApp.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && $0.className.contains("NativeWidget") }
        await capture3b("usb-chooser", screen: true)
        SpikeRunner.record("chooser_open", "opened=\(opened) window=\(bubble.map { "\($0.className) \(Int($0.frame.width))x\(Int($0.frame.height)) over room=\($0.frame.intersects(window.frame))" } ?? "none") page=\(await pageLog(page))")
        // Esc to the bubble cancels it (the page hears NotFoundError).
        bubble?.makeKeyAndOrderFront(nil)
        if let bubble, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: bubble.windowNumber, context: nil, characters: "\u{1b}",
                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
            NSApp.sendEvent(event)
        }
        let cancelled = await waitUntil(5) { !(bubble?.isVisible ?? false) }
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("chooser_cancel", "closed=\(cancelled) page=\(await pageLog(page))")
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
