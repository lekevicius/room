import AppKit
import Library
import Model
import Sidebar
import Store
import Tabs

/// The Library in the sidebar (4.1a, PLAN §4): ⇧⌘L swaps the spaces view
/// (essentials and lists between the header and the footer) for it and back,
/// Esc returns, ⌘Y opens it at History, the downloads button's menu at
/// Downloads. Restores and History opens go through the sidebar and the tab
/// controller like any other selection.
extension AppDelegate {
    func installLibrary(_ session: WindowSession, store: RoomStore) {
        guard let sidebar = session.sidebar, let tabs = session.tabs else { return }
        let library = LibraryController(store: store, downloads: downloadList)
        library.historyArchiveURL = store.historyArchiveURL
        library.history = { [weak sidebar, weakSelf = MainActorWeak(self), weak store] in
            guard let sidebar, let profile = store?.sidebar.space(sidebar.activeSpaceID)?.profileID else { return nil }
            return weakSelf.value?.engineProfiles[profile]?.history
        }
        library.profileID = { [weak sidebar, weak store] in
            guard let sidebar else { return nil }
            return store?.sidebar.space(sidebar.activeSpaceID)?.profileID
        }
        library.onOpen = { [weak tabs] url in _ = tabs?.openNewTab(url: url.absoluteString, transition: .link) }
        library.onRestore = { [weak self] id in self?.restoreArchived(id) }
        library.onClose = { [weak self] in self?.hideLibrary() }
        sidebar.onFooterSpaceSelected = { [weak self] in self?.hideLibrary() }
        session.downloads?.onOpenLibrary = { [weak self] in self?.showLibrary(section: .downloads) }
        session.library = library
        _ = tabs
    }

    var isLibraryShown: Bool { library.map { sidebar?.bodyView.replacementView === $0.view } ?? false }

    /// ⇧⌘L.
    @objc func toggleLibrary(_ sender: Any?) {
        if isLibraryShown { hideLibrary() } else { showLibrary(section: nil) }
    }

    /// ⌘Y: the Library at History (its search field has the keyboard).
    @objc func showHistory(_ sender: Any?) {
        showLibrary(section: .history)
    }

    func showLibrary(section: LibrarySection?) {
        ensureWindow()
        guard let sidebar, let library else { return }
        // With the sidebar hidden, its overlay is pinned open for the Library (spec §E).
        if windowController?.isSidebarOpen == false { hiddenSidebar?.revealPinned() }
        sidebar.bodyView.replacementView = library.view
        library.show(section: section)
    }

    func hideLibrary() {
        guard isLibraryShown, let sidebar else { return }
        let hadKeyboard = library?.hasKeyboard == true
        sidebar.bodyView.replacementView = nil
        if hadKeyboard { pageHost?.focusPage() }
    }

    /// Restore from the Archive (the Library's row, the palette's Enter): the
    /// tab goes back to its space (or the active one when its space is gone)
    /// at the top of Today, and is selected there.
    @discardableResult
    func restoreArchived(_ id: UUID) -> UUID? {
        guard let store, let sidebar else { return nil }
        do {
            // Into the window that asked (its Today list, 4.8a).
            let entry = try store.sidebar.restore(archived: id, activeSpace: sidebar.activeSpaceID, window: sidebar.windowID)
            if let space = entry.spaceID, space != sidebar.activeSpaceID { sidebar.showSpace(space) }
            sidebar.select(entry.id)
            return entry.id
        } catch {
            NSLog("Room: restore of archived \(id) failed: \(error)")
            return nil
        }
    }
}
