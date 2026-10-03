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
        fullBadge.font = .systemFont(ofSize: 10, weight: .semibold)
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

    func setEntries(_ ids: [UUID], animated: Bool) {
        let removed = Set(order).subtracting(ids)
        for id in removed {
            guard let tile = tiles.removeValue(forKey: id) else { continue }
            if animated, !Motion.reduceMotion {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Motion.standard
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
            if animated {
                tile.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.standard
                    tile.animator().alphaValue = 1
                }
            }
        }
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
        for (id, frame) in zip(order, tileFrames) {
            tiles[id]?.frame = frame
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
        if Motion.reduceMotion {
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
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: Radius.medium, cornerHeight: Radius.medium,
                             transform: nil)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            border.strokeColor = NSColor.tertiaryLabelColor.cgColor
        }
        let height = ceil(label.cell?.cellSize.height ?? 14)
        label.frame = NSRect(x: Spacing.s, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * Spacing.s),
                             height: height)
    }
}

/// One Essential: the icon at 20 pt on its dominant colour at 15% (spec §I.2),
/// the pill fill when selected, dimmed while unloaded, the changed dot at the
/// tile's corner and the reset icon on hover (§I.8).
final class EssentialTileView: NSView {
    let entryID: UUID
    weak var events: EssentialTileEvents?
    private let favicon = FaviconView()
    private let resetButton = NSButton()
    private let audio = NSImageView()
    private let dot = NSView()
    private let hoverLayer = CALayer()
    private var tint: NSColor?
    private var hovering = false { didSet { if hovering != oldValue { update() } } }
    private var isSelected = false
    private var isChanged = false
    /// In the ⌘/⇧-click multi-selection (spec §A.9).
    var isMultiSelected = false { didSet { if isMultiSelected != oldValue { needsDisplay = true } } }
    private var mouseDownPoint: NSPoint?
    private var didDrag = false

    init(entryID: UUID) {
        self.entryID = entryID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(hoverLayer)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("essential")
        resetButton.image = Symbol.resetPinned.image(pointSize: 13, weight: .medium, accessibilityDescription: "Back to pinned URL")
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
        self.isSelected = isSelected
        self.isChanged = isChanged
        favicon.image = page.favicon
        favicon.letterSource = EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry)
        favicon.isUnloaded = !page.isLoaded
        favicon.isLoading = page.isLoading
        tint = page.favicon.flatMap(Self.dominantColor) ?? Palette.letterTileColor(for: favicon.letterSource)
        let audible = page.isAudible || page.isMuted
        audio.isHidden = !audible
        audio.image = (page.isMuted ? Symbol.muted : Symbol.audible).image(pointSize: 8, weight: .semibold)
        toolTip = EntryLabel.title(entry)
        setAccessibilityLabel(EntryLabel.title(entry))
        update()
    }

    private func update() {
        resetButton.isHidden = !(hovering && isChanged)
        favicon.isHidden = !resetButton.isHidden
        dot.isHidden = !isChanged || hovering
        needsDisplay = true
        needsLayout = true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Radius.medium
        layer.cornerCurve = .continuous
        let fill: NSColor = isSelected
            ? Palette.sidebarSelection
            : (tint ?? .clear).withAlphaComponent(SidebarMetrics.essentialTintAlpha)
        layer.backgroundColor = fill.cgColor
        layer.shadowColor = Palette.cardShadow.cgColor
        layer.shadowOpacity = isSelected && !effectiveAppearance.isDark ? SidebarMetrics.pillShadowOpacity : 0
        layer.shadowRadius = SidebarMetrics.pillShadowRadius
        layer.shadowOffset = SidebarMetrics.pillShadowOffset
        hoverLayer.frame = layer.bounds
        hoverLayer.cornerRadius = Radius.medium
        hoverLayer.cornerCurve = .continuous
        hoverLayer.backgroundColor = (isMultiSelected ? Palette.sidebarMultiSelection : Palette.sidebarHover).cgColor
        hoverLayer.isHidden = !(isMultiSelected || hovering) || (isSelected && !isMultiSelected)
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
        hoverLayer.frame = bounds
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

    /// The average colour of the icon's opaque pixels (spec §I.2 "dominant colour").
    static func dominantColor(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 127 {
            red += Double(pixels[index])
            green += Double(pixels[index + 1])
            blue += Double(pixels[index + 2])
            alpha += Double(pixels[index + 3])
        }
        guard alpha > 0 else { return nil }
        // Premultiplied sums over the alpha sum: the unpremultiplied average.
        return NSColor(srgbRed: red / alpha, green: green / alpha, blue: blue / alpha, alpha: 1)
    }
}
