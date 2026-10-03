import AppKit
import Design

/// The window-wide material: a behind-window `NSVisualEffectView` (`.sidebar`)
/// with the space tint gradient above it.
public final class WindowMaterialView: NSVisualEffectView {
    let tintView = SpaceTintView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        material = Materials.window
        blendingMode = Materials.windowBlending
        state = .followsWindowActiveState
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The space's theme colour (the first of its tint); `nil` leaves the neutral material (Dia's look).
    public var tintColor: NSColor? { tintView.tint?.light.first }

    /// One colour, fading from the top (snapshots and tests).
    public func setTintColor(_ color: NSColor?, animated: Bool) {
        setTint(color.map { SpaceTint(light: [$0], dark: [$0], alpha: Materials.tintOpacity) }, animated: animated)
    }

    /// The active space's theme (spec §B), crossfaded over `Motion.medium`
    /// when `animated` (the space switch's slide runs alongside).
    public func setTint(_ tint: SpaceTint?, animated: Bool) {
        tintView.setTint(tint, animated: animated)
    }

    /// Follows `WindowActivity`; the material itself already follows the
    /// window's active state unless `state` is forced.
    public var isWindowActive: Bool {
        get { tintView.isWindowActive }
        set { tintView.isWindowActive = newValue }
    }

    public override var mouseDownCanMoveWindow: Bool { false }
}

/// A space's tint: its theme colours (1–3, `ThemePalette` in Model) for
/// each appearance, and the gradient's alpha (within `Materials.tintOpacityRange`).
public struct SpaceTint: Equatable, Sendable {
    public var light: [NSColor]
    public var dark: [NSColor]
    public var alpha: CGFloat

    public init(light: [NSColor], dark: [NSColor], alpha: CGFloat) {
        self.light = light
        self.dark = dark
        self.alpha = alpha
    }
}

/// The space tint over the material: a diagonal gradient (top leading to
/// bottom trailing) through the theme's colours at 10–25% opacity. Always
/// three stops, so a switch between themes with different numbers of
/// colours interpolates instead of snapping: one colour fades from `alpha`
/// to the range's lower bound, two put their blend in the middle.
final class SpaceTintView: NSView {
    private(set) var tint: SpaceTint?
    var isWindowActive = true {
        didSet { if isWindowActive != oldValue { needsDisplay = true } }
    }
    /// Inactive windows keep a fainter tint, matching the desaturated sidebar.
    static let inactiveFactor: CGFloat = 0.6

    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAGradientLayer()
        // Non-flipped layer: from the top leading corner.
        layer.startPoint = CGPoint(x: 0, y: 1)
        layer.endPoint = CGPoint(x: 1, y: 0)
        layer.locations = [0, 0.5, 1]
        layer.colors = Self.clearColors
        return layer
    }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Appearance and activity changes land here, inside the effective appearance.
    override func updateLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.colors = targetColors()
        CATransaction.commit()
    }

    func setTint(_ newTint: SpaceTint?, animated: Bool) {
        tint = newTint
        var target: [CGColor] = []
        effectiveAppearance.performAsCurrentDrawingAppearance { target = self.targetColors() }
        let layer = gradientLayer
        if animated {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = layer.presentation()?.colors ?? layer.colors
            animation.toValue = target
            animation.duration = Motion.medium
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.colors = target
        CATransaction.commit()
    }

    /// Must run with the view's appearance current (dynamic colors).
    func targetColors() -> [CGColor] {
        guard let tint else { return Self.clearColors }
        let colors = effectiveAppearance.isDark ? tint.dark : tint.light
        guard let first = colors.first else { return Self.clearColors }
        let factor = isWindowActive ? 1 : Self.inactiveFactor
        let alpha = min(max(tint.alpha, Materials.tintOpacityRange.lowerBound), Materials.tintOpacityRange.upperBound) * factor
        let stops: [NSColor]
        let alphas: [CGFloat]
        switch colors.count {
        case 1:
            let low = Materials.tintOpacityRange.lowerBound * factor
            stops = [first, first, first]
            alphas = [alpha, (alpha + low) / 2, low]
        case 2:
            stops = [first, first.blended(withFraction: 0.5, of: colors[1]) ?? first, colors[1]]
            alphas = [alpha, alpha, alpha]
        default:
            stops = Array(colors.prefix(3))
            alphas = [alpha, alpha, alpha]
        }
        return zip(stops, alphas).map { $0.withAlphaComponent($1).cgColor }
    }

    private static let clearColors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.clear.cgColor]
}
