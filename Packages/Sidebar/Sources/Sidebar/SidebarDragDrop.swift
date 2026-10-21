import AppKit
import Chrome
import Design
import Model
import Omnibox
import Store

/// Drag and drop (spec §A.9, §A.6 folders, §I.7 content): reorder with the
/// insertion line and a lifted row; conversion across sections through
/// `SidebarStore.move`; the Essentials cap (badge, shake, refused); onto a
/// folder or a pinned entry after a 500 ms hold; ⌥-drag duplicates; URLs
/// and text from outside; group drags of the multi-selection; a haptic tick
/// whenever the insertion line moves. A drag of one entry that ends beyond
/// `WindowMetrics.dragOutDistance` outside the window opens it in a new
/// window at the drop point (4.8a, `DragOutRule`).
/// The sidebar's own drag types, for drop targets outside it (the card's split drop zones, spec §D).
public enum SidebarDragTypes {
    /// One sidebar entry: its id.
    public static let entry = NSPasteboard.PasteboardType("app.room.desktop.sidebar-entry")
    /// A split's row: all its panes' ids, in order.
    public static let splitPanes = NSPasteboard.PasteboardType("app.room.desktop.split-panes")
}

extension SidebarController {
    /// One sidebar entry on the pasteboard: its id for drops on the sidebar,
    /// its URL for every other app.
    static let entryPasteboardType = SidebarDragTypes.entry

    static let acceptedDragTypes: [NSPasteboard.PasteboardType] = [entryPasteboardType, .URL, .fileURL, .string]

    /// What a drag in progress is over and what it would do.
    struct DragState {
        /// Entries being dragged from this sidebar (empty for drags from outside).
        var ids: [UUID] = []
        /// The row (and whether its middle zone) the pointer rests on, and since when.
        var hoverKey: HoverKey?
        var hoverSince: TimeInterval = 0
        var target: DropRules.Target?
        var gridDrop: DropRules.GridDrop?
        /// The grid refused the drop for the cap: releasing shakes it.
        var refusedForCap = false
        /// Where feedback was last shown, for the haptic tick when it moves.
        var feedback: Feedback?
    }

    struct HoverKey: Equatable {
        var row: Int?
        var middle: Bool
    }

    enum Feedback: Equatable {
        case line(DropRules.Line)
        case row(Int)
        case grid(DropRules.GridDrop)
    }

    func pasteboardItem(for entry: Entry) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(entry.id.uuidString, forType: Self.entryPasteboardType)
        if let url = entry.currentURL {
            item.setString(url, forType: .URL)
            item.setString(url, forType: .string)
        }
        return item
    }

    /// A split's row carries all its panes, in order (spec §D: the split moves as one row).
    static let splitPanesPasteboardType = SidebarDragTypes.splitPanes

    func pasteboardItem(forSplit group: SplitGroup) -> NSPasteboardItem {
        let members = sidebar.splitMembers(group.id)
        let anchor = SplitRules.anchor(of: members).flatMap(sidebar.entry) ?? members[0]
        let item = pasteboardItem(for: anchor)
        item.setString(members.map(\.id.uuidString).joined(separator: ","), forType: Self.splitPanesPasteboardType)
        return item
    }

    /// The sidebar entries on a drag's pasteboard (none if it came from elsewhere).
    func draggedEntryIDs(_ info: any NSDraggingInfo) -> [UUID] {
        (info.draggingPasteboard.pasteboardItems ?? []).flatMap { item -> [UUID] in
            if let panes = item.string(forType: Self.splitPanesPasteboardType) {
                return panes.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            }
            return item.string(forType: Self.entryPasteboardType).flatMap(UUID.init(uuidString:)).map { [$0] } ?? []
        }.filter { sidebar.entry($0) != nil }
    }

    /// ⌥ held: the source offers only copy.
    private func isCopy(_ info: any NSDraggingInfo) -> Bool {
        !info.draggingSourceOperationMask.contains(.move) && info.draggingSourceOperationMask.contains(.copy)
    }

    // MARK: Starting a drag (outline rows; tiles below)

    func draggingSessionWillBegin(_ session: NSDraggingSession, ids: [UUID]) {
        drag = DragState(ids: ids)
        onEntryDrag?(true)
        setDragging(ids, dimmed: true)
        if tree.essentialIDs.isEmpty {
            grid.showsDropSlot = true
            bodyView.needsLayout = true
        }
    }

    func draggingSessionEnded() {
        onEntryDrag?(false)
        if let ids = drag?.ids { setDragging(ids, dimmed: false) }
        drag = nil
        hideDropFeedback()
        if grid.showsDropSlot {
            grid.showsDropSlot = false
            bodyView.needsLayout = true
        }
    }

    /// Rows being dragged stay in place, dimmed, until the drop.
    func setDragging(_ ids: [UUID], dimmed: Bool) {
        let alpha = dimmed ? SidebarMetrics.draggedRowAlpha : 1
        for id in ids {
            if let node = tree.displayedNode(for: id) {
                let row = outline.row(forItem: node)
                if row >= 0 { outline.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = alpha }
            }
            grid.tile(for: id)?.alphaValue = alpha
        }
    }

    /// Lifted images for the outline's dragging items (spec §A.9: scale 1.03, shadow).
    func liftDraggingItems(_ session: NSDraggingSession) {
        session.enumerateDraggingItems(options: [], for: outline, classes: [NSPasteboardItem.self], searchOptions: [:]) {
            [weak self] item, _, _ in
            guard let self, let pasteboardItem = item.item as? NSPasteboardItem,
                  let id = pasteboardItem.string(forType: Self.entryPasteboardType).flatMap(UUID.init(uuidString:)),
                  let entry = sidebar.entry(id), let node = tree.displayedNode(for: id) else { return }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            let pill = SidebarRowView.pillRect(in: outline.rect(ofRow: row))
            let image = DragImage.row(entry, page: pageState(id), size: pill.size, appearance: outline.effectiveAppearance)
            item.setDraggingFrame(DragImage.frame(for: image, around: pill), contents: image)
        }
    }

    /// A press on a tile moved: drag it (with the rest of an Essentials multi-selection).
    func tileDragStarted(_ id: UUID, event: NSEvent) {
        let ids = multiSelection.section == .essentials && multiSelection.contains(id) ? multiSelection.ids : [id]
        let frames = Dictionary(uniqueKeysWithValues: zip(grid.order, grid.tileFrames))
        let items: [NSDraggingItem] = ids.compactMap { id in
            guard let entry = sidebar.entry(id), let frame = frames[id] else { return nil }
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem(for: entry))
            let image = DragImage.tile(entry, page: pageState(id), size: frame.size, appearance: grid.effectiveAppearance)
            item.setDraggingFrame(DragImage.frame(for: image, around: frame), contents: image)
            return item
        }
        guard !items.isEmpty else { return }
        let session = grid.beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        draggingSessionWillBegin(session, ids: ids)
    }

    // MARK: Over the outline

    /// What a drop at the pointer would do (validateDrop).
    func outlineDragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        if drag == nil { drag = DragState() }
        let ids = draggedEntryIDs(info)
        let external = ids.isEmpty ? SidebarDrop.urls(from: info.draggingPasteboard) : []
        guard !ids.isEmpty || !external.isEmpty else {
            hideDropFeedback()
            return []
        }
        let point = outline.convert(info.draggingLocation, from: nil)
        let rowIndex = outline.row(at: point)
        let row = rowIndex >= 0 ? rowIndex : nil
        let fraction = row.map { (point.y - outline.rect(ofRow: $0).minY) / max(1, outline.rect(ofRow: $0).height) } ?? 0
        let key = HoverKey(row: row, middle: DropRules.isMiddle(fraction))
        let now = ProcessInfo.processInfo.systemUptime
        if drag?.hoverKey != key {
            drag?.hoverKey = key
            drag?.hoverSince = now
        }
        let held = key.middle && now - (drag?.hoverSince ?? now) >= DropRules.holdDelay
        let single = ids.count == 1 && sidebar.entry(ids[0])?.kind != .folder
        let draggedKind = single ? sidebar.entry(ids[0])?.kind : nil
        func target(held: Bool) -> DropRules.Target {
            DropRules.target(row.map(dropRow), at: row ?? outline.numberOfRows, rowCount: outline.numberOfRows, fraction: fraction,
                             held: held, space: tree.spaceID, single: single, draggedKind: draggedKind)
        }
        let copy = isCopy(info)
        var chosen = target(held: held)
        if !isValid(chosen, ids: ids, copy: copy, externalCount: external.count) {
            chosen = target(held: false)
            guard isValid(chosen, ids: ids, copy: copy, externalCount: external.count) else {
                hideDropFeedback()
                drag?.target = nil
                return []
            }
        }
        drag?.target = chosen
        showFeedback(for: chosen)
        return ids.isEmpty || copy ? .copy : .move
    }

    func outlineAcceptDrop(_ info: any NSDraggingInfo) -> Bool {
        guard let target = drag?.target else { return false }
        let ids = draggedEntryIDs(info)
        let external = ids.isEmpty ? SidebarDrop.urls(from: info.draggingPasteboard) : []
        hideDropFeedback()
        return performDrop(target, ids: ids, copy: isCopy(info), external: external)
    }

    func outlineDragExited() {
        hideDropFeedback()
        drag?.hoverKey = nil
    }

    /// One outline row as `DropRules` sees it.
    private func dropRow(_ row: Int) -> DropRules.Row {
        guard let node = outline.item(atRow: row) as? OutlineNode else { return .newTab }
        switch node.kind {
        case .spaceTitle: return .spaceTitle
        case .separator: return .separator
        case .newTab: return .newTab
        case .entry(let id):
            guard let entry = sidebar.entry(id) else { return .newTab }
            let depth = entry.kind == .today ? 0 : max(0, outline.level(forRow: row) - 1)
            let showsChildren = entry.kind == .folder && !tree.children(of: node).isEmpty
            return .entry(id: id, kind: entry.kind, container: entry.container, index: entry.position, depth: depth,
                          showsChildren: showsChildren)
        }
    }

    private func isValid(_ target: DropRules.Target, ids: [UUID], copy: Bool, externalCount: Int) -> Bool {
        let space = tree.spaceID
        switch target {
        case .insert(let container, _, _):
            return canDrop(ids, into: container, copy: copy, externalCount: externalCount)
        case .intoFolder(let folder, _):
            return !ids.contains(folder) && canDrop(ids, into: .pinned(space: space, folder: folder), copy: copy, externalCount: externalCount)
        case .newFolder(let other, _):
            guard ids.count == 1, ids[0] != other, !copy, let entry = sidebar.entry(other) else { return false }
            return (try? FolderRules.validateNewFolder(in: entry.folderID, in: sidebar.entries)) != nil
        case .join(let other, _):
            return canJoin(ids, with: other) && !copy
        }
    }

    private func canDrop(_ ids: [UUID], into container: Container, copy: Bool, externalCount: Int) -> Bool {
        if ids.isEmpty {
            guard container.section == .essentials else { return true }
            return essentialsCount + externalCount <= EntryRules.essentialsCap
        }
        if copy {
            guard ids.allSatisfy({ sidebar.entry($0)?.kind != .folder }) else { return false }
            if container.section == .essentials { return essentialsCount + ids.count <= EntryRules.essentialsCap }
            return true
        }
        return (try? sidebar.canMove(ids, to: local(container)).get()) != nil
    }

    var essentialsCount: Int {
        tree.space.map { sidebar.essentials(profile: $0.profileID).count } ?? 0
    }

    // MARK: Over the Essentials grid

    func gridDragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        if drag == nil { drag = DragState() }
        guard let space = tree.space else { return [] }
        let ids = draggedEntryIDs(info)
        let external = ids.isEmpty ? SidebarDrop.urls(from: info.draggingPasteboard) : []
        guard !ids.isEmpty || !external.isEmpty else { return [] }
        hideOutlineFeedback()
        let container = Container.essentials(profile: space.profileID)
        let copy = isCopy(info)
        let operation: NSDragOperation = ids.isEmpty || copy ? .copy : .move
        if canDrop(ids, into: container, copy: copy, externalCount: external.count) {
            let drop = DropRules.gridDrop(frames: grid.tileFrames, point: grid.convert(info.draggingLocation, from: nil))
            drag?.gridDrop = drop
            drag?.refusedForCap = false
            grid.showFullBadge(nil)
            grid.showInsertion(drop)
            tick(.grid(drop))
            return operation
        }
        drag?.gridDrop = nil
        grid.showInsertion(nil)
        // Over the cap: the badge now, the shake on release (spec §A.9). Folders are simply refused.
        let folders = ids.contains { sidebar.entry($0)?.kind == .folder }
        drag?.refusedForCap = !folders
        guard !folders else { return [] }
        grid.showFullBadge("\(essentialsCount)/\(EntryRules.essentialsCap)")
        return operation
    }

    func gridPerformDrop(_ info: any NSDraggingInfo) -> Bool {
        defer { gridDragExited() }
        guard let space = tree.space else { return false }
        if drag?.refusedForCap == true {
            grid.shake()
            return false
        }
        guard let drop = drag?.gridDrop else { return false }
        let ids = draggedEntryIDs(info)
        let external = ids.isEmpty ? SidebarDrop.urls(from: info.draggingPasteboard) : []
        let target = DropRules.Target.insert(.essentials(profile: space.profileID), index: drop.index, line: .init(boundary: 0, depth: 0))
        return performDrop(target, ids: ids, copy: isCopy(info), external: external)
    }

    func gridDragExited() {
        grid.showInsertion(nil)
        grid.showFullBadge(nil)
        drag?.gridDrop = nil
        if drag?.feedback.map({ if case .grid = $0 { true } else { false } }) == true { drag?.feedback = nil }
    }

    // MARK: Feedback

    func showFeedback(for target: DropRules.Target) {
        switch target {
        case .insert(_, _, let line):
            setDropTargetRow(nil)
            let rows = outline.numberOfRows
            let y: CGFloat
            if rows == 0 {
                y = 0
            } else if line.boundary < rows {
                y = outline.rect(ofRow: line.boundary).minY
            } else {
                y = outline.rect(ofRow: rows - 1).maxY
            }
            let x = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset + CGFloat(line.depth) * SidebarMetrics.folderIndent
            outline.dropIndicator.show(y: y, x: x, maxX: outline.bounds.width - SidebarMetrics.rowHorizontalInset)
            tick(.line(line))
        case .intoFolder(_, let row), .newFolder(_, let row), .join(_, let row):
            outline.dropIndicator.show(y: nil, x: 0, maxX: 0)
            setDropTargetRow(row)
            tick(.row(row))
        }
    }

    /// The haptic tick when the insertion line moves (spec §A.9).
    private func tick(_ feedback: Feedback) {
        defer { drag?.feedback = feedback }
        guard let previous = drag?.feedback, previous != feedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func setDropTargetRow(_ row: Int?) {
        outline.enumerateAvailableRowViews { rowView, index in
            (rowView as? SidebarRowView)?.isDropTarget = index == row
        }
    }

    private func hideOutlineFeedback() {
        outline.dropIndicator.show(y: nil, x: 0, maxX: 0)
        setDropTargetRow(nil)
    }

    func hideDropFeedback() {
        hideOutlineFeedback()
        grid.showInsertion(nil)
        grid.showFullBadge(nil)
        drag?.feedback = nil
    }

    // MARK: Drop

    /// Applies a drop; `ids` are sidebar entries, `external` URLs from outside.
    @discardableResult
    func performDrop(_ target: DropRules.Target, ids: [UUID], copy: Bool, external: [String]) -> Bool {
        let space = tree.spaceID
        do throws(SidebarError) {
            switch target {
            case .insert(let container, let index, _):
                try drop(ids, external: external, into: container, at: index, copy: copy)
            case .intoFolder(let folder, _):
                try drop(ids, external: external, into: .pinned(space: space, folder: folder), at: .max, copy: copy)
            case .newFolder(let other, _):
                guard let entry = sidebar.entry(other) else { return false }
                let folder = try sidebar.addFolder(name: CommandName.newFolder, space: space, parent: entry.folderID, at: entry.position)
                do throws(SidebarError) {
                    try sidebar.move([other] + ids, to: .pinned(space: space, folder: folder.id), insertingAt: 0)
                } catch {
                    _ = try? sidebar.remove(folder.id)
                    throw error
                }
                beginRename(folder.id)
            case .join(let other, _):
                guard let id = ids.first else { return false }
                try join(id, with: other)
            }
        } catch {
            showRefusal(error)
            return false
        }
        retainMultiSelection()
        return true
    }

    private func drop(_ ids: [UUID], external: [String], into container: Container, at index: Int, copy: Bool) throws(SidebarError) {
        let container = local(container)
        if !ids.isEmpty {
            if copy {
                try sidebar.duplicate(ids, to: container, at: index)
            } else {
                try sidebar.move(ids, to: container, insertingAt: index)
            }
            return
        }
        // From outside: new entries of the target's kind at the drop position; the first opens.
        let space = tree.spaceID
        let kind: EntryKind
        var folder: UUID?
        switch container {
        case .essentials: kind = .essential
        case .pinned(_, let parent):
            kind = .pinned
            folder = parent
        case .today: kind = .today
        }
        var first: Entry?
        for (offset, url) in external.enumerated() {
            let entry = try sidebar.addEntry(kind, url: url, space: space, folder: folder, window: windowID,
                                             at: index == .max ? nil : index + offset)
            if first == nil { first = entry }
        }
        if let first { select(first.id) }
    }

    func showRefusal(_ error: SidebarError) {
        switch error {
        case .conversion(.essentialsFull(let cap)):
            grid.shake()
            toasts?.show(Toast(id: "essentials-full", symbol: .info, message: "Essentials are full (\(cap)/\(cap))"))
        case .folder(.tooDeep(let max)):
            toasts?.show(Toast(id: "folder-depth", symbol: .info, message: "Folders nest at most \(max) deep"))
        case .splitFull:
            showSplitFullToast()
        default:
            NSSound.beep()
        }
    }
}

extension SidebarController: NSDraggingSource {
    /// Outside Room an entry offers nothing (4.8a): the desktop and Finder
    /// would otherwise take its URL as a file, and a drop there is the drag
    /// out to a new window (spec §A.9). Other Room windows' sidebars take it.
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : []
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = drag?.ids ?? []
        draggingSessionEnded()
        dragEnded(ids, at: screenPoint, operation: operation)
    }
}

extension SidebarController {
    /// A drag that no target took (`operation` empty), of one entry, ending
    /// beyond the drag-out distance outside the window: a new window there.
    func dragEnded(_ ids: [UUID], at screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation.isEmpty, ids.count == 1, let id = ids.first, let frame = outline.window?.frame,
              DragOutRule.opensWindow(at: screenPoint, windowFrame: frame), let onOpenInNewWindow else { return }
        onOpenInNewWindow(id, screenPoint)
    }
}

/// The drag out of the window (spec §A.9), as a pure rule.
public enum DragOutRule {
    /// The drop point is more than `distance` outside `windowFrame` (screen coordinates).
    public static func opensWindow(at point: NSPoint, windowFrame: NSRect, distance: CGFloat = WindowMetrics.dragOutDistance) -> Bool {
        !windowFrame.insetBy(dx: -distance, dy: -distance).contains(point)
    }

    /// The new window's frame for a drop at `point`: `size`, its top-left
    /// corner at the drop point, kept on the screen that holds the point.
    public static func frame(droppedAt point: NSPoint, size: NSSize, screen: NSRect) -> NSRect {
        var frame = NSRect(x: point.x, y: point.y - size.height, width: size.width, height: size.height)
        guard !screen.isEmpty else { return frame }
        frame.size.width = min(frame.width, screen.width)
        frame.size.height = min(frame.height, screen.height)
        frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        return frame
    }

    /// ⌘N's and "Open in New Window"'s frame: `key` moved right and down by the cascade offset, kept on `screen`.
    public static func cascaded(from key: NSRect, screen: NSRect, offset: CGFloat = WindowMetrics.cascadeOffset) -> NSRect {
        frame(droppedAt: NSPoint(x: key.minX + offset, y: key.maxY - offset), size: key.size, screen: screen)
    }
}

/// Drops from outside the window.
enum SidebarDrop {
    static func urls(from pasteboard: NSPasteboard) -> [String] { URLFixup.dropURLs(from: pasteboard) }
}

/// The images under the pointer while dragging: the row lifted onto a pill
/// (scale 1.03, shadow; spec §A.9) or the Essentials tile.
enum DragImage {
    /// Room around the content for the shadow.
    static var margin: CGFloat { SidebarMetrics.dragShadowRadius * 2 }

    static func row(_ entry: Entry, page: EntryPageState, size: NSSize, appearance: NSAppearance) -> NSImage {
        image(size: size, appearance: appearance) { rect in
            let inset = SidebarMetrics.rowContentInset
            let icon = SidebarMetrics.faviconSize
            let iconRect = NSRect(x: rect.minX + inset, y: rect.midY - icon / 2, width: icon, height: icon)
            drawIcon(entry, page: page, in: iconRect)
            let title = EntryLabel.title(entry) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: Typography.sidebarRow, .foregroundColor: NSColor.labelColor]
            let height = title.size(withAttributes: attributes).height
            let x = iconRect.maxX + SidebarMetrics.faviconTitleGap
            title.draw(with: NSRect(x: x, y: rect.midY - height / 2, width: max(0, rect.maxX - inset - x), height: height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        }
    }

    static func tile(_ entry: Entry, page: EntryPageState, size: NSSize, appearance: NSAppearance) -> NSImage {
        image(size: size, appearance: appearance) { rect in
            let icon = SidebarMetrics.essentialIconSize
            drawIcon(entry, page: page, in: NSRect(x: rect.midX - icon / 2, y: rect.midY - icon / 2, width: icon, height: icon))
        }
    }

    /// Where the image goes so the lifted content stays centred on `rect`.
    static func frame(for image: NSImage, around rect: NSRect) -> NSRect {
        NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2, width: image.size.width,
               height: image.size.height)
    }

    private static func image(size: NSSize, appearance: NSAppearance, content: @escaping (NSRect) -> Void) -> NSImage {
        let scale = SidebarMetrics.dragLiftScale
        let lifted = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let total = NSSize(width: lifted.width + 2 * margin, height: lifted.height + 2 * margin)
        return NSImage(size: total, flipped: true) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let pill = NSRect(x: margin, y: margin, width: lifted.width, height: lifted.height)
                let shape = NSBezierPath(roundedRect: pill, xRadius: SidebarMetrics.pillCornerRadius, yRadius: SidebarMetrics.pillCornerRadius)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = SidebarMetrics.dragShadowRadius
                shadow.shadowOffset = NSSize(width: 0, height: -2)
                shadow.shadowColor = NSColor.black.withAlphaComponent(SidebarMetrics.dragShadowOpacity)
                shadow.set()
                // An opaque base so the translucent pill colour still reads off the sidebar.
                (appearance.isDark ? Palette.dragImageFillDark : NSColor.white).setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
                Palette.sidebarSelection.setFill()
                shape.fill()
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: pill.minX, yBy: pill.minY)
                transform.scale(by: scale)
                transform.concat()
                content(NSRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    private static func drawIcon(_ entry: Entry, page: EntryPageState, in rect: NSRect) {
        if entry.kind == .folder {
            let symbol = (entry.isCollapsed ? Symbol.folder : Symbol.folderOpen).image(.folder)
            symbol?.withSymbolConfiguration(.init(hierarchicalColor: .secondaryLabelColor))?
                .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if let favicon = page.favicon {
            favicon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            FaviconView.drawLetterTile(EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry), in: rect)
        }
    }
}

#if DEBUG
/// A drag over the outline as AppKit would describe it, for spikes that cannot
/// move the real pointer (5.6a: a folder dropped onto a folder, B-117).
final class DebugDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    weak var window: NSWindow?

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow?) {
        draggingPasteboard = pasteboard
        draggingLocation = location
        self.window = window
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { [.move, .copy] }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}

extension SidebarController {
    /// Drags `ids` over the outline to `point` (window coordinates), rests there `rest` seconds
    /// (the hold is measured as a real drag's is), then drops: the outline's own validate and accept.
    public func debugDrop(_ ids: [UUID], at point: NSPoint, rest: TimeInterval) async -> (accepted: Bool, target: String) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("room.debug.drag.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(ids.compactMap(sidebar.entry).map { pasteboardItem(for: $0) })
        let info = DebugDraggingInfo(pasteboard: pasteboard, location: point, window: outline.window)
        drag = DragState(ids: ids)
        _ = outlineDragUpdated(info)
        try? await Task.sleep(for: .seconds(rest))
        _ = outlineDragUpdated(info)
        let target = drag?.target.map { "\($0)" } ?? "none"
        let accepted = outlineAcceptDrop(info)
        drag = nil
        hideDropFeedback()
        pasteboard.releaseGlobally()
        return (accepted, target)
    }

    /// A row's middle and lower-quarter points in window coordinates.
    public func debugRowPoints(_ id: UUID) -> (middle: NSPoint, lower: NSPoint)? {
        guard let node = tree.displayedNode(for: id) else { return nil }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return nil }
        let rect = outline.rect(ofRow: row)
        let middle = outline.convert(NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.5), to: nil)
        let lower = outline.convert(NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.9), to: nil)
        return (middle, lower)
    }
}
#endif
