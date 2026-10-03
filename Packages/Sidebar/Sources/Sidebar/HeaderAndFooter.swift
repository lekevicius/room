import AppKit
import Design
import Model

/// The header's compact address field (spec §C): the site button, the
/// selected page's domain only, and a Copy URL button on hover; the full
/// URL is the tooltip. A click edits the address (⌘L docked, Phase 2.4).
public final class AddressFieldView: NSView {
    var onActivate: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSiteButton: (() -> Void)?

    private let siteButton = NSButton()
    private let domainField = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var hovering = false { didSet { if hovering != oldValue { updateHover() } } }
    private var url: String?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("address-field")
        setAccessibilityRole(.button)
        siteButton.isBordered = false
        siteButton.imagePosition = .imageOnly
        siteButton.contentTintColor = .secondaryLabelColor
        siteButton.target = self
        siteButton.action = #selector(siteClicked)
        siteButton.setAccessibilityIdentifier("site-button")
        domainField.font = Typography.row
        // A domain that does not fit keeps both ends: "devel…apple.com" (2.2a review).
        domainField.lineBreakMode = .byTruncatingMiddle
        domainField.cell?.truncatesLastVisibleLine = true
        copyButton.image = Symbol.copyURL.image(pointSize: 12, accessibilityDescription: "Copy URL")
        copyButton.isBordered = false
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        copyButton.toolTip = "Copy URL (⇧⌘C)"
        copyButton.isHidden = true
        copyButton.setAccessibilityIdentifier("copy-url")
        addSubview(siteButton)
        addSubview(domainField)
        addSubview(copyButton)
        setURL(nil, isSecure: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var wantsUpdateLayer: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: SidebarMetrics.addressFieldHeight)
    }

    public override var fittingSize: NSSize {
        NSSize(width: bounds.width, height: SidebarMetrics.addressFieldHeight)
    }

    /// The selected page's URL (`nil`: the placeholder).
    func setURL(_ url: String?, isSecure: Bool) {
        self.url = url
        if let url, let domain = EntryLabel.domain(url) ?? Optional(url) {
            domainField.stringValue = domain
            domainField.textColor = .labelColor
            toolTip = url
        } else {
            domainField.stringValue = "Search or enter URL"
            domainField.textColor = .placeholderTextColor
            toolTip = nil
        }
        let symbol: Symbol = url == nil ? .search : (isSecure ? .siteSecure : .siteInfo)
        siteButton.image = symbol.image(pointSize: 11, accessibilityDescription: "Site Information")
        siteButton.isEnabled = url != nil
        setAccessibilityLabel(url ?? "Search or enter URL")
        updateHover()
    }

    public override func updateLayer() {
        layer?.cornerRadius = Radius.small
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = Palette.sidebarHover.cgColor
    }

    public override func layout() {
        super.layout()
        let side = bounds.height
        let padding = SidebarMetrics.addressFieldPadding
        let icon = SidebarMetrics.faviconSize
        siteButton.frame = NSRect(x: padding, y: 0, width: icon, height: side)
        let copyWidth: CGFloat = copyButton.isHidden ? 0 : side
        copyButton.frame = NSRect(x: bounds.width - side, y: 0, width: side, height: side)
        let x = siteButton.frame.maxX + padding
        let height = ceil(domainField.cell?.cellSize.height ?? 16)
        domainField.frame = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(),
                                   width: max(0, bounds.width - x - max(copyWidth, padding)), height: height)
    }

    private func updateHover() {
        copyButton.isHidden = !(hovering && url != nil)
        needsLayout = true
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true }
    public override func mouseExited(with event: NSEvent) { hovering = false }

    public override func mouseDown(with event: NSEvent) {}

    public override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onActivate?()
    }

    @objc private func copyClicked() { onCopy?() }
    @objc private func siteClicked() { onSiteButton?() }
}

/// Drops on the footer's space icons (spec §B, §I.7): an entry dropped on a
/// space's icon moves there; resting on an icon for `DropRules.holdDelay`
/// switches to that space, so the drop can land in its list.
protocol SpaceIconDropEvents: AnyObject {
    /// What a drop on `space`'s icon would do (`[]` refuses it).
    func spaceIconDragOperation(_ info: any NSDraggingInfo, space: UUID) -> NSDragOperation
    func spaceIconDragHeld(_ space: UUID)
    func spaceIconDrop(_ info: any NSDraggingInfo, space: UUID) -> Bool
}

/// The bottom bar (spec §F): the downloads button (disabled until 2.6),
/// the space icons centred (spec §B: hidden with one space; the active one
/// 1.15× over a highlight that slides between icons; the hovered or active
/// space's name beside the row while the pointer is on it) and the "+" menu.
final class SidebarFooterView: NSView {
    let downloadsButton = NSButton()
    let plusButton = NSButton()
    private let iconRow = FlippedRow()
    private let indicator = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var icons: [SpaceIconView] = []
    private var spaces: [Space] = []
    private var activeID: UUID?
    private var hoveredID: UUID? { didSet { if hoveredID != oldValue { updateLabel() } } }
    /// Builds the "+" menu when it opens.
    var plusMenu: (() -> NSMenu)?
    /// Double-click on the footer's empty area (a new tab, spec §F).
    var onEmptyDoubleClick: (() -> Void)?
    /// A click on a space's icon.
    var onSelectSpace: ((UUID) -> Void)?
    /// A space's context menu (right-click on its icon).
    var spaceMenu: ((UUID) -> NSMenu?)?
    weak var dropEvents: SpaceIconDropEvents?
    /// An icon was dragged to `index` (Reorder Spaces, spec §B).
    var onReorderSpace: ((UUID, Int) -> Void)?
    /// The icon a drag rests on and the pending switch to it.
    private var dropHover: (space: UUID, work: DispatchWorkItem)?
    /// An icon being dragged along the row: its space and the slot it would take.
    private var reorder: (space: UUID, index: Int)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        downloadsButton.image = Symbol.downloads.image(pointSize: 14, accessibilityDescription: "Downloads")
        downloadsButton.isBordered = false
        downloadsButton.imagePosition = .imageOnly
        downloadsButton.contentTintColor = .secondaryLabelColor
        downloadsButton.isEnabled = false
        downloadsButton.toolTip = "Downloads (Phase 2.6)"
        downloadsButton.setAccessibilityIdentifier("downloads")
        plusButton.image = Symbol.newTab.image(pointSize: 14, accessibilityDescription: "New")
        plusButton.isBordered = false
        plusButton.imagePosition = .imageOnly
        plusButton.contentTintColor = .secondaryLabelColor
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        plusButton.setAccessibilityIdentifier("footer-plus")
        indicator.wantsLayer = true
        indicator.layer?.cornerCurve = .continuous
        indicator.isHidden = true
        iconRow.addSubview(indicator)
        iconRow.setAccessibilityIdentifier("space-icons")
        nameLabel.font = Typography.secondary
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.alphaValue = 0
        addSubview(downloadsButton)
        addSubview(iconRow)
        addSubview(nameLabel)
        addSubview(plusButton)
        registerForDraggedTypes([SidebarController.entryPasteboardType, .URL, .fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onEmptyDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    // MARK: Spaces

    /// One icon per space (the space's emoji or SF Symbol, else a dot);
    /// none with ≤ 1 space (spec §B). The highlight slides to the active one.
    func setSpaces(_ spaces: [Space], active: UUID?, animated: Bool) {
        let same = spaces.map(\.id) == self.spaces.map(\.id)
        let previousActive = activeID
        self.spaces = spaces
        activeID = active
        if !same || icons.count != spaces.count {
            icons.forEach { $0.removeFromSuperview() }
            icons = spaces.count > 1 ? spaces.map { space in
                let icon = SpaceIconView(space: space)
                icon.onClick = { [weak self] in self?.onSelectSpace?(space.id) }
                icon.onMenu = { [weak self] in self?.spaceMenu?(space.id) }
                icon.onHover = { [weak self] hovering in self?.iconHovered(space.id, hovering) }
                icon.onDrag = { [weak self] event, phase in self?.iconDragged(space.id, event, phase) }
                iconRow.addSubview(icon)
                return icon
            } : []
        } else {
            // A switch: only the active icon changes (no layout pass, Phase 2.5 switch timing).
            for (icon, space) in zip(icons, spaces) where icon.space != space { icon.update(space) }
            applyActive(animated: animated && previousActive != nil && previousActive != active)
            return
        }
        indicator.isHidden = icons.isEmpty
        needsLayout = true
        layoutSubtreeIfNeeded()
        applyActive(animated: false)
        updateLabel()
    }

    private func applyActive(animated: Bool) {
        guard let index = spaces.firstIndex(where: { $0.id == activeID }), icons.indices.contains(index) else { return }
        let target = icons[index].frame.insetBy(dx: -SpaceIconMetrics.indicatorPadding, dy: -SpaceIconMetrics.indicatorPadding)
        let duration = animated && !Motion.reduceMotion ? Motion.medium : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = duration > 0
            indicator.animator().frame = target
            for (offset, icon) in icons.enumerated() where icon.isActive != (offset == index) || !animated {
                icon.setActive(offset == index, animated: duration > 0)
            }
        }
    }

    private func iconHovered(_ space: UUID, _ hovering: Bool) {
        if hovering { hoveredID = space } else if hoveredID == space { hoveredID = nil }
    }

    /// The hovered space's name beside the row, only while the pointer is on it (spec §B).
    private func updateLabel() {
        let name = hoveredID.flatMap { id in spaces.first { $0.id == id }?.name }
        if let name { nameLabel.stringValue = name }
        needsLayout = true
        layoutSubtreeIfNeeded()
        // A name longer than the gap before "+" takes its place while shown.
        let covers = name != nil && nameLabel.frame.maxX > plusButton.frame.minX - Spacing.xs
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fast
            nameLabel.animator().alphaValue = name == nil ? 0 : 1
            plusButton.animator().alphaValue = covers ? 0 : 1
        }
    }

    override func updateLayer() {
        indicator.layer?.backgroundColor = Palette.sidebarHover.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { indicator.layer?.backgroundColor = Palette.sidebarHover.cgColor }
    }

    override func layout() {
        super.layout()
        let side = SidebarMetrics.footerButtonSize
        let inset = SidebarMetrics.rowHorizontalInset + Spacing.xs
        let y = ((bounds.height - side) / 2).rounded()
        downloadsButton.frame = NSRect(x: inset, y: y, width: side, height: side)
        plusButton.frame = NSRect(x: bounds.width - inset - side, y: y, width: side, height: side)
        // Icons shrink to fit between the buttons (Zen shrinks its strip on overflow).
        let available = max(0, plusButton.frame.minX - downloadsButton.frame.maxX - 2 * Spacing.xs)
        let count = CGFloat(icons.count)
        let pitch = count > 0 ? min(SpaceIconMetrics.pitch, available / count) : 0
        let size = min(SpaceIconMetrics.size, pitch)
        let rowWidth = pitch * count
        iconRow.frame = NSRect(x: ((bounds.width - rowWidth) / 2).rounded(), y: 0, width: rowWidth, height: bounds.height)
        for (index, icon) in icons.enumerated() {
            icon.frame = NSRect(x: CGFloat(index) * pitch + (pitch - size) / 2, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        }
        indicator.layer?.cornerRadius = (size + 2 * SpaceIconMetrics.indicatorPadding) / 2
        if let index = spaces.firstIndex(where: { $0.id == activeID }), icons.indices.contains(index), indicator.layer?.animationKeys()?.isEmpty != false {
            indicator.frame = icons[index].frame.insetBy(dx: -SpaceIconMetrics.indicatorPadding, dy: -SpaceIconMetrics.indicatorPadding)
        }
        let labelSize = nameLabel.cell?.cellSize ?? NSSize(width: 0, height: 14)
        let labelX = iconRow.frame.maxX + Spacing.xs
        nameLabel.frame = NSRect(x: labelX, y: ((bounds.height - ceil(labelSize.height)) / 2).rounded(),
                                 width: max(0, min(ceil(labelSize.width), bounds.width - inset - labelX)), height: ceil(labelSize.height))
    }

    // MARK: Reordering (spec §B: drag an icon more than a few points, Zen)

    private func iconDragged(_ space: UUID, _ event: NSEvent, _ phase: SpaceIconView.DragPhase) {
        guard let from = spaces.firstIndex(where: { $0.id == space }), !icons.isEmpty else { return }
        let pitch = iconRow.bounds.width / CGFloat(icons.count)
        let x = iconRow.convert(event.locationInWindow, from: nil).x
        let index = min(max(Int(x / max(pitch, 1)), 0), icons.count - 1)
        switch phase {
        case .moved:
            if reorder?.index != index {
                if reorder != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                reorder = (space, index)
                layoutReorder(moving: from, to: index, pitch: pitch)
            }
            // The dragged icon follows the pointer.
            icons[from].frame.origin.x = min(max(x - icons[from].frame.width / 2, 0), iconRow.bounds.width - icons[from].frame.width)
        case .ended:
            let target = reorder?.index
            reorder = nil
            if let target, target != from { onReorderSpace?(space, target) } else { needsLayout = true }
        }
    }

    /// The other icons make room for the dragged one at `to`.
    private func layoutReorder(moving from: Int, to: Int, pitch: CGFloat) {
        var order = Array(icons.indices)
        order.remove(at: from)
        order.insert(from, at: to)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.standard
            for (slot, index) in order.enumerated() where index != from {
                var frame = icons[index].frame
                frame.origin.x = CGFloat(slot) * pitch + (pitch - frame.width) / 2
                icons[index].animator().frame = frame
            }
        }
    }

    /// The icon view of a space (DEBUG captures, drop targeting).
    func icon(for space: UUID) -> NSView? {
        spaces.firstIndex { $0.id == space }.flatMap { icons.indices.contains($0) ? icons[$0] : nil }
    }

    /// Shows the hover label as if the pointer were on `space`'s icon (DEBUG captures).
    func debugHover(_ space: UUID?) { hoveredID = space }

    @objc private func plusClicked() {
        guard let menu = plusMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: plusButton.frame.minX, y: plusButton.frame.minY), in: self)
    }

    // MARK: Drops on space icons

    private func space(at info: any NSDraggingInfo) -> UUID? {
        let point = iconRow.convert(info.draggingLocation, from: nil)
        guard let index = icons.firstIndex(where: { $0.frame.insetBy(dx: -4, dy: -6).contains(point) }) else { return nil }
        return spaces[index].id
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { dragUpdated(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { dragUpdated(sender) }

    private func dragUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        guard let space = space(at: info), let dropEvents else {
            endDropHover()
            return []
        }
        let operation = dropEvents.spaceIconDragOperation(info, space: space)
        guard !operation.isEmpty else {
            endDropHover()
            return []
        }
        if dropHover?.space != space {
            endDropHover()
            let work = DispatchWorkItem { [weak self] in
                guard let self, dropHover?.space == space else { return }
                self.dropEvents?.spaceIconDragHeld(space)
            }
            dropHover = (space, work)
            DispatchQueue.main.asyncAfter(deadline: .now() + DropRules.holdDelay, execute: work)
            for (offset, icon) in icons.enumerated() { icon.isDropTarget = spaces[offset].id == space }
            hoveredID = space
        }
        return operation
    }

    private func endDropHover() {
        dropHover?.work.cancel()
        dropHover = nil
        icons.forEach { $0.isDropTarget = false }
        hoveredID = nil
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { endDropHover() }

    override func draggingEnded(_ sender: any NSDraggingInfo) { endDropHover() }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { endDropHover() }
        guard let space = space(at: sender) else { return false }
        return dropEvents?.spaceIconDrop(sender, space: space) ?? false
    }
}

/// Footer space icons (spec §B; chosen sizes, `docs/design-tokens.md`).
enum SpaceIconMetrics {
    /// An icon's box; the dot of a space without an icon is smaller.
    static let size: CGFloat = 20
    /// Icon spacing along the row.
    static let pitch: CGFloat = 26
    static let dotSize: CGFloat = 6
    /// The active icon's scale (spec §B).
    static let activeScale: CGFloat = 1.15
    /// The highlight behind the active icon extends this far around it.
    static let indicatorPadding: CGFloat = 2
    /// An inactive icon's opacity.
    static let inactiveAlpha: CGFloat = 0.55
    /// Pointer travel that turns a press on an icon into a reorder drag (Zen: 5 px).
    static let reorderThreshold: CGFloat = 5
}

/// A space's icon in the footer: its emoji, its SF Symbol, or a dot.
final class SpaceIconView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private(set) var space: Space
    private(set) var isActive = false
    var onClick: (() -> Void)?
    var onMenu: (() -> NSMenu?)?
    var onHover: ((Bool) -> Void)?
    enum DragPhase { case moved, ended }
    /// A press that moved past `SidebarMetrics.dragThreshold` drags the icon (reorder).
    var onDrag: ((NSEvent, DragPhase) -> Void)?
    private var pressLocation: NSPoint?
    private var dragging = false
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true; updateLayer() } } }

    init(space: Space) {
        self.space = space
        super.init(frame: .zero)
        wantsLayer = true
        label.alignment = .center
        imageView.imageScaling = .scaleProportionallyDown
        addSubview(label)
        addSubview(imageView)
        update(space)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    func update(_ space: Space) {
        self.space = space
        toolTip = space.name
        setAccessibilityRole(.button)
        setAccessibilityLabel(space.name)
        switch SpaceIcon(space.icon) {
        case .emoji(let emoji):
            label.stringValue = emoji
            label.isHidden = false
            imageView.isHidden = true
        case .symbol(let name):
            imageView.image = NSImage(systemSymbolName: name, accessibilityDescription: space.name)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
            imageView.contentTintColor = .labelColor
            label.isHidden = true
            imageView.isHidden = false
        case .none:
            imageView.image = Symbol.space.image(pointSize: SpaceIconMetrics.dotSize)
            imageView.contentTintColor = .labelColor
            label.isHidden = true
            imageView.isHidden = false
        }
        needsLayout = true
    }

    func setActive(_ active: Bool, animated: Bool) {
        isActive = active
        guard let layer else { return }
        let scale = active ? SpaceIconMetrics.activeScale : 1
        let transform = CATransform3DMakeScale(scale, scale, 1)
        // Scale about the centre (layer-backed views anchor at the origin).
        let bounds = layer.bounds
        let centred = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-bounds.midX, -bounds.midY, 0), transform),
                                          CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0))
        if animated {
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = NSValue(caTransform3D: layer.presentation()?.sublayerTransform ?? layer.sublayerTransform)
            animation.toValue = NSValue(caTransform3D: centred)
            animation.duration = Motion.medium
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "scale")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = centred
        CATransaction.commit()
        alphaValue = active ? 1 : SpaceIconMetrics.inactiveAlpha
    }

    override func updateLayer() {
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = isDropTarget ? Palette.sidebarMultiSelection.cgColor : NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        label.font = .systemFont(ofSize: max(9, bounds.height * 0.62))
        let height = ceil(label.cell?.cellSize.height ?? bounds.height)
        label.frame = NSRect(x: -2, y: ((bounds.height - height) / 2).rounded(), width: bounds.width + 4, height: height)
        imageView.frame = bounds
        if isActive { setActive(true, animated: false) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressLocation else { return }
        if !dragging, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > SpaceIconMetrics.reorderThreshold {
            dragging = true
        }
        if dragging { onDrag?(event, .moved) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressLocation = nil; dragging = false }
        if dragging {
            onDrag?(event, .ended)
            return
        }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = onMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { onMenu?() }
}

/// A space's icon value (spec §B: emoji or SF Symbol).
enum SpaceIcon: Equatable {
    case emoji(String)
    case symbol(String)
    case none

    init(_ icon: String?) {
        guard let icon, !icon.isEmpty else { self = .none; return }
        if icon.unicodeScalars.first?.properties.isEmoji == true, icon.unicodeScalars.first.map({ $0.value > 0x7F }) == true {
            self = .emoji(icon)
        } else if NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil {
            self = .symbol(icon)
        } else {
            self = .emoji(String(icon.prefix(1)))
        }
    }
}

private final class FlippedRow: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}
