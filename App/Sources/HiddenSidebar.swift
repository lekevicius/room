import AppKit
import Chrome
import Design
import Engine
import Model
import Observation
import Palette
import Sidebar
import Tabs
import UIKitCore

/// The hidden sidebar (spec §E): what keeps the hover-revealed overlay open,
/// Back/Forward/Reload in the sidebar's top bar (docked or revealed), and the toasts that stand in for what
/// the hidden sidebar would have shown.
@MainActor
final class HiddenSidebar {
    private weak var controller: RoomWindowController?
    private weak var tabs: TabController?
    private weak var sidebar: SidebarController?
    private weak var toasts: ToastCenter?
    let navigation = NavigationButtonsView(buttonSize: SidebarMetrics.topBarButtonSize)
    private var snapToken: NSObjectProtocol?

    /// View ▸ Show Sidebar's key as the Shortcuts table has it (`applyShortcuts`), for the hint's line.
    static var toggleKey: String? = "⌘S"

    init(controller: RoomWindowController, tabs: TabController, sidebar: SidebarController, palette: PaletteController, toasts: ToastCenter) {
        self.controller = controller
        self.tabs = tabs
        self.sidebar = sidebar
        self.toasts = toasts
        let sidebarView = controller.sidebarView
        controller.reveal.keepOpen = [
            { [weak palette] in palette?.isOpen == true },
            // An inline rename (or any field) in the sidebar.
            { [weak sidebarView] in
                guard let sidebarView, let editor = sidebarView.window?.firstResponder as? NSTextView, editor.isFieldEditor,
                      let field = editor.delegate as? NSView else { return false }
                return field.isDescendant(of: sidebarView)
            },
        ]
        palette.onClose = { [weak controller] in controller?.reveal.keepOpenChanged() }

        navigation.onBack = { [weak tabs] in tabs?.focusedPage?.goBack() }
        navigation.onForward = { [weak tabs] in tabs?.focusedPage?.goForward() }
        navigation.onReload = { [weak tabs] in
            guard let page = tabs?.focusedPage else { return }
            page.isLoading ? page.stop() : page.reload()
        }
        sidebarView.navigationView = navigation

        snapToken = NotificationCenter.default.addObserver(forName: RoomWindowController.sidebarDidSnapClosedNotification, object: controller,
                                                           queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sidebarSnappedClosed() }
        }
        tabs.onBackgroundTabOpened = { [weak self] _ in self?.backgroundTabOpened() }
        sidebar.onSpaceCreated = { [weak self] space in self?.spaceCreated(space) }
    }

    isolated deinit {
        if let snapToken { NotificationCenter.default.removeObserver(snapToken) }
    }

    private var isHidden: Bool { controller?.isSidebarOpen == false }

    /// Dragging the splitter under 120 pt hid the sidebar: once per state (its
    /// settings remember it, 5.6b), a toast says how to get it back.
    private func sidebarSnappedClosed() {
        guard let settings = sidebar?.store.settings else { return }
        var shows = false
        settings.update { shows = SidebarHiddenHint.take(&$0) }
        guard shows else { return }
        toasts?.show(Toast(id: "sidebar-hidden", symbol: .toggleSidebar, message: SidebarHiddenHint.message(toggleKey: Self.toggleKey),
                           duration: Timing.toastWithAction))
    }

    private func backgroundTabOpened() {
        guard isHidden, controller?.reveal.isShown == false else { return }
        toasts?.show(Toast(id: "background-tab", symbol: .newTab, message: "New background tab opened"))
    }

    private func spaceCreated(_ space: Space) {
        guard isHidden else { return }
        toasts?.show(Toast(id: "space-created", symbol: .newSpace, message: "Created “\(space.name)”"))
    }

    /// The sidebar's overlay pinned open while the sidebar is hidden: for the Library, an inline rename (spec §E).
    func revealPinned() {
        guard let controller, isHidden, !controller.reveal.isPinned else { return }
        controller.reveal.togglePin()
    }

    /// Back/Forward/Reload follow the focused page.
    func update(_ page: (any WebContents)?) {
        navigation.update(canGoBack: page?.canGoBack ?? false, canGoForward: page?.canGoForward ?? false,
                          isLoading: page?.isLoading ?? false, hasPage: page != nil)
    }
}
