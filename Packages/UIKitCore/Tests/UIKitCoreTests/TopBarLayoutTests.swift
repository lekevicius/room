import CoreGraphics
import Design
import Testing
@testable import UIKitCore

@Suite("The sidebar's top bar (5.13, the user's design, Figma 157:233)")
struct TopBarLayoutTests {
    /// The design's traffic lights: 14 pt buttons at (17, 17), 9 pt apart.
    let lights = TrafficLightGeometry(buttonsRect: CGRect(x: 17, y: 17, width: 60, height: 14))

    @Test("At the design's 304 pt: the toggle at x 92, the extensions from x 132, Back at 224 and Reload ending 8 pt from the edge")
    func design() {
        let bar = TopBarLayout(width: 304, trafficLights: lights)
        #expect(bar.buttonSize == 32)
        #expect(bar.toggle == CGRect(x: 92, y: 8, width: 32, height: 32))
        #expect(bar.navigation == CGRect(x: 224, y: 8, width: 72, height: 32))
        #expect(bar.showsReload)
        #expect(bar.accessory.minX == 132)
        #expect(bar.accessory.maxX == 216)
        #expect(bar.bottom == 40)
    }

    @Test("Forward widens the navigation group (67 pt, the design's segmented control) and narrows the extensions' strip")
    func forward() {
        let back = GlassControlMetrics.groupWidth(2)
        #expect(back == 67)
        let bar = TopBarLayout(width: 304, trafficLights: lights, navigationWidth: (back + 8 + 32, back))
        #expect(bar.navigation.minX == 189)
        #expect(bar.showsReload)
        #expect(bar.accessory.width == 49)
    }

    @Test("No room for the puzzle piece: Reload goes first, then the toggle; the extensions get nothing")
    func narrow() {
        let withForward = (withReload: CGFloat(107), withoutReload: CGFloat(67))
        let noReload = TopBarLayout(width: 250, trafficLights: lights, navigationWidth: withForward)
        #expect(!noReload.showsReload)
        #expect(noReload.toggle != nil)
        #expect(noReload.accessory.width >= GlassControlMetrics.size)
        let minimum = TopBarLayout(width: SidebarMetrics.minWidth, trafficLights: lights, navigationWidth: withForward)
        #expect(!minimum.showsReload)
        #expect(minimum.toggle == nil)
        #expect(minimum.navigation.maxX == SidebarMetrics.minWidth - SidebarMetrics.headerTrailingInset)
        #expect(minimum.navigation.minX >= lights.buttonsRect!.maxX)
        // The address row does not move with the buttons.
        #expect(minimum.bottom == noReload.bottom)
    }
}
