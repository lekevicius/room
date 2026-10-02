import AppKit

/// The browser window: full-size content, transparent titlebar, no title, no
/// tabbing. The traffic lights stay exactly where AppKit puts them; the
/// layout reads their frames through `TrafficLightLayout`.
public final class RoomWindow: NSWindow {
    public static let defaultContentSize = NSSize(width: 1280, height: 800)
    public static let minimumContentSize = NSSize(width: 600, height: 400)

    public init(contentRect: NSRect = NSRect(origin: .zero, size: RoomWindow.defaultContentSize)) {
        NSWindow.allowsAutomaticWindowTabbing = false
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // Kept for the Window menu and Mission Control; never drawn.
        title = "Room"
        tabbingMode = .disallowed
        // Only the sidebar background moves the window (it calls `performDrag`).
        isMovableByWindowBackground = false
        collectionBehavior.insert(.fullScreenPrimary)
        contentMinSize = Self.minimumContentSize
        isReleasedWhenClosed = false
        // Follow the system appearance.
        appearance = nil
    }
}
