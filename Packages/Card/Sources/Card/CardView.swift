import AppKit
import Design

/// The inset page card: a clipped `CardContainerView` over a `ShadowBackingView`
/// sibling (`masksToBounds` would kill a shadow on the clipped layer itself).
/// The window lays this view out with `CardMetrics.inset`; the shadow spills
/// outside its bounds, so its superview must not clip.
public final class CardView: NSView {
    public let container = CardContainerView()
    let shadowView = ShadowBackingView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(shadowView)
        addSubview(container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The engine's page view (or any view) shown inside the clipped card.
    public var contentView: NSView? {
        get { container.contentView }
        set { container.contentView = newValue }
    }

    /// A bar across the card's top above the page (the optional toolbar, spec §E).
    public var topAccessory: NSView? {
        get { container.topAccessory }
        set { container.topAccessory = newValue }
    }

    /// Card fill, visible wherever the page has not painted (live resize,
    /// loading). Phase 1.4 binds it to the page's `rootBackgroundColor`.
    public var backgroundColor: NSColor {
        get { container.backgroundColor }
        set { container.backgroundColor = newValue }
    }

    public override var mouseDownCanMoveWindow: Bool { false }

    /// The card's corner (`CardMetrics.cornerRadius`; Peek's card is rounder).
    public var cornerRadius: CGFloat = CardMetrics.cornerRadius {
        didSet {
            container.cornerRadius = cornerRadius
            shadowView.cornerRadius = cornerRadius
        }
    }

    /// Floats higher than the page card: a larger, darker shadow (Peek).
    public var isElevated = false {
        didSet { shadowView.isElevated = isElevated }
    }

    /// Square, borderless and shadowless: a page in element fullscreen.
    public var isEdgeToEdge = false {
        didSet {
            guard isEdgeToEdge != oldValue else { return }
            container.isEdgeToEdge = isEdgeToEdge
            shadowView.isHidden = isEdgeToEdge
        }
    }

    public override func layout() {
        super.layout()
        shadowView.frame = bounds
        container.frame = bounds
    }
}

/// The clipped, rounded, bordered layer that hosts the page view.
public final class CardContainerView: NSView {
    public var backgroundColor: NSColor = Palette.cardBackground {
        didSet { needsDisplay = true }
    }

    var isEdgeToEdge = false {
        didSet {
            layer?.cornerRadius = isEdgeToEdge ? 0 : cornerRadius
            needsDisplay = true
        }
    }

    var cornerRadius: CGFloat = CardMetrics.cornerRadius {
        didSet { if !isEdgeToEdge { layer?.cornerRadius = cornerRadius } }
    }

    public var contentView: NSView? {
        didSet {
            guard contentView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let contentView {
                contentView.frame = contentFrame
                contentView.autoresizingMask = [.width, .height]
                addSubview(contentView, positioned: .below, relativeTo: topAccessory)
            }
        }
    }

    /// Over the page at the card's top, its fitting height tall; the page fills the rest.
    var topAccessory: NSView? {
        didSet {
            guard topAccessory !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let topAccessory { addSubview(topAccessory) }
            needsLayout = true
        }
    }

    private var accessoryHeight: CGFloat { topAccessory.map { $0.fittingSize.height } ?? 0 }

    private var contentFrame: NSRect {
        let top = accessoryHeight
        // Flipped or not, the page sits below the bar.
        return NSRect(x: 0, y: isFlipped ? top : 0, width: bounds.width, height: max(0, bounds.height - top))
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let height = accessoryHeight
        topAccessory?.frame = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - height, width: bounds.width, height: height)
        contentView?.frame = contentFrame
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        guard let layer else { return }
        layer.cornerRadius = CardMetrics.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var wantsUpdateLayer: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    /// Runs inside the view's effective appearance, so dynamic colors resolve correctly.
    public override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = backgroundColor.cgColor
        // The border draws above the layer's sublayers (CALayer composites
        // borders over contents and sublayers), so the page cannot cover it.
        layer.borderColor = Palette.cardBorder.cgColor
        layer.borderWidth = isEdgeToEdge ? 0 : CardMetrics.borderWidth / (window?.backingScaleFactor ?? 2)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
}

/// Draws only the card's shadow, from an explicit `shadowPath`, behind the card.
final class ShadowBackingView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var cornerRadius: CGFloat = CardMetrics.cornerRadius {
        didSet { updateShadowPath() }
    }

    var isElevated = false {
        didSet { needsDisplay = true }
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.shadowColor = Palette.cardShadow.cgColor
        let dark = effectiveAppearance.isDark
        if isElevated {
            layer.shadowOpacity = dark ? PeekMetrics.shadowOpacityDark : PeekMetrics.shadowOpacityLight
            layer.shadowRadius = PeekMetrics.shadowRadius
            layer.shadowOffset = CGSize(width: 0, height: -PeekMetrics.shadowRadius / 3)
        } else {
            layer.shadowOpacity = dark ? CardMetrics.shadowOpacityDark : CardMetrics.shadowOpacityLight
            layer.shadowRadius = CardMetrics.shadowRadius
            layer.shadowOffset = CardMetrics.shadowOffset
        }
        updateShadowPath()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateShadowPath()
    }

    private func updateShadowPath() {
        let radius = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
