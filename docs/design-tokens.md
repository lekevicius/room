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

## Added in Phase 2.5 (spaces)

| Token | Value | Provenance |
|---|---|---|
| Space switch slide | both lists move by the list's width over `Motion.medium` (0.25 s), ease-out, as layer transforms on lists built ahead of time; Reduce Motion: a crossfade over the same time | spec §B, §I.1; Zen `switch-animation-duration=250` |
| Tint crossfade | `colors` of the tint gradient over `Motion.medium`, ease-in-out, alongside the slide | spec §B |
| Theme algorithms (`ThemePalette`) | the first well is the base; the algorithm fills empty wells at hue offsets from it: Complementary +180°; Split +150°, +210°; Analogous −30°, +30°; Triadic +120°, +240°; Floating none. A filled well always wins; 3 colours at most | spec §B (five algorithms, 1–3 colours); colour-wheel harmonies as Zen's gradient generator places its dots; the "fill empty wells" rule is ours |
| Tint gradient (`SpaceTintView`) | diagonal, top leading → bottom trailing, always 3 stops: one colour fades from its alpha to `tintOpacityRange.lowerBound`; two put their 50% blend in the middle; three as given | chosen; 3 stops so themes with different colour counts interpolate |
| Tint alpha | `ThemePalette.tintAlpha`: `themeOpacity` (0–1, default 0.5) mapped linearly into `Materials.tintOpacityRange` (0.10–0.25; 0.5 → 0.175) | chosen, within the Phase 1.6 range |
| Dark theme colours | lightness capped at 0.45 (`ThemePalette.darkMaxLightness`), hue and saturation kept | chosen: pastel themes washed out the dark material |
| `SpaceIconMetrics.size` / `pitch` / `dotSize` | 20 / 26 / 6 pt; icons shrink to fit between the footer buttons | chosen; Zen shrinks its strip on overflow |
| `SpaceIconMetrics.activeScale` | 1.15, animated over `Motion.medium` | spec §B |
| Active highlight | `Palette.sidebarHover` capsule 2 pt around the active icon (`indicatorPadding`), sliding over `Motion.medium` ease-out | spec §B "the active indicator slides"; colour chosen |
| `SpaceIconMetrics.inactiveAlpha` | 0.55 | chosen |
| Hover name | `Typography.secondary`, secondary label colour, right of the icon row, fades over `Motion.fast` | spec §B |
| `SpaceIconMetrics.reorderThreshold` | 5 pt of travel turns a press on an icon into a reorder drag, haptic `.alignment` per slot | Zen (>5 px) |
| Drop on a space icon | `Palette.sidebarMultiSelection` circle behind the icon; resting `DropRules.holdDelay` (0.5 s) switches to the space | spec §B / ROADMAP 2.5 task 5 (500 ms) |
| Swipe | 25% of the list width or a fling (progress + 0.5 × velocity in widths/s) switches; before the first space a rubber band bounded at 0.15 widths; past the last the new-space form; axis locks horizontal when the first movement is 1.5× more horizontal | spec §B, Zen (`threshold 0.25`, `velocity 0.5`); band limit and lock ratio chosen |
| ⌃ + wheel | one space per notch (down = next), 200 ms cooldown; trackpad ⌃-scroll counts 30 pt as a notch | Zen `scroll-modifier-key`, cooldown 200 ms; trackpad step chosen |
| `SpaceFormMetrics.padding` / `iconCell` / `previewHeight` | 12 / 26 / 18 pt | chosen |
| Space form icons | 24 SF Symbols and 24 emoji, any emoji typed in its field | chosen |
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
| `Timing.revealDwell` / `revealGrace` | 0.15 / 0.15 s | spec §E (150 ms dwell; Zen `sidebar-keep-hover.duration` 150 ms) |
| `RevealMetrics.outsideToleranceX` / `Y` | 200 / 100 pt around the overlay, pointer outside the window | spec §E (Zen `outside-window-edge-offset`) |
| `RevealMetrics.overlayInset` | 10 pt from the top, leading and bottom edges | spec §E (Zen `--zen-compact-float`) |
| Overlay slide | `Motion.medium` (0.25 s) ease-out in, ease-in out, fully off the leading edge; Reduce Motion: a fade | spec §E (250 ms) |
| `RevealMetrics.overlayCornerRadius` | `Radius.large` (12) on `NSGlassEffectView` | chosen (the overlays' radius) |
| Overlay wash (`overlayTintWhiteLight` / `Dark`, `overlayTintAlpha`) | white 0.88 / 0.16 at α 0.75 inside the glass | chosen: untinted glass let page text read through the rows; the glass's own `tintColor` rendered near white and hid the white selection pill (2.7a captures) |
| Overlay header | Back, Forward, Reload (`navigationButtonSize` 28) beside the traffic lights; the address field on its own row below, `addressRowGap` 4 | spec §E ("present in the revealed overlay header"); layout chosen (Arc's two rows) |
| `ClusterMetrics.height` | 38 pt glass pill centred on the window's own buttons | spec §E (38 px) |
| `ClusterMetrics.horizontalPadding` | 12 pt beside the outer buttons (pill 84 × 38 around 60 × 14 buttons) | chosen |
| `Timing.clusterFade` | 2 s after the pointer was last within `ClusterMetrics.nearDistance` (60 pt) of the pill; fades with the buttons over `Motion.standard`, back over `Motion.fast` | spec §E (2 s); distance chosen |
| Cluster wash | the overlay's wash inside the pill's glass | chosen (page text read through the clear glass behind the buttons) |
| `ClusterMetrics.contentDragFraction` / `contentDragThreshold` | the top 5% of the card drags the window once a press moves 3 pt | spec §E (Zen `drag-window-from-content`); threshold = AppKit's drag distance |
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
| `SplitMetrics.dividerWidth` / `resizerHitWidth` | 1 pt line between panes (separator colour), 7 pt hit area centred on it; double-click equalises | spec §D |
| `SplitMetrics.minimumPaneFraction` / `minimumPaneLength` | a pane never gets under 7% of the split along the dragged axis, nor under 120 pt while the split has room (never more than an equal share) | Zen `min-resize-width` 7 percent; 120 pt chosen (as `DevToolsMetrics.minPaneHeight`) |
| `SplitMetrics.paneHeaderHeight` / `paneHeaderRevealBand` / `paneHeaderButtonSize`, `Timing.paneHeaderHideDelay` | 24 pt header over the pane's top (domain, grip, layout menu, ×) while the pointer is within 36 pt of the top; buttons 20 pt; hides 0.3 s after the pointer leaves; `.headerView` material, the appearance that reads on the page's fill | spec §D (24 px strip); band, buttons, delay chosen |
| `SplitMetrics.dropEdgeBand` / `dropPreviewFraction` / `dropPreviewAlpha` | an entry dragged into the card: within 40 pt of a pane's edge it splits to that side (the nearest edge in a corner), elsewhere it replaces the pane; the preview covers the half the new pane gets, accent at 18% with a 2 pt accent border, 10 pt corners | spec §D (40 px band); preview chosen |
| `Timing.splitJoinDwell` (= `DropRules.holdDelay`) | a single entry resting 500 ms on a tab row's middle 60% joins it into a split (a pinned entry onto a pinned entry still makes a folder, §A.6) | spec §D, §A.6 |
| `SplitMetrics.segmentTitleMinWidth` / `focusedSegmentAlpha` | the group row's segments show a title when at least 64 pt wide (else the favicon alone); the focused pane's segment is tinted with the accent at 16% | spec §D ("tinted"); values chosen |

## Added in Phase 2.8a (menus, Settings v0, the sidebar on the right)

| Token | Value | Provenance |
|---|---|---|
| Settings window | toolbar tabs (`NSTabViewController.tabStyle = .toolbar`, `toolbarStyle = .preference`), sections General, Appearance, Search, Downloads; each a grouped SwiftUI `Form` 480 pt wide at its own height; the title follows the section | the Mac's settings windows; width chosen (460 in 2.4b, wider for the segmented pickers) |
| Settings section symbols | `gearshape` / `paintpalette` / `magnifyingglass` / `arrow.down.circle` | chosen (system settings conventions) |
| Sidebar on the right | the docked layout mirrored with the same tokens (`CardMetrics.inset` on the card's outer sides, `sidebarSideInset` against the sidebar, the splitter's hit area mostly inside the sidebar), the reveal band (`RevealMetrics.edgeBand`) and the overlay (`overlayInset`) at the right edge; the traffic lights stay where AppKit puts them, over the card, with the floating cluster (`ClusterMetrics`) and the card-top drag band; the header starts at `SidebarMetrics.edgeInset` | Settings v0 (ROADMAP 2.8 task 2); Chapter 1 traffic-light rule |
| Planned menu items | present, disabled, tooltip "Comes in Chapter N"; keys the menu cannot carry (Esc, Return) named in the tooltip | ROADMAP 2.8 task 1 |

## Added in Phase 2.8b (the first-run card, Settings ▸ Privacy)

| Token | Value | Provenance |
|---|---|---|
| First-run card (`FirstRunCardView`) | in the sidebar above the footer (`SidebarBodyView.accessoryView`), the rows' width (6 pt inset each side); fill `Palette.sidebarSelection`, corner `FirstRunMetrics.cornerRadius` = `Radius.medium` (10, the selection pill's), continuous; shadow `Palette.cardShadow` at 0.08, radius 3, 1 pt down | `macos-ui-stack.md` §7.4 ("an in-sidebar card, never a modal"); look chosen: one of the sidebar's own surfaces |
| `FirstRunMetrics.padding` / `rowSpacing` | 12 / 8 pt | chosen (the overlays' 12 pt) |
| `FirstRunMetrics.gapAboveFooter` / `gapAboveList` | 4 / 8 pt; the list ends above the card | chosen |
| Card content | SwiftUI leaf, `.controlSize(.small)`: title `.headline`, caption `.caption` secondary; Search with (menu picker), Make Room Your Default Browser (or a check and "Room is your default browser"), two checkboxes with a one-line note, Done trailing (no default-button key: Return belongs to the fields) | chosen |
| Card dismissal | fades out over `Motion.fast` (0.12 s), then the list takes the space | chosen |
| Settings ▸ Privacy | symbol `hand.raised`; "Send crash reports", "Check for updates automatically", Check Now beside the version | chosen (system settings conventions) |
