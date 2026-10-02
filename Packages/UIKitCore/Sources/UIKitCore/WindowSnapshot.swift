#if DEBUG
import AppKit
import Darwin

/// Debug-only capture of one of our own windows as the window server
/// composites it (material included). Uses `CGWindowListCreateImage`, which
/// the SDK marks unavailable since macOS 15 but still exports; capturing the
/// calling process's own windows needs no Screen Recording permission.
public enum WindowSnapshot {
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    private static let createImage: CreateImage? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    /// The window's content at backing resolution, without its frame shadow.
    public static func capture(_ window: NSWindow) -> CGImage? {
        guard let createImage, window.windowNumber > 0 else { return nil }
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)     // BoundsIgnoreFraming | BestResolution
        return createImage(.null, includingWindow, UInt32(window.windowNumber), options)?.takeRetainedValue()
    }

    @discardableResult
    public static func writePNG(_ window: NSWindow, to url: URL) throws -> CGImage? {
        guard let image = capture(window) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try data.write(to: url)
        return image
    }
}
#endif
