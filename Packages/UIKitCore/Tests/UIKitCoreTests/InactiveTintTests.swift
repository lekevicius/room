import AppKit
import Design
import Testing
@testable import UIKitCore

/// Spec §I.12: inactive windows desaturate the sidebar 20%. 5.2b found the tint's inactive colours
/// computed but never applied (the layer kept the active stops); now they reach the layer.
@Suite("Inactive tint")
@MainActor
struct InactiveTintTests {
    private func stops(_ view: SpaceTintView) -> [NSColor] {
        (view.gradientLayer.colors as? [CGColor] ?? []).compactMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
    }

    @Test("An inactive window's tint is fainter and 20% less saturated, and comes back when active")
    func inactiveStops() throws {
        let view = SpaceTintView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.appearance = NSAppearance(named: .aqua)
        let blue = NSColor(srgbRed: 0.12, green: 0.53, blue: 0.90, alpha: 1)
        view.setTint(SpaceTint(light: [blue, .systemRed, .systemGreen], dark: [blue], alpha: 0.2), animated: false)
        let active = try #require(stops(view).first)
        view.isWindowActive = false
        let inactive = try #require(stops(view).first)
        #expect(abs(inactive.alphaComponent - active.alphaComponent * SpaceTintView.inactiveFactor) < 0.002)
        #expect(abs(inactive.saturationComponent - active.saturationComponent * SidebarMetrics.inactiveSaturation) < 0.01)
        view.isWindowActive = true
        let again = try #require(stops(view).first)
        #expect(abs(again.alphaComponent - active.alphaComponent) < 0.002 && abs(again.saturationComponent - active.saturationComponent) < 0.01)
    }
}
