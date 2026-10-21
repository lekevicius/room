import AppKit

/// Dynamic colors from the package asset catalog (light and dark variants).
public enum Palette {
    /// Card fill before the page reports its root background color.
    public static var cardBackground: NSColor { named("CardBackground") }
    /// Hairline around the card (6–8% label color); Increase Contrast: `hairlineHighContrast` (5.3b).
    public static var cardBorder: NSColor {
        DisplayOptions.current.increaseContrast ? hairlineHighContrast : named("CardBorder")
    }
    /// The chrome's other hairlines (`HairlineView`, split panes' segment lines, the status pill's
    /// border, the DevTools and Peek header lines): AppKit's separator, or `hairlineHighContrast`
    /// under Increase Contrast (5.3b). Resolved when drawn, so a live toggle reaches it.
    public static let hairline = NSColor(name: "RoomHairline") { appearance in
        DisplayOptions.current.increaseContrast ? highContrastHairline(dark: appearance.isDark) : .separatorColor
    }
    /// Increase Contrast's hairline (5.3b): the label colour at `hairlineHighContrastAlpha`.
    public static let hairlineHighContrast = NSColor(name: "RoomHairlineHighContrast") { appearance in
        highContrastHairline(dark: appearance.isDark)
    }
    /// The alphas of `hairlineHighContrast` (chosen: the separator's 10% and the card's 7–8% read as
    /// borders at 45% light / 50% dark, as AppKit's own controls gain borders under Increase Contrast).
    nonisolated public static let hairlineHighContrastAlpha: (light: CGFloat, dark: CGFloat) = (0.45, 0.5)

    private nonisolated static func highContrastHairline(dark: Bool) -> NSColor {
        dark ? NSColor(white: 1, alpha: hairlineHighContrastAlpha.dark) : NSColor(white: 0, alpha: hairlineHighContrastAlpha.light)
    }
    /// Shadow color behind the card; opacity comes from `CardMetrics`.
    public static var cardShadow: NSColor { named("CardShadow") }
    /// Selected sidebar row pill (Chapter 2).
    public static var sidebarSelection: NSColor { named("SidebarSelection") }
    /// Hovered sidebar row background (spec §I.4: 6% foreground).
    public static var sidebarHover: NSColor { named("SidebarHover") }
    /// The address field under the pointer: its resting fill (`sidebarHover`) deepened to 10% (B-111, 5.1b; chosen).
    public static var addressFieldHover: NSColor { named("AddressFieldHover") }
    /// Space tint when a space has no theme colors.
    public static var spaceTintDefault: NSColor { named("SpaceTintDefault") }
    /// Secondary text over the sidebar's tinted material (sublabels, the folder glyph, the unloaded
    /// split titles, the footer's space name): the label colour at `sidebarSecondaryAlpha` (5.2b's
    /// contrast rule: AppKit's secondary label, black 50% / white 55%, measured 3.8:1 light and 4.1:1
    /// dark over the untinted material and 2.95:1 under a dark tint; this holds 4.5:1 over every theme
    /// sample at the highest tint opacity, `docs/design-tokens.md` "Theme contrast").
    /// Under Increase Contrast it takes `sidebarSecondaryHighContrastAlpha` (5.3b).
    public static let sidebarSecondaryLabel = NSColor(name: "RoomSidebarSecondaryLabel") { appearance in
        let alpha = sidebarSecondaryAlpha(for: DisplayOptions.current)
        return appearance.isDark ? NSColor(white: 1, alpha: alpha.dark) : NSColor(white: 0, alpha: alpha.light)
    }
    /// The alphas of `sidebarSecondaryLabel` (the primary label is AppKit's, 85%): the dark tint
    /// lightens the material more than the light tint darkens it, so dark needs more.
    nonisolated public static let sidebarSecondaryAlpha: (light: CGFloat, dark: CGFloat) = (0.64, 0.82)
    /// Increase Contrast's secondary text (5.3b): 7:1 (WCAG AAA) over the 5.2b samples' worst
    /// backgrounds, still below the primary label so the two read apart.
    nonisolated public static let sidebarSecondaryHighContrastAlpha: (light: CGFloat, dark: CGFloat) = (0.80, 0.92)

    /// The secondary text's alphas under `options`.
    public nonisolated static func sidebarSecondaryAlpha(for options: DisplayOptions) -> (light: CGFloat, dark: CGFloat) {
        options.increaseContrast ? sidebarSecondaryHighContrastAlpha : sidebarSecondaryAlpha
    }

    /// An unloaded row's title (spec §A.1): the label colour at `SidebarMetrics.unloadedTitleAlpha`, resolved
    /// when drawn (5.3b: `labelColor.withAlphaComponent` was fixed to the appearance of the row's last
    /// configure, so after a light/dark switch unloaded titles kept the other appearance's colour, read
    /// back as dark text on the dark sidebar); under Increase Contrast the secondary text's alphas.
    public static let sidebarUnloadedLabel = NSColor(name: "RoomSidebarUnloadedLabel") { appearance in
        let options = DisplayOptions.current
        let alpha = options.increaseContrast ? sidebarSecondaryHighContrastAlpha : (light: unloadedTitleAlpha, dark: unloadedTitleAlpha)
        return appearance.isDark ? NSColor(white: 1, alpha: alpha.dark) : NSColor(white: 0, alpha: alpha.light)
    }
    nonisolated static let unloadedTitleAlpha: CGFloat = 0.7

    /// Differentiate Without Colour (5.3b): the ring around the changed dot, so the dot's shape
    /// reads against a favicon of any colour (`ChangedMark`).
    public static var changedMarkOutline: NSColor { .windowBackgroundColor }

    /// Accent marks: the changed-entry dot (spec §I.8), the drag insertion line (§A.9).
    public static var accent: NSColor { .controlAccentColor }
    /// Rows in the ⌘/⇧-click multi-selection and the drop-onto target (§A.9, §A.6).
    public static var sidebarMultiSelection: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.18) }
    /// Behind a dragged row's image in dark appearance (light: white) (chosen, 2.2b; a token since 5.2a).
    public static let dragImageFillDark = NSColor(white: 0.2, alpha: 1)
    /// A new theme colour well when the algorithm offers no hue (chosen, 2.5: a calm blue).
    public static let themeWellDefaultHex = "#5B8DEF"

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
        "SidebarHover", "SpaceTintDefault", "AddressFieldHover",
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
