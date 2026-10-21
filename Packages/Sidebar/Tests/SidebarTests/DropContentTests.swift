import AppKit
import Design
import Omnibox
import Testing
@testable import Sidebar

/// 5.5b: what a drop from another app opens (spec §I.7), what a row's drag
/// gives other apps (B-97), the slide back (B-96), the hover sublabel (§I.4).
@Suite("Drops, drags out and sublabels (5.5b)")
struct DropContentTests {
    private func pasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RoomDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        write(pasteboard)
        return pasteboard
    }

    @Test("Dropped text searches with the profile's engine, not always Google (a bug 5.5b found)")
    func searchEngine() {
        let board = pasteboard { $0.setString("room browser", forType: .string) }
        #expect(URLFixup.dropURLs(from: board, engine: .duckDuckGo) == ["https://duckduckgo.com/?q=room%20browser"])
        board.releaseGlobally()
    }

    @Test("Image data with no URL opens as a PNG file: TIFF is converted; a placeholder while only hovering")
    func image() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let board = pasteboard { $0.setData(tiff, forType: .tiff) }
        let png = try #require(URLFixup.droppedImagePNG(from: board))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(SidebarDrop.urls(from: board, writingImages: false).count == 1)
        let directory = FileManager.default.temporaryDirectory.appending(path: "RoomDropTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = try #require(URLFixup.writeDroppedImage(png, into: directory))
        #expect(written.hasPrefix("file://") && written.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: try #require(URL(string: written)).path))
        // A URL on the pasteboard wins over the image (a page's image dragged with its address).
        board.clearContents()
        board.writeObjects([URL(string: "https://example.com/a.png")! as NSURL])
        board.setData(tiff, forType: .tiff)
        #expect(SidebarDrop.urls(from: board, writingImages: false) == ["https://example.com/a.png"])
        board.releaseGlobally()
    }

    @Test("A URL dragged out carries its title for Finder and the URL as text")
    func urlDrag() {
        let item = URLDrag.pasteboardItem(url: "https://example.com/", title: "Example")
        #expect(item.string(forType: .URL) == "https://example.com/")
        #expect(item.string(forType: .string) == "https://example.com/")
        #expect(item.string(forType: URLDrag.titleType) == "Example")
    }

    @Test("Rows offer other apps their URL only with ⌥ (B-97); past the drag-out distance the image does not slide back (B-96)")
    func dragOut() {
        #expect(DragOutRule.outsideOperations(option: false).isEmpty)
        #expect(DragOutRule.outsideOperations(option: true).contains(.copy))
        let window = NSRect(x: 100, y: 100, width: 1000, height: 700)
        #expect(DragOutRule.slidesBack(at: NSPoint(x: 500, y: 400), windowFrame: window, count: 1))
        #expect(!DragOutRule.slidesBack(at: NSPoint(x: 1200, y: 400), windowFrame: window, count: 1))
        // Several entries never open a window: they slide back.
        #expect(DragOutRule.slidesBack(at: NSPoint(x: 1200, y: 400), windowFrame: window, count: 2))
    }

    @Test("The reset icon's ⌘ sublabel says Separate only where ⌘-click separates: the selected row")
    func sublabel() {
        #expect(HoverSublabel.text(hovered: true, changed: true, onIcon: true, command: false, selected: true, currentTitle: "Live")
            == HoverSublabel.reset)
        #expect(HoverSublabel.text(hovered: true, changed: true, onIcon: true, command: true, selected: true, currentTitle: "Live")
            == HoverSublabel.separate)
        #expect(HoverSublabel.text(hovered: true, changed: true, onIcon: true, command: true, selected: false, currentTitle: "Live")
            == HoverSublabel.reset)
        #expect(HoverSublabel.text(hovered: true, changed: true, onIcon: false, command: false, selected: false, currentTitle: "Live") == "Live")
        #expect(HoverSublabel.text(hovered: true, changed: false, onIcon: true, command: false, selected: true, currentTitle: "Live") == nil)
        #expect(HoverSublabel.text(hovered: false, changed: true, onIcon: false, command: false, selected: true, currentTitle: "Live") == nil)
    }
}
