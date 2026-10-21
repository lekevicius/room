import AppKit
import Design

/// The top 5% of the card as a window drag handle while the sidebar is hidden
/// (spec §E, Zen `drag-window-from-content`; Chapter 1 carry-over). The page
/// keeps its clicks there: a press goes to the page as always, and only once
/// it moves `ContentDragMetrics.contentDragThreshold` does it become a window
/// drag (the page then gets a mouse-up, so it ends its press). Presses on
/// Room's own controls over the page (the find bar) are left alone.
final class ContentDragMonitor {
    private weak var rootView: BrowserWindowView?
    private var monitor: Any?
    private var press: (start: CGPoint, event: NSEvent)?
    private var releaseTimer: Timer?

    init(rootView: BrowserWindowView) {
        self.rootView = rootView
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        releaseTimer?.invalidate()
    }

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                    self?.handle(event) ?? event
                }
            } else {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                press = nil
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let rootView, let window = rootView.window, event.window === window else { return event }
        let point = rootView.convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            press = nil
            guard event.clickCount == 1, ContentDragGeometry.band(card: rootView.currentLayout.card).contains(point),
                  isPage(rootView.hitTest(rootView.superview?.convert(event.locationInWindow, from: nil) ?? point)) else { return event }
            press = (point, event)
            return event
        case .leftMouseDragged:
            guard let press else { return event }
            guard ContentDragGeometry.startsWindowDrag(from: press.start, to: point) else { return event }
            self.press = nil
            window.performDrag(with: event)
            endPagePress(at: event.locationInWindow, in: window)
            return nil
        default:
            press = nil
            return event
        }
    }

    /// The window drag took the mouse-up: once the button is up, the page gets one of its own.
    private func endPagePress(at location: NSPoint, in window: NSWindow) {
        releaseTimer?.invalidate()
        if NSEvent.pressedMouseButtons & 1 == 0 { return Self.postMouseUp(in: window) }
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self, weak window] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            MainActor.assumeIsolated {
                self?.releaseTimer = nil
                if let window { Self.postMouseUp(in: window) }
            }
        }
    }

    private static func postMouseUp(in window: NSWindow) {
        guard let up = NSEvent.mouseEvent(with: .leftMouseUp, location: window.mouseLocationOutsideOfEventStream, modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else { return }
        NSApp.postEvent(up, atStart: false)
    }

    /// The press is on the page itself, not on a control, field or glass panel over it.
    private func isPage(_ view: NSView?) -> Bool {
        guard let rootView, var current = view, current.isDescendant(of: rootView.cardView) else { return false }
        while current !== rootView.cardView {
            if current is NSControl || current is NSText || current is NSGlassEffectView { return false }
            guard let parent = current.superview else { return false }
            current = parent
        }
        return true
    }
}
