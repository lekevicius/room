import AppKit
import Observation
import UIKitCore

/// Phase 1.4 overlay spike: an `NSGlassEffectView` panel above the card
/// (palette stand-in) and a hover-revealed sidebar that slides over the card,
/// driven by a local mouse-moved monitor so tracking works over the web view.
@Observable
final class OverlaySpike {
    @ObservationIgnored private weak var rootView: NSView?
    @ObservationIgnored private var glass: NSGlassEffectView?
    @ObservationIgnored private let revealPanel = NSGlassEffectView()
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var isRevealed = false

    /// Counters the spike reads back.
    private(set) var overlayHoverCount = 0
    private(set) var overlayClickCount = 0
    private(set) var revealCount = 0
    /// `mouseMoved` events seen while the pointer was over the page view.
    private(set) var movesOverPage = 0

    /// Width of the left-edge band that reveals the sidebar, and the dwell (spec §E).
    let edgeBand: CGFloat = 4
    let dwell: Duration = .milliseconds(150)

    var isHoverRevealEnabled = false {
        didSet {
            guard isHoverRevealEnabled != oldValue else { return }
            isHoverRevealEnabled ? installMonitor() : removeMonitor()
        }
    }

    init(rootView: NSView) {
        self.rootView = rootView
        revealPanel.cornerRadius = 10
        let label = NSTextField(labelWithString: "Hover-revealed sidebar")
        label.frame = NSRect(x: 16, y: 16, width: 220, height: 20)
        let content = NSView()
        content.addSubview(label)
        revealPanel.contentView = content
        revealPanel.setAccessibilityIdentifier("reveal-panel")
    }

    // MARK: Glass overlay

    var isGlassOverlayShown: Bool { glass != nil }

    func toggleGlassOverlay() {
        if let glass {
            glass.removeFromSuperview()
            self.glass = nil
            return
        }
        guard let rootView else { return }
        let overlay = NSGlassEffectView()
        overlay.cornerRadius = 16
        let content = HoverClickView { [weak self] event in
            switch event {
            case .entered: self?.overlayHoverCount += 1
            case .clicked: self?.overlayClickCount += 1
            }
        }
        overlay.contentView = content
        let size = NSSize(width: 420, height: 220)
        overlay.frame = NSRect(
            x: (rootView.bounds.width - size.width) / 2 + 100,
            y: rootView.isFlipped ? 140 : rootView.bounds.height - 140 - size.height,
            width: size.width,
            height: size.height
        )
        overlay.autoresizingMask = [.minXMargin, .maxXMargin, rootView.isFlipped ? .maxYMargin : .minYMargin]
        overlay.setAccessibilityIdentifier("glass-overlay")
        rootView.addSubview(overlay)
        glass = overlay
    }

    // MARK: Hover reveal

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.mouseMoved(event)
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        dwellTask?.cancel()
        setRevealed(false)
    }

    private func mouseMoved(_ event: NSEvent) {
        guard let rootView, event.window === rootView.window else { return }
        let point = rootView.convert(event.locationInWindow, from: nil)
        // hitTest takes the point in the superview's coordinates.
        let hitPoint = rootView.superview?.convert(event.locationInWindow, from: nil) ?? point
        if let hit = rootView.hitTest(hitPoint), isOverPage(hit) {
            movesOverPage += 1
        }
        if point.x <= edgeBand {
            guard dwellTask == nil, !isRevealed else { return }
            dwellTask = Task { [weak self, dwell] in
                try? await Task.sleep(for: dwell)
                guard let self, !Task.isCancelled else { return }
                self.dwellTask = nil
                self.setRevealed(true)
            }
        } else {
            dwellTask?.cancel()
            dwellTask = nil
            if isRevealed, point.x > revealPanel.frame.maxX + 24 { setRevealed(false) }
        }
    }

    private func isOverPage(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.accessibilityIdentifier() == "web-contents" { return true }
            current = candidate.superview
        }
        return false
    }

    private func setRevealed(_ revealed: Bool) {
        guard let rootView, revealed != isRevealed else { return }
        isRevealed = revealed
        let width: CGFloat = 260
        let inset: CGFloat = 6
        let height = rootView.bounds.height - 2 * inset
        let shown = NSRect(x: inset, y: inset, width: width, height: height)
        let hidden = shown.offsetBy(dx: -(width + inset + 20), dy: 0)
        if revealed {
            revealCount += 1
            revealPanel.frame = hidden
            revealPanel.autoresizingMask = [.height]
            rootView.addSubview(revealPanel)
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            revealPanel.animator().frame = revealed ? shown : hidden
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.isRevealed == false { self?.revealPanel.removeFromSuperview() }
            }
        })
    }
}

/// Glass overlay content: reports hover and clicks, shows them as text.
private final class HoverClickView: NSView {
    enum Event { case entered, clicked }

    private let label = NSTextField(labelWithString: "Overlay — hover and click me")
    private let onEvent: (Event) -> Void
    private var clicks = 0

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: bounds.midY - 12, width: bounds.width, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        label.stringValue = "Hovering"
        onEvent(.entered)
    }

    override func mouseExited(with event: NSEvent) {
        label.stringValue = clicks == 0 ? "Overlay — hover and click me" : "Clicked \(clicks)×"
    }

    override func mouseDown(with event: NSEvent) {
        clicks += 1
        label.stringValue = "Clicked \(clicks)×"
        onEvent(.clicked)
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
