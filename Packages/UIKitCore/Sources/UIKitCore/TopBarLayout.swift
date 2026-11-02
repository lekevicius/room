import CoreGraphics
import Design

/// The sidebar's top bar beside the traffic lights (5.13, the user's design, Figma 157:233):
/// the sidebar toggle `topBarLeadingGap` after the zoom button, then the extensions (a glass
/// group, leading-aligned in the strip that follows); at the trailing end (the rows' trailing
/// inset) Back (and Forward) and Reload; AppKit's 32 pt glass controls, 8 pt apart, centred on
/// the traffic lights. With no room for the extensions' smallest form (`accessoryMinimum`, the
/// puzzle piece alone) Reload goes first, then the toggle (⌘S remains); the extensions get what
/// is left, possibly nothing.
public struct TopBarLayout: Equatable, Sendable {
    /// `nil` while the toggle does not fit.
    public var toggle: CGRect?
    /// Back (and Forward), then Reload while `showsReload`.
    public var navigation: CGRect
    public var showsReload: Bool
    /// The extensions' strip (zero width when nothing fits).
    public var accessory: CGRect
    /// Every button's side.
    public var buttonSize: CGFloat
    /// The bar's bottom edge (the address row hangs from it).
    public var bottom: CGFloat

    /// `navigationWidth`: the navigation buttons' width with Reload and without it
    /// (`NavigationButtonsView.preferredWidth`); the default is Back alone.
    public init(width: CGFloat, trafficLights: TrafficLightGeometry,
                navigationWidth: (withReload: CGFloat, withoutReload: CGFloat)? = nil,
                accessoryMinimum: CGFloat = GlassControlMetrics.size) {
        let size = GlassControlMetrics.size
        let gap = GlassControlMetrics.gap
        let navigationWidths = navigationWidth ?? (withReload: 2 * size + gap, withoutReload: size)
        let centerY = trafficLights.centerY(fallback: SidebarMetrics.headerHeight / 2)
        let y = centerY - size / 2
        let leading = trafficLights.leadingX(gap: SidebarMetrics.topBarLeadingGap, edgeInset: SidebarMetrics.rowHorizontalInset)
        let trailing = width - SidebarMetrics.headerTrailingInset

        func strip(toggle: Bool, reload: Bool) -> CGFloat {
            let start = toggle ? leading + size + gap : leading
            return trailing - (reload ? navigationWidths.withReload : navigationWidths.withoutReload) - gap - start
        }
        // Reload goes first, then the toggle; failing both, the fullest bar that fits the buttons.
        let choices = [(true, true), (true, false), (false, false)]
        let (showsToggle, reload) = choices.first { strip(toggle: $0.0, reload: $0.1) >= accessoryMinimum }
            ?? choices.first { strip(toggle: $0.0, reload: $0.1) >= 0 }
            ?? (false, false)
        showsReload = reload
        toggle = showsToggle ? CGRect(x: leading, y: y, width: size, height: size) : nil
        let navWidth = reload ? navigationWidths.withReload : navigationWidths.withoutReload
        navigation = CGRect(x: trailing - navWidth, y: y, width: navWidth, height: size)
        let accessoryX = toggle.map { $0.maxX + gap } ?? leading
        accessory = CGRect(x: accessoryX, y: y, width: max(0, navigation.minX - gap - accessoryX), height: size)
        buttonSize = size
        bottom = centerY + size / 2
    }
}
