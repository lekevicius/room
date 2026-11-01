import CoreGraphics
import Design

/// Where DevTools shows (5.10, the user on build 24: "no placements, no close button"): docked at a
/// side of the card, or in a window of its own. Remembered across launches (a view preference).
public enum DevToolsPlacement: String, CaseIterable, Sendable {
    case bottom, right, left, window

    /// The pane sits beside the page (left or right) rather than under it.
    public var isHorizontal: Bool { self == .left || self == .right }
    /// The pane is before the page along the split's axis (left).
    public var isLeading: Bool { self == .left }
    public var isDocked: Bool { self != .window }

    public var title: String {
        switch self {
        case .bottom: "Dock to Bottom"
        case .right: "Dock to Right"
        case .left: "Dock to Left"
        case .window: "Open in Window"
        }
    }

    /// The placement stored under `key`, else the first-run default (bottom, as since 2.6).
    public static func stored(_ value: String?) -> DevToolsPlacement { value.flatMap(DevToolsPlacement.init(rawValue:)) ?? .bottom }
}

/// The card's split between the page and the docked DevTools pane (ROADMAP 2.6 task 4; 5.10 for
/// the sides): the divider drags between the minimums; the pane's share of the card along the
/// split's axis is what is remembered.
public enum DevToolsSplit {
    /// The pane's length for `fraction` of a card `length` long (its height docked at the bottom,
    /// its width at a side), within the minimums.
    public static func paneHeight(fraction: CGFloat, height: CGFloat) -> CGFloat {
        clampPane((height * fraction).rounded(), height: height)
    }

    /// The pane's share after dragging the divider to `y` (from the card's top), the pane after it.
    public static func fraction(dividerAt y: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return DevToolsMetrics.defaultFraction }
        return clampPane(height - y, height: height) / height
    }

    /// The pane's share after dragging the divider to `position` along the axis, with the pane
    /// before the divider (`leading`, docked left) or after it.
    public static func fraction(dividerAt position: CGFloat, length: CGFloat, leading: Bool) -> CGFloat {
        guard length > 0 else { return DevToolsMetrics.defaultFraction }
        return clampPane(leading ? position : length - position, height: length) / length
    }

    private static func clampPane(_ pane: CGFloat, height: CGFloat) -> CGFloat {
        let upper = height - DevToolsMetrics.minPageHeight
        guard upper >= DevToolsMetrics.minPaneHeight else { return max(0, (height / 2).rounded()) }
        return min(max(pane, DevToolsMetrics.minPaneHeight), upper)
    }
}
