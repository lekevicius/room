import AppKit

/// Dynamic colors from the package asset catalog (light and dark variants).
public enum Palette {
    /// Card fill before the page reports its root background color.
    public static var cardBackground: NSColor { named("CardBackground") }
    /// Hairline around the card (6–8% label color).
    public static var cardBorder: NSColor { named("CardBorder") }
    /// Shadow color behind the card; opacity comes from `CardMetrics`.
    public static var cardShadow: NSColor { named("CardShadow") }
    /// Selected sidebar row pill (Chapter 2).
    public static var sidebarSelection: NSColor { named("SidebarSelection") }
    /// Hovered sidebar row background (spec §I.4: 6% foreground).
    public static var sidebarHover: NSColor { named("SidebarHover") }
    /// Space tint when a space has no theme colors.
    public static var spaceTintDefault: NSColor { named("SpaceTintDefault") }
    /// Splitter line shown while hovering or dragging the sidebar edge.
    public static var splitterHighlight: NSColor { named("SplitterHighlight") }

    /// Every catalog color, for tests.
    public static let allNames = [
        "CardBackground", "CardBorder", "CardShadow", "SidebarSelection",
        "SidebarHover", "SpaceTintDefault", "SplitterHighlight",
    ]

    static func named(_ name: String) -> NSColor {
        guard let color = NSColor(named: name, bundle: .module) else {
            assertionFailure("missing color asset \(name)")
            return .magenta
        }
        return color
    }
}

public extension NSColor {
    /// This color resolved for `appearance` (dynamic colors have no fixed components otherwise).
    func resolved(for appearance: NSAppearance) -> NSColor {
        var result = self
        appearance.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }

    /// `cgColor` resolved for `appearance`.
    func cgColor(for appearance: NSAppearance) -> CGColor {
        resolved(for: appearance).cgColor
    }
}

public extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark,
                         .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                         .accessibilityHighContrastVibrantLight, .accessibilityHighContrastVibrantDark])
            .map { [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark].contains($0) }
            ?? false
    }
}
