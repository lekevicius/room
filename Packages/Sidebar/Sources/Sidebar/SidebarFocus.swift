import AppKit
import Chrome
import Design
import Model
import Store

/// Multi-selection (spec §A.9), the commands that act on it (⌘D, ⇧⌘D,
/// Delete), keyboard focus (§I.13), the overflow indicator (§I.11) and
/// Clear's staggered slide-out (§A.7).
extension SidebarController {
    // MARK: Multi-selection

    /// A section's entries in the order the sidebar shows them.
    func displayedOrder(_ section: EntrySection) -> [UUID] {
        switch section {
        case .essentials:
            return tree.essentialIDs
        case .today:
            return sidebar.today(space: tree.spaceID).map(\.id)
        case .pinned:
            return (0..<outline.numberOfRows).compactMap { row in
                guard let id = (outline.item(atRow: row) as? OutlineNode)?.entryID, sidebar.entry(id)?.kind == .pinned else { return nil }
                return id
            }
        }
    }

    func toggleSelection(_ id: UUID) {
        guard let section = sidebar.entry(id)?.container.section else { return }
        multiSelection.toggle(id, section: section, order: displayedOrder(section), primary: selectedEntryID)
        multiSelectionDidChange()
    }

    func extendSelection(_ id: UUID) {
        guard let section = sidebar.entry(id)?.container.section else { return }
        multiSelection.extend(to: id, section: section, order: displayedOrder(section), primary: selectedEntryID)
        multiSelectionDidChange()
    }

    func clearMultiSelection() {
        guard !multiSelection.isEmpty else { return }
        multiSelection.clear()
        multiSelectionDidChange()
    }

    /// Drops entries that left their section (after a move or removal).
    func retainMultiSelection() {
        guard let section = multiSelection.section else { return }
        let before = multiSelection
        multiSelection.retain(displayedOrder(section))
        if multiSelection != before || !multiSelection.isEmpty { multiSelectionDidChange() }
    }

    /// Redraws the tint and mirrors the group into AppKit's selection, so a
    /// drag of a selected row carries all of it.
    func multiSelectionDidChange() {
        let ids = Set(multiSelection.ids)
        outline.enumerateAvailableRowViews { rowView, row in
            let id = (outline.item(atRow: row) as? OutlineNode)?.entryID
            (rowView as? SidebarRowView)?.isMultiSelected = id.map(ids.contains) ?? false
        }
        for (id, tile) in grid.tiles { tile.isMultiSelected = ids.contains(id) }
        outline.selectRowIndexes(multiSelectionRows, byExtendingSelection: false)
    }

    var multiSelectionRows: IndexSet {
        IndexSet(multiSelection.ids.compactMap { tree.displayedNode(for: $0) }.map { outline.row(forItem: $0) }.filter { $0 >= 0 })
    }

    /// What a command acts on: the multi-selection if `id` is in it (or no
    /// `id` is given), else `id`, else the selected entry.
    func commandTargets(_ id: UUID? = nil) -> [UUID] {
        if !multiSelection.isEmpty, id.map(multiSelection.contains) ?? true { return multiSelection.ids }
        return [id ?? selectedEntryID].compactMap { $0 }
    }

    // MARK: ⌘D, ⇧⌘D, ⇧⌘K (main menu)

    /// The ⌘D item's title for the current target ("Pin Tab", "Unpin Tab"), `nil` when it does not apply.
    public var pinCommandTitle: String? {
        let kinds = Set(commandTargets().compactMap { sidebar.entry($0)?.kind })
        if kinds == [.today] { return CommandName.pinTab }
        if kinds == [.pinned] { return CommandName.unpinTab }
        return nil
    }

    /// The ⇧⌘D item's title ("Add to Essentials", "Remove from Essentials"), `nil` when it does not apply.
    public var essentialsCommandTitle: String? {
        let kinds = Set(commandTargets().compactMap { sidebar.entry($0)?.kind })
        if kinds.isEmpty || kinds.contains(.folder) { return nil }
        return kinds == [.essential] ? CommandName.removeFromEssentials : CommandName.addToEssentials
    }

    public var canClearToday: Bool { !sidebar.today(space: tree.spaceID).isEmpty }

    /// ⌘D: pin the target Today tabs, or unpin pinned entries to the top of Today.
    public func togglePin() {
        let ids = commandTargets()
        switch pinCommandTitle {
        case CommandName.pinTab?:
            run { () throws(SidebarError) in try sidebar.move(ids, to: .pinned(space: tree.spaceID, folder: nil), insertingAt: .max) }
        case CommandName.unpinTab?:
            run { () throws(SidebarError) in try sidebar.move(ids, to: .today(space: tree.spaceID), insertingAt: 0) }
        default:
            NSSound.beep()
        }
    }

    /// ⇧⌘D: into the Essentials, or out of them to the top of Today.
    public func toggleEssentials() {
        guard let space = tree.space else { return }
        let ids = commandTargets()
        switch essentialsCommandTitle {
        case CommandName.removeFromEssentials?:
            run { () throws(SidebarError) in try sidebar.move(ids, to: .today(space: tree.spaceID), insertingAt: 0) }
        case CommandName.addToEssentials?:
            run { () throws(SidebarError) in try sidebar.move(ids, to: .essentials(profile: space.profileID), insertingAt: .max) }
        default:
            NSSound.beep()
        }
    }

    /// ⇧⌘K and the separator's "Clear".
    public func clearTodayTabs() { clearToday(nil) }

    private func run(_ body: () throws(SidebarError) -> Void) {
        do throws(SidebarError) { try body() } catch { showRefusal(error) }
        retainMultiSelection()
    }

    // MARK: Keyboard focus (spec §I.13)

    /// ↑/↓ move the focus ring, →/← open and close folders, Enter selects
    /// (on the selected row: rename, §I.9), Delete is ⌘W, Esc clears the
    /// multi-selection; Space (Peek) waits for 2.7.
    func outlineKeyDown(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 125: moveFocus(by: 1)
        case 126: moveFocus(by: -1)
        case 124: expandFocused()
        case 123: collapseFocused()
        case 36, 76: return activateFocused()
        case 49: return focusedEntryID != nil
        case 51, 117: return closeFocused()
        case 53:
            let handled = !multiSelection.isEmpty || focusRingVisible
            clearMultiSelection()
            setFocus(focusedNode, ring: false)
            return handled
        default: return false
        }
        return true
    }

    var focusedEntryID: UUID? { focusedNode?.entryID }

    /// Moves keyboard focus; `ring`: draw it (keyboard use, not clicks).
    func setFocus(_ node: OutlineNode?, ring: Bool) {
        focusedNode = node
        focusRingVisible = ring && node != nil
        updateFocusRing()
    }

    func updateFocusRing() {
        let focusedRow = focusedNode.map { outline.row(forItem: $0) } ?? -1
        let show = focusRingVisible && outline.window?.firstResponder === outline
        outline.enumerateAvailableRowViews { rowView, row in
            (rowView as? SidebarRowView)?.showsFocusRing = show && row == focusedRow
        }
    }

    func outlineFocusChanged(_ focused: Bool) { updateFocusRing() }

    private func moveFocus(by delta: Int) {
        let rows = outline.numberOfRows
        var row = focusedNode.map { outline.row(forItem: $0) } ?? -1
        if row < 0, let id = selectedEntryID, let node = tree.displayedNode(for: id), focusedNode == nil {
            row = outline.row(forItem: node)
            // The first key press shows the ring where the selection is.
            if row >= 0 {
                setFocus(node, ring: true)
                outline.scrollRowToVisible(row)
                return
            }
        }
        if row < 0 { row = delta > 0 ? -1 : rows }
        var next = row + delta
        while next >= 0, next < rows, (outline.item(atRow: next) as? OutlineNode)?.entryID == nil { next += delta }
        guard next >= 0, next < rows, let node = outline.item(atRow: next) as? OutlineNode else {
            setFocus(focusedNode, ring: true)
            return
        }
        setFocus(node, ring: true)
        outline.scrollRowToVisible(next)
    }

    private func expandFocused() {
        guard let id = focusedEntryID, let entry = sidebar.entry(id), entry.kind == .folder, let node = focusedNode else { return }
        if entry.isCollapsed {
            try? sidebar.setFolderCollapsed(id, false)
        } else if let child = tree.children(of: node).first {
            setFocus(child, ring: true)
        }
        updateFocusRing()
    }

    private func collapseFocused() {
        guard let id = focusedEntryID, let entry = sidebar.entry(id) else { return }
        if entry.kind == .folder, !entry.isCollapsed {
            try? sidebar.setFolderCollapsed(id, true)
        } else if let parent = entry.folderID, let node = tree.displayedNode(for: parent) {
            setFocus(node, ring: true)
        }
        updateFocusRing()
    }

    /// Enter: select the focused entry; on the selected one, rename it (§I.9).
    private func activateFocused() -> Bool {
        guard let id = focusedEntryID ?? selectedEntryID, let entry = sidebar.entry(id) else { return false }
        if entry.kind == .folder {
            try? sidebar.setFolderCollapsed(id, !entry.isCollapsed)
        } else if id == selectedEntryID {
            beginRename(id)
        } else {
            clearMultiSelection()
            select(id)
        }
        return true
    }

    /// Delete = ⌘W on the focused entry, or on the whole multi-selection.
    private func closeFocused() -> Bool {
        let ids = multiSelection.isEmpty ? [focusedEntryID ?? selectedEntryID].compactMap { $0 } : multiSelection.ids
        let closable = ids.filter { sidebar.entry($0).map { $0.kind != .folder } ?? false }
        guard !closable.isEmpty else { return false }
        clearMultiSelection()
        for id in closable { close(id) }
        return true
    }

    // MARK: Overflow indicator (spec §I.11)

    /// A line at the top or bottom edge of the list while the selected row is scrolled out of view.
    func updateOverflow() {
        var above = false, below = false
        if let id = selectedEntryID, let node = tree.displayedNode(for: id) {
            let row = outline.row(forItem: node)
            if row >= 0 {
                let rect = outline.rect(ofRow: row)
                let visible = outline.visibleRect
                above = rect.maxY <= visible.minY
                below = rect.minY >= visible.maxY
            }
        }
        bodyView.setOverflow(above: above, below: below)
    }

    /// The indicator was clicked: bring the selected row to the middle of the list.
    func scrollToSelected() {
        guard let id = selectedEntryID, let node = tree.displayedNode(for: id), let scrollView = outline.enclosingScrollView else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        let clip = scrollView.contentView
        let rect = outline.rect(ofRow: row)
        let maxY = max(0, outline.frame.height - clip.bounds.height)
        let y = min(max(0, rect.midY - clip.bounds.height / 2), maxY)
        if Motion.reduceMotion {
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.medium
            context.allowsImplicitAnimation = true
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    // MARK: Clear (spec §A.7)

    /// "Clear" / ⇧⌘K: the visible Today rows slide out to the left one after
    /// another (30 ms apart, the whole stagger at most 300 ms; a fade under
    /// Reduce Motion), then the tabs are removed with an Undo toast.
    @objc func clearToday(_ sender: Any?) {
        guard !isClearing, canClearToday else { return }
        let todayIDs = Set(sidebar.today(space: tree.spaceID).map(\.id))
        var rows: [NSTableRowView] = []
        outline.enumerateAvailableRowViews { rowView, row in
            if let id = (outline.item(atRow: row) as? OutlineNode)?.entryID, todayIDs.contains(id),
               outline.visibleRect.intersects(rowView.frame) {
                rows.append(rowView)
            }
        }
        rows.sort { $0.frame.minY < $1.frame.minY }
        guard outline.window != nil, !rows.isEmpty else {
            commitClear()
            return
        }
        isClearing = true
        let reduce = Motion.reduceMotion
        let duration = Motion.standard * clearSlowdown
        let step = reduce ? 0 : min(Motion.clearStagger, Motion.clearStaggerMax / Double(max(1, rows.count - 1))) * clearSlowdown
        let start = CACurrentMediaTime()
        for (index, rowView) in rows.enumerated() {
            rowView.wantsLayer = true
            guard let layer = rowView.layer else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let group = CAAnimationGroup()
            if reduce {
                group.animations = [fade]
            } else {
                let slide = CABasicAnimation(keyPath: "transform.translation.x")
                slide.fromValue = 0
                slide.toValue = -rowView.bounds.width
                group.animations = [slide, fade]
            }
            group.beginTime = start + Double(index) * step
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "clear")
        }
        let total = step * Double(rows.count - 1) + duration
        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self else { return }
            // Hidden before the removal so its fade shows nothing.
            for rowView in rows {
                rowView.alphaValue = 0
                rowView.layer?.removeAnimation(forKey: "clear")
            }
            isClearing = false
            commitClear()
            for rowView in rows where outline.row(for: rowView) >= 0 { rowView.alphaValue = 1 }
        }
    }

    /// Removes the space's Today tabs (the selection moves to the most recent
    /// other entry if it was one), with "N tabs closed · Undo".
    func commitClear() {
        let space = tree.spaceID
        let selected = selectedEntryID
        let selectedWasToday = selected.flatMap(sidebar.entry)?.kind == .today
        let removed = sidebar.clearToday(space: space)
        guard !removed.isEmpty else { return }
        for item in removed { host?.unload(item.entry.id) }
        if selectedWasToday {
            let next = sidebar.mruOrder(space: space).first { $0.kind != .folder && $0.lastActiveAt != nil }
            select(next?.id)
        }
        retainMultiSelection()
        let message = removed.count == 1 ? "1 tab closed" : "\(removed.count) tabs closed"
        toasts?.show(Toast(id: "tabs-closed", symbol: .clearToday, message: message,
                           action: .init(title: "Undo") { [weak self] in
                               guard let self else { return }
                               sidebar.restore(removed)
                               if selectedWasToday, let selected, sidebar.entry(selected) != nil { select(selected) }
                           },
                           duration: Timing.undoToast))
    }
}

/// The overflow indicator (spec §I.11): a 2 pt accent line at the list's
/// edge; its click target is taller than the line.
final class OverflowIndicatorView: NSView {
    enum Edge { case top, bottom }

    let edge: Edge
    var onClick: (() -> Void)?
    private let line = CALayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(line)
        isHidden = true
        setAccessibilityRole(.button)
        setAccessibilityLabel("Scroll to Selected Tab")
        setAccessibilityIdentifier(edge == .top ? "overflow-top" : "overflow-bottom")
        toolTip = "Scroll to Selected Tab"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let width = SidebarMetrics.overflowLineWidth
        let inset = SidebarMetrics.rowHorizontalInset
        line.frame = CGRect(x: inset, y: edge == .top ? 0 : bounds.height - width, width: max(0, bounds.width - 2 * inset), height: width)
        line.cornerRadius = width / 2
        effectiveAppearance.performAsCurrentDrawingAppearance { line.backgroundColor = Palette.accent.cgColor }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
