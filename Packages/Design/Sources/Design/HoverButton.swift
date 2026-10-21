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
        layer?.cornerRadius = ControlMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        _ = feedback
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    open override var mouseDownCanMoveWindow: Bool { false }

    // MARK: VoiceOver and keyboard (5.3a)

    // The button's cell is the element VoiceOver reads, and it takes its name from the image's
    // description: a label or help set on the button alone never reached it (5.3a: an extension's
    // action without a described icon had no name).
    open override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        super.setAccessibilityLabel(accessibilityLabel)
        cell?.setAccessibilityLabel(accessibilityLabel)
    }

    open override func setAccessibilityHelp(_ accessibilityHelp: String?) {
        super.setAccessibilityHelp(accessibilityHelp)
        cell?.setAccessibilityHelp(accessibilityHelp)
    }

    open override func setAccessibilityValue(_ accessibilityValue: Any?) {
        super.setAccessibilityValue(accessibilityValue)
        cell?.setAccessibilityValue(accessibilityValue)
    }

    /// The tooltip "Name (key)": VoiceOver says the name, with the key as its help ("Open as Tab (⌘O)"
    /// was read whole as the name).
    public func setTip(_ tip: String) {
        toolTip = tip
        if let open = tip.range(of: " ("), tip.hasSuffix(")") {
            setAccessibilityLabel(String(tip[..<open.lowerBound]))
            setAccessibilityHelp(String(tip[open.upperBound...].dropLast()))
        } else {
            setAccessibilityLabel(tip)
            setAccessibilityHelp(nil)
        }
    }

    /// A key view while Full Keyboard Access is on (`KeyboardAccess`), as AppKit's buttons.
    open override var acceptsFirstResponder: Bool { isEnabled && !refusesFirstResponder && KeyboardAccess.allControls }
    /// AppKit's button asks the system's setting itself here; Room's asks `KeyboardAccess` (5.3a: the keyboard spike).
    open override var canBecomeKeyView: Bool { acceptsFirstResponder && window != nil && !isHiddenOrHasHiddenAncestor }

    /// Space presses it (NSButton); Return and Enter too.
    open override func keyDown(with event: NSEvent) {
        if KeyboardAccess.isPressKey(event), event.keyCode != 49 {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The ring follows the hover square (`FocusRing.controlCornerRadius`), not the glyph.
    open override var focusRingMaskBounds: NSRect { bounds }

    open override func drawFocusRingMask() {
        let radius = layer?.cornerRadius ?? FocusRing.controlCornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

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
