import Foundation

/// A colour as hue, saturation and lightness (HSL, all 0–1; hue in turns).
public struct HSLColor: Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var lightness: Double

    public init(hue: Double, saturation: Double, lightness: Double) {
        self.hue = hue - floor(hue)
        self.saturation = min(max(saturation, 0), 1)
        self.lightness = min(max(lightness, 0), 1)
    }

    /// `#RRGGBB` (case-insensitive, the `#` optional); `nil` for anything else.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    public init(red: Double, green: Double, blue: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else {
            self.init(hue: 0, saturation: 0, lightness: lightness)
            return
        }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue /= 6
        self.init(hue: hue, saturation: saturation, lightness: lightness)
    }

    /// Red, green and blue, 0–1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        guard saturation > 0 else { return (lightness, lightness, lightness) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return (channel(hue + 1 / 3), channel(hue), channel(hue - 1 / 3))
    }

    /// `#RRGGBB`, uppercase.
    public var hex: String {
        let (red, green, blue) = rgb
        // The nudge keeps halves (127.5) from rounding down after hue arithmetic leaves 127.4999….
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255 + 1e-9).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// The same colour turned by `degrees` around the hue circle.
    public func rotated(by degrees: Double) -> HSLColor {
        HSLColor(hue: hue + degrees / 360, saturation: saturation, lightness: lightness)
    }
}

/// A space's theme (spec §B: 1–3 colours, five algorithms) turned into the
/// colours the window tint draws. Pure functions; the window converts the
/// result to `NSColor` (`docs/design-tokens.md`, "Space themes").
///
/// The user's colour wells hold up to three colours; the first is the base.
/// An algorithm fills the wells the user left empty with hues at fixed
/// angles from the base (colour-wheel harmonies, as Zen's gradient
/// generator places its dots): Complementary +180°; Split +150° and +210°;
/// Analogous −30° and +30°; Triadic +120° and +240°. Floating derives
/// nothing: the wells are used as they are. A well the user filled always wins.
public enum ThemePalette {
    /// Most colours a theme has.
    public static let maxColors = 3

    /// Hue offsets (degrees) each algorithm derives from the base colour.
    public static func offsets(_ algorithm: ThemeAlgorithm) -> [Double] {
        switch algorithm {
        case .complementary: [180]
        case .split: [150, 210]
        case .analogous: [-30, 30]
        case .triadic: [120, 240]
        case .floating: []
        }
    }

    /// The theme's colours (`#RRGGBB`): the base, then each derived slot
    /// filled by the user's well at that position or else by the algorithm,
    /// then any further user wells, at most `maxColors`. Unparseable wells
    /// are skipped; no colours gives none (the neutral window).
    public static func colors(_ wells: [String], algorithm: ThemeAlgorithm) -> [String] {
        let parsed = wells.compactMap(HSLColor.init(hex:))
        guard let base = parsed.first else { return [] }
        var result = [base.hex]
        let derived = offsets(algorithm)
        for (slot, offset) in derived.enumerated() {
            let user = parsed.indices.contains(slot + 1) ? parsed[slot + 1] : nil
            result.append((user ?? base.rotated(by: offset)).hex)
        }
        for extra in parsed.dropFirst(derived.count + 1) { result.append(extra.hex) }
        return Array(result.prefix(maxColors))
    }

    /// The colours for a dark appearance: no lighter than `darkMaxLightness`,
    /// so a pastel theme does not wash out the dark material (chosen).
    public static func darkVariant(_ colors: [String]) -> [String] {
        colors.compactMap(HSLColor.init(hex:)).map { color in
            var dark = color
            dark.lightness = min(color.lightness, darkMaxLightness)
            return dark.hex
        }
    }

    public static let darkMaxLightness = 0.45

    /// The tint's alpha for a space's `themeOpacity` (0–1), mapped linearly
    /// into `range` (the window's tint range, `Materials.tintOpacityRange`).
    public static func tintAlpha(opacity: Double, range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(max(opacity, 0), 1)
    }
}
