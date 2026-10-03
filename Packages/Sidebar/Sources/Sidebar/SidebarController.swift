import AppKit
import Chrome
import Design
import Model
import Store

/// One window's sidebar for its active space: Essentials grid, the outline
/// (space title → pinned/folders → separator with Clear → Today → New Tab),
/// the header's address field and the footer. It writes the stores (the
/// only writers of the model) and asks its `host` for everything that
/// touches a page. Store changes arrive as `SidebarChange`s; only the rows
/// they name are reloaded (`SidebarTree`).
public final class SidebarController: NSObject {
    /// Goes into `SidebarView.bodyView`.
    public let bodyView = SidebarBodyView()
    /// Goes into `SidebarView.headerView`.
    public let addressField = AddressFieldView()
    let outline = SidebarOutlineView()
    let grid = EssentialsGridView()
    let footer = SidebarFooterView()

    public let store: RoomStore
    public let windowID: UUID
    public weak var host: SidebarHost? {
        didSet { reloadAll() }
    }
    public weak var toasts: ToastPresenting?
    /// The active space was renamed or replaced (window title).
    public var onSpaceChange: ((Space) -> Void)?

    private(set) var tree: SidebarTree
    private var token: ObservationToken?
    private var flagsMonitor: Any?
    private var hoveredNode: OutlineNode?
    /// A click on a selected, changed entry's title resets after the
    /// double-click interval unless a double-click (rename) follows.
    private var pendingReset: DispatchWorkItem?
    var isCommandHeld = false {
        didSet { if isCommandHeld != oldValue { (hoveredCell as? EntryCellView)?.isCommandHeld = isCommandHeld } }
    }
    /// The ⌘/⇧-click group (spec §A.9).
    var multiSelection = MultiSelection()
    /// A drag over the sidebar (`SidebarDragDrop`).
    var drag: DragState?
    /// The keyboard focus row (spec §I.13); its ring shows after keyboard use.
    var focusedNode: OutlineNode?
    var focusRingVisible = false
    /// Clear's slide-out is running.
    var isClearing = false
    /// Stretches Clear's animation (DEBUG captures of the mid-Clear frame).
    var clearSlowdown: Double = 1
    /// The folder preview waiting for its 500 ms dwell, and the one showing (spec §A.6).
    private var pendingFolderPreview: DispatchWorkItem?
    private weak var folderPreview: NSPopover?
    #if DEBUG
    var debugDragImage: NSView?
    #endif

    var sidebar: SidebarStore { store.sidebar }

    public init(store: RoomStore, windowID: UUID) {
        self.store = store
        self.windowID = windowID
        let spaceID = Self.activeSpace(store: store, windowID: windowID)
        tree = SidebarTree(store: store.sidebar, spaceID: spaceID,
                           selectedEntry: store.windows.selectedEntry(space: spaceID, window: windowID))
        super.init()
        bodyView.install(grid: grid, outline: outline, footer: footer)
        outline.dataSource = self
        outline.delegate = self
        outline.events = self
        outline.target = self
        outline.action = #selector(outlineClicked(_:))
        outline.doubleAction = #selector(outlineDoubleClicked(_:))
        grid.events = self
        grid.dropEvents = self
        outline.registerForDraggedTypes(Self.acceptedDragTypes)
        grid.registerForDraggedTypes(Self.acceptedDragTypes)
        bodyView.onEmptyDoubleClick = { [weak self] in self?.host?.newTab() }
        bodyView.onOverflowClick = { [weak self] in self?.scrollToSelected() }
        bodyView.onScroll = { [weak self] in self?.updateOverflow() }
        footer.plusMenu = { [weak self] in self?.makePlusMenu() ?? NSMenu() }
        addressField.onActivate = { [weak self] in self?.host?.editAddress() }
        addressField.onCopy = { [weak self] in
            guard let self, let id = selectedEntryID else { return }
            copyURL(of: id, markdown: false)
        }
        token = store.sidebar.observe { [weak self] change in self?.apply(change) }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isCommandHeld = event.modifierFlags.contains(.command)
            return event
        }
        reloadAll()
    }

    isolated deinit {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
    }

    private static func activeSpace(store: RoomStore, windowID: UUID) -> UUID {
        if let active = store.windows.window(windowID)?.activeSpaceID, store.sidebar.space(active) != nil { return active }
        return store.sidebar.spaces.first?.id ?? UUID()
    }

    // MARK: State

    public var activeSpaceID: UUID { tree.spaceID }
    public var activeSpace: Space? { tree.space }

    public var selectedEntryID: UUID? {
        store.windows.selectedEntry(space: tree.spaceID, window: windowID)
    }

    /// Shows `space` (switching animation is Phase 2.5).
    public func showSpace(_ spaceID: UUID) {
        guard sidebar.space(spaceID) != nil else { return }
        store.windows.setActiveSpace(spaceID, window: windowID)
        tree = SidebarTree(store: sidebar, spaceID: spaceID, selectedEntry: selectedEntryID)
        reloadAll()
        if let id = selectedEntryID, let entry = sidebar.entry(id) { host?.activate(entry) } else { host?.deactivate() }
    }

    /// The host's pages changed (loaded, loading, audible, favicon…).
    public func pageStateDidChange(_ ids: Set<UUID>) {
        for id in ids {
            if let node = tree.displayedNode(for: id) { reconfigure(node) }
            if let tile = grid.tile(for: id) { configureTile(tile) }
        }
        if let selected = selectedEntryID, ids.contains(selected) { updateAddressField() }
    }

    func pageState(_ id: UUID) -> EntryPageState { host?.pageState(for: id) ?? .unloaded }

    /// Loaded and away from its stored URL (spec §A.1 state 3).
    func isChanged(_ entry: Entry) -> Bool {
        pageState(entry.id).isLoaded && EntryRules.isChanged(entry)
    }

    // MARK: Reload

    func reloadAll() {
        tree.selectedEntry = selectedEntryID
        tree.reloadAll()
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        reloadGrid(animated: false)
        footer.setSpaces(sidebar.spaces, active: tree.spaceID)
        updateAddressField()
        bodyView.needsLayout = true
        bodyView.layoutSubtreeIfNeeded()
        updatePill(animated: false)
        if let id = selectedEntryID, let node = tree.displayedNode(for: id) {
            let row = outline.row(forItem: node)
            if row >= 0 { outline.scrollRowToVisible(row) }
        }
        if let node = focusedNode, outline.row(forItem: node) < 0 { focusedNode = nil }
        retainMultiSelection()
        updateOverflow()
        if let space = tree.space { onSpaceChange?(space) }
    }

    private func apply(_ change: SidebarChange) {
        if change.removedSpaces.contains(tree.spaceID) || tree.space == nil {
            let next = store.windows.window(windowID)?.activeSpaceID.flatMap { sidebar.space($0) }?.id ?? sidebar.spaces.first?.id
            if let next { showSpace(next) }
            return
        }
        // The selected entry may have been removed; the window store drops it.
        if let selected = tree.selectedEntry, sidebar.entry(selected) == nil { tree.selectedEntry = nil }
        let update = tree.update(for: change)
        perform(update)
        if update.essentialsChanged { reloadGrid(animated: true) }
        for id in change.entries { if let tile = grid.tile(for: id) { configureTile(tile) } }
        if !change.spaces.isEmpty || !change.removedSpaces.isEmpty { footer.setSpaces(sidebar.spaces, active: tree.spaceID) }
        if update.spaceChanged, let space = tree.space { onSpaceChange?(space) }
        updateAddressField()
        retainMultiSelection()
        if let node = focusedNode, outline.row(forItem: node) < 0 { focusedNode = nil }
        updateFocusRing()
        updateOverflow()
    }

    /// Applies row removals/insertions (150 ms ease-out fade, spec §I.1) and reconfigures.
    private func perform(_ update: SidebarTree.Update) {
        if update.changesRows {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.standard
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                outline.beginUpdates()
                for removal in update.removals {
                    outline.removeItems(at: removal.indexes, inParent: removal.parent, withAnimation: .effectFade)
                }
                for insertion in update.insertions {
                    outline.insertItems(at: insertion.indexes, inParent: insertion.parent, withAnimation: .effectFade)
                }
                outline.endUpdates()
            }
            for node in update.insertedExpandable { outline.expandItem(node, expandChildren: true) }
        }
        for node in update.reconfigure { reconfigure(node) }
        updatePill(animated: true)
        if update.changesRows { outline.refreshHover() }
    }

    func reconfigure(_ node: OutlineNode) {
        let row = outline.row(forItem: node)
        guard row >= 0, let view = outline.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
        configure(view, for: node)
    }

    private func configure(_ view: NSView, for node: OutlineNode) {
        switch (node.kind, view) {
        case (.entry, let cell as EntryCellView):
            guard let entry = tree.entry(node) else { return }
            let level = outline.level(forItem: node)
            cell.configure(EntryRowModel(entry: entry, page: pageState(entry.id), isSelected: entry.id == selectedEntryID,
                                         isChanged: isChanged(entry), depth: entry.kind == .today ? 0 : max(0, level - 1)))
        case (.spaceTitle, let cell as SpaceTitleCellView):
            if let space = tree.space { cell.configure(space) }
        case (.separator, let cell as SeparatorCellView):
            cell.configure(todayCount: sidebar.today(space: tree.spaceID).count)
        default:
            break
        }
    }

    // MARK: Selection

    /// Makes `id` the selected entry of this window's space (or none) and
    /// shows its page.
    public func select(_ id: UUID?) {
        let previous = selectedEntryID
        store.windows.select(id, space: tree.spaceID, window: windowID)
        if let id, sidebar.entry(id) != nil {
            try? sidebar.markActive(id)
            if let entry = sidebar.entry(id) { host?.activate(entry) }
        } else if id == nil {
            host?.deactivate()
        }
        selectionDidChange(from: previous)
    }

    private func selectionDidChange(from previous: UUID?) {
        perform(tree.selectionChanged(to: selectedEntryID))
        for id in [previous, selectedEntryID].compactMap({ $0 }) {
            if let node = tree.displayedNode(for: id) { reconfigure(node) }
            if let tile = grid.tile(for: id) { configureTile(tile) }
        }
        updateAddressField()
        updateOverflow()
    }

    func updatePill(animated: Bool) {
        var selectedRow = -1
        if let id = selectedEntryID, let node = tree.displayedNode(for: id) {
            selectedRow = outline.row(forItem: node)
        }
        outline.enumerateAvailableRowViews { rowView, row in
            (rowView as? SidebarRowView)?.isSelectedEntry = row == selectedRow
        }
        guard selectedRow >= 0 else {
            outline.pill.move(to: nil, animated: false)
            return
        }
        outline.pill.move(to: SidebarRowView.pillRect(in: outline.rect(ofRow: selectedRow)), animated: animated)
    }

    private func updateAddressField() {
        let entry = selectedEntryID.flatMap(sidebar.entry)
        let url = entry?.currentURL
        addressField.setURL(url, isSecure: url?.hasPrefix("https://") == true)
    }

    // MARK: Essentials

    private func reloadGrid(animated: Bool) {
        let ids = tree.essentialIDs
        grid.setEntries(ids, animated: animated)
        for id in ids { if let tile = grid.tile(for: id) { configureTile(tile) } }
        bodyView.needsLayout = true
    }

    func configureTile(_ tile: EssentialTileView) {
        guard let entry = sidebar.entry(tile.entryID) else { return }
        tile.configure(entry: entry, page: pageState(entry.id), isSelected: entry.id == selectedEntryID,
                       isChanged: isChanged(entry))
    }

    // MARK: Clicks (spec §A.2)

    @objc private func outlineClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? OutlineNode else { return }
        let event = NSApp.currentEvent
        switch node.kind {
        case .newTab:
            host?.newTab()
        case .spaceTitle, .separator:
            break
        case .entry(let id):
            guard let entry = sidebar.entry(id) else { return }
            let gesture = Self.gesture(event)
            setFocus(node, ring: false)
            if entry.kind == .folder {
                if gesture == .primary { try? sidebar.setFolderCollapsed(id, !entry.isCollapsed) }
                return
            }
            if gesture == .primary { clearMultiSelection() }
            let outcome = ClickRules.outcome(gesture, kind: entry.kind, isSelected: id == selectedEntryID,
                                             isChanged: isChanged(entry), isLoaded: pageState(id).isLoaded)
            if outcome == .reset, let event, clickIsOnTitle(event, row: row) {
                // The first click of a rename double-click must not reset the page.
                let work = DispatchWorkItem { [weak self] in self?.perform(.reset, on: id) }
                pendingReset = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
            } else {
                perform(outcome, on: id)
            }
        }
    }

    static func gesture(_ event: NSEvent?) -> ClickRules.Gesture {
        let flags = event?.modifierFlags ?? []
        if flags.contains(.command) { return .command }
        if flags.contains(.shift) { return .shift }
        return .primary
    }

    @objc private func outlineDoubleClicked(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? OutlineNode, let id = node.entryID,
              let event = NSApp.currentEvent, clickIsOnTitle(event, row: row) else { return }
        pendingReset?.cancel()
        pendingReset = nil
        beginRename(id)
    }

    private func clickIsOnTitle(_ event: NSEvent, row: Int) -> Bool {
        guard let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView else { return false }
        let point = cell.convert(event.locationInWindow, from: nil)
        return cell.titleRect.insetBy(dx: 0, dy: -4).contains(point)
    }

    func perform(_ outcome: ClickRules.Outcome, on id: UUID) {
        switch outcome {
        case .select: select(id)
        case .reset: reset(id)
        case .separate: separate(id)
        case .unload: unload(id)
        case .remove: removeEntry(id, undoable: true)
        case .close: close(id)
        case .toggleSelection: toggleSelection(id)
        case .extendSelection: extendSelection(id)
        case .none: break
        }
    }

    func reset(_ id: UUID) {
        try? sidebar.resetToStoredURL(id)
        if let entry = sidebar.entry(id) { host?.reset(entry) }
        pageStateDidChange([id])
    }

    func unload(_ id: UUID) {
        host?.unload(id)
        pageStateDidChange([id])
    }

    /// ⌘-click "Separate from pinned tab": the page continues as a new Today
    /// tab, the permanent entry goes back to its stored URL, unloaded.
    func separate(_ id: UUID) {
        guard let entry = sidebar.entry(id), let live = entry.liveURL,
              let tab = try? sidebar.addEntry(.today, url: live, title: entry.liveTitle, space: tree.spaceID) else { return }
        host?.separate(id, into: tab)
        try? sidebar.resetToStoredURL(id)
        select(tab.id)
        pageStateDidChange([id, tab.id])
    }

    /// Close per `NavigationRules.closeSteps` (Today tab: switch away, unload,
    /// remove; permanent entries follow the ⌘W preference, spec §A.3).
    func close(_ id: UUID, behavior: PermanentCloseBehavior? = nil) {
        let behavior = behavior ?? store.settings.settings.permanentCloseBehavior
        guard let plan = sidebar.closePlan(for: id, behavior: behavior, space: tree.spaceID) else { return }
        if plan.steps.contains(.switchAway), selectedEntryID == id { applyFallback(plan.fallback) }
        if plan.steps.contains(.unload) { host?.unload(id) }
        if plan.steps.contains(.reset) { try? sidebar.resetToStoredURL(id) }
        if plan.steps.contains(.remove) { _ = try? sidebar.remove(id) }
        pageStateDidChange([id])
    }

    func applyFallback(_ fallback: CloseFallback?) {
        switch fallback {
        case .select(let next): select(next)
        case .newTodayTabAndPalette:
            select(nil)
            host?.newTab()
        case .emptyState, nil: select(nil)
        }
    }

    /// Removes a permanent entry (folders: children move up, spec §A.6), with Undo.
    func removeEntry(_ id: UUID, undoable: Bool) {
        guard let entry = sidebar.entry(id) else { return }
        if selectedEntryID == id, let plan = sidebar.closePlan(for: id, behavior: .close, space: tree.spaceID) {
            applyFallback(plan.fallback)
        }
        host?.unload(id)
        guard let removed = try? sidebar.remove(id) else { return }
        guard undoable else { return }
        let title = EntryLabel.title(entry)
        toasts?.show(Toast(id: "removed", symbol: .info, message: "Removed “\(title)”",
                           action: .init(title: "Undo") { [weak self] in self?.sidebar.restore([removed]) }))
    }

    // MARK: Rename (spec §I.9)

    /// Starts the inline rename of a row (double-click, Enter, menu).
    public func beginRename(_ id: UUID) {
        guard let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        (outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? EntryCellView)?.beginRename()
    }

    private func pulse(_ id: UUID) {
        guard !Motion.reduceMotion, let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0, let rowView = outline.rowView(atRow: row, makeIfNecessary: false) else { return }
        rowView.wantsLayer = true
        guard let layer = rowView.layer else { return }
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        func scale(_ factor: CGFloat) -> NSValue {
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, factor, factor, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            return NSValue(caTransform3D: transform)
        }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [scale(1), scale(Motion.renamePulseScale), scale(1)]
        animation.duration = Motion.standard * 2
        layer.add(animation, forKey: "pulse")
    }

    // MARK: Copy

    func copyURL(of id: UUID, markdown: Bool) {
        guard let entry = sidebar.entry(id), let url = entry.currentURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if markdown {
            pasteboard.setString(EntryLabel.markdown(title: EntryLabel.title(entry), url: url), forType: .string)
            toasts?.show(Toast(id: "copy-markdown", symbol: .copyMarkdown, message: "Copied as Markdown"))
        } else {
            pasteboard.setString(url, forType: .string)
            if let link = URL(string: url) { pasteboard.setString(link.absoluteString, forType: .URL) }
            toasts?.show(Toast(id: "copy-url", symbol: .copyURL, message: "Copied URL"))
        }
    }

    // MARK: Hover

    private var hoveredCell: NSView? {
        guard let hoveredNode else { return nil }
        let row = outline.row(forItem: hoveredNode)
        return row >= 0 ? outline.view(atColumn: 0, row: row, makeIfNecessary: false) : nil
    }

    func setHoveredForDebug(_ node: OutlineNode?) { setHovered(node) }

    private func setHovered(_ node: OutlineNode?) {
        guard node !== hoveredNode else { return }
        setHover(false, on: hoveredNode)
        hoveredNode = node
        setHover(true, on: node)
        scheduleFolderPreview(for: node)
    }

    /// Resting on a collapsed folder for 500 ms opens its preview (spec §A.6).
    private func scheduleFolderPreview(for node: OutlineNode?) {
        pendingFolderPreview?.cancel()
        pendingFolderPreview = nil
        guard folderPreview == nil, drag == nil, let id = node?.entryID, let folder = sidebar.entry(id), folder.kind == .folder,
              folder.isCollapsed, !descendants(of: id).isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, hoveredNode === node, drag == nil else { return }
            showFolderPreview(id)
        }
        pendingFolderPreview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DropRules.holdDelay, execute: work)
    }

    /// The preview popover beside a folder's row.
    public func showFolderPreview(_ id: UUID) {
        guard let folder = sidebar.entry(id), let node = tree.displayedNode(for: id) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        let items = descendants(of: id).map { entry in
            FolderPreviewController.Item(id: entry.id, title: EntryLabel.title(entry), url: entry.currentURL,
                                         domain: EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry))
        }
        folderPreview = FolderPreviewController.show(folderName: EntryLabel.title(folder), items: items,
                                                     relativeTo: SidebarRowView.pillRect(in: outline.rect(ofRow: row)), of: outline) {
            [weak self] entry in
            // Opens inside the collapsed folder: the entry peeks under it (Arc).
            self?.clearMultiSelection()
            self?.select(entry)
        }
    }

    private func setHover(_ hovering: Bool, on node: OutlineNode?) {
        guard let node else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        (outline.rowView(atRow: row, makeIfNecessary: false) as? SidebarRowView)?.isHovered = hovering
        switch outline.view(atColumn: 0, row: row, makeIfNecessary: false) {
        case let cell as EntryCellView:
            cell.isCommandHeld = hovering && isCommandHeld
            cell.isHovered = hovering
            if !hovering { cell.isHoveringIcon = false }
        case let cell as SpaceTitleCellView:
            cell.isHovered = hovering
        default:
            break
        }
    }
}

// MARK: - NSOutlineView data source and delegate

extension SidebarController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        tree.children(of: item as? OutlineNode).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        tree.children(of: item as? OutlineNode)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? OutlineNode).map(tree.isExpandable) ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool { false }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        switch (item as? OutlineNode)?.kind {
        case .spaceTitle: SidebarMetrics.spaceTitleRowHeight
        case .separator: SidebarMetrics.separatorRowHeight
        default: SidebarMetrics.rowHeight
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? OutlineNode)?.entryID != nil
    }

    /// AppKit never changes the selection by itself: it mirrors the
    /// multi-selection, which clicks change through `ClickRules`.
    public func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        multiSelectionRows
    }

    // MARK: Drag and drop (SidebarDragDrop)

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let id = (item as? OutlineNode)?.entryID, let entry = sidebar.entry(id), !isClearing else { return nil }
        return pasteboardItem(for: entry)
    }

    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
                            forItems draggedItems: [Any]) {
        session.animatesToStartingPositionsOnCancelOrFail = true
        liftDraggingItems(session)
        draggingSessionWillBegin(session, ids: draggedItems.compactMap { ($0 as? OutlineNode)?.entryID })
    }

    public func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
                            operation: NSDragOperation) {
        draggingSessionEnded()
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                            proposedChildIndex index: Int) -> NSDragOperation {
        let operation = outlineDragUpdated(info)
        // The target is ours (`DropRules`); AppKit only needs a valid one and draws nothing.
        if !operation.isEmpty { outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex) }
        return operation
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        outlineAcceptDrop(info)
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        // Reused: allocating and attaching a row view per scrolled-in row was a third of its cost (2.2b profile).
        let rowView = outlineView.makeView(withIdentifier: SidebarRowView.identifier, owner: self) as? SidebarRowView ?? SidebarRowView()
        rowView.identifier = SidebarRowView.identifier
        switch (item as? OutlineNode)?.kind {
        case .spaceTitle, .separator: rowView.showsHover = false
        default: rowView.showsHover = true
        }
        return rowView
    }

    public func outlineView(_ outlineView: NSOutlineView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let rowView = rowView as? SidebarRowView, let node = outlineView.item(atRow: row) as? OutlineNode else { return }
        rowView.isSelectedEntry = node.entryID != nil && node.entryID == selectedEntryID
        rowView.isHovered = node === hoveredNode
        rowView.isMultiSelected = node.entryID.map(multiSelection.contains) ?? false
        rowView.showsFocusRing = focusRingVisible && node === focusedNode && outline.window?.firstResponder === outline
            && outline.window?.isKeyWindow == true
        rowView.isDropTarget = false
        rowView.alphaValue = node.entryID.map { drag?.ids.contains($0) == true } == true ? SidebarMetrics.draggedRowAlpha : 1
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? OutlineNode else { return nil }
        let view: NSView
        switch node.kind {
        case .entry:
            let cell = outlineView.makeView(withIdentifier: EntryCellView.identifier, owner: self) as? EntryCellView ?? EntryCellView()
            cell.actions = self
            cell.isHovered = node === hoveredNode
            view = cell
        case .spaceTitle:
            let cell = outlineView.makeView(withIdentifier: SpaceTitleCellView.identifier, owner: self) as? SpaceTitleCellView
                ?? SpaceTitleCellView()
            cell.onToggle = { [weak self] in self?.togglePinnedCollapsed() }
            view = cell
        case .separator:
            let cell = outlineView.makeView(withIdentifier: SeparatorCellView.identifier, owner: self) as? SeparatorCellView
                ?? SeparatorCellView()
            cell.clearButton.target = self
            cell.clearButton.action = #selector(clearToday(_:))
            view = cell
        case .newTab:
            view = outlineView.makeView(withIdentifier: NewTabCellView.identifier, owner: self) ?? NewTabCellView()
        }
        configure(view, for: node)
        return view
    }

    func togglePinnedCollapsed() {
        try? sidebar.updateSpace(tree.spaceID) { $0.pinnedCollapsed.toggle() }
    }
}

// MARK: - Row and tile events

extension SidebarController: SidebarOutlineEvents, EntryRowActions, EssentialTileEvents, EssentialsDropEvents {
    func outlineMiddleClicked(row: Int) {
        guard let id = (outline.item(atRow: row) as? OutlineNode)?.entryID, let entry = sidebar.entry(id) else { return }
        perform(ClickRules.outcome(.middle, kind: entry.kind, isSelected: id == selectedEntryID, isChanged: isChanged(entry),
                                   isLoaded: pageState(id).isLoaded), on: id)
    }

    func outlineEmptyAreaDoubleClicked() { host?.newTab() }

    func outlineMenu(forRow row: Int) -> NSMenu? {
        guard let id = (outline.item(atRow: row) as? OutlineNode)?.entryID else { return nil }
        return menu(forClicked: id)
    }

    func outlineHoverChanged(row: Int?) {
        setHovered(row.flatMap { outline.item(atRow: $0) as? OutlineNode })
    }

    func resetButtonClicked(_ entry: UUID) {
        if isCommandHeld, entry == selectedEntryID { separate(entry) } else { reset(entry) }
    }

    func closeButtonClicked(_ entry: UUID) { close(entry) }

    func audioButtonClicked(_ entry: UUID) {
        host?.setMuted(!pageState(entry).isMuted, entry: entry)
        pageStateDidChange([entry])
    }

    func renameEnded(_ id: UUID, label: String?, committed: Bool) {
        if committed, let entry = sidebar.entry(id) {
            let before = entry.customLabel
            try? sidebar.rename(id, to: label)
            if sidebar.entry(id)?.customLabel != before {
                pulse(id)
                toasts?.show(Toast(id: "renamed", symbol: .rename, message: entry.kind == .folder ? "Folder renamed" : "Tab renamed"))
            }
        }
        outline.window?.makeFirstResponder(outline)
    }

    func tileClicked(_ id: UUID, gesture: ClickRules.Gesture) {
        guard let entry = sidebar.entry(id) else { return }
        if gesture == .primary { clearMultiSelection() }
        perform(ClickRules.outcome(gesture, kind: entry.kind, isSelected: id == selectedEntryID, isChanged: isChanged(entry),
                                   isLoaded: pageState(id).isLoaded), on: id)
    }

    func tileResetClicked(_ id: UUID) { resetButtonClicked(id) }

    func tileMenu(_ id: UUID) -> NSMenu? { menu(forClicked: id) }
}

/// The sidebar below the header: Essentials, the outline (with the
/// overflow indicators at its edges, spec §I.11), the footer. A
/// double-click on its empty background is a new tab (spec §F).
public final class SidebarBodyView: NSView {
    private(set) var grid: EssentialsGridView?
    private(set) var scrollView = NSScrollView()
    private(set) var footer: SidebarFooterView?
    private let overflowTop = OverflowIndicatorView(edge: .top)
    private let overflowBottom = OverflowIndicatorView(edge: .bottom)
    var onEmptyDoubleClick: (() -> Void)?
    var onOverflowClick: (() -> Void)? {
        didSet {
            overflowTop.onClick = onOverflowClick
            overflowBottom.onClick = onOverflowClick
        }
    }
    /// The list scrolled.
    var onScroll: (() -> Void)?

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }

    func install(grid: EssentialsGridView, outline: NSOutlineView, footer: SidebarFooterView) {
        self.grid = grid
        self.footer = footer
        scrollView.documentView = outline
        // Height comes from `tile()` in `layout()`: with height autoresizing a
        // shorter window shrank the outline below its rows (2.2b), cutting off the last ones.
        outline.autoresizingMask = [.width]
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.verticalScrollElasticity = .allowed
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipViewScrolled(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        footer.onEmptyDoubleClick = { [weak self] in self?.onEmptyDoubleClick?() }
        addSubview(grid)
        addSubview(scrollView)
        addSubview(footer)
        addSubview(overflowTop)
        addSubview(overflowBottom)
    }

    @objc private func clipViewScrolled(_ notification: Notification) { onScroll?() }

    func setOverflow(above: Bool, below: Bool) {
        overflowTop.isHidden = !above
        overflowBottom.isHidden = !below
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onEmptyDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    public override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset
        let width = max(0, bounds.width - 2 * inset)
        let gridHeight = grid?.height(forWidth: width) ?? 0
        grid?.frame = NSRect(x: inset, y: gridHeight > 0 ? Spacing.xs : 0, width: width, height: gridHeight)
        let top = gridHeight > 0 ? (grid?.frame.maxY ?? 0) + Spacing.xs : 0
        let footerHeight = SidebarMetrics.footerHeight
        footer?.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - footerHeight - top))
        if let outline = scrollView.documentView as? NSOutlineView {
            outline.sizeLastColumnToFit()
            outline.tile()
        }
        let hit = SidebarMetrics.overflowHitHeight
        overflowTop.frame = NSRect(x: 0, y: scrollView.frame.minY, width: bounds.width, height: hit)
        overflowBottom.frame = NSRect(x: 0, y: scrollView.frame.maxY - hit, width: bounds.width, height: hit)
        onScroll?()
    }
}

#if DEBUG
/// Hooks for the app's DEBUG snapshot runner (no UI driving in sessions).
extension SidebarController {
    /// Shows the hover state of an entry's row or tile as if the pointer were on it
    /// (`onIcon`: over the favicon / reset icon; `command`: ⌘ held).
    public func debugHover(_ id: UUID?, onIcon: Bool = false, command: Bool = false) {
        setHoveredForDebug(id.flatMap { tree.displayedNode(for: $0) })
        isCommandHeld = command
        if let id, let node = tree.displayedNode(for: id) {
            let row = outline.row(forItem: node)
            if row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView {
                cell.isHoveringIcon = onIcon
                cell.isCommandHeld = command
            }
        }
    }

    /// Rebuilds everything from the store (timing the full reload).
    public func debugReloadAll() { reloadAll() }

    public var debugOutline: NSOutlineView { outline }

    /// ⌘-click on an entry (multi-selection).
    public func debugToggleSelection(_ id: UUID) { toggleSelection(id) }

    public func debugClearMultiSelection() { clearMultiSelection() }

    /// Keyboard focus with its ring, as after ↑/↓.
    public func debugFocus(_ id: UUID?) {
        outline.window?.makeFirstResponder(outline)
        setFocus(id.flatMap { tree.displayedNode(for: $0) }, ring: id != nil)
    }

    /// The feedback of a drag of `ids` with the pointer over `id`'s row at
    /// `fraction` of its height (`held`: after the 500 ms hold): the dimmed
    /// source rows, the insertion line or drop-onto highlight, and the
    /// lifted image at the pointer (drawn in the outline; a real drag draws
    /// it in its own window). `nil` ends it.
    public func debugShowDrag(_ ids: [UUID]?, over id: UUID? = nil, fraction: CGFloat = 0.1, held: Bool = false) {
        debugDragImage?.removeFromSuperview()
        debugDragImage = nil
        guard let ids, let id, let node = tree.displayedNode(for: id) else {
            if let dragged = drag?.ids { setDragging(dragged, dimmed: false) }
            drag = nil
            hideDropFeedback()
            return
        }
        drag = DragState(ids: ids)
        setDragging(ids, dimmed: true)
        let row = outline.row(forItem: node)
        let rowRect = outline.rect(ofRow: row)
        let single = ids.count == 1 && sidebar.entry(ids[0])?.kind != .folder
        let target = DropRules.target(debugDropRow(row), at: row, rowCount: outline.numberOfRows, fraction: fraction, held: held,
                                      space: tree.spaceID, single: single)
        showFeedback(for: target)
        guard let first = ids.first, let entry = sidebar.entry(first) else { return }
        let pill = SidebarRowView.pillRect(in: rowRect)
        let image = DragImage.row(entry, page: pageState(first), size: pill.size, appearance: outline.effectiveAppearance)
        var frame = DragImage.frame(for: image, around: pill)
        // Under the pointer, grabbed near its top edge (the line above stays visible).
        frame.origin.x += 8
        frame.origin.y = rowRect.minY + rowRect.height * fraction - DragImage.margin + 6
        let view = NSImageView(frame: frame)
        view.image = image
        view.imageScaling = .scaleNone
        outline.addSubview(view)
        debugDragImage = view
    }

    private func debugDropRow(_ row: Int) -> DropRules.Row? {
        guard let node = outline.item(atRow: row) as? OutlineNode, let id = node.entryID, let entry = sidebar.entry(id) else {
            return nil
        }
        let depth = entry.kind == .today ? 0 : max(0, outline.level(forRow: row) - 1)
        return .entry(id: id, kind: entry.kind, container: entry.container, index: entry.position, depth: depth,
                      showsChildren: entry.kind == .folder && !tree.children(of: node).isEmpty)
    }

    /// Clear's animation runs `factor` times slower (for a mid-Clear capture).
    public func debugSetClearSlowdown(_ factor: Double) { clearSlowdown = factor }

    /// The grid's "12/12" badge, as over a full grid during a drag.
    public func debugShowEssentialsFull(_ show: Bool) {
        grid.showFullBadge(show ? "\(essentialsCount)/\(EntryRules.essentialsCap)" : nil)
    }

    /// The folder preview's window, if one is showing.
    public var debugFolderPreviewWindow: NSWindow? { folderPreview?.contentViewController?.view.window }

    /// The empty grid's drop slot, as during a drag.
    public func debugShowDropSlot(_ show: Bool) {
        grid.showsDropSlot = show
        bodyView.needsLayout = true
        bodyView.layoutSubtreeIfNeeded()
    }
}
#endif
