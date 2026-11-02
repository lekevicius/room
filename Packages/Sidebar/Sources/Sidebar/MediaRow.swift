import AppKit
import Design

/// What the mini-player shows (spec §F, §I.5; 4.6; 5.13): the page that
/// plays (or holds a paused media session) and is not on screen.
public struct MediaRowContent: Equatable {
    public var entry: UUID
    public var title: String
    /// The artist, else the page's host.
    public var subtitle: String
    /// The session's artwork, else the page's favicon.
    public var image: NSImage?
    public var isPlaying: Bool
    /// The page handles "nexttrack" / "previoustrack".
    public var canGoNext: Bool
    public var canGoPrevious: Bool
    public var isMuted: Bool
    /// The session's position as the engine reported it at `positionDate` (`nil`: no progress row).
    public var position: Position?

    public struct Position: Equatable, Sendable {
        public var duration: TimeInterval
        public var elapsed: TimeInterval
        /// 0 while paused.
        public var rate: Double
        public var date: Date

        public init(duration: TimeInterval, elapsed: TimeInterval, rate: Double, date: Date) {
            self.duration = duration
            self.elapsed = elapsed
            self.rate = rate
            self.date = date
        }

        /// Where playback is at `now`, inside the duration.
        public func elapsed(at now: Date) -> TimeInterval {
            min(max(0, elapsed + rate * now.timeIntervalSince(date)), duration)
        }
    }

    public init(entry: UUID, title: String, subtitle: String, image: NSImage?, isPlaying: Bool, canGoNext: Bool,
                canGoPrevious: Bool = false, isMuted: Bool = false, position: Position? = nil) {
        self.entry = entry
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.isPlaying = isPlaying
        self.canGoNext = canGoNext
        self.canGoPrevious = canGoPrevious
        self.isMuted = isMuted
        self.position = position
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle && lhs.image === rhs.image
            && lhs.isPlaying == rhs.isPlaying && lhs.canGoNext == rhs.canGoNext && lhs.canGoPrevious == rhs.canGoPrevious
            && lhs.isMuted == rhs.isMuted && lhs.position == rhs.position
    }

    /// "2:36", "1:02:09".
    public static func time(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// What a click on the mini-player asks for.
public enum MediaRowAction: Equatable, Sendable {
    case playPause, next, previous, dismiss, select, toggleMute, pictureInPicture
    /// A click on the progress bar: the position in seconds.
    case seek(TimeInterval)
}

/// The mini-player (5.13, the user's design from Dia's): a Liquid Glass card. Collapsed: the
/// artwork, the title (scrolling when it does not fit) and play/pause. Under the pointer it grows
/// upward over the list (`isExpanded`; the list keeps ending above the collapsed card): the
/// artist, ×, the elapsed and total time around a bar that seeks, then volume, previous,
/// play/pause, next and picture-in-picture. A click elsewhere on the card selects its entry.
final class MediaRowView: NSView {
    private let glass = NSGlassEffectView()
    private let imageView = NSImageView()
    private let titleLabel = MarqueeLabel()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")
    private let progress = MediaProgressView()
    let playButton = HoverButton()
    let nextButton = HoverButton()
    let previousButton = HoverButton()
    let muteButton = HoverButton()
    let pictureInPictureButton = HoverButton()
    let closeButton = HoverButton()
    private(set) var content: MediaRowContent?
    var onAction: ((MediaRowAction) -> Void)?
    /// The card grew or shrank: the owner lays it out again (animated).
    var onExpansionChange: (() -> Void)?
    private(set) var isExpanded = false
    private var collapseWork: DispatchWorkItem?
    private var ticker: Task<Void, Never>?

    /// The views only the expanded card shows.
    private var expandedViews: [NSView] {
        [subtitleLabel, closeButton, elapsedLabel, totalLabel, progress, muteButton, previousButton, nextButton, pictureInPictureButton]
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.style = .regular
        glass.cornerRadius = MediaRowMetrics.cornerRadius
        addSubview(glass)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = MediaRowMetrics.imageCornerRadius
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        subtitleLabel.font = Typography.secondary
        subtitleLabel.textColor = Palette.sidebarSecondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        for label in [elapsedLabel, totalLabel] {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = Palette.sidebarSecondaryLabel
        }
        totalLabel.alignment = .right
        progress.onSeek = { [weak self] fraction in
            guard let duration = self?.content?.position?.duration else { return }
            self?.onAction?(.seek(fraction * duration))
        }
        for (button, symbol, style, label, action) in [
            (playButton, Symbol.pause, IconStyle.playerMain, "Pause", #selector(playPauseClicked)),
            (nextButton, Symbol.nextTrack, IconStyle.player, "Next Track", #selector(nextClicked)),
            (previousButton, Symbol.previousTrack, IconStyle.player, "Previous Track", #selector(previousClicked)),
            (muteButton, Symbol.playerVolume, IconStyle.player, "Mute", #selector(muteClicked)),
            (pictureInPictureButton, Symbol.pictureInPicture, IconStyle.player, "Picture in Picture", #selector(pictureInPictureClicked)),
            (closeButton, Symbol.closeTab, IconStyle.media, "Hide", #selector(closeClicked)),
        ] {
            button.image = symbol.image(style, accessibilityDescription: label)
            button.contentTintColor = .labelColor
            button.setTip(label)
            button.target = self
            button.action = action
        }
        closeButton.contentTintColor = Palette.sidebarSecondaryLabel
        playButton.setAccessibilityIdentifier("media-row-play")
        nextButton.setAccessibilityIdentifier("media-row-next")
        previousButton.setAccessibilityIdentifier("media-row-previous")
        muteButton.setAccessibilityIdentifier("media-row-mute")
        pictureInPictureButton.setAccessibilityIdentifier("media-row-pip")
        closeButton.setAccessibilityIdentifier("media-row-close")
        setAccessibilityIdentifier("media-row")
        for view in [imageView, titleLabel, playButton] + expandedViews { addSubview(view) }
        for view in expandedViews { view.alphaValue = 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The card's height now (the body view lays it out from the footer up).
    var preferredHeight: CGFloat { isExpanded ? MediaRowMetrics.expandedHeight : MediaRowMetrics.height }

    func configure(_ content: MediaRowContent) {
        self.content = content
        titleLabel.stringValue = content.title
        subtitleLabel.stringValue = content.subtitle
        imageView.image = content.image ?? Symbol.audible.image(.media, accessibilityDescription: nil)
        let (symbol, label) = content.isPlaying ? (Symbol.pause, "Pause") : (Symbol.play, "Play")
        playButton.image = symbol.image(.playerMain, accessibilityDescription: label)
        playButton.setTip(label)
        nextButton.isEnabled = content.canGoNext
        previousButton.isEnabled = content.canGoPrevious
        muteButton.image = (content.isMuted ? Symbol.playerMuted : Symbol.playerVolume)
            .image(.player, accessibilityDescription: content.isMuted ? "Unmute" : "Mute")
        muteButton.setTip(content.isMuted ? "Unmute" : "Mute")
        toolTip = content.subtitle.isEmpty ? content.title : "\(content.title) — \(content.subtitle)"
        setAccessibilityLabel(toolTip)
        updateProgress()
        updateTimer()
        needsLayout = true
    }

    // MARK: Expansion (the pointer)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        collapseWork?.cancel()
        setExpanded(true)
    }

    override func mouseExited(with event: NSEvent) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MediaRowMetrics.collapseDelay, execute: work)
    }

    /// Expands or collapses the card (spikes and captures call it too).
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        updateTimer()
        let animates = window != nil && SidebarMotion.mediaRowExpansion.animates
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animates ? Motion.fast : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // Reduce Motion: the card's height changes at once and its rows cross-fade.
            context.allowsImplicitAnimation = animates && SidebarMotion.mediaRowExpansion.variant == .full
            for view in expandedViews { (animates ? view.animator() : view).alphaValue = expanded ? 1 : 0 }
            onExpansionChange?()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
        if window == nil { collapseWork?.cancel(); isExpanded = false; for view in expandedViews { view.alphaValue = 0 } }
    }

    // MARK: Progress

    /// While the card shows a playing position, the elapsed time moves each half second.
    private func updateTimer() {
        let ticking = window != nil && !isHidden && (content?.position?.rate ?? 0) > 0
        if ticking, ticker == nil {
            // A main-actor task, not a `Timer` (whose block is @Sendable, CLAUDE.md).
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.updateProgress()
                }
            }
        } else if !ticking {
            ticker?.cancel()
            ticker = nil
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateTimer()
    }

    private func updateProgress() {
        guard let position = content?.position, position.duration > 0 else {
            elapsedLabel.stringValue = ""
            totalLabel.stringValue = ""
            progress.fraction = nil
            return
        }
        let elapsed = position.elapsed(at: Date())
        elapsedLabel.stringValue = MediaRowContent.time(elapsed)
        totalLabel.stringValue = MediaRowContent.time(position.duration)
        progress.fraction = elapsed / position.duration
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        glass.frame = bounds
        let pad = MediaRowMetrics.padding
        let button = MediaRowMetrics.buttonSize
        let expanded = bounds.height > (MediaRowMetrics.height + MediaRowMetrics.expandedHeight) / 2
        let image = expanded ? MediaRowMetrics.expandedImageSize : MediaRowMetrics.imageSize
        imageView.frame = NSRect(x: pad, y: pad, width: image, height: image)
        let textX = imageView.frame.maxX + SidebarMetrics.faviconTitleGap
        let lineHeight = ceil(titleLabel.fittingSize.height)
        if expanded {
            let close = MediaRowMetrics.closeSize
            closeButton.frame = NSRect(x: bounds.width - pad - close, y: pad - 2, width: close, height: close)
            let textWidth = max(0, closeButton.frame.minX - Spacing.xs - textX)
            let subHeight = ceil(subtitleLabel.fittingSize.height)
            let top = imageView.frame.midY - (lineHeight + subHeight) / 2
            titleLabel.frame = NSRect(x: textX, y: top.rounded(), width: textWidth, height: lineHeight)
            subtitleLabel.frame = NSRect(x: textX, y: (top + lineHeight).rounded(), width: textWidth, height: subHeight)
            playButton.frame = NSRect(x: (bounds.width - button) / 2, y: bounds.height - pad - button, width: button, height: button)
        } else {
            playButton.frame = NSRect(x: bounds.width - pad - button + 2, y: (bounds.height - button) / 2, width: button, height: button)
            titleLabel.frame = NSRect(x: textX, y: ((bounds.height - lineHeight) / 2).rounded(),
                                      width: max(0, playButton.frame.minX - Spacing.xs - textX), height: lineHeight)
            subtitleLabel.frame = titleLabel.frame.offsetBy(dx: 0, dy: lineHeight)
            closeButton.frame = NSRect(x: bounds.width - pad - MediaRowMetrics.closeSize, y: pad - 2,
                                       width: MediaRowMetrics.closeSize, height: MediaRowMetrics.closeSize)
        }
        // The progress row under the artwork, and the controls' row at the bottom.
        let controlsY = bounds.height - pad - button
        let progressY = imageView.frame.maxY + Spacing.xs
        let timeHeight = ceil(elapsedLabel.fittingSize.height)
        let time = MediaRowMetrics.timeWidth
        elapsedLabel.frame = NSRect(x: pad + 2, y: progressY, width: time, height: timeHeight)
        totalLabel.frame = NSRect(x: bounds.width - pad - 2 - time, y: progressY, width: time, height: timeHeight)
        progress.frame = NSRect(x: elapsedLabel.frame.maxX + Spacing.xs, y: progressY, width: max(0, totalLabel.frame.minX - Spacing.xs - elapsedLabel.frame.maxX - Spacing.xs),
                                height: timeHeight)
        let centre = bounds.width / 2
        let spacing = button + Spacing.m
        previousButton.frame = NSRect(x: centre - spacing - button / 2, y: controlsY, width: button, height: button)
        nextButton.frame = NSRect(x: centre + spacing - button / 2, y: controlsY, width: button, height: button)
        muteButton.frame = NSRect(x: pad, y: controlsY, width: button, height: button)
        pictureInPictureButton.frame = NSRect(x: bounds.width - pad - button, y: controlsY, width: button, height: button)
    }

    override func mouseDown(with event: NSEvent) {
        // Buttons and the bar take their own clicks; the rest of the card selects the entry.
        onAction?(.select)
    }

    @objc private func playPauseClicked() { onAction?(.playPause) }
    @objc private func nextClicked() { onAction?(.next) }
    @objc private func previousClicked() { onAction?(.previous) }
    @objc private func muteClicked() { onAction?(.toggleMute) }
    @objc private func pictureInPictureClicked() { onAction?(.pictureInPicture) }
    @objc private func closeClicked() { onAction?(.dismiss) }
}

/// The mini-player's progress: a rounded track and the elapsed part; a click seeks.
final class MediaProgressView: NSView {
    var onSeek: ((Double) -> Void)?
    var fraction: Double? {
        didSet { if fraction != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let height = MediaRowMetrics.progressHeight
        let track = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: track, xRadius: height / 2, yRadius: height / 2).fill()
        guard let fraction else { return }
        let played = NSRect(x: track.minX, y: track.minY, width: max(height, track.width * min(max(fraction, 0), 1)), height: height)
        NSColor.labelColor.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: played, xRadius: height / 2, yRadius: height / 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard fraction != nil, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        onSeek?(min(max(x / bounds.width, 0), 1))
    }
}

/// One line of text that scrolls back and forth when it does not fit (5.13: the mini-player's
/// title, as Dia's), its ends fading; text that fits stands still.
final class MarqueeLabel: NSView {
    private let field = NSTextField(labelWithString: "")
    private let fade = CAGradientLayer()

    var stringValue: String {
        get { field.stringValue }
        set {
            guard newValue != field.stringValue else { return }
            field.stringValue = newValue
            needsLayout = true
        }
    }

    var font: NSFont? {
        get { field.font }
        set { field.font = newValue; needsLayout = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        field.textColor = .labelColor
        field.lineBreakMode = .byClipping
        field.wantsLayer = true
        addSubview(field)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { NSSize(width: ceil(field.fittingSize.width), height: ceil(field.fittingSize.height)) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let size = fittingSize
        field.frame = NSRect(x: 0, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        let overflow = size.width - bounds.width
        field.layer?.removeAnimation(forKey: "marquee")
        fade.removeAnimation(forKey: "marquee")
        guard overflow > 0, bounds.width > 0, !Motion.reduceMotion else {
            layer?.mask = overflow > 0 ? edgeMask(leading: false) : nil
            return
        }
        // The leading edge fades only while the text is away from its start (it cut the first letter at rest).
        layer?.mask = edgeMask(leading: false)
        let rest = edgeColors(leading: false), scrolled = edgeColors(leading: true)
        let distance = overflow + SidebarMetrics.titleFadeWidth
        let travel = TimeInterval(distance / MediaRowMetrics.marqueeSpeed)
        let pause = MediaRowMetrics.marqueePause
        let total = 2 * (travel + pause)
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -distance, -distance, 0]
        scroll.keyTimes = [0, pause / total, (pause + travel) / total, (2 * pause + travel) / total, 1].map { NSNumber(value: $0) }
        scroll.duration = total
        scroll.repeatCount = .infinity
        scroll.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        field.layer?.add(scroll, forKey: "marquee")
        let edges = CAKeyframeAnimation(keyPath: "colors")
        edges.values = [rest, rest, scrolled, scrolled, rest]
        edges.keyTimes = scroll.keyTimes
        edges.duration = total
        edges.repeatCount = .infinity
        fade.add(edges, forKey: "marquee")
    }

    /// Both ends fade while the text is scrolled; at its start only the trailing one.
    private func edgeMask(leading: Bool) -> CALayer {
        let width = SidebarMetrics.titleFadeWidth / max(bounds.width, 1)
        fade.frame = bounds
        fade.colors = edgeColors(leading: leading)
        fade.locations = [0, NSNumber(value: Double(width)), NSNumber(value: Double(1 - width)), 1]
        return fade
    }

    private func edgeColors(leading: Bool) -> [CGColor] {
        [leading ? NSColor.clear.cgColor : NSColor.black.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
    }
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
        mediaRow.onExpansionChange = { [weak self] in
            self?.bodyView.needsLayout = true
            self?.bodyView.layoutSubtreeIfNeeded()
        }
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
        case .previous: mediaRow.previousButton.performClick(nil)
        case .toggleMute: mediaRow.muteButton.performClick(nil)
        case .pictureInPicture: mediaRow.pictureInPictureButton.performClick(nil)
        case .select, .seek: mediaRow.onAction?(action)
        }
    }

    /// Spikes and captures: the mini-player expanded as under the pointer, or collapsed.
    public func debugExpandMediaRow(_ expanded: Bool) {
        mediaRow.setExpanded(expanded)
    }
}
