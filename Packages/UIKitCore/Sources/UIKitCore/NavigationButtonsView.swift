import AppKit
import Design

/// Back, Forward and Reload (Stop while loading): the sidebar's top bar
/// and the optional toolbar (spec §E). 5.13 (the user's design, Figma 157:233): Back and Forward
/// in one Liquid Glass group, Back alone (a glass circle) while the page cannot go forward
/// (5.12: as Dia), then Reload as a glass circle, which the sidebar's top bar drops first when
/// there is no room (`showsReload`). The group's width follows Forward (`preferredWidth`;
/// `onWidthChange` lets the owner lay out again, animated).
public final class NavigationButtonsView: NSView {
    public var onBack: (() -> Void)?
    public var onForward: (() -> Void)?
    /// Reload, or Stop while the page loads.
    public var onReload: (() -> Void)?
    /// Forward came or went: the preferred width changed.
    public var onWidthChange: (() -> Void)?

    private let group = GlassButtonGroup()
    private let back = NavigationButtonsView.button(.back, "Back", key: "⌘[")
    private let forward = NavigationButtonsView.button(.forward, "Forward", key: "⌘]")
    private let reload = NavigationButtonsView.button(.reload, "Reload", key: "⌘R")
    /// The sidebar's top bar packs the buttons against its trailing edge; the toolbar against its leading one.
    public var packsTrailing = true { didSet { needsLayout = true } }
    /// Whether Reload shows (the sidebar's top bar hides it when there is no room).
    public var showsReload = true {
        didSet { if showsReload != oldValue { reload.isHidden = !showsReload; needsLayout = true } }
    }
    private var showsForward = false

    public init(buttonSize: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: GlassControlMetrics.size * 2 + GlassControlMetrics.gap, height: GlassControlMetrics.size))
        back.target = self
        back.action = #selector(backClicked)
        back.setAccessibilityIdentifier("nav-back")
        forward.target = self
        forward.action = #selector(forwardClicked)
        forward.setAccessibilityIdentifier("nav-forward")
        reload.target = self
        reload.action = #selector(reloadClicked)
        reload.setAccessibilityIdentifier("nav-reload")
        reload.makeGlass()
        group.setItems([back])
        addSubview(group)
        addSubview(reload)
        update(canGoBack: false, canGoForward: false, isLoading: false, hasPage: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override var intrinsicContentSize: NSSize { NSSize(width: preferredWidth(showsReload: showsReload), height: GlassControlMetrics.size) }
    public override var fittingSize: NSSize { intrinsicContentSize }

    /// The width the buttons take: the Back (and Forward) group, then Reload.
    public func preferredWidth(showsReload: Bool) -> CGFloat {
        let groupWidth = GlassControlMetrics.groupWidth(showsForward ? 2 : 1)
        return groupWidth + (showsReload ? GlassControlMetrics.gap + GlassControlMetrics.size : 0)
    }

    public func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool, hasPage: Bool) {
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
        setShowsForward(canGoForward)
        reload.isEnabled = hasPage
        let symbol: Symbol = isLoading ? .stop : .reload
        reload.image = symbol.image(.control, accessibilityDescription: isLoading ? "Stop" : "Reload")
        reload.toolTip = isLoading ? "Stop (⌘.)" : "Reload (⌘R)"
        reload.setAccessibilityLabel(isLoading ? "Stop" : "Reload")
        reload.setAccessibilityHelp(isLoading ? "⌘." : "⌘R")
    }

    public override func layout() {
        super.layout()
        let size = GlassControlMetrics.size
        let groupWidth = GlassControlMetrics.groupWidth(showsForward ? 2 : 1)
        let y = ((bounds.height - size) / 2).rounded()
        let reloadWidth = showsReload ? GlassControlMetrics.gap + size : 0
        let x = packsTrailing ? bounds.width - groupWidth - reloadWidth : 0
        group.frame = NSRect(x: x, y: y, width: groupWidth, height: size)
        reload.frame = NSRect(x: group.frame.maxX + GlassControlMetrics.gap, y: y, width: size, height: size)
    }

    private func setShowsForward(_ shows: Bool) {
        guard shows != showsForward else { return }
        showsForward = shows
        group.setItems(shows ? [back, forward] : [back])
        invalidateIntrinsicContentSize()
        needsLayout = true
        onWidthChange?()
    }

    @objc private func backClicked() { onBack?() }
    @objc private func forwardClicked() { onForward?() }
    @objc private func reloadClicked() { onReload?() }

    /// VoiceOver says the name; the key is the help (5.3a: "Back (⌘[)" was the label).
    private static func button(_ symbol: Symbol, _ name: String, key: String) -> HoverButton {
        let button = HoverButton()
        button.contentTintColor = .labelColor
        button.image = symbol.image(.control, accessibilityDescription: name)
        button.toolTip = "\(name) (\(key))"
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(key)
        return button
    }
}
