import AppKit
import Design

/// Frames of the window's regions in the (flipped) root view. Pure, so the
/// geometry is unit-tested without a window.
public struct WindowLayout: Equatable, Sendable {
    public var sidebar: CGRect
    /// Splitter hit area; `nil` while the sidebar is closed.
    public var splitter: CGRect?
    public var card: CGRect

    /// The card never gets narrower than this; the sidebar gives way first.
    public static let minimumCardWidth: CGFloat = 320

    public static func compute(bounds: CGRect, sidebarWidth: CGFloat, isSidebarOpen: Bool) -> WindowLayout {
        let inset = CardMetrics.inset
        let width = isSidebarOpen ? effectiveSidebarWidth(sidebarWidth, availableWidth: bounds.width) : 0
        let leading = isSidebarOpen ? CardMetrics.sidebarSideInset : inset
        let card = CGRect(
            x: bounds.minX + width + leading,
            y: bounds.minY + inset,
            width: max(0, bounds.width - width - leading - inset),
            height: max(0, bounds.height - 2 * inset)
        )
        let sidebar = CGRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        // Mostly inside the sidebar so the page keeps its left edge.
        let hit = SidebarMetrics.splitterHitWidth
        let splitter = isSidebarOpen
            ? CGRect(x: sidebar.maxX - hit + 2, y: bounds.minY, width: hit, height: bounds.height)
            : nil
        return WindowLayout(sidebar: sidebar, splitter: splitter, card: card)
    }

    /// The stored width, limited so the card keeps `minimumCardWidth`.
    public static func effectiveSidebarWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let roomForSidebar = max(SidebarMetrics.minWidth, availableWidth - minimumCardWidth)
        return min(width, roomForSidebar)
    }
}

/// What dragging the splitter to a proposed width does (feature spec §E).
public enum SidebarResize: Equatable, Sendable {
    case open(width: CGFloat)
    /// Dragged under `SidebarMetrics.snapCloseWidth`: the sidebar snaps closed.
    case closed

    public static func outcome(forProposedWidth proposed: CGFloat) -> SidebarResize {
        if proposed < SidebarMetrics.snapCloseWidth { return .closed }
        return .open(width: min(max(proposed, SidebarMetrics.minWidth), SidebarMetrics.maxWidth).rounded())
    }
}
