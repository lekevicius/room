import AppKit

/// A borderless icon button that shows the rows' hover fill while the
/// pointer is over it or it is pressed: the sidebar's top bar (toggle,
/// extensions, Back, Forward, Reload) and the address field's buttons.
open class HoverButton: NSButton {
    private var hovering = false { didSet { if hovering != oldValue { updateFill() } } }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageOnly
        title = ""
        contentTintColor = .secondaryLabelColor
        wantsLayer = true
        layer?.cornerRadius = Radius.small
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    open override var mouseDownCanMoveWindow: Bool { false }

    open override var isEnabled: Bool {
        didSet { updateFill() }
    }

    open override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateFill()
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    open override func mouseEntered(with event: NSEvent) { hovering = true }
    open override func mouseExited(with event: NSEvent) { hovering = false }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovering = false
        updateFill()
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let shows = isEnabled && (hovering || isHighlighted)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = shows ? Palette.sidebarHover.cgColor : nil
        }
    }
}
