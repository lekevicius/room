import AppKit

/// Full Keyboard Access (5.3a, ROADMAP 5.3 task 2): with the system's
/// "Keyboard navigation" on, Tab reaches every control; off, only text
/// fields, lists and the page (macOS's default). Room's own controls ask
/// here, so a test or a spike can run either mode in-process (AppKit reads
/// the system setting itself, which a session may not change).
public enum KeyboardAccess {
    /// `nil` follows the system; tests and the keyboard spike set it.
    public static var allControlsOverride: Bool?

    /// Whether Tab reaches buttons too.
    public static var allControls: Bool { allControlsOverride ?? NSApplication.shared.isFullKeyboardAccessEnabled }

    /// Space, Return and Enter press a focused control (no ⌘, ⌃ or ⌥).
    public static func isPressKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        return [49, 36, 76].contains(event.keyCode)
    }
}

extension NSView {
    /// Leaves a decorative view (an icon beside a label, a text the
    /// element's label already says) out of the accessibility tree. A
    /// control's cell is the element AppKit shows, so it goes too.
    public func hideFromAccessibility() {
        setAccessibilityElement(false)
        (self as? NSControl)?.cell?.setAccessibilityElement(false)
    }
}

/// A custom view that is a button to VoiceOver and to the keyboard (5.3a):
/// an accessibility element with the button role whose press runs
/// `performPress()`; a key view while Full Keyboard Access is on (always,
/// with `isAlwaysKeyView`: the address field, which stands for a text
/// field); Space, Return or Enter press it; AppKit's focus ring follows its
/// shape (`focusRingCornerRadius`, `FocusRing`). The space icons, the
/// Essentials' tiles, the address field and the overflow indicators.
open class PressableView: NSView {
    /// A key view in either keyboard mode (a text field stand-in).
    open var isAlwaysKeyView: Bool { false }
    /// The ring's corner (the view's own fill's).
    open var focusRingCornerRadius: CGFloat { FocusRing.controlCornerRadius }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        focusRingType = .default
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// What a click, Space, Return or VoiceOver's press does.
    open func performPress() {}

    open override var acceptsFirstResponder: Bool { isAlwaysKeyView || KeyboardAccess.allControls }
    open override var canBecomeKeyView: Bool { acceptsFirstResponder && window != nil && !isHiddenOrHasHiddenAncestor }

    open override func keyDown(with event: NSEvent) {
        if KeyboardAccess.isPressKey(event) {
            performPress()
        } else {
            super.keyDown(with: event)
        }
    }

    open override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { noteFocusRingMaskChanged() }
        return became
    }

    open override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { noteFocusRingMaskChanged() }
        return resigned
    }

    open override var focusRingMaskBounds: NSRect { bounds }

    open override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: focusRingCornerRadius, yRadius: focusRingCornerRadius).fill()
    }

    open override func accessibilityPerformPress() -> Bool {
        performPress()
        return true
    }
}

/// VoiceOver's reading order for a container whose subviews are not in
/// screen order (5.3a: the sidebar adds its footer before its top bar):
/// top to bottom, then leading to trailing, by each element's frame on
/// screen; elements whose tops fall in the same `tolerance`-point band share a line.
public enum ReadingOrder {
    public static let tolerance: CGFloat = 4

    public static func sorted(_ elements: [Any]) -> [Any] {
        func frame(_ element: Any) -> NSRect {
            (element as? NSAccessibilityProtocol)?.accessibilityFrame() ?? .zero
        }
        // Screen coordinates: a larger maxY is higher up; tops are bucketed so the order is a strict one.
        let keyed = elements.enumerated().map { offset, element in
            let frame = frame(element)
            return (line: -(frame.maxY / tolerance).rounded(), x: frame.minX, offset: offset, element: element)
        }
        return keyed.sorted { ($0.line, $0.x, $0.offset) < ($1.line, $1.x, $1.offset) }.map(\.element)
    }
}

/// Spoken notices (5.3a): a toast, a change VoiceOver would not see
/// otherwise. `NSAccessibility`'s announcement, posted from the window that
/// shows it; `last` keeps the latest for the spikes and tests.
public enum Announcement {
    public private(set) static var last: String?
    /// Announcements posted since launch (spikes compare counts).
    public private(set) static var count = 0

    public static func post(_ message: String, from view: NSView?) {
        last = message
        count += 1
        let element: Any = view?.window ?? NSApplication.shared.mainWindow ?? NSApplication.shared
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
