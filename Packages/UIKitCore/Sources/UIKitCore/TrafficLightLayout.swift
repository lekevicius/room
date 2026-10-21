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

    /// The hidden sidebar took the buttons with it (spec §E as amended by
    /// B-114): they keep their frames and still count as present; hidden,
    /// they take no clicks.
    public private(set) var areButtonsHidden = false

    /// Fades the buttons out or in over `duration` (0: at once), never moving them.
    public func setButtonsHidden(_ hidden: Bool, duration: TimeInterval) {
        guard hidden != areButtonsHidden, let window else { return }
        areButtonsHidden = hidden
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        let fades = duration > 0 && WindowMotion.trafficLights.variant != .instant
        if hidden {
            guard fades else {
                buttons.forEach { $0.alphaValue = 0; $0.isHidden = true }
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                buttons.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard self?.areButtonsHidden == true else { return }
                    buttons.forEach { $0.isHidden = true }
                }
            })
        } else {
            buttons.forEach { $0.isHidden = false }
            guard fades else {
                buttons.forEach { $0.alphaValue = 1 }
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                // They arrive with the sidebar sliding in under them.
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                buttons.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    /// Settings ▸ Appearance ▸ Grey window buttons (spec §I.12: mono traffic lights, optional): each
    /// button drawn without colour through a saturation-0 filter on its own layer, never moved; the
    /// hover glyphs and the inactive window's grey stay AppKit's.
    public var isMonochrome = false {
        didSet { if isMonochrome != oldValue { applyMonochrome() } }
    }

    private func applyMonochrome() {
        guard let window else { return }
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton) {
            if isMonochrome, let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(TrafficLightMetrics.monochromeSaturation, forKey: kCIInputSaturationKey)
                button.wantsLayer = true
                button.layerUsesCoreImageFilters = true
                button.contentFilters = [filter]
            } else if !button.contentFilters.isEmpty {
                button.contentFilters = []
            }
        }
    }

    /// Re-measures; calls `onChange` if the geometry moved.
    public func update() {
        // AppKit makes new buttons when it rebuilds the titlebar (fullscreen, style changes).
        if isMonochrome { applyMonochrome() }
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
