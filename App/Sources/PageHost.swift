import AppKit
import Card
import Design
import Engine
import Observation
import Tabs
import UIKitCore

/// Shows the selected entry's page in the window's card, or its split
/// (spec §D: up to four panes in a `SplitView`, the focused pane's page is
/// `contents`), and keeps the card's fill on the focused page's root
/// background, so live resize and loading never expose the window material
/// at the card edges. With no page it shows the empty state ("Press ⌘T…",
/// spec §A.7). A press in a pane focuses it (focus follows click).
final class PageHost: PageDisplay {
    let splitView = SplitView()
    /// The focused pane's container: the prompts, the find bar, the zoom
    /// indicator, the status pill and DevTools follow it.
    var container: PageContainerView { splitView.focusedPane.container }
    private weak var controller: RoomWindowController?
    private(set) var contents: (any WebContents)?
    private var pendingSplit: SplitPresentation?
    /// The page in the card changed (the page's prompts follow it, 2.6a).
    var onShow: (((any WebContents)?) -> Void)?
    /// A press in another pane of the split: its entry becomes the focused one.
    var onFocusPane: ((UUID) -> Void)?
    private var pressMonitor: Any?
    #if DEBUG
    /// Spikes: a press focused another pane — the main-thread time to the field updated, and to the next frame.
    var debugFocusTiming: ((_ handled: Double, _ toFrame: Double) -> Void)?
    #endif

    init(controller: RoomWindowController) {
        self.controller = controller
        controller.cardView.contentView = splitView
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.pressed(event)
            return event
        }
    }

    isolated deinit {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
    }

    func showSplit(_ split: SplitPresentation?) {
        pendingSplit = split
    }

    func show(_ contents: (any WebContents)?) {
        let split = pendingSplit
        let changed = contents !== self.contents || container.pageView == nil
        if changed {
            self.contents?.devTools?.close()
            container.isDevToolsOpen = false
            devToolsWindow?.dismiss()
            devToolsWindow = nil
        }
        let keyboardInSplit = splitView.isSplit && isFirstResponderInSplit
        self.contents = contents
        splitView.apply(split, focused: contents)
        // B-113: a split's panes are cards of their own; the page card steps back.
        controller?.cardView.isSplitHost = split != nil
        // 5.10: one page is edge to edge; a split's panes keep the inset.
        controller?.rootView.isCardInset = split != nil
        // ⌃⇧1…4 and ⌃⇧] / ⌃⇧[ move the keyboard with the focus (a click already put it there).
        if changed, split != nil, keyboardInSplit { focusPage() }
        guard changed else { return }
        trackBackground()
        onShow?(contents)
    }

    /// Whether the keyboard is in one of the split's pages.
    private var isFirstResponderInSplit: Bool {
        guard let view = splitView.window?.firstResponder as? NSView else { return false }
        return view.isDescendant(of: splitView)
    }

    /// Focus follows click (spec §D): a press inside another pane's page
    /// focuses that pane; the press goes on to the page.
    private func pressed(_ event: NSEvent) {
        guard splitView.isSplit, let window = splitView.window, event.window === window,
              let hit = window.contentView?.hitTest(window.contentView?.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        else { return }
        guard let pane = splitView.panes.first(where: { hit.isDescendant(of: $0.container) }), let entry = pane.entry,
              pane !== splitView.focusedPane else { return }
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        #endif
        onFocusPane?(entry)
        #if DEBUG
        let handled = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let timing = debugFocusTiming
        CATransaction.setCompletionBlock { timing?(handled, (ProcessInfo.processInfo.systemUptime - start) * 1000) }
        #endif
    }

    /// Puts the keyboard in the page: the first view in its tree that takes
    /// it (Chromium's render widget view inside our container).
    func focusPage() {
        guard let window = container.window else { return }
        guard let root = contents?.nativeView else {
            window.makeFirstResponder(nil)
            return
        }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.acceptsFirstResponder {
                window.makeFirstResponder(view)
                return
            }
            queue += view.subviews
        }
        window.makeFirstResponder(root)
    }

    var isDevToolsOpen: Bool { container.isDevToolsOpen || devToolsWindow != nil || contents?.devTools?.isOpen == true }

    /// Where DevTools shows (5.10): docked at the card's bottom, right or left, or in its own window;
    /// the pane's header and the window's change it. Remembered across launches.
    private(set) var devToolsPlacement = DevToolsPlacement.stored(UserDefaults.standard.string(forKey: PageHost.placementKey)) {
        didSet { UserDefaults.standard.set(devToolsPlacement.rawValue, forKey: Self.placementKey) }
    }

    private static let placementKey = "RoomDevToolsPlacement"
    /// The DevTools window while DevTools is undocked (5.10).
    private var devToolsWindow: DevToolsWindowController?

    /// ⌥⌘I: DevTools for the page where it was last placed (docked or its window), or closed.
    func toggleDevTools(inspecting point: NSPoint? = nil) {
        guard let devTools = contents?.devTools else { return }
        if isDevToolsOpen && point == nil {
            closeDevTools()
            return
        }
        let host = devToolsHost(for: devTools)
        if let point {
            devTools.inspectElement(at: point, in: host)
        } else {
            devTools.open(in: host)
        }
    }

    /// ⌥⌘J (console) and ⌥⌘C (element picker): open on that tool.
    func openDevTools(_ tool: DevToolsTool) {
        guard let devTools = contents?.devTools else { return }
        devTools.open(in: devToolsHost(for: devTools), tool: tool)
    }

    /// The view DevTools' front-end goes into for the current placement, shown.
    private func devToolsHost(for devTools: any DevTools) -> NSView {
        if devToolsPlacement == .window || !devTools.isDockable {
            container.isDevToolsOpen = false
            return showDevToolsWindow().host
        }
        devToolsWindow?.dismiss()
        devToolsWindow = nil
        container.devToolsPlacement = devToolsPlacement
        container.devToolsPane.header.onPlacement = { [weak self] placement in self?.place(placement) }
        container.devToolsPane.header.onClose = { [weak self] in self?.closeDevTools() }
        container.isDevToolsOpen = true
        container.layoutSubtreeIfNeeded()
        return container.devToolsHost
    }

    private func showDevToolsWindow() -> DevToolsWindowController {
        if let devToolsWindow { return devToolsWindow }
        let window = DevToolsWindowController(title: contents?.title, parent: controller?.window)
        window.header.onPlacement = { [weak self] placement in self?.place(placement) }
        window.header.onClose = { [weak self] in self?.closeDevTools() }
        window.onClose = { [weak self] in self?.closeDevTools(windowClosing: true) }
        devToolsWindow = window
        window.show()
        return window
    }

    /// Moves open DevTools to `placement` (the header's buttons): the engine re-hosts the front-end.
    func place(_ placement: DevToolsPlacement) {
        guard let devTools = contents?.devTools else { return }
        devToolsPlacement = placement
        devTools.open(in: devToolsHost(for: devTools))
    }

    /// Close: the front-end goes, with its pane or window.
    func closeDevTools(windowClosing: Bool = false) {
        contents?.devTools?.close()
        container.isDevToolsOpen = false
        if !windowClosing { devToolsWindow?.dismiss() }
        devToolsWindow = nil
        focusPage()
    }

    private func trackBackground() {
        let color = withObservationTracking {
            contents?.rootBackgroundColor
        } onChange: { [weakSelf = MainActorWeak(self), id = contents.map(ObjectIdentifier.init)] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self = weakSelf.value, self.contents.map(ObjectIdentifier.init) == id else { return }
                self.trackBackground()
            }
        }
        controller?.cardView.backgroundColor = color ?? Palette.cardBackground
        // The optional toolbar sits on that fill (2.7a).
        controller?.rootView.toolbarView.pageBackground = color
    }
}

/// The card's content: the page, and an optional DevTools pane docked at its bottom, right or left (5.10).
final class PageContainerView: NSView {
    /// The docked DevTools: Room's header (placements, Close) over the front-end's host.
    let devToolsPane = DevToolsPaneView()
    /// The DevTools front-end page is placed in this view (RoomCore 3.3b: `DevToolsWindow`'s front-end adopted).
    var devToolsHost: NSView { devToolsPane.host }
    /// Shown in place of a page when nothing is selected.
    let emptyState = CardEmptyStateView()
    /// Over the page, under its prompts: the find bar, the zoom indicator, the status pill (2.6b).
    let toolLayer = ToolLayerView()
    /// Over the page: its dialog sheet or certificate interstitial (2.6a).
    let promptLayer = PromptLayerView()
    /// Between the page and DevTools: drag to resize, double-click for the default.
    private let divider = DevToolsDividerView()

    var pageView: NSView? {
        didSet {
            guard pageView !== oldValue else { return }
            // A page view another container took already (Peek → Open as Tab) stays where it is.
            if oldValue?.superview === self { oldValue?.removeFromSuperview() }
            if let pageView { addSubview(pageView, positioned: .below, relativeTo: nil) }
            // Tools and prompts stay above the page view whatever was added last.
            addSubview(toolLayer, positioned: .above, relativeTo: nil)
            addSubview(promptLayer, positioned: .above, relativeTo: nil)
            addSubview(divider, positioned: .above, relativeTo: nil)
            needsLayout = true
        }
    }

    var isDevToolsOpen = false {
        didSet {
            devToolsPane.isHidden = !isDevToolsOpen
            divider.isHidden = !isDevToolsOpen
            needsLayout = true
        }
    }

    /// The docked pane's side (never `.window` here; the host keeps that).
    var devToolsPlacement = DevToolsPlacement.bottom {
        didSet {
            guard devToolsPlacement != oldValue else { return }
            divider.isVertical = devToolsPlacement.isHorizontal
            devToolsPane.header.placement = devToolsPlacement
            devToolsFraction = Self.storedFraction(devToolsPlacement)
            needsLayout = true
        }
    }

    /// The card's share DevTools takes when open along its axis; dragging the divider sets it,
    /// and it is remembered across launches per axis (a view preference, not model state).
    var devToolsFraction: CGFloat = PageContainerView.storedFraction(.bottom) {
        didSet { needsLayout = true }
    }

    private static let fractionKey = "RoomDevToolsFraction"
    private static let sideFractionKey = "RoomDevToolsSideFraction"
    private static func fractionKey(_ placement: DevToolsPlacement) -> String { placement.isHorizontal ? sideFractionKey : fractionKey }

    private static func storedFraction(_ placement: DevToolsPlacement) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: fractionKey(placement))
        return stored > 0 ? CGFloat(stored) : DevToolsMetrics.defaultFraction
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        devToolsPane.isHidden = true
        divider.isHidden = true
        devToolsPane.setAccessibilityIdentifier("devtools-pane")
        divider.onDrag = { [weak self] point in
            guard let self else { return }
            let horizontal = devToolsPlacement.isHorizontal
            devToolsFraction = DevToolsSplit.fraction(dividerAt: horizontal ? point.x : point.y,
                                                      length: horizontal ? bounds.width : bounds.height, leading: devToolsPlacement.isLeading)
        }
        divider.onDragEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Double(devToolsFraction), forKey: Self.fractionKey(devToolsPlacement))
        }
        divider.onReset = { [weak self] in
            guard let self else { return }
            devToolsFraction = DevToolsMetrics.defaultFraction
            UserDefaults.standard.removeObject(forKey: Self.fractionKey(devToolsPlacement))
        }
        addSubview(devToolsPane)
        addSubview(toolLayer)
        addSubview(promptLayer)
        // Above the pane's and the page's own views (Chromium's), so it gets the drags.
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let placement = devToolsPlacement
        let length = placement.isHorizontal ? bounds.width : bounds.height
        let pane = isDevToolsOpen ? DevToolsSplit.paneHeight(fraction: devToolsFraction, height: length) : 0
        let page: NSRect
        let hit = DevToolsMetrics.dividerHitHeight
        switch placement {
        case .bottom, .window:
            page = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - pane)
            devToolsPane.frame = NSRect(x: 0, y: page.maxY, width: bounds.width, height: pane)
            divider.frame = NSRect(x: 0, y: page.maxY - hit / 2, width: bounds.width, height: hit)
        case .right:
            page = NSRect(x: 0, y: 0, width: bounds.width - pane, height: bounds.height)
            devToolsPane.frame = NSRect(x: page.maxX, y: 0, width: pane, height: bounds.height)
            divider.frame = NSRect(x: page.maxX - hit / 2, y: 0, width: hit, height: bounds.height)
        case .left:
            page = NSRect(x: pane, y: 0, width: bounds.width - pane, height: bounds.height)
            devToolsPane.frame = NSRect(x: 0, y: 0, width: pane, height: bounds.height)
            divider.frame = NSRect(x: pane - hit / 2, y: 0, width: hit, height: bounds.height)
        }
        pageView?.frame = page
        promptLayer.frame = page
        toolLayer.frame = page
    }
}

final class FlippedPaneView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Holds the page's dialog or interstitial over the page view; without one
/// it lets every event through to the page.
final class PromptLayerView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !subviews.isEmpty else { return nil }
        return super.hitTest(point)
    }
}

/// Holds the find bar, the zoom indicator and the status pill over the page;
/// only they take events, the rest of the page stays clickable.
final class ToolLayerView: NSView {
    /// After every layout (the status pill and the indicator re-place themselves).
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// The DevTools pane's edge toward the page: a 1 pt line in an 8 pt drag area with the
/// resize cursor (ROADMAP 2.6 task 4; 5.10: vertical when DevTools is docked at a side).
final class DevToolsDividerView: NSView {
    /// The pointer during a drag, in the container's (flipped) coordinates.
    var onDrag: ((NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onReset: (() -> Void)?
    /// A line from top to bottom (DevTools at the right or left).
    var isVertical = false {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Palette.hairline.setFill()
        let line = Hairline.width(in: self)
        if isVertical {
            NSRect(x: (bounds.width / 2).rounded(.down), y: 0, width: line, height: bounds.height).fill()
        } else {
            NSRect(x: 0, y: (bounds.height / 2).rounded(.down), width: bounds.width, height: line).fill()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isVertical ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return onReset?() ?? () }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let container = superview else { return }
        onDrag?(container.convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}
