// Renders Room's theme images for Chromium's "room" theme directories (B-103, 5.2b) from the
// Room icon's glyph (App/Resources/AppIcon.icon/Assets/Image.png, the user's Icon Composer
// document): the product logos WebUI pages show in their corner (IDR_PRODUCT_LOGO_16/32 through
// chrome://theme/current-channel-logo) and the larger sizes, and the wordmark (the glyph and
// "Room", IDR_PRODUCT_LOGO_NAME_22). Run by hand after the icon changes; the PNGs are committed
// under theme/ and tools/install_theme.sh links them into the checkout.
//   swift Engine/roomcore/room/branding/tools/render_theme.swift <repo root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let theme = root.appending(path: "Engine/roomcore/room/branding/theme")
guard let glyph = NSImage(contentsOf: root.appending(path: "App/Resources/AppIcon.icon/Assets/Image.png")) else {
    fatalError("no glyph")
}

func write(_ size: NSSize, scale: CGFloat, to path: String, draw: (NSRect) -> Void) {
    let pixels = NSSize(width: size.width * scale, height: size.height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    draw(NSRect(origin: .zero, size: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let url = theme.appending(path: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(path, Int(pixels.width), "x", Int(pixels.height))
}

// The glyph fills its square with a small margin, as Chromium's logo does.
func logo(_ points: CGFloat, scale: CGFloat, _ path: String) {
    write(NSSize(width: points, height: points), scale: scale, to: path) { rect in
        glyph.draw(in: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04))
    }
}

// The wordmark: the glyph at the row's height, then "Room" (97 × 22 pt, Chromium's size).
func wordmark(scale: CGFloat, white: Bool, _ path: String) {
    write(NSSize(width: 97, height: 22), scale: scale, to: path) { rect in
        let unit = rect.height / 22
        glyph.draw(in: NSRect(x: 0, y: unit, width: 20 * unit, height: 20 * unit))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17 * unit, weight: .semibold),
            .foregroundColor: white ? NSColor.white : NSColor(srgbRed: 0.235, green: 0.251, blue: 0.263, alpha: 1),
        ]
        NSAttributedString(string: "Room", attributes: attributes).draw(at: NSPoint(x: 27 * unit, y: 1.5 * unit))
    }
}

// chrome/app/theme/room (sizes by pixels, 1×).
for side in [16, 24, 48, 64, 128, 256] { logo(CGFloat(side), scale: 1, "room/product_logo_\(side).png") }
// default_100_percent/room and default_200_percent/room (points, each scale).
for (scale, directory) in [(CGFloat(1), "default_100_percent"), (2, "default_200_percent")] {
    logo(16, scale: scale, "\(directory)/product_logo_16.png")
    logo(32, scale: scale, "\(directory)/product_logo_32.png")
    wordmark(scale: scale, white: false, "\(directory)/product_logo_name_22.png")
    wordmark(scale: scale, white: true, "\(directory)/product_logo_name_22_white.png")
}
