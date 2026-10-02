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

    public init(contentSize: NSSize = RoomWindow.defaultContentSize) {
        let window = RoomWindow(contentRect: NSRect(origin: .zero, size: contentSize))
        window.contentView = rootView
        trafficLights = TrafficLightLayout(window: window)
        activity = WindowActivity(window: window)
        super.init(window: window)
        window.delegate = self
        window.center()

        rootView.trafficLights = trafficLights
        trafficLights.onChange = { [weak self] geometry in
            self?.sidebarView.trafficLights = geometry
        }
        sidebarView.trafficLights = trafficLights.geometry
        activity.onChange = { [weak self] active in self?.applyActivity(active) }
        applyActivity(activity.isActive)

        rootView.splitterView.onDrag = { [weak self] proposed in self?.splitterDragged(to: proposed) }
        rootView.splitterView.onEnd = { [weak self] in self?.splitterDragEnded() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Sidebar

    public var spaceTitle: String {
        get { sidebarView.title }
        set { sidebarView.title = newValue }
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

    @objc public func toggleSidebar(_ sender: Any?) {
        isSidebarOpen.toggle()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = isSidebarOpen ? "Hide Sidebar" : "Show Sidebar"
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

    private func splitterDragEnded() {
        defer { openWidthBeforeDrag = nil }
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

    public func windowDidEnterFullScreen(_ notification: Notification) { rootView.needsLayout = true }
    public func windowDidExitFullScreen(_ notification: Notification) { rootView.needsLayout = true }
}

/// The window's content view: material behind everything, the sidebar on the
/// leading side, the card inset on the other three, the splitter on top.
public final class BrowserWindowView: NSView {
    public let materialView = WindowMaterialView()
    public let sidebarView = SidebarView()
    public let cardView = CardView()
    let splitterView = SidebarSplitterView()
    weak var trafficLights: TrafficLightLayout?

    public var sidebarWidth: CGFloat = SidebarMetrics.defaultWidth {
        didSet { if sidebarWidth != oldValue { needsLayout = true } }
    }

    public var isSidebarOpen = true {
        didSet { if isSidebarOpen != oldValue { needsLayout = true; layoutSubtreeIfNeeded() } }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        cardView.setAccessibilityIdentifier("card")
        addSubview(materialView)
        addSubview(sidebarView)
        addSubview(cardView)
        addSubview(splitterView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    public var currentLayout: WindowLayout {
        WindowLayout.compute(bounds: bounds, sidebarWidth: sidebarWidth, isSidebarOpen: isSidebarOpen)
    }

    public override func layout() {
        super.layout()
        trafficLights?.update()
        let layout = currentLayout
        sidebarView.isHidden = !isSidebarOpen
        sidebarView.frame = layout.sidebar
        cardView.frame = layout.card
        splitterView.isHidden = layout.splitter == nil
        splitterView.frame = layout.splitter ?? .zero
        splitterView.currentWidth = layout.sidebar.width
    }
}
