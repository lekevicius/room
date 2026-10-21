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

    // MARK: Close and Zoom without their buttons (5.6b)

    /// The traffic lights hide with the sidebar (B-114), and AppKit's
    /// `perform…` methods refuse (a beep) while their button is hidden: ⇧⌘W
    /// and Window ▸ Zoom did nothing with the sidebar hidden (found by 5.6b's
    /// Window-menu check). With the button hidden they do what the button
    /// would. ⌘M still refuses (B-150: `miniaturize` too, even with the button
    /// shown transparent around the call).
    public override func performClose(_ sender: Any?) {
        guard standardWindowButton(.closeButton)?.isHidden == true else { return super.performClose(sender) }
        if let delegate, delegate.windowShouldClose?(self) == false { return }
        close()
    }

    public override func performZoom(_ sender: Any?) {
        guard standardWindowButton(.zoomButton)?.isHidden == true else { return super.performZoom(sender) }
        zoom(sender)
    }

    // MARK: Mouse back and forward (5.5a); the page under the titlebar (B-32, 5.6b)

    /// The mouse's back and forward buttons over the window outside a page (the sidebar, the
    /// header, the card's edges): `nil` lets the event through. Over a page the engine navigates.
    public var onMouseNavigation: ((MouseNavigation) -> Void)?
    /// Whether a view is (inside) a page, where the engine handles the buttons itself (the app sets it).
    public var isPageView: ((NSView) -> Bool)?
    /// Whether a view under the titlebar is the card's page rather than Room's chrome (B-32; set by the controller).
    public var isCardPage: ((NSView) -> Bool)?

    /// The full-size content puts the page under the 52 pt titlebar while the
    /// sidebar is hidden, and the engine's view lets AppKit treat a
    /// double-click there as the titlebar's (it zoomed or filled the window
    /// from a search field at the page's top, B-32). A double-click on the
    /// page goes to the page alone; the rest, and every press on Room's own
    /// views, take AppKit's path.
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .otherMouseUp || event.type == .otherMouseDown, let navigation = MouseNavigation(buttonNumber: event.buttonNumber),
           let onMouseNavigation, let frame = contentView?.superview ?? contentView {
            let hit = frame.hitTest(frame.convert(event.locationInWindow, from: nil))
            if !(hit.map { isPageView?($0) ?? false } ?? false) {
                if event.type == .otherMouseUp { onMouseNavigation(navigation) }
                return
            }
        }
        if event.type == .leftMouseDown || event.type == .leftMouseUp, event.clickCount >= 2,
           let target = pageViewUnderTitlebar(event) {
            if event.type == .leftMouseDown { target.mouseDown(with: event) } else { target.mouseUp(with: event) }
            return
        }
        super.sendEvent(event)
    }

    private func pageViewUnderTitlebar(_ event: NSEvent) -> NSView? {
        guard let isCardPage, !contentLayoutRect.contains(event.locationInWindow), let frameView = contentView?.superview,
              let hit = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil)), isCardPage(hit) else { return nil }
        return hit
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
