import AppKit
import Design
import Model

/// What a tile reports back (clicks, menus).
protocol EssentialTileEvents: AnyObject {
    func tileClicked(_ entry: UUID, gesture: ClickRules.Gesture)
    func tileResetClicked(_ entry: UUID)
    func tileMenu(_ entry: UUID) -> NSMenu?
}

/// Layout of the Essentials grid (spec §I.2): tiles `essentialTileHeight`
/// tall that stretch to fill the row, as many per row as fit at
/// `essentialTileMinWidth`, at most `essentialMaxColumns`, never more than
/// there are tiles.
public enum EssentialsLayout {
    public static func columns(count: Int, width: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        let gap = SidebarMetrics.essentialsGap
        let fit = Int(((width + gap) / (SidebarMetrics.essentialTileMinWidth + gap)).rounded(.down))
        return max(1, min(fit, SidebarMetrics.essentialMaxColumns, count))
    }

    public static func frames(count: Int, width: CGFloat) -> [CGRect] {
        let columns = columns(count: count, width: width)
        guard columns > 0 else { return [] }
        let gap = SidebarMetrics.essentialsGap
        let tileWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = SidebarMetrics.essentialTileHeight
        return (0..<count).map { index in
            let row = index / columns, column = index % columns
            return CGRect(x: (CGFloat(column) * (tileWidth + gap)).rounded(), y: CGFloat(row) * (height + gap),
                          width: tileWidth.rounded(), height: height)
        }
    }

    public static func height(count: Int, width: CGFloat) -> CGFloat {
        frames(count: count, width: width).last?.maxY ?? 0
    }
}

/// The Essentials grid above the space title (≤ 12 tiles per profile).
final class EssentialsGridView: NSView {
    weak var events: EssentialTileEvents?
    private(set) var tiles: [UUID: EssentialTileView] = [:]
    private var order: [UUID] = []

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
            addSubview(tile)
            if animated {
                tile.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Motion.standard
                    tile.animator().alphaValue = 1
                }
            }
        }
        order = ids
        needsLayout = true
    }

    func tile(for id: UUID) -> EssentialTileView? { tiles[id] }

    func height(forWidth width: CGFloat) -> CGFloat {
        EssentialsLayout.height(count: order.count, width: width)
    }

    override func layout() {
        super.layout()
        for (id, frame) in zip(order, EssentialsLayout.frames(count: order.count, width: bounds.width)) {
            tiles[id]?.frame = frame
        }
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
        hoverLayer.backgroundColor = Palette.sidebarHover.cgColor
        hoverLayer.isHidden = !hovering || isSelected
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

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        events?.tileClicked(entryID, gesture: event.modifierFlags.contains(.command) ? .command : .primary)
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
