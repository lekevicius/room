import AppKit
import Design
import Engine
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif

/// Document picture-in-picture (`documentPictureInPicture.requestWindow`,
/// 4.6, B-51): the page the engine made for it floats in its own panel of
/// the requested size, above other windows and on every Space, at the
/// card's top-right corner; no sidebar. The panel closes when the page
/// closes (its `window.close()`, the opener closing, the engine), and the
/// page closes when the user closes the panel; the opener stays loaded.
/// Popups stay Today tabs (2.6's rule). Video picture-in-picture is the
/// engine's own overlay window, not this.
@MainActor
final class PictureInPicturePanels: NSObject, WebContentsUIDelegate, NSWindowDelegate {
    /// One floating page.
    final class Item {
        let panel: NSPanel
        let contents: any WebContents
        weak var opener: (any WebContents)?
        let entry: UUID
        /// The size the page asked for (`requestedBounds`), if the engine reported one.
        let requestedSize: CGSize?

        init(panel: NSPanel, contents: any WebContents, opener: any WebContents, entry: UUID, requestedSize: CGSize?) {
            self.panel = panel
            self.contents = contents
            self.opener = opener
            self.entry = entry
            self.requestedSize = requestedSize
        }
    }

    /// The card's frame in screen coordinates (the panel's corner).
    var cardScreenRect: () -> NSRect = { NSScreen.main?.visibleFrame ?? .zero }
    /// The page's other UI (dialogs, permission prompts) goes where the card's pages' goes.
    weak var pageUIDelegate: (any WebContentsUIDelegate)?
    private(set) var items: [Item] = []
    /// The panel's back-to-tab button (B-107): the opener's entry is selected and its window shown; the panel closes.
    var onBackToTab: ((UUID) -> Void)?
    /// Spikes: each panel shown and closed.
    var debugOnShow: ((Item) -> Void)?
    var debugOnClose: ((Item) -> Void)?

    /// The size used when the engine reported none (Chrome's document PiP default is the page's choice).
    static let fallbackSize = CGSize(width: 400, height: 225)

    func present(_ contents: any WebContents, opener: any WebContents, entry: UUID) {
        let requested = Self.requestedSize(of: contents)
        let screen = NSScreen.screens.first { $0.frame.intersects(cardScreenRect()) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var size = requested ?? Self.fallbackSize
        size.width = min(max(size.width, PictureInPictureMetrics.minimumSize.width), visible.width - 2 * Spacing.l)
        size.height = min(max(size.height, PictureInPictureMetrics.minimumSize.height), visible.height - 2 * Spacing.l)
        // 5.13 (the user's design): borderless and rounded, the page alone; its controls grow around it on hover.
        let panel = PictureInPicturePanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = contents.title ?? opener.url?.host() ?? "Picture in Picture"
        panel.delegate = self
        let container = PictureInPictureContentView(frame: NSRect(origin: .zero, size: size))
        container.pageView = contents.nativeView
        container.setTitle(panel.title, icon: contents.favicon ?? opener.favicon)
        container.onClose = { [weak panel] in panel?.close() }
        container.onBackToTab = { [weak self, weak panel] in
            guard let self, let item = self.items.first(where: { $0.panel === panel }) else { return }
            self.backToTab(item)
        }
        panel.contentView = container
        // The card's top-right corner, inside the visible screen.
        let card = cardScreenRect()
        let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var origin = NSPoint(x: card.maxX - Spacing.l - frame.width, y: card.maxY - Spacing.l - frame.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrameOrigin(origin)
        contents.uiDelegate = self
        let item = Item(panel: panel, contents: contents, opener: opener, entry: entry, requestedSize: requested)
        items.append(item)
        panel.orderFront(nil)
        NSLog("Room: document picture-in-picture panel %@ (requested %@) for entry %@", NSStringFromRect(panel.frame),
              requested.map { NSStringFromSize($0) } ?? "none", entry.uuidString)
        debugOnShow?(item)
    }

    /// What the page asked for (engine-specific: RoomCore reports `requestedBounds`).
    static func requestedSize(of contents: any WebContents) -> CGSize? {
        #if ROOM_ENGINE_ROOMCORE
        if let bounds = (contents as? RoomCoreWebContents)?.requestedBounds, bounds.width > 0, bounds.height > 0 { return bounds.size }
        #endif
        return nil
    }

    func item(for contents: any WebContents) -> Item? { items.first { $0.contents === contents } }

    /// Spikes press it through here.
    func backToTab(_ item: Item) {
        onBackToTab?(item.entry)
        item.panel.close()
    }

    /// Its window closed (4.8a): every panel and its page go.
    func closeAll() {
        let closing = items
        items = []
        for item in closing {
            item.panel.delegate = nil
            item.panel.close()
            item.contents.close()
        }
    }

    // MARK: WebContentsUIDelegate

    /// The page closed (its `window.close()`, the opener closing): its panel goes.
    func webContentsDidClose(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidClose(webContents)
        guard let index = items.firstIndex(where: { $0.contents === webContents }) else { return }
        let item = items.remove(at: index)
        item.panel.delegate = nil
        item.panel.close()
        NSLog("Room: document picture-in-picture closed with its page")
        debugOnClose?(item)
    }

    /// A popup from the PiP page opens under its opener's entry as any other (through the card's delegate).
    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?,
                     disposition: Disposition) {
        if let pageUIDelegate, let opener = item(for: webContents)?.opener {
            pageUIDelegate.webContents(opener, didCreate: newContents, targetURL: targetURL, disposition: disposition)
        } else {
            newContents.close()
        }
    }

    // MARK: NSWindowDelegate

    /// The user closed the panel: the page closes (the opener stays loaded).
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, let index = items.firstIndex(where: { $0.panel === panel }) else { return }
        let item = items.remove(at: index)
        NSLog("Room: document picture-in-picture panel closed by the user")
        item.contents.close()
        debugOnClose?(item)
    }
}

/// The borderless panel (5.13) still closes on ⌘W and `performClose` (a borderless window has no close
/// button, so AppKit's would do nothing).
final class PictureInPicturePanel: NSPanel {
    override func performClose(_ sender: Any?) {
        guard delegate?.windowShouldClose?(self) ?? true else { return }
        close()
    }
}

/// The document picture-in-picture panel's content (5.13, the user's design from Dia's call window):
/// at rest the page fills the rounded panel; under the pointer the panel grows `frameInset` around
/// the page and a bar above it (the page stays where it is on screen) with a glass Close, the title
/// and its icon, and a glass Back to Tab. The bar drags the panel.
final class PictureInPictureContentView: NSView {
    var onClose: (() -> Void)?
    var onBackToTab: (() -> Void)?
    var pageView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let pageView { pageHolder.addSubview(pageView) }
            needsLayout = true
        }
    }
    private let pageHolder = NSView()
    private let bar = PictureInPictureBar()
    private(set) var isExpanded = false
    private var collapseWork: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = PictureInPictureMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        pageHolder.wantsLayer = true
        pageHolder.layer?.cornerCurve = .continuous
        pageHolder.layer?.masksToBounds = true
        bar.alphaValue = 0
        bar.onClose = { [weak self] in self?.onClose?() }
        bar.onBackToTab = { [weak self] in self?.onBackToTab?() }
        addSubview(pageHolder)
        addSubview(bar)
        setAccessibilityIdentifier("pip-panel")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setTitle(_ title: String, icon: NSImage?) { bar.set(title: title, icon: icon) }

    override func layout() {
        super.layout()
        let inset = isExpanded ? PictureInPictureMetrics.frameInset : 0
        let top = isExpanded ? PictureInPictureMetrics.barHeight : 0
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: PictureInPictureMetrics.barHeight)
        pageHolder.frame = NSRect(x: inset, y: top, width: max(0, bounds.width - 2 * inset), height: max(0, bounds.height - top - inset))
        pageHolder.layer?.cornerRadius = isExpanded ? PictureInPictureMetrics.pageCornerRadius : PictureInPictureMetrics.cornerRadius
        pageView?.frame = pageHolder.bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // The panel floats over other apps while Room is in the background: always tracked.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
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

    /// Grows the panel around the page (or back), the page keeping its place on screen (spikes call it too).
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded, let window else { return }
        isExpanded = expanded
        let inset = PictureInPictureMetrics.frameInset, barHeight = PictureInPictureMetrics.barHeight
        var frame = window.frame
        let grow: CGFloat = expanded ? 1 : -1
        frame.origin.x -= grow * inset
        frame.origin.y -= grow * inset
        frame.size.width += grow * 2 * inset
        frame.size.height += grow * (inset + barHeight)
        // The frame changes at once (the page must not move on screen); the bar fades.
        window.setFrame(frame, display: true, animate: false)
        needsLayout = true
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fast
            bar.animator().alphaValue = expanded ? 1 : 0
        }
    }
}

/// The bar over the picture-in-picture page: Close, the title with its icon, Back to Tab.
private final class PictureInPictureBar: NSView {
    var onClose: (() -> Void)?
    var onBackToTab: (() -> Void)?
    private let close = HoverButton()
    private let back = HoverButton()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        close.image = Symbol.closeTab.image(.control, accessibilityDescription: "Close")
        close.makeGlass()
        close.setTip("Close")
        close.target = self
        close.action = #selector(closeClicked)
        close.setAccessibilityIdentifier("pip-close")
        back.image = Symbol.peekExpand.image(.control, accessibilityDescription: "Back to Tab")
        back.makeGlass()
        back.setTip("Back to Tab")
        back.target = self
        back.action = #selector(backClicked)
        back.setAccessibilityIdentifier("pip-back-to-tab")
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.alignment = .center
        [close, back, icon, title].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    // The bar drags the panel.
    override var mouseDownCanMoveWindow: Bool { true }

    func set(title text: String, icon image: NSImage?) {
        title.stringValue = text
        icon.image = image
        icon.isHidden = image == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let size = GlassControlMetrics.size, inset = PictureInPictureMetrics.frameInset
        let y = ((bounds.height - size) / 2).rounded()
        close.frame = NSRect(x: inset, y: y, width: size, height: size)
        back.frame = NSRect(x: bounds.width - inset - size, y: y, width: size, height: size)
        let room = max(0, back.frame.minX - close.frame.maxX - 2 * Spacing.s)
        let iconSide: CGFloat = icon.isHidden ? 0 : 18
        let textWidth = min(ceil(title.fittingSize.width), room - iconSide - (iconSide > 0 ? Spacing.s : 0))
        let total = iconSide + (iconSide > 0 ? Spacing.s : 0) + max(0, textWidth)
        let x = ((bounds.width - total) / 2).rounded()
        icon.frame = NSRect(x: x, y: ((bounds.height - iconSide) / 2).rounded(), width: iconSide, height: iconSide)
        let height = ceil(title.fittingSize.height)
        title.frame = NSRect(x: x + total - max(0, textWidth), y: ((bounds.height - height) / 2).rounded(), width: max(0, textWidth), height: height)
    }

    @objc private func closeClicked() { onClose?() }
    @objc private func backClicked() { onBackToTab?() }
}
