import AppKit
import Card
import Design
import Engine
import Observation
import Tabs
import UIKitCore

/// Peek on screen (spec §I.6): the content area dimmed 30%, an overlay card
/// of 86% of it with 24 pt corners, a header with the domain, Open as Tab
/// (⌘O), Split (⇧⌘O, 2.7b) and ×, and the page in its own `PageContainerView`
/// with its own tool and prompt layers. A click on the dim closes it; nothing
/// under the dim gets an event. It opens scaling up from the click.
final class PeekPresenter: PeekDisplay {
    private weak var rootView: BrowserWindowView?
    let overlay = PeekOverlayView()
    private(set) weak var contents: (any WebContents)?
    /// Close (a click on the dim, ×), Open as Tab.
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?
    /// The focused page changed: Peek's page with its container, or `nil` (back to the card).
    var onFocus: (((any WebContents)?, PageContainerView?) -> Void)?
    /// Where the last click in the window was (root view coordinates), if recent: the open animation starts there.
    var recentClick: () -> CGPoint? = { nil }
    /// Spikes: the overlay was shown and its first frame committed.
    var onPresented: (() -> Void)?

    init(rootView: BrowserWindowView) {
        self.rootView = rootView
        overlay.isHidden = true
        overlay.onDimClick = { [weak self] in self?.onClose?() }
        overlay.header.onClose = { [weak self] in self?.onClose?() }
        overlay.header.onExpand = { [weak self] in self?.onExpand?() }
        // Under the floating cluster and the sidebar overlay, over the card.
        rootView.addSubview(overlay, positioned: .below, relativeTo: rootView.clusterView)
    }

    var isShown: Bool { contents != nil }

    func showPeek(_ contents: (any WebContents)?, animated: Bool) {
        let previous = self.contents
        self.contents = contents
        if let contents {
            overlay.container.pageView = contents.nativeView
            overlay.isHidden = false
            overlay.alphaValue = 1
            layout()
            trackHeader(contents)
            onFocus?(contents, overlay.container)
            focus(contents)
            if animated { animateOpen() } else { overlay.card.layer?.transform = CATransform3DIdentity }
            CATransaction.setCompletionBlock { [weak self] in self?.onPresented?() }
        } else if previous != nil {
            onFocus?(nil, nil)
            if animated, !Motion.reduceMotion {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.fast
                    overlay.animator().alphaValue = 0
                }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.detach() } })
            } else {
                detach()
            }
        }
    }

    /// Off screen once closed (the container lets go of a page view Open as Tab already took into the card).
    private func detach() {
        guard contents == nil else { return }
        overlay.isHidden = true
        overlay.container.pageView = nil
    }

    /// The card's rect: Peek covers the content area (the page card), not the sidebar.
    func layout() {
        guard let rootView, !overlay.isHidden else { return }
        overlay.frame = rootView.currentLayout.card
    }

    private func focus(_ contents: any WebContents) {
        guard let window = overlay.window else { return }
        var queue = [contents.nativeView]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.acceptsFirstResponder { window.makeFirstResponder(view); return }
            queue += view.subviews
        }
    }

    /// Scales up from the click (CEF reports no link rect) over `Motion.slow`;
    /// the dim fades in. Reduce Motion: a fade.
    private func animateOpen() {
        guard let layer = overlay.card.layer else { return }
        overlay.layoutSubtreeIfNeeded()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Motion.reduceMotion ? Motion.medium : Motion.fast
        overlay.dim.layer?.add(fade, forKey: "peek-open")
        if Motion.reduceMotion {
            layer.add(fade, forKey: "peek-open")
            return
        }
        let frame = overlay.card.frame
        let click = recentClick().map { overlay.convert($0, from: rootView) } ?? CGPoint(x: frame.midX, y: frame.midY)
        let scale = PeekMetrics.openStartScale
        // The card's layer scales about its frame origin (AppKit's anchor), the
        // top-left corner here (flipped): move that corner so the small card centres on the click.
        let dx = click.x - frame.minX - frame.width * scale / 2
        let dy = click.y - frame.minY - frame.height * scale / 2
        let start = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(dx, overlay.isFlipped ? -dy : dy, 0))
        let grow = CASpringAnimation(perceptualDuration: Motion.slow, bounce: 0)
        grow.keyPath = "transform"
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = grow.settlingDuration
        layer.add(grow, forKey: "peek-open")
        layer.add(fade, forKey: "peek-open-fade")
    }

    /// The header's domain and the card's fill follow the page.
    private func trackHeader(_ contents: any WebContents) {
        let (url, title, background) = withObservationTracking {
            (contents.url, contents.title, contents.rootBackgroundColor)
        } onChange: { [weak self, id = ObjectIdentifier(contents)] in
            Task { @MainActor in
                guard let self, let current = self.contents, ObjectIdentifier(current) == id else { return }
                self.trackHeader(current)
            }
        }
        overlay.header.set(host: url?.host() ?? url?.absoluteString ?? "", title: title)
        // As the page card: the fill (and the header on it) follows the page's root background.
        overlay.card.backgroundColor = background ?? Palette.cardBackground
        // Its text and buttons read on that fill, whatever the window's appearance.
        overlay.header.appearance = NSAppearance.reading(on: background)
    }
}

/// The dim over the content area with Peek's card in it.
final class PeekOverlayView: NSView {
    let dim = PeekDimView()
    let card = CardView()
    let header = PeekHeaderView()
    let container = PageContainerView()
    var onDimClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("peek")
        wantsLayer = true
        dim.onClick = { [weak self] in self?.onDimClick?() }
        card.cornerRadius = PeekMetrics.cornerRadius
        card.isElevated = true
        card.topAccessory = header
        card.contentView = container
        card.setAccessibilityIdentifier("peek-card")
        addSubview(dim)
        addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The card is 86% of the content area, centred (spec §I.6).
    static func cardFrame(in bounds: CGRect) -> CGRect {
        let width = (bounds.width * PeekMetrics.sizeFraction).rounded()
        let height = (bounds.height * PeekMetrics.sizeFraction).rounded()
        return CGRect(x: (bounds.midX - width / 2).rounded(), y: (bounds.midY - height / 2).rounded(), width: width, height: height)
    }

    override func layout() {
        super.layout()
        dim.frame = bounds
        card.frame = Self.cardFrame(in: bounds)
    }

    /// Everything under the overlay is the dim's or the card's: nothing reaches the page below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? dim
    }
}

/// Black at `PeekMetrics.dimAlpha` over the content area, in the card's corner; a click closes Peek.
final class PeekDimView: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(PeekMetrics.dimAlpha).cgColor
        layer?.cornerRadius = CardMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        setAccessibilityIdentifier("peek-dim")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

/// Peek's header: the domain (the title on hover as a tooltip), Open as Tab, Split (2.7b) and ×.
final class PeekHeaderView: NSView {
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?
    private let domain = NSTextField(labelWithString: "")
    private let expand = PeekHeaderView.button(.peekExpand, "Open as Tab (⌘O)")
    let split = PeekHeaderView.button(.peekSplit, "Open in Split View (⇧⌘O) — Phase 2.7b")
    private let close = PeekHeaderView.button(.closeTab, "Close (Esc)")

    override init(frame: NSRect) {
        super.init(frame: frame)
        domain.font = Typography.spaceTitle
        domain.textColor = .secondaryLabelColor
        domain.lineBreakMode = .byTruncatingMiddle
        domain.setAccessibilityIdentifier("peek-domain")
        expand.target = self
        expand.action = #selector(expandClicked)
        expand.setAccessibilityIdentifier("peek-open-as-tab")
        split.isEnabled = false
        split.setAccessibilityIdentifier("peek-split")
        close.target = self
        close.action = #selector(closeClicked)
        close.setAccessibilityIdentifier("peek-close")
        [domain, expand, split, close].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var fittingSize: NSSize { NSSize(width: bounds.width, height: PeekMetrics.headerHeight) }

    func set(host: String, title: String?) {
        domain.stringValue = host
        toolTip = title
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func layout() {
        super.layout()
        let size = PeekMetrics.headerButtonSize, padding = PeekMetrics.headerPadding
        let y = ((bounds.height - size) / 2).rounded()
        close.frame = NSRect(x: bounds.width - padding - size, y: y, width: size, height: size)
        split.frame = close.frame.offsetBy(dx: -size, dy: 0)
        expand.frame = split.frame.offsetBy(dx: -size, dy: 0)
        let height = domain.cell?.cellSize.height ?? 16
        domain.frame = NSRect(x: padding + Spacing.xs, y: ((bounds.height - height) / 2).rounded(), width: max(0, expand.frame.minX - padding - Spacing.xs),
                              height: height)
    }

    @objc private func expandClicked() { onExpand?() }
    @objc private func closeClicked() { onClose?() }

    private static func button(_ symbol: Symbol, _ tip: String) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = symbol.image(pointSize: 13, accessibilityDescription: tip)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        return button
    }
}
