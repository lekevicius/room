import CoreGraphics
import Engine
import Foundation

/// ⇧⌘2's arithmetic (4.7a): the dragged rectangle, its pixels in the
/// engine's capture at the screen's backing scale, the file name.
nonisolated public enum ScreenshotRules {
    /// The rectangle a drag from `start` to `end` selects, clipped to
    /// `bounds` (the page's view, top-left origin); `nil` for a click or a
    /// drag thinner than `minimum` on either side.
    public static func selection(from start: CGPoint, to end: CGPoint, within bounds: CGRect, minimum: CGFloat) -> CGRect? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            .intersection(bounds)
        guard !rect.isNull, rect.width >= minimum, rect.height >= minimum else { return nil }
        return rect
    }

    /// `rect` (points in a view of `viewSize`, top-left origin) as whole
    /// pixels of a capture `pixelSize` big: scaled by the capture's own
    /// scale (the backing scale the compositor drew at), rounded outward,
    /// clipped to the image. `nil` when nothing is left.
    public static func pixelRect(for rect: CGRect, viewSize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scaleX = pixelSize.width / viewSize.width
        let scaleY = pixelSize.height / viewSize.height
        let scaled = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY, width: rect.width * scaleX, height: rect.height * scaleY)
        let whole = CGRect(x: floor(scaled.minX), y: floor(scaled.minY),
                           width: ceil(scaled.maxX) - floor(scaled.minX), height: ceil(scaled.maxY) - floor(scaled.minY))
        let clipped = whole.intersection(CGRect(origin: .zero, size: pixelSize))
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        return clipped
    }

    /// "Screenshot 2026-10-07 at 01.23.45.png" (the system's own pattern).
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: date)).png"
    }

    /// `name` in `folder`, or "name (2).png", "name (3).png" … when taken.
    public static func uniqueURL(for name: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let first = folder.appending(path: name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)")
            if !exists(candidate) { return candidate }
            index += 1
        }
    }

    /// The files of `<state>/Screenshots/` to delete at launch (B-92): every
    /// one modified more than `maximumAge` before `now`, and of the rest
    /// every one beyond the newest `keep`. The folder holds only Open as
    /// Tab's images, which a `file://` tab needs while it is open.
    public static func pruned(_ files: [(url: URL, modified: Date)], now: Date, maximumAge: TimeInterval, keep: Int) -> [URL] {
        let newestFirst = files.sorted { $0.modified > $1.modified }
        var kept = 0
        var gone: [URL] = []
        for file in newestFirst {
            if now.timeIntervalSince(file.modified) > maximumAge || kept >= keep {
                gone.append(file.url)
            } else {
                kept += 1
            }
        }
        return gone
    }

    /// The CSS clip a full-page capture asks for: the page's content size,
    /// its height cut so the image stays within `maximumPixels` at `scale`.
    public static func fullPageClip(contentSize: CGSize, scale: CGFloat, maximumPixels: CGFloat) -> CGSize {
        let limit = scale > 0 ? floor(maximumPixels / scale) : maximumPixels
        return CGSize(width: min(contentSize.width, limit), height: min(contentSize.height, limit))
    }
}

/// File ▸ Save Page…'s defaults (4.7a).
nonisolated public enum SavePageRules {
    /// The panel's format popup, in order (the first is the default, as in Chrome).
    public static let formats: [SavePageFormat] = [.completeHTML, .html, .mhtml]

    public static func title(_ format: SavePageFormat) -> String {
        switch format {
        case .completeHTML: "Web Page, Complete"
        case .html: "Web Page, HTML Only"
        case .mhtml: "Web Archive (MHTML)"
        }
    }

    /// The page's title as a file name with the format's extension: path
    /// separators and colons become "-", whitespace runs one space, at most
    /// 120 characters; the host (or "Page") when the title is empty.
    public static func fileName(title: String?, url: URL?, format: SavePageFormat) -> String {
        var base = (title ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        base = base.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if base.isEmpty { base = url?.host() ?? "Page" }
        if base.count > 120 { base = String(base.prefix(120)).trimmingCharacters(in: .whitespaces) }
        return "\(base).\(format.fileExtension)"
    }

    /// `name` with the format's extension in place of an `.html`/`.htm`/`.mhtml`/`.mht` one.
    public static func renamed(_ name: String, to format: SavePageFormat) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let base = ["html", "htm", "mhtml", "mht"].contains(ext) ? (name as NSString).deletingPathExtension : name
        return "\(base).\(format.fileExtension)"
    }
}
