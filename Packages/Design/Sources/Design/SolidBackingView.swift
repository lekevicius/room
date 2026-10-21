import AppKit

/// Reduce Transparency (5.3b): an opaque `Materials.solidFill` under an overlay's content, in place
/// of what its glass or material shows through. Hidden while the option is off; follows a live
/// toggle (`DisplayOptions.didChange`). The owner adds it as the first subview of the glass's
/// content (or of the material view) and sizes it to fill, with the glass's corner radius.
public final class SolidBackingView: NSView {
    public var cornerRadius: CGFloat {
        didSet { needsDisplay = true }
    }

    public init(cornerRadius: CGFloat = 0) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.actions = CALayer.noImplicitActions
        autoresizingMask = [.width, .height]
        update()
        NotificationCenter.default.addObserver(self, selector: #selector(optionsChanged), name: DisplayOptions.didChange, object: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var wantsUpdateLayer: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func optionsChanged() { update() }

    private func update() {
        isHidden = !Materials.usesSolidFill()
        needsDisplay = true
    }

    public override func updateLayer() {
        layer?.backgroundColor = Materials.solidFill.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
    }

    /// Adds a backing under `view`'s subviews, filling it.
    @discardableResult
    public static func install(in view: NSView, cornerRadius: CGFloat) -> SolidBackingView {
        let backing = SolidBackingView(cornerRadius: cornerRadius)
        backing.frame = view.bounds
        view.addSubview(backing, positioned: .below, relativeTo: view.subviews.first)
        return backing
    }
}
