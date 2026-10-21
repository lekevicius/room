import AppKit
import Design

/// The card with nothing selected (spec §A.7: no new-tab page): one line
/// telling how to open something, centred. The key is New Tab's as the
/// Shortcuts table has it now (5.6a: a remapped or removed key is what the
/// line says).
public final class CardEmptyStateView: NSView {
    /// The line for New Tab's current key (`nil` or empty: New Tab has none).
    public static func message(newTabKey: String?) -> String {
        guard let newTabKey, !newTabKey.isEmpty else { return "Click New Tab in the sidebar to search or type a URL" }
        return "Press \(newTabKey) to search or type a URL"
    }

    /// New Tab's key as the menu shows it ("⌘T"); every empty card follows a change.
    public static var newTabKey: String? = "⌘T" {
        didSet {
            guard newTabKey != oldValue else { return }
            NotificationCenter.default.post(name: keyDidChange, object: nil)
        }
    }

    private static let keyDidChange = Notification.Name("RoomCardEmptyStateKeyDidChange")

    private let label = NSTextField(labelWithString: CardEmptyStateView.message(newTabKey: CardEmptyStateView.newTabKey))

    /// The line on screen (spikes read it).
    public var message: String { label.stringValue }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = Typography.row
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        addSubview(label)
        setAccessibilityIdentifier("card-empty-state")
        NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: Self.keyDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func keyChanged() {
        label.stringValue = Self.message(newTabKey: Self.newTabKey)
        needsLayout = true
    }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func layout() {
        super.layout()
        let size = label.fittingSize
        label.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(),
                             width: size.width, height: size.height)
    }
}
