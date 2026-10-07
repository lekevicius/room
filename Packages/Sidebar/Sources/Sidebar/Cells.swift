import AppKit
import Design
import Model

/// What a row's buttons and inline rename report back.
protocol EntryRowActions: AnyObject {
    func resetButtonClicked(_ entry: UUID)
    func closeButtonClicked(_ entry: UUID)
    func audioButtonClicked(_ entry: UUID)
    /// Enter (`label`, empty = clear the label) or Esc (`nil`).
    func renameEnded(_ entry: UUID, label: String?, committed: Bool)
}

/// Everything an entry row shows.
struct EntryRowModel {
    var entry: Entry
    var page: EntryPageState
    var isSelected: Bool
    /// Loaded and away from the stored URL (spec §A.1 state 3).
    var isChanged: Bool
    /// Folder levels above the row (0 for the pinned root and Today).
    var depth: Int
}

/// Shared text field setup for row labels.
@MainActor
private func makeLabel(font: NSFont, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    field.font = font
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    field.cell?.truncatesLastVisibleLine = true
    field.maximumNumberOfLines = 1
    return field
}

@MainActor
private func makeIconButton(_ symbol: Symbol, size: CGFloat, label: String) -> NSButton {
    let button = NSButton(image: symbol.image(pointSize: size, weight: .medium, accessibilityDescription: label) ?? NSImage(),
                          target: nil, action: nil)
    button.isBordered = false
    button.bezelStyle = .accessoryBarAction
    button.imagePosition = .imageOnly
    button.contentTintColor = .secondaryLabelColor
    button.setAccessibilityLabel(label)
    button.toolTip = label
    return button
}

/// An entry or folder row: icon, title, hover sublabel, and on the trailing
/// side the audio indicator and (Today tabs) the close button.
final class EntryCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("entry")

    weak var actions: EntryRowActions?
    private(set) var model: EntryRowModel?

    let favicon = FaviconView()
    private let folderIcon = NSImageView()
    let titleField = makeLabel(font: Typography.row, color: .labelColor)
    private let sublabel = makeLabel(font: Typography.secondary, color: .secondaryLabelColor)
    private let resetButton = makeIconButton(.resetPinned, size: 11, label: "Back to pinned URL")
    private let closeButton = makeIconButton(.closeTab, size: 10, label: "Close Tab")
    private let audioButton = AudioIndicatorView()
    /// The page captures its camera, microphone or a screen (3.4b).
    private let captureIndicator = NSImageView()
    /// The entry is in reader mode (4.7b).
    private let readerIndicator = NSImageView()

    /// The pointer is over the row.
    var isHovered = false { didSet { if isHovered != oldValue { updateHoverState() } } }
    /// ⌘ is held (sublabel "Separate from pinned tab").
    var isCommandHeld = false { didSet { if isCommandHeld != oldValue { updateHoverState() } } }
    var isHoveringIcon = false { didSet { if isHoveringIcon != oldValue { updateHoverState() } } }
    private(set) var isRenaming = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        textField = titleField
        titleField.delegate = self
        folderIcon.imageScaling = .scaleProportionallyDown
        folderIcon.contentTintColor = .secondaryLabelColor
        sublabel.isHidden = true
        resetButton.isHidden = true
        closeButton.isHidden = true
        audioButton.isHidden = true
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        audioButton.onClick = { [weak self] in self?.audioClicked() }
        resetButton.setAccessibilityIdentifier("row-reset")
        closeButton.setAccessibilityIdentifier("row-close")
        audioButton.setAccessibilityIdentifier("row-audio")
        captureIndicator.isHidden = true
        captureIndicator.contentTintColor = .systemRed
        captureIndicator.setAccessibilityIdentifier("row-capture")
        readerIndicator.isHidden = true
        readerIndicator.contentTintColor = .secondaryLabelColor
        readerIndicator.image = Symbol.readerMode.image(pointSize: 11, weight: .medium, accessibilityDescription: "Reader mode")
        readerIndicator.toolTip = "Reader mode (⌥⇧⌘R or Esc to exit)"
        readerIndicator.setAccessibilityIdentifier("row-reader")
        for view in [favicon, folderIcon, titleField, sublabel, resetButton, closeButton, audioButton, captureIndicator, readerIndicator] as [NSView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ model: EntryRowModel) {
        let previous = self.model
        self.model = model
        let entry = model.entry
        let isFolder = entry.kind == .folder
        favicon.isHidden = isFolder
        folderIcon.isHidden = !isFolder
        if isFolder {
            let open = !entry.isCollapsed
            folderIcon.image = (open ? Symbol.folderOpen : Symbol.folder).image(pointSize: 13)
        } else {
            favicon.image = model.page.favicon
            favicon.letterSource = EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry)
            favicon.isLoading = model.page.isLoading
            favicon.showsChangedDot = model.isChanged
            let unloaded = !model.page.isLoaded
            favicon.isUnloaded = unloaded
            if previous?.entry.id == entry.id, previous?.isChanged == true, !model.isChanged, !Motion.reduceMotion {
                // Reset: crossfade back to the stored icon (spec §A.5).
                let fade = CATransition()
                fade.type = .fade
                fade.duration = Motion.resetCrossfade
                favicon.layer?.add(fade, forKey: "reset")
            }
        }
        if !isRenaming { titleField.stringValue = EntryLabel.title(entry) }
        titleField.textColor = (isFolder || model.page.isLoaded) ? .labelColor : .secondaryLabelColor
        let audible = model.page.isAudible || model.page.isMuted
        audioButton.isHidden = !audible
        if audible {
            let symbol: Symbol = model.page.isMuted ? .muted : .audible
            let label = model.page.isMuted ? "Unmute Tab" : "Mute Tab"
            audioButton.image = symbol.image(pointSize: 11, weight: .medium, accessibilityDescription: label)
            audioButton.toolTip = label
            audioButton.setAccessibilityLabel(label)
            audioButton.removeAllSymbolEffects()
            if model.page.isAudible, !model.page.isMuted, !Motion.reduceMotion {
                audioButton.addSymbolEffect(.variableColor.iterative)
            }
        }
        captureIndicator.isHidden = model.page.capture == nil
        if let capture = model.page.capture {
            let (symbol, label): (Symbol, String) = switch capture {
            case .screen: (.screenSharing, "Sharing your screen")
            case .camera: (.camera, "Using your camera")
            case .microphone: (.microphone, "Using your microphone")
            }
            captureIndicator.image = symbol.image(pointSize: 11, weight: .medium, accessibilityDescription: label)
            captureIndicator.toolTip = label
            captureIndicator.setAccessibilityLabel(label)
        }
        readerIndicator.isHidden = !model.page.isReader
        setAccessibilityLabel(EntryLabel.title(entry))
        updateHoverState()
        needsLayout = true
    }

    /// Before the row animates away as a whole (Clear): the trailing audio
    /// indicator's layer does not follow the row layer's transform and
    /// opacity (seen in the 2.2b mid-Clear capture), so it goes first.
    func prepareForSlideOut() {
        audioButton.removeAllSymbolEffects()
        audioButton.isHidden = true
    }

    // MARK: Hover

    private func updateHoverState() {
        guard let model else { return }
        let entry = model.entry
        let showReset = isHovered && model.isChanged
        resetButton.isHidden = !showReset
        favicon.isHidden = entry.kind == .folder || showReset
        closeButton.isHidden = !(isHovered && entry.kind == .today) || isRenaming
        // Sublabel: over the reset icon, what clicking it does (⌘ swaps it);
        // elsewhere on a changed entry, the live page's title (spec §I.3, §I.4).
        var text: String?
        if showReset && isHoveringIcon {
            text = isCommandHeld ? "Separate from pinned tab" : "Back to pinned URL"
        } else if isHovered && model.isChanged {
            text = EntryLabel.currentTitle(entry)
        }
        sublabel.stringValue = text ?? ""
        sublabel.isHidden = text == nil || isRenaming
        needsLayout = true
    }

    /// The pointer moved over the row (from the outline's tracking area).
    func pointerMoved(to point: NSPoint) {
        isHoveringIcon = iconRect.insetBy(dx: -4, dy: -4).contains(point)
    }

    // MARK: Layout

    private var leading: CGFloat {
        SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
            + CGFloat(model?.depth ?? 0) * SidebarMetrics.folderIndent
    }

    private var iconRect: NSRect {
        let size = SidebarMetrics.faviconSize
        return NSRect(x: leading, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
    }

    /// Where the title text sits (clicks there mean rename on double-click).
    var titleRect: NSRect { titleField.frame }

    override func layout() {
        super.layout()
        let icon = iconRect
        favicon.frame = icon
        folderIcon.frame = icon
        resetButton.frame = icon.insetBy(dx: -2, dy: -2)
        var trailing = bounds.width - SidebarMetrics.rowHorizontalInset - Spacing.xs
        let button = SidebarMetrics.closeButtonSize
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: trailing - button, y: (bounds.height - button) / 2, width: button, height: button)
            trailing -= button
        }
        if !audioButton.isHidden {
            let width = SidebarMetrics.audioIndicatorWidth
            audioButton.frame = NSRect(x: trailing - width, y: (bounds.height - button) / 2, width: width, height: button)
            trailing -= width
        }
        if !captureIndicator.isHidden {
            let width = SidebarMetrics.audioIndicatorWidth
            captureIndicator.frame = NSRect(x: trailing - width, y: (bounds.height - button) / 2, width: width, height: button)
            trailing -= width
        }
        if !readerIndicator.isHidden {
            let width = SidebarMetrics.audioIndicatorWidth
            readerIndicator.frame = NSRect(x: trailing - width, y: (bounds.height - button) / 2, width: width, height: button)
            trailing -= width
        }
        let x = icon.maxX + SidebarMetrics.faviconTitleGap
        let width = max(0, trailing - x - Spacing.xs)
        let titleHeight = ceil(titleField.cell?.cellSize.height ?? 16)
        if sublabel.isHidden {
            titleField.frame = NSRect(x: x, y: ((bounds.height - titleHeight) / 2).rounded(), width: width, height: titleHeight)
        } else {
            let subHeight = ceil(sublabel.cell?.cellSize.height ?? 13)
            let top = ((bounds.height - titleHeight - subHeight) / 2).rounded()
            titleField.frame = NSRect(x: x, y: top, width: width, height: titleHeight)
            sublabel.frame = NSRect(x: x, y: top + titleHeight, width: width, height: subHeight)
        }
    }

    // MARK: Buttons

    @objc private func resetClicked() { model.map { actions?.resetButtonClicked($0.entry.id) } }
    @objc private func closeClicked() { model.map { actions?.closeButtonClicked($0.entry.id) } }
    @objc private func audioClicked() { model.map { actions?.audioButtonClicked($0.entry.id) } }

    // MARK: Rename (spec §I.9)

    func beginRename() {
        guard let model, let window else { return }
        isRenaming = true
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBordered = false
        titleField.drawsBackground = true
        titleField.backgroundColor = .textBackgroundColor
        titleField.focusRingType = .none
        titleField.stringValue = EntryLabel.title(model.entry)
        updateHoverState()
        window.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    private func endRename(committed: Bool) {
        guard isRenaming, let model else { return }
        isRenaming = false
        let text = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.drawsBackground = false
        titleField.stringValue = EntryLabel.title(model.entry)
        updateHoverState()
        actions?.renameEnded(model.entry.id, label: committed ? text : nil, committed: committed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            endRename(committed: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(committed: false)
            return true
        default:
            return false
        }
    }

    /// Clicking elsewhere ends editing: that commits, as in Finder.
    func controlTextDidEndEditing(_ obj: Notification) {
        endRename(committed: true)
    }
}

/// The audible/muted indicator (spec §I.5): an animated equaliser while
/// playing; a click toggles mute.
final class AudioIndicatorView: NSImageView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleNone
        contentTintColor = .secondaryLabelColor
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The space title above the pinned list: icon, name, and a chevron that
/// collapses the pinned section (spec §B).
/// The space title row (spec §B): icon and name, a click on the name renames
/// it inline, "…" on hover opens the space menu, the chevron collapses the
/// pinned section (Arc).
final class SpaceTitleCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("space-title")

    private let iconField = makeLabel(font: Typography.spaceTitle, color: .secondaryLabelColor)
    private let iconImage = NSImageView()
    private let nameField = makeLabel(font: Typography.spaceTitle, color: .labelColor)
    let chevron = makeIconButton(.disclosure, size: 9, label: "Collapse Pinned")
    let moreButton = makeIconButton(.more, size: 11, label: "Space Menu")
    var onToggle: (() -> Void)?
    /// "…" was clicked: the space menu, below the button.
    var onMore: ((NSButton) -> Void)?
    /// An inline rename ended (`nil` name: cancelled).
    var onRenameEnded: ((String?) -> Void)?
    var isHovered = false { didSet { updateChevron() } }
    private var isCollapsed = false
    private(set) var isRenaming = false
    private var spaceName = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        chevron.target = self
        chevron.action = #selector(toggle)
        chevron.setAccessibilityIdentifier("pinned-collapse")
        moreButton.target = self
        moreButton.action = #selector(more)
        moreButton.setAccessibilityIdentifier("space-more")
        nameField.delegate = self
        iconImage.contentTintColor = .secondaryLabelColor
        addSubview(iconField)
        addSubview(iconImage)
        addSubview(nameField)
        addSubview(moreButton)
        addSubview(chevron)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ space: Space) {
        isNote = false
        nameField.textColor = .labelColor
        spaceName = space.name
        if !isRenaming { nameField.stringValue = space.name }
        switch SpaceIcon(space.icon) {
        case .emoji(let emoji):
            iconField.stringValue = emoji
            iconImage.image = nil
        case .symbol(let name):
            iconField.stringValue = ""
            iconImage.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        case .none:
            iconField.stringValue = ""
            iconImage.image = nil
        }
        isCollapsed = space.pinnedCollapsed
        chevron.setAccessibilityLabel(isCollapsed ? "Expand Pinned" : "Collapse Pinned")
        chevron.toolTip = chevron.accessibilityLabel()
        setAccessibilityLabel(space.name)
        updateChevron()
        needsLayout = true
    }

    /// The incognito window's note in place of a space's name (4.8b): no
    /// icon, no chevron, no menu, no rename.
    func configureNote(_ text: String) {
        isNote = true
        spaceName = text
        nameField.stringValue = text
        nameField.textColor = .secondaryLabelColor
        iconField.stringValue = ""
        iconImage.image = nil
        setAccessibilityLabel(text)
        updateChevron()
        needsLayout = true
    }

    private var isNote = false

    private func updateChevron() {
        chevron.isHidden = isNote || !(isHovered || isCollapsed)
        moreButton.isHidden = isNote || !isHovered || isRenaming
        chevron.image = (isCollapsed ? Symbol.forward : Symbol.disclosure).image(pointSize: 9, weight: .medium,
                                                                                 accessibilityDescription: chevron.accessibilityLabel())
    }

    @objc private func toggle() { onToggle?() }
    @objc private func more() { onMore?(moreButton) }

    /// The name's frame (a click there renames).
    var nameRect: NSRect { nameField.frame }

    // MARK: Rename (spec §B: click the name to rename inline)

    func beginRename() {
        guard let window, !isRenaming else { return }
        isRenaming = true
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.focusRingType = .none
        updateChevron()
        window.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    private func endRename(committed: Bool) {
        guard isRenaming else { return }
        isRenaming = false
        let text = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.drawsBackground = false
        nameField.stringValue = spaceName
        updateChevron()
        onRenameEnded?(committed && !text.isEmpty ? text : nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            endRename(committed: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(committed: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { endRename(committed: true) }

    override func layout() {
        super.layout()
        var x = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        let height = ceil(nameField.cell?.cellSize.height ?? 16)
        let y = ((bounds.height - height) / 2).rounded()
        if !iconField.stringValue.isEmpty {
            let width = ceil(iconField.cell?.cellSize.width ?? 16)
            iconField.frame = NSRect(x: x, y: y, width: width, height: height)
            iconImage.frame = .zero
            x += width + SidebarMetrics.faviconTitleGap
        } else if iconImage.image != nil {
            let side = SidebarMetrics.faviconSize
            iconImage.frame = NSRect(x: x, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            iconField.frame = .zero
            x += side + SidebarMetrics.faviconTitleGap
        } else {
            iconField.frame = .zero
            iconImage.frame = .zero
        }
        let chevronSize = SidebarMetrics.chevronSize
        let trailing = bounds.width - SidebarMetrics.rowHorizontalInset - Spacing.xs
        chevron.frame = NSRect(x: trailing - chevronSize, y: (bounds.height - chevronSize) / 2, width: chevronSize, height: chevronSize)
        moreButton.frame = chevron.frame.offsetBy(dx: -chevronSize, dy: 0)
        let nameWidth = ceil(nameField.cell?.cellSize.width ?? 0)
        nameField.frame = NSRect(x: x, y: y, width: max(0, min(isRenaming ? .greatestFiniteMagnitude : nameWidth + 2,
                                                                moreButton.frame.minX - x)), height: height)
    }
}

/// The 1 px line between Pinned and Today with "Clear" on the right (spec §A.7).
final class SeparatorCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("separator")

    private let line = NSBox()
    let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        line.boxType = .separator
        clearButton.isBordered = false
        clearButton.font = Typography.secondary
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.setAccessibilityIdentifier("clear-today")
        clearButton.toolTip = "Clear Today Tabs (⇧⌘K)"
        addSubview(line)
        addSubview(clearButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(todayCount: Int) {
        clearButton.isHidden = todayCount == 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        let buttonWidth = clearButton.isHidden ? 0 : ceil(clearButton.fittingSize.width)
        let trailing = bounds.width - inset
        clearButton.frame = NSRect(x: trailing - buttonWidth, y: 0, width: buttonWidth, height: bounds.height)
        let lineEnd = clearButton.isHidden ? trailing : trailing - buttonWidth - Spacing.s
        line.frame = NSRect(x: inset, y: (bounds.height / 2).rounded(), width: max(0, lineEnd - inset), height: 1)
    }
}

/// "+ New Tab" under the Today tabs (Dia's row).
final class NewTabCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("new-tab")

    private let icon = NSImageView()
    private let label = makeLabel(font: Typography.row, color: .secondaryLabelColor)

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        icon.image = Symbol.newTab.image(pointSize: 12)
        icon.contentTintColor = .secondaryLabelColor
        label.stringValue = "New Tab"
        setAccessibilityLabel("New Tab")
        addSubview(icon)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let size = SidebarMetrics.faviconSize
        let x = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset
        icon.frame = NSRect(x: x, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
        let height = ceil(label.cell?.cellSize.height ?? 16)
        let titleX = x + size + SidebarMetrics.faviconTitleGap
        label.frame = NSRect(x: titleX, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - titleX - x), height: height)
    }
}
