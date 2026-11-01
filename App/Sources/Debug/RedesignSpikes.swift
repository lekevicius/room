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
/// - `devtools`: the header's Dock to Right, Left, Bottom, Open in Window and Close, clicked through
///   their buttons: the pane's frame beside the page, the window, DevTools closed;
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

    private func redesignDevTools() async {
        guard let page = await open(URL(string: Self.redesignBase + "find.html?devtools")!), let app = AppDelegate.current,
              let host = app.pageHost else { return SpikeRunner.record("error", "devtools: no page") }
        guard page.devTools != nil else { return SpikeRunner.record("error", "devtools: none on this engine") }
        // A known start: docked at the bottom.
        UserDefaults.standard.set("bottom", forKey: "RoomDevToolsPlacement")
        host.toggleDevTools()
        _ = await waitUntil(10) { page.devTools?.isOpen == true }
        try? await Task.sleep(for: .seconds(2))
        let container = host.container
        func record(_ label: String) {
            container.layoutSubtreeIfNeeded()
            let pane = container.devToolsPane
            let frontend = container.devToolsHost.subviews.first
            SpikeRunner.record("devtools_\(label)", "open=\(page.devTools?.isOpen == true) pane=\(pane.isHidden ? "hidden" : NSStringFromRect(pane.frame)) "
                + "page=\(NSStringFromRect(container.pageView?.frame ?? .zero)) frontend_in_pane=\(frontend != nil) "
                + "window=\(NSApp.windows.contains { $0.isVisible && $0.title.hasPrefix("Developer Tools") })")
        }
        record("bottom")
        redesignCapture("devtools-bottom")
        func click(_ id: String, in root: NSView) -> Bool {
            guard let button = redesignFind(id, in: root) as? NSButton else {
                SpikeRunner.record("error", "devtools: no button \(id)")
                return false
            }
            button.performClick(nil)
            return true
        }
        for placement in ["right", "left", "bottom"] {
            guard click("devtools-\(placement)", in: container.devToolsPane) else { return }
            try? await Task.sleep(for: .seconds(1))
            record(placement)
            if placement != "bottom" { redesignCapture("devtools-\(placement)") }
        }
        guard click("devtools-window", in: container.devToolsPane) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        let devToolsWindow = NSApp.windows.first { $0.isVisible && $0.title.hasPrefix("Developer Tools") }
        let inWindow = devToolsWindow.flatMap { redesignFind("devtools-host", in: $0.contentView) }?.subviews.isEmpty == false
        record("window")
        SpikeRunner.record("devtools_window_frontend", "in_window=\(inWindow) title=\(devToolsWindow?.title ?? "none")")
        if let devToolsWindow { redesignCapture("devtools-window", of: devToolsWindow) }
        // Dock back from the window's own strip, then Close from the pane's.
        if let content = devToolsWindow?.contentView, click("devtools-right", in: content) {
            try? await Task.sleep(for: .seconds(1))
            record("docked_from_window")
        }
        guard click("devtools-close", in: container.devToolsPane) else { return }
        _ = await waitUntil(5) { page.devTools?.isOpen == false }
        try? await Task.sleep(for: .milliseconds(500))
        record("closed")
        // The window's close button closes DevTools too.
        host.toggleDevTools()
        _ = await waitUntil(10) { page.devTools?.isOpen == true }
        try? await Task.sleep(for: .seconds(1))
        guard click("devtools-window", in: container.devToolsPane) else { return }
        try? await Task.sleep(for: .seconds(1))
        NSApp.windows.first { $0.isVisible && $0.title.hasPrefix("Developer Tools") }?.performClose(nil)
        _ = await waitUntil(5) { page.devTools?.isOpen == false }
        record("window_closed")
        host.place(.bottom)
        host.closeDevTools()
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
