import AppKit
import Chrome
import Design
import Engine
import FakeEngine
import Foundation
import Library
import Model
import Palette
import Sidebar
import Store
import Tabs
import Testing
import UIKitCore

/// The browser window as the app assembles it, from the packages: the
/// sidebar (Essentials, a folder, pinned and Today rows, an audible one, the
/// footer's two spaces) in a `RoomWindowController`, toasts, the palette and
/// the Library, on FakeEngine pages. On screen (window tier).
@MainActor
final class BrowserWindowFixture {
    let directory: URL
    let engine = FakeApplication()
    let store: RoomStore
    let controller: RoomWindowController
    let sidebar: SidebarController
    let tabs: TabController
    let palette: PaletteController
    let toasts: ToastCenter
    let library: LibraryController
    let today: [UUID]

    var window: NSWindow { controller.window! }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "RoomAccessibilityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try engine.initialize(EngineConfiguration(userDataDirectory: directory))
        let store = try RoomStore.open(directory: directory)
        self.store = store
        let space = store.sidebar.spaces[0]
        let record = store.windows.restoreOrCreateWindow(defaultSidebarWidth: 280, space: space.id)
        for index in 0..<2 { try store.sidebar.addEntry(.essential, url: "https://e\(index).example/", title: "Essential \(index)", space: space.id) }
        let folder = try store.sidebar.addFolder(name: "Reading", space: space.id)
        try store.sidebar.addEntry(.pinned, url: "https://f.example/", title: "In folder", space: space.id, folder: folder.id)
        try store.sidebar.addEntry(.pinned, url: "https://p.example/", title: "Pinned", space: space.id)
        today = try (0..<3).map { try store.sidebar.addEntry(.today, url: "https://t\($0).example/", title: "Today \($0)", space: space.id, window: record.id).id }
        _ = try store.sidebar.createSpace(name: "Work", profile: space.profileID, icon: "briefcase", themeColors: [])

        sidebar = SidebarController(store: store, windowID: record.id)
        tabs = TabController(store: store)
        tabs.sidebar = sidebar
        tabs.profile = try engine.profile(named: "Default")
        sidebar.host = tabs
        controller = RoomWindowController(contentSize: NSSize(width: 1100, height: 720))
        controller.sidebarView.headerView = sidebar.addressField
        controller.sidebarView.accessoryView = sidebar.extensionBar
        controller.sidebarView.bodyView = sidebar.bodyView
        let rootView = controller.rootView
        toasts = ToastCenter(hostView: rootView) { [weak rootView] in
            ToastCenter.Anchor(rect: rootView?.currentLayout.sidebar ?? .zero, alignment: .center)
        }
        sidebar.toasts = toasts
        palette = PaletteController(hostView: rootView, tabs: tabs, sidebar: sidebar)
        library = LibraryController(store: store, downloads: DownloadList())
        // The app's Tab order (AppDelegate.installSidebar), without Peek.
        let sidebarController = sidebar
        (controller.window as? RoomWindow)?.keyViewRegions = { [weak sidebarController, weak controller] in
            guard let sidebarController, let controller else { return [] }
            return [KeyViewRegion([sidebarController.bodyView], excluding: [sidebarController.footerView]),
                    KeyViewRegion([controller.sidebarView, controller.rootView.toolbarView], excluding: [sidebarController.bodyView]),
                    KeyViewRegion([controller.cardView]),
                    KeyViewRegion([sidebarController.footerView])]
        }
        sidebar.select(today[0])
        // An audible page in the list (the row's state and its Mute action).
        if let entry = store.sidebar.entry(today[1]), let page = tabs.loadInBackground(entry) as? FakeWebContents {
            page.simulateAudio(true)
            sidebar.pageStateDidChange([today[1]])
        }
        controller.window?.orderFrontRegardless()
        controller.window?.layoutIfNeeded()
    }

    isolated deinit {
        controller.close()
        store.close()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Lets AppKit and SwiftUI lay out and build their trees: run-loop turns until `condition` (at most `turns`).
    func settle(turns: Int = 20, until condition: () -> Bool = { false }) {
        for _ in 0..<turns where !condition() {
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    func audit() -> AccessibilityAudit.Report { AccessibilityAudit.audit(window) }
}

@Suite("Accessibility self-audit (5.3a)", .serialized, .tags(.window), .localOnly)
struct AccessibilityAuditTests {
    init() { AccessibilityAudit.requestTree() }

    /// ROADMAP 5.3 task 1: no interactive element without a label, none with a generic role, no hidden click target.
    @Test("The window: sidebar, header, footer, Essentials; then the palette, a toast, the Library")
    func audit() throws {
        let f = try BrowserWindowFixture()
        f.settle()
        let rest = f.audit()
        #expect(rest.interactive > 10, "the tree was walked: \(rest.summary)")
        #expect(rest.findings.isEmpty, "at rest: \(rest.findings)")

        f.palette.toggleNew()
        f.palette.setText("Today")
        f.settle()
        #expect(f.palette.isOpen)
        let palette = f.audit()
        #expect(palette.findings.isEmpty, "the palette: \(palette.findings)")
        f.palette.dismiss()

        f.toasts.show(Toast(id: "audit", symbol: .clearToday, message: "3 tabs closed", action: Toast.Action(title: "Undo") {}, duration: 60))
        f.settle()
        let toast = f.audit()
        #expect(toast.findings.isEmpty, "a toast: \(toast.findings)")
        #expect(Announcement.last == "3 tabs closed. Undo available.")
        f.toasts.dismiss(id: "audit")

        f.sidebar.bodyView.replacementView = f.library.view
        f.library.show()
        f.settle()
        let library = f.audit()
        #expect(library.findings.isEmpty, "the Library: \(library.findings)")
        f.sidebar.bodyView.replacementView = nil
    }
}

/// ROADMAP 5.3 task 2: the Tab order is sidebar → header → card → footer and
/// around again, in macOS's default keyboard mode (lists, text fields and
/// the page) and with Full Keyboard Access (every control); walked through
/// the window's own key-view selection.
@Suite("Tab order (5.3a)", .serialized, .tags(.window), .localOnly)
struct KeyViewLoopTests {
    /// A view's name in the order: its identifier, else its label.
    private func name(_ responder: NSResponder?) -> String {
        guard let view = responder as? NSView else { return "nil" }
        if !view.accessibilityIdentifier().isEmpty { return view.accessibilityIdentifier() }
        return (view as? NSControl)?.cell?.accessibilityLabel() ?? view.accessibilityLabel() ?? String(describing: type(of: view))
    }

    /// Tab from the list until the focus is back on it.
    private func walk(_ f: BrowserWindowFixture) -> [String] {
        let window = f.window
        window.makeFirstResponder(f.sidebar.debugOutline)
        var names = [name(window.firstResponder)]
        for _ in 0..<30 {
            window.selectNextKeyView(nil)
            let current = name(window.firstResponder)
            if current == names[0] { break }
            names.append(current)
        }
        return names
    }

    @Test("Default mode: the list, then the address field; buttons are not stops")
    func defaultMode() throws {
        KeyboardAccess.allControlsOverride = false
        defer { KeyboardAccess.allControlsOverride = nil }
        let f = try BrowserWindowFixture()
        f.settle()
        #expect(walk(f) == ["sidebar-outline", "address-field"])
    }

    @Test("Full Keyboard Access: the sidebar's controls, the header's, the footer's, in that order")
    func allControls() throws {
        KeyboardAccess.allControlsOverride = true
        defer { KeyboardAccess.allControlsOverride = nil }
        let f = try BrowserWindowFixture()
        f.settle()
        let order = walk(f)
        // The walk starts on the list (inside the sidebar, after the Essentials): around to the Essentials last.
        let expected = ["sidebar-outline", "sidebar-toggle", "address-field", "site-button", "downloads", "Space", "Work", "footer-plus",
                        "essential", "essential"]
        #expect(order.filter(expected.contains) == expected, "\(order)")
        // Back and Forward are stops only when they can act (no page history here); Reload with a page.
        #expect(!order.contains("nav-back"))
    }

    @Test("⇧Tab walks the same order backwards")
    func backwards() throws {
        KeyboardAccess.allControlsOverride = true
        defer { KeyboardAccess.allControlsOverride = nil }
        let f = try BrowserWindowFixture()
        f.settle()
        let forward = walk(f)
        let window = f.window
        window.makeFirstResponder(f.sidebar.debugOutline)
        var backward = [name(window.firstResponder)]
        for _ in 1..<forward.count {
            window.selectPreviousKeyView(nil)
            backward.append(name(window.firstResponder))
        }
        #expect(backward == [forward[0]] + forward.dropFirst().reversed())
    }
}
