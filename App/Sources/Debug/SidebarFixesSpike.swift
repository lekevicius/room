#if DEBUG
import AppKit
import Engine

/// `sidebarfixes` (5.0a): the pass's two sidebar bugs in the running app.
/// B-108: the sidebar is resized as its edge's drag does
/// (`RoomWindowController.sidebarWidth`) and the selected row's pill is read
/// against the row. B-109: the outline's pointer is held still over a Today
/// tab's row, the tab is closed, and the row that slid under the pointer is
/// read back with its close button (the pointer itself is a computer-use check).
extension SpikeRunner.Context {
    func sidebarFixesChecks() async {
        let base = "http://127.0.0.1:8766"
        var pages: [any WebContents] = []
        for name in ["one", "two", "three"] {
            if let page = await open(URL(string: "\(base)/find.html?\(name)")!) { pages.append(page) }
        }
        let entries = pages.compactMap { tabs.entryID(for: $0) }
        guard entries.count == 3 else { return SpikeRunner.record("error", "sidebarfixes: three tabs did not open") }
        // B-108.
        sidebar.select(entries[0])
        try? await Task.sleep(for: .milliseconds(300))
        let format = { (pair: (pill: NSRect, row: NSRect)?) -> String in
            pair.map { String(format: "pill x=%.0f w=%.0f row x=%.0f w=%.0f", $0.pill.minX, $0.pill.width, $0.row.minX, $0.row.width) } ?? "none"
        }
        let width = controller.sidebarWidth
        let before = sidebar.debugPillAndRow
        for step in 1...6 {  // as a drag's steps
            controller.sidebarWidth = width + CGFloat(step * 20)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        let after = sidebar.debugPillAndRow
        SpikeRunner.record("b108_resize", "width \(Int(width)) → \(Int(controller.sidebarWidth)): before \(format(before)); after \(format(after)) "
            + "follows=\(after.map { $0.pill == $0.row } ?? false)")
        controller.sidebarWidth = width
        window.contentView?.layoutSubtreeIfNeeded()
        // B-109.
        let hovered = sidebar.debugStillPointer(over: entries[1])
        sidebar.close(entries[1])
        try? await Task.sleep(for: .milliseconds(400))
        let now = sidebar.debugHoveredEntry
        let names = Dictionary(uniqueKeysWithValues: zip(entries, ["one", "two", "three"]))
        let name = { (id: UUID?) in id.map { names[$0] ?? "other" } ?? "none" }
        SpikeRunner.record("b109_close", "hovered before=\(name(hovered)) after=\(name(now.id)) close_button=\(now.closeShown) "
            + "rows=\(sidebar.debugRowKinds.count)")
        sidebar.debugStillPointer(over: nil)
    }
}
#endif
