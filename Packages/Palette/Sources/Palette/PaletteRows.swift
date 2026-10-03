import AppKit
import Design
import Sidebar

/// One row as drawn.
struct PaletteRow: Identifiable, Equatable {
    enum Icon: Equatable {
        /// A favicon, or the letter tile for `domain` without one (spec §I.2).
        case favicon(NSImage?, domain: String, dimmed: Bool)
        case symbol(Symbol)
        /// A command's SF Symbol by name.
        case systemName(String)
    }

    var id: String
    var icon: Icon
    var title: String
    var detail: String?
    /// "Switch to Tab" on entries.
    var hint: String?
    /// Another space's name (spec §C chip).
    var spaceName: String?
    /// The first row of a group after the first: a small gap above it.
    var startsGroup: Bool
    /// A history row: an × removes it (spec §C).
    var isDeletable = false
}

/// The result list: one reusable AppKit row view per slot (PLAN §4: palette
/// rows are AppKit; SwiftUI laid out eight new rows in ~12 ms on a query's
/// first keystroke, 2.4b profile). The controller sets `rows` and
/// `highlighted`; a slot's views are only touched when its row changed.
final class PaletteRowsView: NSView {
    /// One per possible row (`OmniboxResult.limit`).
    static let slots = 8

    var rows: [PaletteRow] = [] {
        didSet { if rows != oldValue { update() } }
    }
    var highlighted: Int? {
        didSet {
            guard highlighted != oldValue else { return }
            for (index, view) in slotViews.enumerated() { view.isHighlighted = index == highlighted }
        }
    }
    var onHover: ((Int) -> Void)?
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onDelete: ((Int) -> Void)?
    /// The pointer only highlights a row when it moved: rows changing under a
    /// still pointer must not take the highlight from the keyboard's top hit.
    private var lastPointer: NSPoint?
    private var slotViews: [PaletteRowView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for index in 0..<Self.slots {
            let view = PaletteRowView(frame: .zero)
            view.inUse = false
            view.onHover = { [weak self] in self?.pointerMoved(over: index) }
            view.onClick = { [weak self] flags in self?.onClick?(index, flags) }
            view.onDelete = { [weak self] in self?.onDelete?(index) }
            slotViews.append(view)
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Suggestions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    private func pointerMoved(over index: Int) {
        let location = NSEvent.mouseLocation
        defer { lastPointer = location }
        guard let lastPointer, lastPointer != location else { return }
        onHover?(index)
    }

    /// Slots past the rows keep their last content and stay shown: the panel
    /// clips the list to the rows in use. Hiding them made AppKit redraw
    /// every row it showed again, which was most of a query's first
    /// keystroke (2.6a measurement: the cost followed the row count, not
    /// whether the rows' content changed).
    private func update() {
        for (index, view) in slotViews.enumerated() {
            let inUse = index < rows.count
            view.inUse = inUse
            guard inUse else { continue }
            view.row = rows[index]
            view.isHighlighted = index == highlighted
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var y = PaletteMetrics.listPadding
        let width = bounds.width - 2 * PaletteMetrics.listPadding
        for (index, view) in slotViews.enumerated() {
            if index < rows.count, rows[index].startsGroup { y += PaletteMetrics.groupGap }
            let frame = NSRect(x: PaletteMetrics.listPadding, y: y, width: width, height: PaletteMetrics.rowHeight)
            if view.frame != frame { view.frame = frame }
            y += PaletteMetrics.rowHeight
        }
    }
}

/// One slot: icon, title and detail, space chip, hint, ×. Frames are set by
/// hand in `layout()`; colours are dynamic `NSColor`s resolved for the
/// view's appearance (the overlay is reused across opens and appearance changes).
final class PaletteRowView: NSView {
    var row: PaletteRow? {
        didSet { if row != oldValue { apply() } }
    }
    var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            updateHighlight()
            needsLayout = true
        }
    }
    /// A slot past the rows: clipped away by the panel, out of the accessibility tree.
    var inUse = true {
        didSet { if inUse != oldValue { setAccessibilityElement(inUse) } }
    }
    var onHover: (() -> Void)?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDelete: (() -> Void)?

    private let favicon = FaviconView(frame: NSRect(x: 0, y: 0, width: PaletteMetrics.iconSize, height: PaletteMetrics.iconSize))
    private let symbol = NSImageView()
    private let label = PaletteRowView.makeLabel(font: Typography.row)
    private let chip = NSView()
    private let chipLabel = PaletteRowView.makeLabel(font: Typography.secondary)
    private let hint = PaletteRowView.makeLabel(font: Typography.secondary)
    private let delete = PaletteDeleteButton()
    private let pill = CALayer()
    private var hovering = false {
        didSet { if hovering != oldValue { updateDeleteVisibility() } }
    }
    /// Sizes measured once per text (they change only with the row).
    private var chipSize = NSSize.zero
    private var hintSize = NSSize.zero

    /// Symbol icons: 13 pt, secondary label colour (2.4b look).
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    /// Looking a symbol up in the catalogue on every row update showed in the profile (2.6a).
    private static var symbolImages: [String: NSImage] = [:]
    /// One line of `Typography.row` (labels are never measured per row).
    private static let labelHeight = ceil(NSLayoutManager().defaultLineHeight(for: Typography.row))

    private static func symbolImage(_ name: String) -> NSImage? {
        if let image = symbolImages[name] { return image }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        symbolImages[name] = image
        return image
    }
    private static let gap = SidebarMetrics.faviconTitleGap + 2
    private static let chipInsets = NSSize(width: 6, height: 2)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pill.cornerRadius = Radius.medium
        pill.cornerCurve = .continuous
        pill.isHidden = true
        layer?.addSublayer(pill)
        symbol.imageScaling = .scaleNone
        symbol.contentTintColor = .secondaryLabelColor
        symbol.symbolConfiguration = Self.symbolConfiguration
        label.lineBreakMode = .byTruncatingTail
        hint.textColor = .secondaryLabelColor
        hint.stringValue = ""
        chipLabel.textColor = .secondaryLabelColor
        chip.wantsLayer = true
        chip.addSubview(chipLabel)
        delete.target = self
        delete.action = #selector(deleteClicked)
        delete.alphaValue = 0
        for view in [favicon, symbol, label, chip, hint, delete] { addSubview(view) }
        // One area that follows the visible rect: re-adding areas on every layout showed in the profile (2.6a).
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private static func makeLabel(font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.cell?.truncatesLastVisibleLine = true
        label.setAccessibilityElement(false)
        return label
    }

    // MARK: Content

    private func apply() {
        guard let row else { return }
        switch row.icon {
        case .favicon(let image, let domain, let dimmed):
            favicon.image = image
            favicon.letterSource = domain
            favicon.isUnloaded = dimmed
            favicon.isHidden = false
            symbol.isHidden = true
        case .symbol(let value):
            symbol.image = Self.symbolImage(value.name)
            symbol.isHidden = false
            favicon.isHidden = true
        case .systemName(let name):
            symbol.image = Self.symbolImage(name)
            symbol.isHidden = false
            favicon.isHidden = true
        }
        label.attributedStringValue = Self.text(title: row.title, detail: row.detail)
        chip.isHidden = row.spaceName == nil
        if let space = row.spaceName, chipLabel.stringValue != space {
            chipLabel.stringValue = space
            chipSize = chipLabel.cell?.cellSize ?? .zero
        }
        if let text = row.hint, hint.stringValue != text {
            hint.stringValue = text
            hintSize = hint.cell?.cellSize ?? .zero
        }
        hint.isHidden = !isHighlighted || row.hint == nil
        delete.isHidden = !row.isDeletable
        updateDeleteVisibility()
        setAccessibilityLabel(row.detail.map { "\(row.title), \($0)" } ?? row.title)
        needsLayout = true
    }

    /// Title and detail in one text, the detail cut first (tail truncation).
    private static func text(title: String, detail: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let string = NSMutableAttributedString(string: title, attributes: [
            .font: Typography.row, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        if let detail {
            string.append(NSAttributedString(string: "  " + detail, attributes: [
                .font: Typography.row, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
            ]))
        }
        return string
    }

    private func updateHighlight() {
        pill.isHidden = !isHighlighted
        hint.isHidden = !isHighlighted || row?.hint == nil
        updateDeleteVisibility()
        setAccessibilitySelected(isHighlighted)
        if isHighlighted { updateColors() }
    }

    /// Spec §C: hover shows an × on the right (also on the highlighted row, for ⇧Delete's target).
    private func updateDeleteVisibility() {
        delete.alphaValue = row?.isDeletable == true && (isHighlighted || hovering) ? 1 : 0
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            pill.backgroundColor = Palette.sidebarMultiSelection.cgColor
            chip.layer?.backgroundColor = Palette.sidebarHover.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    // MARK: Layout (the 2.4b SwiftUI row: icon, 8 pt gaps, label, ≥ 8 pt spacer, chip, hint, ×)

    override func layout() {
        super.layout()
        if pill.frame != bounds { pill.frame = bounds }
        let height = bounds.height
        let inset = SidebarMetrics.rowContentInset
        let gap = Self.gap
        let iconSize = PaletteMetrics.iconSize
        let iconFrame = NSRect(x: inset, y: ((height - iconSize) / 2).rounded(), width: iconSize, height: iconSize)
        Self.place(favicon, iconFrame)
        Self.place(symbol, iconFrame.insetBy(dx: -2, dy: -2))

        // Trailing items right to left.
        var right = bounds.width - inset
        if !delete.isHidden {
            let size = PaletteMetrics.deleteButtonSize
            Self.place(delete, NSRect(x: right - size, y: ((height - size) / 2).rounded(), width: size, height: size))
            right = delete.frame.minX - gap
        }
        if !hint.isHidden {
            let width = ceil(hintSize.width)
            Self.place(hint, NSRect(x: right - width, y: ((height - hintSize.height) / 2).rounded(), width: width, height: ceil(hintSize.height)))
            right = hint.frame.minX - gap
        }
        if !chip.isHidden {
            let insets = Self.chipInsets
            let size = NSSize(width: ceil(chipSize.width) + 2 * insets.width, height: ceil(chipSize.height) + 2 * insets.height)
            Self.place(chip, NSRect(x: right - size.width, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height))
            chip.layer?.cornerRadius = size.height / 2
            Self.place(chipLabel, NSRect(x: insets.width, y: insets.height, width: ceil(chipSize.width), height: ceil(chipSize.height)))
            right = chip.frame.minX - gap
        }
        // The spacer between the label and the trailing items is at least 8 pt, with a gap on each side.
        let labelX = iconFrame.maxX + gap
        let labelLimit = right - 8 - gap
        let labelHeight = Self.labelHeight
        Self.place(label, NSRect(x: labelX, y: ((height - labelHeight) / 2).rounded(), width: max(0, labelLimit - labelX), height: labelHeight))
    }

    /// Frames are only set when they change: each set lays the view out again.
    private static func place(_ view: NSView, _ frame: NSRect) {
        if view.frame != frame { view.frame = frame }
    }

    // MARK: Pointer

    override func mouseEntered(with event: NSEvent) {
        guard inUse else { return }
        hovering = true
        onHover?()
    }

    override func mouseMoved(with event: NSEvent) { if inUse { onHover?() } }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(event.modifierFlags)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The × only takes clicks while it shows; elsewhere the row takes them (not its labels).
        guard inUse, !isHidden, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if !delete.isHidden, delete.alphaValue > 0, delete.frame.contains(local) { return delete }
        return self
    }

    @objc private func deleteClicked() { onDelete?() }
}

/// The × that removes a history row: 10 pt semibold, secondary label colour.
private final class PaletteDeleteButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        bezelStyle = .shadowlessSquare
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: Symbol.closeTab.name, accessibilityDescription: "Remove from History")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        contentTintColor = .secondaryLabelColor
        setAccessibilityLabel("Remove from History")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
