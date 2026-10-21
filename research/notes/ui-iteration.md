# The UI iteration list (Chapter 5)

ROADMAP Phase 5.9 task 4. Every taste item from Chapter 5's review sheets and every row the sessions could not judge, one per line, with the capture to look at, the token it would change (name and current value, from `docs/design-tokens.md` unless the row says otherwise) and the session's provisional choice, which is what ships until you mark it. Chapter 6 starts after your pass over it.

Sources: `research/notes/chapter-5-by-hand.md` "For the user" (each phase's Taste steps, and the taste notes in "Run by the sessions"), the review sheets under `research/screenshots/phase-5.*/`, the backlog rows marked taste, iteration list or the user's call (`docs/backlog.md`), and the deviations the Chapter 5 log entries flagged (`docs/progress.md`).

**How to mark.** Write in the "Your call" column: **keep**; a new value for the named token (`0.08`, `0 1 6 at 10%`, `14 pt`); a wording; or **drop** / **build** for a feature row. A blank row means keep. Capture paths are relative to `research/screenshots/`; "→" is before → after. Sheets with `-light`/`-dark` have both; the 5.2 matrix sheets hold light and dark × active and inactive on one sheet. Row ids (S1, T1 …) are for the session that applies the marks.

## The review sheets

| Phase | Sheets |
|---|---|
| 5.1b | `phase-5.1/phase-5.1b-controls.png` (each top-bar and footer control at rest, hovered, pressed, pressed under Reduce Motion; light and dark), `phase-5.1/phase-5.1b-reveal.png` (the hidden sidebar's slide at 0/25/50/75/100 % and the Reduce Motion fade) |
| 5.2a | `phase-5.2/phase-5.2-{footer,rows,split,extensions,header}.png` with `-before` sheets; `phase-5.2-{palette,peek,toasts,downloads,sitepanel,prompts,library,settings,incognito}.png` (17 surfaces in all with 5.2b's, light/dark × active/inactive, the tokens printed on each) |
| 5.2b | `phase-5.2/phase-5.2-themes.png`, `-rows.png`, `-menus.png`, `-split.png`, `-spaceform.png` (each with a `-5.2b-before` sheet), `phase-5.2-icon.png`, `phase-5.2-branding-light-before.png` → `phase-5.2-branding-light.png` / `-dark.png` |
| 5.3a | `phase-5.3/phase-5.3a-focus-{address-field,back,outline,space-icon}.png` (focus rings) |
| 5.3b | `phase-5.3/phase-5.3-{rows,header,palette,toasts}-modes.png` (normal, Increase Contrast, Reduce Transparency, Differentiate Without Colour; light and dark), `-sizes.png` (Sidebar text small, medium, large; light and dark) |
| 5.4a | `phase-5.4/phase-5.4a-500-overlays-release.png` (evidence for the scroll with overlays; no taste step) |
| 5.5b | `phase-5.5/phase-5.5b-drop-sidebar-line-{light,dark}.png`, `-split-snap-light.png`, `-overflow-{line,clicked}-light.png`, `-status-pill{,-dodged}-light.png`, `-sublabel-{title,separate,reset}-light.png` (single captures, not sheets; only the haptics row below is a taste step) |
| 5.6a | `phase-5.6/phase-5.6a-details-{light,dark}.png` (14 captures, each with its token or rule) |
| 5.6b | `phase-5.6/phase-5.6b-details-{light,dark}.png` (5 captures) |
| 5.7a | `phase-5.7/phase-5.7-settings.png` (every pane), `phase-5.7/phase-5.7-settingssheets.png` (Privacy's four sheets); light and dark, active and inactive |
| 5.7b | `phase-5.7/phase-5.7-spaceform.png`, `phase-5.7/phase-5.7-onboarding.png`; before them `phase-5.2/phase-5.2-spaceform.png` and `phase-2.8b/phase-2.8b-firstrun-*.png` |
| 5.8a | `phase-5.8/phase-5.8a-passwords-{light,dark}.png` and five single captures per appearance (`phase-5.8a-password-{save,update,saved-toast,save-sidebar-hidden,manager-tab}-*.png`); on branch `phase-5.8a`, not yet merged into main |

## Sidebar

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| S1 | The selected pill's shadow (B-112) | `phase-5.2/phase-5.2-rows-before.png` → `phase-5.2-rows.png` | `SidebarMetrics.pillShadowOpacity` 0.12, `pillShadowOpacityDark` 0.30, `pillShadowRadius` 2, `pillShadowOffset` (0, −1): `0 1 4`; the selected Essential shares opacity and offset | `0 1 4` at 12 % light / 30 % dark (was `0 0.5 2` at 15 %, light only) | |
| S2 | The folder glyph (B-115) | `phase-5.2/phase-5.2-rows-before.png` → `phase-5.2-rows.png` | `IconStyle.folder` 15 regular in a 20 × 18 box (`SidebarMetrics.folderGlyphSize`) | 15 pt, Finder's and Notes' size (was 13 pt in the 16 pt favicon box) | |
| S3 | Dark secondary text close to the primary (B-131, taste half) | `phase-5.2/phase-5.2-themes-5.2b-before.png` → `phase-5.2-themes.png`; `phase-5.2-rows.png` | `Palette.sidebarSecondaryAlpha` 0.64 light / 0.82 dark; primary is the label colour, 85 % | 82 % in dark (worst secondary 4.51:1 over 800 samples). Alternative: the dark tint at about half the light one's alpha, secondary at 70 % | |
| S4 | How dim an inactive window is (B-131) | `phase-5.2/phase-5.2-themes.png` (inactive columns) | `SidebarMetrics.inactiveContentAlpha` 0.6, `inactiveSaturation` 0.8, `SpaceTintView.inactiveFactor` 0.6 (tint alpha), faded over `Motion.standard` 0.15 s | Spec §I.12's dimming kept: inactive primary text 3.7:1 light / 4.0 dark, secondary 2.6 / 3.8 at the highest tint (under 4.5:1 by design) | |
| S5 | Each theme algorithm on its colour, the tint strength | `phase-5.2/phase-5.2-themes.png` | `Materials.tintOpacityRange` 0.10–0.25; `ThemePalette.tintAlpha` default `themeOpacity` 0.5 → 0.175; `ThemePalette.darkMaxLightness` 0.45 | Unchanged since 2.5; the inactive tint now applies (it never reached its layer before 5.2b) | |
| S6 | The unread dot: place and colour | `phase-5.6/phase-5.6a-details-light.png` / `-dark.png` ("(3) Inbox -> Inbox + unread dot") | `SidebarMetrics.unreadDotSize` 6, `Palette.accent` (`controlAccentColor`); row: trailing edge, gives way to ×; tile: top-left corner (`EssentialTileView.layout`, a flipped view: the top-right is the audio badge's, the bottom-right the changed dot's; `design-tokens.md` said top-right until 5.9 and now agrees) | A leading "(N)" stripped from the title and shown as the dot, loaded pages only | |
| S7 | A changed pinned row: stored label, live title as sublabel | `phase-5.6/phase-5.6a-details-*.png` ("Changed pinned") | Sublabel `Typography.sidebarSecondary` 11 (medium) in `Palette.sidebarSecondaryLabel` | `EntryLabel.title`: custom label, else the stored title away from the pinned URL, the live title on hover | |
| S8 | Change Icon…'s picker beside the row, an emoji in the favicon's place | `phase-5.6/phase-5.6a-details-*.png` ("Change Icon…", "Picked") | `SpaceFormMetrics.iconPopoverWidth` (6 cells of `iconCell` 26 + 5 gaps + padding + 24); `SidebarMetrics.customIconEmojiScale` 0.82 | The space form's picker in a popover; a choice applies at once and closes it | |
| S9 | A folder's custom symbol in place of its glyph | `phase-5.6/phase-5.6a-details-*.png` ("Folder symbol") | `IconStyle.rowGlyph` 12 regular, label colour | The symbol replaces the folder glyph | |
| S10 | Clear fades with the pointer (B-118) | `phase-5.6/phase-5.6a-details-*.png` ("Clear: pointer away", "pointer over the sidebar") | Alpha 0 → 1 over `Motion.fast` 0.12 s (`SidebarMotion.clearReveal`) | Stays in place transparent (VoiceOver and the keyboard keep it), not hidden as B-118 asked | |
| S11 | The Library | `phase-5.2/phase-5.2-library.png` | `LibraryMetrics.sectionRowHeight` / `dayRowHeight` / `itemRowHeight` 28 / 22 / 36; `buttonSize` 20; `chipHeight` 16 on `Palette.sidebarHover` | Unchanged since 4.1a | |
| S12 | A deleted space's Archive rows: the chip's words (B-124) | none (`-RoomSpike skipped`, Chapter 4 step 6) | `LibraryController.spaceName` | "Deleted space" from the deletion on; Chapter 4's step expected the space's name | |
| S13 | Incognito windows, the second one (B-98) | `phase-5.2/phase-5.2-incognito.png`; `phase-5.6/phase-5.6b-details-*.png` | none new | Several incognito windows share one ephemeral store | |

## Top bar and controls

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| T1 | One metric for the top bar's and the footer's buttons (B-110) | `phase-5.2/phase-5.2-footer-before.png` → `phase-5.2-footer.png` | `ControlMetrics.size` 32, `minSize` 24, `groupGap` 4, `cornerRadius` 6; glyphs `IconStyle.control` 13; the downloads ring 20 pt across (`DownloadsMetrics.ringInset` 6); space icons a 32 pt square, glyph 20 | Footer buttons 32 pt at `rowHorizontalInset` 8 (were 28 at 12, glyphs 14) | |
| T2 | Two extensions beside Back (B-125), "…" overflow (B-89) | `phase-5.2/phase-5.2-extensions-before.png` → `phase-5.2-extensions.png` | The strip from `topBarGroupGap` 4 after the toggle to Back: 66 pt at the 300 pt default sidebar; an icon-less action `IconStyle.controlSmall` 12 | Two pinned actions fit at the default width (the strip packs against Back; the sidebar not widened to 304) | |
| T3 | The header | `phase-5.2/phase-5.2-header-before.png` → `phase-5.2-header.png` | `SidebarMetrics.headerHeight` 48, `topBarLeadingGap` 15, `addressFieldHeight` / `addressFieldPadding` / `addressRowGap` 36 / 10 / 8 | The Room Browser design's values | |
| T4 | Hover (B-111) | `phase-5.1/phase-5.1b-controls.png` | Fill `Palette.sidebarHover` 6 % over `Motion.fast` 0.12 s ease-out; the address field `Palette.addressFieldHover` 10 % (6 % at rest); space icons brighten from `SpaceIconMetrics.inactiveAlpha` 0.55 to 1 | One hover style for every icon button, "as Arc's" | |
| T5 | Press (B-111) | `phase-5.1/phase-5.1b-controls.png` | `Motion.pressScale` 0.9 over `pressIn` 0.08 s ease-out; `Motion.pressRelease` spring 0.3 s, bounce 0.35 (settles in 0.553 s); Reduce Motion `pressReducedAlpha` 0.6 | Shrink and spring back | |
| T6 | Menu key glyphs (B-37) | `phase-5.2/phase-5.2-menus-5.2b-before.png` → `phase-5.2-menus.png` | `MenuKey.display`: ⇧⌘] where ⌘} was | ⇧ drawn with the base key | |

## Card

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| C1 | Split as two cards with a gap (B-113) | `phase-5.2/phase-5.2-split-before.png` → `phase-5.2-split-5.2b-before.png` → `phase-5.2-split.png` | `SplitMetrics.paneGap` 8, `resizerHitWidth` 10; each pane `CardMetrics.cornerRadius` 6, 1 px border, shadow `0 2 6` at 15 % light / 35 % dark | 8 pt gap, the resize cursor anywhere in it | |
| C2 | The empty card's line | `phase-5.6/phase-5.6a-details-*.png` ("Empty card") | `Typography.row` 13, `tertiaryLabelColor`, centred | "Press ⌘T to search or type a URL" (New Tab's key from the Shortcuts table; "Click New Tab in the sidebar…" without a key) | |
| C3 | The card's top with the sidebar hidden, no drag band (B-32) | `phase-5.6/phase-5.6b-details-*.png` | `ContentDragMetrics` removed; a double-click under the 52 pt titlebar goes to the page | Only the sidebar moves the window | |
| C4 | Chrome's pages in Room (B-103) | `phase-5.2/phase-5.2-branding-light-before.png` → `phase-5.2-branding-light.png` / `-dark.png` | Logos rendered from the icon's glyph layer (`product_logo_*.png` 16–256 px, wordmark 97 × 22 pt) | "About Room", Room's glyph in the corner; `chrome://version`'s wordmark stays Chromium's until a patch (B-130, your decision) | |

## Palette

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| P1 | The palette | `phase-5.2/phase-5.2-palette.png` | `PaletteMetrics.width` 640, `topFraction` 0.18, `fieldHeight` 48, `rowHeight` 36; `Typography.paletteField` 18; highlight accent α 0.18 (`Palette.sidebarMultiSelection`) at `Radius.medium` 10; panel `Radius.large` 12 | Unchanged since 2.4–2.6 | |
| P2 | ⌃Tab thumbnails (B-119) | none (measured, not shipped) | `TabSwitcherMetrics.width` / `rowHeight` 340 / 36 | Not shipped: a shown page's capture 15–16 ms, a page off screen gives none (0 of 4). Option: a capture of each tab as it is left (stale for pages that change behind) | |

## Overlays and toasts

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| O1 | Toasts | `phase-5.2/phase-5.2-toasts.png` | `Typography.toast` 12 semibold; `Motion.toast` spring 0.5 s, bounce 0.2; `Motion.toastOut` 0.2 s; `toastInOffset` 12, `toastInScale` 0.9, `toastOutScale` 0.95, `toastPopScale` 1.06 | Unchanged | |
| O2 | The crash toast's time (Chapter 4 step 9) | none (tour `recovery`) | `Timing.toast` 2 s | 2 s | |
| O3 | Reaching a routing toast's Switch (Chapter 4 step 12) | none (`-RoomSpike skipped`) | `Timing.toastWithAction` 5 s, held while hovered | 5 s | |
| O4 | The hidden sidebar's toasts (background tab, download, new space) | `phase-5.6/phase-5.6b-details-*.png` | Anchor at the bottom-left, up to `SidebarMetrics.maxWidth` 500 pt | Shown with the sidebar hidden | |
| O5 | The "Sidebar hidden" hint at its new width | `phase-5.6/phase-5.6b-details-*.png` | Anchor up to 500 pt (was 240, the text cut at "…to bring i…") | Once per state, on the first snap; names Show Sidebar's key | |
| O6 | Downloads popover | `phase-5.2/phase-5.2-downloads.png` | `DownloadsMetrics.popoverWidth` 320, `maxVisibleRows` 6, file icon 32 | Unchanged | |
| O7 | Site panel | `phase-5.2/phase-5.2-sitepanel.png` | `SitePanelMetrics.width` 360 | Unchanged | |
| O8 | Page dialogs | `phase-5.2/phase-5.2-prompts.png` | `PromptMetrics.dialogWidth` 420, `dialogTopInset` 32, `dialogPadding` 20, `dialogSpacing` 12; dim `dimAlphaLight` 0.18 / `dimAlphaDark` 0.35 | Unchanged | |
| O9 | The dialog checkbox's words (B-116) | `phase-5.6/phase-5.6a-details-*.png` ("Second alert") | `Typography.secondary` 11 | "Prevent additional dialogs from this site", from a page's second dialog until it reloads | |
| O10 | Peek | `phase-5.2/phase-5.2-peek.png` | `PeekMetrics.sizeFraction` 0.86, `cornerRadius` 24, `dimAlpha` 0.30; shadow 24 pt at 0.25 / 0.5 | Unchanged | |

## Settings

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| ST1 | The panes' order and wording | `phase-5.7/phase-5.7-settings.png` | `SettingsWindowFit.contentWidth` 560, `preferredContentHeight` 640, `margin` 8 | Each setting in one pane, no Notes sections, Default browser compact (B-120) | |
| ST2 | Privacy's summary rows | `phase-5.7/phase-5.7-settings.png` | none | Three switches and summary rows ("3 built in · 164 995 rules · updated with Room"; custom rules; allowed sites), each list in a sheet | |
| ST3 | Privacy's sheets, the Safari-like site permissions | `phase-5.7/phase-5.7-settingssheets.png` | `ContentBlockingSheetMetrics` 540 × 480; `SitePermissionsMetrics` 640 × 420, types column 200 | Safari's Websites layout | |
| ST4 | Shortcuts' table | `phase-5.7/phase-5.7-settings.png` | `ShortcutsSettingsMetrics.margin` 20 (12 between the lines), `rowHeight` 34, `keyColumnWidth` 120, `resetColumnWidth` 28 | Bordered full-width table, no ◆ (a reserved action's tooltip says so) | |
| ST5 | The app icon's slots | `phase-5.2/phase-5.2-icon.png` | `App/Resources/AppIcon.icon` and its alternates | Your icon in every slot; no placeholder | |

## Space window and onboarding

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| W1 | The space window's sections and order | `phase-5.2/phase-5.2-spaceform.png` → `phase-5.7/phase-5.7-spaceform.png` | `SpaceWindowMetrics.width` / `height` / `minHeight` 420 / 640 / 360; `SpaceFormMetrics` padding 12, icon cell 26, preview 18 | Name, Icon, Colour, Profile, Routes | |
| W2 | Save versus applying as you go (5.7b deviation 1) | `phase-5.7/phase-5.7-spaceform.png` | none | Save/Create (Return), Esc and the close button cancel; routes written as they change. Live apply would also have to apply a profile change with its warning | |
| W3 | The tint opacity slider (B-23) | `phase-5.2/phase-5.2-spaceform.png`, `phase-5.7/phase-5.7-spaceform.png` | `TintOpacityControl` 0–100 % → `Materials.tintOpacityRange` 0.10–0.25 | Under the algorithm in Colour | |
| W4 | A swipe past the last space (5.7b deviation 2) | none | Swipe threshold 0.25 widths; rubber band bounded at 0.15 widths | Rubber band at both ends; a release past the threshold opens the space window (spec §B's sliding form superseded by B-122) | |
| W5 | Onboarding's steps and words | `phase-2.8b/phase-2.8b-firstrun-*.png` → `phase-5.7/phase-5.7-onboarding.png` | `OnboardingMetrics.width` / `height` 560 × 440; `padding` 24, `symbolSize` 40, `dotSize` 6; inactive dots 0.35 | Welcome, import, default browser, theme, search with the two opt-ins; Skip Setup on every step | |
| W6 | The theme swatches | `phase-5.7/phase-5.7-onboarding.png` | `OnboardingMetrics.themeSwatches` none, #1E88E5, #3E9B5B, #E53935, #8E24AA, #FB8C00, #546E7A; `swatchSize` 28, `swatchRingWidth` 2, `emptySwatchAlpha` 0.15 | Six colours and none | |
| W7 | An essentials step (5.7b deviation 6) | none | none | Not built (ROADMAP: "a theme or essentials step"); the theme step was | |
| W8 | The import sheet's look, Arc's import (Chapter 4 steps 20, 23, 29) | `phase-5.7/phase-5.7-onboarding.png` (the import sheet) | `ImportSheetMetrics` 580 × 640 (580 × 760 as 5.7b measured it) | Unchanged since 4.3a | |

## Motion

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| M1 | The hidden sidebar's reveal (B-114) | `phase-5.1/phase-5.1b-reveal.png` | `Timing.revealDwell` 0.06 s, `revealGrace` 0.15 s; `Motion.revealIn` 0.18 s ease-out, `revealOut` 0.15 s ease-in; `RevealMetrics.edgeBand` 4, `overlayInset` 10 | Band to in place 282–292 ms median (was ≥ 400); Reduce Motion a fade | |
| M2 | The traffic lights with the hidden sidebar (B-114) | `phase-5.1/phase-5.1b-reveal.png` | Fade in over `revealIn` ease-in, out over `revealOut`; `Motion.fast` on ⌘S | No pill; the lights come and go with the overlay | |
| M3 | The Essentials grid's reflow (5.1a deviation 6) | none (motion harness; feel in the app) | `Motion.standard` 0.15 s ease-out | When the grid loses a row, the list moves up with the tiles and lies over the footer for 150 ms | |
| M4 | The ⌃Tab switcher's fade (5.1b deviation 3) | none | `Motion.fast` 0.12 s ease-out; `Timing.tabSwitcherDelay` 0.12 s | A fade-in added (the spec gives the switcher none); it goes at once | |
| M5 | A split's creation and layout changes (5.1b deviation 2) | none | `CardMotion.splitLayout` instant | Instant: a page resized each frame relays out each frame | |
| M6 | Reduce Motion for rows, the pill, folders and the grid (5.1a deviation 2) | none | `SidebarMotion` variant `instant` | Instant, not the spec's crossfade (`NSOutlineView` has no insert without the slide); fades stay fades | |
| M7 | Haptic ticks, too many or too few (Phase 5.5 step 3 j) | `phase-5.5/phase-5.5b-drop-sidebar-line-{light,dark}.png`, `phase-5.5b-split-snap-light.png` | `Haptics.alignment()` per insertion-line move, target row, Essentials slot, space icon slot, and the split's equal point (0.497 → 0.500 snaps, 0.503 does not) | Ticks on alignment only; hover 0 | |

## Accessibility modes

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| A1 | Rows in the four modes | `phase-5.3/phase-5.3-rows-modes.png` | Increase Contrast: `Palette.hairlineHighContrastAlpha` 45 % light / 50 % dark, `sidebarSecondaryHighContrastAlpha` 80 % / 85 %; Reduce Transparency: `Materials.solidFill` (`windowBackgroundColor`); Differentiate Without Colour: `ChangedMark` 9 pt with a 1.5 pt ring (6 pt normal), audio glyphs in a circle | As listed | |
| A2 | Header in the four modes | `phase-5.3/phase-5.3-header-modes.png` | As A1 (hairlines, solid fill) | As listed | |
| A3 | Palette in the four modes | `phase-5.3/phase-5.3-palette-modes.png` | As A1 (solid fill under the glass) | As listed | |
| A4 | Toasts in the four modes | `phase-5.3/phase-5.3-toasts-modes.png` | Reduce Transparency: a solid capsule with a hairline | As listed | |
| A5 | Sidebar text small, medium, large | `phase-5.3/phase-5.3-{rows,header,palette,toasts}-sizes.png` | `TextScale` ×12/14, ×1, ×16/14; `Typography.sidebarRow` 12 / 14 / 16; `sidebarSecondary` 9.5 / 11 / 12.5; `paletteField` 15.5 / 18 / 20.5; row heights 31 / 36 / 41 | Medium default | |
| A6 | What follows the sidebar's size (B-137) | `phase-5.3/phase-5.3-*-sizes.png` | Not scaled: the Library, the folder preview, the media row, the footer's space name, the Essentials' empty label, the ⌃Tab switcher (`Typography.row` / `secondary`) | Not following | |
| A7 | Increase Contrast in dark: fade the tint too? (B-138) | `phase-5.3/phase-5.3-rows-modes.png` | `Materials.tintOpacityRange` lower bound 0.10 | Tint unchanged: secondary 4.7:1, primary 4.67:1 at the darkest tint's highest opacity | |
| A8 | Focus rings' shapes | `phase-5.3/phase-5.3a-focus-{address-field,back,outline,space-icon}.png` | `FocusRing.controlCornerRadius` 6, `pillCornerRadius` 12; rows `SidebarMetrics.insertionLineWidth` 2 in the accent | Icon buttons' ring is their hover square | |

## Passwords popover

| # | Item | Capture | Token(s), current value | Provisional choice | Your call |
|---|---|---|---|---|---|
| PW1 | The save offer on the site button | `phase-5.8/phase-5.8a-passwords-{light,dark}.png`, `phase-5.8a-password-save-*.png` (branch `phase-5.8a`) | Width `PromptMetrics.permissionWidth` 360; insets `Spacing.l` 16, spacing `Spacing.m` 12; title `Typography.headline` 13 semibold; username and bullets `Typography.row` 13; `Symbol.password` (`key.fill`, secondary) | "Save password for “site”?"; Never for This Site left, Not Now and Save (Return) right, Manage Passwords… (`Typography.secondary` 11, link colour) under them | |
| PW2 | The update offer | `phase-5.8/phase-5.8a-password-update-*.png` | As PW1 | Update the default button, no Never | |
| PW3 | The saved toast | `phase-5.8/phase-5.8a-password-saved-toast-*.png` | `Timing.toastWithAction` 5 s | "Password saved for host" · Manage | |
| PW4 | The popover with the sidebar hidden | `phase-5.8/phase-5.8a-password-save-sidebar-hidden-*.png` | none | At the card's top-left corner, inside the card | |

Real sign-ins reach PW1–PW4 only after the engine half (the `//room` adapter); until then real pages show Chrome's Views bubble.

## Not on this list

- B-150 (⌘M with the sidebar hidden, "5.8 (iteration)") is a bug, not taste.
- The click checks and hardware runs of `chapter-5-by-hand.md` (the 120 Hz runs, VoiceOver, input methods, the gesture script's drags) check behaviour; their marks belong there.

5.4b, 5.8 (5.8b's bubbles and its review sheet) and 5.9 (the tour and the release) may add items.
