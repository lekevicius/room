# Spike results

Measurements and outcomes from Chapter 1 spikes. Numbers, not adjectives.

## Phase 1.3 — the window vs. Dia (2026-10-02)

Method: Room's DEBUG snapshot runner (`scripts/window-snapshots.sh`) captures the window with `CGWindowListCreateImage` on our own window (no Screen Recording permission needed; the symbol is unavailable in the Swift SDK since macOS 15 but still exported, called through `dlsym`, DEBUG builds only). The comparison state uses Dia's reference framing: 1244×818 pt window, 280 pt sidebar. Room captures are 2× and were downsampled to 1× to compare pixel rows with `research/screenshots/dia-window.jpg` (1× JPEG). Images: `research/screenshots/phase-1.3/`.

| Measure (1× px, light mode) | Dia | Room | Notes |
|---|---|---|---|
| Card left edge (first card pixel, y=400) | x=280 | x=280 | sidebar 280 in the compare state; default 240 |
| Card top edge (x=700) | y=6 | y=6 | ROADMAP guessed inset 8; token now 6 |
| Card bottom edge | y=811 (818−7) | y=811 | |
| Card right edge | x=1237 | x=1237 | |
| Corner: first card-fill pixel on the diagonal from the corner | k=3 | k=3 | continuous radius 10; at 12 Room reached fill at k≈3.75 |
| Shadow under bottom edge, y=812…816 | 216 217 223 227 230 | 216 217 221 224 226 | light opacity 0.15, radius 4, offset (0,−1); 0.10 gave 222 222 224 227 228 |
| Shadow left of card, x=278…279 | 219 223 | 220 219 | |
| Traffic lights, close button left edge / zoom right edge | 17.5 / 78.5 | 18.5 / 79.5 | AppKit's own placement with an empty unified toolbar; never moved |
| Traffic-light centre line | y≈27 | y=26 (19+7) | |
| Space-title first glyph column (13pt semibold) | x=93–94 | x=93–94 | label frame at zoom maxX + 12 |
| Title glyph rows | 22–31 | 21–30 | 1 pt higher, following the traffic-light centre line |
| Material at (140,400) | 227 | 233 | backdrop-dependent: Dia's capture blurs a window behind it; own-window capture renders the material without the desktop backdrop |

Traffic lights without a toolbar sit at (9,9) in content coordinates (60×14 pt union, 23 pt pitch), 9–10 pt off Dia's. With an empty `NSToolbar` and `toolbarStyle = .unified` they sit at (19,19): AppKit's 52 pt titlebar layout. This is the chosen fix; no frame is set on any button.

Other findings:
- Clicks in the 52 pt toolbar band over the card hit-test to the card's subtree, not the titlebar (`RoomWindowControllerTests.titlebarHitTesting`). An NSScrollView in the card (FakeEngine page) shows no macOS 26 scroll-edge effect under the empty toolbar.
- Dark + inactive: the flat inactive dark material is luma ~40; a card fill of 30 left 10 levels of contrast and the snapshot test's corner/inset checks failed. Card fill in dark is now rgb(24,24,25) (luma 24): 16 levels inactive, ~46 active.
- `NSApp.activate()` from a script-launched app is refused while the user is working in another app (cooperative activation, macOS 14+). The runner retries until the window stays main for the whole capture, and the script also activates it via AppleScript; inactive states use a second window of ours taking main instead of deactivating the app (deactivation got undone mid-run twice). `states.txt` records `appActive`/`main` per capture.
- Sidebar header title: a truncating `NSTextField` under-reported its intrinsic width (55 pt for "Personal", needs 59); sized from `cell.cellSize` instead.
