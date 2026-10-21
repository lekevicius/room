import AppKit
import Card
import Design

/// Owns one browser window: material, sidebar placeholder, splitter and card.
public final class RoomWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    /// Posted (object: the controller) when a splitter drag ends with the
    /// sidebar snapped closed. Chapter 2 shows the "Sidebar hidden" toast.
    public static let sidebarDidSnapClosedNotification = Notification.Name("RoomSidebarDidSnapClosed")

    public let rootView = BrowserWindowView()
    public var materialView: WindowMaterialView { rootView.materialView }
    public var sidebarView: SidebarView { rootView.sidebarView }
    public var cardView: CardView { rootView.cardView }

    public let trafficLights: TrafficLightLayout
    public let activity: WindowActivity
    /// The hidden sidebar's hover reveal (spec §E).
    public private(set) var reveal: SidebarRevealController!

    public init(contentSize: NSSize = RoomWindow.defaultContentSize) {
        let window = RoomWindow(contentRect: NSRect(origin: .zero, size: contentSize))
        window.contentView = rootView
        trafficLights = TrafficLightLayout(window: window)
        activity = WindowActivity(window: window)
        super.init(window: window)
        window.delegate = self
        window.center()

        rootView.trafficLights = trafficLights
        trafficLights.onChange = { [weak self] _ in
            self?.rootView.needsLayout = true
        }
        sidebarView.trafficLights = trafficLights.geometry
        activity.onChange = { [weak self] active in self?.applyActivity(active) }
        applyActivity(activity.isActive)

        rootView.splitterView.onDrag = { [weak self] proposed in self?.splitterDragged(to: proposed) }
        rootView.splitterView.onEnd = { [weak self] in self?.splitterDragEnded() }

        reveal = SidebarRevealController(rootView: rootView)
        // A double-click on the page under the titlebar is the page's (B-32).
        window.isPageView = { [weak self] view in self?.isPage(view) ?? false }
        rootView.onAvailabilityChange = { [weak self] in
            self?.reveal.availabilityChanged()
            self?.hiddenChromeChanged()
        }
        rootView.onOverlayChange = { [weak self] in self?.hiddenChromeChanged() }
        reveal.availabilityChanged()
        hiddenChromeChanged()
    }

    // MARK: The traffic lights while the sidebar is hidden (spec §E, B-114)

    /// Settings ▸ Appearance ▸ Grey window buttons (spec §I.12).
    public var monoTrafficLights: Bool {
        get { trafficLights.isMonochrome }
        set { trafficLights.isMonochrome = newValue }
    }

    /// View ▸ Show Toolbar.
    public var showsToolbar: Bool {
        get { rootView.showsToolbar }
        set { rootView.showsToolbar = newValue }
    }

    /// The sidebar, the overlay, the toolbar or fullscreen changed. The
    /// traffic lights live in the sidebar (B-114, amending spec §E): hidden
    /// with it, they fade in as the overlay slides in under them and out as
    /// it leaves; they stay where AppKit put them, only hidden (a hidden
    /// button takes no clicks). The card has no drag band (B-32, removed in
    /// 5.6b): the sidebar's areas move the window.
    private func hiddenChromeChanged() {
        let hide = rootView.hidesTrafficLights
        // In with the overlay's slide, out with its slide back; ⌘S hiding the docked sidebar fades them quickly.
        let duration = hide ? (rootView.isOverlayAnimating ? Motion.revealOut : Motion.fast) : (rootView.isOverlayShown ? Motion.revealIn : 0)
        trafficLights.setButtonsHidden(hide, duration: duration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The view is the page itself (the engine's view in the card), not a
    /// control, field or glass panel of Room's over it.
    private func isPage(_ view: NSView) -> Bool {
        guard view.isDescendant(of: cardView) else { return false }
        var current = view
        while current !== cardView {
            if current is NSControl || current is NSText || current is NSGlassEffectView { return false }
            guard let parent = current.superview else { return false }
            current = parent
        }
        return true
    }

    // MARK: Incognito (4.8b)

    /// The incognito window's look: the dark material whatever the system's
    /// appearance (`Palette.incognitoAppearance`) and "Incognito" under the
    /// sidebar's header row. Its tint is its space's theme colour
    /// (`Palette.incognitoTintHex`), set like any space's.
    public func applyIncognitoLook() {
        window?.appearance = NSAppearance(named: Palette.incognitoAppearance)
        sidebarView.badgeText = "Incognito"
    }

    /// The window shows the incognito look.
    public var isIncognito: Bool { sidebarView.badgeText != nil }

    // MARK: Sidebar

    /// The active space's name: the header title while no header view is
    /// set, and the window's title (Window menu, Mission Control).
    public var spaceTitle: String {
        get { sidebarView.title }
        set {
            sidebarView.title = newValue
            window?.title = newValue.isEmpty ? "Room" : newValue
        }
    }

    /// Stored width (180–500); kept while the sidebar is closed.
    public var sidebarWidth: CGFloat {
        get { rootView.sidebarWidth }
        set { rootView.sidebarWidth = min(max(newValue, SidebarMetrics.minWidth), SidebarMetrics.maxWidth) }
    }

    public var isSidebarOpen: Bool {
        get { rootView.isSidebarOpen }
        set { rootView.isSidebarOpen = newValue }
    }

    /// The user changed the sidebar's width or visibility (toggle, splitter
    /// drag end); programmatic changes do not call it. The store persists it.
    public var onSidebarStateChange: ((_ width: CGFloat, _ isOpen: Bool) -> Void)?

    /// The window moved or finished resizing (not while in fullscreen).
    public var onFrameChange: ((NSRect) -> Void)?

    /// The window is about to close.
    public var onWillClose: (() -> Void)?

    /// The window entered (`true`) or left window fullscreen.
    public var onFullscreenChange: ((Bool) -> Void)?

    /// ⌘S (spec §E): hides the sidebar, or docks it again (from the overlay too).
    /// Not `toggleSidebar:`: NSWindow answers that action itself (AppKit's own
    /// sidebar) and validates it disabled, ahead of its controller in the
    /// responder chain (2.7b; Room's menu routes through the app delegate).
    @objc public func toggleSidebarVisibility(_ sender: Any?) {
        isSidebarOpen.toggle()
        onSidebarStateChange?(sidebarWidth, isSidebarOpen)
    }

    /// ⌥⌘S (spec §E): pins the hidden sidebar's overlay open until ⌥⌘S, ⌘S
    /// or a click in the page.
    @objc public func toggleSidebarOverlayPin(_ sender: Any?) {
        reveal.togglePin()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebarVisibility(_:)) {
            menuItem.title = isSidebarOpen ? "Hide Sidebar" : "Show Sidebar"
            return !rootView.isPageFullscreen
        }
        if menuItem.action == #selector(toggleSidebarOverlayPin(_:)) {
            menuItem.state = reveal.isPinned ? .on : .off
            return !isSidebarOpen && !rootView.isPageFullscreen
        }
        return true
    }

    private var openWidthBeforeDrag: CGFloat?

    private func splitterDragged(to proposed: CGFloat) {
        if openWidthBeforeDrag == nil { openWidthBeforeDrag = sidebarWidth }
        switch SidebarResize.outcome(forProposedWidth: proposed) {
        case .open(let width):
            sidebarWidth = width
            isSidebarOpen = true
        case .closed:
            isSidebarOpen = false
        }
    }

    /// A splitter drag that ends under the snap width, as a person's would (spikes).
    public func debugSnapSidebarClosed() {
        splitterDragged(to: sidebarWidth - 40)
        splitterDragged(to: SidebarMetrics.minWidth / 3)
        splitterDragEnded()
    }

    private func splitterDragEnded() {
        defer {
            openWidthBeforeDrag = nil
            onSidebarStateChange?(sidebarWidth, isSidebarOpen)
        }
        guard !isSidebarOpen else { return }
        // Reopening restores the width the drag started from, not the minimum.
        if let width = openWidthBeforeDrag { sidebarWidth = width }
        NotificationCenter.default.post(name: Self.sidebarDidSnapClosedNotification, object: self)
    }

    // MARK: Activity and appearance

    /// Forces the active/inactive look (snapshots); `nil` follows focus.
    public var activityOverride: Bool? {
        get { activity.override }
        set {
            activity.override = newValue
            materialView.state = newValue.map { $0 ? .active : .inactive } ?? .followsWindowActiveState
            applyActivity(activity.isActive)
        }
    }

    private func applyActivity(_ active: Bool) {
        sidebarView.isWindowActive = active
        materialView.isWindowActive = active
    }

    // MARK: NSWindowDelegate

    // In fullscreen AppKit moves the toolbar into its own 52 pt window that
    // slides down with the menu bar; ours is empty (it only positions the
    // traffic lights), so it is hidden for the duration (Phase 1.4 spike).
    public func windowWillEnterFullScreen(_ notification: Notification) { window?.toolbar?.isVisible = false }
    public func windowDidEnterFullScreen(_ notification: Notification) {
        rootView.needsLayout = true
        onFullscreenChange?(true)
    }
    public func windowWillExitFullScreen(_ notification: Notification) { window?.toolbar?.isVisible = true }
    public func windowDidExitFullScreen(_ notification: Notification) {
        // Again here: after a page's element fullscreen the toolbar came back hidden from the
        // transition (2.6b), leaving the traffic lights at 9,9 instead of 19,19.
        window?.toolbar?.isVisible = true
        rootView.needsLayout = true
        onFullscreenChange?(false)
    }

    public func windowDidMove(_ notification: Notification) { reportFrame() }
    public func windowDidEndLiveResize(_ notification: Notification) { reportFrame() }
    public func windowDidResize(_ notification: Notification) {
        if window?.inLiveResize == false { reportFrame() }
    }
    public func windowWillClose(_ notification: Notification) { onWillClose?() }

    private func reportFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        onFrameChange?(window.frame)
    }

    /// Restores a saved frame if it is still on a screen; otherwise keeps the
    /// centred default. Returns whether it applied.
    @discardableResult
    public func restoreFrame(_ frame: NSRect) -> Bool {
        guard let window, frame.width >= window.minSize.width, frame.height >= window.minSize.height,
              let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) else { return false }
        window.setFrame(window.constrainFrameRect(frame, to: screen), display: false)
        return true
    }
}

/// The window's content view: material behind everything, the sidebar on its
/// side (left unless Settings says right), the card inset on the other three,
/// the splitter on top.
/// With the sidebar hidden, the same sidebar view floats in `overlayView`
/// while the hover reveal shows it (spec §E).
public final class BrowserWindowView: NSView {
    public let materialView = WindowMaterialView()
    public let sidebarView = SidebarView()
    public let cardView = CardView()
    let splitterView = SidebarSplitterView()
    /// The hidden sidebar's floating glass overlay (spec §E).
    public let overlayView = SidebarOverlayView()
    /// View ▸ Show Toolbar (spec §E), across the card's top.
    public let toolbarView = PageToolbarView()
    weak var trafficLights: TrafficLightLayout?

    /// The optional toolbar shows (not while a page is fullscreen).
    public var showsToolbar = false {
        didSet {
            guard showsToolbar != oldValue else { return }
            updateToolbar()
            onAvailabilityChange?()
        }
    }

    /// The traffic lights hide with the sidebar (B-114): the sidebar hidden on the left without its
    /// overlay, no toolbar (whose leading end holds them), no fullscreen page (they are in the menu
    /// bar's window then).
    public var hidesTrafficLights: Bool {
        !isSidebarOpen && !isOverlayShown && !isPageFullscreen && !showsToolbar
    }

    /// Nothing of the sidebar is under the traffic lights: they sit over the card's top-left corner.
    var buttonsOverCard: Bool {
        !isSidebarOpen && !isOverlayShown && !isOverlayAnimating
    }

    public var sidebarWidth: CGFloat = SidebarMetrics.defaultWidth {
        didSet { if sidebarWidth != oldValue { needsLayout = true } }
    }

    /// The sidebar is docked beside the card (`false`: hidden, spec §E).
    public var isSidebarOpen = true {
        didSet {
            guard isSidebarOpen != oldValue else { return }
            // Docking takes the sidebar out of the overlay at once.
            if isSidebarOpen, isOverlayShown || isOverlayAnimating { finishOverlay(shown: false) }
            needsLayout = true
            layoutSubtreeIfNeeded()
            onAvailabilityChange?()
        }
    }

    /// A page in element fullscreen: the card fills the window edge to edge.
    public var isPageFullscreen = false {
        didSet {
            guard isPageFullscreen != oldValue else { return }
            cardView.isEdgeToEdge = isPageFullscreen
            updateToolbar()
            if isPageFullscreen, isOverlayShown || isOverlayAnimating { finishOverlay(shown: false) }
            needsLayout = true
            layoutSubtreeIfNeeded()
            onAvailabilityChange?()
        }
    }

    /// The overlay is shown (or sliding in).
    public private(set) var isOverlayShown = false
    /// The slide is running; the animation owns the overlay's origin.
    public private(set) var isOverlayAnimating = false
    private var overlayGeneration = 0

    /// Called after every layout pass (overlays such as toasts re-anchor).
    public var onLayout: (() -> Void)?
    /// The sidebar was hidden or docked, a page entered or left fullscreen, the toolbar came or went.
    var onAvailabilityChange: (() -> Void)?
    /// The overlay started or finished sliding in or out (the traffic lights come and go with it).
    var onOverlayChange: (() -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        cardView.setAccessibilityIdentifier("card")
        overlayView.isHidden = true
        addSubview(materialView)
        addSubview(sidebarView)
        addSubview(cardView)
        addSubview(splitterView)
        // Above the card and everything the window adds over it later stays above (palette, toasts).
        addSubview(overlayView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    public var currentLayout: WindowLayout {
        WindowLayout.compute(bounds: bounds, sidebarWidth: sidebarWidth, isSidebarOpen: isSidebarOpen, pageFullscreen: isPageFullscreen)
    }

    /// Where the overlay sits while shown.
    public var overlayFrame: CGRect { WindowLayout.overlayFrame(bounds: bounds, sidebarWidth: sidebarWidth) }

    /// The traffic lights as the sidebar view at `origin` sees them.
    private func sidebarTrafficLights(_ geometry: TrafficLightGeometry, origin: CGPoint) -> TrafficLightGeometry {
        geometry.relative(to: origin)
    }

    /// The sidebar view lives in the overlay whenever the sidebar is hidden, the overlay shown or
    /// not: a reveal then only shows and slides it. Moving the sidebar into the overlay as the
    /// slide began cost 40 ms on the main thread and three frames of the slide (5.1b's motion
    /// harness); ⌘S pays it now, while nothing slides.
    private var sidebarInOverlay: Bool { !isSidebarOpen && !isPageFullscreen }

    public override func layout() {
        super.layout()
        trafficLights?.update()
        let layout = currentLayout
        let geometry = trafficLights?.geometry ?? .none
        placeSidebar()
        if sidebarInOverlay {
            let frame = overlayFrame
            if isOverlayAnimating { overlayView.setFrameSize(frame.size) } else { overlayView.frame = frame }
            sidebarView.isHidden = false
            sidebarView.frame = CGRect(origin: .zero, size: frame.size)
            // The header lays out around the buttons where the overlay will rest.
            sidebarView.trafficLights = sidebarTrafficLights(geometry, origin: frame.origin)
        } else {
            sidebarView.isHidden = !isSidebarOpen || isPageFullscreen
            if isSidebarOpen {
                sidebarView.frame = layout.sidebar
                sidebarView.trafficLights = sidebarTrafficLights(geometry, origin: .zero)
            } else {
                // Hidden, it keeps the overlay's size: a reveal only moves it (no relayout of
                // the list, and no zero-height list whose overflow lines would show).
                let frame = overlayFrame
                sidebarView.frame = CGRect(origin: .zero, size: frame.size)
                sidebarView.trafficLights = sidebarTrafficLights(geometry, origin: frame.origin)
            }
        }
        cardView.frame = layout.card
        if showsToolbar {
            // The traffic lights over the card: they sit in the bar's leading end.
            if buttonsOverCard, let buttons = geometry.buttonsRect {
                toolbarView.leadingInset = buttons.maxX + SidebarMetrics.headerLeadingGap - layout.card.minX
                toolbarView.contentCenterY = buttons.midY - layout.card.minY
            } else {
                toolbarView.leadingInset = ToolbarMetrics.padding
                toolbarView.contentCenterY = nil
            }
        }
        splitterView.isHidden = layout.splitter == nil
        splitterView.frame = layout.splitter ?? .zero
        splitterView.currentWidth = layout.sidebar.width
        onLayout?()
    }

    private func updateToolbar() {
        let shown = showsToolbar && !isPageFullscreen
        if (cardView.topAccessory != nil) != shown { cardView.topAccessory = shown ? toolbarView : nil }
        needsLayout = true
    }

    private func placeSidebar() {
        let inOverlay = sidebarInOverlay
        let target = inOverlay ? overlayView.contentView : self
        if sidebarView.superview !== target {
            // Moved straight across (no `removeFromSuperview` first, which takes the whole
            // tree out of the window and back: viewWillMove(toWindow:) for every row).
            if inOverlay {
                overlayView.contentView.addSubview(sidebarView)
            } else {
                addSubview(sidebarView, positioned: .above, relativeTo: materialView)
            }
        }
        sidebarView.autoresizingMask = inOverlay ? [.width, .height] : []
    }

    // MARK: The overlay (spec §E)

    /// Slides the hidden sidebar in over the card (`Motion.revealIn`, ease-out)
    /// or out again (`Motion.revealOut`, ease-in); Reduce Motion fades it
    /// instead (`WindowMotion.reveal`). Ignored while the sidebar is docked or
    /// a page is fullscreen.
    public func setOverlayShown(_ shown: Bool, animated: Bool = true) {
        guard shown != isOverlayShown else { return }
        if shown, isSidebarOpen || isPageFullscreen { return }
        isOverlayShown = shown
        overlayGeneration += 1
        let generation = overlayGeneration
        let frame = overlayFrame
        // Fully off its edge of the window, its shadow included.
        let away = frame.offsetBy(dx: -(frame.maxX + Spacing.l), dy: 0)
        let variant = WindowMotion.reveal.variant
        guard animated, variant != .instant else { return finishOverlay(shown: shown) }
        let reduceMotion = variant == .crossfade
        if shown, !isOverlayAnimating {
            overlayView.frame = reduceMotion ? frame : away
            overlayView.alphaValue = reduceMotion ? 0 : 1
        }
        isOverlayAnimating = true
        // The traffic lights fade with the slide (B-114).
        onOverlayChange?()
        overlayView.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = shown ? Motion.revealIn : Motion.revealOut
            context.timingFunction = CAMediaTimingFunction(name: shown ? .easeOut : .easeIn)
            if reduceMotion {
                overlayView.animator().alphaValue = shown ? 1 : 0
            } else {
                overlayView.animator().setFrameOrigin(shown ? frame.origin : away.origin)
            }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.overlayGeneration else { return }
                self.finishOverlay(shown: shown)
            }
        })
    }

    /// Ends the slide where it was going (or jumps there).
    private func finishOverlay(shown: Bool) {
        overlayGeneration += 1
        isOverlayAnimating = false
        isOverlayShown = shown && !isSidebarOpen && !isPageFullscreen
        onOverlayChange?()
        overlayView.alphaValue = 1
        overlayView.isHidden = !isOverlayShown
        if isOverlayShown { overlayView.frame = overlayFrame }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}
