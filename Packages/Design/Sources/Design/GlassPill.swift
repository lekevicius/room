import AppKit

/// Liquid Glass under a sidebar control (5.10, the Room Browser design's "Liquid Glass - Small",
/// Figma 67:2115): the address field, the selected row's pill and the selected Essential.
/// An `NSGlassEffectView` at the pill's corner; under Reduce Transparency the selection's
/// solid fill instead (`Materials.usesSolidFill`), as the overlays' glass gives way (5.3b).
/// It draws only: clicks go to the control it sits under.
public final class GlassPillView: NSView {
    private let glass = NSGlassEffectView()
    private let solid = CALayer()
    /// Over the glass while the pointer is on the control (the rows' hover fill).
    private let highlight = CALayer()

    /// The control under the pointer: the glass deepens by the rows' hover fill.
    public var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    public var cornerRadius: CGFloat = GlassMetrics.cornerRadius {
        didSet {
            glass.cornerRadius = cornerRadius
            needsDisplay = true
        }
    }

    /// A colour the glass is tinted with (the selected Essential's favicon colour); `nil`: clear glass.
    public var tint: NSColor? {
        didSet {
            glass.tintColor = tint?.withAlphaComponent(GlassMetrics.tintAlpha)
            needsDisplay = true
        }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.actions = CALayer.noImplicitActions
        solid.actions = CALayer.noImplicitActions
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        layer?.addSublayer(solid)
        highlight.actions = CALayer.noImplicitActions
        layer?.addSublayer(highlight)
        setAccessibilityElement(false)
        NotificationCenter.default.addObserver(self, selector: #selector(optionsChanged), name: DisplayOptions.didChange, object: nil)
        optionsChanged()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var wantsUpdateLayer: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func optionsChanged() {
        let solidFill = Materials.usesSolidFill()
        glass.isHidden = solidFill
        solid.isHidden = !solidFill
        needsDisplay = true
    }

    public override func updateLayer() {
        solid.backgroundColor = (tint.map { FaviconTint.fill($0, dark: effectiveAppearance.isDark) } ?? Palette.sidebarSelection).cgColor
        for overlay in [solid, highlight] {
            overlay.frame = bounds
            overlay.cornerRadius = cornerRadius
            overlay.cornerCurve = .continuous
        }
        highlight.backgroundColor = isHighlighted ? Palette.sidebarHover.cgColor : nil
    }

    public override func layout() {
        super.layout()
        solid.frame = bounds
        highlight.frame = bounds
    }
}

/// The glass pills' tokens (5.10).
public enum GlassMetrics {
    /// The design's Liquid Glass - Small at the rows' pill corner.
    public static let cornerRadius: CGFloat = SidebarMetrics.pillCornerRadius
    /// The selected Essential's glass tinted with its favicon's colour at this alpha (the design's
    /// tile reads #F8CECE over a #DE5A5A favicon: about a quarter of it over white).
    public static let tintAlpha: CGFloat = 0.25
    /// The selected row's glow: its favicon's colour, blurred behind the favicon (the design: a
    /// 48 pt square blurred 32 pt at 40%, clipped to the pill's first 114 pt).
    public static let glowAlpha: CGFloat = 0.4
    public static let glowDiameter: CGFloat = 112
}

/// A favicon's colour for the selected tab's glow and the selected Essential's tint (5.10): the
/// average of its opaque, saturated pixels, so a white or black background does not wash it out.
/// `nil` for an icon without colour (a monochrome glyph), which then shows clear glass.
public enum FaviconTint {
    private static let cache = NSMapTable<NSImage, NSColor>.weakToStrongObjects()

    @MainActor public static func color(of image: NSImage?) -> NSColor? {
        guard let image else { return nil }
        if let cached = cache.object(forKey: image) { return cached == .clear ? nil : cached }
        let color = image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(average)
        cache.setObject(color ?? .clear, forKey: image)
        return color
    }

    /// The saturation-weighted average of `image` drawn at 16 × 16 (pure, unit-tested).
    public static func average(_ image: CGImage) -> NSColor? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[index]) / 255 / alpha, g = Double(pixels[index + 1]) / 255 / alpha, b = Double(pixels[index + 2]) / 255 / alpha
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high > 0 ? (high - low) / high : 0
            // Saturated pixels count; near-greys (white backgrounds, black outlines) barely do.
            let w = alpha * saturation * saturation
            red += r * w; green += g * w; blue += b * w; weight += w
        }
        guard weight > 0.5 else { return nil }
        return NSColor(srgbRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
    }

    /// The selected Essential's solid fill under Reduce Transparency: `tint` over the selection's white
    /// (or dark grey) at `GlassMetrics.tintAlpha`.
    public static func fill(_ tint: NSColor, dark: Bool) -> NSColor {
        let base = dark ? NSColor(white: 0.25, alpha: 1) : NSColor.white  // design-audit: the selection's own white / dark grey under the tint
        return base.blended(withFraction: GlassMetrics.tintAlpha, of: tint) ?? base
    }
}
