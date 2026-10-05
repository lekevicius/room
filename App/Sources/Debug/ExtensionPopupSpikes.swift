#if DEBUG
import AppKit
import Chrome
import Engine
import UIKitCore

/// Phase 3.6b spike `extpopup` (`Room -RoomSpike extpopup`): the unpacked
/// fixture (`research/spikes/phase-3.6/extension`) through the header:
/// its action button with the badge, the popup from a click on the button
/// (a real NSEvent on the host's view), the page's own resize, the popover
/// closing on focus loss (a click on the page) with the engine told, Esc,
/// `action.openPopup()` from the fixture's service worker, `_execute_action`
/// and a named command from the keyboard, the named command's
/// `sidePanel.open()` (side panels are not supported), the open time
/// (click to the popup page's load, three times) and captures of the popup
/// over the header (research/screenshots/phase-3.6b).
///
/// The same popup steps run for Web Store extensions in `webstore` when
/// `-RoomWebstorePopups YES` is passed (`webstorePopupChecks`).
extension SpikeRunner.Context {
    var popupShots: URL {
        let url = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? SpikeRunner.pagesDirectory.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "screenshots/phase-3.6b")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// What the popover hooks saw, in order.
    final class PopupEvents {
        var shown: [(id: String, at: ContinuousClock.Instant, size: CGSize)] = []
        var resized: [CGSize] = []
        var closed: [Bool] = []  // byEngine
        weak var popover: ExtensionPopover?
    }

    func installPopupHooks() -> PopupEvents {
        let events = PopupEvents()
        ExtensionPopups.debugOnShow = { popover, id in
            events.shown.append((id, ContinuousClock.now, popover.contentSize))
            events.popover = popover
        }
        ExtensionPopups.debugOnResize = { events.resized.append($0) }
        ExtensionPopups.debugOnClose = { events.closed.append($0) }
        return events
    }

    /// A click on `view` (the header's button), as posted mouse events the
    /// run loop delivers (NSButton tracks the mouse-up in its own loop).
    func postClick(on view: NSView) {
        guard let window = view.window else { return SpikeRunner.record("error", "click: the view is not in a window") }
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    /// A click on the page's centre posted to the application (what a user's
    /// click elsewhere is to a transient popover).
    func postClick(onPage page: any WebContents) {
        let view = page.nativeView
        postClick(on: view)
    }

    /// The popover over the window as one image: the popover's window and
    /// everything below it inside the browser window's frame.
    func capturePopupOverWindow(_ name: String, popover: ExtensionPopover?) {
        guard let popoverWindow = popover?.window, let screen = window.screen else {
            return SpikeRunner.record("capture", "failed: \(name) (no popover window)")
        }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return SpikeRunner.record("capture", "failed: \(name) (no CGWindowListCreateImage)")
        }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // Global coordinates have their origin at the top-left of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        var rect = window.frame
        rect.origin.y = primaryHeight - window.frame.maxY
        let options: UInt32 = (1 << 0) | (1 << 3)               // BoundsIgnoreFraming | BestResolution
        let list: UInt32 = (1 << 2) | (1 << 3)                  // OnScreenBelowWindow | IncludingWindow
        guard let image = create(rect, list, UInt32(popoverWindow.windowNumber), options)?.takeRetainedValue() else {
            return SpikeRunner.record("capture", "failed: \(name)")
        }
        let file = popupShots.appending(path: "\(name).png")
        let rep = NSBitmapImageRep(cgImage: image)
        let written = (try? rep.representation(using: .png, properties: [:])?.write(to: file)) != nil
        SpikeRunner.record("capture", written ? "\(file.lastPathComponent) \(image.width)x\(image.height)" : "failed: \(name)")
    }

    /// Opens `id`'s popup from its header button and waits for the popover;
    /// the milliseconds from the click to the popover (the popup page's load).
    func openPopupFromHeader(_ id: String, events: PopupEvents, timeout: Double = 10) async -> Double? {
        guard let button = session.sidebar.addressField.extensionButton(for: id) else {
            SpikeRunner.record("error", "no header button for \(id) (header: \(session.sidebar.addressField.extensionActionIDs))")
            return nil
        }
        let before = events.shown.count
        let start = ContinuousClock.now
        postClick(on: button)
        guard await waitUntil(timeout, { events.shown.count > before }) else {
            SpikeRunner.record("error", "\(id): no popup \(Int(timeout)) s after the click")
            return nil
        }
        let shown = events.shown[events.shown.count - 1]
        return Double((shown.at - start).components.attoseconds) / 1e15 + Double((shown.at - start).components.seconds) * 1000
    }

    /// A key press for `window`: through the application while it is active
    /// (PageDriver.key); while another application holds the screen (the
    /// run's conditions: a system dialog in front, the window cannot become
    /// key, and AppKit hands ⌘-keys only to the key window), the same events
    /// straight to the engine's page view under `page` (the view the
    /// application would have given them to).
    func sendKey(_ window: NSWindow, page: NSView? = nil, characters: String, charactersIgnoringModifiers: String? = nil,
                 keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        guard !NSApp.isActive else {
            return PageDriver.key(window, characters: characters, charactersIgnoringModifiers: charactersIgnoringModifiers,
                                  keyCode: keyCode, modifiers: modifiers)
        }
        func engineView(in view: NSView?) -> NSView? {
            guard let view else { return nil }
            if NSStringFromClass(Swift.type(of: view)).contains("RenderWidgetHostView") { return view }
            for child in view.subviews { if let found = engineView(in: child) { return found } }
            return nil
        }
        guard let target = engineView(in: page ?? window.contentView) else {
            return SpikeRunner.record("error", "key: no page view in the window")
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters, isARepeat: false,
                                               keyCode: keyCode) else { continue }
            if type == .keyDown { target.keyDown(with: event) } else { target.keyUp(with: event) }
        }
    }

    /// Closes the open popover with Esc in its page and waits for it.
    func closePopupWithEsc(_ events: PopupEvents) async -> Bool {
        guard let popoverWindow = events.popover?.window else { return false }
        let before = events.closed.count
        PageDriver.key(popoverWindow, characters: "\u{1b}", keyCode: 53)
        return await waitUntil(5) { events.closed.count > before }
    }

    // MARK: extpopup

    func extensionPopupChecks() async {
        guard let app = AppDelegate.current, let center = app.extensions, let section = center.sections.first,
              app.extensionPopups != nil else {
            return SpikeRunner.record("extpopup", "skipped: the engine has no extensions (CEF)")
        }
        await activate()
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        let id: String
        do {
            id = try await section.extensions.loadUnpacked(at: fixture)
        } catch {
            return SpikeRunner.record("error", "load unpacked: \(error)")
        }
        let installed = { center.sections.first?.installed.first { $0.id == id } }
        _ = await waitUntil(5) { installed()?.action?.icon != nil }
        SpikeRunner.record("fixture", "id=\(id) pinned=\(installed()?.isPinned ?? false) popup=\(installed()?.action?.hasPopup ?? false)")
        guard let page = await open(URL(string: "https://example.com/")!) else { return SpikeRunner.record("error", "no page") }
        var marker = ""
        for _ in 0..<50 {
            marker = await js(page, "document.documentElement.dataset.roomFixtureTabs || ''")
            if marker.contains("1") || marker.contains("2") { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        let field = session.sidebar.addressField
        _ = await waitUntil(5) { field.extensionActionIDs.contains(id) }
        let header = center.headerActions(profile: session.sidebar.activeSpace?.profileID, page: page)
        SpikeRunner.record("header", "buttons=\(field.extensionActionIDs) badge=\"\(header.first?.badgeText ?? "nil")\" "
            + "title=\"\(header.first?.title ?? "nil")\" content_script_tabs=\(marker)")
        let events = installPopupHooks()

        // 1. The click: open, the page's load, the page's own resize.
        guard let openMs = await openPopupFromHeader(id, events: events) else { return }
        let firstSize = events.shown.last?.size ?? .zero
        _ = await waitUntil(3) { (events.resized.last?.width ?? 0) >= 360 }
        let popupPage = events.popover?.popup
        var state = "nil"
        if let popupPage { state = await js(popupPage, "document.getElementById('state') ? document.getElementById('state').textContent : null") }
        SpikeRunner.record("popup_click", String(format: "open %.1f ms; size at load %@; resized %@; popover now %@; page state %@",
                                                 openMs, NSStringFromSize(firstSize), "\(events.resized.map { NSStringFromSize($0) })",
                                                 NSStringFromSize(events.popover?.contentSize ?? .zero), state))
        SpikeRunner.record("popup_window", "key=\(events.popover?.window?.isKeyWindow ?? false) app_active=\(NSApp.isActive) "
            + "anchored_on_button=\(field.extensionButton(for: id)?.window === window)")
        try? await Task.sleep(for: .milliseconds(300))
        capturePopupOverWindow("fixture-popup-over-header", popover: events.popover)

        // 2. Focus loss: a click on the page; the popover closes itself and the engine destroys the popup.
        let closedBefore = events.closed.count
        postClick(onPage: page)
        let closedByFocus = await waitUntil(5) { events.closed.count > closedBefore }
        let popupGone = await waitUntil(5) { popupPage?.state == .closed }
        SpikeRunner.record("popup_focus_loss", "popover_closed=\(closedByFocus) by_engine=\(events.closed.last.map { "\($0)" } ?? "nil") "
            + "engine_destroyed_page=\(popupGone) center_shown=\(center.shownPopup != nil)")
        if !closedByFocus {
            // A standalone condition (another app frontmost): close it so the run continues.
            if let shown = center.shownPopup { center.popoverDidClose(shown.popup); events.popover?.close() }
        }

        // 3. Esc in the popup: the engine closes it (ExtensionViewHost), the popover follows.
        var openTimes = [openMs]
        for round in 0..<3 {
            await activate()
            guard let ms = await openPopupFromHeader(id, events: events) else { break }
            if round > 0 { openTimes.append(ms) }
            let page = events.popover?.popup
            let escClosed = await closePopupWithEsc(events)
            let gone = await waitUntil(5) { page?.state == .closed }
            SpikeRunner.record("popup_esc_\(round)", String(format: "open %.1f ms; esc closed=%@ by_engine=%@ page_destroyed=%@", ms,
                                                             "\(escClosed)", "\(events.closed.last.map { "\($0)" } ?? "nil")", "\(gone)"))
            try? await Task.sleep(for: .milliseconds(300))
        }
        let sortedTimes = openTimes.sorted()
        SpikeRunner.record("popup_open_times", "\(openTimes.map { String(format: "%.1f", $0) }) median=\(String(format: "%.1f", sortedTimes[sortedTimes.count / 2])) ms")

        // 4. action.openPopup() from the service worker.
        await activate()
        let shownBefore = events.shown.count
        let start = ContinuousClock.now
        _ = await js(page, "document.dispatchEvent(new Event('room-open-popup')); 'sent'")
        let apiShown = await waitUntil(8) { events.shown.count > shownBefore }
        var answer = ""
        for _ in 0..<20 {
            answer = await js(page, "document.documentElement.dataset.roomFixtureOpenPopup || ''")
            if !answer.isEmpty && answer != "\"\"" { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        SpikeRunner.record("action_open_popup", "popover=\(apiShown) in \(String(format: "%.0f", ms(since: start))) ms worker_answer=\(answer) "
            + "anchored_on=\(events.shown.last?.id ?? "nil") window_key_before=\(window.isKeyWindow)")
        if apiShown { _ = await closePopupWithEsc(events) }

        // 5. Commands from the keyboard: _execute_action (⇧⌘Y) opens and closes the popup, the named one (⇧⌘U) reaches onCommand.
        await activate()
        PageDriver.click(page, at: CGPoint(x: 40, y: 40), "focus the page")
        try? await Task.sleep(for: .milliseconds(300))
        let keyShownBefore = events.shown.count
        let keyStart = ContinuousClock.now
        sendKey(window, page: page.nativeView, characters: "Y", charactersIgnoringModifiers: "y", keyCode: 16, modifiers: [.command, .shift])
        let keyShown = await waitUntil(8) { events.shown.count > keyShownBefore }
        SpikeRunner.record("command_execute_action", "app_active=\(NSApp.isActive) popover=\(keyShown) in \(String(format: "%.0f", ms(since: keyStart))) ms")
        if keyShown, let popoverWindow = events.popover?.window {
            let closedBeforeKey = events.closed.count
            sendKey(popoverWindow, characters: "Y", charactersIgnoringModifiers: "y", keyCode: 16, modifiers: [.command, .shift])
            let toggled = await waitUntil(5) { events.closed.count > closedBeforeKey }
            SpikeRunner.record("command_execute_action_again", "closed=\(toggled) by_engine=\(events.closed.last.map { "\($0)" } ?? "nil")")
            if !toggled { _ = await closePopupWithEsc(events) }
        }
        await activate()
        PageDriver.click(page, at: CGPoint(x: 40, y: 40), "focus the page")
        try? await Task.sleep(for: .milliseconds(300))
        let titleBefore = section.extensions.action(for: id, in: nil)?.title ?? ""
        sendKey(window, page: page.nativeView, characters: "U", charactersIgnoringModifiers: "u", keyCode: 32, modifiers: [.command, .shift])
        let commanded = await waitUntil(8) { (section.extensions.action(for: id, in: nil)?.title ?? "").hasPrefix("command:") }
        SpikeRunner.record("command_named", "onCommand=\(commanded) title_before=\"\(titleBefore)\" "
            + "title=\"\(section.extensions.action(for: id, in: nil)?.title ?? "nil")\"")
        // Task 5: the named command's sidePanel.open() result is in that title ("sidePanel:<result>").
        SpikeRunner.record("side_panel_open", (section.extensions.action(for: id, in: nil)?.title ?? "nil")
            .components(separatedBy: "sidePanel:").last ?? "nil")
        SpikeRunner.record("popup_events", "shown=\(events.shown.count) closed=\(events.closed) resizes=\(events.resized.count)")
        ExtensionPopups.debugOnShow = nil
        ExtensionPopups.debugOnResize = nil
        ExtensionPopups.debugOnClose = nil
    }

    // MARK: webstore popups (the exit)

    /// One store extension's popup from the header, three times: the open
    /// times, a capture of the first, Esc (or the focus loss) closing it.
    func webstorePopupChecks(_ id: String, page: any WebContents) async {
        let events = installPopupHooks()
        let field = session.sidebar.addressField
        _ = await waitUntil(5) { field.extensionActionIDs.contains(id) }
        SpikeRunner.record("header_\(id)", "buttons=\(field.extensionActionIDs)")
        var times: [Double] = []
        for round in 0..<3 {
            await activate()
            reselectPage(page)
            try? await Task.sleep(for: .milliseconds(500))
            guard let ms = await openPopupFromHeader(id, events: events, timeout: 15) else { break }
            times.append(ms)
            let popup = events.popover?.popup
            try? await Task.sleep(for: .milliseconds(round == 0 ? 1500 : 500))
            if round == 0 {
                var text = "nil"
                if let popup { text = await js(popup, "document.title + ' | ' + (document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 160) : '')") }
                SpikeRunner.record("popup_\(id)", "size=\(NSStringFromSize(events.popover?.contentSize ?? .zero)) url=\(popup?.url?.absoluteString ?? "nil") text=\(text)")
                capturePopupOverWindow("popup-\(id)", popover: events.popover)
            }
            var closed = await closePopupWithEsc(events)
            if !closed {
                postClick(onPage: page)
                closed = await waitUntil(5) { events.popover == nil || !(events.popover?.isShown ?? false) }
            }
            let gone = await waitUntil(5) { popup?.state == .closed }
            SpikeRunner.record("popup_\(id)_\(round)", String(format: "open %.1f ms closed=%@ page_destroyed=%@", ms, "\(closed)", "\(gone)"))
        }
        let sorted = times.sorted()
        SpikeRunner.record("popup_open_times_\(id)", "\(times.map { String(format: "%.1f", $0) }) median=\(sorted.isEmpty ? "nil" : String(format: "%.1f", sorted[sorted.count / 2])) ms")
        ExtensionPopups.debugOnShow = nil
        ExtensionPopups.debugOnResize = nil
        ExtensionPopups.debugOnClose = nil
    }

    private func reselectPage(_ page: any WebContents) {
        if let entry = session.store.today(space: session.sidebar.activeSpaceID).first(where: { tabs.contents(for: $0.id) === page }) {
            session.sidebar.select(entry.id)
        }
    }
}
#endif
