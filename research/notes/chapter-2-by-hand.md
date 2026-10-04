# Chapter 2 — the by-hand pass (Phase 2.9)

One ordered list for the user's pass over spec §A–I on one Debug build and one state directory (ROADMAP 2.9 task 1, a day at most). It merges every step of the try-lists from 2.4b to 2.8b in `docs/progress.md`, grouped by feature as in 2.8b's "Where each feature starts", with that list's entry points for the features the earlier lists covered (2.2–2.4a), each once. The tag after a step is the list it came from. Everything the grand tour already checks without a person (`scripts/grand-tour.sh`, `spike-results.md` "Phase 2.9 — grand tour") is not repeated here; these are the steps that need a pointer, a trackpad, a key on the real keyboard, another app, a device, or eyes.

Friction goes into `docs/backlog.md` as a new row with source **"2.9 by-hand"** (what you did, what happened, what you expected). Use accounts you can afford to expose on disk: a Chapter 2 build keeps cookies under CEF's mock-keychain key (ROADMAP Chapter 2, CEF caps).

## Setup

1. Build once: `xcodegen && xcodebuild -scheme Room -configuration Debug -derivedDataPath build/DerivedData build` (note `git rev-parse --short HEAD` in the backlog rows).
2. In a second terminal: `scripts/test-servers.sh` (127.0.0.1:8765, :8766, :8767, :8770, :8771; Ctrl-C stops them). Steps marked **[S]** need it.
3. First launch, once (the `spaces` fixture: the demo sidebar in "Space", plus Work in its own profile, Reading and Music; the first-run card):
   `build/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-2.9 -RoomEngineDirectory /tmp/room-2.9/engine -RoomSidebarFixture spaces -RoomFirstRun YES`
4. Every later launch (same state, no card): `build/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-2.9 -RoomEngineDirectory /tmp/room-2.9/engine`
5. Do the pass in light, then repeat the steps marked **(L/D)** in dark (Settings ▸ Appearance, or System Settings).

## First run (at the first launch)

1. The card above the footer: change the search engine, tick and untick both checkboxes, Done (the card fades) — 2.8b (e)
2. Settings ▸ General ▸ Show Welcome Card brings it back with the choices kept; Done again — 2.8b
3. Settings ▸ Privacy ▸ Check Now (Sparkle's error for the placeholder feed is expected) — 2.8b (e)

## Sidebar (§A)

1. Click entries in "Space": the pill slides, each page loads once, switching back is instant, the card follows the page's background — 2.3
2. Follow a link inside a pinned entry, then click the selected entry (reset) and ⌘-click it (the page continues as a Today tab) — 2.2a
3. Hover the changed row with and without ⌘ (reset button, sublabel) — 2.2a
4. Middle-click a pinned entry, a Today tab and an essential — 2.2a
5. Double-click a title and Enter on a selected row (rename, pulse, toast); Tab ▸ Rename… with the sidebar docked and hidden — 2.2a, 2.8a
6. Right-click each kind (essential, pinned, folder, Today); Edit Pinned URL… with "not a url"; Duplicate, Unload, Reset Pinned Tab from the Tab menu — 2.2a, 2.8b
7. Drag a pinned row up and down (line, haptic tick, lifted row), a Today tab into Pinned and back, one onto the Essentials grid — 2.2b
8. Add essentials until 12 and drag another (badge, shake) — 2.2b
9. Hold a row over the middle of "Reading" for half a second (drops in); over a pinned entry (new folder, renamed inline) — 2.2b
10. ⌥-drag a tab (copy); drag a link from Safari and some text from TextEdit onto the sidebar — 2.2b
11. ⌘-click two Today tabs, ⇧-click a third, drag the group, right-click it, press Delete — 2.2b
12. ⌘D, ⇧⌘D, ⇧⌘K on the selected tab; Undo in Clear's toast — 2.2b
13. Click a row, then ↑/↓/→/←/Enter/Esc; scroll the selected row out of view and click the accent line — 2.2b
14. Double-click below the rows (new tab); rest the pointer on "Archive" (folder preview: type, ↑/↓, Enter) — 2.2b
15. ⌘W on a Today tab (the most recent other tab is selected, not the neighbour), ⇧⌘T (back where it was) — 2.3
16. ⌘W on a pinned entry after following a link inside it (unloads, resets); ⇧⌘T brings the deeper page back — 2.3
17. ⌘-click two links in a page (background tabs below it, in order) and a `target=_blank` link (below, selected) — 2.3
18. Hold ⌃ and press Tab a few times (the list over the card), W on a row, release ⌃; Tab ▸ Switch to Recent Tab — 2.3, 2.8a
19. ⌘1, ⌘9, ⇧⌘], ⇧⌘[, ⌥⌘↓, ⌥⌘↑ — 2.3
20. Play a video and press ⇧⌘M (the row's speaker) — 2.3
21. Close every tab of a space until the card says "Press ⌘T to search or type a URL" — 2.3

## Spaces (§B)

1. Click the footer icons (lists slide, tint crossfades, highlight slides; Work shows its own essentials L/G); hover them (name on the right) **(L/D)** — 2.5
2. ⌃1…⌃4 and ⌥⌘←/→ from a page with focus (wraps) — 2.5
3. Two-finger swipe over the sidebar slowly (lists follow, release before a quarter returns, a flick switches, the first space rubber-bands, past the last the New Space form slides in) — 2.5
4. ⌃ + mouse wheel over the sidebar — 2.5
5. Reduce Motion on, switch spaces (crossfade); off again — 2.5
6. Click the space title's name (rename); its "…" and a right-click (menu) — 2.5
7. Change Icon…; Edit Theme… (colours in the wells, change the algorithm: the window previews; Esc restores) — 2.5
8. New Space from "+" and from File ▸ New Space, Enter — 2.5, 2.8b
9. Set Profile ▸ New Profile… on a space with tabs (the warning once; pages reload); sign in somewhere, check the other profile's spaces stay signed out — 2.5
10. Drag a Today tab onto another space's icon (drop: it moves; hold: the space opens and the drop lands in its list) — 2.5
11. Drag a space icon along the row (reorder, haptic ticks) — 2.5
12. Delete Space… then Undo in the toast — 2.5
13. ⌘T in Work and type a site visited only in Default (no history row) — 2.5

## Palette (§C)

1. ⌘T over a page (glass panel scales in), type "ar" (top hit, open tab, pinned and essentials), ↑/↓, ⇥/⇧⇥, pointer over rows, click a row, ⌘-click a row (a copy opens) — 2.4a
2. ⌘T "example.com" with Enter, ⌘Enter, ⌥Enter (new tab / current tab / background) — 2.4a
3. ⌘L (URL selected), Enter (reload); type, click outside, ⌘L within 45 s (text back) and after 45 s (the URL) — 2.4a
4. Click the header's address field (docked), ⌘S then ⌘L (centred); ⌘T ⌘T and ⌘L ⌘T (closes); after closing, type into a page field (focus back in the page) — 2.4a
5. Visit a few sites through ⌘T, then ⌘T and type the start of one (inline completion; →/End accepts, Backspace removes it and it does not come back on that text) — 2.4b
6. ⇧Delete and ⌘⌥Delete on a history row, and its × on hover — 2.4b
7. ⌘T ⇥ (commands), `>re`, Enter on Reload; File ▸ Commands… — 2.4b, 2.8a
8. `yt` ⇥ `lofi` Enter (YouTube results), Backspace on the empty chip; once each `wiki`, `gh`, `maps`, `ddg` ⇥ — 2.4b, 2.8b
9. Type a query and pause (suggestions join the search group, the highlighted row stays put) — 2.4b
10. With suggestions showing, ⌘, ▸ Search ▸ "Show search suggestions" off (the rows go at once), type again (none appear); on again — 2.4b
11. Copy a URL in another app, ⌘T (Paste and Go, no paste prompt until Enter), Enter — 2.4b
12. ⌘Y (recent history) — 2.4b
13. A Lithuanian layout and an IME in the field; light/dark with the chip shown **(L/D)** — 2.4b

## Split view (§D) [S]

1. Open three tabs on http://127.0.0.1:8770/site.html and http://localhost:8770/site.html — 2.7b
2. Drag a row into the card and hover each edge and the centre (the preview, then the drop) — 2.7b
3. Drag a row onto another row's centre and hold 500 ms (join) — 2.7b
4. ⌥-click the selected row, another row, the group row — 2.7b
5. Right-click ▸ Split With ▸; ⌘-click two rows ▸ Join 2 Tabs — 2.7b
6. Pointer to a pane's top (the header): drag the grip onto another pane, the layout button, × — 2.7b
7. Drag a resizer and double-click it; click between panes (the header field follows) — 2.7b
8. ⇧⌘= then Esc (the empty pane goes), ⇧⌘= then a URL; ⌃⇧- — 2.7b
9. ⌃⇧1…4, ⌃⇧] / ⌃⇧[, ⌥⌘G, ⌥⌘V, ⌥⌘U, Tab ▸ Split View ▸ Stacked (no key since B-36) on the laptop's keyboard layout — 2.7b, 2.8a
10. ⌘W on a pinned pane and on a Today pane — 2.7b
11. Peek from a pinned pane, then its Split button — 2.7b
12. A video's fullscreen button in a pane; hide the sidebar with a split **(L/D)** — 2.7b

## Hide and reveal (§E) [S]

1. Pin http://127.0.0.1:8770/site.html with ⌘D; View ▸ Hide Sidebar with a page focused, then ⌘S — 2.7a, 2.7b
2. Rest the pointer at the left edge (150 ms), move into the overlay, out over the page, out of the window toward the Dock (it stays) — 2.7a
3. Right-click a row in the overlay (stays while the menu is open); ⌥⌘S (stays until a click in the page); ⌘T from the overlay — 2.7a
4. Drag the splitter under 120 pt (the toast, once) — 2.7a
5. Drag the window by the pill and by the top of the page (a click there still reaches the page; try selecting text in that band, B-32); double-click the pill — 2.7a
6. Wait 2 s away from the pill (it fades with the buttons), come back — 2.7a
7. View ▸ Show Toolbar with the sidebar docked and hidden (Back, Forward, Reload, click the URL, drag the bar) — 2.7a
8. Settings ▸ Appearance ▸ Sidebar Right: drag the splitter (cursor directions at 180 and 500 pt), snap it closed, hover the right edge, the cluster, drag the window by it and by the card's top, View ▸ Show Toolbar, a split and Peek on the right; back to Left — 2.8a
9. ⌃⌘F and 🌐F; in fullscreen hover the left edge (reveal) and the top (menu bar); leave fullscreen — 2.8a
10. Reduce Motion on: hide, reveal, Peek (fades); off again — 2.7a

## Footer and toasts (§F) [S]

1. http://127.0.0.1:8766/downloads.html: click the 6 MB link (the icon flies from the click to the footer, the ring fills, it bounces with a badge) — 2.6b
2. The popover (⇧⌘J or the button): hover a finished row for Show in Finder, double-click opens, × cancels the 50 MB one, Clear; right-click the button **(L/D)** — 2.6b
3. Settings ▸ Downloads ▸ Change…, then Use the Downloads Folder — 2.6b, 2.8a
4. ⇧⌘C and ⌥⇧⌘C (toasts) — 2.6b

## Lifecycle (§H)

1. Debug ▸ Discard Background Pages (rows dim, a click reloads); Debug ▸ Simulate Memory Pressure (Console: "discarded … (memory pressure)") — 2.3
2. Quit and relaunch with the later-launch command (only the selected tab loads; others show their favicons dimmed) — 2.3
3. Auto-archive after 12 h is Chapter 4.1: not in this build — 2.8b

## Peek (§I.6) [S]

1. On the pinned site.html click each link and button (the table in `spike-results.md` 2.7a); ⇧-click a link — 2.7a
2. In Peek: scroll, click inside, click the dim, Esc, ⌘W, ⌘O, ⇧⌘O, ⇧⌘T, × and Open as Tab in its header — 2.7a, 2.8b
3. In Peek: Show an alert (the dialog in Peek's card), ⌘F — 2.7a
4. Right-click a link ▸ Open Link in Peek — 2.7a
5. Settings ▸ General ▸ Links off (off-site links navigate in place); on again — 2.7a
6. A focused pinned row (↑/↓ in the sidebar) + Space — 2.7a

## Page surfaces [S]

1. http://127.0.0.1:8766/dialogs.html: each button (sheet over the page, Return/Esc, a click on the dim does nothing, ⌘W still works) **(L/D)** — 2.6a
2. Switch tabs with a dialog open and back (it waits for its page) — 2.6a
3. Arm beforeunload, then ⌘W (Cancel brings the tab back) and ⌘R (Reload site?) — 2.6a
4. http://127.0.0.1:8766/auth: sign in with room / secret, Tab between fields; once with Cancel — 2.6a
5. https://127.0.0.1:8767/secure.html: Go Back, Show Details, Visit … Anyway; again in a new tab, Go Back (empty card, row "127.0.0.1") — 2.6a, 2.6b
6. permissions.html: the popover on the site button; a click elsewhere dismisses it; switch tabs while it shows — 2.6a
7. permissions.html: click the site button in the header (change Location, Reload, Clear…, Reset Permissions) — 2.6b
8. menu.html: right-click a link, an image, selected text and the field (Open Link in New Tab, Copy Link, Open Link in Peek) — 2.6a
9. files.html: each input, choose a file — 2.6a
10. popups.html: a popup and `target=_blank`, then Close this window — 2.6a
11. find.html: ⌘F, type, Return / ⇧Return / ⌘G / ⇧⌘G, Esc; switch tabs with the bar open and back — 2.6b
12. ⌘= ⌘- ⌘0 (hover the indicator: it stays); ⌘P (Cancel) — 2.6b
13. status.html: hover the links (600 ms, then the full URL), move toward the bottom-left pill (it jumps right) — 2.6b
14. fullscreen.html: Fullscreen, then Esc; once with the green button — 2.6b
15. `chrome://crash` in ⌘L, then Reload — 2.6b
16. ⌥⌘I, drag the divider, double-click it; ⌥⌘J; ⌥⌘C then click an element — 2.6b
17. ⌘← / ⌘→ on a page and inside a page's text field; ⇧⌘R; ⌘. while a page loads — 2.8a

## App integration

1. Open each menu from the menu bar with a page focused and with the palette open; hover the disabled planned items (tooltip) **(L/D)** — 2.8a
2. ⇧⌘W, then ⌘N (the window back) — 2.8a
3. File ▸ Open File… (an HTML file) — 2.8a
4. Settings: every control in every section (General, Appearance, Search, Downloads, Privacy); Appearance Light / Dark / System while a page shows — 2.8a
5. Room ▸ Set as Default Browser… (or Settings ▸ General ▸ Set as Default…) and confirm the system dialog; once with Keep "Chrome" (the item stays enabled, nothing changes) — 2.8b (a)
6. With Room the default: click a link in Mail, Notes or Messages (a Today tab in Room's window); ⇧⌘W and click another (the window comes back with it) — 2.8b (a)
7. Quit Room and click a link (cold launch). This launches Room without arguments, on the real state in `~/Library/Application Support/Room`, not /tmp/room-2.9 — 2.8b (a)
8. Room ▸ Check for Updates… (the placeholder feed's error) — 2.8b
9. Set Chrome (or your browser) back as the default when done.

## Measurements for the laptop's 120 Hz panel (not part of the pass; each on its own throwaway state)

1. B-16: `scripts/sidebar-snapshots.sh 500`, then a trackpad fling on the 500 fixture (`… -RoomSidebarFixture 500 -RoomStateDirectory /tmp/room-500`)
2. B-18: `scripts/tabs-measure.sh` with the screen unlocked and Room frontmost; `scripts/sidebar-snapshots.sh demo`
3. B-20: `scripts/run-spike.sh palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000`, without screen sharing
4. B-21: `scripts/run-spike.sh spaces -RoomSidebarFixture spaces500 -ApplePersistenceIgnoreState YES`, Room frontmost
5. B-26: http://127.0.0.1:8766/permissions.html camera and microphone with Allow This Time (the Mac mini has no devices); location: does the page read "granted" after Allow?

## Not by hand (the user's, outside the pass)

- The Sparkle private key to the release machine (`docs/setup.md` §5.4: `generate_keys -x` here, `-f` there).
- A Sentry project and its DSN in `ROOM_SENTRY_DSN` (`xcodegen/base.yml`).
- The product name and domain (B-6), then `ROOM_UPDATE_FEED_URL`.

## What the tour does not run, and why (none of it a bug)

The grand tour runs every Chapter 1–2 spike that exists as a spike. These checks are not spikes, or cannot run on this Mac in sequence; each is in this list or the measurements above:

- **RoomCore embryo spikes** (Phase 1.5 `nav`, `open10` on `RoomCoreHost`): another binary and engine, not the one Debug build; Chapter 3 runs the tour itself on `EngineRoomCore`.
- **The card-mask composite cost** (B-1, done): an Instruments Metal System Trace, not a spike.
- **Extensions and the autofill dropdown on CEF** (Phase 1.4): checked once with `--load-extension` and by hand; there is no spike, and both are CEF caps lifted in 3.6 and 3.7.
- **120 Hz numbers** (B-16, B-20, B-21): the Mac mini drives a 60 Hz display; the laptop's runs are listed above.
- **Camera and microphone prompts** (B-26): the Mac mini has no devices; the spikes run and record `NotFoundError` before any prompt.
- **Search suggestions from Google**: the tour sends its suggestion checks through the logging proxy on :8771 (on: three requests at the pauses; off: none), so no query leaves the Mac; real suggestions are step 9 of the palette list.
- **Pointer-only and system interactions**: trackpad swipes, drags into the card and between rows, window drags, the default-browser system dialog, links clicked in other apps, Reduce Motion, IMEs: the steps above.
