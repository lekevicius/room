import AppKit
import Card
import Design
import Engine
import Model
import Observation
import Sidebar
import Tabs

/// The card's content (spec §D): one pane, or a split of up to four, each a
/// `SplitPaneView` with its own page container (tools, prompts, DevTools).
/// In a split each pane is a card of its own (B-113, 5.2a: the card's corner,
/// hairline border and shadow) with `SplitMetrics.paneGap` between them and a
/// resizer over each gap (double-click equalises); the page card itself then
/// draws nothing (`CardView.isSplitHost`). While a sidebar entry is dragged,
/// the drop overlay shows where it would land.
final class SplitView: NSView {
    private(set) var panes: [SplitPaneView] = []
    private(set) var focusedPane: SplitPaneView
    private(set) var presentation: SplitPresentation?
    /// Sizes while a resizer is dragged (committed to the store on release).
    private var liveRatios: [Double]?
    /// The divider being dragged rests on its equal point (one tick on arrival).
    private var isSnapped = false
    private var resizers: [SplitResizerView] = []
    /// Each pane's card shadow, under the panes (B-113).
    private var shadows: [CALayer] = []
    let dropOverlay = SplitDropOverlayView()
    /// Content from other apps dropped on the card (5.5b): the page first, Room for what it refuses.
    let contentDrop = CardDropView()
    /// The page in element fullscreen fills the card alone (B-35).
    var fullscreenContents: (any WebContents)? { didSet { needsLayout = true } }

    /// A pane container was made (the app hooks its tool layer).
    var onNewPane: ((SplitPaneView) -> Void)?
    /// A resizer was released (or double-clicked): the split's new sizes.
    var onRatios: ((UUID, [Double]) -> Void)?
    /// Pane header: × (closes that pane), the layout menu, the grip's move.
    var onClosePane: ((UUID) -> Void)?
    var onLayoutMenu: ((UUID, NSView) -> Void)?
    var onMovePane: ((UUID, Int, Int) -> Void)?

    override init(frame: NSRect) {
        focusedPane = SplitPaneView()
        super.init(frame: frame)
        wantsLayer = true
        panes = [focusedPane]
        addSubview(focusedPane)
        dropOverlay.isHidden = true
        addSubview(contentDrop)
        addSubview(dropOverlay)
        contentDrop.roots = { [weak self] in self?.panes ?? [] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var isSplit: Bool { presentation != nil }

    /// The pane showing `entry`.
    func pane(for entry: UUID) -> SplitPaneView? { panes.first { $0.entry == entry } }

    // MARK: Panes

    /// Shows `split` (or one page, `nil`) with `focused` in the focused pane.
    /// A pane keeps its view while its entry (or page) stays, so pages are
    /// not moved between containers when the split changes.
    func apply(_ split: SplitPresentation?, focused: (any WebContents)?) {
        if presentation?.group != split?.group || presentation?.layout != split?.layout { liveRatios = nil }
        presentation = split
        var wanted: [(entry: UUID?, contents: (any WebContents)?)] = []
        if let split {
            wanted = split.panes.map { ($0.entry, $0.entry == split.focused ? focused : $0.contents) }
        } else {
            wanted = [(nil, focused)]
        }
        var available = panes
        var chosen: [SplitPaneView?] = Array(repeating: nil, count: wanted.count)
        func take(_ index: Int, _ match: (SplitPaneView) -> Bool) {
            guard chosen[index] == nil, let found = available.firstIndex(where: match) else { return }
            chosen[index] = available.remove(at: found)
        }
        // The pane already showing the page, then the one already showing the entry, then any.
        for (index, item) in wanted.enumerated() {
            if let contents = item.contents { take(index) { $0.container.pageView === contents.nativeView } }
        }
        for (index, item) in wanted.enumerated() where item.entry != nil { take(index) { $0.entry == item.entry } }
        for index in wanted.indices where chosen[index] == nil {
            if !available.isEmpty {
                chosen[index] = available.removeFirst()
            } else {
                let pane = SplitPaneView()
                wire(pane)
                onNewPane?(pane)
                chosen[index] = pane
            }
        }
        for pane in available {
            pane.container.pageView = nil
            pane.removeFromSuperview()
        }
        panes = chosen.compactMap { $0 }
        for (pane, item) in zip(panes, wanted) {
            if pane.superview !== self { addSubview(pane, positioned: .below, relativeTo: contentDrop) }
            pane.entry = item.entry
            pane.show(item.contents)
            pane.isInSplit = split != nil
        }
        focusedPane = split.flatMap { pane(for: $0.focused) } ?? panes[0]
        for pane in panes { pane.isFocused = split != nil && pane === focusedPane }
        rebuildDividers()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func wire(_ pane: SplitPaneView) {
        pane.header.onClose = { [weak self, weak pane] in
            guard let entry = pane?.entry else { return }
            self?.onClosePane?(entry)
        }
        pane.header.onLayout = { [weak self, weak pane] button in
            guard let entry = pane?.entry else { return }
            self?.onLayoutMenu?(entry, button)
        }
        pane.header.onGripDrag = { [weak self, weak pane] point, ended in
            guard let self, let pane else { return }
            gripDragged(pane, to: convert(point, from: nil), ended: ended)
        }
    }

    // MARK: Layout

    private var layoutKind: SplitGeometry.Layout {
        switch presentation?.layout {
        case .vbox: .vbox
        case .grid: .grid
        default: .hbox
        }
    }

    private var ratios: [Double] { liveRatios ?? presentation?.ratios ?? [1] }

    var paneFrames: [CGRect] {
        SplitGeometry.frames(in: bounds, layout: layoutKind, count: panes.count, ratios: ratios)
    }

    override func layout() {
        super.layout()
        if let fullscreen = fullscreenContents, let pane = panes.first(where: { $0.container.pageView === fullscreen.nativeView }) {
            for other in panes { other.isHidden = other !== pane }
            pane.isCard = false
            pane.frame = bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for shadow in shadows { shadow.isHidden = true }
            CATransaction.commit()
            for resizer in resizers { resizer.isHidden = true }
            dropOverlay.frame = bounds
            contentDrop.frame = bounds
            return
        }
        let frames = paneFrames
        for (pane, frame) in zip(panes, frames) {
            pane.isHidden = false
            pane.isCard = isSplit
            pane.frame = frame
        }
        let dividers = SplitGeometry.dividers(in: bounds, layout: layoutKind, count: panes.count, ratios: ratios)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, divider) in dividers.enumerated() where index < resizers.count {
            resizers[index].isHidden = false
            resizers[index].divider = divider
            resizers[index].frame = divider.hit
        }
        layoutShadows(isSplit ? frames : [])
        CATransaction.commit()
        dropOverlay.frame = bounds
        contentDrop.frame = bounds
    }

    /// One card shadow under each pane of a split (B-113: the page card's `CardMetrics` shadow).
    private func layoutShadows(_ frames: [CGRect]) {
        while shadows.count < frames.count {
            let shadow = CALayer()
            shadow.actions = CALayer.noImplicitActions
            layer?.insertSublayer(shadow, at: 0)
            shadows.append(shadow)
        }
        let dark = effectiveAppearance.isDark
        var color: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { color = Palette.cardShadow.cgColor }
        for (index, shadow) in shadows.enumerated() {
            guard index < frames.count else {
                shadow.isHidden = true
                continue
            }
            let frame = frames[index]
            shadow.isHidden = false
            shadow.frame = frame
            shadow.shadowColor = color
            shadow.shadowOpacity = dark ? CardMetrics.shadowOpacityDark : CardMetrics.shadowOpacityLight
            shadow.shadowRadius = CardMetrics.shadowRadius
            // This view is flipped: the card's shadow falls down the screen as the page card's does.
            shadow.shadowOffset = CGSize(width: CardMetrics.shadowOffset.width, height: -CardMetrics.shadowOffset.height)
            let radius = min(CardMetrics.cornerRadius, frame.width / 2, frame.height / 2)
            shadow.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
    }

    private func rebuildDividers() {
        let count = SplitGeometry.dividers(in: bounds, layout: layoutKind, count: panes.count, ratios: ratios).count
        while resizers.count < count {
            let resizer = SplitResizerView()
            resizer.onDrag = { [weak self] divider, point in self?.resizerDragged(divider, to: point) }
            resizer.onEnd = { [weak self] in self?.commitRatios() }
            resizer.onReset = { [weak self] in self?.equalise() }
            addSubview(resizer, positioned: .below, relativeTo: dropOverlay)
            resizers.append(resizer)
        }
        for index in count..<resizers.count { resizers[index].isHidden = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    // MARK: Resizers (spec §D: double-click equalises; B-113: over the gap between the cards)

    private func resizerDragged(_ divider: SplitGeometry.Divider, to point: CGPoint) {
        guard isSplit else { return }
        let pointer = divider.axis == .vertical ? point.x : point.y
        // The equal point is an alignment point: the divider snaps to it with a haptic tick (5.5 task 6).
        let snap = SplitGeometry.snap(pointer, dragging: divider, in: bounds, layout: layoutKind, count: panes.count, ratios: ratios)
        if snap.snapped, !isSnapped { Haptics.alignment() }
        isSnapped = snap.snapped
        liveRatios = SplitGeometry.ratios(dragging: divider, to: snap.position, in: bounds, layout: layoutKind, count: panes.count, ratios: ratios)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    #if DEBUG
    /// Spikes (5.5b): the first divider dragged to `position` along its axis (split view coordinates); the live ratios.
    func debugDragDivider(to position: CGFloat) -> [Double]? {
        guard let divider = SplitGeometry.dividers(in: bounds, layout: layoutKind, count: panes.count, ratios: ratios).first else { return nil }
        resizerDragged(divider, to: divider.axis == .vertical ? CGPoint(x: position, y: bounds.midY) : CGPoint(x: bounds.midX, y: position))
        return liveRatios
    }

    func debugEndDividerDrag() { commitRatios() }
    #endif

    private func commitRatios() {
        isSnapped = false
        guard let presentation, let liveRatios else { return }
        onRatios?(presentation.group, liveRatios)
    }

    private func equalise() {
        guard let presentation else { return }
        liveRatios = SplitRules.equalRatios(layout: presentation.layout, count: panes.count)
        needsLayout = true
        commitRatios()
    }

    // MARK: The grip (reorder panes by dragging the header)

    private var gripTarget: Int?

    private func gripDragged(_ pane: SplitPaneView, to point: CGPoint, ended: Bool) {
        guard let presentation, let from = panes.firstIndex(where: { $0 === pane }) else { return }
        let target = paneFrames.firstIndex { $0.contains(point) }
        for (index, other) in panes.enumerated() { other.isDropHighlighted = !ended && index == target && index != from }
        guard ended else { return }
        if let target, target != from { onMovePane?(presentation.group, from, target) }
    }
}

/// One pane: the page's container, its fill following the page's root
/// background, and (in a split) the header that shows on hover at its top.
final class SplitPaneView: NSView, DisplayOptionsObserving {
    let container = PageContainerView()
    let header = PaneHeaderView()
    /// The pane's entry in a split (`nil` for the single page).
    var entry: UUID?
    private(set) weak var contents: (any WebContents)?
    var isInSplit = false { didSet { if !isInSplit { setHeaderShown(false, animated: false) } } }
    /// A card of its own (B-113): the page card's corner and hairline border, clipped; its shadow is the split's.
    var isCard = false {
        didSet { if isCard != oldValue { applyCardStyle() } }
    }
    var isFocused = false
    var isDropHighlighted = false { didSet { highlight.isHidden = !isDropHighlighted } }
    private let highlight = CALayer()
    private var hideHeader: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("split-pane")
        container.frame = bounds
        container.autoresizingMask = [.width, .height]
        addSubview(container)
        header.isHidden = true
        addSubview(header)
        highlight.isHidden = true
        highlight.actions = CALayer.noImplicitActions
        highlight.borderWidth = 2
        layer?.addSublayer(highlight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // VoiceOver (5.3a): in a split, each pane is a group named by its page; the focused one says so.
    override func isAccessibilityElement() -> Bool { isInSplit }
    override func accessibilityRole() -> NSAccessibility.Role? { isInSplit ? .group : super.accessibilityRole() }
    override func accessibilityLabel() -> String? {
        guard isInSplit else { return nil }
        return "Split pane: " + (contents?.title.flatMap { $0.isEmpty ? nil : $0 } ?? contents?.url?.host() ?? "New Tab")
    }
    override func accessibilityValue() -> Any? { isInSplit && isFocused ? "focused" : nil }

    func show(_ contents: (any WebContents)?) {
        let changed = contents !== self.contents || container.pageView == nil
        self.contents = contents
        guard changed else { return }
        container.pageView = contents?.nativeView ?? container.emptyState
        trackPage()
    }

    /// The pane's fill (so resizing never shows the window material) and the header's domain follow its page.
    private func trackPage() {
        let (background, url) = withObservationTracking {
            (contents?.rootBackgroundColor, contents?.url)
        } onChange: { [weakSelf = MainActorWeak(self), id = contents.map(ObjectIdentifier.init)] in
            Task { @MainActor in
                guard let self = weakSelf.value, self.contents.map(ObjectIdentifier.init) == id else { return }
                self.trackPage()
            }
        }
        layer?.backgroundColor = (background ?? Palette.cardBackground).cgColor
        header.set(host: url?.host() ?? url?.absoluteString ?? "New Tab")
        header.appearance = NSAppearance.reading(on: background)
    }

    /// Increase Contrast (5.3b): the pane card's border is `Palette.cardBorder`'s high-contrast hairline.
    func displayOptionsDidChange() { applyCardStyle() }

    private func applyCardStyle() {
        guard let layer else { return }
        layer.cornerRadius = isCard ? CardMetrics.cornerRadius : 0
        layer.cornerCurve = .continuous
        layer.masksToBounds = isCard
        layer.borderWidth = isCard ? CardMetrics.borderWidth * Hairline.width(in: self) : 0
        effectiveAppearance.performAsCurrentDrawingAppearance { layer.borderColor = Palette.cardBorder.cgColor }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardStyle()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyCardStyle()
    }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: SplitMetrics.paneHeaderHeight)
        highlight.frame = bounds
        highlight.borderColor = NSColor.controlAccentColor.cgColor
        highlight.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(SplitMetrics.dropPreviewAlpha).cgColor
    }

    // MARK: The header on hover (spec §D)

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        pointerMoved(to: nil)
    }

    /// Shows the header while the pointer is near the pane's top; hides it a little after it leaves.
    func pointerMoved(to point: CGPoint?) {
        guard isInSplit else { return }
        if let point, bounds.contains(point), point.y <= SplitMetrics.paneHeaderRevealBand {
            hideHeader?.cancel()
            hideHeader = nil
            setHeaderShown(true, animated: true)
        } else if !header.isHidden, hideHeader == nil, !header.isTracking {
            let work = DispatchWorkItem { [weak self] in
                self?.hideHeader = nil
                self?.setHeaderShown(false, animated: true)
            }
            hideHeader = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Timing.paneHeaderHideDelay, execute: work)
        }
    }

    func setHeaderShown(_ shown: Bool, animated: Bool) {
        guard header.isHidden == shown else { return }
        header.isHidden = false
        let fade = { (alpha: CGFloat) in
            if animated, CardMotion.paneHeader.animates {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.fast
                    self.header.animator().alphaValue = alpha
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated { if alpha == 0 { self?.header.isHidden = true } }
                })
            } else {
                self.header.alphaValue = alpha
                self.header.isHidden = alpha == 0
            }
        }
        fade(shown ? 1 : 0)
    }
}

/// A pane's header (spec §D): the pane's domain, a grip to reorder panes,
/// the layout menu and ×, 24 pt over the top of the page.
final class PaneHeaderView: NSVisualEffectView {
    var onClose: (() -> Void)?
    var onLayout: ((NSView) -> Void)?
    /// The grip moved (window coordinates); `ended` on release.
    var onGripDrag: ((CGPoint, Bool) -> Void)?
    private let grip = PaneGripView()
    private let domain = NSTextField(labelWithString: "")
    private let layoutButton = PaneHeaderView.button(.paneLayout, "Split Layout")
    private let close = PaneHeaderView.button(.closeTab, "Close Pane (⌘W)")
    var isTracking: Bool { grip.isDragging }

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow
        state = .active
        // Reduce Transparency (5.3b): an opaque fill in place of the header material.
        let solid = SolidBackingView(cornerRadius: 0)
        solid.frame = bounds
        addSubview(solid)
        setAccessibilityIdentifier("pane-header")
        domain.font = Typography.secondary
        domain.textColor = .secondaryLabelColor
        domain.lineBreakMode = .byTruncatingMiddle
        grip.onDrag = { [weak self] point, ended in self?.onGripDrag?(point, ended) }
        layoutButton.target = self
        layoutButton.action = #selector(layoutClicked)
        close.target = self
        close.action = #selector(closeClicked)
        close.setAccessibilityIdentifier("pane-close")
        [grip, domain, layoutButton, close].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func set(host: String) { domain.stringValue = host }

    override func layout() {
        super.layout()
        let size = SplitMetrics.paneHeaderButtonSize, y = ((bounds.height - size) / 2).rounded()
        grip.frame = NSRect(x: Spacing.xs, y: y, width: size, height: size)
        close.frame = NSRect(x: bounds.width - Spacing.xs - size, y: y, width: size, height: size)
        layoutButton.frame = close.frame.offsetBy(dx: -size, dy: 0)
        let height = ceil(domain.cell?.cellSize.height ?? 14)
        domain.frame = NSRect(x: grip.frame.maxX + Spacing.xs, y: ((bounds.height - height) / 2).rounded(),
                              width: max(0, layoutButton.frame.minX - grip.frame.maxX - 2 * Spacing.xs), height: height)
    }

    @objc private func closeClicked() { onClose?() }
    @objc private func layoutClicked() { onLayout?(layoutButton) }

    private static func button(_ symbol: Symbol, _ tip: String) -> NSButton {
        let button = HoverButton()
        button.image = symbol.image(.paneControl, accessibilityDescription: tip)
        button.contentTintColor = .secondaryLabelColor
        button.setTip(tip)
        return button
    }
}

/// Drag it onto another pane to swap places (spec §D "drag grip").
final class PaneGripView: NSImageView {
    var onDrag: ((CGPoint, Bool) -> Void)?
    private(set) var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        image = Symbol.paneGrip.image(.paneControl, accessibilityDescription: "Move Pane")
        contentTintColor = .tertiaryLabelColor
        toolTip = "Drag to move the pane"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { isDragging = true }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.closedHand.set()
        onDrag?(event.locationInWindow, false)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onDrag?(event.locationInWindow, true)
    }
}

/// The 7 pt hit area on a line between panes: drag to resize, double-click for equal sizes.
final class SplitResizerView: NSView {
    var divider: SplitGeometry.Divider? {
        didSet { setAccessibilityOrientation(divider?.axis == .horizontal ? .horizontal : .vertical) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // VoiceOver's splitter between two panes (5.3a); a drag or a double-click resizes (equal sizes: ⌥⌘G's layout menu).
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Split divider")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func accessibilityPerformPress() -> Bool {
        onReset?()
        return true
    }
    /// The pointer in the split view's coordinates.
    var onDrag: ((SplitGeometry.Divider, CGPoint) -> Void)?
    var onEnd: (() -> Void)?
    var onReset: (() -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: divider?.axis == .horizontal ? .resizeUpDown : .resizeLeftRight)
    }

    override var frame: NSRect { didSet { if frame.size != oldValue.size { window?.invalidateCursorRects(for: self) } } }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let divider, let split = superview else { return }
        onDrag?(divider, split.convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount < 2 { onEnd?() }
    }
}

/// Over the card while a sidebar entry is dragged (spec §D drop zones):
/// the pane under the pointer shows where the entry would go, an edge
/// (split to that side) or its centre (replace).
final class SplitDropOverlayView: NSView {
    /// The pane frames (split view coordinates) and their entries; one frame and `nil` for a single page.
    var panes: () -> [(frame: CGRect, entry: UUID?)] = { [] }
    /// A drop: the dragged entry, the pane it landed on, the zone.
    var onDrop: ((UUID, UUID?, SplitGeometry.DropZone) -> Void)?
    private let preview = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.isHidden = true
        // Only its frame moves (`CardMotion.dropPreview`), in the drag's own transaction.
        preview.actions = ["hidden": NSNull(), "backgroundColor": NSNull(), "borderColor": NSNull(), "opacity": NSNull()]
        preview.borderWidth = 2
        preview.cornerRadius = Radius.medium
        preview.cornerCurve = .continuous
        layer?.addSublayer(preview)
        registerForDraggedTypes([SidebarDragTypes.entry])
        setAccessibilityIdentifier("split-drop-overlay")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func target(_ info: any NSDraggingInfo) -> (entry: UUID?, zone: SplitGeometry.DropZone, frame: CGRect)? {
        let point = convert(info.draggingLocation, from: nil)
        guard let pane = panes().first(where: { $0.frame.contains(point) }),
              let zone = SplitGeometry.dropZone(at: point, in: pane.frame) else { return nil }
        return (pane.entry, zone, SplitGeometry.dropPreview(zone, in: pane.frame))
    }

    /// One sidebar entry (a split's row, which carries its panes, is not taken).
    private func draggedEntry(_ info: any NSDraggingInfo) -> UUID? {
        let items = info.draggingPasteboard.pasteboardItems ?? []
        guard items.count == 1, items[0].string(forType: SidebarDragTypes.splitPanes) == nil else { return nil }
        return items[0].string(forType: SidebarDragTypes.entry).flatMap(UUID.init(uuidString:))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard draggedEntry(sender) != nil, let target = target(sender) else {
            preview.isHidden = true
            return []
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.fast)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setDisableActions(!CardMotion.dropPreview.animates)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            preview.borderColor = NSColor.controlAccentColor.cgColor
            preview.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(SplitMetrics.dropPreviewAlpha).cgColor
        }
        preview.frame = target.frame.insetBy(dx: Spacing.xs, dy: Spacing.xs)
        preview.isHidden = false
        CATransaction.commit()
        return .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { preview.isHidden = true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        preview.isHidden = true
        guard let id = draggedEntry(sender), let target = target(sender) else { return false }
        onDrop?(id, target.entry, target.zone)
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { preview.isHidden = true }
}
