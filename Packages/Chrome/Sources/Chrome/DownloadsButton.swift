import AppKit
import Design

/// The footer's downloads button (spec §F): a down-arrow; while something
/// downloads, a progress ring around it (spinning when a size is unknown);
/// on completion it bounces and shows a count badge until the popover opens.
public final class DownloadsButton: NSView {
    public var onClick: (() -> Void)?
    /// Right-click: the button's menu (Open Library, Show Downloads Folder).
    public var menuProvider: (() -> NSMenu?)?

    private let icon = NSImageView()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let badge = NSTextField(labelWithString: "")
    private let badgeBackground = CALayer()
    private var pressed = false
    /// Hover fill and press (B-111), as the header's buttons.
    public private(set) lazy var feedback = ControlFeedback(view: self)

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Radius.small
        layer?.cornerCurve = .continuous
        _ = feedback
        icon.image = Symbol.downloads.image(pointSize: 14, accessibilityDescription: "Downloads")
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleNone
        addSubview(icon)
        for shape in [track, ring] {
            shape.fillColor = nil
            shape.lineWidth = DownloadsMetrics.ringWidth
            shape.lineCap = .round
            shape.isHidden = true
            layer?.addSublayer(shape)
        }
        ring.strokeEnd = 0
        badgeBackground.isHidden = true
        layer?.addSublayer(badgeBackground)
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.isHidden = true
        addSubview(badge)
        toolTip = "Downloads (⇧⌘J)"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Downloads")
        setAccessibilityIdentifier("downloads")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override var wantsUpdateLayer: Bool { true }

    // MARK: State

    /// 0…1 while downloading, `-1` while a size is unknown, `nil` when idle (`DownloadRules.progress`).
    public var progress: Double? {
        didSet {
            guard progress != oldValue else { return }
            updateRing(animated: oldValue != nil)
        }
    }

    /// Finished downloads not seen yet; 0 hides the badge.
    public var badgeCount = 0 {
        didSet {
            guard badgeCount != oldValue else { return }
            badge.stringValue = badgeCount > 99 ? "99+" : "\(badgeCount)"
            badge.isHidden = badgeCount == 0
            badgeBackground.isHidden = badgeCount == 0
            needsLayout = true
        }
    }

    /// The spring bounce on completion (spec §F: 0.5 s); a fade under Reduce Motion.
    public func bounce() {
        guard let layer else { return }
        if Motion.reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.4
            fade.toValue = 1
            fade.duration = Motion.medium
            layer.add(fade, forKey: "bounce")
            return
        }
        centreAnchor()
        let spring = Motion.toast.animation(keyPath: "transform.scale")
        spring.fromValue = DownloadsMetrics.bounceScale
        spring.toValue = 1
        spring.initialVelocity = 8
        layer.add(spring, forKey: "bounce")
    }

    /// The point downloads fly to, in `view`'s coordinates.
    public func target(in view: NSView) -> NSPoint {
        convert(NSPoint(x: bounds.midX, y: bounds.midY), to: view)
    }

    private func centreAnchor() {
        guard let layer, layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
    }

    private func updateRing(animated: Bool) {
        let active = progress != nil
        track.isHidden = !active
        ring.isHidden = !active
        // The arrow shrinks into the ring while downloading.
        icon.image = (active ? Symbol.downloadInProgress : Symbol.downloads)
            .image(pointSize: active ? 11 : 14, accessibilityDescription: "Downloads")
        guard let progress else {
            ring.removeAnimation(forKey: "spin")
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if progress < 0 {
            ring.strokeEnd = 0.25
            if ring.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = 1
                spin.repeatCount = .infinity
                ring.add(spin, forKey: "spin")
            }
        } else {
            ring.removeAnimation(forKey: "spin")
            ring.strokeEnd = max(0.02, progress)
        }
        CATransaction.commit()
        setAccessibilityValue(progress < 0 ? "Downloading" : "\(Int(progress * 100))%")
    }

    public override func updateLayer() {
        track.strokeColor = NSColor.tertiaryLabelColor.cgColor
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        badgeBackground.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    public override func layout() {
        super.layout()
        icon.frame = bounds
        let side = min(bounds.width, bounds.height) - 2 * DownloadsMetrics.ringInset
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        for shape in [track, ring] { shape.frame = bounds }
        // Starts at 12 o'clock and runs clockwise on screen, whichever way the layer's geometry is flipped.
        let flipped = ring.contentsAreFlipped()
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: side / 2, startAngle: flipped ? -.pi / 2 : .pi / 2,
                    endAngle: flipped ? 1.5 * .pi : -1.5 * .pi, clockwise: !flipped)
        track.path = path
        ring.path = path
        let size = badge.cell?.cellSize ?? .zero
        let height = DownloadsMetrics.badgeHeight
        let width = max(height, ceil(size.width) + 6)
        let badgeRect = NSRect(x: bounds.maxX - width + 3, y: -2, width: width, height: height)
        badgeBackground.frame = badgeRect
        badgeBackground.cornerRadius = height / 2
        badge.frame = NSRect(x: badgeRect.minX, y: badgeRect.minY + (height - ceil(size.height)) / 2, width: width, height: ceil(size.height))
    }

    // MARK: Mouse

    public override func mouseDown(with event: NSEvent) {
        pressed = true
        feedback.setPressed(true)
    }

    public override func mouseDragged(with event: NSEvent) {
        feedback.setPressed(pressed && bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    public override func mouseUp(with event: NSEvent) {
        feedback.setPressed(false)
        defer { pressed = false }
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) { feedback.setHovering(true) }
    public override func mouseExited(with event: NSEvent) { feedback.setHovering(false) }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        feedback.reset()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        feedback.appearanceChanged()
    }

        onClick?()
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The downloads popover (spec §F): an `NSPopover` on the footer button
/// with the list as a SwiftUI leaf (PLAN §4: downloads rows are SwiftUI).
public final class DownloadsPopover: NSObject, NSPopoverDelegate {
    private let list: DownloadList
    private var popover: NSPopover?

    public init(list: DownloadList) {
        self.list = list
    }

    public var isShown: Bool { popover?.isShown == true }
    /// The popover's content on screen (DEBUG captures, spikes).
    public var contentView: NSView? { popover?.contentViewController?.view }

    public func toggle(relativeTo view: NSView) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        show(relativeTo: view)
    }

    /// Points at `rect` of `view` (its bounds by default).
    public func show(relativeTo view: NSView, rect: NSRect? = nil) {
        guard view.window != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !Motion.reduceMotion
        popover.contentViewController = DownloadsViewController(list: list)
        popover.delegate = self
        self.popover = popover
        // Above the footer button (in a flipped view, minY is the top edge).
        popover.show(relativeTo: rect ?? view.bounds, of: view, preferredEdge: view.isFlipped ? .minY : .maxY)
        list.markSeen()
    }

    public func close() { popover?.performClose(nil) }

    public func popoverDidClose(_ notification: Notification) {
        list.markSeen()
        popover = nil
    }
}

/// Ring, badge and bounce sizes (chosen).
public enum DownloadsMetrics {
    public static let ringWidth: CGFloat = 2
    /// Inside the 28 pt footer button.
    public static let ringInset: CGFloat = 4
    public static let badgeHeight: CGFloat = 13
    public static let bounceScale: CGFloat = 1.3
    /// The popover's list (chosen) and the rows' icon.
    public static let popoverWidth: CGFloat = 320
    public static let rowIconSize: CGFloat = 32
    public static let maxVisibleRows = 6
    /// The fly-in (spec §F, Zen): 1000 ms, ending at 45% scale.
    public static let flyDuration: TimeInterval = 1
    public static let flyEndScale: CGFloat = 0.45
    public static let flyIconSize: CGFloat = 32
    /// A click this recent starts the flight; otherwise it starts at the card's centre (chosen).
    public static let clickMemory: TimeInterval = 3
}
