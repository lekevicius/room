import AppKit
import Model

/// Settings ▸ Appearance ▸ App Icon: the choices rendered to PNG by
/// `scripts/render-app-icons.sh`, bundled in `Resources/Rendered` as
/// `<raw>.png` (Icon Composer's Default rendition) and `<raw>-dark.png` (Dark).
/// `.room` has PNGs too, for the picker; the Dock takes the bundle's own icon for it.
enum AppIconImages {
    static let subdirectory = "Rendered"

    /// The PNG's name without its extension.
    static func resourceName(_ choice: AppIconChoice, dark: Bool) -> String {
        dark ? "\(choice.rawValue)-dark" : choice.rawValue
    }

    static func url(_ choice: AppIconChoice, dark: Bool, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName(choice, dark: dark), withExtension: "png", subdirectory: subdirectory)
    }

    private static var cache: [String: NSImage] = [:]

    /// The rendition, loaded once (the picker shows all of them; the Dock one at a time).
    static func image(_ choice: AppIconChoice, dark: Bool) -> NSImage? {
        let name = resourceName(choice, dark: dark)
        if let image = cache[name] { return image }
        guard let url = url(choice, dark: dark), let image = NSImage(contentsOf: url) else { return nil }
        // 1024 px is 512 pt @2x, the size macOS draws app icons from.
        image.size = NSSize(width: 512, height: 512)
        cache[name] = image
        return image
    }
}
