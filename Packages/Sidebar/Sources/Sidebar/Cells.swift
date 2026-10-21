import AppKit
import Design
import Model

/// What a row's buttons and inline rename report back.
protocol EntryRowActions: AnyObject {
    func resetButtonClicked(_ entry: UUID)
    func closeButtonClicked(_ entry: UUID)
    func audioButtonClicked(_ entry: UUID)
    /// VoiceOver's press on the row (5.3a): what a click does (select; a folder opens or closes).
    func rowPressed(_ entry: UUID)
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
private func makeIconButton(_ symbol: Symbol, style: IconStyle, label: String) -> NSButton {
    let button = NSButton(image: symbol.image(style, accessibilityDescription: label) ?? NSImage(),
                          target: nil, action: nil)
    button.isBordered = false
    button.bezelStyle = .accessoryBarAction
    button.imagePosition = .imageOnly
    button.contentTintColor = Palette.sidebarSecondaryLabel
    button.setAccessibilityLabel(label)
    button.toolTip = label
    return button
}

extension NSTextField {
    /// Ends text too long for the field with a `titleFadeWidth` fade instead
    /// of an ellipsis (the Room Browser design); `enabled` false (an inline
    /// rename) or text that fits shows it whole. The field must clip.
    func updateTrailingFade(enabled: Bool = true) {
        let fade = SidebarMetrics.titleFadeWidth
        let overflows = (cell?.cellSize.width ?? 0) > bounds.width
        guard enabled, overflows, bounds.width > fade else {
            layer?.mask = nil
            return
        }
        wantsLayer = true
        let mask = layer?.mask as? CAGradientLayer ?? CAGradientLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double((bounds.width - fade) / bounds.width)), 1]
        layer?.mask = mask
        CATransaction.commit()
    }
}

/// An entry or folder row: icon, title, hover sublabel, and on the trailing
/// side the audio indicator and (Today tabs) the close button.
final class EntryCellView: NSTableCellView, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("entry")

    weak var actions: EntryRowActions?
    private(set) var model: EntryRowModel?

    let favicon = FaviconView()
    private let folderIcon = NSImageView()
    let titleField = makeLabel(font: Typography.sidebarRow, color: .labelColor)
    private let sublabel = makeLabel(font: Typography.sidebarSecondary, color: Palette.sidebarSecondaryLabel)
    /// The text size last applied (Settings ▸ Appearance ▸ Sidebar text, 5.3b).
    private var textScale = TextScaleApplied()
    private let resetButton = makeIconButton(.resetPinned, style: .rowAction, label: "Back to pinned URL")
    private let closeButton: NSButton = {
        let button = HoverButton()
        button.layer?.cornerRadius = SidebarMetrics.rowButtonCornerRadius
        button.contentTintColor = .labelColor
        button.image = Symbol.closeTab.image(.rowButton, accessibilityDescription: "Close Tab")
        button.setAccessibilityLabel("Close Tab")
        button.toolTip = "Close Tab"
        return button
    }()
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
    /// The entry the hover state was last shown for (a reused cell's first state never fades).
    private var hoverEntryID: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        wantsLayer = true
        textField = titleField
        titleField.delegate = self
        // A long title fades out over its last points (`updateTrailingFade`).
        titleField.lineBreakMode = .byClipping
        titleField.cell?.truncatesLastVisibleLine = false
        folderIcon.imageScaling = .scaleNone
        folderIcon.contentTintColor = Palette.sidebarSecondaryLabel
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
        readerIndicator.contentTintColor = Palette.sidebarSecondaryLabel
        readerIndicator.image = Symbol.readerMode.image(.rowAction, accessibilityDescription: "Reader mode")
        readerIndicator.toolTip = "Reader mode (⌥⇧⌘R or Esc to exit)"
        readerIndicator.setAccessibilityIdentifier("row-reader")
        // The row's value says what these show (`EntryAccessibility`); the title's text stays for an inline rename.
        folderIcon.hideFromAccessibility()
        favicon.hideFromAccessibility()
        captureIndicator.hideFromAccessibility()
        readerIndicator.hideFromAccessibility()
        for view in [favicon, folderIcon, titleField, sublabel, resetButton, closeButton, audioButton, captureIndicator, readerIndicator] as [NSView] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ model: EntryRowModel) {
        if textScale.needsUpdate() {
            titleField.font = Typography.sidebarRow
            sublabel.font = Typography.sidebarSecondary
        }
        let previous = self.model
        self.model = model
        let entry = model.entry
        let isFolder = entry.kind == .folder
        favicon.isHidden = isFolder
        folderIcon.isHidden = !isFolder
        if isFolder {
            let open = !entry.isCollapsed
            folderIcon.image = (open ? Symbol.folderOpen : Symbol.folder).image(.folder)
        } else {
            favicon.image = model.page.favicon
            favicon.letterSource = EntryLabel.domain(entry.currentURL) ?? EntryLabel.title(entry)
            favicon.isLoading = model.page.isLoading
            favicon.showsChangedDot = model.isChanged
            let unloaded = !model.page.isLoaded
            favicon.isUnloaded = unloaded
            if previous?.entry.id == entry.id, previous?.isChanged == true, !model.isChanged, SidebarMotion.resetCrossfade.animates {
                // Reset: crossfade back to the stored icon (spec §A.5).
                favicon.layer?.add(Self.fade(Motion.resetCrossfade), forKey: "reset")
            } else if previous?.entry.id == entry.id, previous?.isChanged == false, model.isChanged, SidebarMotion.changedDot.animates {
                // The page left the pinned URL: the changed dot fades in (spec §I.8).
                favicon.layer?.add(Self.fade(Motion.fast), forKey: "changed")
            }
        }
        if !isRenaming { titleField.stringValue = EntryLabel.title(entry) }
        titleField.textColor = (isFolder || model.page.isLoaded) ? .labelColor
            : Palette.sidebarUnloadedLabel
        let audible = model.page.isAudible || model.page.isMuted
        audioButton.isHidden = !audible
        if audible {
            // Differentiate Without Colour (5.3b): the glyph inside a circle (`AudioGlyph`).
            let symbol = AudioGlyph.symbol(muted: model.page.isMuted)
            let label = model.page.isMuted ? "Unmute Tab" : "Mute Tab"
            audioButton.image = symbol.image(.rowButton, accessibilityDescription: label)
            audioButton.toolTip = label
            audioButton.setAccessibilityLabel(label)
            audioButton.removeAllSymbolEffects()
            if model.page.isAudible, !model.page.isMuted, SidebarMotion.audioIndicator.animates {
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
            captureIndicator.image = symbol.image(.rowAction, accessibilityDescription: label)
            captureIndicator.toolTip = label
            captureIndicator.setAccessibilityLabel(label)
        }
        readerIndicator.isHidden = !model.page.isReader
        // The title, then the kind and states (`EntryAccessibility`): in the label, because the outline's cell
        // element passes a cell view's label through but not its value (5.3a, read back from the tree).
        setAccessibilityLabel(EntryLabel.title(entry) + ", " + EntryAccessibility.value(kind: entry.kind, isCollapsed: entry.isCollapsed,
                                                                                        page: model.page, isSelected: model.isSelected,
                                                                                        isChanged: model.isChanged))
        setAccessibilityCustomActions(EntryAccessibility.actionNames(kind: entry.kind, page: model.page, isChanged: model.isChanged).map { name in
            NSAccessibilityCustomAction(name: name) { [weak self] in self?.performAction(named: name) ?? false }
        })
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

    /// A crossfade of a layer's changes in the current transaction.
    static func fade(_ duration: TimeInterval) -> CATransition {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        return fade
    }

    private func updateHoverState() {
        guard let model else { return }
        let entry = model.entry
        let showReset = isHovered && model.isChanged
        if showReset == resetButton.isHidden, hoverEntryID == entry.id, SidebarMotion.resetIconSwap.animates {
            // The favicon and the reset icon swap with the hover's other changes (spec §I.4, §I.8; hover fades).
            layer?.add(Self.fade(Motion.fast), forKey: "hover-swap")
        }
        hoverEntryID = entry.id
        resetButton.isHidden = !showReset
        favicon.isHidden = entry.kind == .folder || showReset
        closeButton.isHidden = !(isHovered && entry.kind == .today) || isRenaming
        // Sublabel: over the reset icon, what clicking it does (⌘ swaps it);
        // elsewhere on a changed entry, the live page's title (spec §I.3, §I.4).
        let text = HoverSublabel.text(hovered: isHovered, changed: model.isChanged, onIcon: isHoveringIcon, command: isCommandHeld,
                                      selected: model.isSelected, currentTitle: EntryLabel.currentTitle(entry))
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
        // The folder glyph is wider than a favicon (B-115), centred where the favicon's centre is.
        let glyph = SidebarMetrics.folderGlyphSize
        folderIcon.frame = NSRect(x: (icon.midX - glyph.width / 2).rounded(), y: (icon.midY - glyph.height / 2).rounded(),
                                  width: glyph.width, height: glyph.height)
        resetButton.frame = icon.insetBy(dx: -2, dy: -2)
        // Buttons and indicators line up from the pill's trailing edge; the
        // title ends `Spacing.s` before the pill's edge, or `Spacing.xs` before the first of them.
        var trailing = bounds.width - SidebarMetrics.rowHorizontalInset - SidebarMetrics.closeButtonInset
        let button = SidebarMetrics.closeButtonSize
        var titleEnd = bounds.width - SidebarMetrics.rowHorizontalInset - Spacing.s
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: trailing - button, y: ((bounds.height - button) / 2).rounded(), width: button, height: button)
            trailing -= button
            titleEnd = trailing - Spacing.xs
        }
        if !captureIndicator.isHidden {
            let width = SidebarMetrics.audioIndicatorWidth
            captureIndicator.frame = NSRect(x: trailing - width, y: (bounds.height - button) / 2, width: width, height: button)
            trailing -= width
            titleEnd = trailing - Spacing.xs
        }
        if !readerIndicator.isHidden {
            let width = SidebarMetrics.audioIndicatorWidth
            readerIndicator.frame = NSRect(x: trailing - width, y: (bounds.height - button) / 2, width: width, height: button)
            trailing -= width
            titleEnd = trailing - Spacing.xs
        }
        var x = icon.maxX + SidebarMetrics.faviconTitleGap
        // The audio button sits between the favicon and the title (the Room Browser design).
        if !audioButton.isHidden {
            let side = SidebarMetrics.audioIndicatorWidth
            audioButton.frame = NSRect(x: x, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
            x = audioButton.frame.maxX + Spacing.s
        }
        let width = max(0, titleEnd - x)
        let titleHeight = ceil(titleField.cell?.cellSize.height ?? 16)
        if sublabel.isHidden {
            titleField.frame = NSRect(x: x, y: ((bounds.height - titleHeight) / 2).rounded(), width: width, height: titleHeight)
        } else {
            let subHeight = ceil(sublabel.cell?.cellSize.height ?? 13)
            let top = ((bounds.height - titleHeight - subHeight) / 2).rounded()
            titleField.frame = NSRect(x: x, y: top, width: width, height: titleHeight)
            sublabel.frame = NSRect(x: x, y: top + titleHeight, width: width, height: subHeight)
        }
        titleField.updateTrailingFade(enabled: !isRenaming)
    }

    // MARK: Buttons

    @objc private func resetClicked() { model.map { actions?.resetButtonClicked($0.entry.id) } }
    /// Spikes (B-109): whether the row's close button shows.
    var debugCloseButtonShown: Bool { !closeButton.isHidden }

    @objc private func closeClicked() { model.map { actions?.closeButtonClicked($0.entry.id) } }

    /// A VoiceOver action (`EntryAccessibility.actionNames`): the hover button's click.
    private func performAction(named name: String) -> Bool {
        guard let id = model?.entry.id else { return false }
        switch name {
        case "Close Tab": actions?.closeButtonClicked(id)
        case "Back to Pinned URL": actions?.resetButtonClicked(id)
        case "Mute Tab", "Unmute Tab": actions?.audioButtonClicked(id)
        default: return false
        }
        return true
    }

    override func accessibilityPerformPress() -> Bool {
        guard let id = model?.entry.id else { return false }
        actions?.rowPressed(id)
        return true
    }
    @objc private func audioClicked() { model.map { actions?.audioButtonClicked($0.entry.id) } }

    // MARK: Rename (spec §I.9)

    func beginRename() {
        guard let model, let window else { return }
        isRenaming = true
        titleField.updateTrailingFade(enabled: false)
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
        needsLayout = true
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
    private var hovering = false { didSet { if hovering != oldValue { updateFill() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleNone
        contentTintColor = .labelColor
        // The view is the element, a button (5.3a): an image view's cell would read as an image.
        cell?.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        wantsLayer = true
        layer?.cornerRadius = SidebarMetrics.rowButtonCornerRadius
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    /// The hover square, as the close button's (the Room Browser design).
    private func updateFill() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = hovering ? Palette.sidebarHover.cgColor : nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovering = false
    }

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

    private let iconField = makeLabel(font: Typography.sidebarSpaceTitle, color: Palette.sidebarSecondaryLabel)
    private let iconImage = NSImageView()
    private let nameField = makeLabel(font: Typography.sidebarSpaceTitle, color: .labelColor)
    private var textScale = TextScaleApplied()

    /// Settings ▸ Appearance ▸ Sidebar text (5.3b).
    private func applyTextScale() {
        guard textScale.needsUpdate() else { return }
        iconField.font = Typography.sidebarSpaceTitle
        nameField.font = Typography.sidebarSpaceTitle
    }
    let chevron = makeIconButton(.disclosure, style: .rowChevron, label: "Collapse Pinned")
    let moreButton = makeIconButton(.more, style: .rowAction, label: "Space Menu")
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
        iconImage.contentTintColor = Palette.sidebarSecondaryLabel
        // The row's label is the space's name: its icon and the name's text say it again.
        iconImage.hideFromAccessibility()
        iconField.hideFromAccessibility()
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
        applyTextScale()
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
                .withSymbolConfiguration(IconStyle.spaceTitle.configuration)
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
        applyTextScale()
        isNote = true
        spaceName = text
        nameField.stringValue = text
        nameField.textColor = Palette.sidebarSecondaryLabel
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
        chevron.image = (isCollapsed ? Symbol.forward : Symbol.disclosure).image(.rowChevron,
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

    private let line = HairlineView()
    let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private var textScale = TextScaleApplied()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        clearButton.isBordered = false
        clearButton.font = Typography.sidebarSecondary
        clearButton.contentTintColor = Palette.sidebarSecondaryLabel
        clearButton.setAccessibilityIdentifier("clear-today")
        clearButton.toolTip = "Clear Today Tabs (⇧⌘K)"
        addSubview(line)
        addSubview(clearButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(todayCount: Int) {
        if textScale.needsUpdate() { clearButton.font = Typography.sidebarSecondary }
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
        line.frame = NSRect(x: inset, y: (bounds.height / 2).rounded(), width: max(0, lineEnd - inset), height: line.thickness)
    }
}

/// "+ New Tab" under the Today tabs (Dia's row).
final class NewTabCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("new-tab")

    private let icon = NSImageView()
    private let label = makeLabel(font: Typography.sidebarRow, color: Palette.sidebarSecondaryLabel)
    private var textScale = TextScaleApplied()

    /// Settings ▸ Appearance ▸ Sidebar text (5.3b).
    func configure() {
        guard textScale.needsUpdate() else { return }
        label.font = Typography.sidebarRow
        needsLayout = true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        icon.image = Symbol.newTab.image(.rowGlyph)
        icon.contentTintColor = Palette.sidebarSecondaryLabel
        label.stringValue = "New Tab"
        setAccessibilityLabel("New Tab")
        icon.hideFromAccessibility()
        label.hideFromAccessibility()
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

/// A changed permanent row's hover sublabel (spec §I.3, §I.4): over the
/// reset icon, what a click on it does; elsewhere on the row, the live page's
/// title. ⌘ separates only the selected entry's page (`resetButtonClicked`),
/// so on another row the ⌘ label stays "Back to pinned URL" (5.5b: it said
/// "Separate" while the click reset).
enum HoverSublabel {
    static let reset = "Back to pinned URL"
    static let separate = "Separate from pinned tab"

    static func text(hovered: Bool, changed: Bool, onIcon: Bool, command: Bool, selected: Bool, currentTitle: String?) -> String? {
        guard hovered, changed else { return nil }
        if onIcon { return command && selected ? separate : reset }
        return currentTitle
    }
}
