# Design tokens, v0 (frozen in Phase 1.6)

The values Chapter 2 builds on. Source of truth: `Packages/Design`
(`Tokens.swift`, `Colors.swift` + `Resources/Colors.xcassets`, `Symbols.swift`).
This page records them with where each came from. "Frozen" means: Chapter 2
uses these names and values; changing one needs a reason in the
`docs/progress.md` log and a fresh window-snapshot run
(`scripts/window-snapshots.sh`). New tokens may be added; Chapter 5 (Polish)
is where the set is revisited as a whole.

Provenance key: **measured** = pixel-measured against Dia's window
(`research/notes/spike-results.md`, Phase 1.3/1.4); **spec** = feature spec
section; **chosen** = our call, no reference measurement.

## Spacing (pt)

| Token | Value | Provenance |
|---|---|---|
| `Spacing.xs` | 4 | chosen |
| `Spacing.s` | 8 | chosen |
| `Spacing.m` | 12 | chosen; also the gap after the zoom button (measured: title glyphs at x=93–94 match Dia) |
| `Spacing.l` | 16 | chosen; header inset when no traffic lights are beside it (fullscreen) |

## Radii (pt, continuous corners)

| Token | Value | Provenance |
|---|---|---|
| `Radius.small` | 6 | chosen (rows, pills) |
| `Radius.medium` | 10 | measured: Dia's card corner (fill reached at k=3 on the diagonal) |
| `Radius.large` | 12 | chosen (popovers, palette) |

## Window geometry

| Token | Value | Provenance |
|---|---|---|
| `CardMetrics.inset` | 6 | measured (ROADMAP guessed 8) |
| `CardMetrics.sidebarSideInset` | 0 | measured: the card butts against the sidebar |
| `CardMetrics.cornerRadius` | 10 (`Radius.medium`) | measured (guessed 12) |
| `CardMetrics.borderWidth` | 1 | measured: hairline composites above the page |
| `CardMetrics.shadowRadius` / `shadowOffset` | 4 / (0, −1) | measured: rows y=812…816 within 1–4 luma of Dia |
| `CardMetrics.shadowOpacityLight` / `Dark` | 0.15 / 0.35 | measured (light); chosen (dark) |
| `SidebarMetrics.defaultWidth` | 240 | spec §E |
| `SidebarMetrics.minWidth` / `maxWidth` | 180 / 500 | spec §E (Zen max 500) |
| `SidebarMetrics.snapCloseWidth` | 120 | spec §E |
| `SidebarMetrics.splitterHitWidth` | 8 | chosen |
| `SidebarMetrics.headerHeight` | 52 | measured: AppKit's unified-toolbar titlebar, traffic lights at (19,19) |
| `SidebarMetrics.headerLeadingGap` | 12 | measured (see `Spacing.m`) |
| `SidebarMetrics.edgeInset` | 16 | chosen |
| `SidebarMetrics.inactiveSaturation` / `inactiveContentAlpha` | 0.8 / 0.6 | spec §I.12 (desaturate 20%) |

## Typography

| Token | Value | Provenance |
|---|---|---|
| `Typography.row` | system 13 regular | chosen (Dia/Arc rows) |
| `Typography.spaceTitle` | system 13 semibold | measured: Dia's header title |
| `Typography.secondary` | system 11 regular | chosen |

## Materials

| Token | Value | Provenance |
|---|---|---|
| `Materials.window` | `.sidebar`, behind-window | measured: Dia's neutral material (227 vs our 233 luma at (140,400); backdrop-dependent) |
| `Materials.tintOpacityRange` | 0.10–0.25 | chosen |
| `Materials.tintOpacity` | 0.18 | chosen |
| Overlays (palette, hover sidebar, Peek, toasts) | `NSGlassEffectView` | PLAN §2.4; Phase 1.4 overlay spike |

## Colors (asset catalog, sRGB, light / dark)

| Token | Light | Dark | Provenance |
|---|---|---|---|
| `Palette.cardBackground` | 1.000 1.000 1.000 | 0.094 0.094 0.098 | chosen; dark darkened in Phase 1.3 for inactive contrast. Replaced at runtime by the page's `rootBackgroundColor` |
| `Palette.cardBorder` | black α 0.07 | white α 0.08 | measured (light) |
| `Palette.cardShadow` | black | black | opacity from `CardMetrics` |
| `Palette.sidebarSelection` | white α 0.90 | white α 0.12 | chosen (Chapter 2 pill) |
| `Palette.sidebarHover` | black α 0.06 | white α 0.06 | spec §I.4 |
| `Palette.spaceTintDefault` | 0.545 0.584 0.784 | 0.420 0.459 0.659 | chosen |

## Motion

| Token | Value | Use (spec) |
|---|---|---|
| `Motion.fast` | 0.12 s | palette open, hover fades (§I.1) |
| `Motion.standard` | 0.15 s | row insert/remove, hover-reveal dwell, keep-open grace (§E, §I.1) |
| `Motion.medium` | 0.25 s | space switch slide, tint crossfade, sidebar reveal (§B, §E) |
| `Motion.slow` | 0.35 s | Peek open, selection pill (§I.1, §I.6) |
| `Motion.pill` | spring 0.35 s, bounce 0.15 | selection pill |
| `Motion.toast` | spring 0.5 s, bounce 0.2 | toasts, download-button bounce (§F) |
| `Motion.smooth` | spring 0.25 s, bounce 0 | sidebar open/close, splitter snap |

Springs use `CASpringAnimation(perceptualDuration:bounce:)`. Every animation
has a reduced-motion alternative (crossfade), spec §I.1.

## Symbols

`Symbols.swift` names the SF Symbols the chrome uses (`Symbol` cases, 77 at
the freeze); `DesignTests` checks each exists and renders as a template. Adding a symbol means adding a case there.

## Added in Phase 2.2 (sidebar rows, toasts)

| Token | Value | Provenance |
|---|---|---|
| `SidebarMetrics.rowHeight` / `pillVerticalInset` | 36 / 1 | measured: Dia's selected pill is 34 pt tall, rows repeat every ~37 pt (`dia-window.jpg`, 1×) |
| `SidebarMetrics.rowHorizontalInset` | 6 | measured: pill spans x 6…274 of a 280 pt sidebar (same as `CardMetrics.inset`) |
| `SidebarMetrics.rowContentInset` / `faviconSize` / `faviconTitleGap` | 10 / 16 / 6 | measured: favicon at x 16, title at x 38 |
| Selection pill corner | `Radius.medium` (10) | measured: Dia's pill corner reaches the fill ~5 px down at 1.5 px in |
| `SidebarMetrics.pillShadowOpacity` / `Radius` / `Offset` | 0.08 / 1.5 / (0, −0.5), light only | chosen ("slightly elevated" pill) |
| `SidebarMetrics.folderIndent` | 14 | chosen |
| `SidebarMetrics.closeButtonSize` | 28 | spec §I.4 |
| `SidebarMetrics.changedDotSize` | 6 | spec §I.8 |
| `SidebarMetrics.unloadedIconAlpha` | 0.6 | spec §A.1 |
| `SidebarMetrics.separatorRowHeight` / `spaceTitleRowHeight` | 24 / 36 | chosen |
| `SidebarMetrics.essentialTileHeight` / `essentialIconSize` / `essentialTintAlpha` | 36 / 20 / 0.15 | spec §I.2 |
| `SidebarMetrics.essentialTileMinWidth` / `essentialMaxColumns` / `essentialsGap` | 48 / 6 / 8 | chosen: tiles stretch to fill the row (4 per row at the default width) |
| `SidebarMetrics.addressFieldHeight` | 28 | chosen |
| `SidebarMetrics.footerHeight` | 40 | spec §F |
| `SidebarMetrics.audioIndicatorWidth`, `tileBadgeSize`/`Inset`, `footerButtonSize`, `chevronSize`, `popoverFieldWidth` | 22, 11/3, 28, 20, 280 | chosen |
| `Palette.accent` | `controlAccentColor` | changed dot, insertion line (spec §I.8, §A.9) |
| `Palette.letterTileColors` / `letterTileColor(for:)` | 10 system colours, FNV-1a of the domain | spec §I.2 (stable across launches) |
| `Motion.toastOut` | 0.2 s | spec §F |
| `Motion.renamePulseScale` | 0.98 | spec §I.9 |
| `Motion.clearStagger` / `clearStaggerMax` | 0.03 / 0.3 s | spec §A.7 (used in 2.2b) |
| `Motion.resetCrossfade` | 0.15 s | spec §A.5 |
| `Motion.reduceMotion` | `accessibilityDisplayShouldReduceMotion` | spec §I.1 |
| `Timing.toast` / `toastWithAction` / `undoToast` | 2 / 5 / 8 s | spec §F, §A.7 |
| `Timing.urlTooltipDelay` | 0.6 s | spec §C (app-wide `NSInitialToolTipDelay`) |

## Added in Phase 2.2b (drag and drop, keyboard, Clear, review polish)

| Token | Value | Provenance |
|---|---|---|
| `SidebarMetrics.headerTrailingInset` | 6 (`rowHorizontalInset`) | 2.2a review: the address field ends where the pill ends (was 16, the domain truncated) |
| `SidebarMetrics.addressFieldPadding` | 4 (`Spacing.xs`) | 2.2a review: padding around the site icon and domain trimmed from 8 |
| Essentials rows | rows = ceil(count / columns), tiles spread evenly | 2.2a review: five tiles are 3 + 2, never 4 + 1 |
| `SidebarMetrics.insertionLineWidth` | 2 | spec §A.9 (insertion line); also the drop-onto ring and the keyboard focus ring (§I.13) |
| `SidebarMetrics.dragLiftScale` / `dragShadowRadius` / `dragShadowOpacity` | 1.03 / 8 / 0.25 | spec §A.9 (scale 1.03, shadow); shadow values chosen |
| `SidebarMetrics.draggedRowAlpha` | 0.35 | chosen: rows being dragged stay in place, dimmed |
| `SidebarMetrics.overflowLineWidth` / `overflowHitHeight` | 2 / 10 | spec §I.11 (2 px line); hit height chosen |
| `SidebarMetrics.fullBadgeHeight` / `shakeDistance` | 16 / 6 | chosen ("12/12" badge, refused-drop shake, spec §A.9) |
| `SidebarMetrics.dragThreshold` | 3 | AppKit's own drag distance, for tiles |
| `Motion.shake` | 0.4 s | chosen (refused drop on a full grid) |
| `DropRules.edgeZone` / `holdDelay` | 0.2 / 0.5 s | spec §A.6 (20% edges reorder, middle 60% drops onto, 500 ms) |
| `Palette.sidebarMultiSelection` | accent α 0.18 | chosen: multi-selected rows and the drop-onto target |
| Clear stagger | step = min(30 ms, 300 ms / (rows − 1)) over the visible rows, 150 ms slide + fade each, ease-in | spec §A.7 (`Motion.clearStagger`, `clearStaggerMax`) |
| Folder preview | 280 pt wide (`popoverFieldWidth`), rows 28 pt, 8 visible | chosen; behaviour spec §A.6 |

## Added in Phase 2.3 (tabs, lifecycle, ⌃Tab switcher)

| Token | Value | Provenance |
|---|---|---|
| `Timing.discardIdleToday` / `discardIdlePermanent` | 60 min / 3 h | spec §H (idle discard: Today tabs, pinned entries and essentials) |
| `Timing.discardSweepInterval` | 60 s | chosen (how often the idle sweep runs) |
| Memory-pressure discard | warning: the older half of the eligible pages (rounded up); critical: all of them; least recently seen first | chosen; spec §H says LRU first, never the selected or an audible page |
| `Timing.tabSwitcherDelay` | 0.12 s | chosen: ⌃ held this long shows the list; a quicker ⌃Tab tap switches without it |
| `TabSwitcherMetrics.limit` | 5 | spec §G ("5 most recent") |
| `TabSwitcherMetrics.width` / `rowHeight` / `padding` | 340 / 36 / 8 | chosen; rows reuse the sidebar's favicon and title metrics; corner `Radius.large` on `NSGlassEffectView` |
| Switcher highlight | `Palette.sidebarMultiSelection` (accent α 0.18), corner `Radius.medium` | chosen: the sidebar's white selection pill does not read on light glass (2.3 capture) |
| Card empty state | "Press ⌘T to search or type a URL", `Typography.row`, `tertiaryLabelColor`, centred | spec §A.7 text; style chosen |

## Added in Phase 2.4a (palette)

| Token | Value | Provenance |
|---|---|---|
| `PaletteMetrics.width` | 640 | spec §C (Zen's floating urlbar) |
| `PaletteMetrics.topFraction` | 0.18 | spec §C: top edge 18% down the content area (the card) |
| `PaletteMetrics.windowMargin` | 16 | chosen: the panel narrows to stay this far from the window edges |
| `PaletteMetrics.fieldHeight` / `fieldInset` | 48 / 16 | chosen |
| `PaletteMetrics.rowHeight` / `iconSize` | 36 / 16 | the sidebar's row and favicon (measured from Dia) |
| `PaletteMetrics.listPadding` / `groupGap` | 6 / 4 | chosen: highlight inset like the sidebar pill; groups have no headers, a gap separates them |
| `PaletteMetrics.openScale` | 0.96, with a fade over `Motion.fast` (0.12 s); close fades over `Motion.fast` | spec §I.1; reduced motion: fade only |
| Panel | `NSGlassEffectView`, corner `Radius.large` | PLAN §2.4 overlays |
| Row highlight | `Palette.sidebarMultiSelection` (accent α 0.18), corner `Radius.medium` | as the ⌃Tab switcher (2.3) |
| Space chip | `Typography.secondary` on a `Palette.sidebarHover` capsule | chosen; spec §C names the chip |
| Docked (header-field click) | the panel's left edge on the address field's, centred on it vertically, never above `CardMetrics.inset` from the window top | chosen; spec §C "keeps the input docked in place" |
| `Typography.paletteField` | system 18 regular | chosen |
| `Timing.typedTextMemory` | 45 s | spec §C (Zen `wait-to-clear`) |
| `Symbol.openURL` | `globe` | the verbatim URL row |
| Max rows | 8 (`OmniboxResult.limit`) | spec §C |

## Added in Phase 2.4b (palette: history, commands, site search, suggest)

| Token | Value | Provenance |
|---|---|---|
| `Timing.suggestDebounce` | 0.12 s | ROADMAP 2.4 task 6 (120 ms); `macos-ui-stack.md` §5.2 (100–150 ms) |
| `SuggestClient.limit` | 5 suggestions | `macos-ui-stack.md` §5.2 ("cap at 5") |
| `PaletteMetrics.chipHeight` / `chipPadding` | 24 / 8 | chosen: the site-search chip left of the field (spec §C "chip on the left") |
| Site-search chip | `Typography.secondary` semibold on a `Palette.sidebarMultiSelection` capsule | chosen; the row highlight's accent tint marks the mode |
| `PaletteMetrics.deleteButtonSize` | 18 | chosen: the × on a history row (spec §C "hover shows an × on the right"), shown on hover or highlight |
| History frecency | half-life 30 days; visit weights typed 2, bookmark 1.5, link/other 1, generated/keyword/form 0.3, reload 0 | Firefox frecency (exponential decay, visit-type bonuses scaled to link = 1), `macos-ui-stack.md` §5.2 |
| Inline completion | a host or URL typed before, or visited 3 times | chosen, after Chromium's HistoryURL provider (inlines typed URLs) |
| `Symbol.appearance` | `circle.lefthalf.filled` | palette: Switch to Light/Dark/Auto Appearance |
| Commands outside `>` | 3 letters or more starting a word of the title, relevance 400–700 (always the last group) | chosen; spec §C group 6 |
