import AppKit
import Model
import Store

/// Tab commands the main menu and the tab switcher reach (spec §G, Phase
/// 2.3): ⇧⌘T, ⌘1–9, ⇧⌘] / ⇧⌘[ and ⌥⌘↓ / ⌥⌘↑, ⇧⌘M, and the ⌃Tab list.
extension SidebarController {
    /// ⇧⌘T: reopens the most recently closed tab that can still come back
    /// (Today tabs where they were; a permanent entry's page at the URL it
    /// had) and selects it.
    public func reopenClosedTab() {
        while let closed = closedTabs.pop() {
            guard let id = sidebar.reopen(closed), let entry = sidebar.entry(id) else { continue }
            if let space = entry.spaceID, space != tree.spaceID { showSpace(space) }
            clearMultiSelection()
            // A permanent entry that kept its page (reset only) loads the reopened URL.
            if case .page = closed, pageState(id).isLoaded { host?.unload(id) }
            select(id)
            pageStateDidChange([id])
            return
        }
    }

    public var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// ⌘1…⌘8 select the Nth entry in sidebar order, ⌘9 the last.
    public func selectTab(digit: Int) {
        guard let target = NavigationRules.digitTarget(digit, in: sidebar.sidebarOrder(space: tree.spaceID)) else { return }
        clearMultiSelection()
        select(target.id)
    }

    /// ⇧⌘] / ⌥⌘↓ (`offset` 1), ⇧⌘[ / ⌥⌘↑ (−1): the next entry in sidebar order, wrapping.
    public func selectAdjacentTab(_ offset: Int) {
        let order = sidebar.sidebarOrder(space: tree.spaceID)
        guard let target = NavigationRules.adjacent(to: selectedEntryID, offset: offset, in: order),
              target.id != selectedEntryID else { return }
        clearMultiSelection()
        select(target.id)
    }

    /// The ⌃Tab switcher's list: the space's most recently used entries,
    /// the selected one first.
    public func recentEntries(limit: Int) -> [Entry] {
        var order = sidebar.mruOrder(space: tree.spaceID)
        if let selected = selectedEntryID, let index = order.firstIndex(where: { $0.id == selected }), index > 0 {
            order.insert(order.remove(at: index), at: 0)
        }
        return Array(order.prefix(limit))
    }

    /// ⇧⌘M: mutes or unmutes the selected page.
    public func toggleMuteSelected() {
        guard let id = selectedEntryID, pageState(id).isLoaded else { return }
        host?.setMuted(!pageState(id).isMuted, entry: id)
        pageStateDidChange([id])
    }

    /// The selected entry has a page (Mute, Reload apply).
    public var selectedHasPage: Bool { selectedEntryID.map { pageState($0).isLoaded } ?? false }

    /// ⌘W applies: something is selected or multi-selected.
    public var canCloseCommandTargets: Bool {
        commandTargets().contains { sidebar.entry($0).map { $0.kind != .folder } ?? false }
    }
}
