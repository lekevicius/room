import AppKit
import Testing
@testable import Design

@Suite("Sidebar text: one scale factor for the sidebar's and the palette's tokens (5.3b)", .serialized)
struct TextScaleTests {
    /// ROADMAP 5.3 task 4: Settings ▸ Appearance ▸ Sidebar text scales the sidebar's and the palette's
    /// typography and row heights through the tokens. Medium is the design's sizes; small and large
    /// step the sidebar row's 14 pt by 2 pt, everything else by the same factor.
    @Test("The tokens at small, medium and large")
    func tokens() {
        defer { TextScale.size = .medium }
        let expected: [(TextScale.Size, row: CGFloat, secondary: CGFloat, title: CGFloat, palette: CGFloat, field: CGFloat,
                        height: CGFloat, separator: CGFloat)] = [
            (.small, 12, 9.5, 11, 11, 15.5, 31, 21),
            (.medium, 14, 11, 13, 13, 18, 36, 24),
            (.large, 16, 12.5, 15, 15, 20.5, 41, 27),
        ]
        for value in expected {
            TextScale.size = value.0
            #expect(Typography.sidebarRow.pointSize == value.row, "\(value.0)")
            #expect(Typography.sidebarSecondary.pointSize == value.secondary, "\(value.0)")
            #expect(Typography.sidebarSpaceTitle.pointSize == value.title, "\(value.0)")
            #expect(Typography.paletteRow.pointSize == value.palette, "\(value.0)")
            #expect(Typography.paletteSecondary.pointSize == value.secondary, "\(value.0)")
            #expect(Typography.paletteField.pointSize == value.field, "\(value.0)")
            #expect(SidebarMetrics.rowHeight == value.height, "\(value.0)")
            #expect(SidebarMetrics.spaceTitleRowHeight == value.height, "\(value.0)")
            #expect(SidebarMetrics.separatorRowHeight == value.separator, "\(value.0)")
            #expect(PaletteMetrics.rowHeight == value.height, "\(value.0)")
        }
    }

    @Test("Tokens outside the sidebar and the palette keep their sizes")
    func others() {
        defer { TextScale.size = .medium }
        TextScale.size = .large
        #expect(Typography.row.pointSize == 13)
        #expect(Typography.secondary.pointSize == 11)
        #expect(Typography.spaceTitle.pointSize == 13)
        #expect(SidebarMetrics.faviconSize == 16)
        #expect(LibraryMetrics.itemRowHeight == 36)
    }

    /// The exit's "the three text sizes render without clipping": a row's title over its hover
    /// sublabel (the tallest an entry row gets) and a palette row's line fit their rows at every size.
    @Test("A row's lines fit its height at every size")
    func fits() {
        defer { TextScale.size = .medium }
        for size in TextScale.Size.allCases {
            TextScale.size = size
            let entry = TextScale.lineHeight(Typography.sidebarRow) + TextScale.lineHeight(Typography.sidebarSecondary)
            #expect(entry <= SidebarMetrics.rowHeight, "\(size): \(entry) in \(SidebarMetrics.rowHeight)")
            #expect(TextScale.lineHeight(Typography.sidebarSpaceTitle) <= SidebarMetrics.spaceTitleRowHeight, "\(size)")
            #expect(TextScale.lineHeight(Typography.sidebarSecondary) <= SidebarMetrics.separatorRowHeight, "\(size)")
            #expect(TextScale.lineHeight(Typography.paletteRow) <= PaletteMetrics.rowHeight, "\(size)")
            #expect(TextScale.lineHeight(Typography.paletteField) <= PaletteMetrics.fieldHeight, "\(size)")
        }
    }

    @Test("A change posts once; setting the same size again does not")
    func notification() {
        defer { TextScale.size = .medium }
        TextScale.size = .medium
        final class Count: @unchecked Sendable { nonisolated(unsafe) var value = 0 }
        let posts = Count()
        let observer = NotificationCenter.default.addObserver(forName: TextScale.didChange, object: nil, queue: nil) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        TextScale.size = .large
        TextScale.size = .large
        #expect(posts.value == 1)
        var applied = TextScaleApplied()
        let first = applied.needsUpdate(), again = applied.needsUpdate()
        TextScale.size = .small
        let changed = applied.needsUpdate()
        #expect(first && !again && changed)
    }
}
