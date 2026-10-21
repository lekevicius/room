import AppKit
import Design

/// What the footer's media row shows (spec §F, §I.5; 4.6): the page that
/// plays (or holds a paused media session) and is not on screen.
public struct MediaRowContent: Equatable {
    public var entry: UUID
    public var title: String
    /// The artist, else the page's host.
    public var subtitle: String
    /// The session's artwork, else the page's favicon.
    public var image: NSImage?
    public var isPlaying: Bool
    /// The page handles "nexttrack".
    public var canGoNext: Bool

    public init(entry: UUID, title: String, subtitle: String, image: NSImage?, isPlaying: Bool, canGoNext: Bool) {
        self.entry = entry
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.isPlaying = isPlaying
        self.canGoNext = canGoNext
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.image === rhs.image
            && lhs.isPlaying == rhs.isPlaying && lhs.canGoNext == rhs.canGoNext
    }
}

/// What a click on the media row asks for.
public enum MediaRowAction: String, Sendable {
    case playPause, next, dismiss, select
}

/// One AppKit row above the footer: the image, title and subtitle, then
/// play/pause, next and ×. A click elsewhere on the row selects its entry.
final class MediaRowView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    let playButton = HoverButton()
    let nextButton = HoverButton()
    let closeButton = HoverButton()
    private(set) var content: MediaRowContent?
    var onAction: ((MediaRowAction) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = MediaRowMetrics.imageCornerRadius
        imageView.layer?.masksToBounds = true
        for label in [titleLabel, subtitleLabel] {
            label.font = Typography.secondary
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.cell?.truncatesLastVisibleLine = true
        }
        titleLabel.textColor = .labelColor
        subtitleLabel.textColor = .secondaryLabelColor
        for (button, symbol, label, action) in [
            (playButton, Symbol.pause, "Pause", #selector(playPauseClicked)),
            (nextButton, Symbol.nextTrack, "Next Track", #selector(nextClicked)),
            (closeButton, Symbol.closeTab, "Hide", #selector(closeClicked)),
        ] {
            button.image = symbol.image(.media, accessibilityDescription: label)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = .secondaryLabelColor
            button.toolTip = label
            button.target = self
            button.action = action
            addSubview(button)
        }
        playButton.setAccessibilityIdentifier("media-row-play")
        nextButton.setAccessibilityIdentifier("media-row-next")
        closeButton.setAccessibilityIdentifier("media-row-close")
        setAccessibilityIdentifier("media-row")
        addSubview(imageView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func configure(_ content: MediaRowContent) {
        self.content = content
        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle
        subtitleLabel.isHidden = content.subtitle.isEmpty
        imageView.image = content.image ?? Symbol.audible.image(.media, accessibilityDescription: nil)
        let (symbol, label) = content.isPlaying ? (Symbol.pause, "Pause") : (Symbol.play, "Play")
        playButton.image = symbol.image(.media, accessibilityDescription: label)
        playButton.toolTip = label
        nextButton.isEnabled = content.canGoNext
        toolTip = content.subtitle.isEmpty ? content.title : "\(content.title) — \(content.subtitle)"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = MediaRowMetrics.imageSize, button = MediaRowMetrics.buttonSize
        let inset = SidebarMetrics.rowContentInset - SidebarMetrics.rowHorizontalInset
        imageView.frame = NSRect(x: inset, y: (bounds.height - size) / 2, width: size, height: size)
        var x = bounds.width - inset
        for view in [closeButton, nextButton, playButton] {
            x -= button
            view.frame = NSRect(x: x, y: (bounds.height - button) / 2, width: button, height: button)
        }
        let textX = imageView.frame.maxX + SidebarMetrics.faviconTitleGap
        let textWidth = max(0, x - Spacing.xs - textX)
        let lineHeight = ceil(titleLabel.fittingSize.height)
        if subtitleLabel.isHidden {
            titleLabel.frame = NSRect(x: textX, y: (bounds.height - lineHeight) / 2, width: textWidth, height: lineHeight)
        } else {
            let top = (bounds.height - 2 * lineHeight) / 2
            titleLabel.frame = NSRect(x: textX, y: top, width: textWidth, height: lineHeight)
            subtitleLabel.frame = NSRect(x: textX, y: top + lineHeight, width: textWidth, height: lineHeight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Buttons take their own clicks; the rest of the row selects the entry.
        onAction?(.select)
    }

    override func updateLayer() {
        layer?.backgroundColor = Palette.sidebarHover.cgColor
        layer?.cornerRadius = Radius.small
    }

    override var wantsUpdateLayer: Bool { true }

    @objc private func playPauseClicked() { onAction?(.playPause) }
    @objc private func nextClicked() { onAction?(.next) }
    @objc private func closeClicked() { onAction?(.dismiss) }
}

// MARK: - The sidebar's media row

extension SidebarController {
    /// Shows the media row with `content`, or hides it (`nil`).
    public func setMediaRow(_ content: MediaRowContent?) {
        if bodyView.mediaRowView == nil {
            mediaRow.isHidden = true
            mediaRow.onAction = { [weak self] action in
                guard let self, let entry = mediaRow.content?.entry else { return }
                onMediaRowAction?(action, entry)
            }
            bodyView.mediaRowView = mediaRow
        }
        let hidden = content == nil
        if let content, content != mediaRow.content || mediaRow.isHidden { mediaRow.configure(content) }
        guard mediaRow.isHidden != hidden else { return }
        mediaRow.isHidden = hidden
        bodyView.needsLayout = true
    }

    /// What the media row shows (`nil` while hidden).
    public var mediaRowContent: MediaRowContent? { mediaRow.isHidden ? nil : mediaRow.content }

    /// The media row's frame in window coordinates (spikes and captures).
    public var mediaRowFrameInWindow: NSRect? {
        mediaRow.isHidden || mediaRow.window == nil ? nil : mediaRow.convert(mediaRow.bounds, to: nil)
    }

    /// Selects `id` and shows its space when it is another one (a click on
    /// the media row; an essential is selected in the shown space).
    public func reveal(_ id: UUID) {
        guard let entry = sidebar.entry(id) else { return }
        if let space = entry.spaceID, space != activeSpaceID {
            selectInBackground(id, space: space)
            showSpace(space)
        } else {
            select(id)
        }
    }

    /// Spikes: presses a media row button or the row itself as a click would.
    public func debugPressMediaRow(_ action: MediaRowAction) {
        switch action {
        case .playPause: mediaRow.playButton.performClick(nil)
        case .next: mediaRow.nextButton.performClick(nil)
        case .dismiss: mediaRow.closeButton.performClick(nil)
        case .select: mediaRow.onAction?(.select)
        }
    }
}
