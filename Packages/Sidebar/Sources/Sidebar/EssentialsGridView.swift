import AppKit
import Design
import Model

/// What a tile reports back (clicks, menus, the start of a drag).
protocol EssentialTileEvents: AnyObject {
    func tileClicked(_ entry: UUID, gesture: ClickRules.Gesture)
    func tileResetClicked(_ entry: UUID)
    func tileMenu(_ entry: UUID) -> NSMenu?
    func tileDragStarted(_ entry: UUID, event: NSEvent)
}

/// Drags over the grid (spec §A.9).
protocol EssentialsDropEvents: AnyObject {
    func gridDragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation
    func gridPerformDrop(_ info: any NSDraggingInfo) -> Bool
    func gridDragExited()
}

/// Layout of the Essentials grid (spec §I.2): tiles `essentialTileHeight`
/// tall that stretch to fill their row. The column count is as many as fit
/// at `essentialTileMinWidth`, at most `essentialMaxColumns`, never more
/// than there are tiles; the rows that count needs are then filled evenly,
/// left to right, so no row is shorter than another by more than one (five
/// tiles in four columns are 3 + 2, never 4 + 1; ROADMAP 2.2 review).
public enum EssentialsLayout {
    public static func columns(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let gap = SidebarMetrics.essentialsGap
        let fit = Int(((width + gap) / (SidebarMetrics.essentialTileMinWidth + gap)).rounded(.down))
        return max(1, min(fit, SidebarMetrics.essentialMaxColumns, count))
    }

    /// Tiles per row, top to bottom.
    public static func rowCounts(count: Int, width: CGFloat) -> [Int] {
        let columns = columns(count: count, width: width)
        guard columns > 0 else { return [] }
        let rows = (count + columns - 1) / columns
        let base = count / rows, longer = count % rows
        return (0..<rows).map { $0 < longer ? base + 1 : base }
    }

    public static func frames(count: Int, width: CGFloat) -> [CGRect] {
        let gap = SidebarMetrics.essentialsGap
        let height = SidebarMetrics.essentialTileHeight
        var frames: [CGRect] = []
        for (row, tiles) in rowCounts(count: count, width: width).enumerated() {
            let tileWidth = (width - gap * CGFloat(tiles - 1)) / CGFloat(tiles)
            for column in 0..<tiles {
                frames.append(CGRect(x: (CGFloat(column) * (tileWidth + gap)).rounded(), y: CGFloat(row) * (height + gap),
                                     width: tileWidth.rounded(), height: height))
            }
        }
        return frames
    }

    public static func height(count: Int, width: CGFloat) -> CGFloat {
        frames(count: count, width: width).last?.maxY ?? 0
    }
}

/// The Essentials grid above the space title (≤ 12 tiles per profile). It
/// takes drops: a vertical insertion line between tiles; over a full grid
/// a "12/12" badge, and a shake when the drop is refused (spec §A.9); with
/// no essentials, a dashed drop slot while a sidebar drag is in progress
/// (spec §I.15).
final class EssentialsGridView: NSView {
    weak var events: EssentialTileEvents?
    weak var dropEvents: EssentialsDropEvents?
    private(set) var tiles: [UUID: EssentialTileView] = [:]
    private(set) var order: [UUID] = []
    private let insertionLine = DropIndicatorView()
    private let fullBadge = NSTextField(labelWithString: "")
    private let dropSlot = EssentialsDropSlotView()

    /// Shows the empty grid's drop slot (only while a sidebar drag is in progress).
    var showsDropSlot = false {
        didSet {
            guard showsDropSlot != oldValue else { return }
            dropSlot.isHidden = !(showsDropSlot && order.isEmpty)
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        fullBadge.font = Typography.badgeLarge
        fullBadge.textColor = .white
        fullBadge.alignment = .center
        fullBadge.wantsLayer = true
        fullBadge.layer?.backgroundColor = NSColor.systemRed.cgColor
        fullBadge.layer?.cornerRadius = SidebarMetrics.fullBadgeHeight / 2
        fullBadge.isHidden = true
        fullBadge.setAccessibilityIdentifier("essentials-full")
        dropSlot.isHidden = true
        addSubview(dropSlot)
        addSubview(insertionLine)
        addSubview(fullBadge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    /// The next layout moves the tiles to their new places (`SidebarMotion.essentialsReflow`).
    private var reflowsAnimated = false

    func setEntries(_ ids: [UUID], animated: Bool) {
        let fades = animated && SidebarMotion.essentialFade.animates
        let removed = Set(order).subtracting(ids)
        for id in removed {
            guard let tile = tiles.removeValue(forKey: id) else { continue }
            if fades {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.standard
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    tile.animator().alphaValue = 0
                }, completionHandler: { MainActor.assumeIsolated { tile.removeFromSuperview() } })
            } else {
                tile.removeFromSuperview()
            }
        }
        for id in ids where tiles[id] == nil {
            let tile = EssentialTileView(entryID: id)
            tile.events = events
            tiles[id] = tile
            addSubview(tile, positioned: .below, relativeTo: insertionLine)
            if fades {
                tile.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.standard
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    tile.animator().alphaValue = 1
                }
            }
        }
        reflowsAnimated = animated && !order.isEmpty && order != ids && SidebarMotion.essentialsReflow.animates
        order = ids
        dropSlot.isHidden = !(showsDropSlot && order.isEmpty)
        needsLayout = true
    }

    func tile(for id: UUID) -> EssentialTileView? { tiles[id] }

    func height(forWidth width: CGFloat) -> CGFloat {
        if order.isEmpty { return showsDropSlot ? SidebarMetrics.essentialTileHeight : 0 }
        return EssentialsLayout.height(count: order.count, width: width)
    }

    var tileFrames: [CGRect] { EssentialsLayout.frames(count: order.count, width: bounds.width) }

    override func layout() {
        super.layout()
        // A reflow (a tile added, removed or moved): the tiles that were on
        // screen move to their places with the rows' timing; a new tile
        // starts at its own (it fades in there).
        let animated = reflowsAnimated && window != nil
        reflowsAnimated = false
        var moves: [(EssentialTileView, CGRect)] = []
        for (id, frame) in zip(order, tileFrames) {
            guard let tile = tiles[id], tile.frame != frame else { continue }
            if animated, tile.frame != .zero { moves.append((tile, frame)) } else { tile.frame = frame }
        }
        if !moves.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.standard
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for (tile, frame) in moves { tile.animator().frame = frame }
            }
        }
        dropSlot.frame = NSRect(x: 0, y: 0, width: bounds.width, height: SidebarMetrics.essentialTileHeight)
        let size = fullBadge.cell?.cellSize ?? .zero
        let badgeWidth = ceil(size.width) + 2 * Spacing.xs
        fullBadge.frame = NSRect(x: bounds.width - badgeWidth, y: 0, width: badgeWidth, height: SidebarMetrics.fullBadgeHeight)
    }

    // MARK: Drop feedback

    /// The insertion line beside tile `tile` (after it if `after`); `nil` hides it.
    func showInsertion(_ drop: DropRules.GridDrop?) {
        let frames = tileFrames
        guard let drop, frames.indices.contains(drop.tile) else {
            insertionLine.isHidden = true
            return
        }
        let gap = SidebarMetrics.essentialsGap
        let width = SidebarMetrics.insertionLineWidth
        let tile = frames[drop.tile]
        let x = drop.after ? tile.maxX + gap / 2 : tile.minX - gap / 2
        insertionLine.frame = NSRect(x: min(max(x - width / 2, 0), bounds.width - width), y: tile.minY, width: width, height: tile.height)
        insertionLine.isHidden = false
    }

    /// The "12/12" badge over a full grid (`nil` hides it).
    func showFullBadge(_ text: String?) {
        fullBadge.stringValue = text ?? ""
        fullBadge.isHidden = text == nil
        needsLayout = true
    }

    /// The refused-drop shake (spec §A.9); a flash under Reduce Motion.
    func shake() {
        wantsLayer = true
        guard let layer else { return }
        if SidebarMotion.refusedDrop.variant == .crossfade {
            let flash = CABasicAnimation(keyPath: "opacity")
            flash.fromValue = 0.4
            flash.toValue = 1
            flash.duration = Motion.slow
            layer.add(flash, forKey: "refused")
            return
        }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let distance = SidebarMetrics.shakeDistance
        shake.values = [0, -distance, distance, -distance * 0.6, distance * 0.6, -distance * 0.3, 0]
        shake.duration = Motion.shake
        layer.add(shake, forKey: "refused")
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropEvents?.gridDragUpdated(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropEvents?.gridDragUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropEvents?.gridDragExited()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropEvents?.gridPerformDrop(sender) ?? false
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dropEvents?.gridDragExited()
    }
}

/// The empty grid while dragging: "Drag a tab here to make it an Essential" (spec §I.15).
final class EssentialsDropSlotView: NSView {
    private let label = NSTextField(labelWithString: "Drag a tab here to make it an Essential")
    private let border = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        border.actions = CALayer.noImplicitActions
        border.fillColor = nil
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer?.addSublayer(border)
        label.font = Typography.secondary
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: SidebarMetrics.pillCornerRadius, cornerHeight: SidebarMetrics.pillCornerRadius,
                             transform: nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            border.strokeColor = NSColor.tertiaryLabelColor.cgColor
        }
        let height = ceil(label.cell?.cellSize.height ?? 14)
        label.frame = NSRect(x: Spacing.s, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * Spacing.s),
                             height: height)
    }
}

/// One Essential: the icon on the rows' hover fill (the Room Browser design,
/// 2026-10-07; spec §I.2 had the icon's dominant colour at 15%), the pill
/// fill when selected and half of it on hover, dimmed while unloaded, the
/// changed dot at the tile's corner and the reset icon on hover (§I.8).
final class EssentialTileView: NSView {
    let entryID: UUID
    weak var events: EssentialTileEvents?
    private let favicon = FaviconView()
    private let resetButton = NSButton()
    private let audio = NSImageView()
    private let dot = NSView()
    private let multiSelectionLayer = CALayer()
    private var hovering = false { didSet { if hovering != oldValue { update() } } }
    private var isSelected = false
    private var isChanged = false
    /// Configured once (its first state never fades).
    private var configured = false
    /// In the ⌘/⇧-click multi-selection (spec §A.9).
    var isMultiSelected = false { didSet { if isMultiSelected != oldValue { needsDisplay = true } } }
    private var mouseDownPoint: NSPoint?
    private var didDrag = false

    init(entryID: UUID) {
        self.entryID = entryID
        super.init(frame: .zero)
        wantsLayer = true
        // Resized with the tile without Core Animation's implicit 0.25 s animation (5.1a).
        multiSelectionLayer.actions = CALayer.noImplicitActions
        layer?.addSublayer(multiSelectionLayer)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("essential")
        resetButton.image = Symbol.resetPinned.image(.tileReset, accessibilityDescription: "Back to pinned URL")
        resetButton.isBordered = false
        resetButton.imagePosition = .imageOnly
        resetButton.contentTintColor = .labelColor
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        resetButton.toolTip = "Back to pinned URL"
        resetButton.isHidden = true
        audio.isHidden = true
        audio.contentTintColor = .secondaryLabelColor
        dot.wantsLayer = true
        dot.isHidden = true
        addSubview(favicon)
        addSubview(resetButton)
        addSubview(audio)
        addSubview(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func configure(entry: Entry, page: EntryPageState, isSelected: Bool, isChanged: Bool) {
        if configured, isChanged != self.isChanged, isChanged ? SidebarMotion.changedDot.animates : SidebarMotion.resetCrossfade.animates {
            // The dot fades in as the page leaves the pinned URL; on reset the tile crossfades back (spec §A.5, §I.8).
            layer?.add(EntryCellView.fade(isChanged ? Motion.fast : Motion.resetCrossfade), forKey: "changed")
        }
        configured = true
        self.isSelected = isSelected
        self.isChanged = isChanged
        favicon.image = page.favicon
        favicon.letterSource = EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry)
        favicon.isUnloaded = !page.isLoaded
        favicon.isLoading = page.isLoading
        let audible = page.isAudible || page.isMuted
        audio.isHidden = !audible
        audio.image = (page.isMuted ? Symbol.muted : Symbol.audible).image(.tileBadge)
        toolTip = EntryLabel.title(entry)
        setAccessibilityLabel(EntryLabel.title(entry))
        update()
    }

    private func update() {
        let showReset = hovering && isChanged
        if showReset == resetButton.isHidden, SidebarMotion.resetIconSwap.animates {
            // The favicon and the reset icon swap with the hover fill (spec §I.8; hover fades).
            layer?.add(EntryCellView.fade(Motion.fast), forKey: "hover-swap")
        }
        resetButton.isHidden = !showReset
        favicon.isHidden = !resetButton.isHidden
        dot.isHidden = !isChanged || hovering
        needsDisplay = true
        needsLayout = true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = SidebarMetrics.pillCornerRadius
        layer.cornerCurve = .continuous
        // A hovered tile is half the selection fill in place of its own (the design).
        let fill = isSelected ? Palette.sidebarSelection
            : hovering ? Palette.sidebarSelection.withAlphaComponent(SidebarMetrics.essentialHoverAlpha) : Palette.sidebarHover
        layer.backgroundColor = fill.cgColor
        layer.shadowColor = Palette.cardShadow.cgColor
        layer.shadowOpacity = isSelected ? SidebarMetrics.pillShadowOpacity(dark: effectiveAppearance.isDark) : 0
        layer.shadowRadius = SidebarMetrics.essentialShadowRadius
        layer.shadowOffset = SidebarMetrics.pillShadowOffset
        multiSelectionLayer.frame = layer.bounds
        multiSelectionLayer.cornerRadius = SidebarMetrics.pillCornerRadius
        multiSelectionLayer.cornerCurve = .continuous
        multiSelectionLayer.backgroundColor = Palette.sidebarMultiSelection.cgColor
        multiSelectionLayer.isHidden = !isMultiSelected
        dot.layer?.backgroundColor = Palette.accent.cgColor
        dot.layer?.cornerRadius = SidebarMetrics.changedDotSize / 2
    }

    override func layout() {
        super.layout()
        let size = SidebarMetrics.essentialIconSize
        let icon = NSRect(x: ((bounds.width - size) / 2).rounded(), y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        favicon.frame = icon
        resetButton.frame = icon.insetBy(dx: -Spacing.xs, dy: -Spacing.xs)
        let dotSize = SidebarMetrics.changedDotSize
        let inset = SidebarMetrics.tileBadgeInset, badge = SidebarMetrics.tileBadgeSize
        dot.frame = NSRect(x: bounds.maxX - dotSize - inset, y: bounds.maxY - dotSize - inset, width: dotSize, height: dotSize)
        audio.frame = NSRect(x: bounds.maxX - badge - inset, y: inset, width: badge, height: badge)
        multiSelectionLayer.frame = bounds
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !didDrag else { return }
        let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
        guard distance >= SidebarMetrics.dragThreshold else { return }
        didDrag = true
        events?.tileDragStarted(entryID, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        guard !didDrag, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let flags = event.modifierFlags
        let gesture: ClickRules.Gesture = flags.contains(.command) ? .command : flags.contains(.shift) ? .shift : .primary
        events?.tileClicked(entryID, gesture: gesture)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { events?.tileClicked(entryID, gesture: .middle) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { events?.tileMenu(entryID) }

    @objc private func resetClicked() { events?.tileResetClicked(entryID) }
}
