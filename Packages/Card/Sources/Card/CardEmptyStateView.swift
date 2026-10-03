import AppKit
import Design

/// The card with nothing selected (spec §A.7: no new-tab page): one line
/// telling how to open something, centred.
public final class CardEmptyStateView: NSView {
    public static let message = "Press ⌘T to search or type a URL"

    private let label = NSTextField(labelWithString: CardEmptyStateView.message)

    public override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Typography.row
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        addSubview(label)
        setAccessibilityIdentifier("card-empty-state")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func layout() {
        super.layout()
        let size = label.fittingSize
        label.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                             width: size.width, height: size.height)
    }
}
