import AppKit
import Testing
import Design
@testable import Card

@Suite("Card")
struct CardTests {
    private func makeCard() -> CardView {
        let card = CardView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        card.layoutSubtreeIfNeeded()
        return card
    }

    @Test("Container clips with a continuous 12pt corner")
    func clipping() throws {
        let layer = try #require(makeCard().container.layer)
        #expect(layer.cornerRadius == CardMetrics.cornerRadius)
        #expect(layer.cornerCurve == .continuous)
        #expect(layer.masksToBounds)
    }

    @Test("Shadow lives on an unclipped sibling behind the container")
    func shadowSibling() throws {
        let card = makeCard()
        card.shadowView.updateLayer()
        let shadow = try #require(card.shadowView.layer)
        #expect(card.subviews.first === card.shadowView)
        #expect(card.subviews.last === card.container)
        #expect(!shadow.masksToBounds)
        #expect(shadow.shadowOpacity > 0)
        let path = try #require(shadow.shadowPath)
        #expect(path.boundingBox == card.bounds)
        #expect(card.shadowView.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }

    @Test("Shadow path follows resizes")
    func shadowResize() throws {
        let card = makeCard()
        card.setFrameSize(NSSize(width: 640, height: 480))
        card.layoutSubtreeIfNeeded()
        #expect(card.shadowView.layer?.shadowPath?.boundingBox == NSRect(x: 0, y: 0, width: 640, height: 480))
    }

    @Test("Border and background resolve per appearance")
    func appearanceColors() throws {
        let card = makeCard()
        let container = card.container
        for (name, brightCard) in [(NSAppearance.Name.aqua, true), (.darkAqua, false)] {
            container.appearance = NSAppearance(named: name)
            container.effectiveAppearance.performAsCurrentDrawingAppearance { container.updateLayer() }
            let layer = try #require(container.layer)
            let background = try #require(layer.backgroundColor.flatMap { NSColor(cgColor: $0) })
            #expect((background.brightnessComponent > 0.5) == brightCard)
            let border = try #require(layer.borderColor.flatMap { NSColor(cgColor: $0) })
            #expect((0.06...0.08).contains(border.alphaComponent))
            #expect(layer.borderWidth > 0 && layer.borderWidth <= 1)
        }
    }

    @Test("Background color is settable")
    func backgroundSettable() throws {
        let card = makeCard()
        card.backgroundColor = .systemRed
        card.container.updateLayer()
        let layer = try #require(card.container.layer)
        #expect(layer.backgroundColor == NSColor.systemRed.cgColor)
    }

    @Test("Content view fills the container and is replaced cleanly")
    func contentSlot() {
        let card = makeCard()
        let first = NSView()
        card.contentView = first
        #expect(first.superview === card.container)
        #expect(first.frame == card.container.bounds)
        let second = NSView()
        card.contentView = second
        #expect(first.superview == nil)
        #expect(second.superview === card.container)
        card.contentView = nil
        #expect(second.superview == nil)
    }

    @Test("The card never drags the window")
    func noWindowDrag() {
        let card = makeCard()
        #expect(!card.mouseDownCanMoveWindow)
        #expect(!card.container.mouseDownCanMoveWindow)
    }
}
