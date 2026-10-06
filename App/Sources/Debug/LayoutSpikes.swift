#if DEBUG
import AppKit
import Card
import Chrome
import Design
import Engine
import Model
import QuartzCore
import Tabs
import UIKitCore

/// Phase 2.7a: `layoutmodes` (`scripts/layout-modes.sh`, which serves
/// `research/spikes/phase-2.7/` on 127.0.0.1:8770 and, as a second site, on
/// localhost:8770). With a pinned entry on the test site it measures the
/// hover reveal (edge-band dwell to the overlay shown, the slide's frame
/// times, the grace), checks the overlay keeps events from the page, then
/// the floating traffic-light cluster and the optional toolbar, and Peek:
/// the off-site rule for each kind of navigation the spec names, Peek open
/// to its first frame, events under the dim, Open as Tab and ⇧⌘T.
/// `-RoomSpikeOnly reveal,peek` runs only those checks; captures
/// (`-RoomSpikeCaptures27 YES`) are named `phase-2.7a-<name>-<appearance>`.
extension SpikeRunner.Context {
    static let site = "http://127.0.0.1:8770/"
    static let otherSite = "http://localhost:8770/"

    private var app27: AppDelegate? { AppDelegate.current }

    func layoutModes() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        controller.activityOverride = true
        await activate()
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        func runs(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
        guard let pinned = pinSite() else { return SpikeRunner.record("error", "no pinned entry") }
        sidebar.select(pinned)
        if let page = tabs.contents(for: pinned) { await waitLoaded(page) }
        try? await Task.sleep(for: .milliseconds(500))
        if runs("menu") { await menuCheck() }
        if runs("reveal") { await revealCheck() }
        if runs("cluster") { await clusterCheck() }
        if runs("toolbar") { await toolbarCheck() }
        if runs("peek") { await peekCheck(pinned: pinned) }
        if runs("split") { await splitCheck(pinned: pinned) }
        controller.isSidebarOpen = true
    }

    /// A pinned entry on the test site, the spike's "permanent entry".
    private func pinSite() -> UUID? {
        let store = sidebar.store.sidebar
        if let existing = store.pinned(space: sidebar.activeSpaceID).first(where: { $0.storedURL == Self.site + "site.html" }) { return existing.id }
        return (try? store.addEntry(.pinned, url: Self.site + "site.html", title: "Room Test Site", space: sidebar.activeSpaceID))?.id
    }

    /// A window capture for 2.7a (the script answers it).
    func capture27(_ name: String) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures27") else { return }
        let full = "\(UserDefaults.standard.string(forKey: "RoomSpikeCapturePrefix") ?? "phase-2.7a")-\(name)-\(appearanceSuffix)"
        SpikeRunner.record("capture", full)
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + full)
        if !(await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }) { SpikeRunner.record("capture_timeout", full) }
    }

    /// A mouse event through `NSApp` (the path real events take: monitors, hit testing, the page's view).
    /// `point` is in the root view's flipped coordinates.
    func post(_ type: NSEvent.EventType, at point: CGPoint, clickCount: Int = 0, modifiers: NSEvent.ModifierFlags = []) {
        let root = controller.rootView
        let inWindow = root.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount,
                                             pressure: type == .leftMouseDown ? 1 : 0) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    func postClick(at point: CGPoint) async {
        post(.leftMouseDown, at: point, clickCount: 1)
        post(.leftMouseUp, at: point, clickCount: 1)
        try? await Task.sleep(for: .milliseconds(150))
    }

    /// Display-link frame intervals while `running` holds (the main thread's frames).
    func frameIntervals(while running: @escaping () -> Bool, timeout: Double = 2) async -> [Double] {
        let recorder = FrameRecorder()
        let link = controller.rootView.displayLink(target: recorder, selector: #selector(FrameRecorder.tick(_:)))
        link.add(to: .main, forMode: .common)
        let start = Date()
        while running(), Date().timeIntervalSince(start) < timeout { try? await Task.sleep(for: .milliseconds(5)) }
        link.invalidate()
        return zip(recorder.stamps.dropFirst(), recorder.stamps).map { ($0 - $1) * 1000 }
    }

    // MARK: The View menu with a page focused (2.7b carry-over)

    /// Clicks into the page (Chromium's view takes the keyboard), then records the
    /// responder chain an action message walks and what `NSMenu.update()`
    /// validates for View ▸ Hide Sidebar and Keep Sidebar Open, with the
    /// sidebar docked and hidden.
    func menuCheck() async {
        let card = controller.rootView.currentLayout.card
        await postClick(at: CGPoint(x: card.midX, y: card.midY))
        try? await Task.sleep(for: .milliseconds(300))
        var chain: [String] = []
        var responder: NSResponder? = window.firstResponder
        while let current = responder, chain.count < 40 {
            chain.append(String(describing: Swift.type(of: current)))
            responder = current.nextResponder
        }
        SpikeRunner.record("menu_responder_chain", "key=\(window.isKeyWindow) main=\(window.isMainWindow) NSApp.keyWindow=\(NSApp.keyWindow.map { String(describing: Swift.type(of: $0)) } ?? "nil") window.delegate=\(window.delegate.map { String(describing: Swift.type(of: $0)) } ?? "nil") chain: \(chain.joined(separator: " → "))")
        guard let view = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return SpikeRunner.record("error", "no View menu") }
        for docked in [true, false] {
            controller.isSidebarOpen = docked
            try? await Task.sleep(for: .milliseconds(300))
            view.update()
            let items = view.items.filter { $0.keyEquivalent.lowercased() == "s" && $0.keyEquivalentModifierMask.contains(.command) }
            let states = items.map { item -> String in
                let target = item.action.flatMap { NSApp.target(forAction: $0, to: item.target, from: item) }
                return "\(item.title) [\(item.action.map(NSStringFromSelector) ?? "nil")] enabled=\(item.isEnabled) target=\(target.map { String(describing: Swift.type(of: $0)) } ?? "nil")"
            }
            SpikeRunner.record(docked ? "menu_sidebar_docked" : "menu_sidebar_hidden", states.joined(separator: "; "))
        }
        controller.isSidebarOpen = true
        // ⌘S as the page hands it on unhandled (`handleUnhandledKeyEvent` → the main menu).
        let commandS = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: "s", charactersIgnoringModifiers: "s",
                                        isARepeat: false, keyCode: 1)!
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: commandS) ?? false
        let hidden = !controller.isSidebarOpen
        _ = NSApp.mainMenu?.performKeyEquivalent(with: commandS)
        SpikeRunner.record("menu_command_s", "handled=\(handled) hid the sidebar=\(hidden) second ⌘S docked it=\(controller.isSidebarOpen)")
        controller.isSidebarOpen = true
    }

    // MARK: Hide/reveal (spec §E)

    private func revealCheck() async {
        let root = controller.rootView
        let reveal = controller.reveal!
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("hidden_card", NSStringFromRect(root.currentLayout.card))
        await capture27("hidden")
        let page = tabs.current
        if let page { _ = await js(page, "window.__clicks = 0; window.__moves = 0; window.__downs = 0") }
        // Rest in the band: the dwell, then the slide.
        var dwells: [Double] = [], slides: [String] = [], graces: [Double] = []
        var frames: [Double] = []
        for round in 0..<5 {
            post(.mouseMoved, at: CGPoint(x: 600, y: 300))
            try? await Task.sleep(for: .milliseconds(400))
            let start = ContinuousClock.now
            post(.mouseMoved, at: CGPoint(x: 1, y: 300))
            _ = await waitUntil(2) { reveal.isShown }
            dwells.append(ms(since: start))
            let intervals = await frameIntervals(while: { root.isOverlayAnimating })
            frames += intervals
            slides.append(String(format: "%d frames %.1fms", intervals.count, intervals.reduce(0, +)))
            if round == 0 { await capture27("overlay") }
            post(.mouseMoved, at: CGPoint(x: 150, y: 400))
            try? await Task.sleep(for: .milliseconds(300))
            // Away over the page: hidden after the grace.
            let away = ContinuousClock.now
            post(.mouseMoved, at: CGPoint(x: 700, y: 400))
            _ = await waitUntil(2) { !reveal.isShown }
            graces.append(ms(since: away))
            _ = await waitUntil(2) { !root.isOverlayAnimating }
        }
        SpikeRunner.record("reveal_band_to_shown", SpikeRunner.stats(dwells) + " (dwell \(Int(Timing.revealDwell * 1000)) ms)")
        SpikeRunner.record("reveal_slide", slides.joined(separator: ", "))
        SpikeRunner.record("reveal_slide_frame_intervals", SpikeRunner.stats(frames))
        SpikeRunner.record("reveal_leave_to_hidden", SpikeRunner.stats(graces) + " (grace \(Int(Timing.revealGrace * 1000)) ms)")
        // The overlay keeps events from the page under it (Phase 1.4 method, synthetic events through NSApp).
        post(.mouseMoved, at: CGPoint(x: 1, y: 300))
        _ = await waitUntil(2) { reveal.isShown && !root.isOverlayAnimating }
        if let page { _ = await js(page, "window.__clicks = 0; window.__moves = 0; window.__downs = 0") }
        let overlay = root.overlayFrame
        // Over the overlay where the card is under it (the card starts at x = 6).
        for y in stride(from: 120.0, through: 600, by: 120) {
            post(.mouseMoved, at: CGPoint(x: overlay.maxX - 20, y: y))
            await postClick(at: CGPoint(x: overlay.maxX - 20, y: y))
        }
        try? await Task.sleep(for: .milliseconds(300))
        if let page {
            SpikeRunner.record("isolation_overlay", "5 clicks + 5 moves over the overlay → page clicks=\(await js(page, "__clicks")) downs=\(await js(page, "__downs")) moves=\(await js(page, "__moves"))")
        }
        // ⌥⌘S pins it; a click in the page hides it.
        reveal.togglePin()
        post(.mouseMoved, at: CGPoint(x: 700, y: 400))
        try? await Task.sleep(for: .milliseconds(500))
        let pinnedStays = reveal.isShown
        await postClick(at: CGPoint(x: 700, y: 400))
        _ = await waitUntil(2) { !reveal.isShown }
        SpikeRunner.record("reveal_pin", "stays after leaving=\(pinnedStays) hidden by a page click=\(!reveal.isShown)")
        _ = await waitUntil(2) { !root.isOverlayAnimating }
    }
}

extension SpikeRunner.Context {
    // MARK: The floating cluster (spec §E)

    fileprivate func clusterCheck() async {
        let root = controller.rootView
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(300))
        let near = ContinuousClock.now
        post(.mouseMoved, at: CGPoint(x: 50, y: 30))
        try? await Task.sleep(for: .milliseconds(400))
        let buttons = controller.trafficLights.geometry.buttonsRect
        SpikeRunner.record("cluster", "shown=\(!root.clusterView.isHidden) pill=\(NSStringFromRect(root.clusterView.frame)) buttons=\(buttons.map(NSStringFromRect) ?? "none")")
        await capture27("cluster")
        // Away from it for 2 s: the pill and the buttons fade (the buttons keep their frames).
        post(.mouseMoved, at: CGPoint(x: 700, y: 500))
        _ = await waitUntil(4) { root.clusterView.alphaValue < 0.01 && self.window.standardWindowButton(.closeButton)?.isHidden == true }
        let fadedAfter = ms(since: near)
        let geometryKept = controller.trafficLights.geometry.buttonsRect == buttons
        await capture27("cluster-faded")
        post(.mouseMoved, at: CGPoint(x: 60, y: 60))
        _ = await waitUntil(2) { root.clusterView.alphaValue > 0.99 && self.window.standardWindowButton(.closeButton)?.isHidden == false }
        SpikeRunner.record("cluster_fade", String(format: "faded %.0f ms after the last movement near it (configured %d ms, + %d ms fade); buttons kept their frames=%@; back when near=%@",
                                                  fadedAfter, Int(Timing.clusterFade * 1000), Int(Motion.standard * 1000), "\(geometryKept)",
                                                  "\(root.clusterView.alphaValue > 0.99)"))
        // The drag regions: the pill and the top 5% of the card (the drag itself needs a person's pointer).
        let band = ClusterGeometry.contentDragBand(card: root.currentLayout.card)
        let hit = root.hitTest(root.superview?.convert(root.convert(CGPoint(x: root.clusterView.frame.midX, y: root.clusterView.frame.maxY - 3), to: nil), from: nil) ?? .zero)
        SpikeRunner.record("drag_regions", "pill hit=\(hit.map { String(describing: Swift.type(of: $0)) } ?? "nil") movable=\(hit?.mouseDownCanMoveWindow ?? false) content band=\(NSStringFromRect(band))")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("cluster_docked", "hidden=\(root.clusterView.isHidden) buttons visible=\(self.window.standardWindowButton(.closeButton)?.isHidden == false)")
    }

    // MARK: The optional toolbar (spec §E)

    fileprivate func toolbarCheck() async {
        let root = controller.rootView
        controller.showsToolbar = true
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("toolbar_docked", "frame=\(NSStringFromRect(root.toolbarView.frame)) leading=\(root.toolbarView.leadingInset)")
        await capture27("toolbar")
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("toolbar_hidden_sidebar", "leading=\(root.toolbarView.leadingInset) centre=\(root.toolbarView.contentCenterY.map { "\($0)" } ?? "nil") cluster hidden=\(root.clusterView.isHidden)")
        await capture27("toolbar-hidden-sidebar")
        controller.showsToolbar = false
        controller.isSidebarOpen = true
    }
}

extension SpikeRunner.Context {
    // MARK: Peek (spec §A.4, §I.6)

    /// The pointer over an element (Chromium reports the link as status text), then a click, as a person
    /// would: real mouse events on the page's view (`PageDriver`).
    fileprivate func hoverAndClick(_ page: any WebContents, _ selector: String, modifiers: NSEvent.ModifierFlags = []) async {
        guard let point = await PageDriver.center(of: selector, in: page, "hover \(selector)") else { return }
        PageDriver.hover(page, at: point, "hover \(selector)")
        try? await Task.sleep(for: .milliseconds(150))
        PageDriver.click(page, at: point, modifiers: modifiers, "click \(selector)")
    }

    /// Spec §I.6 (4.2): Open as Tab from a Peek over a Today tab (⇧-click peeks from any page) puts the new
    /// tab directly under that tab. The Today parent is a new tab of the fixture's site, closed afterwards.
    fileprivate func peekPlacementUnderToday() async {
        let home = URL(string: Self.site + "site.html")!
        let store = sidebar.store.sidebar
        let space = sidebar.activeSpaceID
        guard let parentID = tabs.openNewTab(url: home.absoluteString, transition: .link) else {
            return SpikeRunner.record("peek_open_as_tab_today_parent", "no parent tab")
        }
        // Two more Today tabs under it so "directly under" is not "at the end".
        let below = [tabs.openBackgroundTab(url: home.absoluteString + "?below=1"), tabs.openBackgroundTab(url: home.absoluteString + "?below=2")]
        for id in below.compactMap({ $0 }) { try? store.move(id, to: .today(space: space), at: (store.today(space: space).firstIndex { $0.id == parentID } ?? 0) + 1) }
        sidebar.select(parentID)
        guard let parent = tabs.contents(for: parentID) else { return SpikeRunner.record("peek_open_as_tab_today_parent", "no parent page") }
        await waitLoaded(parent)
        try? await Task.sleep(for: .milliseconds(300))
        await hoverAndClick(parent, "#offsite", modifiers: .shift)
        _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
        guard tabs.shownPeek != nil else { return SpikeRunner.record("peek_open_as_tab_today_parent", "⇧-click opened no Peek") }
        tabs.expandShownPeek()
        try? await Task.sleep(for: .milliseconds(400))
        let today = store.today(space: space).map(\.id)
        let parentIndex = today.firstIndex(of: parentID), newIndex = tabs.currentEntryID.flatMap { today.firstIndex(of: $0) }
        SpikeRunner.record("peek_open_as_tab_today_parent", "parent index=\(parentIndex.map(String.init) ?? "none") new tab index=\(newIndex.map(String.init) ?? "none") "
            + "directly under=\(parentIndex != nil && newIndex == parentIndex.map { $0 + 1 }) today=\(today.count)")
        for id in ([parentID] + below.compactMap { $0 } + [tabs.currentEntryID].compactMap { $0 }) { sidebar.close(id) }
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// B-35 (4.2): a fullscreen request from the Peek's page (`requestFullscreen()` with a gesture) expands
    /// the Peek into a Today tab under the pinned entry, then the page takes the window as the card's page.
    fileprivate func peekFullscreen(pinned: UUID, page: any WebContents, reset: () async -> Void) async {
        guard let app = app27 else { return }
        if sidebar.selectedEntryID != pinned { sidebar.select(pinned) }
        await reset()
        await hoverAndClick(page, "#offsite")
        _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
        try? await Task.sleep(for: .milliseconds(400))
        guard let peeked = tabs.shownPeek else { return SpikeRunner.record("peek_fullscreen", "Peek did not open") }
        let before = sidebar.store.sidebar.today(space: sidebar.activeSpaceID).count
        let asked = await PageDriver.evaluateWithGesture(peeked, "document.documentElement.requestFullscreen().then(() => 'ok', e => 'refused: ' + e.message)",
                                                         "fullscreen from Peek")
        let entered = await waitUntil(6) { self.window.styleMask.contains(.fullScreen) && app.pageDelegate?.fullscreen?.isActive == true }
        try? await Task.sleep(for: .milliseconds(800))
        let element = await js(peeked, "String(document.fullscreenElement !== null)")
        let today = sidebar.store.sidebar.today(space: sidebar.activeSpaceID)
        let index = today.firstIndex { $0.id == tabs.currentEntryID }
        SpikeRunner.record("peek_fullscreen", "request=\(asked ?? "nil") Peek gone=\(tabs.shownPeek == nil) today \(before) → \(today.count) "
            + "card page is the Peek's=\(tabs.current === peeked) index in Today=\(index.map(String.init) ?? "none") "
            + "window fullscreen=\(window.styleMask.contains(.fullScreen)) page fullscreen=\(app.pageDelegate?.fullscreen?.isActive == true) "
            + "document.fullscreenElement=\(element) entered=\(entered)")
        _ = await js(peeked, "document.exitFullscreen().then(() => 'ok', e => e.message)")
        let left = await waitUntil(8) { !self.window.styleMask.contains(.fullScreen) && app.pageDelegate?.fullscreen?.isActive != true }
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("peek_fullscreen_exit", "window back=\(left) the tab stays=\(tabs.current === peeked)")
        if let id = tabs.currentEntryID, id != pinned { sidebar.close(id) }
        sidebar.select(pinned)
        try? await Task.sleep(for: .milliseconds(400))
    }

    fileprivate func peekCheck(pinned: UUID) async {
        guard let app = app27, let peek = app.peek, let page = tabs.contents(for: pinned) else {
            return SpikeRunner.record("error", "no pinned page for Peek")
        }
        controller.isSidebarOpen = true
        // The reveal check's clicks over the overlay land on rows when the sidebar has any (a fixture, the
        // grand tour's shared state) and can select another entry: Peek's checks start on the pinned page.
        SpikeRunner.record("peek_start", "selected is the pinned entry=\(sidebar.selectedEntryID == pinned)")
        if sidebar.selectedEntryID != pinned {
            sidebar.select(pinned)
            await waitLoaded(page)
        }
        var decisions: [String] = []
        var decidedAt: (uptime: TimeInterval, epoch: Double)?
        tabs.debugPeekDecisions = { action, decision in
            decisions.append("\(action.url.host() ?? "")\(action.url.path)\(action.url.query.map { "?" + $0 } ?? "") \(decision == .peek ? "peek" : "in place")"
                + " [kind=\(action.kind) transition=\(action.transition) disposition=\(action.disposition) gesture=\(action.isUserGesture)"
                + " redirect=\(action.isRedirect) client=\(action.isClientRedirect)]")
            if decision == .peek { decidedAt = (ProcessInfo.processInfo.systemUptime, Date().timeIntervalSince1970 * 1000) }
        }
        var presentedAt: TimeInterval?
        peek.onPresented = { presentedAt = ProcessInfo.processInfo.systemUptime }
        let home = URL(string: Self.site + "site.html")!
        func reset() async {
            if tabs.shownPeek != nil { tabs.closeShownPeek() }
            if page.url != home {
                page.load(home, transition: .bookmark, fromAddressBar: false)
                await waitLoaded(page)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        /// Clicks, then says where the navigation went.
        func outcome(_ selector: String, modifiers: NSEvent.ModifierFlags = [], gestureAgo: TimeInterval? = nil) async -> String {
            await reset()
            tabs.lastUserInput = gestureAgo.map { ProcessInfo.processInfo.systemUptime - $0 }
            await hoverAndClick(page, selector, modifiers: modifiers)
            _ = await waitUntil(4) { self.tabs.shownPeek != nil || (page.url != home && !page.isLoading) }
            try? await Task.sleep(for: .milliseconds(400))
            if let peeked = tabs.shownPeek { return "peek \(peeked.url?.absoluteString ?? "loading") (pinned page stays at \(page.url?.lastPathComponent ?? ""))" }
            return "in place → \(page.url?.absoluteString ?? "nil")"
        }
        SpikeRunner.record("peek_onsite", await outcome("#onsite"))
        SpikeRunner.record("peek_offsite", await outcome("#offsite"))
        // Open timing: the decision → the overlay's first committed frame, → the page's first contentful paint.
        var overlayTimes: [Double] = [], paintTimes: [Double] = []
        for _ in 0..<5 {
            await reset()
            decidedAt = nil
            presentedAt = nil
            await hoverAndClick(page, "#offsite")
            _ = await waitUntil(4) { presentedAt != nil && self.tabs.shownPeek?.isLoading == false }
            try? await Task.sleep(for: .milliseconds(300))
            if let decidedAt, let presentedAt { overlayTimes.append((presentedAt - decidedAt.uptime) * 1000) }
            if let decidedAt, let peeked = tabs.shownPeek {
                let fcp = await js(peeked, "(() => { const p = performance.getEntriesByName('first-contentful-paint')[0]; return p ? performance.timeOrigin + p.startTime : -1 })()")
                if let value = Double(fcp), value > 0 { paintTimes.append(value - decidedAt.epoch) }
            }
        }
        SpikeRunner.record("peek_open_to_overlay_frame", SpikeRunner.stats(overlayTimes))
        SpikeRunner.record("peek_open_to_first_contentful_paint", SpikeRunner.stats(paintTimes))
        // The open animation starts at the click: the card's presentation frame right after a posted click.
        await reset()
        await capture27("peek-before")
        let root = controller.rootView
        // Events under the dim (Phase 1.4 method, through NSApp): moves and a scroll over the dim
        // reach neither page; a click inside the card reaches the Peek page; a click on the dim closes it.
        await hoverAndClick(page, "#offsite")
        _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
        try? await Task.sleep(for: .milliseconds(600))
        await capture27("peek")
        guard let peeked = tabs.shownPeek else {
            // What the navigations were decided as, and where Peek stood, for the run that failed.
            SpikeRunner.record("peek_decisions", decisions.joined(separator: " | "))
            SpikeRunner.record("peek_state", "shown=\(tabs.shownPeek != nil) page=\(page.url?.absoluteString ?? "nil") loading=\(page.isLoading) "
                + "linksInPeek=\(sidebar.store.settings.settings.peekOffSiteLinks) lastUserInput=\(tabs.lastUserInput.map { String(format: "%.1f s ago", ProcessInfo.processInfo.systemUptime - $0) } ?? "nil")")
            return SpikeRunner.record("error", "Peek did not open")
        }
        _ = await js(page, "window.__clicks = 0; window.__moves = 0; window.__downs = 0")
        _ = await js(peeked, "window.__clicks = 0")
        let overlayFrame = peek.overlay.frame
        let cardFrame = peek.overlay.card.frame.offsetBy(dx: overlayFrame.minX, dy: overlayFrame.minY)
        let dimPoints = [CGPoint(x: overlayFrame.minX + 20, y: overlayFrame.midY), CGPoint(x: overlayFrame.midX, y: overlayFrame.maxY - 15),
                         CGPoint(x: overlayFrame.maxX - 20, y: overlayFrame.minY + 30)]
        for point in dimPoints { post(.mouseMoved, at: point) }
        try? await Task.sleep(for: .milliseconds(300))
        let inCard = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        post(.mouseMoved, at: inCard)
        await postClick(at: inCard)
        try? await Task.sleep(for: .milliseconds(300))
        let peekClicks = await js(peeked, "__clicks")
        let stillOpen = tabs.shownPeek != nil
        await postClick(at: dimPoints[0])
        _ = await waitUntil(2) { self.tabs.shownPeek == nil }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("isolation_peek", "3 moves over the dim, a click in the card, a click on the dim → page under: clicks=\(await js(page, "__clicks")) downs=\(await js(page, "__downs")) moves=\(await js(page, "__moves")); Peek page clicks=\(peekClicks) open after the card click=\(stillOpen); closed by the dim click=\(tabs.shownPeek == nil)")
        // Where the open animation starts: the card's presentation frame just after the click that opened it.
        await reset()
        let linkPoint = await js(page, "(() => { const r = document.querySelector('#offsite2').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()")
        if let point = try? JSONSerialization.jsonObject(with: Data(linkPoint.utf8)) as? [Double], point.count == 2 {
            let card = root.currentLayout.card
            let clickPoint = CGPoint(x: card.minX + point[0], y: card.minY + point[1])
            post(.mouseMoved, at: clickPoint)
            try? await Task.sleep(for: .milliseconds(200))
            await postClick(at: clickPoint)
            _ = await waitUntil(3) { self.tabs.shownPeek != nil }
            let presentation = peek.overlay.card.layer?.presentation()?.frame ?? .zero
            let start = peek.overlay.convert(presentation, to: root)
            SpikeRunner.record("peek_open_origin", String(format: "click (%.0f, %.0f) in the window; the card's first presented frame centred at (%.0f, %.0f), %.0f × %.0f",
                                                           clickPoint.x, clickPoint.y, start.midX, start.midY, start.width, start.height))
            _ = await waitUntil(3) { self.tabs.shownPeek?.isLoading == false }
            try? await Task.sleep(for: .milliseconds(500))
        }
        // ⌘O: Open as Tab, a Today tab right under the pinned entry, the same page.
        if let peeked = tabs.shownPeek {
            let before = sidebar.store.sidebar.today(space: sidebar.activeSpaceID).count
            tabs.expandShownPeek()
            try? await Task.sleep(for: .milliseconds(400))
            let today = sidebar.store.sidebar.today(space: sidebar.activeSpaceID)
            SpikeRunner.record("peek_open_as_tab", "today \(before) → \(today.count); selected is the Peek's page=\(tabs.current === peeked) url=\(tabs.current?.url?.absoluteString ?? "nil") Peek gone=\(tabs.shownPeek == nil)")
            // Spec §I.6 (4.2): "under the parent": a pinned parent's tab is the first of Today (§A.7's related-tab rule).
            let index = today.firstIndex { $0.id == tabs.currentEntryID }
            SpikeRunner.record("peek_open_as_tab_placement", "parent=pinned index in Today=\(index.map(String.init) ?? "none") under the parent=\(index == 0)")
            sidebar.select(pinned)
            try? await Task.sleep(for: .milliseconds(400))
        }
        await peekPlacementUnderToday()
        await peekFullscreen(pinned: pinned, page: page, reset: reset)
        // Esc closes it (the page did not use the key); ⇧⌘T brings it back.
        await reset()
        await hoverAndClick(page, "#offsite")
        _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
        try? await Task.sleep(for: .milliseconds(400))
        let url = tabs.shownPeek?.url?.absoluteString
        pressEscape()
        _ = await waitUntil(2) { self.tabs.shownPeek == nil }
        let closedByEscape = tabs.shownPeek == nil
        sidebar.reopenClosedTab()
        _ = await waitUntil(4) { self.tabs.shownPeek != nil }
        SpikeRunner.record("peek_escape_and_reopen", "Esc closed=\(closedByEscape); ⇧⌘T reopened=\(tabs.shownPeek?.url?.absoluteString ?? "nil") (was \(url ?? "nil")) over the pinned entry=\(tabs.currentEntryID == pinned)")
        tabs.closeShownPeek()
        // The exemptions (spec §A.4) and ⇧-click.
        SpikeRunner.record("peek_redirect_chain", await outcome("#chain"))
        SpikeRunner.record("peek_oauth", await outcome("#oauth"))
        SpikeRunner.record("peek_form_post", await outcome("#post"))
        SpikeRunner.record("peek_script_within_2s", await outcome("#script", gestureAgo: 0.2))
        SpikeRunner.record("peek_script_after_2s", await outcome("#script", gestureAgo: 3))
        SpikeRunner.record("peek_shift_click", await outcome("#offsite2", modifiers: .shift))
        SpikeRunner.record("peek_target_blank", await outcome("#blank") + " selected=\(tabs.current?.url?.absoluteString ?? "nil")")
        sidebar.select(pinned)
        await reset()
        SpikeRunner.record("peek_decisions", decisions.joined(separator: " | "))
        tabs.debugPeekDecisions = nil
        // The engine's same-site key (B-34): an IDN public suffix (東京.jp) the bundled list skipped.
        if let engine = tabs.engine {
            let hosts = ["shop.example.xn--1lqs71d.jp", "a.b.example.co.uk", "room.github.io", "127.0.0.1"]
            SpikeRunner.record("site_engine", hosts.map { "\($0) → \(engine.site(of: URL(string: "https://\($0)/")!) ?? "nil")" }.joined(separator: ", "))
            SpikeRunner.record("site_bundled_list", hosts.map { "\($0) → \(PublicSuffixList.site(ofHost: $0))" }.joined(separator: ", "))
        }
    }
}

/// Collects display-link timestamps.
final class FrameRecorder: NSObject {
    var stamps: [CFTimeInterval] = []
    @objc func tick(_ link: CADisplayLink) { stamps.append(link.timestamp) }
}
#endif
