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

    // MARK: The page under the titlebar (B-32, 5.6b)

    /// The view is the page itself, not Room's chrome (set by the controller).
    public var isPageView: ((NSView) -> Bool)?

    /// The full-size content puts the page under the 52 pt titlebar while the
    /// sidebar is hidden, and the engine's view lets AppKit treat a
    /// double-click there as the titlebar's (it zoomed or filled the window
    /// from a search field at the page's top, B-32). A double-click on the
    /// page goes to the page alone; the rest, and every press on Room's own
    /// views, take AppKit's path.
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp, event.clickCount >= 2,
           let target = pageViewUnderTitlebar(event) {
            if event.type == .leftMouseDown { target.mouseDown(with: event) } else { target.mouseUp(with: event) }
            return
        }
        super.sendEvent(event)
    }

    private func pageViewUnderTitlebar(_ event: NSEvent) -> NSView? {
        guard let isPageView, !contentLayoutRect.contains(event.locationInWindow), let frameView = contentView?.superview,
              let hit = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil)), isPageView(hit) else { return nil }
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
