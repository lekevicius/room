import AppKit
import Design

/// Where the floating cluster's pill sits: the window's own buttons, padded
/// to `ClusterMetrics.height` (spec §E: 38 px), centred on them. The buttons
/// are measured, never moved.
public enum ClusterGeometry {
    public static func pill(around buttons: CGRect) -> CGRect {
        let height = ClusterMetrics.height
        let padding = ClusterMetrics.horizontalPadding
        return CGRect(x: buttons.minX - padding, y: buttons.midY - height / 2, width: buttons.width + 2 * padding, height: height)
    }

    /// The pointer counts as near the cluster (it shows again, or stays).
    public static func isNear(_ point: CGPoint, pill: CGRect) -> Bool {
        pill.insetBy(dx: -ClusterMetrics.nearDistance, dy: -ClusterMetrics.nearDistance).contains(point)
    }

    /// The top of the card that drags the window while the sidebar is hidden
    /// (spec §E: the top 5% of the content, Zen `drag-window-from-content`).
    public static func contentDragBand(card: CGRect) -> CGRect {
        CGRect(x: card.minX, y: card.minY, width: card.width, height: (card.height * ClusterMetrics.contentDragFraction).rounded())
    }

    /// A press in the band becomes a window drag once it has moved this far; until
    /// then (and for a click) it is the page's.
    public static func startsWindowDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= ClusterMetrics.contentDragThreshold
    }
}

/// The cluster's fade (spec §E): it fades `Timing.clusterFade` after the
/// pointer last moved near it and shows again when the pointer comes near.
/// Times in seconds on any clock.
public struct ClusterFade: Equatable, Sendable {
    public private(set) var lastNear: TimeInterval?
    public var delay: TimeInterval

    public init(delay: TimeInterval = Timing.clusterFade) {
        self.delay = delay
    }

    /// The cluster appeared (the sidebar was hidden): it shows for the full delay.
    public mutating func reset(now: TimeInterval) { lastNear = now }

    public mutating func pointerMoved(near: Bool, now: TimeInterval) {
        if near { lastNear = now }
    }

    public func isVisible(now: TimeInterval) -> Bool {
        guard let lastNear else { return false }
        return now < lastNear + delay
    }

    /// When it fades if the pointer stays away.
    public var deadline: TimeInterval? { lastNear.map { $0 + delay } }
}

/// The glass pill behind the window's own traffic lights while the sidebar
/// is hidden (spec §E), and the window's drag handle there (Chapter 1
/// carry-over): drag it to move the window, double-click it as a titlebar.
public final class TrafficLightClusterView: NSView {
    private let glass = NSGlassEffectView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("traffic-light-cluster")
        glass.cornerRadius = ClusterMetrics.height / 2
        // The overlay's wash, so page text does not read through behind the buttons.
        let backing = OverlayBackingView()
        backing.wantsLayer = true
        backing.autoresizingMask = [.width, .height]
        glass.contentView = backing
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var mouseDownCanMoveWindow: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, frame.contains(point) else { return nil }
        return self
    }

    public override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 { return TitlebarDoubleClick.perform(in: window) }
        window.performDrag(with: event)
    }
}

/// What a double-click on a titlebar does, from the user's setting
/// (System Settings ▸ Desktop & Dock ▸ "Double-click a window's title bar to").
public enum TitlebarDoubleClick {
    public static func perform(in window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}
