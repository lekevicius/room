#if DEBUG
import AppKit
import Card
import Design
import Engine
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 5.10 spike `redesign` (`scripts/redesign-check.sh`) on a throwaway state, the pages on the
/// test servers (:8766). Sections (`-RoomSpikeOnly` picks):
/// - `card`: one page edge to edge beside the sidebar and over the whole window with it hidden, the
///   window's corner; a split's panes inset; the card opaque to the titlebar's server-side drag (B-32);
/// - `devtools`: DevTools' own Dock side (bottom, left, right, undocked into Room's window, back) and
///   close button, driven in the front-end: where the page goes, the window, DevTools closed;
/// - `scroll`: a new tab opened below the list's visible part comes into view;
/// - `shots`: the window open and hidden, the revealed overlay, the palette, a hovered space's name.
/// `-RoomSpikeCaptureDirectory` keeps in-process captures named `phase-5.10-<name>-<appearance>.png`.
extension SpikeRunner.Context {
    func redesignChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: redesignAppearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(redesignAppearance) app=\(Bundle.main.bundlePath)")
        if runs("card") { await redesignCard() }
        if runs("devtools") { await redesignDevTools() }
        if runs("scroll") { await redesignScroll() }
        if runs("shots") { await redesignShots() }
        controller.isSidebarOpen = true
    }

    private var redesignAppearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let redesignBase = "http://127.0.0.1:8766/"

    private func redesignCapture(_ name: String, of target: NSWindow? = nil) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let target = target ?? window
        target.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.10-\(name)-\(redesignAppearance).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(target, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: card

    private func redesignCard() async {
        guard await open(URL(string: Self.redesignBase + "find.html?card")!) != nil else { return SpikeRunner.record("error", "card: no page") }
        let root = controller.rootView
        let card = controller.cardView
        func line(_ label: String) {
            root.layoutSubtreeIfNeeded()
            let bounds = root.bounds
            let expected = controller.isSidebarOpen ? NSRect(x: root.currentLayout.sidebar.maxX, y: 0, width: bounds.width - root.currentLayout.sidebar.maxX, height: bounds.height) : bounds
            SpikeRunner.record("card_\(label)", "frame=\(NSStringFromRect(card.frame)) expected=\(NSStringFromRect(expected)) edge=\(card.frame == expected) "
                + "corner=\(card.cornerRadius) inset=\(root.isCardInset)")
        }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))
        line("open")
        // The titlebar's drag: AppKit asks the views under the titlebar for their opaque rect.
        let selector = NSSelectorFromString("_opaqueRectForWindowMoveWhenInTitlebar")
        let container = card.container
        if container.responds(to: selector), let rect = container.perform(selector).map({ _ in container.bounds }) {
            SpikeRunner.record("card_titlebar_opaque", "responds=true rect=\(NSStringFromRect(rect)) titlebar=\(NSStringFromRect(window.contentLayoutRect))")
        } else {
            SpikeRunner.record("card_titlebar_opaque", "responds=false")
        }
        redesignCapture("card-open")
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        line("hidden")
        redesignCapture("card-hidden")
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))
        // A split keeps the inset.
        guard let second = try? store.addEntry(.today, url: Self.redesignBase + "find.html?split", space: sidebar.activeSpaceID),
              let first = sidebar.selectedEntryID else { return }
        tabs.loadInBackground(second)
        try? await Task.sleep(for: .milliseconds(800))
        sidebar.joinIntoSplit(second.id, with: first)
        try? await Task.sleep(for: .milliseconds(800))
        root.layoutSubtreeIfNeeded()
        SpikeRunner.record("card_split", "frame=\(NSStringFromRect(card.frame)) inset=\(root.isCardInset) corner=\(card.cornerRadius)")
        redesignCapture("card-split")
        sidebar.unsplit()
        try? await Task.sleep(for: .milliseconds(600))
        root.layoutSubtreeIfNeeded()
        SpikeRunner.record("card_unsplit", "frame=\(NSStringFromRect(card.frame)) inset=\(root.isCardInset) corner=\(card.cornerRadius)")
    }

    // MARK: devtools

    /// DevTools' own Dock side (the front-end's DockController, as its ⋮ menu sets it) and close button
    /// (InspectorFrontendHost.closeWindow, as its × calls it), driven in the front-end page.
    private func redesignDevTools() async {
        guard let page = await open(URL(string: Self.redesignBase + "find.html?devtools")!), let app = AppDelegate.current,
              let host = app.pageHost else { return SpikeRunner.record("error", "devtools: no page") }
        guard page.devTools != nil else { return SpikeRunner.record("error", "devtools: none on this engine") }
        host.toggleDevTools()
        _ = await waitUntil(10) { page.devTools?.isOpen == true }
        guard let frontend = devToolsFrontend(page) else { return SpikeRunner.record("error", "devtools: no front-end") }
        await waitLoaded(frontend, timeout: 10)
        try? await Task.sleep(for: .seconds(2))
        let container = host.container
        func frontendJS(_ body: String) async -> String {
            await js(frontend, "(async () => { try { const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js'); "
                + "const dock = UI.DockController.DockController.instance(); \(body) } catch (e) { return 'error ' + e } })()")
        }
        func record(_ label: String) async {
            container.layoutSubtreeIfNeeded()
            let side = await frontendJS("return dock.dockSide() + ' canDock=' + dock.canDock() + ' close=' + (dock.closeButton ? dock.closeButton.visible() : 'none');")
            let devToolsWindow = NSApp.windows.first { $0.isVisible && $0.title.hasPrefix("Developer Tools") }
            let inWindow = devToolsWindow.flatMap { redesignFind("devtools-host", in: $0.contentView) }?.subviews.isEmpty == false
            SpikeRunner.record("devtools_\(label)", "open=\(page.devTools?.isOpen == true) docked=\(page.devTools?.isDocked == true) "
                + "page=\(NSStringFromRect(container.pageFrame)) container=\(NSStringFromRect(container.bounds)) "
                + "frontend_in_card=\(!container.devToolsHost.subviews.isEmpty) window=\(devToolsWindow != nil) in_window=\(inWindow) frontend=\(side)")
        }
        await record("opened")
        redesignCapture("devtools-opened")
        for side in ["bottom", "left", "right"] {
            _ = await frontendJS("dock.setDockSide('\(side)'); return 'ok';")
            try? await Task.sleep(for: .seconds(1.5))
            await record(side)
            redesignCapture("devtools-\(side)")
        }
        _ = await frontendJS("dock.setDockSide('undocked'); return 'ok';")
        try? await Task.sleep(for: .seconds(2))
        await record("undocked")
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.title.hasPrefix("Developer Tools") }) {
            redesignCapture("devtools-window", of: window)
        }
        _ = await frontendJS("dock.setDockSide('right'); return 'ok';")
        try? await Task.sleep(for: .seconds(2))
        await record("redocked")
        // The front-end's own close button.
        let closeCall = await js(frontend, "(async () => { try { const Host = await import('devtools://devtools/bundled/core/host/host.js'); "
            + "Host.InspectorFrontendHost.InspectorFrontendHostInstance.closeWindow(); return 'ok'; } catch (e) { return 'error ' + e } })()")
        var samples: [String] = []
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            samples.append("\(page.devTools?.isOpen == true ? 1 : 0)\(page.devTools?.isDocked == true ? "d" : "")")
        }
        SpikeRunner.record("devtools_close_samples", "call=\(closeCall) \(samples.joined(separator: " "))")
        try? await Task.sleep(for: .milliseconds(800))
        SpikeRunner.record("devtools_closed_by_frontend", "open=\(page.devTools?.isOpen == true) frontend_in_card=\(!container.devToolsHost.subviews.isEmpty) "
            + "card_hidden=\(container.devToolsHost.isHidden) page=\(NSStringFromRect(container.pageFrame))")
        // ⌥⌘I twice: opens where it was, closes.
        host.toggleDevTools()
        _ = await waitUntil(10) { page.devTools?.isOpen == true }
        try? await Task.sleep(for: .seconds(1))
        SpikeRunner.record("devtools_reopened", "docked=\(page.devTools?.isDocked == true) page=\(NSStringFromRect(container.pageFrame))")
        host.toggleDevTools()
        _ = await waitUntil(5) { page.devTools?.isOpen == false }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("devtools_closed_by_key", "open=\(page.devTools?.isOpen == true) card_hidden=\(container.devToolsHost.isHidden)")
    }

    private func redesignFind(_ identifier: String, in root: NSView?) -> NSView? {
        guard let root else { return nil }
        if root.accessibilityIdentifier() == identifier { return root }
        for view in root.subviews { if let found = redesignFind(identifier, in: view) { return found } }
        return nil
    }

    // MARK: scroll

    private func redesignScroll() async {
        let space = sidebar.activeSpaceID
        for index in 0..<30 { _ = try? store.addEntry(.today, url: Self.redesignBase + "find.html?row-\(index)", space: space) }
        try? await Task.sleep(for: .milliseconds(800))
        let outline = sidebar.debugOutline
        outline.scrollRowToVisible(0)
        try? await Task.sleep(for: .milliseconds(300))
        // ⌘T's path: a new Today tab, selected.
        guard session.newPage(URL(string: Self.redesignBase + "find.html?new-tab")!, hidden: false, select: true) != nil else {
            return SpikeRunner.record("error", "scroll: no new tab")
        }
        try? await Task.sleep(for: .milliseconds(800))
        let visible = outline.visibleRect
        let pill = sidebar.debugPillFrame ?? .zero
        SpikeRunner.record("scroll_new_tab", "rows=\(outline.numberOfRows) pill=\(NSStringFromRect(pill)) visible=\(NSStringFromRect(visible)) "
            + "pill_visible=\(pill != .zero && visible.contains(pill))")
        redesignCapture("scroll-new-tab")
    }

    // MARK: shots

    private func redesignShots() async {
        guard await open(URL(string: Self.redesignBase + "find.html?shots")!) != nil else { return }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(500))
        redesignCapture("window")
        // The hidden sidebar's overlay, pinned (⌥⌘S).
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(500))
        controller.reveal.togglePin()
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("overlay_frame", NSStringFromRect(controller.rootView.overlayView.frame))
        redesignCapture("overlay")
        controller.reveal.togglePin()
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(500))
        if let palette = AppDelegate.current?.activeWindow?.palette {
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(600))
            redesignCapture("palette")
            palette.dismiss()
        }
    }
}
#endif
