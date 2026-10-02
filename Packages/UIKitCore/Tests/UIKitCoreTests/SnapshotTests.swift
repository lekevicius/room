import AppKit
import Testing
import Design
import Engine
import FakeEngine
@testable import UIKitCore

/// Window snapshots in every Phase 1.3 state. Each capture is written as a PNG
/// (to `$ROOM_SNAPSHOT_DIR`, else a temporary directory) for comparison by eye
/// against `research/screenshots/dia-window.jpg`, and checked for the things
/// that must hold in every state: the card is clipped, filled, shadowed and
/// inset; the title clears the traffic lights. Test-process windows never
/// become main, so "active" is forced with `activityOverride` (the material
/// and sidebar follow it; the traffic lights stay grey).
@Suite("Window snapshots", .serialized, .enabled("window capture unavailable") { await SnapshotSupport.canCapture })
struct WindowSnapshotTests {
    nonisolated struct State: CustomTestStringConvertible, Sendable {
        var dark: Bool
        var active: Bool
        var sidebarOpen: Bool
        var fakePage = false

        var name: String {
            [dark ? "dark" : "light", active ? "active" : "inactive", sidebarOpen ? "open" : "closed"]
                .joined(separator: "-") + (fakePage ? "-fake-engine-page" : "")
        }
        var testDescription: String { name }
    }

    nonisolated static let states: [State] = [true, false].flatMap { dark in
        [true, false].flatMap { active in
            [true, false].map { open in State(dark: dark, active: active, sidebarOpen: open) }
        }
    } + [State(dark: false, active: true, sidebarOpen: true, fakePage: true),
         State(dark: true, active: true, sidebarOpen: true, fakePage: true)]

    @Test("Window state", arguments: states)
    func snapshot(_ state: State) async throws {
        let size = NSSize(width: 1000, height: 640)
        let controller = RoomWindowController(contentSize: size)
        defer { controller.close() }
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: state.dark ? .darkAqua : .aqua)
        controller.spaceTitle = "Personal"
        controller.isSidebarOpen = state.sidebarOpen
        controller.activityOverride = state.active

        var page: (any WebContents)?
        if state.fakePage {
            let engine = FakeApplication()
            try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
            let contents = try engine.profile(named: "Default").createWebContents(WebContentsConfiguration())
            contents.load(URL(string: "https://example.com/")!, transition: .typed, fromAddressBar: true)
            controller.cardView.contentView = contents.nativeView
            if let background = contents.rootBackgroundColor { controller.cardView.backgroundColor = background }
            page = contents
        }

        window.orderFrontRegardless()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(400))

        let url = SnapshotSupport.directory.appending(path: "phase-1.3-test-\(state.name).png")
        let image = try #require(try WindowSnapshot.writePNG(window, to: url), "no capture")
        let pixels = try #require(Pixels(image, pointSize: size))
        #expect(pixels.scale >= 1)

        let card = controller.rootView.currentLayout.card
        let interior = pixels.luma(atX: card.midX, y: card.midY)
        // Fill: white card (or the fake page's text background) in light, near-black in dark.
        #expect(state.dark ? interior < 60 : interior > 245, "card interior \(interior)")
        // Clipping: the outermost corner point is not card fill.
        let corner = pixels.luma(atX: card.maxX - 0.75, y: card.maxY - 0.75)
        #expect(abs(corner - interior) > 8, "corner \(corner) vs interior \(interior)")
        // Shadow under the bottom edge: darker right below the card than further out.
        if !state.dark {
            let below = pixels.luma(atX: card.midX, y: card.maxY + 1)
            let further = pixels.luma(atX: card.midX, y: card.maxY + CardMetrics.inset - 1)
            #expect(below < further, "shadow \(below) vs \(further)")
        }
        // Inset: material, not card, just outside the trailing edge. The flat
        // dark inactive material depends on what is behind the window (16
        // levels from the card on a desktop, 5 on CI's headless runner), so
        // there the card's edge is checked through its hairline instead.
        let outside = pixels.luma(atX: card.maxX + CardMetrics.inset / 2, y: card.midY)
        if state.dark && !state.active {
            let edge = pixels.luma(atX: card.maxX - 0.5, y: card.midY)
            #expect(abs(edge - interior) > 8, "hairline \(edge) vs interior \(interior)")
        } else {
            #expect(abs(outside - interior) > 8, "outside \(outside) vs interior \(interior)")
        }

        if state.sidebarOpen {
            let lights = try #require(controller.trafficLights.geometry.buttonsRect)
            let title = controller.sidebarView.titleFrame
            #expect(title.minX > lights.maxX)
            // The title's glyphs are drawn: contrast inside its frame.
            let range = pixels.lumaRange(in: title)
            #expect(range > 80, "title contrast \(range)")
        }
        withExtendedLifetime(page) {}
    }
}

enum SnapshotSupport {
    static let directory: URL = {
        let path = ProcessInfo.processInfo.environment["ROOM_SNAPSHOT_DIR"]
        let url = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appending(path: "room-snapshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @MainActor static var canCapture: Bool { WindowSnapshot.isAvailable }
}

/// RGBA8 copy of a capture, addressed in points from the top-left corner.
struct Pixels {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let data: [UInt8]

    init?(_ image: CGImage, pointSize: NSSize) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        scale = CGFloat(width) / pointSize.width
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        data = buffer
    }

    /// Perceived brightness 0–255 at a point (top-left origin).
    func luma(atX x: CGFloat, y: CGFloat) -> Double {
        let px = min(max(Int(x * scale), 0), width - 1)
        let py = min(max(Int(y * scale), 0), height - 1)
        let i = (py * width + px) * 4
        return 0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])
    }

    func lumaRange(in rect: CGRect) -> Double {
        var low = 255.0, high = 0.0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let value = luma(atX: x, y: y)
                low = min(low, value)
                high = max(high, value)
                x += 0.5
            }
            y += 0.5
        }
        return high - low
    }
}
