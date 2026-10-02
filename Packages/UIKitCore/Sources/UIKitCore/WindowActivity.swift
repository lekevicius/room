import AppKit

/// Tracks whether a window looks active (main window of the active app), the
/// state the material, traffic lights and sidebar dimming follow.
public final class WindowActivity {
    public private(set) var isActive: Bool
    /// Forces a state regardless of focus (snapshot tests; windows in a test
    /// process never become main).
    public var override: Bool? {
        didSet { update() }
    }
    public var onChange: ((Bool) -> Void)?

    private weak var window: NSWindow?
    private var tokens: [NSObjectProtocol] = []

    public init(window: NSWindow) {
        self.window = window
        isActive = Self.measure(window)
        let center = NotificationCenter.default
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didBecomeMainNotification, window),
            (NSWindow.didResignMainNotification, window),
            (NSWindow.didBecomeKeyNotification, window),
            (NSWindow.didResignKeyNotification, window),
            (NSApplication.didBecomeActiveNotification, nil),
            (NSApplication.didResignActiveNotification, nil),
        ]
        for (name, object) in names {
            tokens.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
    }

    isolated deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    public func update() {
        let active = override ?? Self.measure(window)
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }

    private static func measure(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return NSApp.isActive && (window.isMainWindow || window.isKeyWindow)
    }
}
