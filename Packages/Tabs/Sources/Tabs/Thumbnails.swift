import AppKit
import Design
import Engine

/// The ⌃Tab switcher's thumbnails (B-119, 5.12; the user on build 26, as Dia's). A page off screen
/// draws no frames, so each picture is taken as its tab is left (and the shown one's as the switcher
/// opens): the viewport's top, cropped to the card's shape and scaled to its size, kept in memory
/// for the `TabSwitcherMetrics.thumbnailsKept` most recently left tabs.
extension TabController {
    public func thumbnail(for entry: UUID) -> NSImage? { thumbnails[entry] }

    /// Pictures `entry`'s page if it is alive (a capture takes 15–16 ms of the GPU's time, 5.6b).
    public func captureThumbnail(_ entry: UUID) {
        guard let page = pages[entry], page.contents.state == .alive else { return }
        let contents = readers[entry]?.contents ?? page.contents
        Task { @MainActor [weak self] in
            guard let image = try? await contents.captureViewport(), let thumb = Thumbnail.make(from: image) else { return }
            guard let self, self.pages[entry] != nil else { return }
            self.thumbnails[entry] = thumb
            self.thumbnailOrder.removeAll { $0 == entry }
            self.thumbnailOrder.append(entry)
            while self.thumbnailOrder.count > TabSwitcherMetrics.thumbnailsKept {
                self.thumbnails[self.thumbnailOrder.removeFirst()] = nil
            }
            self.onThumbnail?(entry)
        }
    }

    /// The page closed or left its entry: its picture goes too.
    func dropThumbnail(_ entry: UUID) {
        thumbnails[entry] = nil
        thumbnailOrder.removeAll { $0 == entry }
    }
}

enum Thumbnail {
    /// The top of `image`, cropped to the switcher card's aspect and scaled to twice its width (Retina).
    static func make(from image: NSImage) -> NSImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let aspect = TabSwitcherMetrics.thumbnailHeight / TabSwitcherMetrics.cardWidth
        let width = TabSwitcherMetrics.cardWidth * 2, height = (width * aspect).rounded()
        let sourceHeight = min(image.size.height, image.size.width * aspect)
        // NSImage's origin is bottom-left: the top band starts at height - sourceHeight.
        let source = NSRect(x: 0, y: image.size.height - sourceHeight, width: image.size.width, height: sourceHeight)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: source, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let thumb = NSImage(size: NSSize(width: width / 2, height: height / 2))
        thumb.addRepresentation(rep)
        return thumb
    }
}
