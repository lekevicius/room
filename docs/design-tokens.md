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
