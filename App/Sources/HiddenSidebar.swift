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

    /// The "Sidebar hidden" toast shows once ever (spec §E).
    static let snapHintKey = "RoomSidebarSnapHintShown"

    init(controller: RoomWindowController, tabs: TabController, sidebar: SidebarController, palette: PaletteController, toasts: ToastCenter) {
        self.controller = controller
        self.tabs = tabs
        self.sidebar = sidebar
        self.toasts = toasts
        let sidebarView = controller.sidebarView
        controller.reveal.keepOpen = [
            { [weak palette] in palette?.isOpen == true },
            { [weak sidebar] in sidebar?.isSpaceFormOpen == true },
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

    /// Dragging the splitter under 120 pt hid the sidebar: once, a toast says how to get it back.
    private func sidebarSnappedClosed() {
        guard !UserDefaults.standard.bool(forKey: Self.snapHintKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.snapHintKey)
        toasts?.show(Toast(id: "sidebar-hidden", symbol: .toggleSidebar, message: "Sidebar hidden — press ⌘S to bring it back",
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

    /// File ▸ New Space while the sidebar is hidden: the form shows in the pinned overlay.
    func revealForSpaceForm() {
        guard let controller, isHidden, !controller.reveal.isPinned else { return }
        controller.reveal.togglePin()
    }

    /// Back/Forward/Reload follow the focused page.
    func update(_ page: (any WebContents)?) {
        navigation.update(canGoBack: page?.canGoBack ?? false, canGoForward: page?.canGoForward ?? false,
                          isLoading: page?.isLoading ?? false, hasPage: page != nil)
    }
}
