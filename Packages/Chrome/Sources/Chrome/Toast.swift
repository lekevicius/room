import Design
import Foundation

/// A transient one-line notice (spec §F): icon, message, optional button.
public struct Toast {
    /// A toast with the same id as the one showing replaces it with a pop.
    public var id: String
    public var symbol: Symbol?
    public var message: String
    public var action: Action?
    /// Overrides the default (`Timing.toast`, or `Timing.toastWithAction` with a button).
    public var duration: TimeInterval?

    public struct Action {
        public var title: String
        public var handler: @MainActor () -> Void

        public init(title: String, handler: @escaping @MainActor () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    public init(id: String, symbol: Symbol? = nil, message: String, action: Action? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.symbol = symbol
        self.message = message
        self.action = action
        self.duration = duration
    }

    /// How long it stays up when not hovered.
    public var effectiveDuration: TimeInterval {
        duration ?? (action == nil ? Timing.toast : Timing.toastWithAction)
    }
}

/// Anything that can show toasts (the sidebar asks; the window owns the view).
public protocol ToastPresenting: AnyObject {
    func show(_ toast: Toast)
}

/// Time source and timer for the toast rules, so tests drive the clock.
public protocol ToastScheduler: AnyObject {
    var now: TimeInterval { get }
    /// Calls `fire` once after `delay` unless the returned token is cancelled.
    func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> ToastTimer
}

public protocol ToastTimer: AnyObject {
    func cancel()
}

/// The toast rules of spec §F, without views: one toast at a time; a new one
/// replaces the current one (with a pop when the id is the same); it
/// dismisses itself after its duration; hovering pauses the countdown and
/// leaving resumes it with the time that was left.
public final class ToastQueue {
    public enum Event: Equatable {
        /// A toast appeared where none was showing.
        case appear(id: String)
        /// The showing toast was replaced; `pop` when the id is the same.
        case replace(id: String, pop: Bool)
        case dismiss(id: String)
    }

    public private(set) var current: Toast?
    public private(set) var isHovering = false
    public var onEvent: ((Event) -> Void)?

    private let scheduler: ToastScheduler
    private var timer: ToastTimer?
    /// Countdown left when the timer was paused (hover), else the full duration.
    private var remaining: TimeInterval = 0
    private var startedAt: TimeInterval = 0

    public init(scheduler: ToastScheduler) {
        self.scheduler = scheduler
    }

    public func show(_ toast: Toast) {
        let previous = current
        current = toast
        remaining = toast.effectiveDuration
        if let previous {
            onEvent?(.replace(id: toast.id, pop: previous.id == toast.id))
        } else {
            onEvent?(.appear(id: toast.id))
        }
        if !isHovering { startCountdown() } else { timer?.cancel(); timer = nil }
    }

    public func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        guard current != nil else { return }
        if hovering {
            remaining = max(0, remaining - (scheduler.now - startedAt))
            timer?.cancel()
            timer = nil
        } else {
            startCountdown()
        }
    }

    /// Runs the toast's button handler and dismisses it.
    public func performAction() {
        let handler = current?.action?.handler
        dismiss()
        handler?()
    }

    public func dismiss() {
        timer?.cancel()
        timer = nil
        guard let toast = current else { return }
        current = nil
        isHovering = false
        onEvent?(.dismiss(id: toast.id))
    }

    private func startCountdown() {
        timer?.cancel()
        startedAt = scheduler.now
        timer = scheduler.schedule(after: remaining) { [weak self] in self?.dismiss() }
    }
}

/// The real clock: `DispatchQueue.main` timers on the uptime clock.
public final class MainQueueToastScheduler: ToastScheduler {
    public init() {}

    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> ToastTimer {
        let item = DispatchWorkItem { MainActor.assumeIsolated { fire() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return WorkItemTimer(item: item)
    }

    private final class WorkItemTimer: ToastTimer {
        let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}
