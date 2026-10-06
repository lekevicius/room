import AppKit
import Chrome
import Design
import Model
import Store

/// Split view's sidebar side (spec §D): creating and changing splits from
/// rows, menus and keys, the group row's clicks, and ⌘W on a pane. The
/// selected entry is the focused pane; selecting any pane shows its split.
extension SidebarController {
    // MARK: Queries

    /// The split the selected entry is a pane of.
    public var selectedSplit: SplitGroup? { selectedEntryID.flatMap(sidebar.splitGroup(of:)) }

    /// A split's group row at `row`: the pane whose segment `event` is over.
    func splitMember(atRow row: Int, event: NSEvent?) -> UUID? {
        guard let event, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? SplitGroupCellView else { return nil }
        return cell.member(at: cell.convert(event.locationInWindow, from: nil))
    }

    /// The entry that becomes a pane for `id`: pinned entries and Today tabs
    /// as they are; an essential's page joins as a Today copy (Zen: permanent
    /// tabs mixed with normal ones are duplicated into the split), right after `after`.
    func paneEntry(for id: UUID, after: UUID? = nil) -> UUID? {
        guard let entry = sidebar.entry(id) else { return nil }
        switch entry.kind {
        case .pinned, .today: return id
        case .folder: return nil
        case .essential:
            let index = after.flatMap(sidebar.entry).flatMap { $0.kind == .today ? $0.position + 1 : nil }
            return (try? sidebar.addEntry(.today, url: entry.currentURL, title: entry.liveTitle ?? entry.storedTitle,
                                          space: tree.spaceID, window: windowID, at: index))?.id
        }
    }

    /// Whether `ids` (one entry) can join `other`'s split or make one with it.
    func canJoin(_ ids: [UUID], with other: UUID) -> Bool {
        guard ids.count == 1, ids[0] != other, let dragged = sidebar.entry(ids[0]), dragged.kind != .folder,
              let target = sidebar.entry(other), target.kind == .pinned || target.kind == .today else { return false }
        guard let group = sidebar.splitGroup(of: other) else { return true }
        return !group.members.contains(ids[0]) && SplitRules.canAdd(toCount: group.members.count)
    }

    // MARK: Creating splits

    /// "Join" (a row dropped on another row's centre), Split With, ⌥-click:
    /// `id` becomes the pane after `other` in its split, or the two become
    /// one side by side; `id` takes the focus.
    func join(_ id: UUID, with other: UUID) throws(SidebarError) {
        guard let target = paneEntry(for: other), let pane = paneEntry(for: id, after: target) else { throw .invalidKind }
        if let group = sidebar.splitGroup(of: target) {
            let index = (group.members.firstIndex(of: target) ?? group.members.count - 1) + 1
            try sidebar.addToSplitGroup(pane, group: group.id, at: index)
        } else {
            try sidebar.createSplitGroup([target, pane], layout: .hbox)
        }
        clearMultiSelection()
        select(pane)
    }

    /// Peek ▸ Split (⇧⌘O): `id` (Peek's page, now a Today tab) becomes the pane after `other`, focused.
    public func joinIntoSplit(_ id: UUID, with other: UUID) {
        do throws(SidebarError) { try join(id, with: other) } catch { showRefusal(error) }
    }

    /// Split With ▸ an entry: the clicked row joins it (spec §A.8).
    public func split(_ id: UUID, with other: UUID) {
        do throws(SidebarError) { try join(other, with: id) } catch { showRefusal(error) }
    }

    /// "Join N Tabs" (spec §D): a multi-selection becomes one split, in sidebar order.
    public func joinSelection(_ ids: [UUID]) {
        let panes = ids.compactMap { paneEntry(for: $0) }
        guard panes.count >= 2 else { return }
        guard panes.count <= SplitRules.maxPanes else { return showSplitFullToast() }
        do throws(SidebarError) {
            try sidebar.createSplitGroup(panes, layout: panes.count > 2 ? .grid : .hbox)
        } catch {
            return showRefusal(error)
        }
        clearMultiSelection()
        select(panes[0])
    }

    /// ⌥-click (spec §D): on a split's row it separates every pane; on the
    /// selected entry it duplicates it into a split; on another entry it
    /// splits it with the selected one (Zen). Returns whether it acted.
    func altClick(_ id: UUID) -> Bool {
        if let group = sidebar.splitGroup(of: id) {
            sidebar.dissolveSplitGroup(group.id)
            return true
        }
        guard let selected = selectedEntryID, sidebar.entry(id)?.kind != .folder else { return false }
        if id == selected {
            duplicateIntoSplit(id)
        } else {
            do throws(SidebarError) { try join(id, with: selected) } catch { showRefusal(error) }
        }
        return true
    }

    /// The selected entry's page, again, as a new pane beside it (a Today copy of its current URL).
    func duplicateIntoSplit(_ id: UUID) {
        guard let entry = sidebar.entry(id), let url = entry.currentURL else { return }
        if let group = sidebar.splitGroup(of: id), !SplitRules.canAdd(toCount: group.members.count) { return showSplitFullToast() }
        let index = entry.kind == .today ? entry.position + 1 : nil
        guard let copy = try? sidebar.addEntry(.today, url: url, title: entry.liveTitle ?? entry.storedTitle, space: tree.spaceID, window: windowID, at: index)
        else { return }
        do throws(SidebarError) { try join(copy.id, with: id) } catch {
            _ = try? sidebar.remove(copy.id)
            showRefusal(error)
        }
    }

    /// ⇧⌘= / ⌃⇧= (spec §D): an empty pane right of the selected one, focused,
    /// with the palette open on it to choose its page.
    public func newSplitPane() {
        guard let selected = selectedEntryID, let entry = sidebar.entry(selected), entry.kind != .folder else { return host?.newTab() ?? () }
        if let group = sidebar.splitGroup(of: selected), !SplitRules.canAdd(toCount: group.members.count) { return showSplitFullToast() }
        guard let target = paneEntry(for: selected) else { return }
        let anchor = sidebar.entry(target)
        let index = anchor?.kind == .today ? (anchor?.position ?? 0) + 1 : nil
        guard let empty = try? sidebar.addEntry(.today, url: nil, space: tree.spaceID, window: windowID, at: index) else { return }
        do throws(SidebarError) { try join(empty.id, with: target) } catch {
            _ = try? sidebar.remove(empty.id)
            return showRefusal(error)
        }
        host?.openLocation()
    }

    /// An entry dropped on a pane's edge in the content area (spec §D drop
    /// zones): a pane on that side of `pane`, the layout following the drop.
    public func dropIntoSplit(_ id: UUID, edge: SplitEdge, of pane: UUID) {
        guard id != pane, let target = paneEntry(for: pane), let dropped = paneEntry(for: id, after: target) else { return }
        do throws(SidebarError) {
            if let group = sidebar.splitGroup(of: target) {
                guard !group.members.contains(dropped) else { return }
                let index = SplitRules.insertionIndex(target: group.members.firstIndex(of: target) ?? 0, edge: edge)
                let layout = SplitRules.layout(afterDropOn: edge, current: group.layout, count: group.members.count + 1)
                try sidebar.addToSplitGroup(dropped, group: group.id, at: index)
                try sidebar.setSplitLayout(group.id, layout)
            } else {
                let members = edge.isLeading ? [dropped, target] : [target, dropped]
                try sidebar.createSplitGroup(members, layout: SplitRules.layout(afterDropOn: edge, current: nil, count: 2))
            }
        } catch {
            return showRefusal(error)
        }
        clearMultiSelection()
        select(dropped)
    }

    /// An entry dropped in a pane's centre: it takes that pane's place (the
    /// pane's entry stays in the sidebar); outside a split it is selected.
    public func dropReplacingPane(_ id: UUID, pane: UUID) {
        guard id != pane else { return }
        if sidebar.splitGroup(of: pane) != nil, let dropped = paneEntry(for: id) {
            do throws(SidebarError) { try sidebar.replaceSplitMember(pane, with: dropped) } catch { return showRefusal(error) }
            select(dropped)
        } else {
            select(id)
        }
    }

    // MARK: Changing the selected split (spec §D keys)

    /// ⌥⌘G / ⌥⌘V / ⌥⌘H: the selected split's layout; outside a split, the
    /// selected entry and the next one in sidebar order (or the
    /// multi-selection) become a split with it (Zen).
    public func setSplitLayout(_ layout: SplitLayout) {
        if let group = selectedSplit {
            do throws(SidebarError) { try sidebar.setSplitLayout(group.id, layout) } catch { showRefusal(error) }
            return
        }
        if multiSelection.ids.count >= 2 {
            joinSelection(multiSelection.ids)
            if let group = selectedSplit { try? sidebar.setSplitLayout(group.id, layout) }
            return
        }
        guard let selected = selectedEntryID else { return }
        let order = sidebar.sidebarOrder(space: tree.spaceID, window: windowID).filter { $0.kind != .folder && $0.splitGroupID == nil }
        guard let index = order.firstIndex(where: { $0.id == selected }), order.count > 1 else { return }
        let next = order[(index + 1) % order.count]
        guard let first = paneEntry(for: selected), let second = paneEntry(for: next.id, after: first) else { return }
        do throws(SidebarError) { try sidebar.createSplitGroup([first, second], layout: layout) } catch { return showRefusal(error) }
        select(first)
    }

    /// ⌥⌘U: every pane of the selected split becomes a normal entry; the focused one stays selected.
    public func unsplit() {
        guard let group = selectedSplit else { return }
        sidebar.dissolveSplitGroup(group.id)
    }

    /// ⌃⇧-: the focused pane leaves its split (it stays in the sidebar); the next pane takes the focus.
    public func removeFocusedPane() {
        guard let id = selectedEntryID, let group = sidebar.splitGroup(of: id) else { return }
        let focus = SplitRules.focusAfterLeaving(id, order: group.members)
        if let focus { select(focus) }
        sidebar.removeFromSplitGroup(id)
    }

    /// ⌃⇧1…4.
    public func focusPane(number: Int) {
        guard let group = selectedSplit, let id = SplitRules.pane(number: number, order: group.members) else { return }
        select(id)
    }

    /// ⌃⇧] (`offset` 1) / ⌃⇧[ (−1), wrapping.
    public func focusAdjacentPane(_ offset: Int) {
        guard let id = selectedEntryID, let group = sidebar.splitGroup(of: id),
              let next = SplitRules.adjacentPane(to: id, offset: offset, order: group.members), next != id else { return }
        select(next)
    }

    /// The pane header's grip: pane `from` moves to `to`.
    public func movePane(in group: UUID, from: Int, to: Int) {
        do throws(SidebarError) { try sidebar.moveSplitMember(group, from: from, to: to) } catch { showRefusal(error) }
    }

    // MARK: ⌘W on a pane (spec §D)

    /// ⌘W closes only the focused pane: a permanent entry gets §A.3 and
    /// leaves the split, a Today tab closes; the next pane takes the focus.
    func closePane(_ id: UUID, group: SplitGroup, behavior: PermanentCloseBehavior) {
        guard let before = sidebar.entry(id) else { return }
        let plan = SplitRules.paneClose(before, behavior: behavior, order: group.members)
        let hadPage = pageState(id).isLoaded
        if selectedEntryID == id, let focus = plan.focus { select(focus) }
        if plan.steps.contains(.unload) { host?.unload(id) }
        if plan.steps.contains(.reset) {
            try? sidebar.resetToStoredURL(id)
            if !plan.steps.contains(.unload), let entry = sidebar.entry(id) { host?.reset(entry) }
        }
        if plan.leavesGroup { sidebar.removeFromSplitGroup(id) }
        if plan.steps.contains(.remove) {
            if let removed = try? sidebar.remove(id) { closedTabs.push(.removed([removed])) }
        } else if hadPage, before.liveURL != nil, plan.steps.contains(.unload) || plan.steps.contains(.reset) {
            closedTabs.push(.page(before))
        }
        pageStateDidChange([id])
    }

    public func showSplitFullToast() {
        NSSound.beep()
        toasts?.show(Toast(id: "split-full", symbol: .info, message: "Can't add more panes to the split view"))
    }

    // MARK: Menus

    /// Split With ▸: the selected entry first, then the space's other tabs.
    func splitWithItem(_ entry: Entry) -> NSMenuItem {
        let item = NSMenuItem(title: CommandName.splitWith, action: nil, keyEquivalent: "")
        item.image = Symbol.newSplit.image()
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let full = sidebar.splitGroup(of: entry.id).map { !SplitRules.canAdd(toCount: $0.members.count) } ?? false
        let group = sidebar.splitGroup(of: entry.id)?.members ?? [entry.id]
        let candidates = sidebar.sidebarOrder(space: tree.spaceID, window: windowID).filter { $0.kind != .folder && !group.contains($0.id) }
        if let selected = selectedEntryID, !group.contains(selected), let current = sidebar.entry(selected) {
            submenu.addItem(action("\(CommandName.currentTab) — \(EntryLabel.title(current))", enabled: !full) { [weak self] in
                self?.split(entry.id, with: selected)
            })
            submenu.addItem(.separator())
        }
        for other in candidates.prefix(20) where other.id != selectedEntryID {
            submenu.addItem(action(EntryLabel.title(other), enabled: !full) { [weak self] in self?.split(entry.id, with: other.id) })
        }
        if submenu.items.isEmpty {
            let none = NSMenuItem(title: "No Other Tabs", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        item.submenu = submenu
        item.isEnabled = !full
        return item
    }

    /// A pane's menu adds the split's own commands.
    func addSplitItems(_ menu: NSMenu, _ entry: Entry) {
        guard let group = sidebar.splitGroup(of: entry.id) else { return }
        menu.addItem(.separator())
        let layout = NSMenuItem(title: CommandName.splitLayout, action: nil, keyEquivalent: "")
        layout.image = Symbol.newSplit.image()
        let layouts = NSMenu()
        layouts.autoenablesItems = false
        for (title, value, key) in [(CommandName.layoutGrid, SplitLayout.grid, "g"), (CommandName.layoutSideBySide, .hbox, "v"),
                                    (CommandName.layoutStacked, .vbox, "h")] {
            let item = action(title, key: key, modifiers: [.command, .option]) { [weak self] in try? self?.sidebar.setSplitLayout(group.id, value) }
            item.state = group.layout == value ? .on : .off
            layouts.addItem(item)
        }
        layout.submenu = layouts
        menu.addItem(layout)
        menu.addItem(action(CommandName.removeFromSplit, key: "-", modifiers: [.control, .shift]) { [weak self] in
            guard let self else { return }
            if selectedEntryID == entry.id, let focus = SplitRules.focusAfterLeaving(entry.id, order: group.members) { select(focus) }
            sidebar.removeFromSplitGroup(entry.id)
        })
        menu.addItem(action(CommandName.separateAllTabs, key: "u", modifiers: [.command, .option]) { [weak self] in
            self?.sidebar.dissolveSplitGroup(group.id)
        })
    }
}
