import AppKit

/// Settings ▸ Appearance ▸ Sidebar text (5.3b, ROADMAP 5.3 task 4): one scale
/// factor for the sidebar's and the palette's typography and row heights,
/// applied here in the tokens (`Typography.sidebarRow`, `sidebarSecondary`,
/// `sidebarSpaceTitle`, `paletteRow`, `paletteSecondary`, `paletteField`;
/// `SidebarMetrics.rowHeight`, `spaceTitleRowHeight`, `separatorRowHeight`;
/// `PaletteMetrics.rowHeight`), never per view. Medium is the design's sizes.
/// The steps are the sidebar row's 14 pt ± 2 pt, as Finder's sidebar sizes
/// step its text by 2 pt; icons, insets and the header keep their sizes.
public enum TextScale {
    public enum Size: String, CaseIterable, Sendable {
        case small, medium, large
    }

    /// The factor for `size`: the sidebar row's 12, 14 or 16 pt over 14.
    public static func factor(_ size: Size) -> CGFloat {
        switch size {
        case .small: 12.0 / 14
        case .medium: 1
        case .large: 16.0 / 14
        }
    }

    /// The size the UI uses now (the setting, applied by the app; `-RoomSidebarTextSize` in DEBUG).
    /// Setting a different size posts `didChange`, so the sidebar and the palette lay out again.
    public static var size: Size = .medium {
        didSet { if size != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
    }

    /// Posted on the main thread when `size` changes.
    public static let didChange = Notification.Name("RoomTextScaleDidChange")

    /// A type size: `base` scaled, to the nearest half point (medium: `base`).
    public static func fontSize(_ base: CGFloat, _ size: Size = TextScale.size) -> CGFloat {
        (base * factor(size) * 2).rounded() / 2
    }

    /// A row height: `base` scaled, to the nearest point (medium: `base`).
    public static func length(_ base: CGFloat, _ size: Size = TextScale.size) -> CGFloat {
        (base * factor(size)).rounded()
    }

    /// One line of `font` as a label lays it out: its cell's height, what the rows size their text
    /// frames to (5.3b: the layout manager's default line height was a point short at 9.5 and 15 pt,
    /// and the palette's labels clipped their text by a point at the small and large sizes).
    public static func lineHeight(_ font: NSFont) -> CGFloat {
        let probe = NSTextField(labelWithString: "Ag")
        probe.font = font
        return ceil(probe.cell?.cellSize.height ?? NSLayoutManager().defaultLineHeight(for: font))
    }
}

/// A view whose text follows `TextScale` keeps the size it last applied, so a
/// reused row re-sets its fonts only when the size changed.
public struct TextScaleApplied {
    private var applied: TextScale.Size?
    public init() {}

    /// True (and remembered) when the current size differs from the one last applied.
    public mutating func needsUpdate() -> Bool {
        guard applied != TextScale.size else { return false }
        applied = TextScale.size
        return true
    }
}
