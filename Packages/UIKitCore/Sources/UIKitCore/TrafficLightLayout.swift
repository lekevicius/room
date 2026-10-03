import AppKit
import Design

/// Where the traffic lights are, measured from the content view's top-left
/// corner. Never used to move them: layout flows around these frames.
public struct TrafficLightGeometry: Equatable, Sendable {
    /// Union of the close, minimize and zoom buttons; `nil` when they are not
    /// in this window (fullscreen moves them to the menu-bar reveal window)
    /// or hidden.
    public var buttonsRect: CGRect?

    public init(buttonsRect: CGRect?) {
        self.buttonsRect = buttonsRect
    }

    public static let none = TrafficLightGeometry(buttonsRect: nil)

    /// First x where header content may start: after the zoom button plus
    /// `gap`, or `edgeInset` when there are no buttons beside the header.
    public func leadingX(gap: CGFloat, edgeInset: CGFloat) -> CGFloat {
        buttonsRect.map { $0.maxX + gap } ?? edgeInset
    }

    /// The same buttons seen from a view whose origin is at `origin` in the
    /// content view (the hover-revealed overlay).
    public func relative(to origin: CGPoint) -> TrafficLightGeometry {
        TrafficLightGeometry(buttonsRect: buttonsRect?.offsetBy(dx: -origin.x, dy: -origin.y))
    }

    /// Distance from the top of the content view to the buttons' centre line,
    /// or `fallback` when there are no buttons.
    public func centerY(fallback: CGFloat) -> CGFloat {
        buttonsRect?.midY ?? fallback
    }
}

/// Measures the standard window buttons and reports changes. Re-measures on
/// resize, fullscreen transitions, title, style-mask, appearance and backing
/// changes, and whenever AppKit re-lays out the titlebar.
public final class TrafficLightLayout {
    public private(set) var geometry: TrafficLightGeometry
    public var onChange: ((TrafficLightGeometry) -> Void)?

    private weak var window: NSWindow?
    private var tokens: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []

    public init(window: NSWindow) {
        self.window = window
        geometry = Self.measure(window)
        observe(window)
    }

    isolated deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// The floating cluster faded the buttons out (spec §E): they keep their
    /// frames and still count as present; hidden, they take no clicks.
    public private(set) var areButtonsHidden = false

    public func setButtonsHidden(_ hidden: Bool) {
        guard hidden != areButtonsHidden, let window else { return }
        areButtonsHidden = hidden
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        if hidden {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Motion.standard
                buttons.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard self?.areButtonsHidden == true else { return }
                    buttons.forEach { $0.isHidden = true }
                }
            })
        } else {
            buttons.forEach { $0.isHidden = false }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.fast
                buttons.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    /// Re-measures; calls `onChange` if the geometry moved.
    public func update() {
        let new = Self.measure(window, includingHidden: areButtonsHidden)
        guard new != geometry else { return }
        geometry = new
        onChange?(new)
    }

    public static func measure(_ window: NSWindow?, includingHidden: Bool = false) -> TrafficLightGeometry {
        guard let window, let content = window.contentView, !window.styleMask.contains(.fullScreen) else {
            return .none
        }
        var union: CGRect?
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), includingHidden || !button.isHidden,
                  button.window === window, let superview = button.superview else { continue }
            let inContent = content.convert(superview.convert(button.frame, to: nil), from: nil)
            let fromTop = CGRect(
                x: inContent.minX,
                y: content.isFlipped ? inContent.minY : content.bounds.height - inContent.maxY,
                width: inContent.width,
                height: inContent.height
            )
            union = union?.union(fromTop) ?? fromTop
        }
        return TrafficLightGeometry(buttonsRect: union)
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in names {
            tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        // AppKit rebuilds the titlebar on title and style changes; the
        // buttons' container posts frame changes when it re-lays them out.
        if let container = window.standardWindowButton(.zoomButton)?.superview {
            container.postsFrameChangedNotifications = true
            tokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: container, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        let refresh: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.update() } }
        }
        observations = [
            window.observe(\.title) { _, _ in refresh() },
            window.observe(\.styleMask) { _, _ in refresh() },
            window.observe(\.effectiveAppearance) { _, _ in refresh() },
        ]
    }
}
