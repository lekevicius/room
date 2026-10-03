import AppKit
import CoreImage
import Design

/// The sidebar region: a transparent area over the window material that
/// moves the window when dragged. Its header row (`SidebarMetrics.headerHeight`)
/// is laid out around the traffic lights: `headerView` (the address field)
/// fills it from after the zoom button to the trailing inset, or the space
/// title shows there while no header view is set. `bodyView` fills the rest.
public final class SidebarView: NSView {
    /// Everything that dims while the window is inactive.
    public let contentView = FlippedView()
    let titleField = NSTextField(labelWithString: "")

    /// Sits beside the traffic lights, vertically centred on them, at its
    /// fitting height.
    public var headerView: NSView? {
        didSet {
            guard headerView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let headerView { contentView.addSubview(headerView) }
            titleField.isHidden = headerView != nil
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
        let leading = trafficLights.leadingX(gap: SidebarMetrics.headerLeadingGap, edgeInset: SidebarMetrics.edgeInset)
        let centerY = trafficLights.centerY(fallback: SidebarMetrics.headerHeight / 2)
        // The cell's natural size; a truncating label under-reports its intrinsic width.
        let intrinsic = titleField.cell?.cellSize ?? titleField.intrinsicContentSize
        let size = NSSize(width: ceil(intrinsic.width), height: ceil(intrinsic.height))
        let width = max(0, bounds.width - leading - SidebarMetrics.edgeInset)
        let frame = NSRect(x: leading, y: centerY - size.height / 2, width: min(size.width, width), height: size.height)
        titleField.frame = backingAlignedRect(frame, options: [.alignMinXNearest, .alignMinYNearest, .alignWidthOutward, .alignHeightOutward])
        if let headerView {
            let height = max(headerView.fittingSize.height, 1)
            let header = NSRect(x: leading, y: centerY - height / 2, width: width, height: height)
            headerView.frame = backingAlignedRect(header, options: .alignAllEdgesNearest)
        }
        bodyView?.frame = NSRect(x: 0, y: SidebarMetrics.headerHeight, width: bounds.width,
                                 height: max(0, bounds.height - SidebarMetrics.headerHeight))
    }

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
