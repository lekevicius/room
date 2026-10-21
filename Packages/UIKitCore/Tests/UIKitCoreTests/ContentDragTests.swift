import CoreGraphics
import Design
import Testing
@testable import UIKitCore

@Suite("The page's top as a drag region while the sidebar is hidden (spec §E)")
struct ContentDragTests {
    @Test("The top 5% of the card drags the window, once a press there moves 3 pt")
    func contentDrag() {
        let card = CGRect(x: 6, y: 6, width: 1232, height: 806)
        let band = ContentDragGeometry.band(card: card)
        #expect(band == CGRect(x: 6, y: 6, width: 1232, height: 40))
        #expect(!ContentDragGeometry.startsWindowDrag(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 102, y: 21)))
        #expect(ContentDragGeometry.startsWindowDrag(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 103, y: 20)))
    }
}
