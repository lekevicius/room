import AppKit
import Design

/// A new download's icon flies on an arc from the click that started it into
/// the footer's downloads button (spec §F, Zen's download animation: 1000 ms,
/// ending at 45% scale, arc height twice the distance capped at 1200 pt).
/// The arc's top is held inside the window so the icon never leaves it.
public enum DownloadFlyIn {
    /// The flight's path in y-up coordinates: a quadratic curve whose highest
    /// point is `min(2 × distance, 1200)` above the higher end, but no higher
    /// than `ceiling`.
    public static func path(from start: CGPoint, to end: CGPoint, ceiling: CGFloat) -> CGPath {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let top = max(start.y, end.y)
        let apex = min(top + min(2 * distance, 1200), max(top, ceiling))
        // A quadratic's peak is halfway between the chord and its control point.
        let chordMid = (start.y + end.y) / 2
        let control = CGPoint(x: (start.x + end.x) / 2, y: chordMid + 2 * (apex - chordMid))
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Runs the flight over `view` (the window's root view) from `start` to
    /// `end` (both in `view`'s coordinates); `completion` when it lands. No
    /// flight under Reduce Motion.
    public static func run(image: NSImage, from start: NSPoint, to end: NSPoint, in view: NSView, completion: @escaping () -> Void) {
        guard ChromeMotion.downloadFlyIn.animates else { return completion() }
        let overlay = FlightView(frame: view.bounds)
        view.addSubview(overlay, positioned: .above, relativeTo: nil)
        guard let layer = overlay.layer else {
            overlay.removeFromSuperview()
            return completion()
        }
        // The overlay is not flipped: its layer's coordinates are its own (y up).
        let from = overlay.convert(start, from: view)
        let to = overlay.convert(end, from: view)
        let size = DownloadsMetrics.flyIconSize
        let icon = CALayer()
        icon.contents = image
        icon.contentsGravity = .resizeAspect
        icon.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        icon.position = to
        icon.transform = CATransform3DMakeScale(DownloadsMetrics.flyEndScale, DownloadsMetrics.flyEndScale, 1)
        icon.opacity = 0
        icon.shadowOpacity = 0.25
        icon.shadowRadius = 4
        icon.shadowOffset = CGSize(width: 0, height: -1)
        layer.addSublayer(icon)

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path(from: from, to: to, ceiling: overlay.bounds.maxY - size)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = DownloadsMetrics.flyEndScale
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.85, 1]
        let group = CAAnimationGroup()
        group.animations = [move, scale, fade]
        group.duration = DownloadsMetrics.flyDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated {
                overlay.removeFromSuperview()
                completion()
            }
        }
        icon.add(group, forKey: "fly")
        CATransaction.commit()
    }
}

/// Holds the flying icon above everything; never takes the mouse.
private final class FlightView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
