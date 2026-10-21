import AppKit
import Design

/// The status pill's rules (spec §I.14, §C): a hovered link's URL appears
/// bottom-left after `Timing.statusPillDelay`; after it has shown for
/// `Timing.statusPillExpand` it widens to the full URL; leaving the link
/// hides it after a short grace (moving to the next link keeps it up and
/// shows the new URL at once); when the pointer comes near it, it moves to
/// the bottom-right. Time comes from a `ToastScheduler`, so tests drive it.
public final class StatusPillState {
    public enum Side: Equatable { case leading, trailing }
    public enum Width: Equatable {
        /// Elided to a third of the card (Chrome's standard bubble width).
        case standard
        /// The full URL, up to the card's width.
        case full
    }

    /// What the pill shows; `nil` while hidden.
    public private(set) var shownText: String?
    public private(set) var width = Width.standard
    public private(set) var side = Side.leading
    /// The last status the page reported (`nil`: none).
    public private(set) var status: String?
    /// After every change of what is shown.
    public var onChange: (() -> Void)?

    private let scheduler: ToastScheduler
    private var showTimer: ToastTimer?
    private var expandTimer: ToastTimer?
    private var hideTimer: ToastTimer?
    /// When the pill last appeared (for the measured delay).
    public private(set) var shownAt: TimeInterval?
    /// When the status that is waiting arrived.
    public private(set) var requestedAt: TimeInterval?

    public init(scheduler: ToastScheduler) {
        self.scheduler = scheduler
    }

    public var isVisible: Bool { shownText != nil }

    /// The page's status text changed (`didChangeStatusText`); `nil` or empty clears it.
    public func setStatus(_ text: String?) {
        let text = (text?.isEmpty ?? true) ? nil : text
        guard text != status else { return }
        status = text
        hideTimer?.cancel()
        hideTimer = nil
        guard let text else {
            showTimer?.cancel()
            showTimer = nil
            requestedAt = nil
            guard isVisible else { return }
            hideTimer = scheduler.schedule(after: Timing.statusPillHideGrace) { [weak self] in self?.hide() }
            return
        }
        if isVisible {
            // Link to link: the new URL at once, its own expansion countdown.
            show(text)
            return
        }
        requestedAt = scheduler.now
        guard showTimer == nil else { return }
        showTimer = scheduler.schedule(after: Timing.statusPillDelay) { [weak self] in
            guard let self else { return }
            self.showTimer = nil
            if let status = self.status { self.show(status) }
        }
    }

    /// The pointer moved; `nearLeading` / `nearTrailing` say whether it is
    /// within reach of the pill at either bottom corner (`StatusPillRules.isNear`).
    public func pointerMoved(nearLeading: Bool, nearTrailing: Bool) {
        let newSide = StatusPillRules.side(current: side, nearLeading: nearLeading, nearTrailing: nearTrailing)
        guard newSide != side else { return }
        side = newSide
        if isVisible { onChange?() }
    }

    /// The card shows another page: whatever was shown goes at once.
    public func reset() {
        status = nil
        showTimer?.cancel()
        showTimer = nil
        hide()
    }

    private func show(_ text: String) {
        shownText = text
        width = .standard
        shownAt = scheduler.now
        expandTimer?.cancel()
        expandTimer = scheduler.schedule(after: Timing.statusPillExpand) { [weak self] in
            guard let self, self.shownText == text else { return }
            self.width = .full
            self.onChange?()
        }
        onChange?()
    }

    private func hide() {
        expandTimer?.cancel()
        expandTimer = nil
        hideTimer = nil
        guard shownText != nil else { return }
        shownText = nil
        width = .standard
        side = .leading
        onChange?()
    }
}

/// Geometry of the pill (pure; `StatusPillState` holds the timing).
public enum StatusPillRules {
    /// Which corner the pill takes: bottom-left, unless the pointer is near
    /// it there (then bottom-right); near both corners (a narrow card) it stays.
    public static func side(current: StatusPillState.Side, nearLeading: Bool, nearTrailing: Bool) -> StatusPillState.Side {
        switch (nearLeading, nearTrailing) {
        case (true, false): .trailing
        case (true, true): current
        default: .leading
        }
    }

    /// Whether `point` is within `StatusPillMetrics.dodgeDistance` of `rect`.
    public static func isNear(_ point: CGPoint, _ rect: CGRect) -> Bool {
        rect.insetBy(dx: -StatusPillMetrics.dodgeDistance, dy: -StatusPillMetrics.dodgeDistance).contains(point)
    }

    /// The pill's widest extent for its width mode in a card of `cardWidth`.
    public static func maxWidth(_ width: StatusPillState.Width, cardWidth: CGFloat) -> CGFloat {
        let available = max(0, cardWidth - 2 * StatusPillMetrics.inset)
        switch width {
        case .standard: return min(available, max(StatusPillMetrics.minWidth, cardWidth / 3))
        case .full: return available
        }
    }

    /// The pill's frame in a flipped card of `bounds` for text `textWidth` wide.
    public static func frame(side: StatusPillState.Side, width: StatusPillState.Width, textWidth: CGFloat, bounds: CGRect) -> CGRect {
        let w = min(ceil(textWidth) + 2 * StatusPillMetrics.horizontalPadding, maxWidth(width, cardWidth: bounds.width))
        let y = bounds.maxY - StatusPillMetrics.inset - StatusPillMetrics.height
        let x = side == .leading ? bounds.minX + StatusPillMetrics.inset : bounds.maxX - StatusPillMetrics.inset - w
        return CGRect(x: x, y: y, width: w, height: StatusPillMetrics.height)
    }
}

/// The pill's size (chosen; Chrome's status bubble is a small rounded
/// rectangle at the content's bottom-left).
public enum StatusPillMetrics {
    public static let height: CGFloat = 22
    public static let horizontalPadding: CGFloat = 8
    /// From the card's bottom and side edges.
    public static let inset: CGFloat = 4
    public static let minWidth: CGFloat = 200
    /// The pointer this close to the pill moves it to the other corner.
    public static let dodgeDistance: CGFloat = 24
}

/// Shows `StatusPillState` over the card's page: a small material capsule at
/// a bottom corner that never takes the mouse; the pointer is followed only
/// while the pill is up.
public final class StatusPill {
    public let state: StatusPillState
    private weak var host: NSView?
    private let view = StatusPillView()
    private var mouseMonitor: Any?

    public init(host: NSView, scheduler: ToastScheduler = MainQueueToastScheduler()) {
        self.host = host
        state = StatusPillState(scheduler: scheduler)
        state.onChange = { [weak self] in self?.update() }
    }

    isolated deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    /// The pill on screen (DEBUG captures, spikes).
    public var pillView: NSView? { view.superview == nil ? nil : view }

    public func setStatus(_ text: String?) { state.setStatus(text) }

    public func reset() { state.reset() }

    /// The focused page's tool layer (the card's, Peek's): the pill starts over there.
    public func setHost(_ host: NSView) {
        guard host !== self.host else { return }
        state.reset()
        view.removeFromSuperview()
        self.host = host
    }

    private func update() {
        guard let host, let text = state.shownText else {
            view.removeFromSuperview()
            stopFollowingPointer()
            return
        }
        if view.superview !== host { host.addSubview(view) }
        view.label.stringValue = text
        layout()
        followPointer()
    }

    public func layout() {
        guard let host, view.superview === host else { return }
        let textWidth = view.label.cell?.cellSize.width ?? 0
        view.frame = StatusPillRules.frame(side: state.side, width: state.width, textWidth: textWidth, bounds: host.bounds)
    }

    private func followPointer() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.pointerMoved(event)
            return event
        }
    }

    private func stopFollowingPointer() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private func pointerMoved(_ event: NSEvent) {
        guard let host, event.window === host.window else { return }
        let point = host.convert(event.locationInWindow, from: nil)
        let textWidth = view.label.cell?.cellSize.width ?? 0
        let leading = StatusPillRules.frame(side: .leading, width: state.width, textWidth: textWidth, bounds: host.bounds)
        let trailing = StatusPillRules.frame(side: .trailing, width: state.width, textWidth: textWidth, bounds: host.bounds)
        state.pointerMoved(nearLeading: StatusPillRules.isNear(point, leading), nearTrailing: StatusPillRules.isNear(point, trailing))
    }
}

final class StatusPillView: NSView {
    let label = NSTextField(labelWithString: "")
    private let background = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Radius.small
        background.layer?.cornerCurve = .continuous
                background.layer?.borderColor = NSColor.separatorColor.cgColor
        addSubview(background)
        label.font = Typography.secondary
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        setAccessibilityIdentifier("status-pill")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        background.layer?.borderWidth = Hairline.width(in: self)
        super.layout()
        background.frame = bounds
        let height = ceil(label.cell?.cellSize.height ?? 14)
        label.frame = NSRect(x: StatusPillMetrics.horizontalPadding, y: ((bounds.height - height) / 2).rounded(),
                             width: max(0, bounds.width - 2 * StatusPillMetrics.horizontalPadding), height: height)
    }
}
