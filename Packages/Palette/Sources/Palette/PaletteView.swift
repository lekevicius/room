import AppKit
import Design
import SwiftUI

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
        // Above every sibling (the page included): outside the panel it is the overlay itself.
        super.hitTest(point) ?? (frame.contains(point) ? self : nil)
    }

    override func mouseDown(with event: NSEvent) { onClickOutside?() }
    override func rightMouseDown(with event: NSEvent) { onClickOutside?() }
    override func otherMouseDown(with event: NSEvent) { onClickOutside?() }
    override func scrollWheel(with event: NSEvent) {}
}

/// The palette itself: `NSGlassEffectView` (PLAN §2.4) holding the text
/// field and, below it, the SwiftUI rows.
final class PalettePanelView: NSView {
    let field = PaletteField()
    let rows = PaletteRowsModel()
    private let glass = NSGlassEffectView()
    private let content = FlippedView()
    private let searchIcon = NSImageView()
    private let separator = NSBox()
    /// The site-search chip ("YouTube") left of the field (spec §C).
    private let chip = NSView()
    private let chipLabel = NSTextField(labelWithString: "")
    private lazy var rowsView = NSHostingView(rootView: PaletteRowsView(model: rows))

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.cornerRadius = Radius.large
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        searchIcon.image = Symbol.search.image(pointSize: 15, accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        separator.boxType = .separator
        rowsView.sizingOptions = []
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
        content.addSubview(rowsView)
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
        let hasRows = !rows.rows.isEmpty
        separator.isHidden = !hasRows
        separator.frame = NSRect(x: 0, y: PaletteMetrics.fieldHeight, width: width, height: 1)
        rowsView.isHidden = !hasRows
        let top = PaletteMetrics.fieldHeight + 1
        rowsView.frame = NSRect(x: 0, y: top, width: width, height: max(0, bounds.height - top))
    }

    // MARK: Open / close animation (spec §I.1: scale 0.96 → 1 and fade, 120 ms)

    func animateIn() {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        if !Motion.reduceMotion {
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
        setAccessibilityIdentifier("palette-field")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
