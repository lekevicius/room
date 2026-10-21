import AppKit
import Testing
@testable import Design

@Suite("Increase Contrast, Reduce Transparency, Differentiate Without Colour: the tokens per mode (5.3b)", .serialized)
struct DisplayOptionsTests {
    private static let ic = DisplayOptions(increaseContrast: true)
    private static let rt = DisplayOptions(reduceTransparency: true)
    private static let dwc = DisplayOptions(differentiateWithoutColor: true)

    private func alpha(_ color: NSColor, dark: Bool) -> CGFloat {
        color.resolved(for: NSAppearance(named: dark ? .darkAqua : .aqua)!).alphaComponent
    }

    /// ROADMAP 5.3 task 5: Increase Contrast moves hairlines and secondary text to their high-contrast tokens.
    @Test("Increase Contrast: hairlines and the sidebar's secondary text take their high-contrast tokens")
    func increaseContrast() {
        defer { DisplayOptions.source = .fixed(.standard) }
        DisplayOptions.source = .fixed(.standard)
        #expect(alpha(Palette.sidebarSecondaryLabel, dark: false) == Palette.sidebarSecondaryAlpha.light)
        #expect(alpha(Palette.sidebarSecondaryLabel, dark: true) == Palette.sidebarSecondaryAlpha.dark)
        let separator = alpha(NSColor.separatorColor, dark: false)
        #expect(alpha(Palette.hairline, dark: false) == separator)
        let border = alpha(Palette.cardBorder, dark: false)

        DisplayOptions.source = .fixed(Self.ic)
        #expect(alpha(Palette.sidebarSecondaryLabel, dark: false) == Palette.sidebarSecondaryHighContrastAlpha.light)
        #expect(alpha(Palette.sidebarSecondaryLabel, dark: true) == Palette.sidebarSecondaryHighContrastAlpha.dark)
        #expect(alpha(Palette.hairline, dark: false) == Palette.hairlineHighContrastAlpha.light)
        #expect(alpha(Palette.hairline, dark: true) == Palette.hairlineHighContrastAlpha.dark)
        #expect(alpha(Palette.cardBorder, dark: false) == Palette.hairlineHighContrastAlpha.light)
        // Stronger than the standard tokens, and secondary text still under the primary label (85%).
        #expect(Palette.hairlineHighContrastAlpha.light > max(separator, border))
        #expect(Palette.sidebarSecondaryHighContrastAlpha.light > Palette.sidebarSecondaryAlpha.light)
        #expect(Palette.sidebarSecondaryHighContrastAlpha.light <= 0.85 && Palette.sidebarSecondaryHighContrastAlpha.dark <= 0.85)
        // The other options leave them alone.
        DisplayOptions.source = .fixed(DisplayOptions(reduceTransparency: true, differentiateWithoutColor: true))
        #expect(alpha(Palette.sidebarSecondaryLabel, dark: false) == Palette.sidebarSecondaryAlpha.light)
        #expect(alpha(Palette.hairline, dark: false) == separator)
    }

    /// The bug 5.3b's modes sheet found: an unloaded row's title colour was resolved for the appearance of the row's
    /// last configure, so after a light/dark switch it drew dark text on the dark sidebar (and white on the light one).
    @Test("An unloaded title's colour follows the appearance it is drawn in")
    func unloadedTitle() {
        defer { DisplayOptions.source = .fixed(.standard) }
        DisplayOptions.source = .fixed(.standard)
        let light = Palette.sidebarUnloadedLabel.resolved(for: NSAppearance(named: .aqua)!)
        let dark = Palette.sidebarUnloadedLabel.resolved(for: NSAppearance(named: .darkAqua)!)
        #expect(light.redComponent == 0 && light.alphaComponent == SidebarMetrics.unloadedTitleAlpha)
        #expect(dark.redComponent == 1 && dark.alphaComponent == SidebarMetrics.unloadedTitleAlpha)
        DisplayOptions.source = .fixed(Self.ic)
        #expect(alpha(Palette.sidebarUnloadedLabel, dark: false) == Palette.sidebarSecondaryHighContrastAlpha.light)
    }

    @Test("Reduce Transparency: solid fills in place of the material and the glass")
    func reduceTransparency() {
        defer { DisplayOptions.source = .fixed(.standard) }
        #expect(!Materials.usesSolidFill(.standard))
        #expect(Materials.usesSolidFill(Self.rt))
        #expect(!Materials.usesSolidFill(Self.ic))
        #expect(Materials.solidFill.resolved(for: NSAppearance(named: .aqua)!).alphaComponent == 1)
        #expect(Materials.solidFill.resolved(for: NSAppearance(named: .darkAqua)!).alphaComponent == 1)
        // The backing an overlay holds follows a live toggle.
        DisplayOptions.source = .fixed(.standard)
        let backing = SolidBackingView(cornerRadius: Radius.large)
        #expect(backing.isHidden)
        DisplayOptions.source = .fixed(Self.rt)
        #expect(!backing.isHidden)
        DisplayOptions.source = .fixed(.standard)
        #expect(backing.isHidden)
    }

    @Test("Differentiate Without Colour: the changed dot and the audible glyph carry a shape")
    func differentiateWithoutColor() {
        #expect(ChangedMark.style(.standard) == ChangedMark.Style(size: SidebarMetrics.changedDotSize, outline: 0))
        let mark = ChangedMark.style(Self.dwc)
        #expect(mark.outline > 0)
        #expect(mark.size > SidebarMetrics.changedDotSize + mark.outline)
        #expect(AudioGlyph.symbol(muted: false, .standard) == .audible)
        #expect(AudioGlyph.symbol(muted: true, .standard) == .muted)
        #expect(AudioGlyph.symbol(muted: false, Self.dwc) == .audibleShape)
        #expect(AudioGlyph.symbol(muted: true, Self.dwc) == .mutedShape)
        // The other options keep the plain dot and glyphs.
        #expect(ChangedMark.style(DisplayOptions(increaseContrast: true, reduceTransparency: true)).outline == 0)
        #expect(AudioGlyph.symbol(muted: false, Self.ic) == .audible)
    }

    @Test("A changed source posts once and is what the tokens read")
    func refresh() {
        defer { DisplayOptions.source = .fixed(.standard) }
        DisplayOptions.source = .fixed(.standard)
        final class Count: @unchecked Sendable { nonisolated(unsafe) var value = 0 }
        let posts = Count()
        let observer = NotificationCenter.default.addObserver(forName: DisplayOptions.didChange, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        DisplayOptions.source = .fixed(Self.dwc)
        DisplayOptions.source = .fixed(Self.dwc)
        #expect(posts.value == 1)
        #expect(DisplayOptions.current == Self.dwc)
        #expect(ChangedMark.style() == ChangedMark.style(Self.dwc))
    }
}
