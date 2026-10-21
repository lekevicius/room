#if DEBUG
import AppKit
import Card
import Design
import Engine
import Model
import Sidebar
import Tabs
import UIKitCore

/// `drops` (5.5b, ROADMAP 5.5 tasks 4–6): the drop matrix, six sources
/// (a link, two links, text, two URLs as text, image data, a file) onto the
/// sidebar's list, the card's page (and its textarea for text), a space icon
/// and the Essentials grid, each a pasteboard of its own handed to Room's
/// drop code through a dragging info (`FakeDraggingInfo`); the insertion
/// line and the haptic ticks read back; no tick on hover; the split's snap.
/// Pages are the test servers' (:8770 site, :8776 ime.html); text searches a
/// local engine (no request to a real site). `-RoomSpikeOnly matrix,haptics,split`.
extension SpikeRunner.Context {
    private static let dropSite = "http://127.0.0.1:8770/"
    private static let dropOther = "http://127.0.0.1:8771/"

    func dropChecks() async {
        let only = UserDefaults.standard.string(forKey: "RoomSpikeOnly").map { Set($0.split(separator: ",").map(String.init)) }
        func runs(_ name: String) -> Bool { only?.contains(name) ?? true }
        window.setContentSize(NSSize(width: 1200, height: 780))
        controller.isSidebarOpen = true
        // Searches go to the test server, never to a real engine.
        AppDelegate.current?.store?.settings.update {
            $0.searchSuggestions = false
            $0.searchEngines = [SearchEngineSetting(id: "local", name: "Local", keyword: "local", searchURL: Self.dropSite + "search?q={searchTerms}")]
            $0.searchEngine = "local"
        }
        SpikeRunner.record("haptics_at_start", Haptics.alignmentCount)
        if runs("routing") { await dropRouting() }
        if runs("matrix") { await dropMatrix() }
        if runs("haptics") { await hoverTicks() }
        if runs("overflow") { await overflowRecheck() }
        if runs("sublabels") { await sublabelRecheck() }
        if runs("pill") { await pillCaptures() }
        if runs("split") { await splitSnap() }
    }

    // MARK: Sources

    private struct DropSource {
        let name: String
        /// Tabs Room should open for it.
        let expected: Int
        let write: (NSPasteboard) -> Void
    }

    private func dropSources(file: URL) -> [DropSource] {
        let one = URL(string: Self.dropSite + "site.html?drop=link")!
        let two = [URL(string: Self.dropSite + "site.html?drop=a")!, URL(string: Self.dropOther + "site.html?drop=b")!]
        return [
            DropSource(name: "link", expected: 1) { $0.writeObjects([one as NSURL]) },
            DropSource(name: "links", expected: 2) { $0.writeObjects(two.map { $0 as NSURL }) },
            DropSource(name: "text", expected: 1) { $0.setString("room drop matrix", forType: .string) },
            DropSource(name: "urltext", expected: 2) {
                $0.setString([Self.dropSite + "site.html?drop=c", Self.dropOther + "site.html?drop=d"].joined(separator: "\n"), forType: .string)
            },
            DropSource(name: "image", expected: 1) { $0.setData(Self.pngFixture(), forType: .png) },
            DropSource(name: "file", expected: 1) { $0.writeObjects([file as NSURL]) },
        ]
    }

    private static func pngFixture() -> Data {
        let image = NSImage(size: NSSize(width: 64, height: 40), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private func pasteboard(_ source: DropSource) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.room.desktop.drop-spike.\(UUID().uuidString)"))
        pasteboard.clearContents()
        source.write(pasteboard)
        return pasteboard
    }

    private var todayURLs: [String] { store.today(space: sidebar.activeSpaceID, window: sidebar.windowID).compactMap(\.currentURL) }

    /// The URLs that appeared at the top of Today since `before` (new Today tabs go on top).
    private func newToday(since before: [String]) -> [String] {
        var after = todayURLs
        for url in before { if let index = after.lastIndex(of: url) { after.remove(at: index) } }
        return after
    }

    private func short(_ urls: [String]) -> String {
        urls.map { $0.replacingOccurrences(of: Self.dropSite, with: ":8770/").replacingOccurrences(of: Self.dropOther, with: ":8771/") }
            .map { $0.hasPrefix("file://") ? "file://…/" + ($0.split(separator: "/").last.map(String.init) ?? "") : $0 }
            .joined(separator: " ")
    }

    private func captureDrop(_ name: String) {
        let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? NSTemporaryDirectory()).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "phase-5.5b-\(name).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: The matrix

    private func dropMatrix() async {
        guard let host = AppDelegate.current?.debugPageHost else { return SpikeRunner.record("error", "drops: no page host") }
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "room-drop-fixture-\(UUID().uuidString.prefix(6)).html")
        try? "<!doctype html><title>Dropped file</title><h1>A dropped file</h1>".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        // Two Today tabs to drop between, the first shown in the card.
        let space = sidebar.activeSpaceID
        guard let base = try? store.addEntry(.today, url: Self.dropSite + "site.html?drop=base", title: "Base", space: space, window: sidebar.windowID),
              let below = try? store.addEntry(.today, url: Self.dropOther + "site.html?drop=below", title: "Below", space: space, window: sidebar.windowID)
        else { return SpikeRunner.record("error", "drops: no fixture tabs") }
        _ = below
        try? await Task.sleep(for: .milliseconds(300))

        for source in dropSources(file: fileURL) {
            await sidebarDrop(source)
            await cardDrop(source, base: base.id)
            await spaceIconDrop(source)
        }
        await essentialsDrop(dropSources(file: fileURL)[0])
        await essentialsDrop(dropSources(file: fileURL)[1])
        await textareaDrop()
    }

    /// Onto the list: over the top edge of one Today row, then of the next (the line moves: one tick), dropped there.
    private func sidebarDrop(_ source: DropSource) async {
        let today = store.today(space: sidebar.activeSpaceID, window: sidebar.windowID)
        guard today.count >= 2, let first = sidebar.debugRowPoint(today[0].id, fraction: 0.1),
              let second = sidebar.debugRowPoint(today[1].id, fraction: 0.1) else {
            return SpikeRunner.record("drop_sidebar_\(source.name)", "no rows")
        }
        let target = today[1].id
        let before = todayURLs
        let pasteboard = pasteboard(source)
        let info = FakeDraggingInfo(pasteboard: pasteboard, location: first, window: window)
        let ticks0 = Haptics.alignmentCount
        let op1 = sidebar.debugOutlineDragUpdated(info)
        let line1 = sidebar.debugInsertionLine
        info.location = second
        let op2 = sidebar.debugOutlineDragUpdated(info)
        let line2 = sidebar.debugInsertionLine
        let ticks = Haptics.alignmentCount - ticks0
        if source.name == "link" {
            captureDrop("drop-sidebar-line-light")
            NSApp.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(for: .milliseconds(400))
            _ = sidebar.debugOutlineDragUpdated(info)
            captureDrop("drop-sidebar-line-dark")
            NSApp.appearance = nil
            try? await Task.sleep(for: .milliseconds(300))
            _ = sidebar.debugOutlineDragUpdated(info)
        }
        let accepted = sidebar.debugOutlinePerformDrop(info)
        try? await Task.sleep(for: .milliseconds(300))
        let added = newToday(since: before)
        let entries = store.today(space: sidebar.activeSpaceID, window: sidebar.windowID)
        let targetIndex = entries.firstIndex { $0.id == target } ?? -1
        let addedIndices = entries.enumerated().filter { added.contains($0.element.currentURL ?? "") }.map(\.offset)
        let placedAbove = !addedIndices.isEmpty && addedIndices.allSatisfy { $0 < targetIndex } && addedIndices.max() == targetIndex - 1
        let selected = sidebar.selectedEntryID.flatMap(store.entry)?.currentURL
        let pass = accepted && added.count == source.expected && placedAbove && line1 != nil && line2 != nil && ticks == 1
        SpikeRunner.record("drop_sidebar_\(source.name)",
                           "\(pass ? "PASS" : "FAIL") op=\(op1.rawValue)/\(op2.rawValue) accepted=\(accepted) added=\(added.count)/\(source.expected) [\(short(added))] "
                           + "placed above the row under the line=\(placedAbove) line y=\(line1.map { "\(Int($0.midY))" } ?? "nil")→\(line2.map { "\(Int($0.midY))" } ?? "nil") "
                           + "ticks=\(ticks) selected first=\(selected == added.first)")
        // Leave the base tab shown for the card.
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// Onto the card's page (site.html, nothing editable under the pointer).
    private func cardDrop(_ source: DropSource, base: UUID) async {
        guard let host = AppDelegate.current?.debugPageHost else { return }
        sidebar.select(base)
        if let page = tabs.contents(for: base) { await waitLoaded(page, timeout: 10) }
        try? await Task.sleep(for: .milliseconds(400))
        let split = host.splitView
        let point = split.convert(NSPoint(x: split.bounds.midX, y: split.bounds.midY + 60), to: nil)
        let before = todayURLs
        let info = FakeDraggingInfo(pasteboard: pasteboard(source), location: point, window: window)
        let drop = split.contentDrop
        var ops: [UInt] = [drop.draggingEntered(info).rawValue]
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(150))
            info.location.x += 4
            ops.append(drop.draggingUpdated(info).rawValue)
        }
        let accepted = drop.prepareForDragOperation(info) && drop.performDragOperation(info)
        drop.concludeDragOperation(info)
        drop.draggingEnded(info)
        _ = await waitUntil(4) { self.newToday(since: before).count >= source.expected }
        try? await Task.sleep(for: .milliseconds(300))
        let added = newToday(since: before)
        let pass = added.count == source.expected
        SpikeRunner.record("drop_card_\(source.name)",
                           "\(pass ? "PASS" : "FAIL") ops=\(ops) accepted=\(accepted) by=\(drop.debugLastDrop ?? "nil") page view=\(drop.debugTargetClass ?? "nil") "
                           + "added=\(added.count)/\(source.expected) [\(short(added))]")
    }

    /// Onto a second space's icon: the tabs go to that space.
    private func spaceIconDrop(_ source: DropSource) async {
        let space = sidebar.activeSpaceID
        guard let profile = store.space(space)?.profileID else { return }
        let other = store.spaces.first { $0.id != space }?.id ?? (try? store.createSpace(name: "Drops", profile: profile))?.id
        guard let other else { return SpikeRunner.record("drop_space_\(source.name)", "no second space") }
        try? await Task.sleep(for: .milliseconds(300))
        guard let center = sidebar.debugSpaceIconCenter(other) else { return SpikeRunner.record("drop_space_\(source.name)", "no icon") }
        let before = store.today(space: other).count
        let footer = sidebar.debugFooter
        let info = FakeDraggingInfo(pasteboard: pasteboard(source), location: center, window: window)
        let op = footer.draggingEntered(info)
        let accepted = footer.performDragOperation(info)
        try? await Task.sleep(for: .milliseconds(200))
        let added = store.today(space: other).count - before
        let stayed = sidebar.activeSpaceID == space
        SpikeRunner.record("drop_space_\(source.name)", "\(added == source.expected && accepted ? "PASS" : "FAIL") op=\(op.rawValue) accepted=\(accepted) "
                           + "added to the other space=\(added)/\(source.expected) shown space unchanged=\(stayed)")
    }

    /// Onto the Essentials grid: one essential, the grid's insertion line, a tick.
    private func essentialsDrop(_ source: DropSource) async {
        let grid = sidebar.debugGridView
        guard let profile = store.space(sidebar.activeSpaceID)?.profileID else { return }
        let before = store.essentials(profile: profile).count
        // Over the first tile's leading half, then its trailing half (with tiles, the line moves: one tick).
        let tile = sidebar.debugTileFrames.first ?? grid.bounds
        let left = grid.convert(NSPoint(x: tile.minX + 4, y: tile.midY), to: nil)
        let right = grid.convert(NSPoint(x: tile.maxX - 4, y: tile.midY), to: nil)
        let info = FakeDraggingInfo(pasteboard: pasteboard(source), location: before == 0 ? grid.convert(NSPoint(x: grid.bounds.midX, y: grid.bounds.midY), to: nil) : left,
                                    window: window)
        let ticks0 = Haptics.alignmentCount
        let op = grid.draggingEntered(info)
        let line1 = sidebar.debugGridInsertion
        if before > 0 {
            info.location = right
            _ = grid.draggingUpdated(info)
        }
        let line2 = sidebar.debugGridInsertion
        let ticks = Haptics.alignmentCount - ticks0
        let accepted = grid.performDragOperation(info)
        try? await Task.sleep(for: .milliseconds(200))
        let added = store.essentials(profile: profile).count - before
        let lineOK = before == 0 || (line1 != nil && line2 != nil && ticks == 1)
        SpikeRunner.record("drop_essentials_\(source.name)", "\(added == source.expected && accepted && lineOK ? "PASS" : "FAIL") op=\(op.rawValue) accepted=\(accepted) "
                           + "added=\(added)/\(source.expected) essentials before=\(before) grid line=\(line1.map { "\(Int($0.midX))" } ?? "nil")→\(line2.map { "\(Int($0.midX))" } ?? "nil") ticks=\(ticks)")
    }

    /// Text onto a page's textarea: the page takes it (inserted), no tab.
    private func textareaDrop() async {
        guard let host = AppDelegate.current?.debugPageHost,
              let page = await open(URL(string: "http://127.0.0.1:8776/phase-5.5/ime.html")!, timeout: 10) else {
            return SpikeRunner.record("drop_card_text_into_field", "ime.html did not open")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let rect = await js(page, "(() => { const r = document.getElementById('t').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()")
        let numbers = rect.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 2 else { return SpikeRunner.record("drop_card_text_into_field", "no textarea rect (\(rect))") }
        let view = page.nativeView
        let local = NSPoint(x: numbers[0], y: view.isFlipped ? numbers[1] : view.bounds.height - numbers[1])
        let point = view.convert(local, to: nil)
        let before = todayURLs
        let info = FakeDraggingInfo(pasteboard: pasteboard(DropSource(name: "text", expected: 0) { $0.setString("dropped words", forType: .string) }),
                                    location: point, window: window)
        let drop = host.splitView.contentDrop
        var ops: [UInt] = [drop.draggingEntered(info).rawValue]
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(150))
            ops.append(drop.draggingUpdated(info).rawValue)
        }
        let accepted = drop.prepareForDragOperation(info) && drop.performDragOperation(info)
        drop.concludeDragOperation(info)
        drop.draggingEnded(info)
        try? await Task.sleep(for: .milliseconds(600))
        let value = await js(page, "document.getElementById('t').value")
        let added = newToday(since: before)
        SpikeRunner.record("drop_card_text_into_field", "\(value.contains("dropped words") && added.isEmpty ? "PASS" : "FAIL") ops=\(ops) accepted=\(accepted) "
                           + "by=\(drop.debugLastDrop ?? "nil") value=\(value) tabs added=\(added.count)")
    }

    // MARK: AppKit's routing

    /// Which view AppKit makes the destination of a drag of `types` at a window point: its own lookup
    /// (`-[NSView _hitTest:dragTypes:]`, the private method the drag machinery uses; it ignores `hitTest:`),
    /// so the card's drop view is proved to sit in front of the engine's view without a real drag.
    private func destination(at point: NSPoint, types: [NSPasteboard.PasteboardType]) -> String {
        let selector = NSSelectorFromString("_hitTest:dragTypes:")
        guard let content = window.contentView, let method = class_getInstanceMethod(NSView.self, selector) else { return "no lookup" }
        typealias Lookup = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSPoint>, NSSet) -> AnyObject?
        let lookup = unsafeBitCast(method_getImplementation(method), to: Lookup.self)
        var local = point  // the content view's superview (the frame view) has window coordinates
        return lookup(content, selector, &local, NSSet(array: types.map(\.rawValue))).map { String(describing: Swift.type(of: $0)) } ?? "nil"
    }

    private func dropRouting() async {
        guard let host = AppDelegate.current?.debugPageHost else { return }
        guard let page = await open(URL(string: Self.dropSite + "site.html?drop=routing")!, timeout: 10) else { return }
        _ = page
        try? await Task.sleep(for: .milliseconds(400))
        let split = host.splitView
        let card = split.convert(NSPoint(x: split.bounds.midX, y: split.bounds.midY), to: nil)
        let url = destination(at: card, types: [.URL])
        let text = destination(at: card, types: [.string])
        let custom = destination(at: card, types: [NSPasteboard.PasteboardType("org.chromium.web-custom-data")])
        let entryHidden = destination(at: card, types: [SidebarDragTypes.entry, .URL])
        split.dropOverlay.isHidden = false
        let entryShown = destination(at: card, types: [SidebarDragTypes.entry, .URL])
        split.dropOverlay.isHidden = true
        let today = store.today(space: sidebar.activeSpaceID, window: sidebar.windowID)
        let row = today.first.flatMap { sidebar.debugRowPoint($0.id, fraction: 0.5) }.map { destination(at: $0, types: [.URL]) } ?? "no row"
        let pass = url == "CardDropView" && text == "CardDropView" && custom == "WebContentsViewCocoa" && entryShown == "SplitDropOverlayView"
        SpikeRunner.record("drop_routing", "\(pass ? "PASS" : "FAIL") over the card: a URL → \(url), text → \(text), only Chromium's custom type → \(custom), "
                           + "a sidebar entry with this window's drag overlay hidden → \(entryHidden), shown → \(entryShown); over a row: a URL → \(row)")
    }

    // MARK: Task 5's rechecks

    /// The overflow indicator (spec §I.11): the selected row scrolled out shows the line at that edge; a click brings it back.
    private func overflowRecheck() async {
        let space = sidebar.activeSpaceID
        var ids: [UUID] = []
        for index in 0..<40 {
            if let entry = try? store.addEntry(.today, url: Self.dropSite + "site.html?row=\(index)", title: "Row \(index)", space: space,
                                               window: sidebar.windowID) { ids.append(entry.id) }
        }
        guard let selected = ids.first(where: { sidebar.debugRowPoint($0, fraction: 0.5) != nil }) else { return }
        sidebar.select(selected)
        try? await Task.sleep(for: .milliseconds(500))
        let outline = sidebar.debugOutline
        let top = sidebar.debugRowVisible(selected) ? "visible" : "hidden"
        outline.scrollRowToVisible(outline.numberOfRows - 1)
        try? await Task.sleep(for: .milliseconds(400))
        let scrolled = sidebar.bodyView.debugOverflow
        captureDrop("overflow-line-light")
        sidebar.bodyView.debugClickOverflow()
        try? await Task.sleep(for: .milliseconds(700))
        let back = sidebar.bodyView.debugOverflow
        let visible = sidebar.debugRowVisible(selected)
        captureDrop("overflow-clicked-light")
        // The selected row below the list: the bottom line.
        if let last = ids.last { sidebar.select(last) }
        try? await Task.sleep(for: .milliseconds(300))
        outline.scrollRowToVisible(0)
        try? await Task.sleep(for: .milliseconds(400))
        let below = sidebar.bodyView.debugOverflow
        let pass = scrolled.top && !scrolled.bottom && !back.top && !back.bottom && visible && below.bottom && !below.top
        SpikeRunner.record("overflow", "\(pass ? "PASS" : "FAIL") selected row at start \(top); scrolled to the end: top=\(scrolled.top) bottom=\(scrolled.bottom); "
                           + "after the click: top=\(back.top) bottom=\(back.bottom) row visible=\(visible); last row selected, list at the top: bottom=\(below.bottom) top=\(below.top)")
        for id in ids { _ = try? store.remove(id) }
    }

    /// Hover sublabels (spec §I.3, §I.4) on a changed pinned entry: the live title; over the icon what a click does; ⌘ on the selected row only.
    private func sublabelRecheck() async {
        let space = sidebar.activeSpaceID
        guard let pinned = try? store.addEntry(.pinned, url: Self.dropSite + "site.html", title: "Pinned Home", space: space) else { return }
        sidebar.select(pinned.id)
        guard let page = tabs.contents(for: pinned.id) else { return SpikeRunner.record("sublabels", "FAIL no page") }
        await waitLoaded(page, timeout: 10)
        _ = await js(page, "location.href = '\(Self.dropSite)site.html?moved=1'; 0")
        try? await Task.sleep(for: .milliseconds(1200))
        await waitLoaded(page, timeout: 10)
        var lines: [String] = []
        sidebar.debugHover(pinned.id)
        try? await Task.sleep(for: .milliseconds(250))
        let title = sidebar.debugSublabel(pinned.id)
        lines.append("row=\(title ?? "nil")")
        captureDrop("sublabel-title-light")
        sidebar.debugHover(pinned.id, onIcon: true)
        try? await Task.sleep(for: .milliseconds(250))
        let icon = sidebar.debugSublabel(pinned.id)
        lines.append("icon=\(icon ?? "nil")")
        captureDrop("sublabel-reset-light")
        sidebar.debugHover(pinned.id, onIcon: true, command: true)
        try? await Task.sleep(for: .milliseconds(250))
        let command = sidebar.debugSublabel(pinned.id)
        lines.append("icon+⌘ selected=\(command ?? "nil")")
        captureDrop("sublabel-separate-light")
        // Another row selected: ⌘ over the changed row's icon still resets.
        if let other = try? store.addEntry(.today, url: Self.dropOther + "site.html?other", title: "Other", space: space, window: sidebar.windowID) {
            sidebar.select(other.id)
            try? await Task.sleep(for: .milliseconds(500))
        }
        sidebar.debugHover(pinned.id, onIcon: true, command: true)
        try? await Task.sleep(for: .milliseconds(250))
        let unselected = sidebar.debugSublabel(pinned.id)
        lines.append("icon+⌘ not selected=\(unselected ?? "nil")")
        sidebar.debugHover(nil)
        try? await Task.sleep(for: .milliseconds(250))
        let gone = sidebar.debugSublabel(pinned.id)
        lines.append("no hover=\(gone ?? "nil")")
        let pass = title != nil && icon == "Back to pinned URL" && command == "Separate from pinned tab" && unselected == "Back to pinned URL" && gone == nil
        SpikeRunner.record("sublabels", "\(pass ? "PASS" : "FAIL") " + lines.joined(separator: "; "))
    }

    /// The status pill (spec §I.14) bottom-left, then dodged to the right with the pointer near it (the
    /// pointer path itself: `chromesurfaces2 -RoomSpikeOnly status`'s `status_pill_dodge`).
    private func pillCaptures() async {
        guard let pill = AppDelegate.current?.statusPill, await open(URL(string: Self.dropSite + "site.html?pill")!, timeout: 10) != nil else { return }
        try? await Task.sleep(for: .milliseconds(400))
        pill.setStatus(Self.dropSite + "an/article/on/this/site.html?with=a&query=that&is=long")
        _ = await waitUntil(2) { pill.state.isVisible }
        let leading = pill.pillView.map { NSStringFromRect($0.frame) } ?? "nil"
        captureDrop("status-pill-light")
        pill.state.pointerMoved(nearLeading: true, nearTrailing: false)
        try? await Task.sleep(for: .milliseconds(300))
        let trailing = pill.pillView.map { NSStringFromRect($0.frame) } ?? "nil"
        captureDrop("status-pill-dodged-light")
        SpikeRunner.record("status_pill_captures", "\(pill.state.side == .trailing ? "PASS" : "FAIL") leading \(leading) → \(trailing)")
        pill.setStatus(nil)
    }

    // MARK: Haptics (task 6)

    /// Pointer moves over the sidebar's rows (hover states change): no tick.
    private func hoverTicks() async {
        let today = store.today(space: sidebar.activeSpaceID, window: sidebar.windowID)
        let ticks0 = Haptics.alignmentCount
        var hovered: Set<String> = []
        for entry in today.prefix(6) {
            guard let point = sidebar.debugRowPoint(entry.id, fraction: 0.5),
                  let event = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { continue }
            window.sendEvent(event)
            sidebar.debugOutline.mouseMoved(with: event)
            try? await Task.sleep(for: .milliseconds(120))
            if let id = sidebar.debugHoveredEntry.id { hovered.insert(id.uuidString) }
        }
        sidebar.debugHover(nil)
        let ticks = Haptics.alignmentCount - ticks0
        SpikeRunner.record("haptics_hover", "\(ticks == 0 ? "PASS" : "FAIL") rows hovered=\(hovered.count) ticks=\(ticks)")
    }

    /// The split divider: dragged near the equal point it snaps (ratio 0.5, one tick); away, no tick; back, one more.
    private func splitSnap() async {
        guard let host = AppDelegate.current?.debugPageHost else { return }
        let space = sidebar.activeSpaceID
        guard let a = try? store.addEntry(.today, url: Self.dropSite + "site.html?pane=a", title: "A", space: space, window: sidebar.windowID),
              let b = try? store.addEntry(.today, url: Self.dropOther + "site.html?pane=b", title: "B", space: space, window: sidebar.windowID)
        else { return }
        sidebar.select(a.id)
        try? await Task.sleep(for: .milliseconds(400))
        sidebar.joinIntoSplit(b.id, with: a.id)
        try? await Task.sleep(for: .milliseconds(600))
        let split = host.splitView
        guard split.isSplit else { return SpikeRunner.record("haptics_split", "FAIL no split") }
        let width = split.bounds.width
        let ticks0 = Haptics.alignmentCount
        var lines: [String] = []
        for fraction in [0.30, 0.497, 0.503, 0.62, 0.501] {
            let ratios = split.debugDragDivider(to: width * fraction) ?? []
            lines.append(String(format: "%.3f→%@ ticks=%d", fraction, ratios.map { String(format: "%.3f", $0) }.joined(separator: "/"),
                                Haptics.alignmentCount - ticks0))
            try? await Task.sleep(for: .milliseconds(80))
        }
        captureDrop("split-snap-light")
        split.debugEndDividerDrag()
        let ticks = Haptics.alignmentCount - ticks0
        SpikeRunner.record("haptics_split", "\(ticks == 2 ? "PASS" : "FAIL") \(lines.joined(separator: "; ")) (expected 2: arriving at the equal point twice)")
    }
}

/// A drag over a Room view, made in the process: the pasteboard, the pointer (window coordinates) and the
/// operations a drag from another app offers. Room's drop code reads only these.
final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var location: NSPoint
    let window: NSWindow
    private static var sequence = 9_000

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
        draggingPasteboard = pasteboard
        self.location = location
        self.window = window
        Self.sequence += 1
        draggingSequenceNumber = Self.sequence
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.copy, .link, .generic] }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
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
