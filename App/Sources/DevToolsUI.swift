import AppKit
import Design

/// DevTools undocked (5.10): DevTools' own Dock side menu chose "Undock into separate window". The
/// front-end fills a window of Room's; its Dock side menu docks it back, and closing the window
/// closes DevTools.
final class DevToolsWindowController: NSWindowController, NSWindowDelegate {
    let host = FlippedPaneView()
    /// The window was closed by its close button (DevTools goes with it).
    var onClose: (() -> Void)?
    private var dismissing = false
    private static let autosaveName = "RoomDevToolsWindow"

    init(title: String?, parent: NSWindow?) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: DevToolsMetrics.windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title.map { "Developer Tools — \($0)" } ?? "Developer Tools"
        window.isReleasedWhenClosed = false
        let placed = window.setFrameUsingName(Self.autosaveName)
        window.setFrameAutosaveName(Self.autosaveName)
        if !placed, let parent {
            // Over the browser window's right half, the first time.
            window.setFrameTopLeftPoint(NSPoint(x: parent.frame.maxX - DevToolsMetrics.windowSize.width / 2, y: parent.frame.maxY - 40))
        }
        super.init(window: window)
        window.delegate = self
        host.setAccessibilityIdentifier("devtools-host")
        window.contentView = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() { window?.makeKeyAndOrderFront(nil) }

    /// Closes the window without closing DevTools again (the host already closed or docked it).
    func dismiss() {
        dismissing = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !dismissing { onClose?() }
    }
}
