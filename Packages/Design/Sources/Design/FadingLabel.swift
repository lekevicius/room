import AppKit

extension NSTextField {
    /// Ends text too long for the field with a `SidebarMetrics.titleFadeWidth` fade instead
    /// of an ellipsis (the Room Browser design); `enabled` false (an inline
    /// rename) or text that fits shows it whole. The field must clip.
    public func updateTrailingFade(enabled: Bool = true) {
        let fade = SidebarMetrics.titleFadeWidth
        let overflows = (cell?.cellSize.width ?? 0) > bounds.width
        guard enabled, overflows, bounds.width > fade else {
            layer?.mask = nil
            return
        }
        wantsLayer = true
        let mask = layer?.mask as? CAGradientLayer ?? CAGradientLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double((bounds.width - fade) / bounds.width)), 1]
        layer?.mask = mask
        CATransaction.commit()
    }
}

/// A one-line label whose overflow fades out (5.13: every tab title fades, never an ellipsis;
/// split rows and ⌃Tab still truncated). The fade follows the frame and the text.
public final class FadingLabel: NSTextField {
    public convenience init(string: String = "") {
        self.init(labelWithString: string)
        lineBreakMode = .byClipping
        cell?.truncatesLastVisibleLine = false
        maximumNumberOfLines = 1
    }

    public override var stringValue: String {
        didSet { updateTrailingFade() }
    }

    public override var font: NSFont? {
        didSet { updateTrailingFade() }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrailingFade()
    }
}
