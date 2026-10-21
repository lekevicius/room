import AppKit
import Design
import Engine

/// Page zoom as pure rules (ROADMAP 2.6 task 3: ⌘= / ⌘- / ⌘0).
public enum ZoomRules {
    /// Chrome's preset zoom factors (`zoom::kPresetZoomFactors`), 25–500%.
    public static let steps: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]
    /// Factors this close count as the same step (the engine round-trips through a log scale).
    static let epsilon = 0.001

    /// The next preset above `factor`; the largest stays.
    public static func zoomIn(from factor: Double) -> Double {
        steps.first { $0 > factor + epsilon } ?? steps.last!
    }

    /// The next preset below `factor`; the smallest stays.
    public static func zoomOut(from factor: Double) -> Double {
        steps.last { $0 < factor - epsilon } ?? steps.first!
    }

    public static func isDefault(_ factor: Double) -> Bool { abs(factor - 1) < epsilon }

    /// "110%".
    public static func label(_ factor: Double) -> String {
        "\(Int((factor * 100).rounded()))%"
    }
}

/// The transient zoom indicator (ROADMAP 2.6 task 3): the page's zoom with
/// − / + and Reset, at the card's top-right (below the find bar when it is
/// open); it goes `Timing.zoomIndicator` after the last change unless the
/// pointer is on it.
public final class ZoomIndicator {
    private weak var host: NSView?
    private var view: ZoomIndicatorView?
    private weak var page: (any WebContents)?
    private var hideWork: DispatchWorkItem?
    /// Where the indicator's top sits (below the find bar while it shows).
    public var topOffset: () -> CGFloat = { FindMetrics.inset }

    public init(host: NSView) {
        self.host = host
    }

    public var isVisible: Bool { view != nil }
    /// The indicator on screen (DEBUG captures, spikes).
    public var indicatorView: NSView? { view }
    public var labelText: String { view?.label.stringValue ?? "" }

    public func zoomIn(_ page: any WebContents) { apply(ZoomRules.zoomIn(from: page.zoomFactor), to: page) }
    public func zoomOut(_ page: any WebContents) { apply(ZoomRules.zoomOut(from: page.zoomFactor), to: page) }
    public func reset(_ page: any WebContents) { apply(1, to: page) }

    /// The focused page's tool layer (the card's, Peek's).
    public func setHost(_ host: NSView) {
        guard host !== self.host else { return }
        hide()
        self.host = host
    }

    /// The card shows another page: the indicator belongs to the old one.
    public func setPage(_ page: (any WebContents)?) {
        guard page !== self.page else { return }
        hide()
        self.page = page
    }

    private func apply(_ factor: Double, to page: any WebContents) {
        page.zoomFactor = factor
        self.page = page
        show(factor)
    }

    private func show(_ factor: Double) {
        guard let host else { return }
        if view == nil {
            let view = ZoomIndicatorView()
            view.onZoomIn = { [weak self] in if let page = self?.page { self?.zoomIn(page) } }
            view.onZoomOut = { [weak self] in if let page = self?.page { self?.zoomOut(page) } }
            view.onReset = { [weak self] in if let page = self?.page { self?.reset(page) } }
            view.onHover = { [weak self] hovering in hovering ? self?.hideWork?.cancel() : self?.scheduleHide() }
            host.addSubview(view)
            self.view = view
        }
        view?.label.stringValue = ZoomRules.label(factor)
        view?.resetButton.isEnabled = !ZoomRules.isDefault(factor)
        layout()
        scheduleHide()
    }

    public func layout() {
        guard let view, let host else { return }
        let size = view.fittingSize
        let top = topOffset()
        let y = host.isFlipped ? top : host.bounds.height - top - size.height
        view.frame = NSRect(x: host.bounds.width - FindMetrics.inset - size.width, y: y, width: size.width, height: ZoomMetrics.height)
        view.autoresizingMask = host.isFlipped ? [.minXMargin, .maxYMargin] : [.minXMargin, .minYMargin]
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.zoomIndicator, execute: work)
    }

    public func hide() {
        hideWork?.cancel()
        view?.removeFromSuperview()
        view = nil
    }
}

final class ZoomIndicatorView: NSView {
    let label = NSTextField(labelWithString: "100%")
    let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let minus = NSButton()
    private let plus = NSButton()
    private let glass = NSGlassEffectView()
    private let content = NSStackView()
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onReset: (() -> Void)?
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.cornerRadius = ZoomMetrics.height / 2
        content.orientation = .horizontal
        content.spacing = Spacing.xs
        content.edgeInsets = NSEdgeInsets(top: 0, left: Spacing.s, bottom: 0, right: Spacing.s)
        // Reduce Transparency (5.3b): an opaque fill under the controls.
        SolidBackingView.install(in: content, cornerRadius: ZoomMetrics.height / 2)
        glass.contentView = content
        addSubview(glass)
        label.font = Typography.zoomValue
        label.alignment = .center
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        label.setAccessibilityIdentifier("zoom-level")
        for (button, symbol, help, action) in [(minus, Symbol.zoomOut, "Zoom Out (⌘-)", #selector(minusClicked)),
                                               (plus, Symbol.zoomIn, "Zoom In (⌘=)", #selector(plusClicked))] {
            button.image = symbol.image(.controlSmall, accessibilityDescription: help)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = help
            button.target = self
            button.action = action
        }
        resetButton.bezelStyle = .push
        resetButton.controlSize = .small
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        resetButton.toolTip = "Actual Size (⌘0)"
        content.addArrangedSubview(minus)
        content.addArrangedSubview(label)
        content.addArrangedSubview(plus)
        content.addArrangedSubview(resetButton)
        setAccessibilityIdentifier("zoom-indicator")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override var fittingSize: NSSize {
        NSSize(width: ceil(content.fittingSize.width), height: ZoomMetrics.height)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    @objc private func minusClicked() { onZoomOut?() }
    @objc private func plusClicked() { onZoomIn?() }
    @objc private func resetClicked() { onReset?() }
}

/// The zoom indicator's height (chosen; the find bar's).
public enum ZoomMetrics {
    public static let height: CGFloat = FindMetrics.height
}
