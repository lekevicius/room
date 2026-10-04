import CoreGraphics
import Design
import Foundation

/// Where the pointer is, as far as the hidden sidebar is concerned (spec §E).
public enum RevealZone: Equatable, Sendable {
    /// The band at the window's edge on the sidebar's side.
    case band
    /// Over the revealed overlay (or the margin between it and the edge).
    case overlay
    /// Outside the window but near the revealed overlay (on its way to the Dock).
    case tolerance
    /// Anywhere else: over the page, or outside the window away from the overlay.
    case elsewhere

    /// Which zone `point` is in. `point` is in the window's content
    /// coordinates, origin top-left (flipped); `overlay` is the revealed
    /// overlay's frame there, `nil` while it is not shown.
    public static func of(_ point: CGPoint, contentSize: CGSize, overlay: CGRect?, edge: SidebarEdge = .left) -> RevealZone {
        let bounds = CGRect(origin: .zero, size: contentSize)
        if bounds.contains(point) {
            // The overlay and the inset between it and the window's edge.
            switch edge {
            case .left:
                if let overlay, point.x <= overlay.maxX { return .overlay }
                return point.x < RevealMetrics.edgeBand ? .band : .elsewhere
            case .right:
                if let overlay, point.x >= overlay.minX { return .overlay }
                return point.x >= contentSize.width - RevealMetrics.edgeBand ? .band : .elsewhere
            }
        }
        guard let overlay else { return .elsewhere }
        let tolerant = overlay.insetBy(dx: -RevealMetrics.outsideToleranceX, dy: -RevealMetrics.outsideToleranceY)
        return tolerant.contains(point) ? .tolerance : .elsewhere
    }
}

/// The hidden sidebar's hover reveal as a state machine on an injected clock
/// (spec §E): resting `Timing.revealDwell` in the edge band shows the overlay;
/// it stays while the pointer is on it, near it outside the window, or
/// anything anchored to it is open (`keepOpen`: a menu, a popover, the
/// palette, a press in progress), and hides `Timing.revealGrace` after the
/// pointer left. ⌥⌘S pins it until the next ⌥⌘S, ⌘S or a click in the page.
///
/// The driver calls `update` on every pointer move, on keep-open changes
/// and when `deadline` passes, with the time in seconds.
public struct SidebarReveal: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case hidden
        /// In the band since this time.
        case dwelling(since: TimeInterval)
        case shown
        /// Left the overlay at this time; it hides after the grace.
        case leaving(since: TimeInterval)
    }

    public private(set) var phase: Phase = .hidden
    /// ⌥⌘S: shown until unpinned, whatever the pointer does.
    public private(set) var isPinned = false
    public var dwell: TimeInterval
    public var grace: TimeInterval

    public init(dwell: TimeInterval = Timing.revealDwell, grace: TimeInterval = Timing.revealGrace) {
        self.dwell = dwell
        self.grace = grace
    }

    /// The overlay is on screen (sliding out ends with `hidden`).
    public var isShown: Bool {
        switch phase {
        case .shown, .leaving: true
        case .hidden, .dwelling: isPinned
        }
    }

    /// When `update` must run again even if the pointer does not move.
    public var deadline: TimeInterval? {
        guard !isPinned else { return nil }
        switch phase {
        case .dwelling(let since): return since + dwell
        case .leaving(let since): return since + grace
        case .hidden, .shown: return nil
        }
    }

    /// Times compare against `deadline` exactly (`since + dwell`), so a timer
    /// firing at the deadline always moves the phase on.
    public mutating func update(zone: RevealZone, keepOpen: Bool, now: TimeInterval) {
        if isPinned {
            phase = .shown
            return
        }
        let staying = zone == .overlay || zone == .band || zone == .tolerance || keepOpen
        switch phase {
        case .hidden:
            guard zone == .band else { return }
            phase = .dwelling(since: now)
            if dwell <= 0 { phase = .shown }
        case .dwelling(let since):
            if zone != .band {
                phase = .hidden
            } else if now >= since + dwell {
                phase = .shown
            }
        case .shown:
            if !staying { phase = grace <= 0 ? .hidden : .leaving(since: now) }
        case .leaving(let since):
            if staying {
                phase = .shown
            } else if now >= since + grace {
                phase = .hidden
            }
        }
    }

    /// ⌥⌘S: pins a hidden or hovering overlay open; unpins (and hides) a pinned one.
    public mutating func togglePin() {
        if isPinned {
            isPinned = false
            phase = .hidden
        } else {
            isPinned = true
            phase = .shown
        }
    }

    /// A click in the page: the overlay goes, pinned or not.
    public mutating func pageClicked() {
        guard isShown else { return }
        dismiss()
    }

    /// ⌘S docks the sidebar, a page goes fullscreen, the window closes: gone, unpinned.
    public mutating func dismiss() {
        isPinned = false
        phase = .hidden
    }
}
