#if DEBUG
import AppKit
import Design
import Engine
import Model
import Sidebar
import Store
import UIKitCore

/// Phase 5.11 spike `fixes` (`scripts/fixes-check.sh`) on a throwaway state, the pages on the test
/// servers (:8766). Sections (`-RoomSpikeOnly` picks):
/// - `tabdrag`: a Today row pressed and moved through the app's event queue: AppKit begins the drag;
///   the drop half through Room's drop code with the row's pasteboard: the row lands two rows down;
/// - `split`: the panes' shadows not clipped by the card (its container's `clipsToBounds`);
/// - `dock`: ⌘S slides the docked sidebar out and in (the card's and the sidebar's frames animate);
/// - `folder`: a click on a folder while its preview's search field has the keyboard opens it at once;
/// - `sitepanel`: from the revealed overlay the panel points at the header's chevron; its certificate button;
/// - `shots`: the selected row's and Essential's glow, Clear's pill, the palette's shadow, the site panel.
/// `-RoomSpikeCaptureDirectory` keeps in-process captures named `phase-5.11-<name>-<appearance>.png`.
extension SpikeRunner.Context {
    func fixesChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: fixesAppearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(fixesAppearance) app=\(Bundle.main.bundlePath)")
        if runs("tabdrag") { await fixesTabDrag() }
        if runs("split") { await fixesSplit() }
        if runs("dock") { await fixesDock() }
        if runs("folder") { await fixesFolder() }
        if runs("sitepanel") { await fixesSitePanel() }
        if runs("shots") { await fixesShots() }
        controller.isSidebarOpen = true
    }

    private var fixesAppearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let fixesBase = "http://127.0.0.1:8766/"

    func fixesCapture(_ name: String, of target: NSWindow? = nil) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let target = target ?? window
        target.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.11-\(name)-\(fixesAppearance).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(target, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    private func todayIDs() -> [UUID] { store.entries(in: .today(space: sidebar.activeSpaceID)).map(\.id) }

    // MARK: dock

    private func fixesDock() async {
        guard await open(URL(string: Self.fixesBase + "find.html?dock")!) != nil else { return SpikeRunner.record("error", "dock: no page") }
        let root = controller.rootView
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))
        for hide in [true, false] {
            let before = controller.cardView.frame
            controller.toggleSidebarVisibility(nil)
            try? await Task.sleep(for: .milliseconds(Int(Motion.dock * 1000 / 2)))
            let mid = controller.cardView.layer?.presentation()?.frame ?? .zero
            let sidebarMid = controller.sidebarView.layer?.presentation()?.frame ?? .zero
            let animating = root.isDockAnimating
            _ = await waitUntil(2) { !root.isDockAnimating }
            root.layoutSubtreeIfNeeded()
            let after = controller.cardView.frame
            SpikeRunner.record(hide ? "dock_hide" : "dock_show", "animating_mid=\(animating) card \(Int(before.minX))→mid \(Int(mid.minX))→\(Int(after.minX)) "
                + "sidebar_mid_x=\(Int(sidebarMid.minX)) open=\(controller.isSidebarOpen) "
                + "between=\(mid.minX > min(before.minX, after.minX) && mid.minX < max(before.minX, after.minX))")
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: folder

    private func fixesFolder() async {
        let space = sidebar.activeSpaceID
        guard let folder = try? store.addFolder(name: "Preview", space: space) else { return SpikeRunner.record("error", "folder: fixture") }
        for index in 0..<2 { _ = try? store.addEntry(.pinned, url: Self.fixesBase + "find.html?inside-\(index)", title: "Inside \(index)", space: space, folder: folder.id) }
        try? store.setFolderCollapsed(folder.id, true)
        try? await Task.sleep(for: .milliseconds(600))
        sidebar.showFolderPreview(folder.id)
        _ = await waitUntil(2) { sidebar.debugFolderPreviewWindow?.isVisible == true }
        try? await Task.sleep(for: .milliseconds(300))
        let previewKey = sidebar.debugFolderPreviewWindow?.isKeyWindow == true
        let mainKey = window.isKeyWindow
        let point = sidebar.debugRowPoint(folder.id, fraction: 0.5) ?? .zero
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        let firstMouse = sidebar.debugOutline.acceptsFirstMouse(for: down)
        await postClick(at: controller.rootView.convert(point, from: nil))
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("folder_first_click", "preview_key=\(previewKey) window_key_before=\(mainKey) accepts_first_mouse=\(firstMouse) "
            + "preview_closed=\(sidebar.debugFolderPreviewWindow?.isVisible != true) expanded=\(store.entry(folder.id)?.isCollapsed == false)")
        try? store.setFolderCollapsed(folder.id, true)
    }

    // MARK: sitepanel

    private func fixesSitePanel() async {
        guard let app = AppDelegate.current, await open(URL(string: "https://example.com/")!, timeout: 15) != nil
        else { return SpikeRunner.record("error", "sitepanel: no page") }
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        controller.reveal.togglePin()
        _ = await waitUntil(2) { controller.rootView.isOverlayShown && !controller.rootView.isOverlayAnimating }
        app.showSitePanel()
        _ = await waitUntil(3) { app.sitePanel.isShown }
        try? await Task.sleep(for: .milliseconds(500))
        let panel = app.sitePanel.contentView?.window?.frame ?? .zero
        let siteButton = sidebar.addressField.siteButtonView
        let button = siteButton.window.map { $0.convertToScreen(siteButton.convert(siteButton.bounds, to: nil)) } ?? .zero
        let card = window.convertToScreen(controller.rootView.convert(controller.rootView.currentLayout.card, to: nil))
        SpikeRunner.record("sitepanel_anchor", "overlay_shown=\(controller.rootView.isOverlayShown) panel=\(NSStringFromRect(panel)) button=\(NSStringFromRect(button)) "
            + "under_button=\(abs(panel.midX - button.midX) < 40 && panel.maxY <= button.minY + 4) card_corner_x=\(Int(card.minX))")
        let chain = app.tabs?.current?.certificateChain.count ?? -1
        SpikeRunner.record("sitepanel_certificate", "chain=\(chain) button=\(findIdentifier("site-certificate", in: app.sitePanel.contentView))")
        if let panelWindow = app.sitePanel.contentView?.window { fixesCapture("site-panel", of: panelWindow) }
        app.sitePanel.close()
        controller.reveal.togglePin()
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(400))
    }

    private func findIdentifier(_ identifier: String, in view: NSView?) -> Bool {
        guard let view else { return false }
        if view.accessibilityIdentifier() == identifier { return true }
        if (view.accessibilityChildren() ?? []).contains(where: { ($0 as? NSAccessibilityElement)?.accessibilityIdentifier() == identifier }) { return true }
        return view.subviews.contains { findIdentifier(identifier, in: $0) }
    }

    // MARK: shots

    private func fixesShots() async {
        let space = sidebar.activeSpaceID
        _ = try? store.addEntry(.essential, url: "https://www.apple.com/", title: "Apple", space: space)
        guard await open(URL(string: "https://github.com/")!, timeout: 15) != nil else { return SpikeRunner.record("error", "shots: no page") }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(1500))
        sidebar.debugHover(nil)
        fixesCapture("window")
        if let palette = AppDelegate.current?.activeWindow?.palette {
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(600))
            fixesCapture("palette")
            palette.dismiss()
        }
    }

    // MARK: split

    private func fixesSplit() async {
        guard await open(URL(string: Self.fixesBase + "find.html?split-a")!) != nil,
              let second = try? store.addEntry(.today, url: Self.fixesBase + "find.html?split-b", space: sidebar.activeSpaceID),
              let first = sidebar.selectedEntryID else { return SpikeRunner.record("error", "split: no pages") }
        tabs.loadInBackground(second)
        try? await Task.sleep(for: .milliseconds(800))
        sidebar.joinIntoSplit(second.id, with: first)
        try? await Task.sleep(for: .milliseconds(800))
        controller.rootView.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSView? {
            if String(describing: Swift.type(of: view)) == "SplitView" { return view }
            for sub in view.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        guard let split = find(controller.cardView) else { return SpikeRunner.record("error", "split: no split view") }
        let shadows = (split.layer?.sublayers ?? []).filter { $0.shadowOpacity > 0 && !$0.isHidden }
        var chain: [String] = []
        var view: NSView? = split
        while let current = view, current !== controller.rootView.superview {
            chain.append("\(Swift.type(of: current))(masks=\(current.layer?.masksToBounds ?? false) clips=\(current.clipsToBounds))")
            view = current.superview
        }
        SpikeRunner.record("split_shadows", "count=\(shadows.count) frames=\(shadows.map { NSStringFromRect($0.frame) }) split_bounds=\(NSStringFromRect(split.bounds)) "
            + "card=\(NSStringFromRect(controller.cardView.frame)) split_host=\(controller.cardView.isSplitHost) chain=\(chain.joined(separator: " < "))")
        fixesCapture("split")
        sidebar.unsplit()
        try? await Task.sleep(for: .milliseconds(500))
    }

    // MARK: tabdrag

    private func fixesTabDrag() async {
        let space = sidebar.activeSpaceID
        for index in 0..<3 { _ = try? store.addEntry(.today, url: Self.fixesBase + "find.html?drag-\(index)", space: space) }
        try? await Task.sleep(for: .milliseconds(800))
        let before = todayIDs()
        guard before.count >= 3, let first = before.first,
              let start = sidebar.debugRowPoint(first, fraction: 0.5), let target = sidebar.debugRowPoint(before[2], fraction: 0.8)
        else { return SpikeRunner.record("error", "tabdrag: rows not listed (\(before.count))") }
        let root = controller.rootView
        let from = root.convert(start, from: nil), to = root.convert(target, from: nil)
        let begun = sidebar.debugDragsBegun
        // Which views under the rows AppKit would let move the window (the window server's own drag, before Room sees the press).
        var movers: [String] = []
        func walk(_ view: NSView) {
            if view.mouseDownCanMoveWindow, !view.isHiddenOrHasHiddenAncestor { movers.append(String(describing: Swift.type(of: view))) }
            view.subviews.forEach(walk)
        }
        walk(sidebar.debugOutline)
        SpikeRunner.record("tabdrag_movers", "window movable=\(window.isMovable) by_background=\(window.isMovableByWindowBackground) "
            + "glass_moves=\(NSGlassEffectView().mouseDownCanMoveWindow) in_outline=\(Set(movers).sorted()) count=\(movers.count)")
        let hit = window.contentView?.superview?.hitTest(start).map { String(describing: Swift.type(of: $0)) } ?? "nil"
        post(.mouseMoved, at: from)
        post(.leftMouseDown, at: from, clickCount: 1)
        var lineSeen = false
        for step in 1...12 {
            let f = CGFloat(step) / 12
            post(.leftMouseDragged, at: CGPoint(x: from.x + 2 * f, y: from.y + (to.y - from.y) * f), clickCount: 1)
            try? await Task.sleep(for: .milliseconds(16))
            lineSeen = lineSeen || sidebar.debugInsertionLine != nil
        }
        post(.leftMouseUp, at: to, clickCount: 1)
        try? await Task.sleep(for: .milliseconds(900))
        let after = todayIDs()
        let names = { (ids: [UUID]) in ids.map { id in before.firstIndex(of: id).map(String.init) ?? "new" }.joined(separator: ",") }
        // The drop half through Room's own drop code: a row's pasteboard (as AppKit's session carries it), over the third row's lower part.
        let reordered = todayIDs()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("room-5.11-tabdrag-\(UUID().uuidString)"))
        pasteboard.clearContents()
        if let item = sidebar.debugPasteboardItem(for: reordered[0]) { pasteboard.writeObjects([item]) }
        let info = RowDraggingInfo(pasteboard: pasteboard, location: target, window: window, source: sidebar.debugOutline)
        let operation = sidebar.debugOutlineDragUpdated(info)
        _ = sidebar.debugOutlineDragUpdated(info)
        let line = sidebar.debugInsertionLine
        let accepted = sidebar.debugOutlinePerformDrop(info)
        sidebar.debugOutlineDragExited()
        try? await Task.sleep(for: .milliseconds(500))
        let dropped = todayIDs()
        pasteboard.releaseGlobally()
        SpikeRunner.record("tabdrag_drop", "operation=\(operation.rawValue) line=\(line.map(NSStringFromRect) ?? "nil") accepted=\(accepted) "
            + "order before=\(reordered.map { before.firstIndex(of: $0).map(String.init) ?? "new" }.joined(separator: ",")) "
            + "after=\(dropped.map { before.firstIndex(of: $0).map(String.init) ?? "new" }.joined(separator: ","))")
        SpikeRunner.record("tabdrag", "hit=\(hit) drags_begun=\(sidebar.debugDragsBegun - begun) insertion_line_seen=\(lineSeen) "
            + "order before=0..\(before.count - 1) after=\(names(after)) windows=\(NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.count) "
            + "mouse=\(NSStringFromPoint(NSEvent.mouseLocation))")
    }
}

/// A row's drag inside Room (5.11): the operations AppKit offers within the app and the outline as its source.
final class RowDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var location: NSPoint
    let window: NSWindow
    let source: Any?
    private static var sequence = 19_000

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow, source: Any?) {
        draggingPasteboard = pasteboard
        self.location = location
        self.window = window
        self.source = source
        Self.sequence += 1
        draggingSequenceNumber = Self.sequence
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.move, .copy] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { source }
    let draggingSequenceNumber: Int
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
#endif
