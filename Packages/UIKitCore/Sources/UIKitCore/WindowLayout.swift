import AppKit
import Design

/// The side of the window the sidebar docks on (Settings ▸ Appearance, ROADMAP 2.8).
/// The traffic lights stay where AppKit puts them: with the sidebar on the
/// right they sit over the card's top-left corner, as with the sidebar hidden.
public enum SidebarEdge: Sendable, Equatable {
    case left, right
}

/// Frames of the window's regions in the (flipped) root view. Pure, so the
/// geometry is unit-tested without a window.
public struct WindowLayout: Equatable, Sendable {
    public var sidebar: CGRect
    /// Splitter hit area; `nil` while the sidebar is closed.
    public var splitter: CGRect?
    public var card: CGRect

    /// The card never gets narrower than this; the sidebar gives way first.
    public static let minimumCardWidth: CGFloat = 320

    /// `pageFullscreen`: a page's element fullscreen (a video, `requestFullscreen()`)
    /// takes the whole window, sidebar hidden and no inset.
    public static func compute(bounds: CGRect, sidebarWidth: CGFloat, isSidebarOpen: Bool, pageFullscreen: Bool = false,
                               edge: SidebarEdge = .left) -> WindowLayout {
        let edgeX = edge == .left ? bounds.minX : bounds.maxX
        if pageFullscreen {
            return WindowLayout(sidebar: CGRect(x: edgeX, y: bounds.minY, width: 0, height: bounds.height), splitter: nil, card: bounds)
        }
        let inset = CardMetrics.inset
        let width = isSidebarOpen ? effectiveSidebarWidth(sidebarWidth, availableWidth: bounds.width) : 0
        // Between the card and the sidebar, and on the card's outer side.
        let inner = isSidebarOpen ? CardMetrics.sidebarSideInset : inset
        let cardWidth = max(0, bounds.width - width - inner - inset)
        let cardX = edge == .left ? bounds.minX + width + inner : bounds.minX + inset
        let card = CGRect(x: cardX, y: bounds.minY + inset, width: cardWidth, height: max(0, bounds.height - 2 * inset))
        let sidebar = CGRect(x: edge == .left ? bounds.minX : bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
        // Mostly inside the sidebar so the page keeps its edge.
        let hit = SidebarMetrics.splitterHitWidth
        let splitterX = edge == .left ? sidebar.maxX - hit + 2 : sidebar.minX - 2
        let splitter = isSidebarOpen ? CGRect(x: splitterX, y: bounds.minY, width: hit, height: bounds.height) : nil
        return WindowLayout(sidebar: sidebar, splitter: splitter, card: card)
    }

    /// The hover-revealed overlay's frame (spec §E): the sidebar's width,
    /// floating `RevealMetrics.overlayInset` from the top, bottom and its own edge.
    public static func overlayFrame(bounds: CGRect, sidebarWidth: CGFloat, edge: SidebarEdge = .left) -> CGRect {
        let inset = RevealMetrics.overlayInset
        let width = effectiveSidebarWidth(sidebarWidth, availableWidth: bounds.width - inset)
        let x = edge == .left ? bounds.minX + inset : bounds.maxX - inset - width
        return CGRect(x: x, y: bounds.minY + inset, width: width, height: max(0, bounds.height - 2 * inset))
    }

    /// The width a splitter drag proposes: the pointer's distance from the sidebar's
    /// edge of the window, plus where in the splitter it grabbed (`grabOffset`).
    public static func proposedWidth(pointerX: CGFloat, bounds: CGRect, grabOffset: CGFloat, edge: SidebarEdge) -> CGFloat {
        (edge == .left ? pointerX - bounds.minX : bounds.maxX - pointerX) + grabOffset
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
