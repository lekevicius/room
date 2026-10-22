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
| `CardMetrics.inset` | 8 | the Room Browser design (2026-10-07); Dia measured 6 |
| `CardMetrics.sidebarSideInset` | 0 | measured: the card butts against the sidebar |
| `CardMetrics.cornerRadius` | 6 (`Radius.small`) | the Room Browser design; Dia measured 10 |
| `CardMetrics.borderWidth` | 1 | measured: hairline composites above the page |
| `CardMetrics.shadowRadius` / `shadowOffset` | 3 / (0, −2) | the Room Browser design (`0 2 6` at 15%) |
| `CardMetrics.shadowOpacityLight` / `Dark` | 0.15 / 0.35 | measured (light); chosen (dark) |
| `SidebarMetrics.defaultWidth` | 300 | the Room Browser design (304 in its frame); spec §E said 240 |
| `SidebarMetrics.minWidth` / `maxWidth` | 180 / 500 | spec §E (Zen max 500) |
| `SidebarMetrics.snapCloseWidth` | 120 | spec §E |
| `SidebarMetrics.splitterHitWidth` | 8 | chosen |
| `SidebarMetrics.headerHeight` | 48 | the Room Browser design: the top bar; the address row starts at its bottom |
| `SidebarMetrics.headerLeadingGap` | 12 | measured (see `Spacing.m`); the optional toolbar |
| `SidebarMetrics.topBarLeadingGap` | 15 | the Room Browser design: the toggle at x 92 after lights ending at 77 |
| `SidebarMetrics.topBarButtonSize` / `topBarButtonMinSize` / `topBarGroupGap` / ~~`topBarSymbolSize`~~ | 32 / 24 / 4 / ~~13~~ | the Room Browser design (min chosen); since 5.2a `ControlMetrics` (B-110), the glyph `IconStyle.control`, the gap only after the toggle (B-125) |
| `SidebarMetrics.addressFieldHeight` / `addressFieldPadding` / `addressRowGap` | 36 / 10 / 8 | the Room Browser design |
| `SidebarMetrics.rowHorizontalInset` / `pillVerticalInset` / `faviconTitleGap` / `pillCornerRadius` / `titleFadeWidth` | 8 / 0 / 10 / 12 / 12 | the Room Browser design |
| `SidebarMetrics.pillShadowOpacity` / `pillShadowRadius` / `pillShadowOffset` | ~~0.15 / 1 / (0, −0.5)~~ 0.12 (dark 0.30) / 2 / (0, −1) | the Room Browser design (`0 0.5 2` at 15%), light only; B-112 (5.2a): `0 1 4` at 12%, dark too |
| `SidebarMetrics.essentialTileHeight` / `essentialIconSize` / `essentialHoverAlpha` | 40 / 16 / 0.5 | the Room Browser design |
| `SidebarMetrics.closeButtonSize` / `audioIndicatorWidth` / `rowButtonCornerRadius` / ~~`rowButtonSymbolSize`~~ | 24 / 24 / 4 / ~~10~~ | the Room Browser design; the glyph `IconStyle.rowButton` since 5.2a |
| `SidebarMetrics.edgeInset` | 16 | chosen (the top bar falls back to `rowHorizontalInset`, 8) |
| `SidebarMetrics.inactiveSaturation` / `inactiveContentAlpha` | 0.8 / 0.6 | spec §I.12 (desaturate 20%) |

## Reader page (4.7b)

The reader page (`App/Resources/Reader/reader.html`) takes its CSS variables from `ReaderStyle` (Chrome package), generated from these and the colours below; never literals in the template.

| Token | Value | Provenance |
|---|---|---|
| `ReaderMetrics.textSizes` | 16 / 19 / 23 px (Settings ▸ Appearance ▸ Reader text size: small, medium, large) | chosen |
| `ReaderMetrics.titleScale` / `headingScale` / `secondaryScale` | 1.6 / 1.25 / 0.8 em | chosen |
| `ReaderMetrics.lineHeight` | 1.55 | chosen |
| `ReaderMetrics.measure` | 34 em | chosen |
| `ReaderMetrics.pagePadding` / `blockGap` / `imageRadius` | 48 (`Spacing.l` × 3) / 12 (`Spacing.m`) / 6 (`Radius.small`) | chosen |
| `ReaderMetrics.minimumArticleCharacters` | 400 (below it: "No article found on this page") | chosen |
| Colours | `--room-background` = `Palette.cardBackground`; `--room-text`, `--room-secondary`, `--room-link`, `--room-separator` = `labelColor`, `secondaryLabelColor`, `linkColor`, `separatorColor`; each resolved in Aqua and Dark Aqua | tokens |

## Typography

| Token | Value | Provenance |
|---|---|---|
| `Typography.row` | system 13 regular | chosen (rows outside the sidebar) |
| `Typography.sidebarRow` | system 14 regular | the Room Browser design: sidebar rows and the address field |
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
| `Motion.standard` | 0.15 s | row insert/remove (§I.1); the reveal's dwell and grace are `Timing.revealDwell`/`revealGrace` |
| `Motion.medium` | 0.25 s | space switch slide, tint crossfade (§B); the sidebar's reveal moved to `Motion.revealIn`/`revealOut` (B-114, 5.1b) |
| `Motion.revealIn` / `revealOut` | 0.18 s ease-out / 0.15 s ease-in | the hidden sidebar's slide in and out (§E as amended by B-114, 5.1b) |
| `Motion.slow` | 0.35 s | Peek open (§I.1, §I.6) |
| ~~`Motion.pill`~~ | ~~spring 0.35 s, bounce 0.15~~ | removed with the Room Browser design (2026-10-07): a new selection switches the pill at once; the pill follows its own row while rows insert or leave, with the rows (`Motion.standard`, ease-out; 5.1a) |
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
| `SidebarMetrics.unreadDotSize` | 6, `Palette.accent`, at the row's trailing edge (a tile's top-left corner: the top-right holds the audio badge, the bottom-right the changed dot); hidden while the close button shows | spec §I.3 (5.6a) |
| `SidebarMetrics.customIconEmojiScale` | 0.82 of the favicon square (an SF Symbol: `IconStyle.rowGlyph`, `labelColor`) | chosen (5.6a) |
| `SidebarMetrics.unloadedIconAlpha` | 0.6 | spec §A.1 |
| `SidebarMetrics.separatorRowHeight` / `spaceTitleRowHeight` | 24 / 36 | chosen |
| `SidebarMetrics.essentialTileHeight` / `essentialIconSize` / `essentialTintAlpha` | 36 / 20 / 0.15 | spec §I.2 |
| `SidebarMetrics.essentialTileMinWidth` / `essentialMaxColumns` / `essentialsGap` | 48 / 6 / 8 | chosen: tiles stretch to fill the row (4 per row at the default width) |
| `SidebarMetrics.addressFieldHeight` | 28 | chosen |
| `SidebarMetrics.footerHeight` | 40 | spec §F |
| `SidebarMetrics.audioIndicatorWidth`, `tileBadgeSize`/`Inset`, `footerButtonSize`, `chevronSize`, `popoverFieldWidth` | 22, 11/3, ~~28~~ 32 (`ControlMetrics.size`, B-110), 20, 280 | chosen |
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

## Added in Phase 2.5 (spaces)

| Token | Value | Provenance |
|---|---|---|
| Space switch slide | both lists move by the list's width over `Motion.medium` (0.25 s), ease-out, as layer transforms on lists built ahead of time; Reduce Motion: a crossfade over the same time | spec §B, §I.1; Zen `switch-animation-duration=250` |
| Tint crossfade | `colors` of the tint gradient over `Motion.medium`, ease-in-out, alongside the slide | spec §B |
| Theme algorithms (`ThemePalette`) | the first well is the base; the algorithm fills empty wells at hue offsets from it: Complementary +180°; Split +150°, +210°; Analogous −30°, +30°; Triadic +120°, +240°; Floating none. A filled well always wins; 3 colours at most | spec §B (five algorithms, 1–3 colours); colour-wheel harmonies as Zen's gradient generator places its dots; the "fill empty wells" rule is ours |
| Tint gradient (`SpaceTintView`) | diagonal, top leading → bottom trailing, always 3 stops: one colour fades from its alpha to `tintOpacityRange.lowerBound`; two put their 50% blend in the middle; three as given | chosen; 3 stops so themes with different colour counts interpolate |
| Tint alpha | `ThemePalette.tintAlpha`: `themeOpacity` (0–1, default 0.5) mapped linearly into `Materials.tintOpacityRange` (0.10–0.25; 0.5 → 0.175) | chosen, within the Phase 1.6 range |
| Dark theme colours | lightness capped at 0.45 (`ThemePalette.darkMaxLightness`), hue and saturation kept | chosen: pastel themes washed out the dark material |
| `SpaceIconMetrics.size` / `pitch` / `dotSize` | 20 / ~~26~~ 32 (B-110: each icon a `ControlMetrics` square, its glyph 20) / 6 pt; icons shrink to fit between the footer buttons; in Design since 5.2a | chosen; Zen shrinks its strip on overflow |
| `SpaceIconMetrics.activeScale` | 1.15, animated over `Motion.medium` | spec §B |
| Active highlight | `Palette.sidebarHover` capsule 2 pt around the active icon (`indicatorPadding`), sliding over `Motion.medium` ease-out | spec §B "the active indicator slides"; colour chosen |
| `SpaceIconMetrics.inactiveAlpha` | 0.55 | chosen |
| Hover name | `Typography.secondary`, secondary label colour, right of the icon row, fades over `Motion.fast` | spec §B |
| `SpaceIconMetrics.reorderThreshold` | 5 pt of travel turns a press on an icon into a reorder drag, haptic `.alignment` per slot | Zen (>5 px) |
| Drop on a space icon | `Palette.sidebarMultiSelection` circle behind the icon; resting `DropRules.holdDelay` (0.5 s) switches to the space | spec §B / ROADMAP 2.5 task 5 (500 ms) |
| Swipe | 25% of the list width or a fling (progress + 0.5 × velocity in widths/s) switches; before the first space a rubber band bounded at 0.15 widths; past the last the new-space form (5.7b: a rubber band too, and a release past the threshold opens the space window for a new space); axis locks horizontal when the first movement is 1.5× more horizontal | spec §B, Zen (`threshold 0.25`, `velocity 0.5`); band limit and lock ratio chosen |
| ⌃ + wheel | one space per notch (down = next), 200 ms cooldown; trackpad ⌃-scroll counts 30 pt as a notch | Zen `scroll-modifier-key`, cooldown 200 ms; trackpad step chosen |
| `SpaceFormMetrics.padding` / `iconCell` / `previewHeight` | 12 / 26 / 18 pt | chosen |
| Space form icons | 24 SF Symbols and 24 emoji, any emoji typed in its field | chosen |
| `SpaceFormMetrics.iconPopoverWidth` | 6 cells + 5 gaps + padding + 24 (Change Icon… for entries and folders, 5.6a: the same picker) | chosen |
| `Symbol.more` on the space title row | "…" on hover, left of the chevron | spec §B |

## Added in Phase 2.6a (palette rows on AppKit, the page's prompts)

| Token | Value | Provenance |
|---|---|---|
| Palette rows (`PaletteRowView`) | AppKit, one reusable view per slot (8); the 2.4b row unchanged: 16 pt icon, 8 pt gaps (`faviconTitleGap + 2`), title and detail in one tail-truncated line (`Typography.row`, detail secondary label colour after two spaces), a spacer of at least 8 pt, space chip (`Typography.secondary`, capsule `Palette.sidebarHover`, 6 × 2 pt padding), hint on the highlighted row, × 10 pt semibold in `PaletteMetrics.deleteButtonSize`; highlight pill `Palette.sidebarMultiSelection`, `Radius.medium`, continuous corners | 2.4b SwiftUI row, PLAN §4 (rows on AppKit) |
| `Timing.paletteContextDelay` | 0.03 s: the palette's sidebar snapshot is built this long after it opens | chosen: after the open's first frame (≤ 16.7 ms plus the turn at 60 Hz), before a person's first keystroke |
| Dialog sheet (`PromptMetrics.dialogWidth` / `dialogTopInset` / `dialogPadding` / `dialogSpacing`) | 420 / 32 / 20 / 12 pt: an `NSGlassEffectView` panel (`Radius.large`) hanging below the card's top edge, centred; title 13 pt semibold ("example.com says", "Leave this site?", "Sign in to …"), message `Typography.row`, notes `Typography.secondary` secondary colour, push buttons right-aligned (primary Return, Cancel Esc); a message over 600 characters scrolls at `messageMaxHeight` 240 pt | chosen; wording after Chrome's tab-modal dialogs |
| Page dim under a dialog | black at `dimAlphaLight` 0.18 / `dimAlphaDark` 0.35; the dialog fades in over `Motion.fast` (none under Reduce Motion) | chosen |
| Certificate interstitial | the card's background (`Palette.cardBackground`), a 520 pt column 120 pt from the top: `Symbol.siteInsecure` 44 pt system red, title 24 pt semibold "This Connection Is Not Private", 14 pt secondary text, the error code 11 pt monospaced, Go Back (default) and Show Details; Visit … Anyway (destructive push button) only behind Show Details and only when the error can be bypassed | chosen; ROADMAP 2.6 "our page" |
| Permission popover | `NSPopover` (transient) on the header's site button (the card's top-left corner without a header), 360 pt wide (`permissionWidth`): "“host” wants to", a row per permission (SF Symbol + Chrome's phrase), Don't Allow · Allow This Time (camera, microphone, location only) · Allow (Return) | Chrome's permission prompt; width chosen so three buttons fit |
| Context menu | Room's items first (Open Link in New Tab, Open Link in Peek (disabled until 2.7), Copy Link; Open Image in New Tab, Copy Image Address), a separator, then the engine's items | ROADMAP 2.6 task 2; Chrome's order |

## Added in Phase 2.6b (downloads, find, zoom, status pill, site panel, DevTools, page states)

| Token | Value | Provenance |
|---|---|---|
| Downloads button (`DownloadsButton`, `DownloadsMetrics`) | the footer's 28 pt button: `Symbol.downloads` 14 pt; while downloading `Symbol.downloadInProgress` 11 pt inside a 2 pt ring (`ringWidth`, `ringInset` 4), track `tertiaryLabelColor`, progress `controlAccentColor` from 12 o'clock clockwise; a quarter arc spinning once a second while a size is unknown; badge 13 pt capsule (`badgeHeight`) in the accent colour, 9 pt semibold white count, top-right | spec §F (ring, bounce, badge); sizes chosen |
| Download bounce | `Motion.toast` spring on the button's scale from 1.3 (`bounceScale`) to 1; Reduce Motion: an opacity pulse 0.4 → 1 over `Motion.medium` | spec §F (spring, 0.5 s); start scale chosen |
| Download fly-in (`DownloadFlyIn`) | the page's favicon (else the generic file icon) at 32 pt (`flyIconSize`) from the click that started the download (within 3 s, `clickMemory`; else the card's centre) to the button on a quadratic arc whose top is min(2 × distance, 1200) pt above the higher end but inside the window, scale 1 → 0.45, ease-in-out over 1 s, fading over the last 15%; none under Reduce Motion | spec §F / Zen (1000 ms, end scale 0.45, arc 2× distance capped 1200); the apex held inside the window and the fade chosen |
| Downloads popover | `NSPopover` (transient) above the button, 320 pt (`popoverWidth`); header "Downloads" + Clear (link button); rows 32 pt file icon (60% while not finished), name (middle-truncated, `Typography.row`), a small linear progress bar while downloading, the detail line (`Typography.secondary`: "1 MB of 5 MB — 1 MB/s, 4 s left", the size, Cancelled, Failed), × while downloading, Resume when interrupted and resumable, Show in Finder on hover when done; hover `Palette.sidebarHover` with `Radius.small`; up to 6 rows (`maxVisibleRows`) then scrolls; "No downloads" when empty | spec §F; macos-ui-stack §8 (SwiftUI rows in an `NSPopover`) |
| Download file names (`DownloadRules`) | `/`, `\` and `:` become "-", control characters and leading dots go, at most 255 bytes, empty is "download"; a taken name becomes "name (1).ext", "(2)" … (compound extensions such as .tar.gz kept whole); names of downloads still in progress count as taken | Chrome's numbering; sanitising chosen |
| Find bar (`FindMetrics`) | 320 × 36 pt (`width`, `height`) `NSGlassEffectView` (`Radius.large`) 8 pt (`inset`) from the card's top and trailing edges; search icon 12 pt, field `Typography.row` with "Find in page", the count in 11 pt monospaced digits (`FindRules`: "3 of 12", "No results"), ˄ ˅ and × as 22 pt borderless buttons | spec §C (top-right, "3 of 12"); sizes chosen |
| Zoom (`ZoomRules`, `ZoomIndicator`) | Chrome's presets 25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500%; the indicator is a 36 pt glass capsule at the card's top-right (under the find bar when it shows): − · "110%" (13 pt medium, monospaced digits) · + · Reset (small push button, disabled at 100%); it leaves 1.5 s (`Timing.zoomIndicator`) after the last change unless the pointer is on it | Chrome `zoom::kPresetZoomFactors`; indicator chosen (ROADMAP 2.6 "transient zoom indicator") |
| Status pill (`StatusPillState`, `StatusPillMetrics`) | 22 pt tall (`height`), 4 pt (`inset`) from the card's bottom and side edges, 8 pt padding, `Typography.secondary` in the secondary label colour, middle-truncated, on a tooltip material with `Radius.small` and a 0.5 pt separator-colour border; shows after 0.6 s (`Timing.statusPillDelay`), standard width a third of the card (at least 200 pt, `minWidth`), the full URL up to the card's width after 1.5 s (`Timing.statusPillExpand`); link to link updates at once; hides 0.1 s (`Timing.statusPillHideGrace`) after the pointer leaves the link; moves to the bottom-right while the pointer is within 24 pt (`dodgeDistance`) of it; never takes the mouse | spec §I.14 (600 ms, 1.5 s, dodges the cursor); Chrome's standard bubble width (a third); the rest chosen |
| Site panel (`SitePanelMetrics`, `SitePanelRules`) | `NSPopover` (transient) on the header's site button (the card's top-left corner without a header), 360 pt (`width`, as the permission popover): host (headline), the connection line with its symbol (red when not secure), "Permissions": Location, Camera, Microphone, Notifications always, then any permission the site has a setting for, each a menu (Ask / Allow / Block, "(default)" on the default; Allow / Block for pop-ups, sound, JavaScript, images, sensors), Reset Permissions (when anything is stored), "Cookies and site data" · Clear… (with a confirmation), "Reload to apply the changes" · Reload | ROADMAP 2.6 task 3; Chromium's per-type defaults; layout chosen |
| Crashed-page view | as the certificate interstitial: the card's background, a 520 pt column 120 pt from the top, `Symbol.pageCrashed` 44 pt in the secondary label colour, 24 pt semibold title ("This Page Crashed", "… Ran Out of Memory", "… Was Stopped", "… Couldn’t Start"), 14 pt secondary text, the result code 11 pt monospaced, Reload (default) | ROADMAP 2.6 exit (processGone); Chrome's sad tab in Room's words |
| Element fullscreen | the card fills the window edge to edge (no inset, corner, border or shadow), the sidebar hidden, the window fullscreen while the page is | `cef_display_handler.h` (the client makes the window fullscreen) |
| DevTools pane (`DevToolsMetrics`) | 42% of the card when first opened (`defaultFraction`, Phase 1.4); a divider with an 8 pt drag area (`dividerHitHeight`) around a 1 pt `separatorColor` line, the up-down resize cursor; neither the page nor the pane under 120 pt (`minPageHeight`, `minPaneHeight`); the share is remembered (`RoomDevToolsFraction`), double-click restores the default | ROADMAP 2.6 task 4; minimums chosen |
| `Symbol.pageCrashed` / `findPrevious` / `findNext` / `dismiss` / `file` | `exclamationmark.octagon` / `chevron.up` / `chevron.down` / `xmark.circle.fill` / `doc` | chosen |

## Added in Phase 2.7a (hide/reveal, the traffic-light cluster, the toolbar, Peek)

| Token | Value | Provenance |
|---|---|---|
| `RevealMetrics.edgeBand` | 4 pt at the window's leading edge | spec §E (4 px) |
| `Timing.revealDwell` / `revealGrace` | ~~0.15~~ **0.06** (B-114, 5.1b) / 0.15 s | spec §E (150 ms dwell; Zen `sidebar-keep-hover.duration` 150 ms); the dwell shortened 2026-10-21 (B-114) |
| `RevealMetrics.outsideToleranceX` / `Y` | 200 / 100 pt around the overlay, pointer outside the window | spec §E (Zen `outside-window-edge-offset`) |
| `RevealMetrics.overlayInset` | 10 pt from the top, leading and bottom edges | spec §E (Zen `--zen-compact-float`) |
| Overlay slide | ~~`Motion.medium` (0.25 s)~~ `Motion.revealIn` (0.18 s) ease-out in, `Motion.revealOut` (0.15 s) ease-in out, fully off the leading edge; Reduce Motion: a fade | spec §E (250 ms); shortened by B-114 (5.1b) |
| `RevealMetrics.overlayCornerRadius` | `Radius.large` (12) on `NSGlassEffectView` | chosen (the overlays' radius) |
| Overlay wash (`overlayTintWhiteLight` / `Dark`, `overlayTintAlpha`) | white 0.88 / 0.16 at α 0.75 inside the glass | chosen: untinted glass let page text read through the rows; the glass's own `tintColor` rendered near white and hid the white selection pill (2.7a captures) |
| Overlay header | Back, Forward, Reload (`navigationButtonSize` 28) beside the traffic lights; the address field on its own row below, `addressRowGap` 4 | spec §E ("present in the revealed overlay header"); layout chosen (Arc's two rows) |
| ~~`ClusterMetrics.height`~~ | ~~38 pt glass pill centred on the window's own buttons~~ | removed by B-114 (5.1b, 2026-10-21): no floating traffic-light pill |
| ~~`ClusterMetrics.horizontalPadding`~~ | ~~12 pt beside the outer buttons (pill 84 × 38 around 60 × 14 buttons)~~ | removed by B-114 (5.1b, 2026-10-21): no floating traffic-light pill |
| ~~`Timing.clusterFade`~~ | ~~2 s after the pointer was last within `ClusterMetrics.nearDistance` (60 pt) of the pill; fades with the buttons over `Motion.standard`, back over `Motion.fast`~~ | removed by B-114 (5.1b, 2026-10-21): no floating traffic-light pill |
| ~~Cluster wash~~ | ~~the overlay's wash inside the pill's glass~~ | removed by B-114 (5.1b, 2026-10-21): no floating traffic-light pill |
| `ToolbarMetrics.height` / `buttonSize` / `padding` / `urlHeight` | 36 / 28 / 6 / 26 pt; the bar sits in the card's top on the page's fill, its content centred on the traffic lights' line when they sit in it | spec §E (36 px); the rest chosen |
| Toolbar and Peek header appearance | Aqua on a light page fill, Dark Aqua on a dark one (relative luminance > 0.5) | chosen (2.7a dark captures) |
| `PeekMetrics.sizeFraction` / `cornerRadius` / `dimAlpha` | 86% of the content area (the page card), 24 pt corners, black at 30% over the card | spec §I.6 |
| `PeekMetrics.headerHeight` / `headerButtonSize` / `headerPadding` | 40 / 28 / 10 pt: the domain (`Typography.spaceTitle`, secondary), Open as Tab (`Symbol.peekExpand`), Split (`Symbol.peekSplit`, disabled until 2.7b), × | chosen; contents spec §I.6 |
| Peek shadow (`shadowRadius`, `shadowOpacityLight` / `Dark`) | 24 pt, 0.25 / 0.5, offset 8 pt down | chosen (floats above the page card) |
| Peek open | scales up from 10% (`openStartScale`) centred on the last click (within 2 s; else the card's centre) to the card, `CASpringAnimation` perceptual `Motion.slow` (0.35 s), bounce 0; the dim fades in over `Motion.fast`; close fades over `Motion.fast`; Reduce Motion: fades | spec §I.1 ("scale from the link's rect … 350 ms"; CEF gives no link rect) |
| `Timing.peekGestureWindow` | 2 s: `window.location` set this soon after a gesture navigates in place | spec §A.4 |

## Added in Phase 2.7b (split view)

| Token | Value | Provenance |
|---|---|---|
| `SplitRules.maxPanes` | 4 panes; a fifth is refused with the toast "Can't add more panes to the split view" | spec §D (Arc, Zen `MAX_TABS`) |
| Layouts | `hbox` side by side, `vbox` stacked, `grid` two columns over two rows (three panes: the third spans the bottom row; two panes: a row); ratios per pane (`hbox`/`vbox`) or two column + two row fractions (grid); a new layout starts equal | spec §D; grid shape chosen (Zen "3–4 = paired columns") |
| `SplitMetrics.dividerWidth` / `resizerHitWidth` | ~~1 pt line between panes (separator colour), 7 pt hit area centred on it~~ since B-113 (5.2a) no line: `paneGap` 8 between pane cards, the hit area the gap + 1 pt each side (10); `dividerWidth` stays the sidebar group row's segment line; double-click equalises | spec §D |
| `SplitMetrics.minimumPaneFraction` / `minimumPaneLength` | a pane never gets under 7% of the split along the dragged axis, nor under 120 pt while the split has room (never more than an equal share) | Zen `min-resize-width` 7 percent; 120 pt chosen (as `DevToolsMetrics.minPaneHeight`) |
| `SplitMetrics.paneHeaderHeight` / `paneHeaderRevealBand` / `paneHeaderButtonSize`, `Timing.paneHeaderHideDelay` | 24 pt header over the pane's top (domain, grip, layout menu, ×) while the pointer is within 36 pt of the top; buttons 20 pt; hides 0.3 s after the pointer leaves; `.headerView` material, the appearance that reads on the page's fill | spec §D (24 px strip); band, buttons, delay chosen |
| `SplitMetrics.dropEdgeBand` / `dropPreviewFraction` / `dropPreviewAlpha` | an entry dragged into the card: within 40 pt of a pane's edge it splits to that side (the nearest edge in a corner), elsewhere it replaces the pane; the preview covers the half the new pane gets, accent at 18% with a 2 pt accent border, 10 pt corners | spec §D (40 px band); preview chosen |
| `Timing.splitJoinDwell` (= `DropRules.holdDelay`) | a single entry resting 500 ms on a tab row's middle 60% joins it into a split (a pinned entry onto a pinned entry still makes a folder, §A.6) | spec §D, §A.6 |
| `SplitMetrics.segmentTitleMinWidth` / `focusedSegmentAlpha` | the group row's segments show a title when at least 64 pt wide (else the favicon alone); the focused pane's segment is tinted with the accent at 16% | spec §D ("tinted"); values chosen |

## Added in Phase 2.8a (menus, Settings v0; the sidebar on the right until 5.7a)

| Token | Value | Provenance |
|---|---|---|
| Settings window | toolbar tabs (`NSTabViewController.tabStyle = .toolbar`, `toolbarStyle = .preference`), sections General, Appearance, Search, Downloads; each a grouped SwiftUI `Form` 480 pt wide at its own height; the title follows the section | the Mac's settings windows; width chosen (460 in 2.4b, wider for the segmented pickers) |
| Settings section symbols | `gearshape` / `paintpalette` / `magnifyingglass` / `arrow.down.circle` | chosen (system settings conventions) |
| ~~Sidebar on the right~~ | removed in 5.7a (B-120: Room will never offer it): the setting, the mirrored layout, the right-edge reveal band and overlay, and their tests | the user, 2026-10-21 |
| Planned menu items | present, disabled, tooltip "Comes in Chapter N"; keys the menu cannot carry (Esc, Return) named in the tooltip | ROADMAP 2.8 task 1 |

## Added in Phase 2.8b (the first-run card, Settings ▸ Privacy)

| Token | Value | Provenance |
|---|---|---|
| ~~First-run card (`FirstRunCardView`)~~ (removed in 5.7b: onboarding's window, below) | in the sidebar above the footer (`SidebarBodyView.accessoryView`), the rows' width (6 pt inset each side); fill `Palette.sidebarSelection`, corner `FirstRunMetrics.cornerRadius` = `Radius.medium` (10, the selection pill's), continuous; shadow `Palette.cardShadow` at 0.08, radius 3, 1 pt down | `macos-ui-stack.md` §7.4 ("an in-sidebar card, never a modal"); look chosen: one of the sidebar's own surfaces |
| ~~`FirstRunMetrics.padding` / `rowSpacing`~~ | ~~12 / 8 pt~~ (removed in 5.7b) | chosen (the overlays' 12 pt) |
| ~~`FirstRunMetrics.gapAboveFooter` / `gapAboveList`~~ | ~~4 / 8 pt~~ (removed in 5.7b with `SidebarBodyView.accessoryView`) | chosen |
| Card content | SwiftUI leaf, `.controlSize(.small)`: title `.headline`, caption `.caption` secondary; Search with (menu picker), Make Room Your Default Browser (or a check and "Room is your default browser"), two checkboxes with a one-line note, Done trailing (no default-button key: Return belongs to the fields) | chosen |
| Card dismissal | fades out over `Motion.fast` (0.12 s), then the list takes the space | chosen |
| Settings ▸ Privacy | symbol `hand.raised`; "Send crash reports", "Check for updates automatically", Check Now beside the version | chosen (system settings conventions) |

## Added in Phase 4.1a (the Library, the archive sweep)

| Token | Value | Provenance |
|---|---|---|
| `LibraryMetrics.searchFieldHeight` | 28 pt (`SidebarMetrics.addressFieldHeight`) | chosen: the header's field |
| `LibraryMetrics.sectionRowHeight` / `dayRowHeight` / `itemRowHeight` | 28 / 22 / 36 pt (`SidebarMetrics.rowHeight`) | chosen |
| `LibraryMetrics.buttonSize` | 20 pt (Restore, Show in Finder, ×) | chosen |
| `LibraryMetrics.chipHeight` / `chipPadding` | 16 pt / `Spacing.xs`; fill `Palette.sidebarHover` | chosen (the palette's space chip) |
| `LibraryMetrics.historyDays` / `historyLimit` / `searchLimit` | 7 days / 500 URLs / 200 matches | chosen |
| `Timing.archiveSweepInterval` | 10 min | spec §A.7 |
| `Timing.archiveIdleAfter` | 60 s without a key or mouse press in Room | chosen (4.1a's idle definition) |
| Library section chevron | `Symbol.disclosure` open, `chevron.right` collapsed | chosen |

## Added in Phase 4.1b (backups, the Archive's retention, crash recovery)

| Token | Value | Provenance |
|---|---|---|
| `Timing.backupInterval` | 30 min: a rolling backup at launch and then this often, each only when the state changed since the last | spec §H (rolling backups); interval chosen (ROADMAP 4.1b) |
| `Retention.backupsToday` / `backupDays` / `backupWeeksSpanDays` / `backupMonthsSpanDays` | 10 of today / one a day for 10 days / one a week back 31 days / one a month back 365 days | spec §H (Arc's schedule) |
| `Retention.archiveRows` | 30 days: older Archive rows are pruned at the sweep | B-80 (the planner's provisional number; no setting) |
| `Retention.archiveNavigationState` | 7 days: older Archive rows keep their URL, not their back/forward list | B-80 (provisional; no setting) |
| Restore Sidebar… sheet | SwiftUI leaf: a list of the backups (date, entries, spaces, Archive rows; "before restore" marked), Cancel, Restore (default) | chosen |
| Crash toast | "Room restarted after a crash" (`Timing.toast`) once, the card's empty state in place of the selected page | spec §H; ROADMAP 4.1b task 7 |

## Added in Phase 4.2 (space routing)

| Token / surface | Value | Source |
|---|---|---|
| Routing toast | `Symbol.routing`, "Opened in {space}" with the button "Switch" (`Timing.toastWithAction`, 5 s), id `routed` (a newer one replaces it) | spec §B, §F |
| Routing sheet (`RoutingSheetMetrics.width` / `height`) | 560 × 520 pt: a SwiftUI leaf in an `NSHostingController` as a sheet on the browser window (or the Settings window when opened from there): the explanation, the rules list (enabled checkbox, number, "URL contains" / "Domain is" / "URL matches regex", pattern, "→ space", move up and down, edit, remove; a disabled rule at 50 % opacity), Add Rule, the editor box (kind popup, pattern field, "Open in" popup, Cancel, Save; the pattern's refusal inline in system red), "Try a URL" with its answer, Done | chosen; looks are Chapter 5's |
| Menu items | "Space Routing Settings…" (space menu), "Add Route for Domain…" (Today and pinned tab menus), both with `Symbol.routing` | spec §B (title case as the other menu items) |

## Added in Phase 4.3a (import)

| Token / surface | Value | Source |
|---|---|---|
| Import sheet (`ImportSheetMetrics.width` / `height`) | 580 × 640 pt: a SwiftUI leaf in an `NSHostingController` as a sheet on the browser window: the title, the sources list (130 pt; a fixture or chosen source on top, detected installs by name, a note line under Firefox), "Choose a File or Folder…", "From profile" (Chromium profiles by `Local State`'s names), a progress bar with the step while reading or importing, the Import box (checkbox rows with the readers' counts in secondary text; Passwords and Extensions disabled with their 4.3b lines), the Where box (Bookmarks: Into one space / One space per folder; "Bookmarks bar into Essentials (up to 12)"; Space: New space named "{source}" or an existing one; Into profile), the preview line and its notes in caption secondary, a Skipped disclosure (80 pt scroll), Cancel and Import (default) or the summary and Done | chosen; looks are Chapter 5's |
| Import toast | `Symbol.importData` (`square.and.arrow.down.on.square`), "Imported from {source}: …" with the counts, id `imported`, `Timing.toast` | spec §F |
| Palette command | "Import from another browser…" with `Symbol.importData` | ROADMAP 4.3a |

## Added in Phase 4.4a (Settings: shortcuts, general, search, downloads)

| Token / surface | Value | Source |
|---|---|---|
| Settings window width | 560 pt for every section (`ShortcutsSettingsMetrics.width`; 480 since 2.8a): the eight sections (General, Appearance, Search, Downloads, Shortcuts, Spaces, Extensions, Privacy) fit the toolbar without its overflow menu | chosen (measured: at 480 pt Extensions and Privacy went behind ») |
| Settings ▸ Shortcuts | symbol `keyboard`; an AppKit `NSTableView` (`.inset`, alternating rows, no selection): Action (title, ◆ before a reserved one, the menu path under it in `Typography.secondary`), Shortcut (a small push button showing the key, "Type shortcut…" while recording, "—" for none), a reset arrow (`arrow.uturn.backward`) while overridden; the rows of a conflict in `systemOrange`; a line under the table with the prompt ("⌘P is Print…'s shortcut. Use it for Pin Tab instead?", Use for …, Cancel) or the refusal in `systemRed`; Reset All bottom right | PLAN §4 UI framework (rows that change per keystroke are AppKit); looks are Chapter 5's |
| `ShortcutsSettingsMetrics.tableHeight` / `keyColumnWidth` / `resetColumnWidth` / `rowHeight` | 380 / 120 / 28 / 34 pt; the section is 510 pt tall and sizes the window to itself | chosen |
| Settings ▸ General | Tabs gains "⌘W on a pinned tab or Essential" (spec §A.3's six, the chosen one's line under it); a Window section (Show the toolbar, Sidebar Left/Right; both gone from Settings in 5.7a) | ROADMAP 4.4a task 2 |
| Settings ▸ Search | Default (an engine popup per profile), Search engines (name, keyword in monospaced secondary, the URL with %s in caption; Edit, Remove as link buttons, Remove disabled with its reason as help; an inline editor with Name, Keyword, Search URL, Suggestions URL, the refusal in red, Cancel, Save), the suggestions switch with B-64's line | ROADMAP 4.4a task 3 |
| Settings ▸ Downloads | "Ask where to save each download" (a save panel as a sheet on the browser window, the folder's name proposed), "PDFs: Open in Room / Download" with "Applies from Phase 4.7" | ROADMAP 4.4a task 4 |


## Added in Phase 4.8a (several windows)

| Token / surface | Value | Source |
|---|---|---|
| `WindowMetrics.cascadeOffset` | 22 pt: ⌘N's window and "Open in New Window"'s sit this far right of and below the key (source) window, kept on its screen (`DragOutRule.cascaded`) | AppKit's `cascadeTopLeft` step; chosen |
| `WindowMetrics.dragOutDistance` | 40 pt: a sidebar entry dragged and released this far outside its window's frame (no drop target took it) opens in a new window whose top-left corner is the drop point, kept on the screen (`DragOutRule`) | spec §A.9 |
| "Open in New Window" | `Symbol.newWindow` (`macwindow.badge.plus`) in the Today, pinned and Essentials menus, after Duplicate (Today, pinned) or the Pinned URL submenu (Essentials); disabled without a URL | ROADMAP 4.8a task 4 |
| A new window | the key window's sidebar width and visibility, its active space, an empty Today list (the card's empty state), the same layout as the first (traffic lights where AppKit puts them) | spec §J |

## Added in Phase 4.9 (the long tail)

| Token | Value | Provenance |
|---|---|---|
| `Retention.screenshotsAge` / `screenshotsKept` | 7 days / the newest 50: ⇧⌘2's Open as Tab files in `<state>/Screenshots/` beyond either are deleted at launch (`ScreenshotRules.pruned`) | B-92 (the planner's rule, 2026-10-07; no setting) |

## Added in Phase 5.1a (the sidebar's motion audited)

Measured by `-RoomSpike motion` (`scripts/motion-check.sh`; `research/notes/spike-results.md` "Phase 5.1"), which reads every animation back from the window's layers.

| Token / animation | Value | Provenance |
|---|---|---|
| `Motion.renamePulse` | 0.3 s (2 × `standard`), keyframes 1 → `renamePulseScale` → 1, linear | spec §I.9 gives no length; the 2.2a value made a token |
| `Motion.preferences` / `MotionPreferences` | `.system` (`accessibilityDisplayShouldReduceMotion`); `.fixed(reduceMotion:)` for tests and DEBUG's `-RoomReduceMotion YES\|NO` | spec §I.1 (the injected seam); `Motion.reduceMotion` reads it |
| `MotionVariant` | `full`, `crossfade`, `instant` | spec §I.1 ("crossfade instead") |
| `SidebarMotion` | each sidebar animation's case and its Reduce Motion variant: instant for the pill, rows and folders, the footer's indicator and reorder, the grid's reflow, the pulse, scrolling, the ring, the equaliser, the folder preview; crossfade for the space slide, the space name, the tiles' fades, the shake (a flash), the changed dot, the reset-icon swap, the reset crossfade, Clear (a fade) | spec §I.1; chosen per animation (movement goes, fades stay) |
| Essentials reflow | the tiles on screen move to their new frames over `Motion.standard`, ease-out; the list under the grid moves with them when the grid gains or loses a row (a position animation from its old place); a new tile fades in at its place, a removed one fades out, both `Motion.standard` ease-out (were the default curve) | spec §I.1 (the rows' insert and remove); before 5.1a the tiles snapped and only their selection layer slid (Core Animation's implicit 0.25 s) |
| Changed dot | fades in over `Motion.fast` when the page leaves the pinned URL (row and tile); on reset it goes with the favicon's `Motion.resetCrossfade` | spec §I.8; hover fades `Motion.fast`; before 5.1a an implicit 0.25 s fade |
| Reset-icon swap | the favicon and the reset icon crossfade over `Motion.fast` on hover in and out (the row's or tile's other hover changes with them) | spec §I.4, §I.8; hover fades `Motion.fast`; before 5.1a instant |
| `CALayer.noImplicitActions` | plain sublayers (the changed dot, the loading ring, the tile's multi-selection layer, the drop slot's border, the overflow line, the split row's tint and dividers) never animate on their own | 5.1a: Core Animation's implicit 0.25 s default was on no token |

## Added in Phase 5.1b (the overlays' motion, hover and press, the reveal)

Measured by `-RoomSpike motion -RoomSpikeOnly overlays` (`scripts/motion-check.sh`; `spike-results.md` "Phase 5.1" 5.1b), read back from the window's layers.

| Token / animation | Value | Provenance |
|---|---|---|
| `ControlFeedback`, `ControlMotion` | one hover and press style for the chrome's controls (Design): `HoverButton` (the top bar, the address field's buttons, New Tab, the media row, the find bar, Peek's and a pane's header) and the downloads button and the space icons directly | B-111 (the user, 2026-10-21: "as Arc's") |
| Hover | the layer's fill fades to `Palette.sidebarHover` over `Motion.fast`, ease-out, and back; space icons brighten from `SpaceIconMetrics.inactiveAlpha` to 1 instead | spec §I.4 (hover fill 6%, fades `Motion.fast`) |
| `Palette.addressFieldHover` | 10% label colour (light and dark): the address field's fill under the pointer, from its resting `sidebarHover` 6% | chosen (B-111) |
| `Motion.pressScale` / `pressIn` | 0.9 about the control's centre over 0.08 s, ease-out, held while pressed (an animation only: the layer's model transform stays identity) | chosen (B-111, Arc's press) |
| `Motion.pressRelease` | spring 0.3 s, bounce 0.35 (settles in 0.553 s) | chosen (B-111) |
| `Motion.pressReducedAlpha` | 0.6: under Reduce Motion a press dims the control over `Motion.fast` and back, no scale | spec §I.1 |
| `Motion.toastInOffset` / `toastInScale` / `toastOutScale` | 12 pt, 0.9 / 0.95 (the 2.2a values made tokens) | spec §F (spring in, fade + scale out) |
| `Motion.toastPopScale` / `toastPopUp` / `toastPopDown` | 1.06 over 0.12 s, back over 0.25 s (spring keyframes; the 2.2a values) | spec §F ("replaces with a pop") |
| `DownloadsMetrics.bounceReducedAlpha` | 0.4 (the Reduce Motion bounce's start, was a literal) | spec §F, §I.1 |
| Download bounce | now a `transform` spring about the centre (`ControlFeedback.centredScale`), no longer moving the layer's anchor point | 5.1b |
| Download ring | grows to the new progress over `Motion.medium`, ease-out (was Core Animation's implicit 0.25 s); the spinner stops under Reduce Motion | 5.1b |
| ⌃Tab switcher | fades in over `Motion.fast`, ease-out (an explicit animation; it goes at once) | chosen: the spec gives the switcher none; as the palette's fade |
| `ChromeMotion`, `PaletteMotion`, `TabsMotion`, `CardMotion`, `WindowMotion` | each package's animations and their Reduce Motion variants (the pattern of `SidebarMotion`): toasts in and out fade, the pop, the fly-in, the ring and the popovers' animation end at once, the bounce fades; the palette's open loses its scale, its close stays a fade (was instant); Peek opens and closes by fades; the pane header stays a fade, the drop preview jumps; the split's layout never animates; the reveal fades; the traffic lights, the tint and the inactive fade stay fades | spec §I.1 |
| Traffic lights with the hidden sidebar | hidden with it; fade in over `Motion.revealIn` ease-in as the overlay slides in under them, out over `revealOut` with it, over `Motion.fast` on ⌘S; never moved | B-114 (amends spec §E) |

## Added in Phase 5.2a (the visual audit: the matrix, token drift, hairlines, icon weights, B-110, B-112, B-113, B-115, B-125)

The matrix (`-RoomSpike matrix`, `scripts/visual-matrix.sh`) shoots every surface light/dark × active/inactive into `research/screenshots/phase-5.2/` (one sheet per surface, the tokens printed on it). `scripts/design-audit.sh` lists literal type and symbol sizes, colours and radii outside Design: 52 before this session, 0 undeclared after (one declared, below); it runs in the CI workflow with `--strict`.

| Token | Value | Provenance |
|---|---|---|
| `ControlMetrics.size` / `minSize` / `groupGap` / `cornerRadius` | 32 / 24 / 4 / 6 (`Radius.small`) | B-110: one metric for the top bar's and the footer's buttons (the Room Browser design's top bar); `topBarButtonSize`, `footerButtonSize` and `SpaceIconMetrics.pitch` read it |
| Footer layout | downloads and New Tab 32 pt squares `rowHorizontalInset` (8) from the edges (were 28 at 12), their glyphs `IconStyle.control` 13 (were 14); the ring 20 pt across (`DownloadsMetrics.ringInset` 6, was 4 in 28) | B-110 |
| Space icons | a 32 pt square each (the hit area and the hover fill), the glyph 20 pt in it; hover: the buttons' fill and the brightening (`ControlFeedback.Hover.fillAndBrighten`); the active circle stays around the glyph | B-110 |
| Top bar extensions | the strip runs from `topBarGroupGap` after the toggle to Back (no gap before Back): 66 pt at the default 300 pt sidebar with macOS 27's traffic lights (they end at x 79, not the design's 77), two pinned buttons; was 62 and one | B-125 (decided: two fit at the default width, as `SidebarMetrics.defaultWidth`'s note says) |
| Overflow button | "…" (`Symbol.more`) since `beea283` (2026-10-07); an icon-less action keeps the puzzle piece (`IconStyle.controlSmall`) | B-89 (already in place; shown in `phase-5.2-extensions.png`) |
| `SidebarMetrics.pillShadowOpacity` / `pillShadowOpacityDark` / `pillShadowRadius` / `pillShadowOffset` | 0.12 / 0.30 / 2 / (0, −1): `0 1 4`; the selected Essentials tile shares the opacity and offset | B-112 (Arc's and Dia's lift; was light only, `0 0.5 2` at 15%) |
| `IconStyle.folder`, `SidebarMetrics.folderGlyphSize` | 15 pt regular in a 20 × 18 box centred on the favicon's centre (was 13 pt in the 16 pt favicon box) | B-115 (Finder's and Notes' sidebar folder) |
| `SplitMetrics.paneGap` / `resizerHitWidth` | 8 (`CardMetrics.inset`) / 10: each pane a card (`CardMetrics` corner, hairline border, shadow), the page card draws nothing behind a split (`CardView.isSplitHost`) | B-113 |
| `Hairline.width(scale:)`, `HairlineView` | 1 / backing scale: one device pixel; the card's border (`CardMetrics.borderWidth` × it), split panes' borders, the Today separator, the palette's and the toolbar's separators, Peek's header line, the DevTools divider, the status pill's border, the split row's segment lines | 5.2a task 3; pixel reads in `spike-results.md` "Phase 5.2" (the Today separator was 2 px, an `NSBox`) |
| `Palette.dragImageFillDark` / `themeWellDefaultHex` | white 0.2 / `#5B8DEF` | were literals (2.2b, 2.5) |
| `SpaceFormMetrics` (moved to Design) | padding 12, icon cell 26, preview 18, `selectionAlpha` 0.25, `cornerRadius` 6, `emptyPreviewAlpha` 0.12, `previewFadeAlpha` 0.4 | were literals (2.5) |

### Icon weights (`IconStyle`, every symbol the chrome draws)

| Role | Size / weight | Used by |
|---|---|---|
| `menu` | 13 regular | menu items, Library list icons, the PiP panel's Back to Tab |
| `control` | 13 regular | the top bar (toggle, Back, Forward, Reload, overflow), the site button, the footer's downloads and New Tab (B-110), Peek's header |
| `controlSmall` | 12 regular | Copy URL, the zoom buttons, the find bar's search glyph, an extension action without an icon |
| `paneControl` | 11 regular | a split pane's header and grip |
| `findButton` | 11 semibold | find previous, next, done |
| `disclosure` | 11 semibold | the Library's section chevrons |
| `rowButton` | 10 medium | a row's ×, audio |
| `rowAction` | 11 medium | a row's reset, the space title's "…", the reader and capture indicators |
| `rowChevron` | 9 medium | the space title's and a folder's collapse chevron |
| `rowGlyph` | 12 regular | the New Tab row's "+" |
| `folder` | 15 regular | a folder row (B-115), its drag image |
| `spaceTitle` / `spaceIcon` / `spaceDot` | 12 semibold / 12 medium / 6 regular | a space's symbol beside its title, in the footer; the dot of a space without one |
| `tileReset` / `tileBadge` | 13 medium / 8 semibold | an Essentials tile's reset glyph and audio badge |
| `media` | 11 regular | the media row |
| `downloadProgress` | 11 regular | the arrow inside the downloads ring |
| `paletteField` / `paletteRow` / `paletteDelete` | 15 regular / 13 regular / 10 semibold | the palette |
| `interstitial` | 44 regular (`PromptMetrics.interstitialIconSize`) | the certificate interstitial, the crashed and unresponsive page |

### Typography against the HIG (macOS scale: Large Title 26, Title 1 22, Title 2 17, Title 3 15, Headline 13 bold, Body 13, Callout 12, Subheadline 11, Footnote 10, Caption 10)

| Token | Value | HIG |
|---|---|---|
| `Typography.row` | 13 regular | Body |
| `Typography.secondary` | 11 regular | Subheadline |
| `Typography.spaceTitle`, `headline` (new) | 13 semibold | Headline (bold in the HIG; semibold is the measured Dia title, kept) |
| `Typography.sidebarRow` | 14 regular | none: the Room Browser design (between Body and Title 3), kept |
| `Typography.paletteField` | 18 regular | none: chosen (Title 2 is 17), kept |
| `Typography.interstitialTitle` (new) | 24 semibold | none: Large Title is 26 regular; was a literal |
| `Typography.interstitialText` (new) | 14 regular | none: the sidebar rows' size; was a literal |
| `Typography.toast` (new) | 12 semibold | Callout's size |
| `Typography.code` / `counter` / `zoomValue` (new) | 11 monospaced / 11 monospaced digits / 13 medium monospaced digits | Subheadline's and Body's sizes |
| `Typography.badgeLarge` / `badge` / `badgeSmall` (new) | 10 / 9 / 8 semibold | below the scale (badges); were literals |

### Deliberate literals (`// design-audit:` on the line)

| Where | Literal | Why |
|---|---|---|
| `Packages/Engine/Sources/FakeEngine/FakePageView.swift` | monospaced 13 | FakeEngine's stand-in page for tests and the engine-free app, not the chrome |


## Added in Phase 5.2b (theme contrast, inactive windows, mono traffic lights, B-23, B-37, the icon's slots, Chromium's branding)

| Token | Value | Provenance |
|---|---|---|
| `Palette.sidebarSecondaryLabel`, `Palette.sidebarSecondaryAlpha` | the label colour at 0.64 light / 0.82 dark (was AppKit's `secondaryLabelColor`, black 0.50 / white 0.55): sublabels, the folder glyph, the unloaded split titles, the footer's space name, Clear, the Essentials grid's empty label | the theme contrast rule (task 4): 800 of 800 samples were under 4.5:1 for secondary text, 0 after; primary text was never under (minimum 4.67 dark, Triadic #FDD835 at the highest opacity). Table in `spike-results.md` "Phase 5.2" |
| Inactive tint | `SpaceTintView.inactiveFactor` 0.6 × the alpha and the colours' saturation × `SidebarMetrics.inactiveSaturation` 0.8, faded over `Motion.standard` with the sidebar's content | spec §I.12; 5.2b found the inactive stops never reached the layer (read back: alpha 0.175 inactive as active) |
| `TrafficLightMetrics.monochromeSaturation` | 0 (a `CIColorControls` filter on each button; Settings ▸ Appearance ▸ Grey window buttons, off by default) | spec §I.12 (mono traffic lights optional); the close button read #F57974 → #9FA0A1 |
| `TintOpacityControl` | a slider 0–100 % of `Space.themeOpacity` (→ `Materials.tintOpacityRange` 0.10–0.25) under the algorithm in the space form; a view of its own for 5.7b's space window | B-23 |
| Menu key glyphs | `MenuKey.display`: a shifted digit or punctuation key drawn as ⇧ with its base key (⇧⌘], ⌃⇧1); a hidden alias on the typed character (`MenuKey.equivalent`, identifier suffix `#shifted`) matches the key | B-37 |

### Theme contrast

The rule (5.2b task 4): over every space theme the sidebar's primary text (AppKit's label colour, 85 %) and secondary text (`Palette.sidebarSecondaryLabel`) hold 4.5:1. Measured by `scripts/theme-contrast.sh` (five algorithms × eight colours × five wallpaper fixtures, light and dark, opacity 0.5 and 1.0): worst primary 4.67 (dark, Triadic #FDD835 at 1.0), worst secondary 4.51 after the rule (2.95 before). The fixtures did not reach the captures (the behind-window material renders without its backdrop in a window capture; B-132). An inactive window's text is below the line by design (B-131). The table: `research/notes/spike-results.md` "Phase 5.2", 5.2b.

### The app icon's slots (task 7)

The icon is the user's (Icon Composer, 2026-10-08; `1c885c1` made the newer one the default), so no placeholder was generated. Where a designer's icon goes:

| Slot | File | Made by |
|---|---|---|
| The app (Dock, Finder, notifications of Room itself) | `App/Resources/AppIcon.icon` (Icon Composer document; layers in `Assets/`) | actool at build time (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `xcodegen/base.yml`) → `Assets.car`, `AppIcon.icns` |
| Settings ▸ Appearance ▸ App Icon alternates | `App/Resources/AppIcons/<Name>.icon` (sources) → `App/Resources/AppIcons/Rendered/<raw>{,-dark}.png` 1024 × 1024 | `scripts/render-app-icons.sh` (ictool), committed |
| The engine's helpers (macOS shows the alerts helper's icon on web notifications) | `chrome/app/theme/room/mac/app.icns`, `Assets.car` in the checkout | `Engine/roomcore/room/branding/tools/install_theme.sh` compiles `App/Resources/AppIcon.icon` with actool into `room/branding/theme/gen/mac/` (gitignored) when the document changes |
| Chrome's pages' corner logo, the larger product logos, the wordmark | `Engine/roomcore/room/branding/theme/{room,default_100_percent,default_200_percent}/product_logo_*.png`, `product_logo_name_22*.png` (16–256 px; the wordmark 97 × 22 pt) | `room/branding/tools/render_theme.swift` from the icon's glyph layer (`Assets/Image.png`), committed |

A new icon: replace the `.icon` document (and its glyph layer), run `scripts/render-app-icons.sh` and `swift Engine/roomcore/room/branding/tools/render_theme.swift .`, then `scripts/roomcore-apply.sh` and the engine build.

## Added in Phase 5.3a (labels, roles, keyboard)

| Token | Value | Provenance |
|---|---|---|
| `FocusRing.controlCornerRadius` | `ControlMetrics.cornerRadius` (6): an icon button's ring is its hover square (`HoverButton.drawFocusRingMask`), not the glyph's outline AppKit drew | 5.3a task 2; AppKit's ring colour (`keyboardFocusIndicatorColor`, the accent) |
| `FocusRing.pillCornerRadius` | `Radius.large` (12): the address field's and an Essential tile's ring is their pill | 5.3a task 2 |
| Sidebar rows' ring | unchanged: `SidebarMetrics.insertionLineWidth` 2 pt in the accent, drawn by the row (spec §I.13); now also when Tab brings the focus to the list (on the selected row) and gone when it leaves | 5.3a |
| `ReadingOrder.tolerance` | 4 pt: VoiceOver's order inside the sidebar and the Tab order inside a region read top to bottom by bands of 4 pt, then leading to trailing | chosen |
| `SidebarSplitterView.accessibilityStep` | 10 pt: VoiceOver's increment and decrement of the sidebar's width | chosen |
| `KeyboardAccess` | Room's controls are Tab stops while Full Keyboard Access is on (`NSApp.isFullKeyboardAccessEnabled`, or `allControlsOverride` in tests and spikes); the address field always (it stands for a text field); a click never takes the keyboard (`isMouseDown`); Space, Return and Enter press | 5.3a task 2 |

The Tab order (`UIKitCore/KeyViewLoop.swift`, `RoomWindow.keyViewRegions` set by the app): the sidebar's body (Essentials, the list, the Library in its place) → the header (toggle, extensions, Back, Forward, Reload, the address field, the site button; the toolbar when shown) → the card (the page, a split's panes, Peek over it) → the footer (downloads, the space icons, New) → around. A list, a text field and the page keep Tab for their own parts; a page's dialog keeps its own loop. Copy URL is not a stop (a hover affordance; ⇧⌘C).

## Added in Phase 5.3b (sidebar text, Increase Contrast, Reduce Transparency, Differentiate Without Colour)

Review sheets: `research/screenshots/phase-5.3/phase-5.3-{rows,header,palette,toasts}-{modes,sizes}.png` (`scripts/visual-matrix.sh … -RoomMatrixColumns modes|sizes -RoomMatrixPhase 5.3`), the tokens printed on each.

| Token | Value | Provenance |
|---|---|---|
| `TextScale` (`size`, `factor(_:)`, `fontSize(_:)`, `length(_:)`) | Settings ▸ Appearance ▸ Sidebar text (`Settings.sidebarTextSize`; DEBUG `-RoomSidebarTextSize`): small ×12/14, medium ×1, large ×16/14; type to the nearest half point, row heights to the nearest point; posts `TextScale.didChange` (the sidebar reloads, the address field and the palette re-set their fonts once per size) | ROADMAP 5.3 task 4 ("one scale factor applied in Design"); the 2 pt step as Finder's sidebar sizes |
| Scaled type | `Typography.sidebarRow` 12 / **14** / 16; `sidebarSecondary` (new: sublabels, Clear) 9.5 / **11** / 12.5; `sidebarSpaceTitle` (new) 11 / **13** / 15 semibold; `paletteRow` (new) 11 / **13** / 15; `paletteSecondary` (new: chip, hint) 9.5 / **11** / 12.5; `paletteField` 15.5 / **18** / 20.5 | the design's sizes at medium |
| Scaled heights | `SidebarMetrics.rowHeight` and `spaceTitleRowHeight` 31 / **36** / 41; `separatorRowHeight` 21 / **24** / 27; `PaletteMetrics.rowHeight` 31 / **36** / 41 | same factor |
| Not scaled | `Typography.row`, `secondary`, `spaceTitle` (Peek, prompts, Library, Settings), favicons, insets, the header and field heights, the Essentials' tiles, `LibraryMetrics.itemRowHeight` (now its own 36) | the setting is the sidebar's and the palette's |
| `TextScale.lineHeight(_:)` | a label cell's height for the font (was `NSLayoutManager.defaultLineHeight`, a point short at 11 and 15 pt: the palette clipped its labels at small and large) | 5.3b's clipping read-back |
| `DisplayOptions` (`current`, `source`, `didChange`, `followSystem()`) | System Settings ▸ Accessibility ▸ Display's Increase contrast, Reduce transparency, Differentiate without colour; `.system` in production, followed live through `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`; `.fixed` in tests and DEBUG's `-RoomIncreaseContrast`, `-RoomReduceTransparency`, `-RoomDifferentiateWithoutColor`; a change redraws Room's windows and posts `didChange` | ROADMAP 5.3 task 5; `Motion.preferences`' injected pattern |
| `Palette.hairline`, `hairlineHighContrast`, `hairlineHighContrastAlpha` | AppKit's separator; under Increase Contrast the label colour at 45 % light / 50 % dark; `Palette.cardBorder` (7–8 %) takes it too; used by `HairlineView`, the split row's segment lines, the status pill's border, the DevTools and Peek header lines, the toast's solid capsule | chosen (borders as AppKit's controls gain them under Increase Contrast) |
| `Palette.sidebarSecondaryHighContrastAlpha` | 80 % light / 85 % dark (normal 64 % / 82 %), never above the primary label's 85 %: worst 8.1:1 light, 4.7:1 dark over 5.2b's 800 samples (the darkest tint at its highest opacity limits dark; the primary is 4.67 there) | 5.3b's measurement (`spike-results.md` "Phase 5.3" 5.3b) |
| `Palette.sidebarUnloadedLabel` | an unloaded row's title: the label colour at 70 % (`SidebarMetrics.unloadedTitleAlpha`), Increase Contrast's secondary alphas under it; resolved when drawn | spec §A.1; 5.3b fixed a colour fixed to the last configure's appearance |
| `Materials.solidFill`, `Materials.usesSolidFill(_:)`, `SolidBackingView` | Reduce Transparency: `windowBackgroundColor` behind the sidebar and the card (in `WindowMaterialView`, the tint over it) and under the overlays' content (palette, find bar, zoom, dialogs, ⌃Tab, the revealed sidebar, the status pill, a pane's header) at each one's corner radius; toasts draw a solid capsule with a hairline when shown | ROADMAP 5.3 task 5 ("solid materials in place of vibrancy"); what macOS draws for materials under the setting |
| `ChangedMark.style(_:)` | the changed dot: normal 6 pt, no ring; Differentiate Without Colour 9 pt with a 1.5 pt `Palette.changedMarkOutline` (`windowBackgroundColor`) ring, the centre unchanged (rows and Essentials tiles) | ROADMAP 5.3 task 5; the ring separates the dot from a favicon of the accent's hue |
| `AudioGlyph.symbol(muted:_:)`, `Symbol.audibleShape` / `mutedShape` | Differentiate Without Colour: `speaker.wave.2.circle.fill` / `speaker.slash.circle.fill` in place of `speaker.wave.2.fill` / `speaker.slash.fill` (rows and the Essentials' badge) | ROADMAP 5.3 task 5 |

What the in-process options do not reach: AppKit's own colours (`labelColor`, `secondaryLabelColor`, `separatorColor` outside `Palette.hairline`) and `NSPopover`'s material (downloads, the site panel, permissions) change only with the real switches, which the system applies itself (Phase 5.3 step 3 for the user).

## Added in Phase 5.7a (Settings, B-120)

| Token / surface | Value | Source |
|---|---|---|
| `SettingsWindowFit.contentWidth` / `preferredContentHeight` / `margin` / `minimumContentHeight` | 560 / 640 / 8 / 240 pt: every pane one height, `min(640, visible frame − title bar and toolbar − 2 × 8)`, its content scrolling; the window moved inside the visible frame | B-120 (panes did not scroll; the window grew past the display); values chosen |
| `SettingsWindowFit.smallestVisibleFrame` | 1024 × 543 pt (a 1024 × 640 display less a 33 pt menu bar and a 64 pt Dock) | the smallest macOS 26 display scale |
| `SearchSettingsMetrics.listHeight` / `editorWidth` | 200 pt (about five engines, then it scrolls) / 460 pt sheet | B-120; chosen |
| `ContentBlockingSheetMetrics` | 540 × 480 pt: Filter Lists, Custom Rules, Allowed Sites sheets | B-120; chosen |
| `SitePermissionsMetrics` | 640 × 420 pt, the types column 200 pt (Safari's Websites layout) | B-120; chosen |
| `ShortcutsSettingsMetrics.margin` | 20 pt around the table, 12 pt between the lines; a bordered full-width table; no ◆ (a reserved action's tooltip) | B-120 |
| Archive tabs after | 12 h, 24 h, 7 d, 30 d, — , Never (the default) | B-120 |

## Added in Phase 5.7b (the space window, onboarding)

| Token | Value | Provenance |
|---|---|---|
| `SpaceWindowMetrics.width` / `height` / `minHeight` | 420 / 640 / 360 pt, fitted inside the display's visible frame less `screenMargin` (`Spacing.s`, 8) and centred over the browser window; resizable, the sections scroll, Cancel and Save/Create stay at the bottom | B-122; chosen |
| The space window's form | `SpaceFormView` (the sidebar's form moved into the window): Name, Icon, Colour (wells, algorithm, `TintOpacityControl`, the preview), Profile, then Routes (this space's rules: a checkbox each, ⊖, a match popup and pattern field with Add, "All Rules…" for the routing sheet); `SpaceFormMetrics` unchanged | B-122 |
| `OnboardingMetrics.width` / `height` | 560 × 440 pt, a panel (`NSPanel`, key, never main) centred over the browser window; its import step orders it out while the import sheet (580 × 760, larger than the panel) shows on the browser window, and back after | B-121; chosen |
| `OnboardingMetrics.padding` / `symbolSize` / `dotSize` / `swatchSize` | 24 / 40 / 6 / 28 pt; the step's SF Symbol in the accent colour, title `.title` bold, the line `.body` secondary centred; step dots primary (current) or secondary at 0.35; Skip Setup leading, Back and Continue / Done (Return) trailing | chosen |
| `OnboardingMetrics.themeSwatches` | none, `#1E88E5`, `#3E9B5B`, `#E53935`, `#8E24AA`, `#FB8C00`, `#546E7A` (the space's algorithm extends the base colour); the chosen one ringed in primary at `swatchRingWidth` 2 pt; the none swatch secondary at `emptySwatchAlpha` 0.15; inactive dots at `inactiveDotAlpha` 0.35 | chosen |
