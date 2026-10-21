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
    }

    private func update() {
        guard let state, let panel, let hostView, let sidebar, let tabs else { return }
        let rows = state.items.compactMap { id -> TabSwitcherPanel.Row? in
            guard let entry = sidebar.store.sidebar.entry(id) else { return nil }
            let page = tabs.pageState(for: id)
        // Explicit: a view added in this transaction has no presentation for `animator()` to start from.
        if TabsMotion.switcherAppear.variant != .instant, let layer = panel.layer {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = Motion.fast
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "appear")
        }
            return TabSwitcherPanel.Row(title: EntryLabel.title(entry), domain: EntryLabel.domain(entry.currentURL) ?? "",
                                        favicon: page.favicon, isLoaded: page.isLoaded)
        }
        panel.setRows(rows, highlighted: state.index)
        let size = panel.fittingSize
        panel.frame = NSRect(x: (hostView.bounds.width - size.width) / 2, y: (hostView.bounds.height - size.height) / 2,
                             width: size.width, height: size.height).integral
    }
}

/// The switcher's glass list.
final class TabSwitcherPanel: NSView {
    struct Row {
        var title: String
        var domain: String
        var favicon: NSImage?
        var isLoaded: Bool
    }

    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private let highlight = HighlightView()
    private var highlighted = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.cornerRadius = Radius.large
        let content = NSView()
        content.addSubview(highlight)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: TabSwitcherMetrics.padding, left: TabSwitcherMetrics.padding,
                                        bottom: TabSwitcherMetrics.padding, right: TabSwitcherMetrics.padding)
        wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: TabSwitcherMetrics.width),
        ])
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
        for row in rows { stack.addArrangedSubview(Self.rowView(row)) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        glass.contentView?.layoutSubtreeIfNeeded()
        guard stack.arrangedSubviews.indices.contains(highlighted), let content = glass.contentView else {
            highlight.isHidden = true
            return
        }
        let row = stack.arrangedSubviews[highlighted]
        highlight.frame = content.convert(row.bounds, from: row)
        highlight.isHidden = false
        highlight.needsDisplay = true
    }

    private static func rowView(_ row: Row) -> NSView {
        let icon = FaviconView(frame: NSRect(x: 0, y: 0, width: SidebarMetrics.faviconSize, height: SidebarMetrics.faviconSize))
        icon.image = row.favicon
        icon.letterSource = row.domain
        icon.isUnloaded = !row.isLoaded
        let title = NSTextField(labelWithString: row.title)
        title.font = Typography.row
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let line = NSStackView(views: [icon, title])
        line.spacing = SidebarMetrics.faviconTitleGap
        line.edgeInsets = NSEdgeInsets(top: 0, left: SidebarMetrics.rowContentInset, bottom: 0, right: SidebarMetrics.rowContentInset)
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: SidebarMetrics.faviconSize),
            icon.heightAnchor.constraint(equalToConstant: SidebarMetrics.faviconSize),
            line.heightAnchor.constraint(equalToConstant: TabSwitcherMetrics.rowHeight),
            line.widthAnchor.constraint(equalToConstant: TabSwitcherMetrics.width - 2 * TabSwitcherMetrics.padding),
        ])
        return line
    }
}

/// The highlighted row's pill (drawn, so captures show it too).
private final class HighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.sidebarMultiSelection.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Radius.medium, yRadius: Radius.medium).fill()
    }
}
