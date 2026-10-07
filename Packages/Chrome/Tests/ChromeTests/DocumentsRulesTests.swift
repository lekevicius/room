import Chrome
import CoreGraphics
import Design
import Engine
import Foundation
import Testing

/// ⇧⌘2's arithmetic and Save Page's defaults (4.7a).
@Suite("Screenshots and Save Page")
struct DocumentsRulesTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func aDragInAnyDirectionSelectsItsRectangleClippedToTheView() {
        #expect(ScreenshotRules.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 50), within: bounds, minimum: 4)
            == CGRect(x: 100, y: 50, width: 200, height: 150))
        #expect(ScreenshotRules.selection(from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1200, y: 900), within: bounds, minimum: 4)
            == CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    @Test func aClickOrAThinDragSelectsNothing() {
        #expect(ScreenshotRules.selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 300), within: bounds, minimum: 4) == nil)
        #expect(ScreenshotRules.selection(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 10), within: bounds, minimum: 4) == nil)
    }

    @Test func theSelectionIsCutFromTheCaptureAtItsBackingScale() {
        // A 2× capture of a 1000 × 800 pt view: 2000 × 1600 pixels.
        let pixels = ScreenshotRules.pixelRect(for: CGRect(x: 100, y: 50, width: 200, height: 150),
                                               viewSize: CGSize(width: 1000, height: 800), pixelSize: CGSize(width: 2000, height: 1600))
        #expect(pixels == CGRect(x: 200, y: 100, width: 400, height: 300))
        // Fractional points round outward to whole pixels.
        let fractional = ScreenshotRules.pixelRect(for: CGRect(x: 10.3, y: 10.3, width: 20.2, height: 20.2),
                                                   viewSize: CGSize(width: 100, height: 100), pixelSize: CGSize(width: 200, height: 200))
        #expect(fractional == CGRect(x: 20, y: 20, width: 41, height: 41))
        // 1× and clipped at the image's edge.
        let edge = ScreenshotRules.pixelRect(for: CGRect(x: 950, y: 750, width: 100, height: 100),
                                             viewSize: CGSize(width: 1000, height: 800), pixelSize: CGSize(width: 1000, height: 800))
        #expect(edge == CGRect(x: 950, y: 750, width: 50, height: 50))
        #expect(ScreenshotRules.pixelRect(for: CGRect(x: 1200, y: 0, width: 10, height: 10),
                                          viewSize: CGSize(width: 1000, height: 800), pixelSize: CGSize(width: 1000, height: 800)) == nil)
    }

    @Test func screenshotFileNamesFollowTheSystemsPatternAndNeverOverwrite() {
        let date = Date(timeIntervalSince1970: 1_791_336_225)  // 2026-10-07 01:23:45 UTC
        let name = ScreenshotRules.fileName(at: date, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Screenshot 2026-10-07 at 01.23.45.png")
        let folder = URL(fileURLWithPath: "/tmp/Downloads", isDirectory: true)
        let taken: Set<String> = [name, "Screenshot 2026-10-07 at 01.23.45 (2).png"]
        let url = ScreenshotRules.uniqueURL(for: name, in: folder) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Screenshot 2026-10-07 at 01.23.45 (3).png")
    }

    @Test func aFullPageStaysWithinTheCaptureLimit() {
        #expect(ScreenshotRules.fullPageClip(contentSize: CGSize(width: 1034, height: 4000), scale: 2, maximumPixels: 16_384)
            == CGSize(width: 1034, height: 4000))
        #expect(ScreenshotRules.fullPageClip(contentSize: CGSize(width: 1034, height: 50_000), scale: 2, maximumPixels: 16_384)
            == CGSize(width: 1034, height: 8192))
    }

    /// B-92: Open as Tab's files are pruned at launch: older than 7 days or beyond the newest 50.
    @Test func screenshotTabFilesArePrunedByAgeAndCount() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let folder = URL(filePath: "/tmp/Screenshots", directoryHint: .isDirectory)
        func file(_ index: Int, hoursAgo: Double) -> (url: URL, modified: Date) {
            (folder.appending(path: "s\(index).png"), now.addingTimeInterval(-hoursAgo * 3600))
        }
        // 60 files an hour apart, the newest first: the 10 beyond the newest 50 go.
        let sixty = (0..<60).map { file($0, hoursAgo: Double($0)) }
        let gone = ScreenshotRules.pruned(sixty.shuffled(), now: now, maximumAge: Retention.screenshotsAge, keep: Retention.screenshotsKept)
        #expect(Set(gone) == Set((50..<60).map { folder.appending(path: "s\($0).png") }))
        // Older than 7 days goes even under the count; exactly 7 days stays.
        let few = [file(0, hoursAgo: 1), file(1, hoursAgo: 7 * 24), file(2, hoursAgo: 7 * 24 + 1)]
        #expect(ScreenshotRules.pruned(few, now: now, maximumAge: Retention.screenshotsAge, keep: Retention.screenshotsKept)
            == [folder.appending(path: "s2.png")])
        // An old file never counts toward the 50 kept.
        let mixed = [file(0, hoursAgo: 400)] + (1...50).map { file($0, hoursAgo: Double($0)) }
        #expect(ScreenshotRules.pruned(mixed, now: now, maximumAge: Retention.screenshotsAge, keep: Retention.screenshotsKept)
            == [folder.appending(path: "s0.png")])
        #expect(ScreenshotRules.pruned([], now: now, maximumAge: Retention.screenshotsAge, keep: Retention.screenshotsKept).isEmpty)
    }

    @Test func savePageNamesComeFromTheTitle() {
        let url = URL(string: "https://example.com/a")
        #expect(SavePageRules.fileName(title: "Room: a/b  test ", url: url, format: .completeHTML) == "Room- a-b test.html")
        #expect(SavePageRules.fileName(title: "  ", url: url, format: .mhtml) == "example.com.mhtml")
        #expect(SavePageRules.fileName(title: nil, url: nil, format: .html) == "Page.html")
        #expect(SavePageRules.fileName(title: String(repeating: "x", count: 300), url: url, format: .html).count == 125)
        #expect(SavePageRules.renamed("Room.html", to: .mhtml) == "Room.mhtml")
        #expect(SavePageRules.renamed("Room.mhtml", to: .completeHTML) == "Room.html")
        #expect(SavePageRules.renamed("Room v1.2", to: .html) == "Room v1.2.html")
        #expect(SavePageRules.formats.first == .completeHTML)
    }
}
