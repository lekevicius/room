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

    /// The space's theme color; `nil` leaves the neutral material (Dia's look).
    public var tintColor: NSColor? { tintView.color }

    public func setTintColor(_ color: NSColor?, animated: Bool) {
        tintView.setColor(color, animated: animated)
    }

    /// Follows `WindowActivity`; the material itself already follows the
    /// window's active state unless `state` is forced.
    public var isWindowActive: Bool {
        get { tintView.isWindowActive }
        set { tintView.isWindowActive = newValue }
    }

    public override var mouseDownCanMoveWindow: Bool { false }
}

/// A vertical gradient of the space color at 10–25% opacity over the material.
final class SpaceTintView: NSView {
    private(set) var color: NSColor?
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
        // Non-flipped layer: start at the top edge.
        layer.startPoint = CGPoint(x: 0.5, y: 1)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
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

    func setColor(_ newColor: NSColor?, animated: Bool) {
        color = newColor
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
        guard let color else { return Self.clearColors }
        let factor = isWindowActive ? 1 : Self.inactiveFactor
        let top = Materials.tintOpacity * factor
        let bottom = Materials.tintOpacityRange.lowerBound * factor
        return [color.withAlphaComponent(top).cgColor, color.withAlphaComponent(bottom).cgColor]
    }

    private static let clearColors = [NSColor.clear.cgColor, NSColor.clear.cgColor]
}
