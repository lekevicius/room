import AppKit

/// The chrome controls' own animations (B-111, 5.1b) and what each becomes
/// under Reduce Motion (spec §I.1): the press's scale turns into a dim and
/// back; the hover's fade stays a fade. `ControlFeedback` asks its case here.
public enum ControlMotion: String, CaseIterable, Sendable {
    /// The hover fill (or brightening) fades in and out (`Motion.fast`).
    case hoverFade
    /// A press shrinks the control to `Motion.pressScale` over `Motion.pressIn`
    /// and the release springs back (`Motion.pressRelease`).
    case press

    /// The variant under Reduce Motion.
    public var reduced: MotionVariant {
        switch self {
        case .hoverFade, .press: .crossfade
        }
    }

    /// The variant to run now (`Motion.preferences`).
    public var variant: MotionVariant { Motion.reduceMotion ? reduced : .full }
}

/// Hover and press feedback for the chrome's icon buttons and other
/// interactive surfaces (B-111: Back, Forward, Reload, the extensions, the
/// downloads button, the space icons, New Tab, the address field, the card's
/// buttons). One style for every control: the owner reports the pointer and
/// the press; the feedback draws them on the view's own layer.
/// - Hover: `.fill` fades the layer's background to `hoverFill` (the rows'
///   hover, `Palette.sidebarHover`) from `restFill`; `.brighten` fades the
///   view's alpha from `restingAlpha` to 1 (the footer's space icons).
/// - Press: the view's layer scales to `Motion.pressScale` about its centre
///   and springs back on release, as Arc's buttons; under Reduce Motion it
///   dims to `Motion.pressReducedAlpha` and back instead. The scale is an
///   animation only (the layer's model transform stays identity), so
///   AppKit's geometry and hit testing are untouched.
public final class ControlFeedback {
    public enum Hover: Equatable, Sendable {
        case fill
        case brighten
    }

    public let hover: Hover
    private weak var view: NSView?
    public private(set) var isHovering = false
    public private(set) var isPressed = false
    /// A disabled control shows neither.
    public var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { isPressed = false; view?.layer?.removeAnimation(forKey: Self.pressKey) }
            apply(animated: false)
        }
    }
    /// The fill at rest (`.fill`; `nil`: none) and while hovered or pressed.
    public var restFill: () -> NSColor? = { nil }
    public var hoverFill: () -> NSColor = { Palette.sidebarHover }
    /// The view's alpha at rest (`.brighten`: an inactive space icon).
    public var restingAlpha: CGFloat = 1 {
        didSet { if restingAlpha != oldValue { apply(animated: false) } }
    }

    /// A `.fill` control's own alpha when the press began (it may be dimmed by its owner).
    private var alphaBeforePress: CGFloat?

    static let pressKey = "control-press"
    static let fillKey = "control-hover"

    public init(view: NSView, hover: Hover = .fill) {
        self.view = view
        self.hover = hover
        view.wantsLayer = true
    }

    /// The pointer entered or left the control.
    public func setHovering(_ hovering: Bool, animated: Bool = true) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        apply(animated: animated)
    }

    /// The control was pressed (mouse down, or an `NSButton`'s highlight) or released.
    public func setPressed(_ pressed: Bool, animated: Bool = true) {
        guard pressed != isPressed, isEnabled || !pressed else { return }
        if pressed, hover == .fill { alphaBeforePress = view?.alphaValue }
        isPressed = pressed
        apply(animated: animated)
        guard let layer = view?.layer else { return }
        switch animated ? ControlMotion.press.variant : .instant {
        case .full:
            press(layer, pressed)
        case .crossfade:
            layer.removeAnimation(forKey: Self.pressKey)
            fadeAlpha(animated: true)
        case .instant:
            layer.removeAnimation(forKey: Self.pressKey)
            fadeAlpha(animated: false)
        }
    }

    /// The pointer left the window or the view left it: rest at once.
    public func reset() {
        isHovering = false
        isPressed = false
        view?.layer?.removeAnimation(forKey: Self.pressKey)
        apply(animated: false)
    }

    /// The appearance changed: the fill resolves again.
    public func appearanceChanged() { apply(animated: false) }

    private var showsHover: Bool { isEnabled && (isHovering || isPressed) }

    private func apply(animated: Bool) {
        guard let view, let layer = view.layer else { return }
        let animate = animated && view.window != nil
        switch hover {
        case .fill:
            var color: CGColor?
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                color = showsHover ? hoverFill().cgColor : restFill()?.cgColor
            }
            let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = color
            CATransaction.commit()
            if animate, from != color {
                let fade = CABasicAnimation(keyPath: "backgroundColor")
                fade.fromValue = from ?? NSColor.clear.cgColor
                fade.toValue = color ?? NSColor.clear.cgColor
                fade.duration = Motion.fast
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(fade, forKey: Self.fillKey)
            } else {
                layer.removeAnimation(forKey: Self.fillKey)
            }
        case .brighten:
            fadeAlpha(animated: animate)
        }
    }

    /// The alpha the view shows now: brightened while hovered, dimmed while
    /// pressed under Reduce Motion.
    private var targetAlpha: CGFloat {
        var alpha: CGFloat = switch hover {
        case .brighten: showsHover ? 1 : restingAlpha
        case .fill: alphaBeforePress ?? view?.alphaValue ?? 1
        }
        if isPressed, ControlMotion.press.variant != .full { alpha *= Motion.pressReducedAlpha }
        return alpha
    }

    private func fadeAlpha(animated: Bool) {
        guard let view else { return }
        let alpha = targetAlpha
        if !isPressed { alphaBeforePress = nil }
        guard view.alphaValue != alpha else { return }
        if animated, view.window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fast
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = alpha
            }
        } else {
            view.alphaValue = alpha
        }
    }

    /// The press's scale: in over `pressIn`, held, then the release spring
    /// from wherever the press-in got to.
    private func press(_ layer: CALayer, _ pressed: Bool) {
        let scaled = Self.centredScale(Motion.pressScale, in: layer)
        let from = layer.presentation()?.transform ?? CATransform3DIdentity
        let animation: CABasicAnimation
        if pressed {
            animation = CABasicAnimation(keyPath: "transform")
            animation.duration = Motion.pressIn
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.toValue = NSValue(caTransform3D: scaled)
            // Held while the button is down; the release replaces it.
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        } else {
            animation = Motion.pressRelease.animation(keyPath: "transform")
            animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        }
        animation.fromValue = NSValue(caTransform3D: from)
        layer.add(animation, forKey: Self.pressKey)
    }

    /// A scale about the layer's centre whatever its anchor point (AppKit's
    /// layer-backed views anchor at the origin).
    public static func centredScale(_ scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let dx = bounds.midX - (bounds.minX + layer.anchorPoint.x * bounds.width)
        let dy = bounds.midY - (bounds.minY + layer.anchorPoint.y * bounds.height)
        return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-dx, -dy, 0), CATransform3DMakeScale(scale, scale, 1)),
                                   CATransform3DMakeTranslation(dx, dy, 0))
    }
}
