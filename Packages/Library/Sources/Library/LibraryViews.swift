import AppKit
import Design

/// The Library's view: the search field over one table. Transparent: the
/// sidebar's material shows through, as under the spaces' lists.
public final class LibraryView: NSView {
    public let searchField = NSSearchField()
    let scrollView = NSScrollView()
    let tableView = LibraryTableView()
    /// Esc with the keyboard in the table (the field handles its own).
    var onCancel: (() -> Void)?

    public override var isFlipped: Bool { true }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        searchField.placeholderString = "Search Archive, Downloads, History"
        searchField.font = Typography.row
        searchField.focusRingType = .none
        searchField.setAccessibilityIdentifier("library-search")
        addSubview(searchField)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.setAccessibilityIdentifier("library-table")
        tableView.onCancel = { [weak self] in self?.onCancel?() }
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset
        searchField.frame = NSRect(x: inset, y: Spacing.xs, width: max(0, bounds.width - 2 * inset),
                                   height: LibraryMetrics.searchFieldHeight)
        let top = searchField.frame.maxY + Spacing.xs
        scrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        tableView.sizeLastColumnToFit()
    }

    public override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Esc in the table returns to the spaces.
final class LibraryTableView: NSTableView {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// A section's title row: chevron, title, count, and an optional trailing button (Clear Archive…).
final class LibraryHeaderCell: NSTableCellView {
    private let chevron = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let button = LibraryButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        chevron.image = Symbol.disclosure.image(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .secondaryLabelColor
        title.font = Typography.spaceTitle
        count.font = Typography.secondary
        count.textColor = .secondaryLabelColor
        button.isBordered = false
        button.font = Typography.secondary
        button.contentTintColor = .secondaryLabelColor
        for view in [chevron, title, count, button] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title text: String, count value: Int, collapsed: Bool, action: (String, () -> Void)?) {
        title.stringValue = text
        count.stringValue = "\(value)"
        chevron.frameCenterRotation = collapsed ? 0 : -90
        if let action {
            button.title = action.0
            button.handler = action.1
            button.isHidden = false
        } else {
            button.isHidden = true
        }
        setAccessibilityLabel("\(text), \(value)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        let size = SidebarMetrics.faviconSize
        chevron.frame = NSRect(x: inset, y: (bounds.height - size) / 2, width: size, height: size)
        title.sizeToFit()
        title.frame.origin = NSPoint(x: chevron.frame.maxX + SidebarMetrics.faviconTitleGap, y: (bounds.height - title.frame.height) / 2)
        count.sizeToFit()
        count.frame.origin = NSPoint(x: title.frame.maxX + Spacing.xs, y: (bounds.height - count.frame.height) / 2)
        button.sizeToFit()
        button.frame.origin = NSPoint(x: bounds.width - inset - button.frame.width, y: (bounds.height - button.frame.height) / 2)
    }
}

/// A day's label, or a section's empty state.
final class LibraryLabelCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Typography.secondary
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ text: String) {
        label.stringValue = text
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        label.sizeToFit()
        label.frame = NSRect(x: inset, y: (bounds.height - label.frame.height) / 2, width: max(0, bounds.width - 2 * inset),
                             height: label.frame.height)
    }
}

/// An item: favicon, title over a secondary line (domain or progress), a
/// chip (the space; "Archived" on History rows from `history-archive.json`)
/// and trailing buttons (Restore, Show in Finder, ×).
final class LibraryItemCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let chip = NSTextField(labelWithString: "")
    private var buttons: [LibraryButton] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = Typography.row
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = Typography.secondary
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        chip.font = Typography.secondary
        chip.textColor = .secondaryLabelColor
        chip.alignment = .center
        chip.wantsLayer = true
        chip.layer?.cornerRadius = LibraryMetrics.chipHeight / 2
        chip.layer?.backgroundColor = Palette.sidebarHover.cgColor
        for view in [icon, title, subtitle, chip] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(icon image: NSImage?, title text: String, subtitle detail: String, chip label: String?,
                   buttons specs: [(Symbol, String, () -> Void)]) {
        icon.image = image
        title.stringValue = text
        subtitle.stringValue = detail
        chip.stringValue = label ?? ""
        chip.isHidden = label == nil
        chip.setAccessibilityLabel(label)
        for button in buttons { button.removeFromSuperview() }
        buttons = specs.map { symbol, help, action in
            let button = LibraryButton()
            button.image = symbol.image()
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = help
            button.setAccessibilityLabel(help)
            button.handler = action
            addSubview(button)
            return button
        }
        setAccessibilityLabel(label.map { "\(text), \($0)" } ?? text)
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { chip.layer?.backgroundColor = Palette.sidebarHover.cgColor }
    }

    override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        let size = SidebarMetrics.faviconSize
        icon.frame = NSRect(x: inset, y: (bounds.height - size) / 2, width: size, height: size)
        let button = LibraryMetrics.buttonSize
        var trailing = bounds.width - inset
        for view in buttons.reversed() {
            view.frame = NSRect(x: trailing - button, y: (bounds.height - button) / 2, width: button, height: button)
            trailing -= button + Spacing.xs
        }
        let x = icon.frame.maxX + SidebarMetrics.faviconTitleGap
        let width = max(0, trailing - x)
        title.sizeToFit()
        subtitle.sizeToFit()
        let lines = title.frame.height + subtitle.frame.height
        let top = (bounds.height - lines) / 2
        title.frame = NSRect(x: x, y: top, width: width, height: title.frame.height)
        var subtitleWidth = width
        if !chip.isHidden {
            chip.sizeToFit()
            let chipWidth = min(chip.frame.width + 2 * LibraryMetrics.chipPadding, width / 2)
            chip.frame = NSRect(x: x + width - chipWidth, y: title.frame.maxY + (subtitle.frame.height - LibraryMetrics.chipHeight) / 2,
                                width: chipWidth, height: LibraryMetrics.chipHeight)
            subtitleWidth = max(0, chip.frame.minX - Spacing.xs - x)
        }
        subtitle.frame = NSRect(x: x, y: title.frame.maxY, width: subtitleWidth, height: subtitle.frame.height)
    }

    override var isFlipped: Bool { true }
}

/// A borderless button that runs a closure.
final class LibraryButton: NSButton {
    var handler: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(run(_:))
        bezelStyle = .inline
        setButtonType(.momentaryChange)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run(_ sender: Any?) { handler?() }
}
