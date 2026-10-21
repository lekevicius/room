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
        // An empty unified toolbar gives the 52pt titlebar Dia uses: AppKit
        // itself places the traffic lights further in and vertically centred
        // in it. We never move them; this only selects AppKit's own layout.
        let toolbar = NSToolbar(identifier: "RoomWindowToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        toolbarStyle = .unified
        titlebarSeparatorStyle = .none
        // Follow the system appearance.
        appearance = nil
    }

    // MARK: Mouse back and forward (5.5a)

    /// The mouse's back and forward buttons over the window outside a page (the sidebar, the
    /// header, the card's edges): `nil` lets the event through. Over a page the engine navigates.
    public var onMouseNavigation: ((MouseNavigation) -> Void)?
    /// Whether a view is (inside) a page, where the engine handles the buttons itself.
    public var isPageView: ((NSView) -> Bool)?

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .otherMouseUp || event.type == .otherMouseDown, let navigation = MouseNavigation(buttonNumber: event.buttonNumber),
           let onMouseNavigation, let frame = contentView?.superview ?? contentView {
            let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil))
            if !(hit.map { isPageView?($0) ?? false } ?? false) {
                if event.type == .otherMouseUp { onMouseNavigation(navigation) }
                return
            }
        }
        super.sendEvent(event)
    }

    // MARK: Tab order (5.3a)

    /// The Tab order's regions (`KeyViewLoop`), from the app: sidebar, header, card, footer.
    /// `nil` leaves AppKit's own loop.
    public var keyViewRegions: (() -> [KeyViewRegion])?

    public override func selectNextKeyView(_ sender: Any?) {
        if !selectInLoop(forward: true, from: firstResponder) { super.selectNextKeyView(sender) }
    }

    public override func selectPreviousKeyView(_ sender: Any?) {
        if !selectInLoop(forward: false, from: firstResponder) { super.selectPreviousKeyView(sender) }
    }

    public override func selectKeyView(following view: NSView) {
        if !selectInLoop(forward: true, from: view) { super.selectKeyView(following: view) }
    }

    public override func selectKeyView(preceding view: NSView) {
        if !selectInLoop(forward: false, from: view) { super.selectKeyView(preceding: view) }
    }

    /// AppKit's own selection, for `selectInLoop` (its overrides above route here).
    func appKitSelect(following view: NSView) { super.selectKeyView(following: view) }
    func appKitSelect(preceding view: NSView) { super.selectKeyView(preceding: view) }
}

/// What the mouse's side buttons do (5.5a): button 4 (`buttonNumber` 3) back, button 5 (4) forward.
public enum MouseNavigation: Equatable, Sendable {
    case back, forward

    public init?(buttonNumber: Int) {
        switch buttonNumber {
        case 3: self = .back
        case 4: self = .forward
        default: return nil
        }
    }
}
