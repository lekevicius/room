#if DEBUG && canImport(EngineCEF)
import AppKit
import Card
import Design
import Engine
import EngineCEF
import Model
import QuartzCore
import Sidebar
import Tabs
import UIKitCore

/// Phase 2.7b: `layoutmodes` `-RoomSpikeOnly split` (`scripts/layout-modes.sh`):
/// split view on CEF with the test site's pages. Measures split creation
/// to both panes laid out (and to the next frame), a resizer drag's frame
/// intervals with two loaded pages, a click in the other pane to the header
/// field updated; checks the keys through the main menu, ⌘W on a pane,
/// Peek over a split (events under the dim) and Peek ▸ Split, element
/// fullscreen of the focused pane; captures (`-RoomSpikeCapturePrefix phase-2.7b`).
extension SpikeRunner.Context {
    private var app27b: AppDelegate? { NSApp.delegate as? AppDelegate }

    /// A Today tab on the test site, loaded (in the background unless `select`).
    private func testTab(_ query: String, host: String = SpikeRunner.Context.site, select: Bool = false) async -> UUID? {
        let store = sidebar.store.sidebar
        guard let entry = try? store.addEntry(.today, url: host + "site.html?pane=" + query, title: "Pane \(query)", space: sidebar.activeSpaceID)
        else { return nil }
        if select { sidebar.select(entry.id) } else { tabs.loadInBackground(entry) }
        if let page = tabs.contents(for: entry.id) { await waitLoaded(page) }
        return entry.id
    }

    private func key(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: characters,
                                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    /// Where a split view rect is in the root view.
    private func inRoot(_ rect: CGRect, of view: NSView) -> CGRect { view.convert(rect, to: controller.rootView) }

    func splitCheck(pinned: UUID) async {
        guard let app = app27b, let host = app.debugPageHost else { return SpikeRunner.record("error", "no page host") }
        let split = host.splitView
        let store = sidebar.store.sidebar
        controller.isSidebarOpen = true
        tabs.closeShownPeek()
        guard let a = await testTab("1", select: true), let b = await testTab("2", host: Self.otherSite) else {
            return SpikeRunner.record("error", "no test tabs")
        }
        try? await Task.sleep(for: .milliseconds(400))

        // Split creation → both panes laid out (synchronous), → the next frame; B already loaded.
        var created: [Double] = [], framed: [Double] = []
        for _ in 0..<6 {
            if let group = store.splitGroup(of: a) { store.dissolveSplitGroup(group.id) }
            sidebar.select(a)
            try? await Task.sleep(for: .milliseconds(300))
            var frameAt: TimeInterval?
            let start = ProcessInfo.processInfo.systemUptime
            sidebar.joinIntoSplit(b, with: a)
            split.layoutSubtreeIfNeeded()
            let laidOut = ProcessInfo.processInfo.systemUptime
            CATransaction.setCompletionBlock { frameAt = ProcessInfo.processInfo.systemUptime }
            _ = await waitUntil(2) { frameAt != nil }
            created.append((laidOut - start) * 1000)
            if let frameAt { framed.append((frameAt - start) * 1000) }
        }
        let frames = split.panes.map { NSStringFromRect($0.frame) }.joined(separator: " ")
        let pagesInPanes = split.panes.map { $0.container.pageView === tabs.contents(for: $0.entry ?? UUID())?.nativeView }
        SpikeRunner.record("split_create_to_laid_out", SpikeRunner.stats(created) + " (both pages loaded before)")
        SpikeRunner.record("split_create_to_next_frame", SpikeRunner.stats(framed))
        SpikeRunner.record("split_panes", "count=\(split.panes.count) frames=\(frames) pages in their panes=\(pagesInPanes) focused=\(tabs.currentEntryID == b)")
        // Creation with a pane whose page is made by the split (not loaded yet).
        if let c0 = try? store.addEntry(.today, url: Self.site + "site.html?pane=fresh", title: "Fresh", space: sidebar.activeSpaceID) {
            sidebar.select(a)
            try? await Task.sleep(for: .milliseconds(300))
            let start = ProcessInfo.processInfo.systemUptime
            sidebar.joinIntoSplit(c0.id, with: a)
            split.layoutSubtreeIfNeeded()
            let laidOut = (ProcessInfo.processInfo.systemUptime - start) * 1000
            if let page = tabs.contents(for: c0.id) { await waitLoaded(page) }
            let loaded = (ProcessInfo.processInfo.systemUptime - start) * 1000
            SpikeRunner.record("split_create_new_page", String(format: "laid out %.2f ms (the page made), loaded %.0f ms", laidOut, loaded))
            sidebar.close(c0.id)
            try? await Task.sleep(for: .milliseconds(300))
        }
        sidebar.select(a)
        try? await Task.sleep(for: .milliseconds(500))
        let rowCell = sidebar.debugRowCellKind(a)
        SpikeRunner.record("split_sidebar_row", "row for pane A is \(rowCell); rows showing B separately: \(sidebar.debugIsListed(b))")
        split.panes.first?.setHeaderShown(true, animated: false)
        await capture27("split-2")
        split.panes.first?.setHeaderShown(false, animated: false)

        // The resizer, dragged with posted events (the path real ones take), 60 steps at ~one per frame.
        if let resizer = split.subviews.compactMap({ $0 as? SplitResizerView }).first(where: { !$0.isHidden }) {
            let hit = inRoot(resizer.bounds, of: resizer)
            let startPoint = CGPoint(x: hit.midX, y: hit.midY)
            _ = await js(tabs.contents(for: a)!, "window.__clicks = 0; window.__downs = 0")
            post(.leftMouseDown, at: startPoint, clickCount: 1)
            var dragging = true
            let recorder = FrameRecorder()
            let link = controller.rootView.displayLink(target: recorder, selector: #selector(FrameRecorder.tick(_:)))
            link.add(to: .main, forMode: .common)
            for step in 0..<60 {
                let x = startPoint.x - 200 * sin(Double(step) / 59 * .pi)
                post(.leftMouseDragged, at: CGPoint(x: x, y: startPoint.y))
                if step == 30 { await capture27("resizer-mid-drag") }
                try? await Task.sleep(for: .milliseconds(16))
            }
            post(.leftMouseUp, at: CGPoint(x: startPoint.x - 120, y: startPoint.y), clickCount: 1)
            try? await Task.sleep(for: .milliseconds(200))
            dragging = false
            link.invalidate()
            _ = dragging
            let intervals = zip(recorder.stamps.dropFirst(), recorder.stamps).map { ($0 - $1) * 1000 }
            let ratios = store.splitGroup(of: a)?.ratios.map { String(format: "%.3f", $0) }.joined(separator: ", ") ?? "none"
            let pageDowns = await js(tabs.contents(for: a)!, "__downs")
            SpikeRunner.record("resizer_drag_frame_intervals", SpikeRunner.stats(intervals) + " (two loaded pages, 60 drag events)")
            SpikeRunner.record("resizer_drag_result", "ratios committed=[\(ratios)] presses that reached pane A's page=\(pageDowns)")
            // Double-click equalises.
            await postClick(at: startPoint)
            post(.leftMouseDown, at: inRoot(resizer.bounds, of: resizer).center, clickCount: 2)
            post(.leftMouseUp, at: inRoot(resizer.bounds, of: resizer).center, clickCount: 2)
            try? await Task.sleep(for: .milliseconds(300))
            SpikeRunner.record("resizer_double_click", "ratios=\(store.splitGroup(of: a)?.ratios ?? [])")
        }

        // Focus follows click: a press in the other pane's page → the header field shows its URL.
        var handled: [Double] = [], toFrame: [Double] = []
        host.debugFocusTiming = { handled.append($0); toFrame.append($1) }
        var fieldFollowed = true
        for round in 0..<10 {
            let target = round % 2 == 0 ? a : b
            guard let pane = split.pane(for: target) else { continue }
            let point = inRoot(pane.bounds, of: pane).center
            post(.mouseMoved, at: point)
            await postClick(at: point)
            _ = await waitUntil(1) { self.tabs.currentEntryID == target }
            try? await Task.sleep(for: .milliseconds(150))
            let url = store.entry(target)?.currentURL
            if sidebar.addressField.displayedURL != url { fieldFollowed = false }
        }
        host.debugFocusTiming = nil
        SpikeRunner.record("focus_click_to_field_updated", SpikeRunner.stats(handled) + " main thread, press handled → field set")
        SpikeRunner.record("focus_click_to_next_frame", SpikeRunner.stats(toFrame))
        SpikeRunner.record("focus_field_follows_pane", fieldFollowed)

        // Four panes, grid; the keys through the main menu (page-first keys arrive there unhandled).
        guard let c = await testTab("3"), let d = await testTab("4", host: Self.otherSite) else { return }
        sidebar.select(b)
        sidebar.joinIntoSplit(c, with: b)
        sidebar.joinIntoSplit(d, with: c)
        try? await Task.sleep(for: .milliseconds(300))
        var keys: [String] = []
        keys.append("⌥⌘G handled=\(key("g", code: 5, [.command, .option])) layout=\(store.splitGroup(of: a)?.layout.rawValue ?? "nil")")
        try? await Task.sleep(for: .milliseconds(400))
        split.panes.last?.setHeaderShown(true, animated: false)
        await capture27("split-4")
        split.panes.last?.setHeaderShown(false, animated: false)
        keys.append("⌃⇧1 handled=\(key("!", code: 18, [.control, .shift])) focused pane=\(store.splitGroup(of: a)?.members.firstIndex(of: tabs.currentEntryID ?? UUID()).map { $0 + 1 } ?? 0)")
        keys.append("⌃⇧] handled=\(key("}", code: 30, [.control, .shift])) focused pane=\(store.splitGroup(of: a)?.members.firstIndex(of: tabs.currentEntryID ?? UUID()).map { $0 + 1 } ?? 0)")
        keys.append("⌃⇧[ handled=\(key("{", code: 33, [.control, .shift])) focused pane=\(store.splitGroup(of: a)?.members.firstIndex(of: tabs.currentEntryID ?? UUID()).map { $0 + 1 } ?? 0)")
        keys.append("⌥⌘V handled=\(key("v", code: 9, [.command, .option])) layout=\(store.splitGroup(of: a)?.layout.rawValue ?? "nil")")
        keys.append("⌥⌘H handled=\(key("h", code: 4, [.command, .option])) layout=\(store.splitGroup(of: a)?.layout.rawValue ?? "nil")")
        keys.append("⌥⌘G handled=\(key("g", code: 5, [.command, .option])) layout=\(store.splitGroup(of: a)?.layout.rawValue ?? "nil")")
        keys.append("⇧⌘= handled=\(key("+", code: 24, [.command, .shift])) (a fifth pane: refused) panes=\(store.splitGroup(of: a)?.members.count ?? 0)")
        app.palette?.dismiss()
        SpikeRunner.record("split_keys", keys.joined(separator: "; "))

        // ⌘W on the focused pane closes only it (a Today tab: removed); the next pane is focused.
        sidebar.select(d)
        try? await Task.sleep(for: .milliseconds(300))
        let before = store.splitGroup(of: a)?.members.count ?? 0
        _ = key("w", code: 13, .command)
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("split_command_w", "panes \(before) → \(store.splitGroup(of: a)?.members.count ?? 0); D removed=\(store.entry(d) == nil); focused=\(tabs.currentEntryID == a ? "A" : tabs.currentEntryID == b ? "B" : tabs.currentEntryID == c ? "C" : "other") card panes=\(split.panes.count)")

        // Peek over the split: the dim covers every pane; nothing reaches the pages under it.
        sidebar.select(a)
        try? await Task.sleep(for: .milliseconds(300))
        if let page = tabs.contents(for: a), let peekView = app.peek {
            tabs.openPeek(URL(string: Self.otherSite + "offsite.html")!, from: page)
            _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
            try? await Task.sleep(for: .milliseconds(600))
            for id in [a, b, c] { if let p = tabs.contents(for: id) { _ = await js(p, "window.__clicks = 0; window.__moves = 0; window.__downs = 0") } }
            let overlay = peekView.overlay.frame
            let card = peekView.overlay.card.frame.offsetBy(dx: overlay.minX, dy: overlay.minY)
            var points: [CGPoint] = []
            for pane in split.panes {
                let rect = inRoot(pane.bounds, of: pane)
                // Points over the pane that the Peek card does not cover (the dim).
                for candidate in [CGPoint(x: rect.minX + 8, y: rect.midY), CGPoint(x: rect.maxX - 8, y: rect.midY),
                                  CGPoint(x: rect.midX, y: rect.minY + 8), CGPoint(x: rect.midX, y: rect.maxY - 8)]
                where !card.contains(candidate) && overlay.contains(candidate) { points.append(candidate) }
            }
            for point in points { post(.mouseMoved, at: point) }
            try? await Task.sleep(for: .milliseconds(300))
            await capture27("peek-over-split")
            var counts: [String] = []
            for (name, id) in [("A", a), ("B", b), ("C", c)] {
                guard let p = tabs.contents(for: id) else { continue }
                counts.append("\(name) clicks=\(await js(p, "__clicks")) downs=\(await js(p, "__downs")) moves=\(await js(p, "__moves"))")
            }
            SpikeRunner.record("isolation_peek_over_split", "Peek covers the card=\(overlay == controller.rootView.currentLayout.card); \(points.count) moves over the dim → \(counts.joined(separator: ", "))")
            // A click on the dim closes Peek and reaches no pane either.
            if let point = points.first {
                await postClick(at: point)
                _ = await waitUntil(2) { self.tabs.shownPeek == nil }
                try? await Task.sleep(for: .milliseconds(300))
                var after: [String] = []
                for (name, id) in [("A", a), ("B", b), ("C", c)] {
                    if let p = tabs.contents(for: id) { after.append("\(name) clicks=\(await js(p, "__clicks")) downs=\(await js(p, "__downs"))") }
                }
                SpikeRunner.record("isolation_peek_dim_click", "closed=\(tabs.shownPeek == nil) focused stays A=\(tabs.currentEntryID == a); \(after.joined(separator: ", "))")
            }
            // Peek ▸ Split from a full split is refused; from a two-pane split it adds the pane beside A.
            tabs.openPeek(URL(string: Self.otherSite + "offsite.html")!, from: page)
            _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
            sidebar.close(c)
            try? await Task.sleep(for: .milliseconds(300))
            sidebar.select(a)
            tabs.openPeek(URL(string: Self.otherSite + "offsite.html")!, from: page)
            _ = await waitUntil(4) { self.tabs.shownPeek?.isLoading == false }
            let peekPage = tabs.shownPeek
            let panesBefore = store.splitGroup(of: a)?.members ?? []
            _ = key("O", code: 31, [.command, .shift])
            try? await Task.sleep(for: .milliseconds(500))
            let members = store.splitGroup(of: a)?.members ?? []
            let added = members.first { !panesBefore.contains($0) }
            SpikeRunner.record("peek_split", "⇧⌘O: panes \(panesBefore.count) → \(members.count); the new pane is the Peek's page=\(added.flatMap { tabs.contents(for: $0) } === peekPage) beside A=\(added.flatMap { members.firstIndex(of: $0) } == members.firstIndex(of: a).map { $0 + 1 }) focused=\(tabs.currentEntryID == added) Peek gone=\(tabs.shownPeek == nil)")
            await capture27("peek-split")
        }

        // Element fullscreen of the focused pane (B-35): it fills the card alone, then everything comes back.
        if let focused = tabs.current, let pageDelegate = app.pageDelegate {
            pageDelegate.webContentsDidRequestEnterFullscreen(focused, origin: nil)
            _ = await waitUntil(5) { self.window.styleMask.contains(.fullScreen) }
            try? await Task.sleep(for: .milliseconds(1200))
            let pane = split.panes.first { $0.container.pageView === focused.nativeView }
            let fills = pane.map { $0.frame == split.bounds } ?? false
            let others = split.panes.filter { $0 !== pane }.allSatisfy(\.isHidden)
            pageDelegate.webContentsDidRequestExitFullscreen(focused)
            _ = await waitUntil(5) { !self.window.styleMask.contains(.fullScreen) }
            try? await Task.sleep(for: .milliseconds(1200))
            SpikeRunner.record("split_element_fullscreen", "focused pane fills the card=\(fills) others hidden=\(others); after exit panes visible=\(split.panes.allSatisfy { !$0.isHidden }) count=\(split.panes.count)")
        }

        // The hidden sidebar with a split.
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        await capture27("split-hidden-sidebar")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(300))
        // Unsplit leaves the focused pane selected, alone in the card.
        _ = key("u", code: 32, [.command, .option])
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("split_unsplit", "splits left=\(store.splitGroups.count) card panes=\(split.panes.count) selected has a page=\(tabs.current != nil)")
        sidebar.select(pinned)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
#endif
