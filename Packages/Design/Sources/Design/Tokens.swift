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
    /// An extension's action button beside the site button (3.6b, chosen;
    /// no polish until Chapter 5): its width and the badge's height.
    public static let extensionActionWidth: CGFloat = 22
    public static let extensionBadgeHeight: CGFloat = 10
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
/// The Library in the sidebar (4.1a, ⇧⌘L): a search field, then the
/// Archive, Downloads and History sections (chosen; Chapter 5 revisits).
public enum LibraryMetrics {
    /// The search field matches the header's address field.
    public static let searchFieldHeight: CGFloat = SidebarMetrics.addressFieldHeight
    /// A section's title row (click to collapse).
    public static let sectionRowHeight: CGFloat = 28
    /// A day's label inside the Archive and History.
    public static let dayRowHeight: CGFloat = 22
    /// An item: favicon, title, domain, the space chip, its buttons.
    public static let itemRowHeight: CGFloat = SidebarMetrics.rowHeight
    /// A row's Restore, Reveal and × buttons.
    public static let buttonSize: CGFloat = 20
    /// The space chip and the "Archived" mark.
    public static let chipHeight: CGFloat = 16
    public static let chipPadding: CGFloat = Spacing.xs
    /// History without a query: the last week, by day, at most this many URLs.
    public static let historyDays = 7
    public static let historyLimit = 500
    /// History with a query: the engine's matches, then `history-archive.json`'s (B-66).
    public static let searchLimit = 200
}

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
    /// The archive sweep runs at launch and then this often while the window
    /// is idle (spec §A.7: every 10 min).
    public static let archiveSweepInterval: TimeInterval = 10 * 60
    /// "Idle" for the archive sweep: no key or mouse press in Room for this
    /// long (chosen, 4.1a); a sweep that falls due earlier waits for it.
    public static let archiveIdleAfter: TimeInterval = 60
    /// A rolling backup of the state database is taken this often while the
    /// state changes (spec §H; chosen, 4.1b), and at launch.
    public static let backupInterval: TimeInterval = 30 * 60
    /// Under critical memory pressure, one more background page is discarded
    /// this often until the pressure drops (chosen, 3.7b).
    public static let criticalPressureStep: TimeInterval = 1
    /// ⌃Tab held this long before the switcher shows; a quicker tap
    /// switches without it (chosen).
    public static let tabSwitcherDelay: TimeInterval = 0.12
    /// Text typed into the palette for a tab and not committed comes back
    /// when the palette reopens on that tab within this long (spec §C, Zen `wait-to-clear`).
    public static let typedTextMemory: TimeInterval = 45
    /// The palette builds its sidebar snapshot this long after opening: after
    /// the open's first frame (≤ 16.7 ms plus the turn at 60 Hz), before a
    /// person's first keystroke (chosen, 2.6a).
    public static let paletteContextDelay: TimeInterval = 0.03
    /// Search suggestions are requested once typing pauses this long (ROADMAP 2.4 task 6;
    /// `macos-ui-stack.md` §5.2: 100–150 ms).
    public static let suggestDebounce: TimeInterval = 0.12
    /// The zoom indicator stays this long after the last change (chosen).
    public static let zoomIndicator: TimeInterval = 1.5
    /// The status pill shows a hovered link after this long (spec §I.14: 600 ms) …
    public static let statusPillDelay: TimeInterval = 0.6
    /// … and widens to the full URL after it has shown this long (spec §I.14: 1.5 s).
    public static let statusPillExpand: TimeInterval = 1.5
    /// Leaving a link hides the pill after this long, so moving between links
    /// does not flicker it (chosen).
    public static let statusPillHideGrace: TimeInterval = 0.1
    /// The pointer rests this long in the edge band before the hidden sidebar
    /// slides in (spec §E: 150 ms).
    public static let revealDwell: TimeInterval = 0.15
    /// The revealed sidebar hides this long after the pointer left it (spec §E,
    /// Zen `sidebar-keep-hover.duration`: 150 ms).
    public static let revealGrace: TimeInterval = 0.15
    /// The floating traffic-light cluster fades after this long without the
    /// pointer moving near it (spec §E: 2 s).
    public static let clusterFade: TimeInterval = 2
    /// `window.location` set by a page this soon after a user gesture
    /// navigates in place, never into Peek (spec §A.4: 2 s).
    nonisolated public static let peekGestureWindow: TimeInterval = 2
    /// A sidebar entry dragged onto another row's centre joins it into a
    /// split after resting this long (spec §D: 500 ms).
    public static let splitJoinDwell: TimeInterval = 0.5
    /// A pane's header hides this long after the pointer left its band (chosen).
    public static let paneHeaderHideDelay: TimeInterval = 0.3
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

/// The page's prompts in the card (ROADMAP 2.6 task 2): JavaScript dialogs,
/// `beforeunload` and HTTP auth as a sheet over the page, the certificate
/// interstitial, the permission popover.
public enum PromptMetrics {
    /// The dialog panel (chosen; Chrome's tab-modal dialogs are ~450 pt).
    public static let dialogWidth: CGFloat = 420
    /// Below the card's top edge, as Chrome's tab-modal dialogs hang from the toolbar (chosen).
    public static let dialogTopInset: CGFloat = 32
    public static let dialogPadding: CGFloat = 20
    public static let dialogSpacing: CGFloat = 12
    /// A long message scrolls past this height (chosen).
    public static let messageMaxHeight: CGFloat = 240
    /// Over the page while a dialog waits: black at this alpha (light / dark appearance, chosen).
    public static let dimAlphaLight: CGFloat = 0.18
    public static let dimAlphaDark: CGFloat = 0.35
    /// The certificate interstitial's column and icon (chosen).
    public static let interstitialWidth: CGFloat = 520
    public static let interstitialIconSize: CGFloat = 44
    /// The permission popover's content width (chosen).
    public static let permissionWidth: CGFloat = 360
}

/// The hidden sidebar and its hover-revealed overlay (spec §E, Phase 2.7a).
public enum RevealMetrics {
    /// The band at the window's leading edge that reveals the sidebar (spec §E: 4 px).
    public static let edgeBand: CGFloat = 4
    /// The revealed overlay floats this far from the window's top, leading
    /// and bottom edges (spec §E: Zen `--zen-compact-float`, 10 px).
    public static let overlayInset: CGFloat = 10
    /// A grey wash inside the overlay's glass, like the docked sidebar's
    /// material (white 0.88 light, 0.16 dark) at this alpha, so rows and the
    /// white selection pill read over any page (chosen: untinted glass let
    /// page text show through; the glass's own tint rendered near white and hid the pill).
    public static let overlayTintAlpha: CGFloat = 0.75
    public static let overlayTintWhiteLight: CGFloat = 0.88
    public static let overlayTintWhiteDark: CGFloat = 0.16
    /// The overlay's corner (chosen: the overlays' `Radius.large`).
    public static let overlayCornerRadius: CGFloat = Radius.large
    /// With the pointer outside the window, the overlay stays while the
    /// pointer is this close to it (spec §E: Zen `outside-window-edge-offset`, 200 × 100 px).
    public static let outsideToleranceX: CGFloat = 200
    public static let outsideToleranceY: CGFloat = 100
    /// The overlay's header holds Back, Forward and Reload beside the traffic
    /// lights (spec §E); the address field moves to a row below it (chosen).
    public static let navigationButtonSize: CGFloat = 28
    public static let addressRowGap: CGFloat = 4
}

/// The floating traffic-light cluster while the sidebar is hidden (spec §E).
public enum ClusterMetrics {
    /// The glass pill behind the window's own buttons (spec §E: 38 px).
    public static let height: CGFloat = 38
    /// Pill padding beside the outer buttons (chosen: as the pill's vertical
    /// room around the 14 pt buttons, 12 pt).
    public static let horizontalPadding: CGFloat = 12
    /// The pointer counts as near the cluster within this distance of the
    /// pill (chosen).
    public static let nearDistance: CGFloat = 60
    /// The top of the card that drags the window while the sidebar is hidden
    /// (spec §E: Zen `drag-window-from-content`, the top 5%).
    public static let contentDragFraction: CGFloat = 0.05
    /// A press there drags the window once it moves this far (AppKit's drag
    /// threshold, as `SidebarMetrics.dragThreshold`); a click still reaches the page.
    public static let contentDragThreshold: CGFloat = 3
}

/// The optional toolbar (View ▸ Show Toolbar; spec §E: 36 px with Back,
/// Forward, Reload and the full URL).
public enum ToolbarMetrics {
    public static let height: CGFloat = 36
    public static let buttonSize: CGFloat = 28
    /// Before the first button and after the URL (chosen).
    public static let padding: CGFloat = 6
    public static let urlHeight: CGFloat = 26
}

/// Peek: off-site links from permanent entries in an overlay card (spec §A.4, §I.6).
public enum PeekMetrics {
    /// The card's share of the content area's width and height (spec §I.6: 86%).
    public static let sizeFraction: CGFloat = 0.86
    /// The card's corner (spec §I.6: 24 px).
    public static let cornerRadius: CGFloat = 24
    /// The content under the card is dimmed with black at this alpha (spec §I.6: 30%).
    public static let dimAlpha: CGFloat = 0.30
    /// The header with the domain, Open as Tab, Split and × (chosen).
    public static let headerHeight: CGFloat = 40
    public static let headerButtonSize: CGFloat = 28
    public static let headerPadding: CGFloat = 10
    /// The card floats higher than the page card (chosen).
    public static let shadowRadius: CGFloat = 24
    public static let shadowOpacityLight: Float = 0.25
    public static let shadowOpacityDark: Float = 0.5
    /// The open animation starts at this scale around the click point (spec
    /// §I.1: "scale from the link's rect"; the engine reports no link rect, chosen).
    public static let openStartScale: CGFloat = 0.1
}

/// Split view (spec §D): up to four panes in the card.
public enum SplitMetrics {
    /// The visible line between panes; the card's fill shows through it (spec §D: 1 px).
    public static let dividerWidth: CGFloat = 1
    /// The resizer's hit area, centred on the line (spec §D: 7 px).
    public static let resizerHitWidth: CGFloat = 7
    /// No pane gets smaller than this share of the split along the dragged
    /// axis (Zen `min-resize-width`: 7 percent) …
    public static let minimumPaneFraction: CGFloat = 0.07
    /// … nor smaller than this, while the split has room for it (chosen).
    public static let minimumPaneLength: CGFloat = 120
    /// The header a pane shows on hover: domain, grip, layout, × (spec §D: 24 px).
    public static let paneHeaderHeight: CGFloat = 24
    /// The header shows while the pointer is this close to the pane's top (chosen: the header and a little below).
    public static let paneHeaderRevealBand: CGFloat = 36
    public static let paneHeaderButtonSize: CGFloat = 20
    /// Drop zones over a pane when an entry is dragged into the content area:
    /// within this distance of an edge the entry splits to that side (spec
    /// §D: 40 px), elsewhere it replaces the pane.
    public static let dropEdgeBand: CGFloat = 40
    /// An edge drop's preview covers this share of the pane on that side (chosen: the half the new pane gets).
    public static let dropPreviewFraction: CGFloat = 0.5
    /// The preview's fill and border (chosen).
    public static let dropPreviewAlpha: CGFloat = 0.18
    /// The sidebar's group row: each pane's segment shows its title when it is at least this wide (chosen).
    public static let segmentTitleMinWidth: CGFloat = 64
    /// The focused pane's segment is tinted with the accent at this alpha (spec §D "tinted", chosen).
    public static let focusedSegmentAlpha: CGFloat = 0.16
}

/// The docked DevTools pane under the page (Phase 1.4; resizable in 2.6b).
public enum DevToolsMetrics {
    /// The pane's share of the card when first opened (Phase 1.4).
    public static let defaultFraction: CGFloat = 0.42
    /// Neither side of the divider gets smaller than this (chosen).
    public static let minPaneHeight: CGFloat = 120
    public static let minPageHeight: CGFloat = 120
    /// The divider's drag area, centred on its 1 pt line (chosen, as the sidebar splitter).
    public static let dividerHitHeight: CGFloat = 8
}

/// The first-run card above the sidebar's footer (ROADMAP 2.8 task 4,
/// `macos-ui-stack.md` §7.4 "an in-sidebar card, never a modal").
public enum FirstRunMetrics {
    /// Inside the card (chosen: the overlay panels' 12 pt).
    public static let padding: CGFloat = Spacing.m
    /// Between the card's rows (chosen).
    public static let rowSpacing: CGFloat = Spacing.s
    /// The selection pill's radius, so the card reads as one of the sidebar's own surfaces (chosen).
    public static let cornerRadius: CGFloat = Radius.medium
    /// Between the card and the footer, and between the list and the card (chosen).
    public static let gapAboveFooter: CGFloat = Spacing.xs
    public static let gapAboveList: CGFloat = Spacing.s
    /// The card's shadow, as the pill's lift (chosen).
    public static let shadowOpacity: Float = 0.08
    public static let shadowRadius: CGFloat = 3
}

/// How long Room keeps what it keeps (spec §H; B-80). Numbers, not settings.
public enum Retention {
    /// Rolling backups (Arc's schedule, spec §H): the newest 10 of today, one
    /// a day for the 10 days before, one a week back a month, one a month back a year.
    public static let backupsToday = 10
    public static let backupDays = 10
    public static let backupWeeksSpanDays = 31
    public static let backupMonthsSpanDays = 365
    /// Archive rows are pruned at the sweep after 30 days (B-80, the
    /// planner's provisional number; Arc keeps its Archive about as long).
    public static let archiveRows: TimeInterval = 30 * 86_400
    /// An archived row keeps its back/forward list for 7 days, then only its
    /// URL (B-80).
    public static let archiveNavigationState: TimeInterval = 7 * 86_400
}
