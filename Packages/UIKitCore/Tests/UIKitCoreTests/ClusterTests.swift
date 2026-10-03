import CoreGraphics
import Design
import Testing
@testable import UIKitCore

@Suite("Floating traffic-light cluster and drag regions (spec §E)")
struct ClusterTests {
    /// AppKit's buttons with the empty unified toolbar (Phase 1.3): 60 × 14 at (19, 19).
    let buttons = CGRect(x: 19, y: 19, width: 60, height: 14)

    @Test("The pill is 38 pt tall, centred on the buttons, padded beside them")
    func pill() {
        let pill = ClusterGeometry.pill(around: buttons)
        #expect(pill.height == ClusterMetrics.height)
        #expect(pill.midY == buttons.midY)
        #expect(pill.minX == buttons.minX - ClusterMetrics.horizontalPadding)
        #expect(pill.maxX == buttons.maxX + ClusterMetrics.horizontalPadding)
    }

    @Test("It fades 2 s after the pointer was last near it and shows again when the pointer comes near")
    func fade() {
        var fade = ClusterFade()
        fade.reset(now: 100)
        #expect(fade.isVisible(now: 101.9))
        fade.pointerMoved(near: false, now: 101)
        #expect(!fade.isVisible(now: 100 + Timing.clusterFade))
        #expect(fade.deadline == 100 + Timing.clusterFade)
        fade.pointerMoved(near: true, now: 110)
        #expect(fade.isVisible(now: 111))
        #expect(!fade.isVisible(now: 112))
        let pill = ClusterGeometry.pill(around: buttons)
        #expect(ClusterGeometry.isNear(CGPoint(x: pill.maxX + ClusterMetrics.nearDistance - 1, y: pill.midY), pill: pill))
        #expect(!ClusterGeometry.isNear(CGPoint(x: 400, y: 300), pill: pill))
    }

    @Test("The top 5% of the card drags the window, once a press there moves 3 pt")
    func contentDrag() {
        let card = CGRect(x: 6, y: 6, width: 1232, height: 806)
        let band = ClusterGeometry.contentDragBand(card: card)
        #expect(band == CGRect(x: 6, y: 6, width: 1232, height: 40))
        #expect(!ClusterGeometry.startsWindowDrag(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 102, y: 21)))
        #expect(ClusterGeometry.startsWindowDrag(from: CGPoint(x: 100, y: 20), to: CGPoint(x: 103, y: 20)))
    }
}
