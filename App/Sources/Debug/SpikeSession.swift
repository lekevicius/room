#if DEBUG
import AppKit
import Engine
import Model
import Sidebar
import Store
import Tabs

/// What the Phase 1.4 spikes drove through Chapter 1's flat page list, now
/// on the sidebar's Today tabs and the tab controller (Phase 2.3): a "page"
/// is a Today entry with a page; ⌘T/⌘L count requests instead of opening
/// the modal prompt.
@MainActor
final class SpikeSession {
    let tabs: TabController
    let sidebar: SidebarController
    let host: PageHost
    let profile: any Engine.Profile
    let pageDelegate: PageUIDelegate
    /// ⌘L presses that reached the app (the keyboard spike).
    private(set) var addressFocusRequest = 0
    /// ⌘T presses that reached the app.
    private(set) var newTabRequests = 0

    init(tabs: TabController, sidebar: SidebarController, host: PageHost, profile: any Engine.Profile, pageDelegate: PageUIDelegate) {
        self.tabs = tabs
        self.sidebar = sidebar
        self.host = host
        self.profile = profile
        self.pageDelegate = pageDelegate
        tabs.onNewTab = { [weak self] in self?.newTabRequests += 1 }
        tabs.onEditAddress = { [weak self] in self?.addressFocusRequest += 1 }
    }

    var store: SidebarStore { sidebar.store.sidebar }

    var keyLog: [String] { pageDelegate.keyLog }

    /// Today tabs with a page, in sidebar order.
    var pages: [any WebContents] {
        store.today(space: sidebar.activeSpaceID).compactMap { tabs.contents(for: $0.id) }
    }

    var current: (any WebContents)? { tabs.current }

    /// A new Today tab at the end of the list, shown (`select`) or loaded in the background.
    @discardableResult
    func newPage(_ url: URL?, hidden: Bool = false, select: Bool = true) -> (any WebContents)? {
        guard let entry = try? store.addEntry(.today, url: url?.absoluteString, space: sidebar.activeSpaceID) else { return nil }
        if select && !hidden {
            sidebar.select(entry.id)
            return tabs.contents(for: entry.id)
        }
        return tabs.loadInBackground(entry)
    }

    func select(_ index: Int) {
        let withPages = store.today(space: sidebar.activeSpaceID).filter { tabs.contents(for: $0.id) != nil }
        guard withPages.indices.contains(index) else { return }
        sidebar.select(withPages[index].id)
    }
}
#endif
