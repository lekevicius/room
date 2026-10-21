import CoreGraphics
import Design
import Testing
@testable import UIKitCore

@Suite("Sidebar hover reveal (spec §E)")
struct SidebarRevealTests {
    @Test("Resting the dwell in the edge band shows the overlay; leaving the band before that does not")
    func dwell() {
        var reveal = SidebarReveal()
        reveal.update(zone: .band, keepOpen: false, now: 10)
        #expect(!reveal.isShown)
        #expect(reveal.deadline == 10 + Timing.revealDwell)
        reveal.update(zone: .band, keepOpen: false, now: 10 + Timing.revealDwell / 2)
        #expect(!reveal.isShown)
        // The pointer rests: the deadline's tick shows it.
        reveal.update(zone: .band, keepOpen: false, now: 10 + Timing.revealDwell)
        #expect(reveal.isShown)

        var early = SidebarReveal()
        early.update(zone: .band, keepOpen: false, now: 0)
        early.update(zone: .elsewhere, keepOpen: false, now: 0.1)
        early.update(zone: .elsewhere, keepOpen: false, now: 0.2)
        #expect(!early.isShown)
        #expect(early.deadline == nil)
    }

    @Test("Leaving the overlay hides it after the 150 ms grace; coming back within it keeps it")
    func grace() {
        var reveal = shown()
        reveal.update(zone: .elsewhere, keepOpen: false, now: 20)
        #expect(reveal.isShown)
        #expect(reveal.deadline == 20 + Timing.revealGrace)
        reveal.update(zone: .overlay, keepOpen: false, now: 20.1)
        #expect(reveal.phase == .shown)
        reveal.update(zone: .elsewhere, keepOpen: false, now: 21)
        reveal.update(zone: .elsewhere, keepOpen: false, now: 21 + Timing.revealGrace)
        #expect(!reveal.isShown)
    }

    @Test("Menus, popovers and the palette keep it open; it leaves after the grace once they close")
    func keepOpen() {
        var reveal = shown()
        reveal.update(zone: .elsewhere, keepOpen: true, now: 30)
        reveal.update(zone: .elsewhere, keepOpen: true, now: 35)
        #expect(reveal.phase == .shown)
        reveal.update(zone: .elsewhere, keepOpen: false, now: 36)
        #expect(reveal.phase == .leaving(since: 36))
        reveal.update(zone: .elsewhere, keepOpen: false, now: 36.2)
        #expect(!reveal.isShown)
    }

    @Test("Near the overlay outside the window (on the way to the Dock) it stays")
    func outsideTolerance() {
        var reveal = shown()
        reveal.update(zone: .tolerance, keepOpen: false, now: 40)
        reveal.update(zone: .tolerance, keepOpen: false, now: 45)
        #expect(reveal.phase == .shown)
    }

    @Test("⌥⌘S pins it until ⌥⌘S again or a click in the page")
    func pin() {
        var reveal = SidebarReveal()
        reveal.togglePin()
        #expect(reveal.isShown && reveal.isPinned)
        reveal.update(zone: .elsewhere, keepOpen: false, now: 1)
        reveal.update(zone: .elsewhere, keepOpen: false, now: 9)
        #expect(reveal.isShown)
        #expect(reveal.deadline == nil)
        reveal.pageClicked()
        #expect(!reveal.isShown && !reveal.isPinned)

        var toggled = shown()
        toggled.togglePin()
        #expect(toggled.isPinned)
        toggled.togglePin()
        #expect(!toggled.isShown && !toggled.isPinned)
    }

    @Test("Zones: the 4 pt band, the overlay with its inset, 200 × 100 pt outside it, elsewhere")
    func zones() {
        let size = CGSize(width: 1000, height: 700)
        let overlay = CGRect(x: 10, y: 10, width: 240, height: 680)
        #expect(RevealZone.of(CGPoint(x: 2, y: 300), contentSize: size, overlay: nil) == .band)
        #expect(RevealZone.of(CGPoint(x: 4, y: 300), contentSize: size, overlay: nil) == .elsewhere)
        #expect(RevealZone.of(CGPoint(x: 500, y: 300), contentSize: size, overlay: nil) == .elsewhere)
        #expect(RevealZone.of(CGPoint(x: -50, y: 300), contentSize: size, overlay: nil) == .elsewhere)
        // Shown: the band and the gap before the overlay count as the overlay.
        #expect(RevealZone.of(CGPoint(x: 2, y: 300), contentSize: size, overlay: overlay) == .overlay)
        #expect(RevealZone.of(CGPoint(x: 249, y: 5), contentSize: size, overlay: overlay) == .overlay)
        #expect(RevealZone.of(CGPoint(x: 251, y: 300), contentSize: size, overlay: overlay) == .elsewhere)
        // Outside the window.
        #expect(RevealZone.of(CGPoint(x: -190, y: 300), contentSize: size, overlay: overlay) == .tolerance)
        #expect(RevealZone.of(CGPoint(x: -200, y: 300), contentSize: size, overlay: overlay) == .elsewhere)
        #expect(RevealZone.of(CGPoint(x: 100, y: 780), contentSize: size, overlay: overlay) == .tolerance)
        #expect(RevealZone.of(CGPoint(x: 100, y: 800), contentSize: size, overlay: overlay) == .elsewhere)
        // Sidebar on the right (Settings v0): the band and the overlay at the right edge.
        let right = CGRect(x: size.width - 260, y: 10, width: 250, height: 780)
        #expect(RevealZone.of(CGPoint(x: size.width - 2, y: 300), contentSize: size, overlay: nil, edge: .right) == .band)
        #expect(RevealZone.of(CGPoint(x: 2, y: 300), contentSize: size, overlay: nil, edge: .right) == .elsewhere)
        #expect(RevealZone.of(CGPoint(x: size.width - 100, y: 300), contentSize: size, overlay: right, edge: .right) == .overlay)
        #expect(RevealZone.of(CGPoint(x: size.width - 300, y: 300), contentSize: size, overlay: right, edge: .right) == .elsewhere)
        #expect(RevealZone.of(CGPoint(x: size.width + 150, y: 300), contentSize: size, overlay: right, edge: .right) == .tolerance)
    }

    private func shown() -> SidebarReveal {
        var reveal = SidebarReveal()
        reveal.update(zone: .band, keepOpen: false, now: 0)
        reveal.update(zone: .band, keepOpen: false, now: 1)
        return reveal
    }
}
