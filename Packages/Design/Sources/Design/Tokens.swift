import AppKit

/// Spacing scale (points). Everything in the chrome snaps to these.
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
}

/// Corner radii (points). All rounded chrome uses `.continuous` corner curves.
public enum Radius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 12
}

/// Sidebar geometry (feature spec §E).
public enum SidebarMetrics {
    public static let defaultWidth: CGFloat = 240
    public static let minWidth: CGFloat = 180
    public static let maxWidth: CGFloat = 500
    /// Dragging the splitter below this width snaps the sidebar closed.
    public static let snapCloseWidth: CGFloat = 120
    /// Hit area of the splitter, centred on the sidebar/card boundary.
    public static let splitterHitWidth: CGFloat = 8
    /// Height of the header row that sits beside the traffic lights.
    public static let headerHeight: CGFloat = 52
    /// Gap between the zoom button and the first header element.
    public static let headerLeadingGap: CGFloat = Spacing.m
    /// Inset from the sidebar edges for header elements when no traffic lights are beside them.
    public static let edgeInset: CGFloat = Spacing.l
    /// Saturation and opacity applied to the sidebar content while the window is inactive (spec §I.12).
    public static let inactiveSaturation: CGFloat = 0.8
    public static let inactiveContentAlpha: CGFloat = 0.6

    // Rows (Phase 2.2). Measured from `dia-window.jpg` at 1×: the selected
    // pill spans x 6…274 of a 280 pt sidebar and is 34 pt tall, the favicon
    // starts at x 16, the title at x 38, and rows repeat every ~37 pt.

    /// Height of an entry row; the selection pill leaves `pillVerticalInset` above and below.
    public static let rowHeight: CGFloat = 36
    public static let pillVerticalInset: CGFloat = 1
    /// Dia's pill is "slightly elevated": a faint shadow in light mode only (chosen).
    public static let pillShadowOpacity: Float = 0.08
    public static let pillShadowRadius: CGFloat = 1.5
    public static let pillShadowOffset = CGSize(width: 0, height: -0.5)
    /// Gap between the sidebar edges and the selection pill / hover background.
    public static let rowHorizontalInset: CGFloat = 6
    /// Gap between the pill's leading edge and the favicon.
    public static let rowContentInset: CGFloat = 10
    public static let faviconSize: CGFloat = 16
    public static let faviconTitleGap: CGFloat = 6
    /// Extra leading inset per folder level (chosen).
    public static let folderIndent: CGFloat = 14
    /// Close × hit area on Today rows (spec §I.4).
    public static let closeButtonSize: CGFloat = 28
    /// Audio indicator on a row (spec §I.5) (chosen).
    public static let audioIndicatorWidth: CGFloat = 22
    /// Small corner badges on Essentials tiles (audio) and their inset (chosen).
    public static let tileBadgeSize: CGFloat = 11
    public static let tileBadgeInset: CGFloat = 3
    /// Footer buttons and the space-title chevron hit area (chosen).
    public static let footerButtonSize: CGFloat = 28
    public static let chevronSize: CGFloat = 20
    /// Text field width in sidebar popovers (Edit Pinned URL…, Rename) (chosen).
    public static let popoverFieldWidth: CGFloat = 280
    /// Changed-entry badge (spec §I.8).
    public static let changedDotSize: CGFloat = 6
    /// Favicon of an unloaded entry (spec §A.1).
    public static let unloadedIconAlpha: CGFloat = 0.6
    /// The Today separator row ("Clear") (chosen).
    public static let separatorRowHeight: CGFloat = 24
    /// Space title row above the pinned list (chosen; same pitch as entries).
    public static let spaceTitleRowHeight: CGFloat = 36

    /// Essentials tiles (spec §I.2): 36 pt tall, icon 20 pt, background the
    /// icon's dominant colour at 15%. Tiles stretch to fill the row; a row
    /// holds as many as fit at `essentialTileMinWidth`, at most `essentialMaxColumns`.
    public static let essentialTileHeight: CGFloat = 36
    public static let essentialTileMinWidth: CGFloat = 48
    public static let essentialMaxColumns = 6
    public static let essentialIconSize: CGFloat = 20
    public static let essentialTintAlpha: CGFloat = 0.15
    public static let essentialsGap: CGFloat = Spacing.s

    /// Address field in the header, beside the traffic lights (chosen).
    public static let addressFieldHeight: CGFloat = 28
    /// The header (address field) ends at the rows' trailing inset, aligned
    /// with the selection pill (2.2a review: the domain truncated at 16 pt).
    public static let headerTrailingInset: CGFloat = rowHorizontalInset
    /// Horizontal padding inside the address field, around the site icon and
    /// the domain (2.2a review: trimmed from 8 to `Spacing.xs`).
    public static let addressFieldPadding: CGFloat = Spacing.xs
    /// Bottom bar (spec §F).
    public static let footerHeight: CGFloat = 40
    /// Drag insertion line, drop-onto ring and keyboard focus ring (spec §A.9, §I.13).
    public static let insertionLineWidth: CGFloat = 2
    /// The lifted row under the pointer while dragging: scale and shadow (spec §A.9).
    public static let dragLiftScale: CGFloat = 1.03
    public static let dragShadowRadius: CGFloat = 8
    public static let dragShadowOpacity: CGFloat = 0.25
    /// Rows being dragged stay in place, dimmed (chosen).
    public static let draggedRowAlpha: CGFloat = 0.35
    /// The overflow indicator's line and its click target (spec §I.11).
    public static let overflowLineWidth: CGFloat = 2
    public static let overflowHitHeight: CGFloat = 10
    /// The Essentials "12/12" badge and the refused-drop shake amplitude (spec §A.9; chosen sizes).
    public static let fullBadgeHeight: CGFloat = 16
    public static let shakeDistance: CGFloat = 6
    /// Pointer travel before a press on a tile becomes a drag (AppKit's own is ~3 pt).
    public static let dragThreshold: CGFloat = 3
}

/// The inset page card (PLAN §2.4).
public enum CardMetrics {
    /// Gap between the card and the window edge on the top, trailing and bottom sides.
    /// Measured from Dia's window (6pt); the ROADMAP's first guess was 8.
    public static let inset: CGFloat = 6
    /// Gap on the sidebar side while the sidebar is open (the card butts against it).
    public static let sidebarSideInset: CGFloat = 0
    /// Continuous corner; fitted to Dia's card (its curve reaches the fill
    /// ~3pt along the diagonal, 12pt reaches it at ~3.75pt). ROADMAP guessed 12.
    public static let cornerRadius: CGFloat = Radius.medium
    public static let borderWidth: CGFloat = 1
    public static let shadowRadius: CGFloat = 4
    public static let shadowOffset = CGSize(width: 0, height: -1)
    public static let shadowOpacityLight: Float = 0.15
    public static let shadowOpacityDark: Float = 0.35
}

/// Type styles. SF Pro through the system font so vibrancy and Dynamic Type-ish scaling behave.
public enum Typography {
    /// Sidebar rows, address field.
    public static var row: NSFont { .systemFont(ofSize: 13, weight: .regular) }
    /// Space title in the sidebar header.
    public static var spaceTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    /// Sublabels, footer labels, badges.
    public static var secondary: NSFont { .systemFont(ofSize: 11, weight: .regular) }
    /// The palette's text field (chosen; Arc's command bar is a size up from its rows).
    public static var paletteField: NSFont { .systemFont(ofSize: 18, weight: .regular) }
}

/// Window and overlay materials.
public enum Materials {
    /// The window-wide material behind the sidebar and around the card (Dia's neutral look).
    public static let window: NSVisualEffectView.Material = .sidebar
    public static let windowBlending: NSVisualEffectView.BlendingMode = .behindWindow
    /// Opacity range of the space tint gradient over the window material.
    public static let tintOpacityRange: ClosedRange<CGFloat> = 0.10...0.25
    /// Default tint opacity (top of the gradient; the bottom fades to the lower bound).
    public static let tintOpacity: CGFloat = 0.18
}

/// Animation timing. Durations in seconds.
public enum Motion {
    /// Palette open, hover fades.
    public static let fast: TimeInterval = 0.12
    /// Row insert/remove, hover-reveal dwell, keep-open grace.
    public static let standard: TimeInterval = 0.15
    /// Space switch slide, tint crossfade, sidebar reveal.
    public static let medium: TimeInterval = 0.25
    /// Peek open, selection pill.
    public static let slow: TimeInterval = 0.35

    /// A spring described like SwiftUI's `Spring(duration:bounce:)`.
    public struct Spring: Sendable, Equatable {
        public let duration: TimeInterval
        public let bounce: Double

        public init(duration: TimeInterval, bounce: Double) {
            self.duration = duration
            self.bounce = bounce
        }

        /// A Core Animation spring for `keyPath` with these parameters.
        public func animation(keyPath: String) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: duration, bounce: bounce)
            animation.keyPath = keyPath
            animation.duration = animation.settlingDuration
            return animation
        }
    }

    /// Selection pill moving between rows (spec §I.1).
    public static let pill = Spring(duration: 0.35, bounce: 0.15)
    /// Toast in, download-button bounce (spec §F).
    public static let toast = Spring(duration: 0.5, bounce: 0.2)
    /// Layout changes without overshoot (sidebar open/close, splitter snap).
    public static let smooth = Spring(duration: 0.25, bounce: 0)

    /// Toast fade+scale out (spec §F).
    public static let toastOut: TimeInterval = 0.2
    /// Row pulse on rename commit, 1 → 0.98 → 1 (spec §I.9).
    public static let renamePulseScale: CGFloat = 0.98
    /// Clear's staggered slide-out: per row, and the cap on the whole stagger (spec §A.7).
    public static let clearStagger: TimeInterval = 0.03
    public static let clearStaggerMax: TimeInterval = 0.3
    /// Refused drop on a full Essentials grid (spec §A.9; chosen).
    public static let shake: TimeInterval = 0.4
    /// Favicon crossfade back to the stored icon on reset (spec §A.5).
    public static let resetCrossfade: TimeInterval = 0.15

    /// Whether to replace movement with crossfades (spec §I.1).
    @MainActor public static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// How long transient UI stays up (seconds).
public enum Timing {
    /// A toast without a button (spec §F).
    public static let toast: TimeInterval = 2
    /// A toast with a button (spec §F).
    public static let toastWithAction: TimeInterval = 5
    /// "Tabs closed · Undo" after Clear (spec §A.7).
    public static let undoToast: TimeInterval = 8
    /// Tooltip with the full URL over the address field (spec §C).
    public static let urlTooltipDelay: TimeInterval = 0.6
    /// A background page is discarded after this long unseen: Today tabs,
    /// then pinned entries and essentials (spec §H).
    public static let discardIdleToday: TimeInterval = 60 * 60
    public static let discardIdlePermanent: TimeInterval = 3 * 60 * 60
    /// How often the idle-discard sweep runs (chosen).
    public static let discardSweepInterval: TimeInterval = 60
    /// ⌃Tab held this long before the switcher shows; a quicker tap
    /// switches without it (chosen).
    public static let tabSwitcherDelay: TimeInterval = 0.12
    /// Text typed into the palette for a tab and not committed comes back
    /// when the palette reopens on that tab within this long (spec §C, Zen `wait-to-clear`).
    public static let typedTextMemory: TimeInterval = 45
    /// Search suggestions are requested once typing pauses this long (ROADMAP 2.4 task 6;
    /// `macos-ui-stack.md` §5.2: 100–150 ms).
    public static let suggestDebounce: TimeInterval = 0.12
}

/// The ⌃Tab MRU switcher (spec §G: five recent tabs, favicons).
public enum TabSwitcherMetrics {
    /// Entries listed.
    public static let limit = 5
    public static let width: CGFloat = 340
    public static let rowHeight: CGFloat = 36
    public static let padding: CGFloat = 8
}

/// The ⌘T / ⌘L palette (spec §C, §I.1).
public enum PaletteMetrics {
    /// Spec §C (Zen's floating urlbar).
    public static let width: CGFloat = 640
    /// The palette's top edge sits this far down the card (spec §C: 18% of the content area).
    public static let topFraction: CGFloat = 0.18
    /// Never closer than this to the window's edges when the window is narrow (chosen).
    public static let windowMargin: CGFloat = 16
    public static let fieldHeight: CGFloat = 48
    /// Text inset in the field; the search icon sits in it (chosen, `Spacing.l`).
    public static let fieldInset: CGFloat = 16
    /// Rows match the sidebar's (measured from Dia).
    public static let rowHeight: CGFloat = 36
    /// Around the list; the highlight pill is inset like the sidebar's selection pill.
    public static let listPadding: CGFloat = 6
    public static let iconSize: CGFloat = 16
    /// Gap between groups (chosen; groups have no headers, spec §C orders them).
    public static let groupGap: CGFloat = 4
    /// Open: scale 0.96 → 1 with a fade, `Motion.fast` (spec §I.1).
    public static let openScale: CGFloat = 0.96
    /// The site-search chip left of the field (spec §C): height and horizontal padding (chosen).
    public static let chipHeight: CGFloat = 24
    public static let chipPadding: CGFloat = 8
    /// The × that removes a history row (spec §C), on hover or highlight.
    public static let deleteButtonSize: CGFloat = 18
}
