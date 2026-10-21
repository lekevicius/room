import AppKit
import Design
import Model

/// One pane of a split as its segment in the group row shows it.
struct SplitSegmentModel {
    var entry: Entry
    var page: EntryPageState
    var isChanged: Bool
}

/// Everything a split's group row shows (spec §D).
struct SplitRowModel {
    var group: UUID
    var segments: [SplitSegmentModel]
    /// The focused pane, when the split is selected: its segment is tinted.
    var focused: UUID?
    /// Folder levels above the row.
    var depth: Int
}

/// A split's one row in the sidebar (spec §D): each pane's favicon, and its
/// title while the segment is wide enough, side by side with 1 pt dividers;
/// the focused pane's segment is tinted. A click on a segment focuses that
/// pane (`member(at:)`); the controller handles the rest.
final class SplitGroupCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("split-group")

    private(set) var model: SplitRowModel?
    private var icons: [FaviconView] = []
    private var titles: [NSTextField] = []
    private var dividers: [CALayer] = []
    /// Settings ▸ Appearance ▸ Sidebar text (5.3b).
    private var textScale = TextScaleApplied()
    private let focusTint = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        wantsLayer = true
        focusTint.actions = CALayer.noImplicitActions
        focusTint.cornerRadius = Radius.small
        focusTint.cornerCurve = .continuous
        focusTint.isHidden = true
        layer?.addSublayer(focusTint)
        setAccessibilityIdentifier("split-row")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ model: SplitRowModel) {
        self.model = model
        if textScale.needsUpdate() { for title in titles { title.font = Typography.sidebarRow } }
        let count = model.segments.count
        while icons.count < count {
            let icon = FaviconView()
            let title = NSTextField(labelWithString: "")
            title.font = Typography.sidebarRow
            title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1
            icons.append(icon)
            titles.append(title)
            addSubview(icon)
            addSubview(title)
            let line = CALayer()
            line.actions = CALayer.noImplicitActions
            dividers.append(line)
            layer?.addSublayer(line)
        }
        for (index, segment) in model.segments.enumerated() {
            let icon = icons[index]
            icon.isHidden = false
            icon.image = segment.page.favicon
            icon.letterSource = EntryLabel.domain(segment.entry.currentURL) ?? EntryLabel.title(segment.entry)
            icon.customIcon = segment.entry.customIcon
            icon.isLoading = segment.page.isLoading
            icon.isUnloaded = !segment.page.isLoaded
            icon.showsChangedDot = segment.isChanged
            titles[index].stringValue = EntryLabel.title(segment.entry)
            titles[index].textColor = segment.page.isLoaded ? .labelColor : Palette.sidebarSecondaryLabel
        }
        for index in count..<icons.count {
            icons[index].isHidden = true
            titles[index].isHidden = true
        }
        setAccessibilityLabel("Split view: " + model.segments.map { EntryLabel.title($0.entry) }.joined(separator: ", "))
        toolTip = model.segments.map { EntryLabel.title($0.entry) }.joined(separator: " · ")
        needsLayout = true
        updateLayer()
    }

    /// The pane whose segment is under `point` (cell coordinates).
    func member(at point: NSPoint) -> UUID? {
        guard let model else { return nil }
        let frames = segmentFrames
        let index = frames.firstIndex { $0.minX <= point.x && point.x < $0.maxX + SplitMetrics.dividerWidth }
            ?? (point.x < (frames.first?.minX ?? 0) ? 0 : frames.count - 1)
        return model.segments.indices.contains(index) ? model.segments[index].entry.id : nil
    }

    /// Equal segments across the row's content, inside the pill.
    var segmentFrames: [NSRect] {
        let count = model?.segments.count ?? 0
        guard count > 0 else { return [] }
        let leading = SidebarMetrics.rowHorizontalInset + Spacing.xs + CGFloat(model?.depth ?? 0) * SidebarMetrics.folderIndent
        let trailing = bounds.width - SidebarMetrics.rowHorizontalInset - Spacing.xs
        let gap = SplitMetrics.dividerWidth
        let width = (trailing - leading - gap * CGFloat(count - 1)) / CGFloat(count)
        let inset = SidebarMetrics.pillVerticalInset + 3
        return (0..<count).map { index in
            NSRect(x: (leading + CGFloat(index) * (width + gap)).rounded(), y: inset, width: width.rounded(.down), height: bounds.height - 2 * inset)
        }
    }

    override func layout() {
        super.layout()
        let frames = segmentFrames
        let size = SidebarMetrics.faviconSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, frame) in frames.enumerated() {
            let showsTitle = frame.width >= SplitMetrics.segmentTitleMinWidth
            let iconX = showsTitle ? frame.minX + Spacing.s : (frame.midX - size / 2).rounded()
            icons[index].frame = NSRect(x: iconX, y: ((bounds.height - size) / 2).rounded(), width: size, height: size)
            titles[index].isHidden = !showsTitle
            if showsTitle {
                let height = ceil(titles[index].cell?.cellSize.height ?? 16)
                let x = icons[index].frame.maxX + SidebarMetrics.faviconTitleGap
                titles[index].frame = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, frame.maxX - Spacing.xs - x), height: height)
            }
            if index < dividers.count {
                dividers[index].isHidden = index == frames.count - 1
                dividers[index].frame = NSRect(x: frame.maxX, y: frame.minY + 4, width: Hairline.width(in: self), height: frame.height - 8)
            }
        }
        for index in frames.count..<dividers.count { dividers[index].isHidden = true }
        if let model, let focused = model.focused, let index = model.segments.firstIndex(where: { $0.entry.id == focused }) {
            focusTint.isHidden = false
            focusTint.frame = frames[index]
        } else {
            focusTint.isHidden = true
        }
        CATransaction.commit()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            focusTint.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(SplitMetrics.focusedSegmentAlpha).cgColor
            for line in dividers { line.backgroundColor = Palette.hairline.cgColor }
        }
    }
}
