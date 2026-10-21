import AppKit
import Design
import Model

/// A space's scroll view: horizontal two-finger swipes and ⌃+wheel go to
/// the space switcher (`SidebarController.handleSpaceScroll`) instead of
/// scrolling the list.
final class SpaceScrollView: NSScrollView {
    var spaceScroll: ((NSEvent) -> Bool)?

    override func scrollWheel(with event: NSEvent) {
        if spaceScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }
}

/// One gesture's state.
struct SpaceSwipe {
    enum Axis { case horizontal, vertical }

    var axis: Axis?
    /// Finger travel so far (points, `scrollingDeltaX` summed: + = to the right).
    var travel: CGFloat = 0
    /// Recent deltas with their times, for the release velocity.
    var samples: [(time: TimeInterval, delta: CGFloat)] = []
    /// The momentum events after a handled release are swallowed.
    var swallowsMomentum = false
}

/// ⌃+wheel's cooldown and the precise-scroll accumulator.
struct SpaceWheel {
    var accumulated: CGFloat = 0
    var cooldownUntil: TimeInterval = 0
}

/// Switching by gesture (spec §B): a two-finger horizontal swipe over the
/// sidebar moves the lists with the fingers (`SwipeRules`: 25% of the width
/// or a fling switches, both ends rubber-band, and a release past the last
/// space opens the space window for a new space, 5.7b), and ⌃ + the scroll wheel steps one space per
/// notch with Zen's 200 ms cooldown.
extension SidebarController {
    /// Zen's `scroll-modifier-key` cooldown.
    static let wheelCooldown: TimeInterval = 0.2
    /// Precise (trackpad) ⌃-scroll travel that counts as one notch (chosen).
    static let preciseWheelStep: CGFloat = 30
    /// A swipe locks to horizontal when its first movement is this much more
    /// horizontal than vertical (chosen).
    static let swipeAxisRatio: CGFloat = 1.5
    /// The release velocity is measured over this much of the gesture's end.
    static let velocityWindow: TimeInterval = 0.08

    /// Handles a scroll event over the sidebar; `false` lets the list scroll it.
    func handleSpaceScroll(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.control) { return handleControlWheel(event) }
        guard event.hasPreciseScrollingDeltas else { return false }
        if event.momentumPhase != [] {
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                let swallowed = swipe.swallowsMomentum
                swipe.swallowsMomentum = false
                return swallowed
            }
            return swipe.swallowsMomentum
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipe = SpaceSwipe()
            return false
        }
        if event.phase.contains(.changed) {
            if swipe.axis == nil {
                let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
                guard dx > 0 || dy > 0 else { return false }
                swipe.axis = dx > dy * Self.swipeAxisRatio ? .horizontal : .vertical
            }
            guard swipe.axis == .horizontal else { return false }
            swipe.travel += event.scrollingDeltaX
            swipe.samples.append((event.timestamp, event.scrollingDeltaX))
            swipe.samples.removeAll { event.timestamp - $0.time > Self.velocityWindow }
            trackSwipe()
            return true
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard swipe.axis == .horizontal else { return false }
            endSwipe(cancelled: event.phase.contains(.cancelled))
            swipe.swallowsMomentum = true
            return true
        }
        return false
    }

    /// The fingers' travel as list widths (+ = towards the next space: fingers move left).
    private var swipeProgress: Double {
        let width = max(1, bodyView.listContainer.bounds.width)
        return Double(-swipe.travel / width)
    }

    private func trackSwipe() {
        let spaces = sidebar.spaces
        guard let index = spaces.firstIndex(where: { $0.id == tree.spaceID }) else { return }
        let displayed = SwipeRules.displayedProgress(swipeProgress, index: index, count: spaces.count)
        bodyView.trackSwipe(current: pane.scrollView, neighbour: swipeNeighbour(displayed, index: index, spaces: spaces),
                            progress: CGFloat(displayed))
    }

    /// The list that slides in: the next or previous space's, nothing past
    /// either end (rubber band).
    private func swipeNeighbour(_ progress: Double, index: Int, spaces: [Space]) -> NSView? {
        if progress > 0 {
            return index + 1 < spaces.count ? preparedPane(spaces[index + 1].id)?.scrollView : nil
        }
        if progress < 0, index > 0 { return preparedPane(spaces[index - 1].id)?.scrollView }
        return nil
    }

    private func endSwipe(cancelled: Bool) {
        let spaces = sidebar.spaces
        guard let index = spaces.firstIndex(where: { $0.id == tree.spaceID }) else { return }
        let width = max(1, bodyView.listContainer.bounds.width)
        let span = (swipe.samples.last?.time ?? 0) - (swipe.samples.first?.time ?? 0)
        let velocity = span > 0 ? Double(-swipe.samples.reduce(0) { $0 + $1.delta } / width) / span : 0
        // The fingers' travel, not the damped display: past the last space the lists rubber-band (5.7b).
        let travelled = min(max(swipeProgress, -1), 1)
        let outcome = cancelled ? .stay : SwipeRules.outcome(progress: travelled, velocity: velocity, index: index, count: spaces.count)
        switch outcome {
        case .switchTo(let offset):
            let space = spaces[index + offset]
            guard let target = preparedPane(space.id) else { return }
            bodyView.endSwipe(toNeighbour: true)
            switchPane(to: target, space: space, direction: offset > 0 ? .forward : .backward, animated: true, slides: false)
        case .newSpace:
            // The list springs back and the space window opens for a new space (5.7b, B-122).
            bodyView.endSwipe(toNeighbour: false)
            newSpace()
        case .stay:
            bodyView.endSwipe(toNeighbour: false)
        }
    }

    /// ⌃ + wheel: one space per notch (down = the next), 200 ms apart (spec §B, Zen).
    private func handleControlWheel(_ event: NSEvent) -> Bool {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard delta != 0 else { return true }
        var step = delta
        if event.hasPreciseScrollingDeltas {
            wheel.accumulated += delta
            guard abs(wheel.accumulated) >= Self.preciseWheelStep else { return true }
            step = wheel.accumulated
            wheel.accumulated = 0
        }
        guard event.timestamp >= wheel.cooldownUntil else { return true }
        wheel.cooldownUntil = event.timestamp + Self.wheelCooldown
        showAdjacentSpace(step < 0 ? 1 : -1)
        return true
    }
}
