import AppKit
import Design
import Model
import Sidebar

/// The ⌃Tab switcher's list and highlight, as a value (spec §G: the five
/// most recent tabs; Tab steps forward, ⇧Tab back, W closes the highlighted
/// one, releasing ⌃ selects it).
public struct TabSwitcherState: Equatable, Sendable {
    public private(set) var items: [UUID]
    public private(set) var index: Int

    /// `items` most recent first (the selected entry first); ⌃Tab starts on
    /// the second (the previous tab), ⌃⇧Tab on the last.
    public init(items: [UUID], backwards: Bool) {
        self.items = items
        index = items.count < 2 ? 0 : (backwards ? items.count - 1 : 1)
    }

    public var highlighted: UUID? { items.indices.contains(index) ? items[index] : nil }

    public mutating func step(_ offset: Int) {
        guard !items.isEmpty else { return }
        index = ((index + offset) % items.count + items.count) % items.count
    }

    /// W: drops the highlighted entry; the highlight stays on the next one.
    @discardableResult
    public mutating func removeHighlighted() -> UUID? {
        guard let id = highlighted else { return nil }
        items.remove(at: index)
        if index >= items.count { index = max(0, items.count - 1) }
        return id
    }
}

/// ⌃Tab in one window: a local key monitor (it sees the keys before the page
/// and the menus; ⌃Tab is reserved, `docs/shortcuts.md`), the state, and a
/// glass list over the card shown once ⌃ has been held
/// `Timing.tabSwitcherDelay`. A quick tap switches to the previous tab
/// without showing it.
public final class TabSwitcher {
    private weak var window: NSWindow?
    private weak var hostView: NSView?
    private weak var sidebar: SidebarController?
    private weak var tabs: TabController?
    private var state: TabSwitcherState?
    private var panel: TabSwitcherPanel?
    /// The list, kept between shows (building its glass cost ~20 ms per show, 5.1b's harness).
    private var builtPanel: TabSwitcherPanel?
    private var monitor: Any?
    private var pendingShow: DispatchWorkItem?

    /// `hostView` is the view the list centres over (the card).
    public init(window: NSWindow, hostView: NSView, sidebar: SidebarController, tabs: TabController) {
        self.window = window
        self.hostView = hostView
        self.sidebar = sidebar
        self.tabs = tabs
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return handle(event) ? nil : event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey(_:)),
                                               name: NSWindow.didResignKeyNotification, object: window)
        tabs.onThumbnail = { [weak self] entry in
            guard let self, self.panel != nil, self.state?.items.contains(entry) == true else { return }
            self.update()
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    public var isActive: Bool { state != nil }

    #if DEBUG
    /// The list's frame in the window, if it is showing (captures).
    public var debugPanelFrame: NSRect? { panel.map { $0.convert($0.bounds, to: nil) } }
    /// The list itself (the glass draws nothing in an in-process render).
    public var debugPanel: NSView? { panel }
    /// ⌃Tab held past the delay, at once (the motion harness, 5.1b); `debugEnd` lets ⌃ go without switching.
    public func debugShow() {
        begin(backwards: false)
        pendingShow?.cancel()
        showPanel()
    }
    public func debugEnd() { cancel() }
    #endif

    /// Returns whether the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window || (event.window == nil && window.isKeyWindow) else { return false }
        let control = event.modifierFlags.contains(.control)
        if event.type == .flagsChanged {
            if state != nil, !control { commit() }
            return false
        }
        if event.keyCode == 48, control {
            let backwards = event.modifierFlags.contains(.shift)
            if state == nil { begin(backwards: backwards) } else { state?.step(backwards ? -1 : 1) }
            update()
            return true
        }
        guard state != nil else { return false }
        switch event.keyCode {
        case 53: cancel()
        case 13: closeHighlighted()   // W (by key position, like the reserved set's letters on QWERTY)
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "w" { closeHighlighted() }
        }
        return true
    }

    private func begin(backwards: Bool) {
        guard let sidebar else { return }
        let items = sidebar.recentEntries(limit: TabSwitcherMetrics.limit).map(\.id)
        guard items.count > 1 else { return }
        state = TabSwitcherState(items: items, backwards: backwards)
        // The shown tab's picture, fresh (the others were taken as they were left).
        if let current = sidebar.selectedEntryID { tabs?.captureThumbnail(current) }
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.tabSwitcherDelay, execute: work)
    }

    private func commit() {
        let target = state?.highlighted
        end()
        guard let target, target != sidebar?.selectedEntryID else { return }
        sidebar?.select(target)
    }

    private func cancel() { end() }

    private func end() {
        pendingShow?.cancel()
        pendingShow = nil
        state = nil
        panel?.isHidden = true
        panel = nil
    }

    private func closeHighlighted() {
        guard let id = state?.removeHighlighted() else { return }
        sidebar?.close(id)
        if (state?.items.count ?? 0) < 2 { end() } else { update() }
    }

    @objc private func windowResignedKey(_ notification: Notification) { cancel() }

    /// Builds the list ahead of the first ⌃Tab (B-129: the first show built the glass and solved
    /// its constraints for the first time, 20–30 ms against 7–10 for a later one) and keeps it in
    /// the host view, hidden. The app calls it once the window is up.
    public func prewarm() {
        guard builtPanel == nil, let hostView else { return }
        let panel = TabSwitcherPanel()
        builtPanel = panel
        panel.isHidden = true
        hostView.addSubview(panel, positioned: .above, relativeTo: nil)
        let row = TabSwitcherPanel.Row(title: " ", domain: "", favicon: nil, isLoaded: true)
        panel.setRows([row, row], highlighted: 0)
        panel.frame = NSRect(origin: .zero, size: panel.fittingSize)
        panel.layoutSubtreeIfNeeded()
    }

    private func showPanel() {
        guard state != nil, panel == nil, let hostView else { return }
        let panel = builtPanel ?? TabSwitcherPanel()
        builtPanel = panel
        if panel.superview !== hostView || hostView.subviews.last !== panel {
            hostView.addSubview(panel, positioned: .above, relativeTo: nil)
        }
        panel.isHidden = false
        self.panel = panel
        update()
        // Explicit: a view added in this transaction has no presentation for `animator()` to start from.
        if TabsMotion.switcherAppear.variant != .instant, let layer = panel.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Motion.fast
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "appear")
        }
    }

    private func update() {
        guard let state, let panel, let hostView, let sidebar, let tabs else { return }
        let rows = state.items.compactMap { id -> TabSwitcherPanel.Row? in
            guard let entry = sidebar.store.sidebar.entry(id) else { return nil }
            let page = tabs.pageState(for: id)
            return TabSwitcherPanel.Row(title: EntryLabel.title(entry), domain: EntryLabel.domain(entry.currentURL) ?? "",
                                        favicon: page.favicon, isLoaded: page.isLoaded, thumbnail: tabs.thumbnail(for: id))
        }
        panel.setRows(rows, highlighted: state.index)
        let size = panel.fittingSize
        panel.frame = NSRect(x: (hostView.bounds.width - size.width) / 2, y: (hostView.bounds.height - size.height) / 2,
                             width: size.width, height: size.height).integral
    }
}

/// The switcher's glass panel: a card per tab, side by side (5.12, B-119): the page's picture
/// (taken as its tab was left), its icon and title under it; the highlighted card in a pill.
final class TabSwitcherPanel: NSView {
    struct Row {
        var title: String
        var domain: String
        var favicon: NSImage?
        var isLoaded: Bool
        var thumbnail: NSImage? = nil
    }

    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private let highlight = HighlightView()
    private var highlighted = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glass.cornerRadius = Radius.large
        let content = NSView()
        content.addSubview(highlight)
        stack.orientation = .horizontal
        stack.spacing = TabSwitcherMetrics.cardGap
        stack.alignment = .top
        stack.edgeInsets = NSEdgeInsets(top: TabSwitcherMetrics.padding, left: TabSwitcherMetrics.padding,
                                        bottom: TabSwitcherMetrics.padding, right: TabSwitcherMetrics.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        // Reduce Transparency (5.3b): an opaque fill under the cards.
        SolidBackingView.install(in: content, cornerRadius: Radius.large)
        glass.contentView = content
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }

    func setRows(_ rows: [Row], highlighted: Int) {
        self.highlighted = highlighted
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in rows { stack.addArrangedSubview(SwitcherCardView(row)) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glass.contentView?.layoutSubtreeIfNeeded()
        guard stack.arrangedSubviews.indices.contains(highlighted), let content = glass.contentView else {
            highlight.isHidden = true
            return
        }
        let card = stack.arrangedSubviews[highlighted]
        highlight.frame = content.convert(card.bounds, from: card)
        highlight.isHidden = false
        highlight.needsDisplay = true
    }
}

/// One tab: its picture (or its icon, large, on a quiet fill when it has none yet), then icon and title.
private final class SwitcherCardView: NSView {
    init(_ row: TabSwitcherPanel.Row) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let inset = TabSwitcherMetrics.cardPadding
        let width = TabSwitcherMetrics.cardWidth
        let picture = NSView()
        picture.wantsLayer = true
        picture.layer?.cornerRadius = TabSwitcherMetrics.thumbnailCorner
        picture.layer?.cornerCurve = .continuous
        picture.layer?.masksToBounds = true
        picture.layer?.borderWidth = 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            picture.layer?.borderColor = Palette.hairline.cgColor
            picture.layer?.backgroundColor = Palette.sidebarHover.cgColor
        }
        picture.frame = NSRect(x: inset, y: inset + TabSwitcherMetrics.titleHeight, width: width, height: TabSwitcherMetrics.thumbnailHeight)
        if let thumbnail = row.thumbnail {
            picture.layer?.contents = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            picture.layer?.contentsGravity = .resizeAspectFill
        } else {
            let icon = FaviconView(frame: NSRect(x: (width - SidebarMetrics.faviconSize * 2) / 2,
                                                 y: (TabSwitcherMetrics.thumbnailHeight - SidebarMetrics.faviconSize * 2) / 2,
                                                 width: SidebarMetrics.faviconSize * 2, height: SidebarMetrics.faviconSize * 2))
            icon.image = row.favicon
            icon.letterSource = row.domain
            icon.isUnloaded = !row.isLoaded
            picture.addSubview(icon)
        }
        addSubview(picture)
        let icon = FaviconView(frame: NSRect(x: inset, y: inset + (TabSwitcherMetrics.titleHeight - SidebarMetrics.faviconSize) / 2,
                                             width: SidebarMetrics.faviconSize, height: SidebarMetrics.faviconSize))
        icon.image = row.favicon
        icon.letterSource = row.domain
        icon.isUnloaded = !row.isLoaded
        addSubview(icon)
        let title = NSTextField(labelWithString: row.title)
        title.font = Typography.row
        title.lineBreakMode = .byTruncatingTail
        title.textColor = row.isLoaded ? .labelColor : .secondaryLabelColor
        let titleHeight = ceil(title.cell?.cellSize.height ?? 16)
        let x = icon.frame.maxX + SidebarMetrics.faviconTitleGap
        title.frame = NSRect(x: x, y: inset + ((TabSwitcherMetrics.titleHeight - titleHeight) / 2).rounded(),
                             width: inset + width - x, height: titleHeight)
        addSubview(title)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(row.title)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width + 2 * inset),
            heightAnchor.constraint(equalToConstant: TabSwitcherMetrics.thumbnailHeight + TabSwitcherMetrics.titleHeight + 2 * inset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The highlighted row's pill (drawn, so captures show it too).
private final class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.sidebarMultiSelection.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Radius.medium, yRadius: Radius.medium).fill()
    }
}
