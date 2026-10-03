import CoreGraphics
import Design

/// The card's split between the page and the docked DevTools pane below it
/// (ROADMAP 2.6 task 4): the divider drags between the minimums; the pane's
/// share of the card is what is remembered.
public enum DevToolsSplit {
    /// The pane's height for `fraction` of a card `height` tall, within the minimums.
    public static func paneHeight(fraction: CGFloat, height: CGFloat) -> CGFloat {
        clampPane((height * fraction).rounded(), height: height)
    }

    /// The pane's share after dragging the divider to `y` (from the card's top).
    public static func fraction(dividerAt y: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return DevToolsMetrics.defaultFraction }
        return clampPane(height - y, height: height) / height
    }

    private static func clampPane(_ pane: CGFloat, height: CGFloat) -> CGFloat {
        let upper = height - DevToolsMetrics.minPageHeight
        guard upper >= DevToolsMetrics.minPaneHeight else { return max(0, (height / 2).rounded()) }
        return min(max(pane, DevToolsMetrics.minPaneHeight), upper)
    }
}
