import AppKit
import Design

/// Back, Forward and Reload (Stop while loading): the sidebar's top bar
/// and the optional toolbar (spec §E). Forward shows only while the page can
/// go forward (5.12, the user on build 26, as Dia): it slides in beside Back
/// over `Motion.fast` (a fade under Reduce Motion), the buttons packed to the
/// trailing edge in the sidebar and the leading one in the toolbar.
public final class NavigationButtonsView: NSView {
    public var onBack: (() -> Void)?
    public var onForward: (() -> Void)?
    /// Reload, or Stop while the page loads.
    public var onReload: (() -> Void)?

    private let back = NavigationButtonsView.button(.back, "Back", key: "⌘[")
    private let forward = NavigationButtonsView.button(.forward, "Forward", key: "⌘]")
    private let reload = NavigationButtonsView.button(.reload, "Reload", key: "⌘R")
    private let size: CGFloat
    /// The sidebar's top bar packs the buttons against its trailing edge; the toolbar against its leading one.
    public var packsTrailing = true { didSet { needsLayout = true } }
    private var showsForward = false

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
        [forward, back, reload].forEach(addSubview)
        forward.isHidden = true
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
        for (button, frame) in zip([back, forward, reload], buttonFrames) { button.frame = frame }
        forward.alphaValue = showsForward ? 1 : 0
    }

    /// Three equal slots across the bounds (the sidebar's top bar may narrow them); without Forward,
    /// Back takes its slot (trailing) or Reload does (leading), and Forward waits under Back.
    private var buttonFrames: [NSRect] {
        let side = min(bounds.width / 3, bounds.height)
        let y = ((bounds.height - side) / 2).rounded()
        let slot = { (index: Int) in NSRect(x: CGFloat(index) * side, y: y, width: side, height: side) }
        switch (showsForward, packsTrailing) {
        case (true, _): return [slot(0), slot(1), slot(2)]
        case (false, true): return [slot(1), slot(1), slot(2)]
        case (false, false): return [slot(0), slot(0), slot(1)]
        }
    }

    private func setShowsForward(_ shows: Bool) {
        guard shows != showsForward else { return }
        showsForward = shows
        forward.isHidden = false
        let frames = buttonFrames
        let animates = window != nil && !isHiddenOrHasHiddenAncestor
        guard animates else {
            needsLayout = true
            forward.isHidden = !shows
            return
        }
        let slides = !Motion.reduceMotion
        if shows, slides { forward.frame = back.frame }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.fast
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (button, frame) in zip([back, forward, reload], frames) {
                if slides { button.animator().frame = frame } else { button.frame = frame }
            }
            forward.animator().alphaValue = shows ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.showsForward == shows else { return }
                self.forward.isHidden = !shows
            }
        })
    }

    @objc private func backClicked() { onBack?() }
    @objc private func forwardClicked() { onForward?() }
    @objc private func reloadClicked() { onReload?() }

    /// VoiceOver says the name; the key is the help (5.3a: "Back (⌘[)" was the label).
    private static func button(_ symbol: Symbol, _ name: String, key: String) -> NSButton {
        let button = HoverButton()
        button.contentTintColor = .labelColor
        button.image = symbol.image(.control, accessibilityDescription: name)
        button.toolTip = "\(name) (\(key))"
        button.setAccessibilityLabel(name)
        button.setAccessibilityHelp(key)
        return button
    }
}
