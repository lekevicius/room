import Design
import Foundation
import Testing
@testable import Chrome

/// A clock the test advances by hand.
final class ManualScheduler: ToastScheduler {
    var now: TimeInterval = 0
    private var timers: [(at: TimeInterval, timer: Timer)] = []

    final class Timer: ToastTimer {
        var fire: (@MainActor () -> Void)?
        func cancel() { fire = nil }
    }

    func schedule(after delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> ToastTimer {
        let timer = Timer()
        timer.fire = fire
        timers.append((now + delay, timer))
        return timer
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
        let due = timers.filter { $0.at <= now }
        timers.removeAll { $0.at <= now }
        for entry in due { entry.timer.fire?() }
    }
}

@Suite("Toasts (spec §F)")
struct ToastQueueTests {
    let clock = ManualScheduler()
    let queue: ToastQueue
    var events: [ToastQueue.Event] { recorder.events }
    private let recorder = Recorder()

    final class Recorder { var events: [ToastQueue.Event] = [] }

    init() {
        queue = ToastQueue(scheduler: clock)
        queue.onEvent = { [recorder] in recorder.events.append($0) }
    }

    @Test("Auto-dismiss after 2 s, or 5 s with a button")
    func durations() {
        queue.show(Toast(id: "copy", message: "Copied URL"))
        clock.advance(by: Timing.toast - 0.01)
        #expect(queue.current != nil)
        clock.advance(by: 0.02)
        #expect(queue.current == nil)

        queue.show(Toast(id: "closed", message: "Tabs closed", action: .init(title: "Undo") {}))
        clock.advance(by: Timing.toast + 0.5)
        #expect(queue.current != nil, "a toast with a button stays longer")
        clock.advance(by: Timing.toastWithAction - Timing.toast)
        #expect(queue.current == nil)
        #expect(events == [.appear(id: "copy"), .dismiss(id: "copy"), .appear(id: "closed"), .dismiss(id: "closed")])
    }

    @Test("One at a time: the same id replaces with a pop, another id replaces without")
    func replacement() {
        queue.show(Toast(id: "copy", message: "Copied URL"))
        clock.advance(by: 1.5)
        queue.show(Toast(id: "copy", message: "Copied URL"))
        clock.advance(by: 1.5)
        #expect(queue.current != nil, "a replacement restarts the countdown")
        queue.show(Toast(id: "renamed", message: "Tab renamed"))
        #expect(events == [.appear(id: "copy"), .replace(id: "copy", pop: true), .replace(id: "renamed", pop: false)])
        #expect(queue.current?.id == "renamed")
    }

    @Test("Hover pauses the countdown; leaving resumes with the time that was left")
    func hoverPauses() {
        queue.show(Toast(id: "copy", message: "Copied URL"))
        clock.advance(by: 1.5)
        queue.setHovering(true)
        clock.advance(by: 30)
        #expect(queue.current != nil)
        queue.setHovering(false)
        clock.advance(by: 0.4)
        #expect(queue.current != nil)
        clock.advance(by: 0.2)
        #expect(queue.current == nil)
    }

    @Test("The button runs its handler and dismisses the toast")
    func action() {
        var undone = 0
        queue.show(Toast(id: "closed", message: "Tabs closed", action: .init(title: "Undo") { undone += 1 }, duration: Timing.undoToast))
        clock.advance(by: Timing.toastWithAction + 1)
        #expect(queue.current != nil, "explicit duration (Clear's 8 s Undo)")
        queue.performAction()
        #expect(undone == 1)
        #expect(queue.current == nil)
        clock.advance(by: 10)
        #expect(undone == 1)
    }
}
