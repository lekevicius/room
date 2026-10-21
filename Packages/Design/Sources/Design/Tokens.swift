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

/// One metric for the chrome's icon buttons (B-110, 5.2a): the top bar's
/// toggle, extensions, Back, Forward and Reload, and the footer's downloads,
/// New Tab and space icons are squares of this size at this pitch, with the
/// one hover and press style (`ControlFeedback`) on this corner, their
/// glyphs `IconStyle.control`.
public enum ControlMetrics {
    /// A button's square (the Room Browser design's top bar: 32 pt at a 32 pt pitch).
    public static let size: CGFloat = 32
    /// The narrowest a button gets when the sidebar is too narrow for all of them (chosen).
    public static let minSize: CGFloat = 24
    /// Between groups of buttons (the toggle and the extensions).
    public static let groupGap: CGFloat = Spacing.xs
    /// The hover fill's corner.
    public static let cornerRadius: CGFloat = Radius.small
}

/// The keyboard focus ring (5.3a): AppKit draws it in the system's focus
/// colour (`NSColor.keyboardFocusIndicatorColor`, the accent) around a mask
/// shaped like the control's own fill, so the ring follows the tokens'
/// corners: a button's hover square, the address field's pill, a tile.
/// Sidebar rows draw their own ring (`SidebarMetrics.insertionLineWidth`, spec §I.13).
public enum FocusRing {
    /// An icon button's ring: its hover square's corner.
    public static let controlCornerRadius: CGFloat = ControlMetrics.cornerRadius
    /// The address field's and an Essential tile's ring: the pill's corner.
    public static let pillCornerRadius: CGFloat = Radius.large
}

/// Hairlines (5.2a): one device pixel at the display's scale, never a point
/// (a 1 pt line is two pixels on a Retina display).
public enum Hairline {
    /// The line's width in points at `scale` (the window's `backingScaleFactor`): 1 px.
    public static func width(scale: CGFloat) -> CGFloat { 1 / max(scale, 1) }

    /// The width for `view` (its window's scale, else the main screen's, else 2×).
    @MainActor public static func width(in view: NSView) -> CGFloat {
        width(scale: view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}

/// Sidebar geometry (feature spec §E).
public enum SidebarMetrics {
    /// The Room Browser design (2026-10-07, Figma `UI` ▸ window): 304 in a
    /// 582 pt window; 300 leaves the top bar room for two extension buttons.
    public static let defaultWidth: CGFloat = 300
    public static let minWidth: CGFloat = 180
    public static let maxWidth: CGFloat = 500
    /// Dragging the splitter below this width snaps the sidebar closed.
    public static let snapCloseWidth: CGFloat = 120
    /// Hit area of the splitter, centred on the sidebar/card boundary.
    public static let splitterHitWidth: CGFloat = 8
    /// Height of the top bar that sits beside the traffic lights (the
    /// fallback when there are none: its buttons centre on half of it).
    public static let headerHeight: CGFloat = 48
    /// Gap between the zoom button and the first header element.
    public static let headerLeadingGap: CGFloat = Spacing.m
    /// Gap between the zoom button and the sidebar toggle (the design: lights 17…77, toggle at 92).
    public static let topBarLeadingGap: CGFloat = 15
    /// The top bar's buttons (sidebar toggle, extensions, Back, Forward,
    /// Reload): `ControlMetrics` squares at their own pitch (the Room Browser design).
    public static let topBarButtonSize: CGFloat = ControlMetrics.size
    /// The narrowest a top-bar button gets when the sidebar is too narrow for all of them.
    public static let topBarButtonMinSize: CGFloat = ControlMetrics.minSize
    /// Between the sidebar toggle and the extensions (the extensions pack against Back, B-125).
    public static let topBarGroupGap: CGFloat = ControlMetrics.groupGap
    /// Between the top bar and the address row, and the address row and the body.
    public static let addressRowGap: CGFloat = Spacing.s
    /// Inset from the sidebar edges for header elements when no traffic lights are beside them.
    public static let edgeInset: CGFloat = Spacing.l
    /// Saturation and opacity applied to the sidebar content while the window is inactive (spec §I.12).
    public static let inactiveSaturation: CGFloat = 0.8
    public static let inactiveContentAlpha: CGFloat = 0.6

    // Rows. Phase 2.2 measured Dia (`dia-window.jpg`); the Room Browser
    // design (2026-10-07) replaced it: rows at a 36 pt pitch with the pill
    // filling the row, 8 pt from the sidebar's edges, the favicon 10 pt into
    // the pill and the title 10 pt after it.

    /// Height of an entry row; the selection pill leaves `pillVerticalInset` above and below.
    public static var rowHeight: CGFloat { TextScale.length(36) }
    public static let pillVerticalInset: CGFloat = 0
    /// The pill is "slightly elevated" (B-112, 5.2a: a subtle shadow under
    /// the selected row, as Arc's and Dia's; was the design's `0 0.5 2` at
    /// 15%, light only, which did not read): `0 1 4` at 12% light, 30% dark.
    public static let pillShadowOpacity: Float = 0.12
    public static let pillShadowOpacityDark: Float = 0.3
    public static let pillShadowRadius: CGFloat = 2
    public static let pillShadowOffset = CGSize(width: 0, height: -1)
    /// The pill's shadow opacity in an appearance.
    public static func pillShadowOpacity(dark: Bool) -> Float { dark ? pillShadowOpacityDark : pillShadowOpacity }
    /// The rows' pill, hover fill, Essentials tiles and the address field (the design: 12).
    public static let pillCornerRadius: CGFloat = Radius.large
    /// Width of the fade that ends a title too long for its row (the design: 12 pt, no ellipsis).
    public static let titleFadeWidth: CGFloat = 12
    /// Gap between the sidebar edges and the selection pill / hover background.
    public static let rowHorizontalInset: CGFloat = Spacing.s
    /// Gap between the pill's leading edge and the favicon.
    public static let rowContentInset: CGFloat = 10
    public static let faviconSize: CGFloat = 16
    public static let faviconTitleGap: CGFloat = 10
    /// Extra leading inset per folder level (chosen).
    public static let folderIndent: CGFloat = 14
    /// A folder row's glyph box (B-115, 5.2a: the folder at Finder's and Notes' sidebar size,
    /// `IconStyle.folder`), centred where a favicon sits; wider than the favicon.
    public static let folderGlyphSize = CGSize(width: 20, height: 18)
    /// Close × on Today rows (spec §I.4), and its gap to the pill's trailing edge.
    public static let closeButtonSize: CGFloat = 24
    public static let closeButtonInset: CGFloat = 6
    /// The row's small buttons (×, audio): their hover square's corner (their glyphs `IconStyle.rowButton`).
    public static let rowButtonCornerRadius: CGFloat = 4
    /// Audio button on a row (spec §I.5): after the favicon, the title
    /// `Spacing.s` after it; filled only on hover (the Room Browser design).
    public static let audioIndicatorWidth: CGFloat = 24
    /// Small corner badges on Essentials tiles (audio) and their inset (chosen).
    public static let tileBadgeSize: CGFloat = 11
    public static let tileBadgeInset: CGFloat = 3
    /// Footer buttons (B-110: the top bar's `ControlMetrics`; was 28) and the space-title chevron hit area (chosen).
    public static let footerButtonSize: CGFloat = ControlMetrics.size
    public static let chevronSize: CGFloat = 20
    /// Text field width in sidebar popovers (Edit Pinned URL…, Rename) (chosen).
    public static let popoverFieldWidth: CGFloat = 280
    /// Changed-entry badge (spec §I.8).
    nonisolated public static let changedDotSize: CGFloat = 6
    /// The unread dot at a row's trailing edge (a title's "(3)" counter, spec §I.3; chosen: the changed dot's size).
    public static let unreadDotSize: CGFloat = 6
    /// A custom icon's emoji in a favicon's square, as a share of the square (chosen).
    public static let customIconEmojiScale: CGFloat = 0.82
    /// Favicon of an unloaded entry (spec §A.1).
    public static let unloadedIconAlpha: CGFloat = 0.5
    /// The title of an unloaded entry (the design: 70% of the label colour).
    public static let unloadedTitleAlpha: CGFloat = Palette.unloadedTitleAlpha
    /// The Today separator row ("Clear") (chosen).
    public static var separatorRowHeight: CGFloat { TextScale.length(24) }
    /// Space title row above the pinned list (chosen; same pitch as entries).
    public static var spaceTitleRowHeight: CGFloat { TextScale.length(36) }

    /// Essentials tiles (spec §I.2): 40 pt tall, icon 16 pt, on the rows'
    /// hover fill (the Room Browser design: neutral tiles, the selected one
    /// the pill's fill). Tiles stretch to fill the row; a row holds as many
    /// as fit at `essentialTileMinWidth`, at most `essentialMaxColumns`.
    public static let essentialTileHeight: CGFloat = 40
    public static let essentialTileMinWidth: CGFloat = 48
    public static let essentialMaxColumns = 6
    public static let essentialIconSize: CGFloat = 16
    /// A hovered tile: the selection fill at this alpha over the tile's own.
    public static let essentialHoverAlpha: CGFloat = 0.5
    /// The selected tile's lift (the design: `drop-shadow 0 0.5 1 rgba(0,0,0,.15)`).
    public static let essentialShadowRadius: CGFloat = 0.5
    public static let essentialsGap: CGFloat = Spacing.s

    /// The address row under the top bar, as wide as the rows' pill (the Room Browser design).
    public static let addressFieldHeight: CGFloat = 36
    /// The top bar and the address row end at the rows' trailing inset, aligned with the selection pill.
    public static let headerTrailingInset: CGFloat = rowHorizontalInset
    /// Horizontal padding inside the address field: before the domain, after the site button.
    public static let addressFieldPadding: CGFloat = 10
    /// The site button and Copy URL inside the address field.
    public static let addressButtonSize: CGFloat = 24
    /// An extension action's badge height (3.6b).
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

/// Footer space icons (spec §B; chosen sizes, `docs/design-tokens.md`).
public enum SpaceIconMetrics {
    /// An icon's glyph box (its emoji or symbol); the dot of a space without an icon is smaller.
    public static let size: CGFloat = 20
    /// Icon spacing along the row, and each icon's square hit area and hover fill
    /// (B-110, 5.2a: the top bar's `ControlMetrics.size`; was 26 with a 20 pt box).
    public static let pitch: CGFloat = ControlMetrics.size
    public static let dotSize: CGFloat = 6
    /// The active icon's scale (spec §B).
    public static let activeScale: CGFloat = 1.15
    /// The highlight behind the active icon extends this far around it.
    public static let indicatorPadding: CGFloat = 2
    /// An inactive icon's opacity.
    public static let inactiveAlpha: CGFloat = 0.55
    /// Pointer travel that turns a press on an icon into a reorder drag (Zen: 5 px).
    public static let reorderThreshold: CGFloat = 5
}

/// The space form (spec §B; 2.5, chosen; the space window replaces it in 5.7b).
public enum SpaceFormMetrics {
    public static let padding: CGFloat = Spacing.m
    public static let iconCell: CGFloat = 26
    public static let previewHeight: CGFloat = 18
    /// The icon grid's selected cell (accent at this alpha) and the preview's corner.
    public static let selectionAlpha: CGFloat = 0.25
    public static let cornerRadius: CGFloat = Radius.small
    /// The theme preview with no colours (secondary at this alpha), and a one-colour gradient's fade.
    public static let emptyPreviewAlpha: CGFloat = 0.12
    public static let previewFadeAlpha: CGFloat = 0.4
    /// Change Icon…'s popover for an entry or a folder (5.6a): the picker's six columns and its padding.
    public static let iconPopoverWidth: CGFloat = 6 * iconCell + 5 * 4 + 2 * padding + 24
}

/// The space window (5.7b, B-122): its size, fitted inside the display's visible frame.
public enum SpaceWindowMetrics {
    public static let width: CGFloat = 420
    public static let height: CGFloat = 640
    /// The least height it shrinks to on a small display (the sections scroll).
    public static let minHeight: CGFloat = 360
    /// The gap kept to the visible frame's edges.
    public static let screenMargin: CGFloat = Spacing.s
}

/// Onboarding (5.7b, B-121): the window and its steps.
public enum OnboardingMetrics {
    public static let width: CGFloat = 560
    public static let height: CGFloat = 440
    public static let padding: CGFloat = 24
    /// The step's symbol above its title.
    public static let symbolSize: CGFloat = 40
    /// The step dots under the content.
    public static let dotSize: CGFloat = 6
    /// The theme step's colour swatches.
    public static let swatchSize: CGFloat = 28
    /// The swatches: no colour, then six base colours (the space's algorithm extends the one chosen).
    public static let themeSwatches: [String?] = [nil, "#1E88E5", "#3E9B5B", "#E53935", "#8E24AA", "#FB8C00", "#546E7A"]
    /// The no-colour swatch's fill (secondary at this alpha) and the steps not shown (the dots).
    public static let emptySwatchAlpha: Double = 0.15
    public static let inactiveDotAlpha: Double = 0.35
    /// The ring around the chosen swatch.
    public static let swatchRingWidth: CGFloat = 2
}

/// The footer's media row (spec §F, §I.5; 4.6): one row above the footer at
/// the rows' width (chosen sizes; Chapter 5 revisits).
public enum MediaRowMetrics {
    public static let height: CGFloat = 40
    /// The artwork or favicon.
    public static let imageSize: CGFloat = 24
    public static let imageCornerRadius: CGFloat = Radius.small / 2
    /// Play/pause, next and × (their glyphs `IconStyle.media`).
    public static let buttonSize: CGFloat = 24
    /// Above the footer and below the list.
    public static let gap: CGFloat = Spacing.xs
}

/// The document picture-in-picture panel (4.6, B-51).
public enum PictureInPictureMetrics {
    /// The smallest panel content (a page asking less gets this).
    public static let minimumSize = CGSize(width: 160, height: 90)
}

/// The screenshot overlay over the card (⇧⌘2, 4.7a): the dimmed outside, the
/// selection's outline and the result bar.
public enum ScreenshotMetrics {
    /// Black over everything outside the selection.
    public static let dimAlpha: CGFloat = 0.35
    public static let selectionBorderWidth: CGFloat = 1
    /// A drag shorter than this (either side) is a click, not a selection.
    public static let minimumSelection: CGFloat = 4
    /// The bar under the selection (or at the card's bottom).
    public static let barHeight: CGFloat = 36
    public static let barPadding: CGFloat = Spacing.s
    public static let barGap: CGFloat = Spacing.s
    public static let barCornerRadius: CGFloat = Radius.medium
    /// Chromium's largest capture texture side, in device pixels: a full page is clipped to it.
    public static let maximumCapturePixels: CGFloat = 16_384
}

/// The reader page (4.7b): a Room-owned HTML page whose CSS variables are
/// generated from these and the `Palette`/system colours (`ReaderStyle` in
/// Chrome). Chosen; Chapter 5 judges the look.
public enum ReaderMetrics {
    /// Body text per `Settings.readerTextSize` (CSS px = pt at 1×): small, medium, large.
    public static let textSizes: [CGFloat] = [16, 19, 23]
    /// The article title relative to the body text.
    public static let titleScale: CGFloat = 1.6
    /// Headings inside the article relative to the body text.
    public static let headingScale: CGFloat = 1.25
    /// The byline (host, original link) and captions relative to the body text.
    public static let secondaryScale: CGFloat = 0.8
    /// Line height as a multiple of the text size.
    public static let lineHeight: CGFloat = 1.55
    /// The measure: the text column's widest line, in `em` of the body text.
    public static let measure: CGFloat = 34
    /// Space above the title and between blocks.
    public static let pagePadding: CGFloat = Spacing.l * 3
    public static let blockGap: CGFloat = Spacing.m
    /// Image corners.
    public static let imageRadius: CGFloat = Radius.small
    /// A page is an article when the distiller's text is at least this many characters.
    public static let minimumArticleCharacters = 400
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
    /// The sidebar row's medium height: the Library keeps its sizes under `TextScale` (5.3b).
    public static let itemRowHeight: CGFloat = 36
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

/// Several windows (Phase 4.8a).
public enum WindowMetrics {
    /// ⌘N's new window sits this far right of and below the key window
    /// (AppKit's `cascadeTopLeft` step; chosen, Chapter 5 may tune it).
    public static let cascadeOffset: CGFloat = 22
    /// A sidebar entry dropped this far outside its window's frame opens in a
    /// new window at the drop point (spec §A.9: "beyond 40px past the window edge").
    public static let dragOutDistance: CGFloat = 40
    /// The incognito window's "Incognito" label: its row under the sidebar's
    /// header row, before the list (4.8b).
    public static let incognitoLabelHeight: CGFloat = 16
    public static let incognitoLabelGap: CGFloat = 4
}

/// The window's buttons (traffic lights): AppKit places and draws them; Room never moves them.
public enum TrafficLightMetrics {
    /// Settings ▸ Appearance ▸ Grey window buttons (spec §I.12, mono traffic lights): the
    /// buttons' saturation (a `CIColorControls` filter; 0 is grey, the inactive window's look).
    public static let monochromeSaturation: CGFloat = 0
}

public enum CardMetrics {
    /// Gap between the card and the window edge on the top, trailing and bottom sides.
    /// Dia's window measured 6; the Room Browser design (2026-10-07) is 8.
    public static let inset: CGFloat = Spacing.s
    /// Gap on the sidebar side while the sidebar is open (the card butts against it).
    public static let sidebarSideInset: CGFloat = 0
    /// Continuous corner (the Room Browser design: 6; Dia measured 10).
    public static let cornerRadius: CGFloat = Radius.small
    public static let borderWidth: CGFloat = 1
    /// The design's `0 2 6 rgba(0,0,0,.15)` (blur 6 = radius 3).
    public static let shadowRadius: CGFloat = 3
    public static let shadowOffset = CGSize(width: 0, height: -2)
    public static let shadowOpacityLight: Float = 0.15
    public static let shadowOpacityDark: Float = 0.35
}

/// Type styles. SF Pro through the system font so vibrancy and Dynamic Type-ish scaling behave.
/// Against the HIG's macOS scale (5.2a, `docs/design-tokens.md` Typography): `row` is Body (13),
/// `secondary` Subheadline (11), `headline` Headline (13, semibold where the HIG says bold);
/// the others are the design's or chosen sizes between the HIG's styles.
public enum Typography {
    /// Rows outside the sidebar (palette, menus, panels).
    public static var row: NSFont { .systemFont(ofSize: 13, weight: .regular) }
    /// Sidebar rows and the address field (the Room Browser design: SF Pro 14; `TextScale`: 12 / 14 / 16).
    public static var sidebarRow: NSFont { .systemFont(ofSize: TextScale.fontSize(14), weight: .regular) }
    /// A sidebar row's sublabel and the Today separator's Clear (`secondary` scaled by `TextScale`, 5.3b).
    public static var sidebarSecondary: NSFont { .systemFont(ofSize: TextScale.fontSize(11), weight: .regular) }
    /// The space's name above its pinned list (`spaceTitle` scaled by `TextScale`, 5.3b).
    public static var sidebarSpaceTitle: NSFont { .systemFont(ofSize: TextScale.fontSize(13), weight: .semibold) }
    /// A palette row's title and detail (`row` scaled by `TextScale`, 5.3b).
    public static var paletteRow: NSFont { .systemFont(ofSize: TextScale.fontSize(13), weight: .regular) }
    /// A palette row's space chip and hint, and the site-search chip (`secondary` scaled by `TextScale`, 5.3b).
    public static var paletteSecondary: NSFont { .systemFont(ofSize: TextScale.fontSize(11), weight: .regular) }
    /// Space title in the sidebar header.
    public static var spaceTitle: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    /// Sublabels, footer labels, badges.
    public static var secondary: NSFont { .systemFont(ofSize: 11, weight: .regular) }
    /// The palette's text field (chosen; Arc's command bar is a size up from its rows; `TextScale` since 5.3b).
    public static var paletteField: NSFont { .systemFont(ofSize: TextScale.fontSize(18), weight: .regular) }

    // Added in 5.2a (the token-drift audit: each was a literal at its call site).

    /// Titles of the page's dialogs and sheets ("example.com says"): the space title's style.
    public static var headline: NSFont { spaceTitle }
    /// The certificate interstitial's and the crashed page's title (chosen; HIG Large Title is 26 regular).
    public static var interstitialTitle: NSFont { .systemFont(ofSize: 24, weight: .semibold) }
    /// Their text (chosen; between HIG Body 13 and Title 3 15, the sidebar rows' size).
    public static var interstitialText: NSFont { .systemFont(ofSize: 14, weight: .regular) }
    /// Error codes and other machine text.
    public static var code: NSFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    /// Counts that change in place ("3 of 12" in the find bar).
    public static var counter: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }
    /// The zoom indicator's percentage.
    public static var zoomValue: NSFont { .monospacedDigitSystemFont(ofSize: 13, weight: .medium) }
    /// A toast's message (chosen, 2.2a).
    public static var toast: NSFont { .systemFont(ofSize: 12, weight: .semibold) }
    /// Badges: the Essentials "12/12" badge, the downloads count, an extension action's badge (chosen).
    public static var badgeLarge: NSFont { .systemFont(ofSize: 10, weight: .semibold) }
    public static var badge: NSFont { .systemFont(ofSize: 9, weight: .semibold) }
    public static var badgeSmall: NSFont { .systemFont(ofSize: 8, weight: .semibold) }
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

    /// Reduce Transparency (5.3b): the opaque fill in place of the window's material and the
    /// overlays' glass (AppKit's window background, what the system draws for materials then).
    public static var solidFill: NSColor { .windowBackgroundColor }

    /// Whether the window's material and the overlays' glass are replaced by `solidFill`.
    public nonisolated static func usesSolidFill(_ options: DisplayOptions = .current) -> Bool { options.reduceTransparency }
}

/// The changed-entry dot (spec §I.8) under Differentiate Without Colour (5.3b): larger, with a
/// ring in `Palette.changedMarkOutline` around it, so its shape reads on a favicon of any colour
/// (an accent dot on a favicon of the accent's hue is otherwise told apart by colour alone).
public enum ChangedMark {
    public struct Style: Equatable, Sendable {
        /// The dot's diameter, ring included.
        public let size: CGFloat
        /// The ring's width (0: no ring).
        public let outline: CGFloat
    }

    public nonisolated static func style(_ options: DisplayOptions = .current) -> Style {
        options.differentiateWithoutColor ? Style(size: 9, outline: 1.5) : Style(size: SidebarMetrics.changedDotSize, outline: 0)
    }
}

/// The audible and muted glyphs (spec §I.5) under Differentiate Without Colour (5.3b): inside a
/// filled circle, a shape of their own beside the title and on an Essentials tile's corner.
public enum AudioGlyph {
    public nonisolated static func symbol(muted: Bool, _ options: DisplayOptions = .current) -> Symbol {
        switch (muted, options.differentiateWithoutColor) {
        case (false, false): .audible
        case (true, false): .muted
        case (false, true): .audibleShape
        case (true, true): .mutedShape
        }
    }
}

/// Animation timing. Durations in seconds.
public enum Motion {
    /// Palette open, hover fades.
    public static let fast: TimeInterval = 0.12
    /// Row insert/remove (the hover reveal's grace is `Timing.revealGrace`).
    public static let standard: TimeInterval = 0.15
    /// Space switch slide, tint crossfade (the sidebar's reveal is `revealIn`/`revealOut` since B-114).
    public static let medium: TimeInterval = 0.25
    /// Peek open.
    public static let slow: TimeInterval = 0.35
    /// The hidden sidebar slides in over this long, ease-out (spec §E said 250 ms;
    /// B-114: shortened with the dwell), and out over `revealOut`, ease-in.
    public static let revealIn: TimeInterval = 0.18
    public static let revealOut: TimeInterval = 0.15

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

    /// Toast in, download-button bounce (spec §F).
    public static let toast = Spring(duration: 0.5, bounce: 0.2)
    /// Layout changes without overshoot (sidebar open/close, splitter snap).
    public static let smooth = Spring(duration: 0.25, bounce: 0)

    /// Toast fade+scale out (spec §F).
    public static let toastOut: TimeInterval = 0.2
    /// Row pulse on rename commit, 1 → 0.98 → 1 (spec §I.9).
    public static let renamePulseScale: CGFloat = 0.98
    /// The pulse's length, in and out (spec §I.9 gives none; twice `standard`, as since 2.2a).
    public static let renamePulse: TimeInterval = 2 * standard
    /// Clear's staggered slide-out: per row, and the cap on the whole stagger (spec §A.7).
    public static let clearStagger: TimeInterval = 0.03
    public static let clearStaggerMax: TimeInterval = 0.3
    /// Refused drop on a full Essentials grid (spec §A.9; chosen).
    public static let shake: TimeInterval = 0.4
    /// Favicon crossfade back to the stored icon on reset (spec §A.5).
    public static let resetCrossfade: TimeInterval = 0.15

    // MARK: Hover and press (B-111, 5.1b)

    /// An icon button pressed: it shrinks to this scale about its centre (chosen, as Arc's press).
    public static let pressScale: CGFloat = 0.9
    /// The press-in: quick, so a click shows it (chosen; ease-out).
    public static let pressIn: TimeInterval = 0.08
    /// The release: a spring back to full size with a little bounce (chosen).
    public static let pressRelease = Spring(duration: 0.3, bounce: 0.35)
    /// Reduce Motion: no scale; the pressed button dims to this alpha and back, over `fast` (chosen).
    public static let pressReducedAlpha: CGFloat = 0.6

    // MARK: Toasts (spec §F, 5.1b)

    /// A toast that enters rises from this far below its place and grows from `toastInScale` (chosen, 2.2a).
    public static let toastInOffset: CGFloat = 12
    public static let toastInScale: CGFloat = 0.9
    /// … and leaves shrinking to this scale with its fade (`toastOut`; chosen, 2.2a).
    public static let toastOutScale: CGFloat = 0.95
    /// The same id again (spec §F "replaces with a pop"): up to this scale over `toastPopUp`, back over `toastPopDown` (springs; chosen, 2.2a).
    public static let toastPopScale: CGFloat = 1.06
    public static let toastPopUp: TimeInterval = 0.12
    public static let toastPopDown: TimeInterval = 0.25

    /// The motion preferences the UI reads: the system's by default; tests
    /// and the `-RoomReduceMotion` launch flag (DEBUG) inject their own (5.1a).
    @MainActor public static var preferences: MotionPreferences = .system

    /// Whether to replace movement with crossfades (spec §I.1).
    @MainActor public static var reduceMotion: Bool { preferences.reduceMotion() }
}

/// What the UI asks before animating (spec §I.1: every animation honours
/// Reduce Motion). Injected through `Motion.preferences`.
public struct MotionPreferences: Sendable {
    public var reduceMotion: @MainActor @Sendable () -> Bool

    public init(reduceMotion: @escaping @MainActor @Sendable () -> Bool) {
        self.reduceMotion = reduceMotion
    }

    /// System Settings ▸ Accessibility ▸ Display ▸ Reduce motion.
    public static let system = MotionPreferences { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A fixed answer (tests, `-RoomReduceMotion YES`).
    public static func fixed(reduceMotion: Bool) -> MotionPreferences { MotionPreferences { reduceMotion } }
}

/// How one animation runs under the current motion preferences.
public enum MotionVariant: String, Sendable, Equatable {
    /// As specified: movement, scale, springs (or the crossfade an animation already is).
    case full
    /// Movement replaced by a crossfade.
    case crossfade
    /// No animation: the end state at once.
    case instant
}

public extension CALayer {
    /// Actions that turn off a plain layer's implicit animations (Core
    /// Animation's 0.25 s default on any property change): our layers
    /// animate only through explicit animations on the tokens (5.1a).
    static let noImplicitActions: [String: any CAAction] = Dictionary(uniqueKeysWithValues: [
        "hidden", "position", "bounds", "frame", "opacity", "backgroundColor", "borderColor", "cornerRadius", "contents",
        "path", "strokeColor", "fillColor", "lineWidth", "transform", "sublayers", "onOrderIn", "onOrderOut", "shadowOpacity",
    ].map { ($0, NSNull() as any CAAction) })
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
    /// slides in (spec §E said 150 ms; B-114, 2026-10-21: shortened so the
    /// sidebar, with the traffic lights in it, arrives sooner).
    public static let revealDwell: TimeInterval = 0.06
    /// The revealed sidebar hides this long after the pointer left it (spec §E,
    /// Zen `sidebar-keep-hover.duration`: 150 ms).
    public static let revealGrace: TimeInterval = 0.15
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
    /// Rows match the sidebar's (measured from Dia; `TextScale` since 5.3b).
    public static var rowHeight: CGFloat { TextScale.length(36) }
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
    /// The line between a split row's segments in the sidebar (spec §D: 1 px).
    public static let dividerWidth: CGFloat = 1
    /// Split view's panes are cards of their own (B-113, 5.2a: each with the card's corner,
    /// border and shadow) with this gap between them: the card's inset from the window.
    public static let paneGap: CGFloat = CardMetrics.inset
    /// The resizer's hit area, centred in the gap (spec §D: 7 px around a 1 px line;
    /// B-113: the gap and a point either side).
    public static let resizerHitWidth: CGFloat = paneGap + 2
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
    /// ⇧⌘2's Open as Tab files in `<state>/Screenshots/` (B-92): pruned at
    /// launch when older than 7 days or beyond the newest 50.
    public static let screenshotsAge: TimeInterval = 7 * 86_400
    public static let screenshotsKept = 50
}
