import AppKit
import Design

/// The hidden sidebar revealed as a floating glass overlay over the card
/// (spec §E): the window's `SidebarView` moves in while it shows, so the
/// overlay is the same tree, rows and header, not a copy.
public final class SidebarOverlayView: NSView {
    let glass = NSGlassEffectView()
    private let container = FlippedView()
    /// A grey wash under the rows, like the docked sidebar's material, so rows and
    /// the white selection pill read over any page.
    private let backing = OverlayBackingView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("sidebar-overlay")
        glass.cornerRadius = RevealMetrics.overlayCornerRadius
        // The rows must read over any page: the glass is tinted toward the window's background.
        backing.wantsLayer = true
        container.addSubview(backing)
        glass.contentView = container
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func layout() {
        super.layout()
        // Sized here, not by the glass, so the list measures its visible rows on the first reveal.
        container.frame = glass.bounds
        backing.frame = container.bounds
    }

    /// Where the sidebar view goes while the overlay shows.
    var contentView: NSView { container }

    /// Nothing under the overlay gets its events, even where the glass is clear.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    public override func mouseDown(with event: NSEvent) {}
}

private final class OverlayBackingView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateLayer() {
        let white = effectiveAppearance.isDark ? RevealMetrics.overlayTintWhiteDark : RevealMetrics.overlayTintWhiteLight
        layer?.backgroundColor = NSColor(white: white, alpha: RevealMetrics.overlayTintAlpha).cgColor
    }
}
