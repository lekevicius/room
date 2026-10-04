import AppKit
import Design

/// Drives `SidebarReveal` for one window (spec §E): follows the pointer
/// with event monitors (a local one in the app, a global one outside it
/// while the overlay shows, so leaving toward the Dock is seen), runs the
/// dwell and grace timers, and slides the overlay in and out. Works only
/// while the sidebar is hidden and no page is fullscreen.
public final class SidebarRevealController {
    public private(set) var state = SidebarReveal()
    /// Anything else anchored to the overlay that keeps it open (the
    /// palette, an inline rename, the space form). Menus, popovers and a
    /// pressed mouse button keep it open on their own.
    public var keepOpen: [() -> Bool] = []
    /// The overlay appeared or went (the floating cluster, toasts, spikes).
    public var onChange: ((Bool) -> Void)?
    /// Every pointer position it sees while the sidebar is hidden (the cluster's fade).
    var onPointer: ((CGPoint) -> Void)?
    /// The clock (`ProcessInfo.systemUptime`, the clock of `NSEvent.timestamp`).
    public var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    private weak var rootView: BrowserWindowView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var timer: Timer?
    private var openMenus = 0
    private var openPopovers = 0
    private var tokens: [NSObjectProtocol] = []

    init(rootView: BrowserWindowView) {
        self.rootView = rootView
        let center = NotificationCenter.default
        let changes: [(Notification.Name, Int)] = [
            (NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1),
            (NSPopover.willShowNotification, 1), (NSPopover.didCloseNotification, -1),
        ]
        for (name, delta) in changes {
            let isMenu = name == NSMenu.didBeginTrackingNotification || name == NSMenu.didEndTrackingNotification
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if isMenu { self.openMenus = max(0, self.openMenus + delta) } else { self.openPopovers = max(0, self.openPopovers + delta) }
                    self.evaluate()
                }
            })
        }
    }

    isolated deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
        stop()
    }

    /// The overlay shows (hovered or pinned).
    public var isShown: Bool { state.isShown }
    public var isPinned: Bool { state.isPinned }

    /// The hover reveal applies: the sidebar is hidden and no page is fullscreen.
    var isEnabled: Bool {
        guard let rootView else { return false }
        return !rootView.isSidebarOpen && !rootView.isPageFullscreen && rootView.window != nil
    }

    /// The sidebar was hidden or docked, a page entered or left fullscreen.
    func availabilityChanged() {
        if isEnabled {
            start()
        } else {
            state.dismiss()
            stop()
            apply(animated: false)
        }
    }

    /// ⌥⌘S (spec §E): pins the overlay open, or unpins and hides it.
    public func togglePin() {
        guard isEnabled else { return }
        state.togglePin()
        apply(animated: true)
        evaluate()
    }

    /// Hides the overlay now (Esc, a command that leaves it), unpinned.
    public func dismiss(animated: Bool = true) {
        state.dismiss()
        apply(animated: animated)
    }

    /// Something in `keepOpen` changed (the palette closed): re-check now.
    public func keepOpenChanged() { evaluate() }

    // MARK: Pointer

    private func start() {
        guard localMonitor == nil else { return }
        rootView?.window?.acceptsMouseMovedEvents = true
        lastPointer = convertFromScreen(NSEvent.mouseLocation)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown,
                                                                   .otherMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
            return event
        }
        evaluate()
    }

    private func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        stopGlobalMonitor()
        timer?.invalidate()
        timer = nil
    }

    private func startGlobalMonitor() {
        guard globalMonitor == nil else { return }
        // Mouse events outside the app need no permission (keys would).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            // Outside the app `locationInWindow` is in screen coordinates.
            let screenPoint = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastPointer = self.convertFromScreen(screenPoint)
                self.onPointer?(self.lastPointer)
                self.evaluate()
            }
        }
    }

    private func stopGlobalMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let rootView, let window = rootView.window else { return }
        // The event's own location (synthetic events in spikes carry theirs; the cursor may be elsewhere).
        if event.window === window {
            lastPointer = rootView.convert(event.locationInWindow, from: nil)
        } else if let other = event.window {
            lastPointer = convertFromScreen(other.convertPoint(toScreen: event.locationInWindow))
        }
        onPointer?(lastPointer)
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // A click in the window outside the overlay (the page): it goes, pinned or not (spec §E).
            guard event.window === window, state.isShown,
                  RevealZone.of(lastPointer, contentSize: rootView.bounds.size, overlay: rootView.overlayFrame, edge: rootView.sidebarEdge) == .elsewhere
            else { return evaluate() }
            state.pageClicked()
            apply(animated: true)
        default:
            evaluate()
        }
    }

    /// The pointer's last known place in the root view's (flipped) coordinates.
    private var lastPointer = CGPoint(x: -10_000, y: -10_000)

    private func convertFromScreen(_ point: CGPoint) -> CGPoint {
        guard let rootView, let window = rootView.window else { return point }
        return rootView.convert(window.convertPoint(fromScreen: point), from: nil)
    }

    private var isKeptOpen: Bool {
        openMenus > 0 || openPopovers > 0 || NSEvent.pressedMouseButtons != 0 || keepOpen.contains { $0() }
    }

    /// Runs the state machine with the pointer where it is now.
    private func evaluate() {
        guard isEnabled, let rootView else { return }
        // A window that is not key keeps whatever it shows until it is key again.
        guard rootView.window?.isKeyWindow == true || state.isShown else { return }
        let overlay = state.isShown ? rootView.overlayFrame : nil
        let zone = RevealZone.of(lastPointer, contentSize: rootView.bounds.size, overlay: overlay, edge: rootView.sidebarEdge)
        state.update(zone: zone, keepOpen: isKeptOpen, now: now())
        apply(animated: true)
    }

    /// Shows the state: the overlay, the global monitor while it shows, the next timer.
    private func apply(animated: Bool) {
        guard let rootView else { return }
        let shown = state.isShown && isEnabled
        if rootView.isOverlayShown != shown {
            rootView.setOverlayShown(shown, animated: animated)
            onChange?(shown)
        }
        if shown { startGlobalMonitor() } else { stopGlobalMonitor() }
        timer?.invalidate()
        timer = nil
        if let deadline = state.deadline {
            let timer = Timer(timeInterval: max(0, deadline - now()), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
}
