import AppKit
import Design
import Testing
@testable import Sidebar

/// The drag out of the window (spec §A.9, 4.8a) and the new window's frame.
@Suite("Drag out to a new window")
struct DragOutTests {
    let window = NSRect(x: 100, y: 100, width: 1000, height: 700)

    @Test("Only a drop more than 40 pt outside the window's frame opens a window")
    func threshold() {
        #expect(WindowMetrics.dragOutDistance == 40)
        // Inside, on the edge band and exactly at 40 pt: no window.
        #expect(!DragOutRule.opensWindow(at: NSPoint(x: 500, y: 400), windowFrame: window))
        #expect(!DragOutRule.opensWindow(at: NSPoint(x: 1120, y: 400), windowFrame: window))
        #expect(!DragOutRule.opensWindow(at: NSPoint(x: 60, y: 400), windowFrame: window))
        #expect(!DragOutRule.opensWindow(at: NSPoint(x: 500, y: 839), windowFrame: window))
        // Past 40 pt on any side, or a corner past both.
        #expect(DragOutRule.opensWindow(at: NSPoint(x: 1141, y: 400), windowFrame: window))
        #expect(DragOutRule.opensWindow(at: NSPoint(x: 59, y: 400), windowFrame: window))
        #expect(DragOutRule.opensWindow(at: NSPoint(x: 500, y: 841), windowFrame: window))
        #expect(DragOutRule.opensWindow(at: NSPoint(x: 500, y: 59), windowFrame: window))
    }

    @Test("The new window's top-left is the drop point, kept on the screen")
    func dropFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = NSSize(width: 1000, height: 700)
        #expect(DragOutRule.frame(droppedAt: NSPoint(x: 300, y: 900), size: size, screen: screen)
                == NSRect(x: 300, y: 200, width: 1000, height: 700))
        // Near the right and bottom edges it slides back on screen.
        #expect(DragOutRule.frame(droppedAt: NSPoint(x: 1800, y: 100), size: size, screen: screen)
                == NSRect(x: 920, y: 0, width: 1000, height: 700))
    }

    @Test("⌘N cascades right and down from the key window by the token")
    func cascade() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let key = NSRect(x: 100, y: 200, width: 1000, height: 700)
        let next = DragOutRule.cascaded(from: key, screen: screen)
        #expect(next == NSRect(x: 100 + WindowMetrics.cascadeOffset, y: 200 - WindowMetrics.cascadeOffset, width: 1000, height: 700))
    }
}
