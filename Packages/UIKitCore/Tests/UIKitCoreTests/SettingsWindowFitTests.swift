import CoreGraphics
import Testing
@testable import UIKitCore

@Suite("Settings window fit (B-120: the window never grows past the display)")
struct SettingsWindowFitTests {
    @Test("On the smallest supported display the window fits the visible frame; on a large one the preferred height")
    func contentHeight() {
        let chrome: CGFloat = 78
        let small = SettingsWindowFit.smallestVisibleFrame
        let height = SettingsWindowFit.contentHeight(visible: small, chrome: chrome)
        #expect(height + chrome <= small.height)
        #expect(height < SettingsWindowFit.preferredContentHeight)
        let large = CGRect(x: 0, y: 0, width: 1920, height: 1080 - 33)
        #expect(SettingsWindowFit.contentHeight(visible: large, chrome: chrome) == SettingsWindowFit.preferredContentHeight)
    }

    @Test("A window below or beside the visible frame moves inside it, top first")
    func placed() {
        let visible = SettingsWindowFit.smallestVisibleFrame
        let frame = CGRect(x: 900, y: 0, width: 560, height: 500)
        let placed = SettingsWindowFit.placed(frame, in: visible)
        #expect(visible.contains(placed))
        #expect(placed.size == frame.size)
        let tall = CGRect(x: 0, y: 0, width: 560, height: 900)
        #expect(SettingsWindowFit.placed(tall, in: visible).maxY == visible.maxY)
    }
}
