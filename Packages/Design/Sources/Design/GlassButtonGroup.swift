import AppKit

/// Buttons in one Liquid Glass capsule (5.13, the user's design: the macOS 27 kit's XL segmented
/// control; AppKit's `NSSegmentedControl` draws a grey fill outside a toolbar in every style, so the
/// group is an `NSGlassEffectView` holding the owner's buttons): items `GlassControlMetrics.itemWidth`
/// wide, 4 pt inside the capsule, hairline separators between them. One item is a glass circle.
/// The items stay the owner's (their targets, menus and popup anchors).
public final class GlassButtonGroup: NSView {
    private let glass = NSGlassEffectView()
    private let content = FlippedGroupContent()
    private var separators: [CALayer] = []
    public private(set) var items: [NSView] = []

    /// The item drawn as selected (the footer's active space): a fill under it.
    public var selectedIndex: Int? {
        didSet { if selectedIndex != oldValue { needsLayout = true } }
    }
    private let selection = CALayer()
    /// The gaps that get a hairline, by the index of the item before them; `nil`, every gap (5.13, the user:
    /// the extension bar parts the puzzle piece from the pinned actions, not the actions from each other).
    public var separatorsAfter: Set<Int>? {
        didSet { if separatorsAfter != oldValue { needsLayout = true } }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .regular
        glass.contentView = content
        addSubview(glass)
        content.wantsLayer = true
        selection.actions = CALayer.noImplicitActions
        selection.isHidden = true
        content.layer?.addSublayer(selection)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override var intrinsicContentSize: NSSize {
        NSSize(width: GlassControlMetrics.groupWidth(items.count), height: GlassControlMetrics.size)
    }
    public override var fittingSize: NSSize { intrinsicContentSize }

    /// The items, in order: borderless buttons (their hover fill takes the item's capsule) or the
    /// footer's space icons. Their frames are the group's (`itemFrames`, the group's coordinates).
    public func setItems(_ newItems: [NSView]) {
        guard newItems.map(ObjectIdentifier.init) != items.map(ObjectIdentifier.init) else { return }
        for item in items where !newItems.contains(where: { $0 === item }) { item.removeFromSuperview() }
        items = newItems
        for item in items where item.superview !== content { content.addSubview(item) }
        while separators.count < max(0, items.count - 1) {
            let line = CALayer()
            line.actions = CALayer.noImplicitActions
            content.layer?.addSublayer(line)
            separators.append(line)
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// Each item's frame in the group's coordinates.
    public var itemFrames: [NSRect] {
        let count = items.count
        let m = GlassControlMetrics.self
        guard count > 1 else {
            let inset = (m.size - m.itemHeight) / 2
            return count == 1 ? [NSRect(x: inset, y: inset, width: m.itemHeight, height: m.itemHeight)] : []
        }
        let y = (bounds.height - m.itemHeight) / 2
        return (0..<count).map { NSRect(x: m.groupPadding + CGFloat($0) * (m.itemWidth + m.separatorWidth), y: y, width: m.itemWidth, height: m.itemHeight) }
    }

    public override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = bounds.height / 2
        content.frame = glass.bounds
        let frames = itemFrames
        for (item, frame) in zip(items, frames) {
            item.frame = frame
            item.layer?.cornerRadius = frame.height / 2
        }
        let m = GlassControlMetrics.self
        let lineColor = resolved(NSColor.separatorColor)
        for (index, line) in separators.enumerated() {
            line.isHidden = index >= frames.count - 1 || separatorsAfter.map { !$0.contains(index) } == true
            guard !line.isHidden else { continue }
            let x = frames[index].maxX + m.separatorWidth / 2
            let width = 1 / (window?.backingScaleFactor ?? 2)
            line.frame = CGRect(x: x - width / 2, y: (bounds.height - m.separatorHeight) / 2, width: width, height: m.separatorHeight)
            // A selected item's neighbours drop their line (the kit's "next to selected").
            if let selectedIndex, index == selectedIndex || index == selectedIndex - 1 { line.isHidden = true }
            line.backgroundColor = lineColor
        }
        if let selectedIndex, frames.indices.contains(selectedIndex) {
            selection.isHidden = false
            selection.frame = frames[selectedIndex]
            selection.cornerRadius = frames[selectedIndex].height / 2
            selection.backgroundColor = resolved(NSColor.labelColor.withAlphaComponent(0.1))
        } else {
            selection.isHidden = true
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    private func resolved(_ color: NSColor) -> CGColor {
        var cg = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        return cg
    }
}

private final class FlippedGroupContent: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}
