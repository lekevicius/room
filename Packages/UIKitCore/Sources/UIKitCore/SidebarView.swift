import AppKit
import CoreImage
import Design

/// The sidebar region: a transparent area over the window material that
/// moves the window when dragged (the Room Browser design, 2026-10-07).
/// Its top bar is laid out around the traffic lights: after the zoom button
/// the sidebar toggle and `accessoryView` (the extensions), and Back, Forward
/// and Reload (`navigationView`) at the trailing end, all centred on the
/// buttons. Under it, `headerView` (the address field) gets a row as wide as
/// the rows' pill, or the space title shows there while no header view is
/// set. `bodyView` fills the rest.
public final class SidebarView: NSView {
    /// Everything that dims while the window is inactive.
    public let contentView = FlippedView()
    let titleField = NSTextField(labelWithString: "")
    /// Hides or shows the sidebar (⌘S): the top bar's first button.
    public let toggleButton = HoverButton()
    public var onToggleSidebar: (() -> Void)?

    /// The row under the top bar, at its fitting height.
    public var headerView: NSView? {
        didSet {
            guard headerView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let headerView { contentView.addSubview(headerView) }
            titleField.isHidden = headerView != nil
            needsLayout = true
        }
    }

    /// Back, Forward, Reload at the top bar's trailing end, three buttons wide.
    public var navigationView: NSView? {
        didSet {
            guard navigationView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let navigationView { contentView.addSubview(navigationView) }
            needsLayout = true
        }
    }

    /// Between the toggle and the navigation buttons: gets all the width
    /// there is and shows what fits (the extension bar).
    public var accessoryView: NSView? {
        didSet {
            guard accessoryView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let accessoryView { contentView.addSubview(accessoryView) }
            needsLayout = true
        }
    }

    /// Fills the sidebar below the header row.
    public var bodyView: NSView? {
        didSet {
            guard bodyView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let bodyView { contentView.addSubview(bodyView, positioned: .below, relativeTo: nil) }
            needsLayout = true
        }
    }

    /// A label under the header row, before the body (4.8b: "Incognito" in
    /// the incognito window); nil shows none.
    public var badgeText: String? {
        didSet {
            badgeField.stringValue = badgeText ?? ""
            badgeField.isHidden = badgeText == nil
            needsLayout = true
        }
    }
    let badgeField = NSTextField(labelWithString: "")

    public var trafficLights = TrafficLightGeometry.none {
        didSet { if trafficLights != oldValue { needsLayout = true } }
    }

    public var title: String {
        get { titleField.stringValue }
        set { titleField.stringValue = newValue; needsLayout = true }
    }

    /// The space title's frame in sidebar coordinates (flipped).
    public var titleFrame: NSRect { titleField.frame }

    public var isWindowActive = true {
        didSet { if isWindowActive != oldValue { applyActivity() } }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("sidebar")
        contentView.wantsLayer = true
        contentView.layerUsesCoreImageFilters = true
        contentView.frame = bounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)

        titleField.font = Typography.spaceTitle
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setAccessibilityIdentifier("space-title")
        contentView.addSubview(titleField)
        badgeField.font = Typography.secondary
        badgeField.textColor = Palette.incognitoLabel
        badgeField.isHidden = true
        badgeField.setAccessibilityIdentifier("sidebar-badge")
        contentView.addSubview(badgeField)
        toggleButton.image = Symbol.toggleSidebar.image(.control, accessibilityDescription: "Toggle Sidebar")
        toggleButton.contentTintColor = .labelColor
        toggleButton.toolTip = "Toggle Sidebar (⌘S)"
        toggleButton.target = self
        toggleButton.action = #selector(toggleClicked)
        toggleButton.setAccessibilityIdentifier("sidebar-toggle")
        toggleButton.setAccessibilityLabel("Toggle Sidebar")
        toggleButton.setAccessibilityHelp("⌘S")
        contentView.addSubview(toggleButton)
        // One group for VoiceOver (5.3a), read top to bottom (`accessibilityChildren`).
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Sidebar")
    }

    /// The top bar, the address row, the list, the footer: in screen order
    /// (the subviews add the body, with its footer, before the top bar).
    public override func accessibilityChildren() -> [Any]? {
        super.accessibilityChildren().map(ReadingOrder.sorted)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }

    // The sidebar background is the window's drag handle.
    public override var mouseDownCanMoveWindow: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    public override func layout() {
        super.layout()
        let bar = TopBarLayout(width: bounds.width, trafficLights: trafficLights)
        toggleButton.isHidden = bar.toggle == nil
        if let toggle = bar.toggle { toggleButton.frame = backingAlignedRect(toggle, options: .alignAllEdgesNearest) }
        navigationView?.frame = backingAlignedRect(bar.navigation, options: .alignAllEdgesNearest)
        accessoryView?.frame = backingAlignedRect(bar.accessory, options: .alignAllEdgesNearest)

        let inset = SidebarMetrics.rowHorizontalInset
        let rowTop = bar.bottom + SidebarMetrics.addressRowGap
        let rowWidth = max(0, bounds.width - inset - SidebarMetrics.headerTrailingInset)
        var bodyTop: CGFloat
        if let headerView {
            let height = max(headerView.fittingSize.height, 1)
            headerView.frame = backingAlignedRect(NSRect(x: inset, y: rowTop, width: rowWidth, height: height), options: .alignAllEdgesNearest)
            bodyTop = headerView.frame.maxY + SidebarMetrics.addressRowGap
        } else {
            // The cell's natural size; a truncating label under-reports its intrinsic width.
            let intrinsic = titleField.cell?.cellSize ?? titleField.intrinsicContentSize
            let size = NSSize(width: ceil(intrinsic.width), height: ceil(intrinsic.height))
            let x = inset + SidebarMetrics.rowContentInset
            let frame = NSRect(x: x, y: rowTop + (SidebarMetrics.addressFieldHeight - size.height) / 2,
                               width: min(size.width, max(0, bounds.width - x - inset)), height: size.height)
            titleField.frame = backingAlignedRect(frame, options: [.alignMinXNearest, .alignMinYNearest, .alignWidthOutward, .alignHeightOutward])
            bodyTop = rowTop + SidebarMetrics.addressFieldHeight + SidebarMetrics.addressRowGap
        }
        if badgeText != nil {
            let inset = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
            badgeField.frame = backingAlignedRect(NSRect(x: inset, y: bodyTop, width: max(0, bounds.width - 2 * inset),
                                                         height: WindowMetrics.incognitoLabelHeight), options: .alignAllEdgesNearest)
            bodyTop = badgeField.frame.maxY + WindowMetrics.incognitoLabelGap
        }
        bodyView?.frame = NSRect(x: 0, y: bodyTop, width: bounds.width, height: max(0, bounds.height - bodyTop))
    }

    @objc private func toggleClicked() { onToggleSidebar?() }

    private func applyActivity() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.standard
            contentView.animator().alphaValue = isWindowActive ? 1 : SidebarMetrics.inactiveContentAlpha
        }
        if isWindowActive {
            contentView.contentFilters = []
        } else if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(SidebarMetrics.inactiveSaturation, forKey: kCIInputSaturationKey)
            contentView.contentFilters = [filter]
        }
    }
}

/// A plain flipped container.
public final class FlippedView: NSView {
    public override var isFlipped: Bool { true }
}
