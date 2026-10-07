import AppKit
import Chrome
import Engine
import Sidebar
import Tabs
import UIKitCore

/// The header's extension action buttons and their popups (ROADMAP 3.6b):
/// the active space's pinned extensions beside the site button, with the
/// focused page's badges, refreshed whenever the engine reports an action
/// change or the page changes; a click runs the action, and the popup the
/// engine opens shows in an `ExtensionPopover` on that button (or on the
/// card's corner while the sidebar is hidden). The popover closing by
/// itself (focus loss, Esc) tells the engine through the center. Unpinned
/// actions are in the overflow menu (4.5): a click there runs the action
/// and its popup points at the overflow button; "Pin" pins it.
final class ExtensionPopups: ExtensionPopupPresenting {
    private let center: ExtensionsCenter
    private weak var sidebar: SidebarController?
    private weak var tabs: TabController?
    private weak var rootView: BrowserWindowView?
    private(set) var popover: ExtensionPopover?

    #if DEBUG
    /// Spikes hear each popover once it is on screen (to time and capture it).
    static var debugOnShow: ((ExtensionPopover, String) -> Void)?
    static var debugOnResize: ((CGSize) -> Void)?
    static var debugOnClose: ((_ byEngine: Bool) -> Void)?
    #endif

    init(center: ExtensionsCenter, sidebar: SidebarController, tabs: TabController, rootView: BrowserWindowView) {
        self.center = center
        self.sidebar = sidebar
        self.tabs = tabs
        self.rootView = rootView
        // The center's presenter is the app's router (one per app; it picks this window for its pages, 4.8a).
        sidebar.addressField.onExtensionAction = { [weak self] id in self?.run(id) }
        sidebar.addressField.onExtensionPin = { [weak self] id in self?.pin(id) }
        observe()
    }

    private var profileID: UUID? { sidebar?.activeSpace?.profileID }

    /// The buttons follow the engine's actions and the focused page.
    private func observe() {
        let actions = withObservationTracking {
            _ = center.actionRevision
            _ = center.sections.map(\.installed)
            return center.headerActions(profile: profileID, page: tabs?.focusedPage)
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.observe() }
        }
        sidebar?.addressField.setExtensionActions(actions)
        sidebar?.addressField.setOverflowActions(center.overflowActions(profile: profileID, page: tabs?.focusedPage))
    }

    /// The overflow menu's "Pin": the action joins the header at the end of the pinned order.
    func pin(_ id: InstalledExtension.ID) {
        guard let section = center.section(profile: profileID),
              let item = section.installed.first(where: { $0.id == id }) else { return }
        center.setPinned(true, item, in: section)
    }

    /// A click on `id`'s button.
    func run(_ id: InstalledExtension.ID) {
        guard let page = tabs?.focusedPage else { return }
        center.runAction(id, profile: profileID, page: page)
    }

    // MARK: ExtensionPopupPresenting

    func showPopup(_ popup: any WebContents, for id: InstalledExtension.ID, page: (any WebContents)?, size: CGSize) {
        popover?.close()
        let popover = ExtensionPopover(popup: popup, size: size)
        popover.onClose = { [weak self, weak popover] in
            guard let self, let popover, self.popover === popover else { return }
            self.popover = nil
            self.center.popoverDidClose(popover.popup)
            #if DEBUG
            Self.debugOnClose?(false)
            #endif
        }
        self.popover = popover
        if let button = sidebar?.addressField.extensionButton(for: id), button.window != nil,
           rootView?.isSidebarOpen == true {
            popover.show(relativeTo: button.bounds, of: button)
        } else if let rootView {
            // The sidebar is hidden: the card's top-left corner.
            let card = rootView.currentLayout.card
            popover.show(relativeTo: NSRect(x: card.minX + 16, y: card.maxY - 8, width: 1, height: 1), of: rootView)
        }
        #if DEBUG
        Self.debugOnShow?(popover, id)
        #endif
    }

    func resizePopup(_ popup: any WebContents, to size: CGSize) {
        guard let popover, popover.popup === popup else { return }
        popover.resize(size)
        #if DEBUG
        Self.debugOnResize?(size)
        #endif
    }

    func closePopup(_ popup: any WebContents) {
        guard let popover, popover.popup === popup else { return }
        self.popover = nil
        popover.close()
        #if DEBUG
        Self.debugOnClose?(true)
        #endif
    }
}
