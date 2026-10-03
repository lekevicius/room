import AppKit
import Design

/// View ▸ Show Toolbar (spec §E): a 36 pt bar across the card's top with
/// Back, Forward, Reload and the page's full URL (a click edits it, as
/// ⌘L). Its background is a drag handle for the window, as a titlebar.
/// With the sidebar hidden it starts after the traffic lights.
public final class PageToolbarView: NSView {
    public let navigation = NavigationButtonsView(buttonSize: ToolbarMetrics.buttonSize)
    /// The URL was clicked.
    public var onURLClick: (() -> Void)?

    private let urlField = ToolbarURLView()
    private let separator = NSBox()

    /// Content starts this far from the bar's leading edge (past the traffic lights while the sidebar is hidden).
    public var leadingInset: CGFloat = ToolbarMetrics.padding {
        didSet { if leadingInset != oldValue { needsLayout = true } }
    }

    /// Content is centred on this line, measured from the bar's top (the traffic lights' centre while they sit in it).
    public var contentCenterY: CGFloat? {
        didSet { if contentCenterY != oldValue { needsLayout = true } }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("page-toolbar")
        separator.boxType = .separator
        urlField.onClick = { [weak self] in self?.onURLClick?() }
        addSubview(navigation)
        addSubview(urlField)
        addSubview(separator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { true }
    public override var fittingSize: NSSize { NSSize(width: bounds.width, height: ToolbarMetrics.height) }
    public override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: ToolbarMetrics.height) }

    /// The page's full URL (`nil`: a placeholder).
    public func setURL(_ url: String?) {
        urlField.setURL(url)
    }

    public override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 { return TitlebarDoubleClick.perform(in: window) }
        window.performDrag(with: event)
    }

    public override func layout() {
        super.layout()
        let center = min(max(contentCenterY ?? bounds.height / 2, ToolbarMetrics.buttonSize / 2), bounds.height - ToolbarMetrics.buttonSize / 2)
        let navigationSize = navigation.fittingSize
        navigation.frame = NSRect(x: leadingInset, y: center - navigationSize.height / 2, width: navigationSize.width, height: navigationSize.height)
        let urlX = navigation.frame.maxX + ToolbarMetrics.padding
        urlField.frame = NSRect(x: urlX, y: center - ToolbarMetrics.urlHeight / 2,
                                width: max(0, bounds.width - urlX - ToolbarMetrics.padding), height: ToolbarMetrics.urlHeight)
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
    }
}

/// The toolbar's URL: full, middle-truncated, on a hover-tinted capsule.
private final class ToolbarURLView: NSView {
    var onClick: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("toolbar-url")
        setAccessibilityRole(.button)
        label.font = Typography.row
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        setURL(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    func setURL(_ url: String?) {
        label.stringValue = url ?? "Search or enter URL"
        label.textColor = url == nil ? .placeholderTextColor : .secondaryLabelColor
        toolTip = url
        needsLayout = true
    }

    override func updateLayer() {
        layer?.cornerRadius = Radius.small
        layer?.backgroundColor = (hovering ? Palette.sidebarHover : NSColor.clear).cgColor
    }

    override func layout() {
        super.layout()
        let height = label.cell?.cellSize.height ?? 16
        label.frame = NSRect(x: Spacing.s, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * Spacing.s), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
