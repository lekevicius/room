import AppKit
import CoreImage

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
    /// The selected Essential's favicon, blurred, inside the pill (5.11: `FaviconGlow`).
    private let glowClip = CALayer()
    private let glowLayer = CALayer()

    /// The control under the pointer: the glass deepens by the rows' hover fill.
    public var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    /// How strongly the glass shows (5.12, the user on build 26: the address field "takes a bit too
    /// much attention"; `.clear` glass reads as white over the light sidebar too, so it is drawn fainter).
    public var strength: CGFloat = 1 {
        didSet { glass.alphaValue = strength }
    }

    public var cornerRadius: CGFloat = GlassMetrics.cornerRadius {
        didSet {
            glass.cornerRadius = cornerRadius
            needsDisplay = true
        }
    }

    /// A blurred favicon over the glass (`FaviconGlow.image`), centred on `glowCenter` (the view's
    /// coordinates); `nil`: clear glass.
    public var glow: CGImage? {
        didSet {
            glowLayer.contents = glow
            glowClip.isHidden = glow == nil
            needsLayout = true
        }
    }

    public var glowCenter: CGPoint? {
        didSet { needsLayout = true }
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
        for glowPart in [glowClip, glowLayer] { glowPart.actions = CALayer.noImplicitActions }
        glowClip.masksToBounds = true
        glowClip.isHidden = true
        glowLayer.opacity = Float(GlassMetrics.glowAlpha)
        glowClip.addSublayer(glowLayer)
        layer?.addSublayer(glowClip)
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
        solid.backgroundColor = Palette.sidebarSelection.cgColor
        for overlay in [solid, glowClip, highlight] {
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
        glowClip.frame = bounds
        let center = glowCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
        glowLayer.frame = FaviconGlow.frame(centeredOn: center)
    }
}

/// The glass pills' tokens (5.10).
public enum GlassMetrics {
    /// The palette's glass (5.12, the user on build 26: the new tab field "a bit less transparent,
    /// more white, keep Liquid Glass"): tinted toward white, in Dark Mode toward the window's grey.
    public static var paletteTint: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.windowBackgroundColor.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(0.6)
        }
    }
    /// The design's Liquid Glass - Small at the rows' pill corner.
    public static let cornerRadius: CGFloat = SidebarMetrics.pillCornerRadius
    /// The selected row's and Essential's glow: the favicon itself, blurred behind it (the design: a
    /// 48 pt square blurred 32 pt, clipped to the pill). 5.11 (the user on build 25: one flat colour,
    /// "way too intense, a third of that is enough"): the favicon's own pixels, at 40 % / 3;
    /// 5.12 (build 26: "too faint, increase them 2x"): twice that.
    public static let glowAlpha: CGFloat = 0.8 / 3
    public static let glowSourceSize: CGFloat = 48
    /// Figma's layer blur is twice the Gaussian's deviation.
    public static let glowBlurSigma: CGFloat = 16
    /// The rendered glow's side: the source and three deviations of its fall-off on each side.
    public static let glowDiameter: CGFloat = 144
}

/// A favicon blurred into a glow (5.11): the selected row's and the selected Essential's, the
/// design's "48 pt square blurred 32 pt" drawn from the favicon's own pixels (or, for a page without
/// one, its letter tile's colour). Rendered once per image at 2× and cached.
public enum FaviconGlow {
    private static let byImage = NSMapTable<NSImage, CGImage>.weakToStrongObjects()
    private static var byColor: [String: CGImage] = [:]
    nonisolated(unsafe) private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The glow of `icon`, else of a square of `color`; `nil` with neither.
    @MainActor public static func image(of icon: NSImage?, color: NSColor?) -> CGImage? {
        if let icon {
            if let cached = byImage.object(forKey: icon) { return cached }
            let rendered = render { context, rect in
                guard let image = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                context.interpolationQuality = .medium
                context.draw(image, in: rect)
            }
            if let rendered { byImage.setObject(rendered, forKey: icon) }
            return rendered
        }
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        let key = String(format: "%.3f %.3f %.3f", color.redComponent, color.greenComponent, color.blueComponent)
        if let cached = byColor[key] { return cached }
        let rendered = render { context, rect in
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }
        byColor[key] = rendered
        return rendered
    }

    /// Where a glow centred on `center` goes (its side `GlassMetrics.glowDiameter`).
    public static func frame(centeredOn center: CGPoint) -> CGRect {
        let side = GlassMetrics.glowDiameter
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    /// `draw` fills the source square of a transparent canvas; the canvas comes back blurred (pure).
    public static func render(_ draw: (CGContext, CGRect) -> Void) -> CGImage? {
        let scale: CGFloat = 2
        let side = Int(GlassMetrics.glowDiameter * scale)
        guard let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let source = GlassMetrics.glowSourceSize * scale
        let origin = (CGFloat(side) - source) / 2
        draw(canvas, CGRect(x: origin, y: origin, width: source, height: source))
        guard let sharp = canvas.makeImage() else { return nil }
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        let blurred = CIImage(cgImage: sharp).applyingGaussianBlur(sigma: GlassMetrics.glowBlurSigma * scale).cropped(to: extent)
        return context.createCGImage(blurred, from: extent)
    }
}
