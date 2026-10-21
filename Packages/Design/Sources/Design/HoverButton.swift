import AppKit

/// A borderless icon button with the chrome's hover and press feedback
/// (`ControlFeedback`, B-111): the rows' hover fill fades in while the
/// pointer is over it, and a press shrinks it and springs it back. The
/// sidebar's top bar (toggle, extensions, Back, Forward, Reload), the address
/// field's buttons, the footer's New Tab, the card's buttons (Peek, a split
/// pane's header, the find bar).
open class HoverButton: NSButton {
    public private(set) lazy var feedback = ControlFeedback(view: self)

    public override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageOnly
        title = ""
        contentTintColor = .secondaryLabelColor
        wantsLayer = true
        layer?.cornerRadius = Radius.small
        layer?.cornerCurve = .continuous
        _ = feedback
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    open override var mouseDownCanMoveWindow: Bool { false }

    open override var isEnabled: Bool {
        didSet { feedback.isEnabled = isEnabled }
    }

    /// NSButton's tracking highlights the button while it is pressed with the pointer inside.
    open override func highlight(_ flag: Bool) {
        super.highlight(flag)
        feedback.setPressed(flag)
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    open override func mouseEntered(with event: NSEvent) { feedback.setHovering(true) }
    open override func mouseExited(with event: NSEvent) { feedback.setHovering(false) }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        feedback.reset()
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        feedback.appearanceChanged()
    }
}
