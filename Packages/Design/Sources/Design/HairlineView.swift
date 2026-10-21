import AppKit

/// A separator line one device pixel thick (`Hairline`, 5.2a): the owner
/// lays it out with `thickness` as its height (or width), and lays it out
/// again when the window's scale changes (`onScaleChange`). Replaces
/// `NSBox`'s separator, which drew 2 px on a Retina display.
public final class HairlineView: NSView {
    /// The line's colour (`Palette.hairline` by default: the system separator, or Increase Contrast's, 5.3b).
    public var color: NSColor = Palette.hairline {
        didSet { needsDisplay = true }
    }

    /// The window's scale changed: the owner lays the line out again.
    public var onScaleChange: (() -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.actions = CALayer.noImplicitActions
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// One device pixel in points, for this view's window.
    public var thickness: CGFloat { Hairline.width(in: self) }

    public override var wantsUpdateLayer: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func updateLayer() {
        layer?.backgroundColor = color.cgColor
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onScaleChange?()
        superview?.needsLayout = true
    }
}
