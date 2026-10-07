import CoreGraphics
import Design

/// The sidebar's top bar beside the traffic lights (the Room Browser
/// design, 2026-10-07): the sidebar toggle after the zoom button, Back,
/// Forward and Reload at the trailing end (the rows' trailing inset), the
/// extensions packed against Back (the accessory strip spans the gap and
/// its content aligns trailing), every button a `topBarButtonSize` square
/// centred on the traffic lights. A sidebar too narrow for all of it shrinks the
/// buttons to `topBarButtonMinSize`, then drops the toggle (⌘S remains);
/// the extensions get what is left, possibly nothing.
public struct TopBarLayout: Equatable, Sendable {
    /// `nil` while the toggle does not fit.
    public var toggle: CGRect?
    /// Back, Forward, Reload: three buttons wide.
    public var navigation: CGRect
    /// The extensions' strip (zero width when nothing fits).
    public var accessory: CGRect
    /// Every button's side.
    public var buttonSize: CGFloat
    /// The bar's bottom edge at full size (the address row hangs from it).
    public var bottom: CGFloat

    public init(width: CGFloat, trafficLights: TrafficLightGeometry) {
        let full = SidebarMetrics.topBarButtonSize
        let gap = SidebarMetrics.topBarGroupGap
        let centerY = trafficLights.centerY(fallback: SidebarMetrics.headerHeight / 2)
        let leading = trafficLights.leadingX(gap: SidebarMetrics.topBarLeadingGap, edgeInset: SidebarMetrics.rowHorizontalInset)
        let trailing = width - SidebarMetrics.headerTrailingInset
        let room = max(0, trailing - leading)
        let withToggle = min(full, (room - gap) / 4)
        let showsToggle = withToggle >= SidebarMetrics.topBarButtonMinSize
        let size = showsToggle ? withToggle : max(0, min(full, room / 3))
        let y = centerY - size / 2
        toggle = showsToggle ? CGRect(x: leading, y: y, width: size, height: size) : nil
        navigation = CGRect(x: trailing - 3 * size, y: y, width: 3 * size, height: size)
        let accessoryX = toggle.map { $0.maxX + gap } ?? leading
        accessory = CGRect(x: accessoryX, y: y, width: max(0, navigation.minX - gap - accessoryX), height: size)
        buttonSize = size
        bottom = centerY + full / 2
    }
}
