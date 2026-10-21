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

    /// Whether the capture function is exported by this system.
    public static var isAvailable: Bool { createImage != nil }

    /// The window's content at backing resolution, without its frame shadow.
    public static func capture(_ window: NSWindow) -> CGImage? {
        guard let createImage, window.windowNumber > 0 else { return nil }
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)     // BoundsIgnoreFraming | BestResolution
        return createImage(.null, includingWindow, UInt32(window.windowNumber), options)?.takeRetainedValue()
    }

    /// A window of this process by its window-server number (5.2b: a menu's window while it
    /// tracks, which is not an `NSWindow` the app can name).
    public static func capture(windowNumber: Int) -> CGImage? {
        guard let createImage, windowNumber > 0 else { return nil }
        let includingWindow: UInt32 = 1 << 3          // kCGWindowListOptionIncludingWindow
        let options: UInt32 = (1 << 0) | (1 << 3)     // BoundsIgnoreFraming | BestResolution
        return createImage(.null, includingWindow, UInt32(windowNumber), options)?.takeRetainedValue()
    }

    /// The window numbers of this process's on-screen windows at `layer` (101: menus), front to back.
    public static func ownWindowNumbers(layer: Int) -> [Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let pid = Int(getpid())
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == pid, (info[kCGWindowLayer as String] as? Int) == layer else { return nil }
            return info[kCGWindowNumber as String] as? Int
        }
    }

    private typealias CreateImageFromArray = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?

    private static let createImageFromArray: CreateImageFromArray? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImageFromArray") else { return nil }
        return unsafeBitCast(symbol, to: CreateImageFromArray.self)
    }()

    /// The window with the app's windows over it (child windows, panels, popovers) composited
    /// as the window server draws them, cropped to `window`'s frame, without frame shadows.
    public static func capture(_ window: NSWindow, with others: [NSWindow]) -> CGImage? {
        guard let createImageFromArray, window.windowNumber > 0, let screen = NSScreen.screens.first else { return nil }
        // Front to back, as the window server orders them.
        let ids = ([window] + others).filter { $0.windowNumber > 0 }.sorted { $0.orderedIndex > $1.orderedIndex }
            .map { UnsafeRawPointer(bitPattern: UInt($0.windowNumber)) }
        let array = ids.withUnsafeBufferPointer { buffer in
            CFArrayCreate(nil, UnsafeMutablePointer(mutating: buffer.baseAddress), buffer.count, nil)
        }
        guard let array else { return nil }
        let frame = window.frame
        let bounds = CGRect(x: frame.minX, y: screen.frame.height - frame.maxY, width: frame.width, height: frame.height)
        let options: UInt32 = (1 << 0) | (1 << 3)     // BoundsIgnoreFraming | BestResolution
        return createImageFromArray(bounds, array, options)?.takeRetainedValue()
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
