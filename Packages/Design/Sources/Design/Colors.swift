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

    /// Accent marks: the changed-entry dot (spec §I.8), the drag insertion line (§A.9).
    public static var accent: NSColor { .controlAccentColor }
    /// Rows in the ⌘/⇧-click multi-selection and the drop-onto target (§A.9, §A.6).
    public static var sidebarMultiSelection: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }

    // MARK: Incognito (4.8b)

    /// The incognito window's appearance whatever the system's (Chrome's
    /// incognito windows are always dark): the dark window material.
    public static let incognitoAppearance: NSAppearance.Name = .darkAqua
    /// The incognito window's tint over that material (its space's theme
    /// colour; `Materials.tintOpacityRange` applies).
    public static let incognitoTintHex = "#2A2A33"
    /// The "Incognito" label in the incognito window's sidebar header.
    public static var incognitoLabel: NSColor { .secondaryLabelColor }

    /// Letter-tile backgrounds for pages without a favicon (spec §I.2), picked
    /// by a stable hash of the domain (`letterTileColor(for:)`).
    public static let letterTileColors: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemRed, .systemOrange,
        .systemGreen, .systemTeal, .systemIndigo, .systemBrown, .systemMint,
    ]

    /// The same colour for the same domain in every launch (FNV-1a; Swift's
    /// `Hasher` is seeded per process).
    public static func letterTileColor(for domain: String) -> NSColor {
        var hash: UInt32 = 2_166_136_261
        for byte in domain.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return letterTileColors[Int(hash % UInt32(letterTileColors.count))]
    }

    /// Every catalog color, for tests.
    public static let allNames = [
        "CardBackground", "CardBorder", "CardShadow", "SidebarSelection",
        "SidebarHover", "SpaceTintDefault",
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
