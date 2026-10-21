import AppKit
import Design

/// The page's top as the window's drag handle while the sidebar is hidden
/// (spec §E; the floating traffic-light cluster that shared this file went
/// with B-114 in 5.1b: the traffic lights now come and go with the sidebar).
public enum ContentDragGeometry {
    /// The top of the card that drags the window while the sidebar is hidden
    /// (spec §E: the top 5% of the content, Zen `drag-window-from-content`).
    public static func band(card: CGRect) -> CGRect {
        CGRect(x: card.minX, y: card.minY, width: card.width, height: (card.height * ContentDragMetrics.contentDragFraction).rounded())
    }

    /// A press in the band becomes a window drag once it has moved this far; until
    /// then (and for a click) it is the page's.
    public static func startsWindowDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= ContentDragMetrics.contentDragThreshold
    }
}

/// What a double-click on a titlebar does, from the user's setting
/// (System Settings ▸ Desktop & Dock ▸ "Double-click a window's title bar to").
public enum TitlebarDoubleClick {
    public static func perform(in window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}
