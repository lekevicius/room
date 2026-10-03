import AppKit
import Design
import Model

/// The folder preview (spec §A.6, Arc's Folder Preview, Zen's folder
/// search): resting the pointer on a collapsed folder for 500 ms opens a
/// popover with "Search {folder}…" and the folder's tabs (nested ones
/// included); the first match is highlighted, ↑/↓ move, Enter or a click
/// opens it (it then peeks under the still-collapsed folder), Esc closes.
final class FolderPreviewController: NSViewController, NSSearchFieldDelegate {
    struct Item: Equatable {
        var id: UUID
        var title: String
        var url: String?
        var domain: String
    }

    private let folderName: String
    private let items: [Item]
    private let onOpen: (UUID) -> Void
    private let searchField = NSSearchField()
    private let list = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No tabs matching that search")
    private var matches: [Item] = []
    private var highlighted = 0
    private weak var popover: NSPopover?

    static let rowHeight: CGFloat = 28
    static let visibleRows = 8

    init(folderName: String, items: [Item], onOpen: @escaping (UUID) -> Void) {
        self.folderName = folderName
        self.items = items
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the preview next to `rect` in `view`; returns the popover.
    @discardableResult
    static func show(folderName: String, items: [Item], relativeTo rect: NSRect, of view: NSView,
                     onOpen: @escaping (UUID) -> Void) -> NSPopover {
        let controller = FolderPreviewController(folderName: folderName, items: items, onOpen: onOpen)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !Motion.reduceMotion
        popover.contentViewController = controller
        controller.popover = popover
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        controller.view.window?.makeFirstResponder(controller.searchField)
        return popover
    }

    override func loadView() {
        searchField.placeholderString = "Search \(folderName)…"
        searchField.font = Typography.row
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityIdentifier("folder-preview-search")
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        let document = FlippedStack()
        document.addSubview(list)
        scrollView.documentView = document
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        emptyLabel.font = Typography.secondary
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true
        let width = SidebarMetrics.popoverFieldWidth
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width + 2 * Spacing.s, height: 0))
        container.addSubview(searchField)
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)
        view = container
        filter("")
    }

    private func layoutContent() {
        let width = SidebarMetrics.popoverFieldWidth
        let inset = Spacing.s
        let listHeight = CGFloat(min(max(matches.count, 1), Self.visibleRows)) * Self.rowHeight
        let fieldHeight: CGFloat = 24
        let height = inset + fieldHeight + inset + listHeight + inset
        view.setFrameSize(NSSize(width: width + 2 * inset, height: height))
        preferredContentSize = view.frame.size
        searchField.frame = NSRect(x: inset, y: height - inset - fieldHeight, width: width, height: fieldHeight)
        scrollView.frame = NSRect(x: inset, y: inset, width: width, height: listHeight)
        emptyLabel.frame = NSRect(x: inset + Spacing.xs, y: inset + (listHeight - 16) / 2, width: width, height: 16)
        let total = CGFloat(matches.count) * Self.rowHeight
        scrollView.documentView?.frame = NSRect(x: 0, y: 0, width: width, height: max(total, listHeight))
        list.frame = NSRect(x: 0, y: 0, width: width, height: total)
    }

    private func filter(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        matches = needle.isEmpty ? items : items.filter {
            $0.title.lowercased().contains(needle) || ($0.url?.lowercased().contains(needle) ?? false)
        }
        highlighted = 0
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in matches.enumerated() {
            let row = FolderPreviewRow(item: item)
            row.frame.size = NSSize(width: SidebarMetrics.popoverFieldWidth, height: Self.rowHeight)
            row.onClick = { [weak self] in self?.open(index) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: SidebarMetrics.popoverFieldWidth).isActive = true
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
        }
        emptyLabel.isHidden = !matches.isEmpty
        updateHighlight()
        layoutContent()
    }

    private func updateHighlight() {
        for (index, row) in list.arrangedSubviews.enumerated() {
            (row as? FolderPreviewRow)?.isHighlighted = index == highlighted
        }
        if list.arrangedSubviews.indices.contains(highlighted) {
            list.arrangedSubviews[highlighted].scrollToVisible(list.arrangedSubviews[highlighted].bounds)
        }
    }

    private func open(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        let id = matches[index].id
        popover?.close()
        onOpen(id)
    }

    func controlTextDidChange(_ obj: Notification) { filter(searchField.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            open(highlighted)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            popover?.close()
            return true
        case #selector(NSResponder.moveDown(_:)):
            highlighted = min(highlighted + 1, max(0, matches.count - 1))
            updateHighlight()
            return true
        case #selector(NSResponder.moveUp(_:)):
            highlighted = max(highlighted - 1, 0)
            updateHighlight()
            return true
        default:
            return false
        }
    }
}

private final class FlippedStack: NSView {
    override var isFlipped: Bool { true }
}

/// One tab in the folder preview: icon and title; highlighted like a hovered row.
private final class FolderPreviewRow: NSView {
    var onClick: (() -> Void)?
    var isHighlighted = false { didSet { needsDisplay = true } }
    private let favicon = FaviconView()
    private let title = NSTextField(labelWithString: "")

    init(item: FolderPreviewController.Item) {
        super.init(frame: .zero)
        favicon.letterSource = item.domain
        title.stringValue = item.title
        title.font = Typography.row
        title.lineBreakMode = .byTruncatingTail
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        addSubview(favicon)
        addSubview(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let icon = SidebarMetrics.faviconSize
        favicon.frame = NSRect(x: Spacing.s, y: ((bounds.height - icon) / 2).rounded(), width: icon, height: icon)
        let height = ceil(title.cell?.cellSize.height ?? 16)
        let x = favicon.frame.maxX + SidebarMetrics.faviconTitleGap
        title.frame = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - x - Spacing.s), height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHighlighted else { return }
        Palette.sidebarMultiSelection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: Radius.small, yRadius: Radius.small).fill()
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
