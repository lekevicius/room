import CoreGraphics

/// The Settings window's size on a display (5.7a, B-120): every pane is the
/// same height, at most `preferredContentHeight` and never taller than the
/// display's visible frame leaves room for; a pane's content scrolls inside
/// it. Pure, so the rule is unit-tested without a window; the app's spike
/// (`-RoomSpike settings -RoomSpikeOnly fit`) runs it over every real pane.
public enum SettingsWindowFit {
    /// The panes' width (the eight sections fit the toolbar at it, 4.4a).
    public static let contentWidth: CGFloat = 560
    /// A pane's height when the display has room (chosen: General and Privacy fit without scrolling on a 1080 pt display).
    public static let preferredContentHeight: CGFloat = 640
    /// Kept between the window and the visible frame's top and bottom (chosen).
    public static let margin: CGFloat = 8
    /// No pane is shorter than this, whatever the display (chosen: the toolbar and a few rows).
    public static let minimumContentHeight: CGFloat = 240

    /// The smallest display Room supports (macOS 26 on a 13-inch MacBook Air at
    /// its "Larger Text" scale, 1024 × 640 points) with the menu bar (33 pt, a
    /// notched display) and a Dock of 64 pt taken: the visible frame the
    /// window has to fit in there.
    public static let smallestVisibleFrame = CGRect(x: 0, y: 64, width: 1024, height: 640 - 33 - 64)

    /// The panes' content height in `visible` (the screen's visible frame) for
    /// a window whose title bar and toolbar take `chrome` points.
    public static func contentHeight(visible: CGRect, chrome: CGFloat) -> CGFloat {
        let room = visible.height - chrome - 2 * margin
        return max(minimumContentHeight, min(preferredContentHeight, room.rounded(.down)))
    }

    /// `frame` moved (never resized) so it lies inside `visible` where it can:
    /// its top first, as AppKit keeps a window's title bar on screen.
    public static func placed(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        if result.maxX > visible.maxX { result.origin.x = visible.maxX - result.width }
        if result.minX < visible.minX { result.origin.x = visible.minX }
        if result.minY < visible.minY { result.origin.y = visible.minY }
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        return result
    }
}
