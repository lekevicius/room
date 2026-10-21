import AppKit
import Testing
@testable import Design

@Suite("Design tokens")
struct DesignTests {
    @Test("Every color asset resolves in light and dark")
    func colorsResolve() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        for name in Palette.allNames {
            let color = try #require(NSColor(named: name, bundle: .module), "missing \(name)")
            _ = color.resolved(for: light)
            _ = color.resolved(for: dark)
        }
    }

    @Test("Card background flips with appearance")
    func cardBackgroundIsDynamic() throws {
        let light = Palette.cardBackground.resolved(for: try #require(NSAppearance(named: .aqua)))
        let dark = Palette.cardBackground.resolved(for: try #require(NSAppearance(named: .darkAqua)))
        #expect(light.brightnessComponent > 0.95)
        #expect(dark.brightnessComponent < 0.2)
    }

    @Test("Card border is a 6–8% hairline")
    func cardBorderAlpha() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let border = Palette.cardBorder.resolved(for: try #require(NSAppearance(named: name)))
            #expect((0.06...0.08).contains(border.alphaComponent))
        }
    }

    @Test("Every symbol exists in SF Symbols", arguments: Symbol.allCases)
    func symbolExists(_ symbol: Symbol) {
        #expect(symbol.image() != nil, "\(symbol) → \(symbol.name)")
    }

    @Test("Symbol images are templates")
    func symbolTemplate() throws {
        #expect(try #require(Symbol.newTab.image()).isTemplate)
    }

    @Test("Sidebar width bounds are ordered")
    func sidebarBounds() {
        #expect(SidebarMetrics.snapCloseWidth < SidebarMetrics.minWidth)
        #expect(SidebarMetrics.minWidth <= SidebarMetrics.defaultWidth)
        #expect(SidebarMetrics.defaultWidth <= SidebarMetrics.maxWidth)
    }

    @Test("Tint opacity sits in its range")
    func tintRange() {
        #expect(Materials.tintOpacityRange.contains(Materials.tintOpacity))
    }

    @Test("Spring animation settles")
    func spring() {
        let animation = Motion.toast.animation(keyPath: "position")
        #expect(animation.keyPath == "position")
        #expect(animation.duration > 0)
    }

    @Test("Appearance darkness")
    func darkness() throws {
        #expect(try #require(NSAppearance(named: .darkAqua)).isDark)
        #expect(try !#require(NSAppearance(named: .aqua)).isDark)
    }

    @Test("Hairlines are one device pixel at 1×, 2× and 3× (5.2a task 3)")
    func hairline() {
        for scale: CGFloat in [1, 2, 3] {
            #expect(Hairline.width(scale: scale) * scale == 1)
        }
    }

    @Test("B-110: the footer's buttons and space icons are the top bar's one control metric")
    func oneControlMetric() {
        #expect(SidebarMetrics.topBarButtonSize == ControlMetrics.size)
        #expect(SidebarMetrics.footerButtonSize == ControlMetrics.size)
        #expect(SpaceIconMetrics.pitch == ControlMetrics.size)
        #expect(IconStyle.control.pointSize == 13)
    }
}
