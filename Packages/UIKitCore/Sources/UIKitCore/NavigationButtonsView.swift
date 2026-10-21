import AppKit
import Design

/// Back, Forward and Reload (Stop while loading): the sidebar's top bar
/// and the optional toolbar (spec §E).
public final class NavigationButtonsView: NSView {
    public var onBack: (() -> Void)?
    public var onForward: (() -> Void)?
    /// Reload, or Stop while the page loads.
    public var onReload: (() -> Void)?

    private let back = NavigationButtonsView.button(.back, "Back (⌘[)")
    private let forward = NavigationButtonsView.button(.forward, "Forward (⌘])")
    private let reload = NavigationButtonsView.button(.reload, "Reload (⌘R)")
    private let size: CGFloat

    public init(buttonSize: CGFloat) {
        size = buttonSize
        super.init(frame: NSRect(x: 0, y: 0, width: buttonSize * 3, height: buttonSize))
        back.target = self
        back.action = #selector(backClicked)
        back.setAccessibilityIdentifier("nav-back")
        forward.target = self
        forward.action = #selector(forwardClicked)
        forward.setAccessibilityIdentifier("nav-forward")
        reload.target = self
        reload.action = #selector(reloadClicked)
        reload.setAccessibilityIdentifier("nav-reload")
        [back, forward, reload].forEach(addSubview)
        update(canGoBack: false, canGoForward: false, isLoading: false, hasPage: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override var intrinsicContentSize: NSSize { NSSize(width: size * 3, height: size) }
    public override var fittingSize: NSSize { intrinsicContentSize }

    public func update(canGoBack: Bool, canGoForward: Bool, isLoading: Bool, hasPage: Bool) {
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
        reload.isEnabled = hasPage
        let symbol: Symbol = isLoading ? .stop : .reload
        reload.image = symbol.image(.control, accessibilityDescription: isLoading ? "Stop" : "Reload")
        reload.toolTip = isLoading ? "Stop (⌘.)" : "Reload (⌘R)"
    }

    public override func layout() {
        super.layout()
        // Three equal buttons across the bounds (the sidebar's top bar may narrow them).
        let side = min(bounds.width / 3, bounds.height)
        for (index, button) in [back, forward, reload].enumerated() {
            button.frame = NSRect(x: CGFloat(index) * side, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        }
    }

    @objc private func backClicked() { onBack?() }
    @objc private func forwardClicked() { onForward?() }
    @objc private func reloadClicked() { onReload?() }

    private static func button(_ symbol: Symbol, _ tip: String) -> NSButton {
        let button = HoverButton()
        button.contentTintColor = .labelColor
        button.image = symbol.image(.control, accessibilityDescription: tip)
        button.toolTip = tip
        return button
    }
}
