import CoreGraphics
import Design
import Testing
@testable import UIKitCore

@Suite("The sidebar's top bar (the Room Browser design, 2026-10-07)")
struct TopBarLayoutTests {
    /// The design's traffic lights: 14 pt buttons at (17, 17), 9 pt apart.
    let lights = TrafficLightGeometry(buttonsRect: CGRect(x: 17, y: 17, width: 60, height: 14))

    @Test("At the design's 304 pt: the toggle at x 92, Back/Forward/Reload ending 8 pt from the edge, 32 pt buttons centred on the lights")
    func design() {
        let bar = TopBarLayout(width: 304, trafficLights: lights)
        #expect(bar.buttonSize == 32)
        #expect(bar.toggle == CGRect(x: 92, y: 8, width: 32, height: 32))
        #expect(bar.navigation == CGRect(x: 200, y: 8, width: 96, height: 32))
        // The extensions fill the gap, 4 pt from the toggle and packed against Back (B-125): two buttons fit.
        #expect(bar.accessory.minX == 128)
        #expect(bar.accessory.maxX == 200)
        #expect(bar.bottom == 40)
    }

    @Test("B-125: at the default width, macOS 27's traffic lights (ending at x 79) leave room for two pinned extensions")
    func twoExtensionsAtTheDefaultWidth() {
        let macOS27 = TrafficLightGeometry(buttonsRect: CGRect(x: 19, y: 17, width: 60, height: 14))
        let bar = TopBarLayout(width: SidebarMetrics.defaultWidth, trafficLights: macOS27)
        #expect(bar.buttonSize == ControlMetrics.size)
        #expect(Int(bar.accessory.width / bar.buttonSize) == 2)
    }

    @Test("A narrow sidebar shrinks the buttons, then drops the toggle; the extensions get nothing")
    func narrow() {
        let shrunk = TopBarLayout(width: 210, trafficLights: lights)
        #expect(shrunk.toggle != nil)
        #expect(shrunk.buttonSize < SidebarMetrics.topBarButtonSize)
        #expect(shrunk.buttonSize >= SidebarMetrics.topBarButtonMinSize)
        let minimum = TopBarLayout(width: SidebarMetrics.minWidth, trafficLights: lights)
        #expect(minimum.toggle == nil)
        #expect(minimum.navigation.maxX == SidebarMetrics.minWidth - SidebarMetrics.headerTrailingInset)
        #expect(minimum.navigation.minX >= lights.buttonsRect!.maxX)
        #expect(minimum.accessory.width == 0)
        // The address row does not move with the buttons.
        #expect(minimum.bottom == shrunk.bottom)
    }
}
