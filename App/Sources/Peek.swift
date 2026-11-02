import AppKit
import Card
import Design
import Engine
import Observation
import Tabs
import UIKitCore

/// Peek on screen (spec §I.6; 5.13, the user's design): the page behind fades
/// (its opacity, no dark layer, so a split's panes fade alike), an overlay card
/// nearly the content area's height with 24 pt corners and a quiet header with
/// the domain, Close, Open as Tab (⌘O) and Split (⇧⌘O) as glass circles beside
/// its top-right corner, and the page in its own `PageContainerView` with its
/// own tool and prompt layers. A click beside the card closes it; nothing
/// under the overlay gets an event. It opens growing from the click.
final class PeekPresenter: PeekDisplay {
    private weak var rootView: BrowserWindowView?
    let overlay = PeekOverlayView()
    private(set) weak var contents: (any WebContents)?
    /// Close (a click on the dim, ×), Open as Tab, Split.
    var onClose: (() -> Void)?
    var onExpand: (() -> Void)?
    var onSplit: (() -> Void)?
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
        overlay.buttons.onClose = { [weak self] in self?.onClose?() }
        overlay.buttons.onExpand = { [weak self] in self?.onExpand?() }
        overlay.buttons.onSplit = { [weak self] in self?.onSplit?() }
        // Under the sidebar's overlay, over the card.
        rootView.addSubview(overlay, positioned: .below, relativeTo: rootView.overlayView)
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
            fadeBackground(to: PeekMetrics.backgroundAlpha, animated: animated)
            CATransaction.setCompletionBlock { [weak self] in self?.onPresented?() }
        } else if previous != nil {
            onFocus?(nil, nil)
            fadeBackground(to: 1, animated: animated)
            if animated, CardMotion.peekClose.animates {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.fast
                    overlay.animator().alphaValue = 0
                }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.detach() } })
            } else {
                detach()
            }
        }
    }

    /// The page card (a split's panes with it) and the toolbar fade and shrink a little while Peek
    /// shows (5.13, the user: the page behind recedes, scaled down as well as faded).
    private func fadeBackground(to alpha: CGFloat, animated: Bool) {
        guard let rootView else { return }
        let views: [NSView] = [rootView.cardView, rootView.toolbarView]
        let receding = alpha < 1
        let animates = animated && CardMotion.peekOpen.animates
        if animates {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.medium
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for view in views { view.animator().alphaValue = alpha }
            }
        } else {
            views.forEach { $0.alphaValue = alpha }
        }
        // The scale only moves: under Reduce Motion the page fades alone.
        let scale = receding && CardMotion.peekOpen.variant == .full ? PeekMetrics.backgroundScale : 1
        guard let layer = rootView.cardView.layer else { return }
        let bounds = layer.bounds
        // About the card's centre (AppKit's layers anchor at their origin).
        let target = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-bounds.midX, -bounds.midY, 0),
                                                             CATransform3DMakeScale(scale, scale, 1)),
                                         CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0))
        if animates {
            let spring = CASpringAnimation(perceptualDuration: Motion.slow, bounce: 0)
            spring.keyPath = "transform"
            spring.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            spring.toValue = NSValue(caTransform3D: target)
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "peek-recede")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()
    }

    /// Spikes: the page behind's scale.
    var debugBackgroundScale: CGFloat { rootView?.cardView.layer.map { $0.transform.m11 } ?? -1 }

    /// Spikes: the page behind's opacity.
    var debugBackgroundAlpha: CGFloat { rootView?.cardView.alphaValue ?? -1 }

    /// Off screen once closed (the container lets go of a page view Open as Tab already took into the card).
    private func detach() {
        guard contents == nil else { return }
        overlay.isHidden = true
        overlay.container.pageView = nil
    }

    /// The card's rect: Peek covers the content area (the page card, a split's
    /// panes together: spec §D "Peek from a pane overlays the whole content area"), not the sidebar.
    func layout() {
        guard let rootView, !overlay.isHidden else { return }
        overlay.frame = rootView.currentLayout.card
        // The page behind keeps its scale about its new centre.
        if isShown { fadeBackground(to: PeekMetrics.backgroundAlpha, animated: false) }
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

    /// Grows from the click (the engine reports no link rect) over `Motion.slow`;
    /// the buttons fade in. Reduce Motion: a fade.
    private func animateOpen() {
        guard let layer = overlay.card.layer else { return }
        overlay.layoutSubtreeIfNeeded()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let variant = CardMotion.peekOpen.variant
        guard variant != .instant else { return }
        fade.duration = variant == .full ? Motion.fast : Motion.medium
        overlay.buttons.layer?.add(fade, forKey: "peek-open")
        if variant == .crossfade {
            layer.add(fade, forKey: "peek-open")
            return
        }
        let frame = overlay.card.frame
        let click = recentClick().map { overlay.convert($0, from: rootView) } ?? CGPoint(x: frame.midX, y: frame.midY)
        lastOpenOrigin = click
        let scale = PeekMetrics.openStartScale
        // In the card layer's superlayer space (5.13: the view-space offset had the wrong sign there,
        // so a click low on the page grew the card from the top): the click converted into it, and the
        // small card (scaled about the layer's anchor) moved so its centre sits on the click.
        let superlayerClick = overlay.convertToLayer(click)
        let size = layer.bounds.size
        let scaledOrigin = CGPoint(x: layer.position.x - layer.anchorPoint.x * size.width * scale,
                                   y: layer.position.y - layer.anchorPoint.y * size.height * scale)
        let dx = superlayerClick.x - scaledOrigin.x - size.width * scale / 2
        let dy = superlayerClick.y - scaledOrigin.y - size.height * scale / 2
        lastOpenStart = CGRect(x: scaledOrigin.x + dx, y: scaledOrigin.y + dy, width: size.width * scale, height: size.height * scale)
        lastOpenClickInLayer = superlayerClick
        let start = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(dx, dy, 0))
        let grow = CASpringAnimation(perceptualDuration: Motion.slow, bounce: 0)
        grow.keyPath = "transform"
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = grow.settlingDuration
        layer.add(grow, forKey: "peek-open")
        layer.add(fade, forKey: "peek-open-fade")
    }

    /// Spikes: where the last open animation started (overlay coordinates), the start rect and the
    /// click in the card layer's superlayer space.
    private(set) var lastOpenOrigin: CGPoint?
    private(set) var lastOpenStart: CGRect?
    private(set) var lastOpenClickInLayer: CGPoint?

    /// The header's domain and the card's fill follow the page.
    private func trackHeader(_ contents: any WebContents) {
        let (url, title, background) = withObservationTracking {
            (contents.url, contents.title, contents.rootBackgroundColor)
        } onChange: { [weakSelf = MainActorWeak(self), id = ObjectIdentifier(contents)] in
            Task { @MainActor in
                guard let self = weakSelf.value, let current = self.contents, ObjectIdentifier(current) == id else { return }
                self.trackHeader(current)
            }
        }
        overlay.header.set(host: url?.host() ?? url?.absoluteString ?? "", title: title)
        // VoiceOver: "Peek: <title>" (5.3a).
        overlay.setAccessibilityLabel("Peek: " + (title.flatMap { $0.isEmpty ? nil : $0 } ?? url?.host() ?? "page"))
        // As the page card: the fill (and the header on it) follows the page's root background.
        overlay.card.backgroundColor = background ?? Palette.cardBackground
        // Its text and buttons read on that fill, whatever the window's appearance.
        overlay.header.appearance = NSAppearance.reading(on: background)
    }
}

/// Peek's overlay over the content area: a clear backdrop (a click on it closes Peek), the card
/// and the buttons beside it.
final class PeekOverlayView: NSView {
    let dim = PeekDimView()
    let card = CardView()
    let header = PeekHeaderView()
    let buttons = PeekButtonsView()
    let container = PageContainerView()
    var onDimClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("peek")
        // One group over the page (5.3a): its buttons and the peeked page inside; Esc closes it.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Peek")
        setAccessibilityHelp("Esc closes it")
        wantsLayer = true
        dim.onClick = { [weak self] in self?.onDimClick?() }
        card.cornerRadius = PeekMetrics.cornerRadius
        card.isElevated = true
        card.topAccessory = header
        card.contentView = container
        card.setAccessibilityIdentifier("peek-card")
        addSubview(dim)
        addSubview(card)
        addSubview(buttons)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The card: nearly the full height, centred, its sides leaving room for the buttons (5.13).
    static func cardFrame(in bounds: CGRect) -> CGRect {
        let column = PeekMetrics.buttonInset + PeekMetrics.buttonSize + PeekMetrics.buttonInset
        let side = max(column, (bounds.width * PeekMetrics.sideFraction).rounded())
        let inset = PeekMetrics.verticalInset
        return CGRect(x: bounds.minX + side, y: bounds.minY + inset, width: max(0, bounds.width - 2 * side), height: max(0, bounds.height - 2 * inset))
    }

    override func layout() {
        super.layout()
        dim.frame = bounds
        card.frame = Self.cardFrame(in: bounds)
        let size = buttons.fittingSize
        buttons.frame = NSRect(x: card.frame.maxX + PeekMetrics.buttonInset, y: card.frame.minY, width: size.width, height: size.height)
    }

    /// Everything under the overlay is the backdrop's, the card's or a button's: nothing reaches the page below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return super.hitTest(point) ?? dim
    }
}

/// Clear over the content area (5.13: the page behind fades instead of a dark layer); a click closes Peek.
final class PeekDimView: NSView, AccessibilityBackdrop {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
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

/// Peek's header (5.13): the page's domain, centred and quiet; the title is its tooltip.
final class PeekHeaderView: NSView {
    private let domain = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        domain.font = Typography.secondary
        domain.textColor = .secondaryLabelColor
        domain.alignment = .center
        domain.lineBreakMode = .byTruncatingMiddle
        domain.setAccessibilityIdentifier("peek-domain")
        domain.hideFromAccessibility()
        addSubview(domain)
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
        Palette.hairline.setFill()
        let line = Hairline.width(in: self)
        NSRect(x: 0, y: bounds.height - line, width: bounds.width, height: line).fill()
    }

    override func layout() {
        super.layout()
        let height = domain.cell?.cellSize.height ?? 16
        let padding = Spacing.l
        domain.frame = NSRect(x: padding, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * padding), height: height)
    }
}

/// Close, Open as Tab and Split beside the card's top-right corner, as AppKit's glass circles (5.13).
final class PeekButtonsView: NSView {
    var onExpand: (() -> Void)?
    var onSplit: (() -> Void)?
    var onClose: (() -> Void)?
    private let close = PeekButtonsView.button(.closeTab, "Close (Esc)")
    private let expand = PeekButtonsView.button(.peekExpand, "Open as Tab (⌘O)")
    let split = PeekButtonsView.button(.peekSplit, "Open in Split View (⇧⌘O)")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        expand.target = self
        expand.action = #selector(expandClicked)
        expand.setAccessibilityIdentifier("peek-open-as-tab")
        split.target = self
        split.action = #selector(splitClicked)
        split.setAccessibilityIdentifier("peek-split")
        close.target = self
        close.action = #selector(closeClicked)
        close.setAccessibilityIdentifier("peek-close")
        [close, expand, split].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var fittingSize: NSSize {
        NSSize(width: PeekMetrics.buttonSize, height: 3 * PeekMetrics.buttonSize + 2 * PeekMetrics.buttonGap)
    }

    override func layout() {
        super.layout()
        let size = PeekMetrics.buttonSize
        for (index, button) in [close, expand, split].enumerated() {
            button.frame = NSRect(x: 0, y: CGFloat(index) * (size + PeekMetrics.buttonGap), width: size, height: size)
        }
    }

    @objc private func expandClicked() { onExpand?() }
    @objc private func splitClicked() { onSplit?() }
    @objc private func closeClicked() { onClose?() }

    private static func button(_ symbol: Symbol, _ tip: String) -> NSButton {
        let button = HoverButton()
        button.image = symbol.image(.control, accessibilityDescription: tip)
        button.makeGlass()
        button.setTip(tip)
        return button
    }
}
