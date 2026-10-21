import AppKit
import Design

/// Fills the window's content view above the card and the sidebar while
/// the palette is open: a click anywhere outside the panel dismisses it
/// (and is not passed on), the panel itself is the glass field and list.
final class PaletteOverlayView: NSView {
    let panel = PalettePanelView()
    var onClickOutside: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(panel)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Hidden between opens (it stays in the view tree): clicks go to the window.
        guard !isHidden else { return nil }
        // Above every sibling (the page included): outside the panel it is the overlay itself.
        return super.hitTest(point) ?? (frame.contains(point) ? self : nil)
    }

    override func mouseDown(with event: NSEvent) { onClickOutside?() }
    override func rightMouseDown(with event: NSEvent) { onClickOutside?() }
    override func otherMouseDown(with event: NSEvent) { onClickOutside?() }
    override func scrollWheel(with event: NSEvent) {}
}

/// The palette itself: `NSGlassEffectView` (PLAN §2.4) holding the text
/// field and, below it, the AppKit rows (PLAN §4).
final class PalettePanelView: NSView {
    let field = PaletteField()
    let rows = PaletteRowsView(frame: .zero)
    /// Rows the panel shows; the list's slots may hold more (stale, clipped away).
    var visibleRowCount = 0 {
        didSet { if visibleRowCount != oldValue { needsLayout = true } }
    }
    private let glass = NSGlassEffectView()
    private let content = FlippedView()
    private let searchIcon = NSImageView()
    private let separator = NSBox()
    /// The site-search chip ("YouTube") left of the field (spec §C).
    private let chip = NSView()
    private let chipLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.cornerRadius = Radius.large
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        searchIcon.image = Symbol.search.image(pointSize: 15, accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        separator.boxType = .separator
        chip.wantsLayer = true
        chip.layer?.cornerRadius = PaletteMetrics.chipHeight / 2
        chip.isHidden = true
        chipLabel.font = NSFont.systemFont(ofSize: Typography.secondary.pointSize, weight: .semibold)
        chipLabel.textColor = .labelColor
        chip.addSubview(chipLabel)
        content.addSubview(chip)
        content.addSubview(searchIcon)
        content.addSubview(field)
        content.addSubview(separator)
        content.addSubview(rows)
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        glass.contentView = content
        addSubview(glass)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Command palette")
        setAccessibilityIdentifier("palette")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Shows the site-search chip with `name`, or hides it (`nil`).
    func setChip(_ name: String?) {
        chip.isHidden = name == nil
        chipLabel.stringValue = name ?? ""
        field.placeholderString = name.map { "Search \($0)…" } ?? PaletteField.placeholder
        needsLayout = true
    }

    override func updateLayer() {
        super.updateLayer()
        chip.layer?.backgroundColor = Palette.sidebarMultiSelection.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { chip.layer?.backgroundColor = Palette.sidebarMultiSelection.cgColor }
    }

    /// The panel's height for `rowCount` rows in `groupCount` groups.
    static func height(rowCount: Int, groupCount: Int) -> CGFloat {
        guard rowCount > 0 else { return PaletteMetrics.fieldHeight }
        return PaletteMetrics.fieldHeight + 1 + 2 * PaletteMetrics.listPadding + CGFloat(rowCount) * PaletteMetrics.rowHeight
            + CGFloat(max(0, groupCount - 1)) * PaletteMetrics.groupGap
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let inset = PaletteMetrics.fieldInset
        let icon: CGFloat = 18
        searchIcon.frame = NSRect(x: inset, y: (PaletteMetrics.fieldHeight - icon) / 2, width: icon, height: icon)
        let fieldHeight = ceil(field.intrinsicContentSize.height)
        var x = searchIcon.frame.maxX + PaletteMetrics.listPadding + 4
        if !chip.isHidden {
            let label = chipLabel.intrinsicContentSize
            let width = ceil(label.width) + 2 * PaletteMetrics.chipPadding
            chip.frame = NSRect(x: x, y: ((PaletteMetrics.fieldHeight - PaletteMetrics.chipHeight) / 2).rounded(), width: width,
                                height: PaletteMetrics.chipHeight)
            chipLabel.frame = NSRect(x: PaletteMetrics.chipPadding, y: ((PaletteMetrics.chipHeight - ceil(label.height)) / 2).rounded(),
                                     width: ceil(label.width), height: ceil(label.height))
            effectiveAppearance.performAsCurrentDrawingAppearance { chip.layer?.backgroundColor = Palette.sidebarMultiSelection.cgColor }
            x = chip.frame.maxX + PaletteMetrics.listPadding
        }
        field.frame = NSRect(x: x, y: ((PaletteMetrics.fieldHeight - fieldHeight) / 2).rounded(), width: max(0, width - x - inset),
                             height: fieldHeight)
        separator.isHidden = visibleRowCount == 0
        separator.frame = NSRect(x: 0, y: PaletteMetrics.fieldHeight, width: width, height: 1)
        // The list keeps its full size; without rows the content view clips it away.
        let top = PaletteMetrics.fieldHeight + 1
        // Always the height of every slot (the content view clips it), so its size changes only with the width.
        let full = Self.height(rowCount: PaletteRowsView.slots, groupCount: PaletteRowsView.slots) - top
        let frame = NSRect(x: 0, y: top, width: width, height: full)
        if rows.frame != frame { rows.frame = frame }
    }

    // MARK: Open / close animation (spec §I.1: scale 0.96 → 1 and fade, 120 ms)

    func animateIn() {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        if PaletteMotion.open.variant == .full {
            // The view's layer scales about its origin; the translation keeps the scale centred.
            let scale = PaletteMetrics.openScale
            let size = bounds.size
            var from = CATransform3DMakeTranslation(size.width * (1 - scale) / 2, size.height * (1 - scale) / 2, 0)
            from = CATransform3DScale(from, scale, scale, 1)
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = from
            grow.toValue = CATransform3DIdentity
            animations.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = Motion.fast
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "open")
    }
}

/// The palette's text field: borderless on the glass, one line, the
/// palette type size. Its delegate (the controller) handles ↑/↓/⏎/⎋/⇥
/// through the field editor's commands.
final class PaletteField: NSTextField {
    static let placeholder = "Search or enter URL…"

    override class var cellClass: AnyClass? {
        get { PaletteFieldCell.self }
        set {}
    }

    // No neighbours in the key-view loop (see `PaletteFieldEditor`).
    override var previousValidKeyView: NSView? { nil }
    override var nextValidKeyView: NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = Typography.paletteField
        placeholderString = Self.placeholder
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
        lineBreakMode = .byClipping
        // It holds URLs and queries. Declared, AppKit's AutoFill stops guessing
        // whether it is a username or one-time-code field, which built an
        // AutoFill window on every open (2.4b profile).
        contentType = .URL
        setAccessibilityIdentifier("palette-field")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Gives the palette field its own field editor (below).
final class PaletteFieldCell: NSTextFieldCell {
    private lazy var editor = PaletteFieldEditor()

    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}

/// The palette's field editor. Field and editor have no neighbours in the
/// key-view loop: when a field gains focus, AppKit's AutoFill heuristics ask
/// for its previous and next valid key views, which otherwise walk every
/// view in the window (6–7 ms per open with 500 sidebar rows, 2.4b
/// profile). The palette's field has no username or password neighbour to find.
final class PaletteFieldEditor: NSTextView {
    /// TextKit 1: one line of text, and the TextKit 2 editor's selection and
    /// viewport bookkeeping was a millisecond of every keystroke (2.6a profile).
    convenience init() {
        self.init(usingTextLayoutManager: false)
        isFieldEditor = true
    }

    override var previousValidKeyView: NSView? { nil }
    override var nextValidKeyView: NSView? { nil }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
