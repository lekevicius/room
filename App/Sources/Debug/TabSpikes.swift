#if DEBUG
import AppKit
import Design
import Engine
import Model
import Sidebar
import Store
import Tabs
#if canImport(EngineCEF)
import EngineCEF
#endif

/// Phase 2.3 spikes on the live engine (`Room -RoomSpike <name>`):
/// - `tabs`: ⌘W / ⇧⌘T / MRU / related tabs / discard / ⌃Tab / ⌘1 / mute on
///   CEF, through real key events where the page has focus.
/// - `switch` (with `-RoomSidebarFixture 50`): loads the fixture's ten site
///   tabs, records summed RSS, then times 100 selection switches.
/// - `relaunch`: on a state directory a `switch` run left behind, records
///   how many pages load at launch and how long the selected one takes.
/// - `capture` (with `-RoomSidebarFixture demo -RoomSpikeCaptureDirectory
///   <dir>`): the card with a real page and the empty state, light and
///   dark, rendered in-process from the layer tree with the page composited
///   from a CDP screenshot (Chromium's layer is in another process, B-9).
extension SpikeRunner.Context {
    var tabs: TabController { session.tabs }
    var sidebar: SidebarController { session.sidebar }
    var store: SidebarStore { session.store }

    // MARK: Behaviour on CEF

    func tabsChecks() async {
        let space = sidebar.activeSpaceID
        func label(_ id: UUID?, _ names: [UUID: String]) -> String { id.flatMap { names[$0] } ?? id.map { "\($0)" } ?? "none" }

        // A, B, C used in that order, then A again, then C: the MRU entry before C is A, its neighbour is B.
        var ids: [UUID] = []
        for url in ["https://en.wikipedia.org/wiki/Web_browser", "https://example.com/", "https://news.ycombinator.com/"] {
            guard let entry = try? store.addEntry(.today, url: url, space: space) else { return }
            ids.append(entry.id)
            sidebar.select(entry.id)
            if let page = tabs.contents(for: entry.id) { await waitLoaded(page) }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let (a, b, c) = (ids[0], ids[1], ids[2])
        let names = [a: "A", b: "B", c: "C"]
        sidebar.select(a)
        try? await Task.sleep(for: .milliseconds(300))
        sidebar.select(c)
        try? await Task.sleep(for: .milliseconds(300))

        // ⌘W as a key event to the focused page: reserved, so it reaches the menu, never the page.
        guard let pageC = tabs.contents(for: c) else { return }
        focusPage(pageC)
        sendKey("w", keyCode: 13, [.command])
        _ = await waitUntil(5) { pageC.state == .closed }
        SpikeRunner.record("cmdW_today", "page=\(pageC.state) entryRemoved=\(store.entry(c) == nil) selected=\(label(sidebar.selectedEntryID, names)) "
            + "inCard=\(session.host.contents === tabs.contents(for: a)) helpers=\(ProcessMemory.snapshot().renderers) renderers")

        // ⇧⌘T as a key event.
        if let page = tabs.contents(for: a) { focusPage(page) }
        sendKey("T", keyCode: 17, [.command, .shift])
        _ = await waitUntil(5) { self.store.entry(c) != nil }
        if let page = tabs.contents(for: c) { await waitLoaded(page) }
        SpikeRunner.record("reopen_today", "index=\(store.today(space: space).firstIndex { $0.id == c }.map(String.init) ?? "none") of 3 "
            + "selected=\(label(sidebar.selectedEntryID, names)) url=\(tabs.contents(for: c)?.url?.absoluteString ?? "nil")")

        // ⌃Tab tapped: back to the previous tab without the list.
        sendKey("\t", keyCode: 48, [.control])
        sendFlags([])
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("ctrl_tab_tap", "selected=\(label(sidebar.selectedEntryID, names)) (was C)")

        // ⌘1 and ⇧⌘] through the menu (AppKit has focus after these selections).
        window.makeFirstResponder(nil)
        sendKey("1", keyCode: 18, [.command])
        let afterDigit = sidebar.selectedEntryID
        sendKey("}", keyCode: 30, [.command, .shift])
        SpikeRunner.record("digit_and_next", "⌘1=\(label(afterDigit, names)) then ⇧⌘]=\(label(sidebar.selectedEntryID, names)) "
            + "order=\(store.sidebarOrder(space: space).map { label($0.id, names) })")

        // A pinned entry: a same-site navigation marks it changed; ⌘W unloads and resets it; ⇧⌘T brings the page back.
        guard let pinned = try? store.addEntry(.pinned, url: "https://example.org/", title: "Example", space: space) else { return }
        sidebar.select(pinned.id)
        guard let pageP = tabs.contents(for: pinned.id) else { return }
        await waitLoaded(pageP)
        _ = await js(pageP, "location.href = '/?changed=1'; 0")
        _ = await waitUntil(10) { self.store.entry(pinned.id)?.liveURL?.contains("changed") == true }
        await waitLoaded(pageP)
        SpikeRunner.record("pinned_changed", "isChanged=\(store.isChanged(pinned.id)) live=\(store.entry(pinned.id)?.liveURL ?? "nil")")
        focusPage(pageP)
        sendKey("w", keyCode: 13, [.command])
        _ = await waitUntil(5) { pageP.state == .closed }
        let afterClose = store.entry(pinned.id)
        SpikeRunner.record("cmdW_pinned", "page=\(pageP.state) entryStays=\(afterClose != nil) live=\(afterClose?.liveURL ?? "nil") "
            + "reset=\(afterClose?.liveURL == afterClose?.storedURL) selected=\(label(sidebar.selectedEntryID, names))")
        sidebar.reopenClosedTab()
        if let page = tabs.contents(for: pinned.id) { await waitLoaded(page) }
        SpikeRunner.record("reopen_pinned", "selected=\(sidebar.selectedEntryID == pinned.id) url=\(tabs.contents(for: pinned.id)?.url?.absoluteString ?? "nil")")

        // Related tabs (§A.7): target=_blank opens below the opener, selected; ⌘-clicks open in the background, in order.
        guard let opener = try? store.addEntry(.today, url: SpikeRunner.page("popups.html").absoluteString, space: space, at: 0) else { return }
        sidebar.select(opener.id)
        guard let openerPage = tabs.contents(for: opener.id) else { SpikeRunner.record("error", "no page for openerPage"); return }
        await waitLoaded(openerPage)
        try? await Task.sleep(for: .milliseconds(500))
        let countBefore = store.today(space: space).count
        await click(openerPage, "#blank")
        _ = await waitUntil(5) { self.store.today(space: space).count > countBefore }
        let todayAfter = store.today(space: space)
        let foregroundTab = sidebar.selectedEntryID
        SpikeRunner.record("related_foreground", "newIndex=\(todayAfter.firstIndex { $0.id == sidebar.selectedEntryID }.map(String.init) ?? "none") "
            + "openerIndex=\(todayAfter.firstIndex { $0.id == opener.id } ?? -1) selectedIsNew=\(sidebar.selectedEntryID != opener.id)")
        sidebar.select(opener.id)
        try? await Task.sleep(for: .milliseconds(500))
        for _ in 0..<2 {
            let before = store.today(space: space).count
            await click(openerPage, "#blank", modifiers: .command)
            _ = await waitUntil(5) { self.store.today(space: space).count > before }
        }
        let order = store.today(space: space).map(\.id)
        let newIDs = Set(order).subtracting(todayAfter.map(\.id))
        SpikeRunner.record("related_background", "selectedStaysOpener=\(sidebar.selectedEntryID == opener.id) "
            + "openerIndex=\(order.firstIndex(of: opener.id) ?? -1) backgroundIndexes=\(newIDs.compactMap { order.firstIndex(of: $0) }.sorted()) "
            + "earlierForegroundIndex=\(foregroundTab.flatMap { order.firstIndex(of: $0) } ?? -1)")

        // A has a back/forward list to keep (B-13): one link further, in the background.
        if let pageA = tabs.contents(for: a) {
            // Through the engine (a script navigation without a gesture is skipped by back, Chromium's history intervention).
            pageA.load(URL(string: "https://en.wikipedia.org/wiki/Chromium_(web_browser)")!, transition: .link, fromAddressBar: false)
            _ = await waitUntil(10) { pageA.url?.path.contains("Chromium") == true }
            await waitLoaded(pageA)
            SpikeRunner.record("discard_history_before", "url=\(pageA.url?.absoluteString ?? "nil") canGoBack=\(pageA.canGoBack)")
        }

        // Discard every background page; reselecting one reloads it.
        try? await Task.sleep(for: .seconds(2))
        let memoryBefore = ProcessMemory.snapshot()
        let discarded = tabs.discardBackgroundPages()
        try? await Task.sleep(for: .seconds(4))
        let memoryAfter = ProcessMemory.snapshot()
        try? await Task.sleep(for: .seconds(6))
        SpikeRunner.record("discard_renderers_after_10s", ProcessMemory.snapshot().summary)
        SpikeRunner.record("discard", "pages=\(discarded.count) renderers \(memoryBefore.renderers)→\(memoryAfter.renderers) "
            + String(format: "total %.0f→%.0f MB", memoryBefore.totalMB, memoryAfter.totalMB)
            + " states=\(discarded.compactMap { tabs.contents(for: $0)?.state }.map { "\($0)" })"
            + " rowsDimmed=\(discarded.filter { !tabs.pageState(for: $0).isLoaded }.count)")
        sidebar.select(a)
        if let page = tabs.contents(for: a) { await waitLoaded(page) }
        let pageA = tabs.contents(for: a)
        SpikeRunner.record("discarded_reselect", "state=\(pageA.map { "\($0.state)" } ?? "nil") url=\(pageA?.url?.absoluteString ?? "nil") "
            + "canGoBack=\(pageA?.canGoBack ?? false) title=\(pageA?.title ?? "nil")")
        // Back from the revived page reaches the page before the discard (its history survived).
        if let pageA, pageA.canGoBack {
            pageA.goBack()
            _ = await waitUntil(10) { pageA.url?.path.contains("Web_browser") == true }
            await waitLoaded(pageA)
            SpikeRunner.record("discarded_back", "url=\(pageA.url?.absoluteString ?? "nil") canGoForward=\(pageA.canGoForward)")
            pageA.goForward()
            await waitLoaded(pageA)
        }

        // Favicons: the page's live one (the row), the store's cache, and the engine's own store (`Profile.favicon(for:)`).
        if let pageA, let url = pageA.url {
            func size(_ image: NSImage?) -> String { image.map { "\(Int($0.size.width))×\(Int($0.size.height)) pt, \($0.representations.count) reps" } ?? "nil" }
            let engineIcon = await tabs.engineProfile(for: pageA)?.favicon(for: url)
            SpikeRunner.record("favicons", "\(url.host() ?? "") live=\(size(pageA.favicon)) cached=\(size(tabs.favicon(forURL: url.absoluteString))) engine=\(size(engineIcon))")
        }

        // Mute (⇧⌘M through the menu).
        window.makeFirstResponder(nil)
        sendKey("M", keyCode: 46, [.command, .shift])
        SpikeRunner.record("mute", "selectedMuted=\(pageA?.isMuted ?? false)")
        sendKey("M", keyCode: 46, [.command, .shift])
    }

    // MARK: Switching and memory (ROADMAP 2.3 exit)

    func switching() async {
        let space = sidebar.activeSpaceID
        let sites = store.today(space: space).filter { entry in Self.typicalSites.contains { $0 == entry.currentURL } }
        SpikeRunner.record("entries", store.entries.values.filter { $0.kind != .folder }.count)
        SpikeRunner.record("site_tabs", sites.count)
        let loadStart = Date()
        for entry in sites {
            sidebar.select(entry.id)
            if let page = tabs.contents(for: entry.id) { await waitLoaded(page, timeout: 45) }
        }
        SpikeRunner.record("load_s", Int(Date().timeIntervalSince(loadStart)))
        try? await Task.sleep(for: .seconds(10))
        SpikeRunner.record("loaded_pages", tabs.loadedEntryIDs.count)
        SpikeRunner.record("rss_10_loaded", ProcessMemory.snapshot().summary)
        for entry in sites {
            if let page = tabs.contents(for: entry.id) { _ = await js(page, Self.visibilityProbe) }
        }
        var sync: [Double] = [], beforeDisplay: [Double] = [], turn: [Double] = [], visible: [Double] = [], frame: [Double] = []
        var previous = sidebar.selectedEntryID
        for _ in 0..<100 {
            var target = sites.randomElement()!
            while target.id == previous { target = sites.randomElement()! }
            let epoch = Date().timeIntervalSince1970 * 1000
            let timing = await timedSelect(target.id)
            sync.append(timing.sync)
            beforeDisplay.append(timing.beforeDisplay)
            turn.append(timing.turn)
            try? await Task.sleep(for: .milliseconds(400))
            if let page = tabs.contents(for: target.id),
               // `__roomVis` is already a JSON string; the engine returns it JSON-encoded once more.
               let values = try? JSONSerialization.jsonObject(with: Data(await js(page, "window.__roomVis").utf8),
                                                              options: .fragmentsAllowed) as? String,
               let pair = try? JSONSerialization.jsonObject(with: Data(values.utf8)) as? [Double], pair.count == 2 {
                visible.append(pair[0] - epoch)
                frame.append(pair[1] - epoch)
                _ = await js(page, "window.__roomVis = null; 0")
            }
            previous = target.id
        }
        SpikeRunner.record("switch_select_call", SpikeRunner.stats(sync))
        SpikeRunner.record("switch_turn_before_display", SpikeRunner.stats(beforeDisplay))
        SpikeRunner.record("switch_main_thread_turn", SpikeRunner.stats(turn))
        SpikeRunner.record("switch_page_visible", SpikeRunner.stats(visible))
        SpikeRunner.record("switch_page_first_frame", SpikeRunner.stats(frame))
        SpikeRunner.record("rss_after_switching", ProcessMemory.snapshot().summary)
        SpikeRunner.record("selected_at_quit", store.entry(sidebar.selectedEntryID ?? UUID())?.currentURL ?? "none")
    }

    /// Main-thread time of one selection: the `select` call itself; the
    /// turn up to its before-waiting observers (whatever else ran in it);
    /// and the whole turn, including layout, display and the Core Animation
    /// commit, which run in those observers (ours is last).
    func timedSelect(_ id: UUID) async -> (sync: Double, beforeDisplay: Double, turn: Double) {
        await timedTurn { sidebar.select(id) }
    }

    /// Main-thread time of `body` and the run-loop turn it runs in (see `timedSelect`).
    func timedTurn(_ body: () -> Void) async -> (sync: Double, beforeDisplay: Double, turn: Double) {
        let start = ContinuousClock.now
        return await withCheckedContinuation { continuation in
            var sync = 0.0, beforeDisplay = 0.0
            var done = false
            var first: CFRunLoopObserver?, last: CFRunLoopObserver?
            first = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.min) { _, _ in
                if beforeDisplay == 0 { beforeDisplay = self.ms(since: start) }
            }
            last = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
                guard !done else { return }
                done = true
                for observer in [first, last].compactMap({ $0 }) { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
                continuation.resume(returning: (sync, beforeDisplay, self.ms(since: start)))
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), first, .commonModes)
            CFRunLoopAddObserver(CFRunLoopGetMain(), last, .commonModes)
            body()
            sync = ms(since: start)
        }
    }

    /// Records when the page becomes visible and its next animation frame (epoch ms).
    static let visibilityProbe = """
    (() => {
      if (!window.__roomVisInstalled) {
        window.__roomVisInstalled = true;
        document.addEventListener('visibilitychange', () => {
          if (document.visibilityState !== 'visible') return;
          const v = performance.timeOrigin + performance.now();
          requestAnimationFrame(() => { window.__roomVis = JSON.stringify([v, performance.timeOrigin + performance.now()]); });
        });
      }
      window.__roomVis = null;
      return document.visibilityState;
    })()
    """

    // MARK: Relaunch

    func relaunch() async {
        let launched = Self.processStartDate()
        SpikeRunner.record("entries", store.entries.values.filter { $0.kind != .folder }.count)
        guard let id = sidebar.selectedEntryID else { return SpikeRunner.record("error", "nothing selected") }
        _ = await waitUntil(30) { self.tabs.contents(for: id) != nil }
        if let page = tabs.contents(for: id) {
            // Loading has to start before it can finish (CEF reports it a moment after `load`).
            let started = await waitUntil(10) { page.isLoading }
            SpikeRunner.record("launch_to_load_start_s", started ? String(format: "%.2f", Date().timeIntervalSince(launched)) : "not seen")
            _ = await waitUntil(45) { !page.isLoading }
        }
        SpikeRunner.record("launch_to_selected_loaded_s", String(format: "%.2f", Date().timeIntervalSince(launched)))
        SpikeRunner.record("selected", store.entry(id)?.currentURL ?? "nil")
        try? await Task.sleep(for: .seconds(5))
        SpikeRunner.record("loaded_pages", tabs.loadedEntryIDs.count)
        SpikeRunner.record("rss_relaunch", ProcessMemory.snapshot().summary)
        let restored = store.entries.values.filter { $0.kind != .folder && tabs.contents(for: $0.id) == nil }
        SpikeRunner.record("unloaded_rows", "\(restored.count), with a cached favicon: \(restored.filter { tabs.pageState(for: $0.id).favicon != nil }.count), "
            + "with a live title: \(restored.filter { $0.liveTitle != nil }.count)")
    }

    static func processStartDate() -> Date {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&mib, 4, &info, &size, nil, 0)
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }

    // MARK: Captures

    /// 3.3a: the page's colours from the engine (theme colour, root
    /// background) and the card's fill following the root background (2.3's
    /// rule), on the 2.3 capture page (Wikipedia) and a dark page; a window
    /// capture of the dark one for the reviewer (the runner answers
    /// `capture:` lines, as the 2.6/2.7 wrappers do).
    func colors() async {
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        let dark = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.3/dark.html")
        for (name, url) in [("wikipedia", URL(string: "https://en.wikipedia.org/wiki/Web_browser")!), ("dark", dark)] {
            guard let page = await open(url) else { continue }
            await waitLoaded(page)
            _ = await waitUntil(5) { page.rootBackgroundColor != nil && (name != "dark" || page.themeColor != nil) }
            try? await Task.sleep(for: .milliseconds(500))
            func hex(_ color: NSColor?) -> String {
                guard let c = color?.usingColorSpace(.sRGB) else { return "nil" }
                return String(format: "#%02x%02x%02x", Int(c.redComponent * 255 + 0.5), Int(c.greenComponent * 255 + 0.5), Int(c.blueComponent * 255 + 0.5))
            }
            SpikeRunner.record("colors_\(name)", "themeColor=\(hex(page.themeColor)) rootBackgroundColor=\(hex(page.rootBackgroundColor)) "
                + "card=\(hex(controller.cardView.backgroundColor)) favicon=\(page.favicon.map { "\(Int($0.size.width))pt" } ?? "nil")")
            if name == "dark" {
                SpikeRunner.record("window_id", window.windowNumber)
                let capture = "phase-3.3a-card-dark-page"
                SpikeRunner.record("capture", capture)
                let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
                let ack = URL(fileURLWithPath: output.path + ".ack-\(capture)")
                if !(await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }) { SpikeRunner.record("capture_timeout", capture) }
            }
        }
    }

    func captures() async {
        let directory = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") ?? NSTemporaryDirectory(),
                            isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let suffix = dark ? "dark" : "light"
            if let id = store.today(space: sidebar.activeSpaceID).first(where: { $0.currentURL?.contains("wikipedia") == true })?.id ?? sidebar.selectedEntryID {
                sidebar.select(id)
            }
            if let page = tabs.current {
                await waitLoaded(page, timeout: 30)
                try? await Task.sleep(for: .seconds(3))
                var pageImage: NSImage?
                pageImage = await PageDriver.capture(page, "page capture")
                SpikeRunner.record("capture_page_\(suffix)", writeComposite(page: pageImage, pageView: page.nativeView,
                                                                           to: directory.appending(path: "phase-2.3-card-page-\(suffix).png")))
            }
            if !dark {
                // The ⌃Tab switcher, held: a few entries used first so the list has five.
                for entry in store.sidebarOrder(space: sidebar.activeSpaceID).prefix(4) {
                    sidebar.select(entry.id)
                    try? await Task.sleep(for: .milliseconds(150))
                }
                sendKey("\t", keyCode: 48, [.control])
                try? await Task.sleep(for: .milliseconds(500))
                let switcher = AppDelegate.current?.switcher
                SpikeRunner.record("switcher_state", "active=\(switcher?.isActive ?? false) panel=\(switcher?.debugPanelFrame.map(NSStringFromRect) ?? "none")")
                SpikeRunner.record("capture_switcher", writeComposite(page: nil, pageView: nil, overlay: switcher?.debugPanel,
                                                                      to: directory.appending(path: "phase-2.3-tab-switcher-light.png")))
                sendFlags([])
                try? await Task.sleep(for: .milliseconds(300))
            }
            sidebar.select(nil)
            try? await Task.sleep(for: .seconds(1))
            SpikeRunner.record("capture_empty_\(suffix)", writeComposite(page: nil, pageView: nil,
                                                                        to: directory.appending(path: "phase-2.3-card-empty-\(suffix).png")))
        }
    }

    /// The window, rendered in-process from its layer tree (window-server
    /// captures come back blank while the session is locked), with `page`
    /// drawn over `pageView`'s frame when given. The behind-window material
    /// renders as nothing in-process; a flat underlay stands in for it.
    func writeComposite(page: NSImage?, pageView: NSView?, overlay: NSView? = nil, to url: URL) -> String {
        guard let content = window.contentView, let layer = content.layer else { return "no layer" }
        let scale = window.backingScaleFactor
        let size = content.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return "no context" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        let dark = content.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cg.setFillColor(dark ? CGColor(gray: 0.17, alpha: 1) : CGColor(gray: 0.91, alpha: 1))
        cg.fill(CGRect(origin: .zero, size: size))
        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        if content.isFlipped {
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
        }
        layer.render(in: cg)
        if content.isFlipped {
            cg.scaleBy(x: 1, y: -1)
            cg.translateBy(x: 0, y: -size.height)
        }
        if let page, let pageView {
            let frame = pageView.convert(pageView.bounds, to: nil)
            let path = NSBezierPath(roundedRect: frame, xRadius: CardMetrics.cornerRadius, yRadius: CardMetrics.cornerRadius)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            page.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        if let overlay, let overlayRep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) {
            // A stand-in for the glass backdrop, then the list drawn by AppKit.
            overlay.cacheDisplay(in: overlay.bounds, to: overlayRep)
            let frame = overlay.convert(overlay.bounds, to: nil)
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: frame, xRadius: Radius.large, yRadius: Radius.large).fill()
            overlayRep.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "encode failed" }
        do { try png.write(to: url) } catch { return "\(error)" }
        return "\(url.lastPathComponent) \(rep.pixelsWide)x\(rep.pixelsHigh) layer render\(page == nil ? "" : ", page composited from CDP")"
            + (overlay == nil ? "" : ", list drawn by cacheDisplay over a flat stand-in for the glass")
    }

    // MARK: Key events

    func sendKey(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) {
        let ignoring = flags.contains(.shift) ? characters : characters.lowercased()
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: keyCode) {
                NSApp.sendEvent(event)
            }
        }
    }

    func sendFlags(_ flags: NSEvent.ModifierFlags) {
        if let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                        isARepeat: false, keyCode: 59) {
            NSApp.sendEvent(event)
        }
    }
}
#endif
