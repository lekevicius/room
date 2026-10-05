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

## Phase 1.4 — CEF inside the card: spike checklist (2026-10-02)

Engine: CEF 154.0.32 (Chromium 154.0.8037.58), Alloy-style child browsers, Debug build unless noted. Method: `App/Sources/Debug/SpikeRunner.swift` (`scripts/run-spike.sh <name>`) drives each measurement through the `Engine` protocol (CEF-specific CDP only where noted) and writes `key: value` lines; test pages are in `research/spikes/phase-1.4/`; interactive checks used real keystrokes/pointer events from the computer-use tool. Load average is recorded per run: this machine was never idle (the user's Chrome, Zen, Claude, Spotlight and CloudMounter kept it at 12–233 during the session).

Summary: 14 items, 11 green, 3 amber (each with a fallback), 0 red.

| Item | Result | Status |
|---|---|---|
| Clipping | Page clipped at the card radius: on a page painting `#d0105a` to its edges, the first page-fill pixel on the corner diagonal is at k=3 at the top-right and bottom-left corners (Dia and the Phase 1.3 empty card: k=3). The 1 px edge row is greyed against the interior (`174,69,102` vs `193,45,93` at x=700; `182,78,111` vs `191,45,90` at y=400), so the `CALayer` border composites above Chromium's layer. Scrolling a 400-row page with an rAF-driven scroll for 3 s: mask on 120.3 / 120.0 fps, 0 frames > 12.5 ms (median 8.30 ms, p95 9.2 / 9.1 ms); mask off 120.0 fps, 1 frame > 12.5 ms (max 16.7 ms); load 30–44. **Not measured:** whether the IOSurface still scans out without an extra composite — Quartz Debug is not installed (Xcode 27 ships no Additional Tools here). Captures: `phase-1.4-clipping-corners.jpg`, `phase-1.4-dia-corner-zoom.png` | amber (no Quartz Debug); fallback: Chromium-side `RoundedCornersF` on the web contents layer in RoomCore (PLAN §7 risk 1) |
| Empty toolbar vs. page | Clicks at window y=14 and y=40 (inside the 52 pt toolbar band, over the card) arrive in the page at y=8 and y=34. With the page scrolled under the band the row colour is uniform (`250,234,175`) from y=9 to y=75: no scroll-edge effect, separator or tint. Fullscreen: AppKit moves the toolbar into its own 1728×52 window that slides down with the menu bar; the controller now hides the toolbar on `windowWillEnterFullScreen` and restores it on `windowWillExitFullScreen`, after which the strip window is 1728×32 (AppKit's standard fullscreen titlebar with the traffic lights). Header falls back to the 16 pt inset in fullscreen (seen on the fullscreen Space) | green, with the planned fullscreen fallback applied |
| Live resize | `PageHost` binds `CardView.backgroundColor` to `rootBackgroundColor` (Wikipedia: `0.973 0.976 0.980`, read via `getComputedStyle` after `OnLoadEnd`). 24 width steps of 10 pt, capture right after each step, 3 insets × 8 rows at the card's right edge: the colour inside the card was the page colour `248,249,250` in 576/576 samples — also with the card fill cleared, because Chromium's own view layer carries the page background in the AppKit tree. Only a page with no background over a clear card shows the material (`198,198,198`). Page frame intervals during 60 resize steps every 16 ms: median 8.30 ms, max 10.4 ms, 0 > 17 ms; main-thread `setFrame` median 1.45 ms | green |
| Overlay z-order | `NSGlassEffectView` overlay above the card: real pointer hover → "Hovering", two real clicks → "Clicked 2×", the page under it received none of them (`__clicks` unchanged); the glass refracts the page content under it. Hover-reveal: with a local `mouseMoved` monitor, a real pointer sweep across the page to the 4 pt edge band revealed a 260 pt glass sidebar sliding over the card after the 150 ms dwell; moving right hid it. The per-event count of moves seen over the web view was not recorded (the second screen-takeover was not approved); Chromium's view receives `mouseMoved` through `NSApp.sendEvent`, where the local monitor sits | green |
| Keyboard | Real keystrokes (background raw input, active layout Colemak): ⌘T opened a page and ⌘L focused the address field without the page logging either; ⌘W closed the page through the engine (`CloseBrowser` → our `DoClose`) and the window stayed open; ⌘A, ⌘Z reached the page and acted (selection 0–19; typed letter undone). In-app events built with each layout's own characters (`UCKeyTranslate` on ABC, Colemak and standard Lithuanian data, sent through `NSApp.sendEvent`): reserved ⌘T/⌘L classified as reserved in all three; ⌘C copied the selection to the pasteboard (`"select me and copy"`), ⌘V pasted, ⌘Z undid, each seen by the page first (`⌘c/KeyC`, `⌘v/KeyV`, `⌘z/KeyZ`) then executed by the Edit menu. ⌘ + number row gives `1…9` in all three layouts. ⌘` with the About panel open moved key focus to the panel (real keystroke). Note: AppKit's menu matching re-translates key codes through the *active* input source, so a synthetic event for a non-active layout is classified correctly but its menu dispatch fails; real events always come from the active layout | green |
| Popups | `target=_blank` and `window.open()` (CDP clicks = user gestures) arrive as `didCreate(_:targetURL:disposition:)`; the bridge parks the popup in an off-screen window and the delegate re-parents its view into the card; both loaded (`title=Popup target`, in window). Chromium blocks renderer-initiated top-level `data:` navigations, so test targets are file pages. `<select>` popup: offset from the element's bottom-left (−12, −25) both before and after moving the window by (+140, −90) pt; date picker (`showPicker()`): offset (0, −1) before and after. JS `alert()` reached the delegate as a sheet and completed | green |
| DevTools | `ShowDevTools` with a parent view hits a `DCHECK` and crashes on CEF 154 macOS (DevTools is always Chrome style; Chrome style refuses a native parent, CEF #3294) — this was the crash the user reported. Docked DevTools is now our own Alloy browser in the pane loading `devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:<port>/devtools/page/<targetId>` over the remote-debugging port (Debug builds, 127.0.0.1, `--remote-allow-origins=devtools://devtools`). Opens in 23 ms; inspect-element (`DOM.getNodeForLocation` on the page + `Common.Revealer.reveal` in the front-end) selected the `<select>` under the point after 10.8 s (front-end attach time); closes cleanly (front-end closed, page alive, pane gone). Without the port, CEF's own top-level DevTools window | green (docked pane needs the debug port; Release falls back to the separate window) |
| Memory | Hidden browsers (created hidden, never shown) on 10 rotating typical sites, RSS summed over Room + helpers with `ps`: baseline (one blank page) 670 MB / 6 processes; 1 hidden: 863 MB, +193 MB; 10 hidden: 3944 MB, +327 MB each, 18 renderers, 8/10 finished loading within 98 s; 30 hidden: 7921 MB, +242 MB each, 40 renderers, 27/30 loaded. RSS double-counts shared pages. Load average 96 at the start of the run. Hidden pages: `visibilityState=hidden`, 1 rAF/s (visible: 123/s); a page removed from the card goes back to hidden, 1 rAF/s | green (numbers recorded) |
| Extensions | `--load-extension` with an unpacked MV3 extension: the content script ran (`data-room-spike-extension` set on the page), the service worker started ("installed" logged). The extension's `popup.html` loads when navigated browser-initiated (renderer-initiated → `chrome-extension://invalid`); there `chrome.tabs.query({})` returns `[]`, `chrome.windows.getAll` returns 0 windows and `chrome.action.openPopup()` fails with "Could not find an active browser window". `chrome://extensions` is blocked ("Navigation to chrome://extensions/ is blocked in Alloy-style browser"). No toolbar/action UI, as expected | green (behaviour recorded; caps as expected) |
| Autofill dropdown | On `file://` nothing is stored. Over `http://127.0.0.1:8765`, after one submit the `autofill` table holds the name and email entries, and typing "R" in the name field opens Chromium's autocomplete dropdown (a 164×58 window at layer 999 with the "Room Spike" suggestion), 1 pt below the field's bottom edge, 95 pt right of its left edge (anchored near the caret). Address/password *save* prompts: none (Alloy) | green |
| Signing | `scripts/sign-and-notarize.sh` signs inside-out (framework dylibs → framework → helpers → app) with `Developer ID Application: Jonas Lekevicius (N56PMJ99UT)`, hardened runtime, timestamp: 6.7 s; `codesign --verify --deep --strict` passes; Gatekeeper: "Unnotarized Developer ID". The signed Release build runs (GPU, renderers, network) with `allow-jit` on Renderer/GPU only; the base helper, which hosts the GPU process on M154, runs without `allow-jit` (gpu crash count 0). Zip for notarization 144 MB. **Notarization not run:** no stored credential profile (`notarytool store-credentials` needs the Apple ID password, which only the user can enter). Also found: a signed CEF build prompts for the login-keychain password over an existing "Chromium Safe Storage" item; CEF 154's stable API cannot rename the item, so CEF builds now always use the mock keychain | amber (notarization blocked on credentials); fallback: user runs `xcrun notarytool store-credentials room --apple-id … --team-id N56PMJ99UT` once, then `scripts/sign-and-notarize.sh` |
| Shutdown | `scripts/quit-timing.sh`: ten loaded pages (one visible, nine hidden), 23–24 helper processes, AppleEvent quit (the ⌘Q path through `terminate:` → `TryCloseBrowser` on every browser → last `OnBeforeClose` → `CefQuitMessageLoop`): 0.54 / 0.66 / 0.60 s, 0 helpers left, 0 crash reports, at load 34.9 / 40.1 / 38.4. Load under 5 never occurred during the session; these are upper bounds | green (< 1 s even under load) |
| CDP channel | On a live Wikipedia page: `Runtime.evaluate` round trip median 0.21 ms, p95 0.40 ms, max 1.72 ms (n=100); `Page.captureScreenshot` (1034×788 pt, PNG) median 126 ms, p95 133 ms (n=20). `Emulation.setDefaultBackgroundColorOverride` (alpha 0): the page paints only its own box (CDP capture `phase-1.4-transparent-cdp-capture.png`), the card shows the window material (`phase-1.4-transparent-background.png`). Resize cost transparent vs opaque: page frames median 8.30 ms both, 0 > 17 ms both; main-thread `setFrame` median 1.57–1.86 ms vs 1.45 ms. Bridge fix: CEF can deliver a method result synchronously inside `ExecuteDevToolsMethod` (seen for `Target.getTargetInfo`), so the bridge allocates the message id and registers the callback before sending | green |
| Audibility | `GetAudioParameters` returning `false` fires on every new stream: `<audio>` play → audible edge after 374 ms (first) and 91 ms (second play); Web Audio oscillator → 94 ms. The JavaScript poll of media elements (0.5 s interval for the spike, 1 s default) reported "stopped" 88 ms and 45 ms after `pause()`, within 2 s; poll cost median 0.12 ms, p95 0.21 ms. The poll cannot see Web Audio: with an oscillator still playing it reported silent within 2 s (false negative) | amber for Web Audio; fallback: `isAudible` is reliable for media elements; for Web Audio it shows only the "became audible" edge until RoomCore (`OnAudioStateChanged`) |

Other findings:
- Own-window captures (`CGWindowListCreateImage` on our window) do **not** include Chromium's GPU-process layer: the card shows only the AppKit layers under it. Page-in-card screenshots were therefore taken from outside (computer-use window capture, 1× JPEG, which needs Screen Recording permission); the Phase 1.3 snapshot runner keeps working for chrome-only states. `screencapture -l` from the shell failed (no permission).
- Page visibility follows window occlusion: a Room window behind other apps reports `visibilityState=hidden` and 0 rAF; frontmost, 121 rAF/s on the 120 Hz panel.
- `CefRequestContext` cache paths must be a direct child of `root_cache_path`; `<root>/Profiles/<name>` silently fell back to an off-the-record profile (`chrome_browser_context.cc`: "Cannot create profile at path"). Profiles now live at `<root>/Room Profile <name>`.
- `DoClose` returning `false` makes CEF send `performClose:` to the NSWindow hosting the view; child browsers return `true` and remove their host view instead.
- Alloy loads ⌘-click/middle-click links in the *current* browser unless `OnOpenURLFromTab` cancels; `CEFWebContents` cancels and opens new contents with the requested disposition.
- Chromium's net error pages render for failed loads (seen: `ERR_BLOCKED_BY_CLIENT` page); no custom error page needed.

Page-in-card vs. Dia (`phase-1.4-light-page-dia-compare.jpg`, `phase-1.4-dia-side-by-side-light.jpg`, `phase-1.4-dark-page-dia-compare.jpg`), 1× luma at Dia's framing (1244×818, 280 pt sidebar):

| Pixel | Dia | Room light | Room dark |
|---|---|---|---|
| x=279 / 280 at y=400 (card left edge) | 223 / 247 | 220 / 244 | — / 215 |
| y=5 / 6 at x=700 (card top edge) | 223 / 251 | 223 / 244 | — / 234 |
| x=1237 / 1238 at y=400 (card right edge) | 249 / 221 | 245 / 219 | 232 / — |
| y=811 / 812 at x=700 (card bottom edge) | 251 / 216 | 243 / 216 | 233 / — |
| (140, 400) material | 227 | 233 | — |

Card edges, corner and traffic-light/header positions match Dia to the pixel; the material differs by 6 levels (backdrop-dependent, as in Phase 1.3); edge pixels differ by 3–8 levels because the hairline sits over different page colours (Dia's in-card toolbar vs. Wikipedia's #f8f9fa).

## Phase 1.5 — RoomCore embryo (2026-10-02/03, Mac mini M4)

The branded fork (`Room.app`/`RoomCore.framework` from `out/dev`, component build) drives the Phase 1.3 window from the Swift host `RoomCoreHost`. Timings in `build-log.md` ("Mac mini (M4)"). Screenshot: `research/screenshots/phase-1.5-roomcore-window.jpg` (Wikipedia in the card, taken with window-level capture after the user granted access).

| Check | Result |
|---|---|
| Page renders in the Phase 1.3 window | yes: `WebContentsViewCocoa` inside the card, 991×758 pt; real clicks, mouse moves and scrolling in the page; Chromium's accessibility tree is exposed to AX clients |
| Navigation through `RoomWebContents` (`-RoomSpike nav`) | load, back, forward, reload all report the right URL/`canGoBack`/`canGoForward`; KVO `isLoading` fires on reload |
| Ten typical sites (`-RoomSpike open10`) | 12 s to all loaded at load 8–13; 24–35 helpers; browser RSS 329–443 MB |
| Quit (⌘Q path, 10 pages) | 0.18–0.55 s at load 8–16, 3.24 s once at load 69; exit 0; no helpers left beyond Chrome's `code-sign-clone-cleanup` (gone 1.4 s after the browser); no crash reports |
| `BrowserWindow` stubs Chrome called over ten sites | 12 of 68: `GetCanResize GetRestoredState GetStatusBubbles GetWindowShowState GetWorkspace IsVisibleOnAllWorkspaces OnTabDetached ResetToolbarTabState UpdateLoadingAnimations UpdateReloadStopState UpdateToolbar UpdateToolbarSecurityState` (real: 22) |
| `AsBrowserView()` | 1 non-test reference on M154 (Phase 1.5 first session); none hit |
| Keychain | patch 0002 works: the item is "Room Safe Storage", account "Room". Ad-hoc builds get a new code identity per build, so the second build's read of the item waits on a login-password prompt; the cookie store needs that key and **every navigation stalls** at `URL_REQUEST_START_JOB` until it is answered (net-log: `COOKIE_PERSISTENT_STORE_LOAD` never ends). Ad-hoc RoomCore builds now pass `--use-mock-keychain`; team-signed builds use the real keychain (not yet exercised: needs the user at the keychain/codesign prompts) |
| Network calls nobody asked for | on launch: component updater (`update.googleapis.com`, `edgedl.me.gvt1.com`), `accounts.google.com/ListAccounts`, `www.google.com/async/folae`; conflicts with the no-unrequested-network rule: Chapter 3 (prefs/switches or `//room` hooks) |
| TLS | ~220 `ssl_client_socket_impl.cc handshake failed … net_error -107` lines over ten sites; every page still loads. Not investigated (candidate: background Google endpoints) |

Failures found on first contact with a non-Views `BrowserWindow`, each fixed (all in `//room` unless noted):
1. `-Wobjc-missing-property-synthesis` is an error in Chromium: explicit `@synthesize`.
2. `Browser::Create` is private on M154: `CreateBrowserWindow(BrowserWindowCreateParams)`.
3. `CanResize` is an Android-only `BaseWindow` member: the stub generator now drops other platforms' `#if BUILDFLAG(IS_…)` blocks.
4. Swift naming `RoomHostApplication.self` runs `+[BrowserCrApplication initialize]`, which reads `base::CommandLine` before `-run` created it: `+[RoomApplication initialize]` inits it from the process argv; `-run` re-inits with the full argument list.
5. The host created AppKit controls before RoomCore created `NSApp`, so a plain `NSApplication` existed and Chrome's CHECK fired: host builds its UI lazily.
6. `ReadAnythingSidePanelController` CHECKs `IS_TEST` when a browser has no side panel: patch 0005 (upstream already exempts its WebUI browser there).
7. `Browser::OnTabDeactivated` dereferences `GetLocationBar()`: `RoomLocationBar`, a no-op `LocationBar`.
8. `~ContextualTasksCloseButtonController` touched a destroyed side-panel entry: `~RoomBrowserWindow` calls `BrowserWindowFeatures::TearDownPreBrowserWindowDestruction()` as `BrowserView` and `WebUIBrowserWindow` do.
9. `AppController windowDidBecomeMain:` builds a `BookmarkMenuBridge` from the main menu's `IDC_BOOKMARKS_MENU` item and CHECKs it: `RoomCrApplication -setMainMenu:` adds a hidden empty Bookmarks item.
10. Mouse input calls `ExclusiveAccessManager::OnUserInput` on a null context: `RoomExclusiveAccessContext` (no page fullscreen yet).
Packaging: the framework binary has no Mach-O header room for an rpath (`install_name_tool` refuses even an in-place rewrite), so the host carries `@executable_path/../Frameworks/RoomCore.framework/Versions/Current/Libraries` and links `libchrome_dll` directly (component build only); GN leaves helper bundles with only linker signatures (re-signed ad hoc); `chrome_crashpad_handler` gets the `Libraries` rpath.

## Card mask composite cost (backlog B-1, 2026-10-03, Mac mini)

Method: `xctrace record --template 'Metal System Trace' --all-processes` (25 s) around the Phase 1.4 `scroll` spike on the CEF build (rAF-driven scroll for 3 s with the card mask on, off, on; `scripts/run-spike.sh scroll` without activation). Chromium on macOS delegates compositing to Core Animation (tiles as IOSurfaces), so WindowServer does the scroll compositing; Room's own GPU process used 2.3 ms of GPU in the whole trace. The display tables (`displayed-surfaces-interval`, `display-compositor-interval`, which carry direct-to-display) were empty on this machine (external 60 Hz display), so the comparison is WindowServer's GPU work per segment from `metal-gpu-intervals`. The machine was not idle: `avconferenced` (screen sharing) used 2.06 s of GPU, rising and falling with screen changes.

| Segment | Page frames | WindowServer GPU per 0.5 s | per frame | GPU intervals per 0.5 s | `avconferenced` per 0.5 s |
|---|---|---|---|---|---|
| Mask on (3.5–6.5 s) | 60.0 fps, median 16.70 ms | 86.6 ms | 2.89 ms | 442 | 75 ms |
| Mask off (7.5–10 s) | 60.3 fps, median 16.70 ms | 86.4 ms | 2.88 ms | 442 | 77 ms |
| Mask on (11–13.5 s) | 60.3 fps, median 16.70 ms | 96.9 ms | 3.23 ms | 454 | 87 ms |
| Idle after quit | — | 21 ms | — | ~235 | 12 ms |

Result: the mask adds no WindowServer pass and no measurable GPU time (2.89 vs 2.88 ms per frame, same interval count); the last segment's +12% tracks `avconferenced`'s +12%, not the mask. Direct-to-display scan-out could not be observed here, and it only applies to fullscreen surfaces, where the card is not masked anyway. **Green.** The `RoundedCornersF` fallback is no longer needed for performance.

## Phase 2.1 — persistence under kill -9 (2026-10-03, Mac mini M4, 24 GB)

Method: `scripts/persistence-kill-test.sh` (`room-persistence-harness run`, release build). Each round starts a writer process that opens a `RoomStore` and mutates it continuously through the real stores and `Persistence` (1–20 random mutations every 1–4 ms: add/move/convert/rename/remove entries and folders, Clear + Undo, spaces, window state, settings, split groups); the `StateWriter` observer prints `begin <generation> <sha256 of the canonical state>` before each transaction and `commit <generation>` after it. The driver SIGKILLs the writer either 0–3 ms after a `begin` (40% of rounds, to land inside the transaction) or 20–1500 ms after start, then reopens the directory with `RoomStorage.open()` and requires: no recovery needed, unclean exit detected, `PRAGMA integrity_check` = ok, no `foreign_key_check` rows, generation on disk ≥ last acknowledged commit and ≤ last begun, content hash of the reopened state = the hash begun for that generation, JSON snapshot decodes and equals its own generation's content at most one generation behind. The same directory carries over from round to round. Load average 8.4 at the start, 3.8 at the end.

| Run | Debounce | Kills | Failures | Killed with a transaction in flight | Of those, rolled back to the previous generation | Final generation | Commit time median / p95 / max | Wall time |
|---|---|---|---|---|---|---|---|---|
| seed 2101 | 300 ms (production) | 100 | 0 | 35 | 35 | 127 | 7.3 / 14.2 / 22.4 ms | 65 s |
| seed 2102 | 5 ms (continuous) | 100 | 0 | 21 | 21 | 5,658 | 1.6 / 3.0 / 53.6 ms | 56 s |

In no round was a commit on disk whose acknowledgement had not been printed (the window between `COMMIT` and the next `write(2)` is a few µs). The databases ended at 200 KB (41 entries) and 180 KB (22 entries); snapshots lagged one generation in 6 and 10 rounds (killed between commit and snapshot write), which is the designed bound.

Found and fixed on the way: in the first 5 ms run one round failed because the JSON snapshot was **two** generations behind (kill 42 landed between commit 2045 and its snapshot, kill 43 between commit 2046 and its snapshot; the database itself was correct). `RoomStorage.open()` now rewrites a lagging or unreadable snapshot, so it never trails by more than one; both runs above are on the fixed build. **Green.**

## Phase 2.2a — sidebar update cost (2026-10-03, Mac mini M4, 24 GB)

Method: `scripts/sidebar-snapshots.sh 500` (Debug build, CEF engine running, FakeEngine pages behind the sidebar) loads the `500` fixture (100 pinned in 5 folders, 400 Today tabs; 508 outline rows) into a throwaway state directory, shows the window at 1100×760 with a 260 pt sidebar, and times each operation on the main thread with `ContinuousClock` around the store mutation, which includes the synchronous `SidebarChange` → `SidebarTree` → `NSOutlineView` update (row animations are started, not finished). Load average 4–7 during the runs.

| Operation | n | Median | p95 | Max |
|---|---|---|---|---|
| Full reload (launch, space switch) | 20 | 42.7 ms | 49.0 ms | 49.0 ms |
| Insert one Today tab at row ~100, viewport at the selected tab (row ~300) | 50 | 4.18 ms | 4.78 ms | 4.91 ms |
| Same insert with the viewport at the top (insert off screen; first run, before scroll-to-selected) | 50 | 1.08 ms | 1.14 ms | 1.50 ms |
| Rename one row (reconfigure the visible cell) | 50 | 0.07 ms | 0.07 ms | 0.09 ms |
| Select (store write, `markActive`, pill spring, peek refresh) | 50 | 0.90 ms | 1.32 ms | 2.86 ms |
| Remove one Today tab | 50 | 1.88 ms | 2.22 ms | 2.48 ms |

Every incremental update stays far under a 120 Hz frame (8.3 ms); only the full reload does not (42.7 ms, once per launch or space switch: 2.5 should measure it again with its slide animation in mind). The scroll exit criterion (500 entries without dropped frames on the 120 Hz panel) is measured in 2.2b with Instruments; this table is main-thread update cost only.

## Phase 2.2b — 500-entry scroll and drop cost (2026-10-03, Mac mini M4, 24 GB)

Display: this machine drives one external 4K panel at **60 Hz** (`system_profiler`: "UI Looks like 1920 x 1080 @ 60.00Hz"); there is no 120 Hz panel here. Method: `scripts/sidebar-snapshots.sh 500` (Debug build, CEF engine running, the `500` fixture: 508 outline rows, window 1100×760, sidebar 260 pt, list viewport 580 pt) runs a scripted scroll after the update timings: a display link on the outline moves the clip view at a fixed speed, bouncing between the ends, for 4 s per run (after a 1 s warm-up). Per frame it records the display link's frame interval (a frame that misses its vsync shows as an interval > 1.5× nominal, the Phase 1.4 rAF criterion) and the main-thread cost of that frame's scroll step: `scroll(to:)`, `reflectScrolledClipView`, `displayIfNeeded` and `CATransaction.flush()`, i.e. row creation, layout, drawing and the commit. Two modes per speed: **native** moves the list speed × 16.7 ms per frame; **proxy120** moves it speed / 120 per frame, the step a 120 Hz panel would ask for, so its step cost is the per-frame cost at 120 Hz, against the 8.33 ms budget. This is programmatic scrolling: AppKit's responsive scrolling, which prepares rows ahead of a real trackpad scroll, does not run, so it is the worst case for row creation. Load average 9–11.

Before fixes (first run, same method): native 9000 pt/s step median 8.06 ms, p95 9.10 ms, 89 of 240 steps over 8.33 ms; proxy120 1500 pt/s 28 steps over 8.33 ms (p95 10.4 ms); a `-O` build of the same code was no faster (the cost is AppKit's). A `sample` of the main thread put each scrolled-in row's cost in allocating and attaching a fresh row view, rebuilding one tracking area per cell every display cycle, and re-rendering letter-tile glyphs on every draw. Fixed (row views reused, icon hover from the outline's single tracking area, letter tiles cached); after:

| Run | Frames | Late frames (>25 ms) | Step median | Step p95 | Step max | Steps > 8.33 ms |
|---|---|---|---|---|---|---|
| native 1500 pt/s | 238 | 1 (36.4 ms, first second) | 3.96 ms | 7.47 ms | 24.87 ms | 2 |
| native 4000 pt/s | 240 | 0 | 4.63 ms | 7.84 ms | 15.06 ms | 7 |
| native 9000 pt/s | 239 | 0 | 4.87 ms | 7.62 ms | 13.80 ms | 6 |
| proxy120 1500 pt/s | 240 | 0 | 1.17 ms | 9.20 ms | 13.32 ms | 20 (8%) |
| proxy120 4000 pt/s | 240 | 0 | 5.00 ms | 7.38 ms | 9.63 ms | 4 (2%) |
| proxy120 9000 pt/s | 240 | 0 | 5.13 ms | 7.62 ms | 9.43 ms | 4 (2%) |

At 60 Hz the 500-entry list scrolls without dropped frames at every speed (one late frame in 1,437, in the first second of the first run). At the 120 Hz step, 2–8% of steps exceed 8.33 ms, all of them frames where a new row enters (the remaining cost is AppKit drawing the row's text and images into its layers, ~9–13 ms per new row at the slowest speed). Whether that drops frames on the laptop's 120 Hz panel depends on responsive scrolling, which this probe cannot exercise: **the exit criterion is measured here only by proxy** and needs one run of `scripts/sidebar-snapshots.sh 500` (native numbers at 120 Hz) plus a trackpad fling on the laptop.

Drop and drag cost on the same fixture (`ContinuousClock` around the store call, which includes the outline update):

| Operation | n | Median | p95 | Max |
|---|---|---|---|---|
| Drop: move one Today tab 200 rows | 50 | 5.18 ms | 6.13 ms | 6.38 ms |
| Drop: move a 10-tab group 300 rows | 20 | 9.52 ms | 10.09 ms | 10.09 ms |
| Drag validation (`canMove`, 10 tabs) per drag update | 50 | 0.02 ms | 0.02 ms | 0.07 ms |
| Full reload | 20 | 40.6 ms | 49.9 ms | 49.9 ms |
| Insert one Today tab | 50 | 4.70 ms | 5.37 ms | 5.45 ms |
| Select | 50 | 0.93 ms | 1.63 ms | 3.58 ms |
| Remove one Today tab | 50 | 2.70 ms | 3.53 ms | 3.82 ms |

Drag updates are negligible; a single drop is one frame of work (a 10-row group drop is ~9.5 ms, one frame over the 120 Hz budget at the moment of the drop). Raw output: `research/screenshots/phase-2.2b/500-entries/states.txt`.

## Phase 2.3 — Tabs on CEF: switching, memory, relaunch (2026-10-03, Mac mini M4, 24 GB)

**Conditions.** Every run below happened with the Mac mini's display asleep and the login session locked (`CGDisplayIsAsleep` true, `CGSSessionScreenIsLocked` 1): the Room window existed and laid out but was occluded, so pages never became visible (`visibilityState` stayed `hidden`, the page-side probe below recorded nothing) and Chromium did not composite them. The main-thread numbers are what AppKit, the sidebar and the tab controller cost; whether CEF's work for a page that turns visible adds to them needs one run with the screen unlocked (backlog B-18). Debug build, CEF 154, load average 2.5–7.5.

**Method.** `scripts/tabs-measure.sh` = two DEBUG spikes on one state directory. `switch` (with `-RoomSidebarFixture 50`: 4 essentials, a folder, 14 pinned, 32 Today tabs = 50 entries, the first ten Today tabs being the Phase 1.4 typical sites) selects the ten site tabs in turn as clicks would (`SidebarController.select`), waits for each to load, waits 10 s, sums RSS over Room + helpers with `ps` (same method and site list as Phase 1.4's memory spike), then switches 100 times between random loaded tabs, 400 ms apart. Per switch: the `select` call itself (store write, `markActive`, sidebar update, `TabController.activate`, the card's view swap), and the whole run-loop turn it ran in, up to the last before-waiting observer (layout, display and the Core Animation commit run in that turn's observers; ours is ordered last), i.e. click handling to the new page's view committed in the card. The spike then quits normally. `relaunch` starts Room on that state directory with no fixture.

| Run (100 switches each) | `select` median / p95 / max | Whole turn median / p95 / max |
|---|---|---|
| First run | 3.87 / 6.96 / 23.31 ms | 12.51 / 22.82 / 41.26 ms |
| Second run (with a before-display split) | 3.59 / 6.79 / 8.71 ms | 11.96 / 20.93 / 28.69 ms |
| After the fix below, run 1 | 4.85 / 6.96 / 11.41 ms | **9.44 / 14.45** / 16.37 ms |
| After the fix below, run 2 | 4.99 / 6.94 / 7.78 ms | **9.51 / 15.38** / 17.94 ms |

The fix: a Time Profiler trace (`xctrace`, attached during switching, 1,056 main-thread samples) put ~3 ms of every switch in SwiftUI re-rendering the Debug ▸ Show Debug Toolbar panel's view, hidden but still observing the tab controller's current page; the panel now builds its view only while open. In the same trace the card's view swap (`removeFromSuperview`/`addSubview` of CEF's views, where Chromium handles hide/show) was ~2 ms per switch and the store write with its observers ~0.9 ms. Median and p95 are under 16 ms; 1–2 switches in 100 exceed it (max 16.4 / 17.9 ms).

Memory, 50 entries with 10 loaded (summed RSS, double-counts shared pages): **4,095 / 4,215 MB** in 21 processes (15 renderers, 3,288 / 3,404 MB of them); after the 100 switches 3,960 / 4,034 MB. Phase 1.4 measured 670 MB for one blank page and +242–327 MB per hidden page, consistent with this.

Relaunch on the quit state (three runs): **1 page loaded** (the selected entry), 49 rows restored unloaded (titles from the store; the 9 entries whose page had reported a favicon show it from the favicon cache, the others letter tiles). Process start to the session running (store open, sidebar, tab controller, profile created, selected page requested): 0.33–0.45 s; to the selected page loaded (BBC News, HTTP cache warm): 0.48–0.60 s. RSS at relaunch 990–1,000 MB in 7 processes (3 renderers).

Behaviour checks on CEF (`scripts/run-spike.sh tabs`; keys sent as `NSEvent`s through `NSApp.sendEvent` with the page focused where noted):

| Check | Result |
|---|---|
| ⌘W on a Today tab, page focused (reserved key → menu) | page closed, entry removed, selection moved to the MRU tab (A), not the neighbour (B); A's view in the card |
| ⇧⌘T, page focused | C back at index 2 of 3, selected, loading `news.ycombinator.com` (first run: not reopened, see the menu fix in the log) |
| ⌃Tab tapped, then ⌃ released | back to the previous tab, no list shown |
| ⌘1, then ⇧⌘] | the first entry, then the next in sidebar order |
| Same-site navigation in a pinned entry, then ⌘W | changed dot on (`/?changed=1`); ⌘W closed the page, the entry stayed with `liveURL` = stored URL; ⇧⌘T reopened it at `/?changed=1` |
| target=_blank from a Today tab (CDP click) | new tab at the opener's index + 1, selected |
| Two ⌘-clicks from the same opener after switching back to it | background tabs at index 1 and 2 (in click order), the earlier foreground tab pushed to 3, selection stays on the opener |
| Debug ▸ Discard Background Pages (7 pages) | all `.discarded`, renderers 9 → 2, summed RSS 1,685 → 765 MB, rows dimmed |
| Selecting a discarded tab | reloaded at its URL with its title; `canGoBack` false (CEF cap B-13) |
| ⇧⌘M through the menu | selected page muted |
| ⌘Q with pages open (quit path closes every browser) | entries untouched (all Today tabs still in the store), `running=0`, no helpers left; before `EngineApplication.isTerminating` the controller took the engine's closes for `window.close()` and removed every Today tab (fixed, see the log) |

## Phase 2.4a — the palette (2026-10-03, Mac mini M4, Debug build, CEF)

The session was locked and the display asleep for the whole run (as in 2.3, B-18): the window was never key or visible, so the numbers are main-thread costs for an occluded window and there is no display-link frame to time "first frame" against. Load average 3.3–9.7 (noted per run).

**Method.** `scripts/run-spike.sh palettemeasure -RoomSidebarFixture 500` (100 pinned in 5 folders + 400 Today tabs; one page loaded). Open: 40 × `PaletteController.toggleNew()` timed like 2.3's switch (the call itself, and the whole run-loop turn up to our last before-waiting observer, i.e. layout, display and the Core Animation commit included), 150 ms apart, closed in between; a display link on the panel asks for the next frame after the open (none came: occluded). Keystrokes: nine queries typed one character at a time as `NSEvent`s through `NSApp.sendEvent` into the field editor ("today tab 3", "pinned 4", "folder", "site1", "example.org/article", "tab 39", "zzz", "github.com", "wikipedia"; 77 keystrokes), each timed as the turn of its key event: field editor → `controlTextDidChange` → the three providers and the scorer → the SwiftUI rows → panel layout → commit. "Query only" is the providers and the scorer alone (`onQueryTimed`). 1–8 rows per keystroke.

| Run | Open call median / p95 | Open turn median / p95 / max | Keystroke turn median / p95 | First key / later keys, median / p95 | Query only median / p95 / max |
|---|---|---|---|---|---|
| First build | 5.02 / 7.88 ms | 19.95 / 29.60 / 36.59 ms | 5.86 / 21.39 ms | (not split) | 3.91 / 8.74 / 15.02 ms |
| First build, run 2 | 4.78 / 6.05 ms | 19.80 / 21.12 / 34.99 ms | 5.42 / 20.80 ms | (not split) | 3.76 / 8.69 / 12.87 ms |
| Final (load 3.3) | 4.86 / 7.57 ms | **15.25 / 20.07** / 33.70 ms | 4.30 / 22.19 ms | 22.19 / 29.29 · **3.98 / 6.42** ms | **2.51 / 6.09** / 11.78 ms |
| Final, run 2 (load 3.5) | 6.58 / 8.11 ms | **16.30 / 19.61** / 33.44 ms | 3.93 / 22.11 ms | 22.11 / 24.67 · **3.60 / 6.58** ms | **2.35 / 6.11** / 10.46 ms |

What changed between the first and the final build: building the providers' snapshot of 500 entries took 6.0 ms of every open (per-open timing written from inside `open`; four `URLComponents` parses per entry in a Debug build), now cached per entry and reused while the entry is unchanged; matching keys (lowercased title, hosts, bare and normalised URLs) are computed once per context instead of per keystroke per entry, which halved the query (3.8 → 2.4 ms median, 8.7 → 6.1 ms p95). Building the overlay once and prewarming it did not move the open turn measurably; the remaining ~10 ms of the open turn is AppKit's layout, display and commit of the glass panel and the field editor, outside our code.

The keystroke tail is the first keystroke of each query (9 of 77): the list appears and the panel grows from the field alone to up to 8 rows (22 ms median). Every later keystroke is under 16 ms at p95 (6.4–6.6 ms). Laying a full list out once at prewarm did not change it (tried, reverted). 2.4b measures keystroke-to-local-results at 50k history rows against the same split.

**Visible-window run (the user, 2026-10-03 13:06Z, screen unlocked, Room frontmost, `window_main: true`, load 5.7 3.2 3.1, same build and method).** The display link now fires, so open-to-first-frame is measured: the time from `toggleNew()` to the panel's next display-link callback.

| Measure | Median | p95 | Max |
|---|---|---|---|
| Open call (our code) | 7.28 ms | 8.83 ms | 19.64 ms |
| Open turn (incl. AppKit layout, display, commit) | 20.28 ms | 22.67 ms | 39.79 ms |
| **Open to next frame** | **25.75 ms** | **36.79 ms** | 43.65 ms |
| Keystroke to rows, all (n = 77) | 4.87 ms | 18.49 ms | 33.81 ms |
| First key of a query (n = 9) | 18.49 ms | 27.21 ms | 33.81 ms |
| Later keys (n = 68) | 4.49 ms | **11.06 ms** | 14.54 ms |
| Providers + scorer alone (n = 86) | 2.45 ms | 5.26 ms | 10.90 ms |

The palette appears 1.5–2 frames at 60 Hz (3–4 at 120 Hz) after ⌘T; the open turn is ~5 ms longer than in the occluded runs (a visible window composites). Later keystrokes stay under 16 ms at p95; the first key of a query is still the panel growing. No 2.4a target applied; the open is the number to bring down (first candidate: build the sidebar snapshot on the first keystroke instead of at open, about 4–6 ms of the open call).

Behaviour on CEF (`scripts/run-spike.sh palette -RoomSidebarFixture demo`, key events into the field editor; the window was not key, so key equivalents that need a key window were not exercised):

| Check | Result |
|---|---|
| ⌘T (reserved, page focused) | palette open in `new` mode, field editor first responder; no tab created |
| Type "example.com", Enter | top hit `navigate https://example.com`; palette closed, one Today tab added and selected, page loaded at `https://example.com/`, focus back on Chromium's view (`RenderWidgetHostViewCocoa`) |
| ⌘L | `edit` mode prefilled with the page URL, all 20 characters selected |
| Type "en.wikipedia.org/wiki/Command_palette", Enter | the same entry navigated (no new tab) |
| ⌘L, Enter unchanged | page reloaded (loading seen) |
| ⌘L, "typo", Esc, Esc | first Esc restored the URL, second closed; focus back on the page |
| ⌘T ⌘T; ⌘L ⌘T | closed both times |
| ⌘T "swift.org" ⌥Enter | one Today tab added in the background, loading `swift.org`; selection unchanged |
| ⌘T "ar", ⇥, ⌘Enter | groups top hit · open tabs · pinned ×4; ⇥ moved to row 1 (the open tab); ⌘Enter opened a copy of it (local key monitor; a key equivalent never reached the panel in a non-key window, fixed) |
| Header field click (`SidebarHost.editAddress`) | docked: panel at (91, 6), 640 × 48, over the address field at (91, 12) |
| After deleting the Debug panel and the URL prompt | the same run passes: URLs open and edit through the palette alone |
| Smoke quit | 0.18 s, exit 0, no helpers left, no crash report |

Captures (`research/screenshots/phase-2.4a/`, 1244 × 818 window at 2×): empty, results ("ar"), ⌘L edit and docked, light and dark; in-process layer renders with the page composited from a CDP screenshot and the glass replaced by a flat stand-in (it draws nothing in-process). The dark captures found row titles drawn in light-mode black: SwiftUI's `.primary` in the reused overlay kept the light appearance; rows now use dynamic `NSColor`s.

## Phase 2.4b — history, commands, site search, suggest; palette cost (2026-10-03, Mac mini M4, 24 GB, CEF)

Conditions for every number below: the screen was unlocked and Room frontmost (`window_main: true`), but **screen sharing was active the whole session** (`avconferenced` + the video encoder, `mediaanalysisd` at up to 190% CPU; load average 5–21, stated per run) and the display ran at **60 Hz** (the running display link reported a 16.67 ms frame interval on every run). WindowServer-side timings are noisier than on an idle machine; our own code's timings are not affected much.

### The 50k-row measurement (`scripts/run-spike.sh palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000`)

Fixture: the 500-entry sidebar plus 50,000 synthetic history URLs (`App/Sources/Debug/HistoryFixture.swift`: deterministic, 2,500 hosts on a steep power law, word-salad paths and titles, 1–30 visits each over a year, 10% typed, 10% search pages; import ~10 s at launch). 14 queries typed as key events into the field editor, 120 keystrokes: sidebar words, hosts (`github`, `news`, `wiki`, `app`), multi-word (`swift docs`, `rust kernel`), a path (`developer.apple.com/sw`), common trigrams (`com`, `the`), a miss (`zzz`). History rows shown per keystroke 0–7 (mean 4.7); 62 of 120 keystrokes completed inline. Final runs on the committed code:

| Measure (ms) | Debug run 1 (load 17) | Debug run 2 (load 12) | `-O` build (load 10) |
|---|---|---|---|
| **Local results: providers + scorer + rows model, all keys** (median / p95) | 3.18 / **9.85** | 3.76 / **9.93** | 2.40 / **5.93** |
| … first key of a query (includes the sidebar snapshot, 2.9 ms Debug / 1.2 ms `-O`) | 9.85 / 16.88 | 9.93 / 13.43 | 5.50 / 7.89 |
| Keystroke turn to rows on screen, later keys (n = 106) | 7.12 / **13.65** | 7.40 / **14.22** | 5.44 / **12.13** |
| Keystroke turn, first key of a query (n = 14) | 23.89 / 28.29 | 24.71 / 30.63 | 22.22 / 31.99 |
| Keystroke turn, all keys (n = 120) | 7.74 / 24.26 | 7.74 / 26.23 | 5.70 / 24.81 |

The local-results pipeline is under 16 ms at p95 with 50k rows (9.9 ms Debug, 5.9 ms optimised), and so is every keystroke's whole turn after a query's first. The first keystroke of a query is not: ~10 ms of ours (snapshot, a one-letter query, ranking) plus ~12 ms of SwiftUI drawing eight rows of new text and ~5–7 ms of Core Animation commit as the glass panel grows from the field to the list (Time Profiler, below). With 14 first keys in 120, the all-keys p95 is a first key.

Where the time went before the fixes (Time Profiler on `palettemeasure`, 1 ms samples, main thread): per keystroke, history 47% of the query (trigram search 32%, the `GROUP BY host` for inline completion 14%), entry matching 25%, the scorer 21% (re-normalising URLs for dedupe, `URLComponents` per comparison); outside the query SwiftUI rebuilt and re-measured all row views (~8 ms/keystroke). Fixes: `history_host` aggregate table (inline lookup is a range scan over hosts), dedupe key computed once per match, entries rejected by a `memmem` over a precomputed UTF-8 haystack and one-letter queries by word initials, history fetch 12 → 8 rows; row slots identified by position at a fixed height and never emptied (the panel clips them), one `Text` per row. Effect on later keys: turn p95 22.6 → 13.7–14.2 ms (Debug); query p95 10.8 → 9.9 ms.

### Opening (⌘T to the next frame)

| Measure (ms, median / p95) | 2.4a code, same probe, same machine (2 runs) | 2.4b, Debug (2 runs) | 2.4b, `-O` |
|---|---|---|---|
| Open call (our code) | 6.85–7.28 / 8.62–8.65 | 2.31–2.39 / 3.51–4.36 | 2.29 / 3.96 |
| Open turn (incl. AppKit layout, display, commit) | 17.31–17.60 / 20.42–24.12 | 2.90–3.01 / 4.12–5.13 | 2.87 / 4.74 |
| **Open to next frame** | 17.41–17.68 / 31.28–33.28 | **6.23–6.29 / 14.97–15.06** | **6.07 / 14.92** |

Target (ROADMAP 2.4 carry-over a): ≤ 8.3 ms our code and ≤ 16.7 ms to the frame, median. Met: 2.3 ms of our code, 6.2 ms to the next frame. On this 60 Hz display "one 120 Hz frame" cannot be observed; the p95 (15 ms) is one 60 Hz frame. The probe changed: 2.4a created a `CADisplayLink` after each open and timed its first callback, which includes the link's own start-up (on the current code the old probe read 29.3 ms with a 7.5 ms turn); 2.4b keeps one link running through the measurement and takes the first frame that starts after the open's turn. The 2.4a column is the 2.4a commit (8522d6f) built with only the new probe patched in, run alternately with the current build.

What the open cost (profile): the field becoming first responder made AppKit's password AutoFill heuristics (`NSAutoFillHeuristicController _showPasswordAutoFillIfNecessaryForView:`) ask the field for its previous and next valid key views, which walked every view in the window (500 sidebar rows, NSButton alignment insets, symbol images: ~6–7 ms), and build a one-time-code AutoFill window (`SPRoundedWindow`) on every open; adding and removing the overlay moved the rows' `NSHostingView` into and out of the window each time (~4 ms); clearing the rows at open re-rendered the list. Fixes: `contentType = .URL` on the field (it holds URLs; AutoFill stops guessing), `previousValidKeyView`/`nextValidKeyView` nil on the field and its own field editor, the overlay kept in the window hidden between opens, rows never emptied.

### History recording on CEF (`scripts/run-spike.sh palette2 -RoomSidebarFixture demo`)

| Navigation | Recorded |
|---|---|
| ⌘T "example.com" Enter | `https://example.com/` visits `[typed]`, title "Example Domain" (CEF's TT_EXPLICIT replaced by the requested `.typed`) |
| `location.href = 'https://example.org/'` (script) | visits `[link]`, title "Example Domain" |
| `history.pushState({}, '', '/pushed')` (same document) | visits `[link]`, title "Example Domain" — first run: not recorded (CEF reports `isLoading` true around `pushState`; rule changed to "an address no `OnLoadStart` claims in the same turn"); second run: no title (written before the deferred commit; titles now follow the visit once loading ends) |
| Reload | no visit (reload transition) |
| ⌘L "https://nonexistent.invalid/" (DNS error page) | not recorded (`OnLoadError` for the URL drops the commit) |
| ⌘T "room browser palette" Enter | the Google results page, 1 visit (`generated`) |
| Then ⌘T "exa" | inline `mple.com` (typed host); first run found none: the more frecent example.org (links only) was the only host fetched — fixed, test added |

### Search suggest and the no-network check

- `scripts/run-spike.sh suggestcheck -RoomSidebarFixture demo` on the real network, suggestions on (Google): three queries typed at ~16 keys/s with a 1.2 s pause after each; 5 suggestions arrived and showed for each ("swift concurrency" → "swift concurrency skill", "… interview questions", "… tutorial", …).
- Through a logging proxy (`-RoomSuggestProxy 127.0.0.1:port`, a small Python listener that records each request line and answers 502), suggestions **on**: exactly 3 requests, `CONNECT suggestqueries.google.com:443` at the three pauses, none between keystrokes (the 120 ms debounce).
- Same, suggestions **off** (`-RoomSuggestionsOff YES`), after the selected page finished loading and 3 s of quiet: **0 proxy requests** over 7.5 s of typing (3 queries, 47 keystrokes, 3 pauses), and in CEF's net-log (`--log-net-log … --net-log-capture-mode=Everything`) **0** `URL_REQUEST_START_JOB` / `HOST_RESOLVER_MANAGER_REQUEST` / `TCP_CONNECT` / `SSL_CONNECT` / `HTTP_STREAM_JOB` events between the first and last keystroke (263 before, from the page load). The 120-keystroke `palettemeasure` run with suggestions off: 0 proxy requests, 0 net-log request events in its 4.2 s typing window.
- Outside the typing window the engine itself talks to Google: at launch `accounts.google.com/ListAccounts`, `www.google.com/async/folae`, `update.googleapis.com/service/update2/json` (as found on RoomCore in Phase 1.5, now also seen on CEF), and at quit a speculative DNS resolve plus a QUIC session job to `www.google.com:443` (aborted, `net_error -3`). A control run with no palette use (launch, 15 s, quit) shows the same quit-time job: engine behaviour, Chapter 3.1's audit (backlog B-19).

Captures (`research/screenshots/phase-2.4b/`, 1244 × 818 window at 2×, light and dark, in-process renders as in 2.4a, glass replaced by a flat stand-in, suggestions off so no live third-party text): `history-inline` ("gi": github.com completed inline and merged with the open GitHub essential, "Switch to Tab"; four GitHub history rows; the search row), `commands` (⇥ from empty: `>` and the first eight commands A–Z), `commands-filtered` (`>re`), `site-search` (`yt` ⇥ `lofi`: the YouTube chip, "Search YouTube", two YouTube history rows).

Tests: Room scheme 301 tests (unit and window tier) pass locally; the no-engine CI spec builds and passes with window suites skipped. Smoke quit 0.21 s, exit 0, no helpers left, no new crash reports.

## Phase 2.5 — spaces: switch cost, cookies per profile, mid-slide frame (2026-10-03, Mac mini M4, 24 GB, CEF, Debug)

Conditions: the screen was unlocked and in use; Room's window was visible but never key (`window_main: false`: macOS refused activation of the script-launched app), the display ran at **60 Hz** (16.67 ms frames on every run), load average 4–13 (stated per run). No screen sharing.

### Switching (`scripts/run-spike.sh spaces -RoomSidebarFixture spaces500`)

Fixture: the 500 entries split over five spaces (100 each: 20 pinned, half in two folders, 80 Today tabs), alternating two profiles; the first ten Today tabs of every space are local colour pages (`research/spikes/phase-2.5/page.html`), all **50 loaded** (10 per space; 51 renderers, 5.9–6.5 GB summed RSS). 60 switches to a random other space by **⌃digit key events**; the slide runs 250 ms, the next switch waits 450 ms. Phases are timed inside `SidebarController.switchPane`. Final run (load 7.3) and the one before it (load 13.3):

| Measure (ms, median / p95) | final run | previous run |
|---|---|---|
| ⌃digit key event to the switch starting (CEF passes the unhandled key to the menu) | 1.93 / 2.54 | 1.75 / 3.34 |
| The switch's main-thread code | **6.37 / 8.70** | 6.84 / 11.28 |
| … list swap and pill | 0.08 / 0.11 | 0.07 / 0.20 |
| … slide set-up (layer animations, unhiding the list) | 1.68 / 2.99 | 1.78 / 3.90 |
| … footer (active icon, highlight) | 0.27 / 0.47 | 0.28 / 0.81 |
| … essentials (crossfade on a profile change) | 0.01 / 0.02 | 0.02 / 0.04 |
| … tint and title | 0.88 / 1.45 | 0.80 / 2.47 |
| … card: the space's selected page into the card (`TabController.activate`) | 3.47 / 4.56 | 3.52 / 6.17 |
| **⌃digit to the slide's first frame** (first display-link frame after the switch) | **10.85 / 17.10** | 9.94 / 23.81 |
| Lists loaded during the 60 switches | **0** | 0 |

The slide never waits on a list: every space's list is built after launch (`SidebarController.prepareSpaces`, one per run-loop turn) and kept up to date off screen. A full reload of one space's list (103 rows) off screen costs 0.18–0.51 ms median (p95 0.9–5.6 ms), because AppKit makes no row views for a hidden outline; the real cost is the list's **first display**: the first switch to each space after launch took **101–105 ms** of run-loop turn (24–28 ms our code, of which 21–25 ms is creating the never-loaded selected page). Fix: each prepared list is laid out and drawn once, transparent, under the active one (`SidebarBodyView.warmUp`): **45.5 ms median per space, one per turn after launch** (4 spaces), and the first switch's turn fell to **36.4–37.6 ms** (24.7–27.6 ms our code, 22.6–25.0 ms of it the page creation). Before trimming, the switch's own code was 10.5–11.4 ms median: the footer re-laid itself out (2.5 ms; now only the active icon changes) and the hidden window title was set synchronously (now after the frame).

The 2.2a full reload (42.7 ms for 508 rows in one visible list) is no longer on any switch's path. At 60 Hz the median switch shows its first slide frame within one frame of the key; at 120 Hz (8.3 ms) the median 6.4 ms of our code would leave little room: rerun on the laptop's panel (below, for the user).

### Material flash (`scripts/spaces-capture.sh`, mid-slide capture)

`research/screenshots/phase-2.5-mid-slide-light.png`: a Default → Work switch slowed 24× (`SidebarController.debugSetSlideSlowdown`, 6 s) and captured by the window server (`screencapture -l`, real CEF content) 1.8 s in: both lists mid-slide, the Work profile's essentials already in place, and the card already showing the Work space's selected page (the card swaps at the switch's start, its fill follows the page's background). No frame shows the window material inside the card. At full speed the swap is inside the switch's turn (3.5 ms), so no frame can show an empty card; checked by eye only in this capture.

### Cookies per profile (`scripts/spaces-cookies.sh`)

`-RoomSidebarFixture spaces` (spaces Space, Reading, Music in profile Default; Work in profile Work), a throwaway `-RoomEngineDirectory`, `research/spikes/phase-2.5/cookies.html` served on 127.0.0.1:8765:

| Step | `document.cookie` |
|---|---|
| Space (Default) opens `?set=home` | `room_profile=home` |
| Work (Work) opens `?set=work` | `room_profile=work` |
| Work opens the page again | `room_profile=work` |
| Reading (Default) opens the page | `room_profile=home` |
| The Space tab, on the page without `?set`, before a move | `room_profile=home` |
| … moved to Work (Move to, warning confirmed): a new page in Work's context, same URL | `room_profile=work` |

Engine directories: `Room Profile Default`, `Room Profile Work`, both direct children of the root (Phase 1.4 finding). The moved entry's `profileID` is Work's.

## Phase 2.6a — palette rows on AppKit: the first keystroke (2026-10-03, Mac mini M4, 24 GB, CEF, Debug)

Same machine and method as 2.4b: `scripts/run-spike.sh palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000`, Debug build, the display at **60 Hz** (16.67 ms frames on every run), Room frontmost, **screen sharing active** (`avconferenced` preempting the main thread in the System Trace), load average 4.5–7.7. "Before" is the session's starting commit (f33c362, SwiftUI rows) built with only the spike's new probes patched in (as 2.4b did for 2.4a); before and after builds ran alternately. New probes in `palettemeasure`: the turn up to the run loop's display pass, each first key's turn / event / query, `-RoomPaletteTypingDelay <ms>` (default 100, as 2.4b) and `-RoomPaletteSpinBeforeFirstKey YES` (diagnostic, below).

| Measure (ms, median / p95) | Before, run 1 | Before, run 2 | After, run 1 | After, run 2 |
|---|---|---|---|---|
| **A query's first keystroke, whole turn** (n = 14) | 26.62 / 34.99 | 25.91 / 36.48 | **17.89 / 21.39** | **18.89 / 20.95** |
| … its query (snapshot + providers + rank + rows) | 9.22 / 12.15 | 9.21 / 16.12 | 5.25 / 10.86 | 5.14 / 12.44 |
| … snapshot on the first key | 2.95 | 2.95 | 0.01 | 0.01 |
| **Later keystrokes, whole turn** (n = 106) | 7.96 / 15.09 | 7.77 / 16.45 | **5.13 / 9.61** | **4.90 / 10.40** |
| Local results, all keys (query only, n = 134) | 3.48 / 9.96 | 3.24 / 9.21 | 2.58 / 6.71 | 2.57 / 6.47 |
| Open call / open turn | 2.58 / 3.43, 3.15 / 4.06 | 2.76 / 3.64, 3.29 / 4.35 | 2.50 / 3.53, 3.07 / 4.49 | 2.75 / 4.20, 3.47 / 4.92 |
| Open to next frame | 5.72 / 15.12 | 5.48 / 14.96 | 7.11 / 13.54 | 7.55 / 13.36 |

Earlier the same day, at the start of the session (the starting commit as it was, load 4.4–5.1): first key 22.18 / 36.57 and 27.29 / 30.53, later keys 6.44 / 12.48 and 7.10 / 13.01. 2.4b recorded first keys at 22–25 ms and later keys at p95 13.65–14.22.

**Target (ROADMAP 2.6 task 0): a first keystroke under one 120 Hz frame (8.33 ms) median. Not met by this method: 17.9–18.9 ms (from 25.9–26.6).** Later keystrokes are better than 2.4b's (p95 9.6–10.4 vs 13.7–14.2).

Why the first key stays slow: **it runs on an efficiency core.** A System Trace of the typing (`xctrace`, System Trace template, 8 s) shows each query's first key, which arrives after ≥ 100 ms of idle, running on an E core for its first ~18 ms before the scheduler moves the main thread to a P core ("balanced off CPU 2 (E Core) to optimize the system's CPU performance"). Example bursts: 4.0 ms on P / 19.3 ms on E; 6.5 / 18.1; 2.2 / 17.0. Later keys follow each other within milliseconds and run on P cores. The work is CPU-bound, not waiting: the main thread is running throughout. Neither a running `CADisplayLink`, nor typing 400 ms after the open (outside the 120 ms open animation), nor a `.latencyCritical` process activity while the palette is open moved the first key (19.7 / 20.3 / 17.6 ms median).

What the first key costs on a performance core (`-RoomPaletteSpinBeforeFirstKey YES`: the spike keeps the main thread busy for 25 ms before the key, so the scheduler has already moved it): **before 17.85 / 20.03 ms, after 7.53 / 12.59 ms** (first-key query 4.80 → 2.27 ms). So our code now fits in one 120 Hz frame; the remaining ~10 ms in the 2.4b method is the same work at E-core speed.

Where the first key's time went (Time Profiler, first keys spun onto a P core, before the fixes): ~3 ms query, ~1.5 ms field editor, ~9 ms in AppKit's display flush (macOS 27's `UC::DriverCore` update source; drawing ~37%, layout ~30%). The 2.4b reading ("SwiftUI drawing eight rows, ~12 ms") was not the main cost: AppKit rows alone moved the first key 22.2 → 22.0 ms. What did move it:

| Change | Effect |
|---|---|
| AppKit rows: one reusable row view per slot, frames by hand, a slot's views touched only when its row changed | later keys 6.4 → 5.8 ms median |
| Sidebar snapshot built 30 ms after the open on an idle turn (`Timing.paletteContextDelay`), not on the first key | first-key query −3 ms |
| One- and two-letter history: ids from the `(profileID, host, frecency)` index, whole rows only for the 8 kept (sorting whole rows read a fifth of the table for one letter); cached statements for it and the inline-completion lookup | "g" at 50k rows 5.8 → 0.5 ms in `sqlite3` |
| Inline completion written into the field editor's text instead of resetting `stringValue` | ~1 ms per completed key (profile) |
| Field editor on TextKit 1 | its selection and viewport bookkeeping was ~1 ms per key (profile) |
| Letter tiles cached as bitmaps (the cached drawing-handler image ran its handler on every draw); symbol images cached by name; no per-layout tracking-area churn or label measuring in rows | ~1–2 ms of the first key's display pass |
| Entry matching iterates indices, not `zip` (Debug) | one-letter entry matching ~−40% |

## Phase 2.6b — downloads, find, zoom, print, the status pill, the site panel, DevTools, the delegate checklist (2026-10-03, Mac mini M4, 24 GB, CEF, Debug)

`scripts/chrome-surfaces.sh --session 2.6b` (spike `chromesurfaces2`): the test server in `research/spikes/phase-2.6/` on 127.0.0.1:8766/8767, a throwaway engine directory, the `demo` fixture, a 1244 × 818 pt window with a 280 pt sidebar, Room frontmost, the display at 60 Hz, load average 4.7–6.4 (a Chromium build was not running; the other load is the machine's own). Two full runs (light, dark) after the fixes below; numbers are from those two runs. Every delegate call went through recording proxies (`DelegateRecorder`) in front of the tab controller and the downloads list.

| Measure | Light | Dark | How |
|---|---|---|---|
| **Find: keystroke → first result with a highlighted match** (a 2,000-paragraph page, ~120k words; "lighthouse" 400×, "harbour" 2,000×; one key at a time in the find field) | **21.3 / 23.8 ms** median / p95 (n = 9) | **20.7 / 26.5 ms** (n = 11) | `sendKey` into the field → the `findResult` observation's change with `activeMatch ≥ 1` (stamped in the observation's `onChange`); keystrokes whose result did not change the highlighted match are not samples |
| Find: keystroke → final count | 21.8 / 38.2 ms (n = 26) | 21.7 / 29.1 ms (n = 26) | same, to the first result with `isFinal` |
| **DevTools pane: ⌥⌘I → front-end loaded** | **327.9 / 336.4 ms** (n = 4) | **334.9 / 336.3 ms** (n = 4) | `toggleDevTools` → the docked front-end page (our Alloy browser on `devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:9339/…`) stops loading |
| DevTools pane: ⌥⌘I → attached to the page | 328.5 / 337.0 ms | 335.4 / 336.8 ms | the front-end's `TargetManager.primaryPageTarget()` exists (first successful probe, 20 ms apart) |
| **Status pill: status text → pill shown** (configured `Timing.statusPillDelay` = 600 ms) | **604.7 ms** median, max 605.5 (n = 3) | **618.7 ms**, max 621.9 (n = 3) | `StatusPillState.requestedAt` → `shownAt` (the main-queue timer's lateness is the difference) |
| Status pill: CDP hover → status text from CEF | 2.4 ms median | 2.1 ms | `Input.dispatchMouseEvent mouseMoved` over a link → `didChangeStatusText` |
| Status pill: full URL after | 1.5 s (`Timing.statusPillExpand`): 756 pt wide on a 958 pt card (standard width 223 pt = a third) | same | frame read after `width == .full` |
| Print panel appears after `print()` | 285 ms (`NSPanel`, app-modal) | 287 ms | a timer in the common modes, which also aborts it |
| Download fly-in → popover | the slow file (6 MB at 1 MB/s) at 1.5 s: ring 0.24, "1,4 MB of 6 MB — 721 KB/s, 7 s left" (the machine's locale writes the decimal comma) | same | |

Behaviour checked on CEF (both appearances): downloads land in Settings' folder (a throwaway one), a second "room-2.6b-small.txt" becomes "room-2.6b-small (1).txt", a download without a length spins the ring (`progress == -1`), pause / resume / cancel through `Profile` work and a cancelled file is removed, two completions leave badge 2, opening the popover clears it, Clear empties finished rows; ⌘F opens the bar with the keyboard in it, "1 of 400", ⌘G → "2 of 400", ⇧⌘G → "1 of 400", Esc closes and the keyboard returns to the page; ⌘= (page first, unhandled, then the menu) → 110% with the indicator, ⌘- ⌘- → 90%, ⌘0 → 100%, the indicator leaves on its own; the status pill dodges to the bottom-right (x 4 → 731) when the pointer reaches it; the site panel on `http://127.0.0.1:8766` shows Location Allow (2.6a's grant), Notifications Block (2.6a's denial), changes Location → Block and Pop-ups → Allow, the page then reads `geolocation: denied`, Clear empties `document.cookie` and `localStorage`, Reset Permissions leaves nothing stored; a JavaScript alert is withdrawn by a navigation (sheet gone, `webContentsDidDismissJavaScriptDialogs`, the page reaches the new URL) and so is a location prompt (`webContentsDidDismissPermissionPrompt`); `chrome://crash` → `processGone(.crashed)`, the crashed-page view with the keyboard in it, Return reloads; the canvas video's fullscreen button → the window goes fullscreen with the card edge to edge (1920 × 1080), `exitFullscreen()` → back with the sidebar and the traffic lights at 19,19; the DevTools divider dragged 150 pt up → 42% → 60.7%; ⌥⌘J opens on the console; ⇧⌘C / ⌥⇧⌘C copy the URL and `[Audio](http://…)`.

Bugs found by running it (fixed before the numbers above): CEF's first `Find` for a text only counts (active match 0: nothing highlighted, ⌘G did nothing; first run "0/400", after the fix "1/400"); a navigation under a pending `alert()` never committed on Alloy (the request went out, the page stayed); `OnDismissPermissionPrompt` also follows answered prompts; download updates carry an empty suggested name; `GetContentSetting` answers with the effective value, so the site panel listed all twelve permissions as set; the popover opened below the footer (flipped `maxY`); the toolbar came back hidden after element fullscreen (traffic lights 9,9). The first run's downloads never started because a stale 2.6a test server held port 8766 and the new `/download` route also matched `/downloads.html`; the script now refuses to run beside another server.

## Phase 2.7a — hide/reveal, the traffic-light cluster, Peek (2026-10-04, Mac mini M4, 24 GB, CEF, Debug)

Method: `scripts/layout-modes.sh` (spike `layoutmodes`, `App/Sources/Debug/LayoutSpikes.swift`) serves `research/spikes/phase-2.7/` on 127.0.0.1:8770, which also answers as `localhost:8770`, a second site (different eTLD+1). A pinned entry on `http://127.0.0.1:8770/site.html` is the "permanent entry". Pointer input is synthetic `NSEvent`s posted through `NSApp` (the path real events take: local monitors, hit testing, the page's view), page clicks are CDP `Input.dispatchMouseEvent` after a CDP hover (Chromium reports the hovered link as status text, as for a real pointer). Display at **60 Hz**; Room's window main; load average 10.6–13.5; light and dark runs. Timings use `ContinuousClock` on the main thread; frame intervals come from a `CADisplayLink` on the window's view while the slide runs.

### Hide/reveal (spec §E)

| Measure (5 rounds per appearance) | Light | Dark | Configured |
|---|---|---|---|
| Pointer into the 4 pt band → overlay shown (state) | 176.6 ms median, 177.9 p95 | 176.9 / 181.6 | dwell 150 ms |
| Slide | 14–15 frames over 233–250 ms | 14–15 frames | 250 ms ease-out |
| Slide frame intervals (main-thread display link) | 73 frames: median 16.67, p95 16.67, max 16.67 ms (none dropped) | same | 60 Hz |
| Pointer away over the page → hidden | 157.3 ms median, 170.5 p95 | 170.1 / 170.2 | grace 150 ms |

The extra ~25 ms over the dwell and ~5–20 ms over the grace are the timer firing on the main run loop plus the 20 ms poll that reads the state. ⌥⌘S kept the overlay after the pointer left and a page click hid it. While the sidebar is hidden the list keeps the overlay's size, so a reveal only moves a view (no list layout).

Event isolation (Phase 1.4 method, synthetic events through `NSApp`): with the overlay shown, 5 moves and 5 clicks at points over the overlay where the card lies under it reached the page **0 times** (`__clicks 0`, `__downs 0`, `__moves 0`), both appearances.

### The floating traffic-light cluster and the drag regions

The pill is 84 × 38 at (7, 7) around the buttons' 60 × 14 at (19, 19) (AppKit's place with the empty unified toolbar; never moved). It faded **2161–2179 ms** after the last pointer movement near it (2 s + the 150 ms fade), the buttons hid with it and `TrafficLightLayout` kept their frames (the docked header lays out the same after); a movement near it brought both back. A hit test on the pill returns `TrafficLightClusterView` (`mouseDownCanMoveWindow` true); the content band is the top 40 pt of an 806 pt card. Docking hides the pill and shows the buttons. The drags themselves need a person's pointer (the window server runs a window drag; listed for the user).

The toolbar is 36 pt across the card's top: content from 6 pt docked, from 85 pt (past the zoom button + 12) with the sidebar hidden, centred on the buttons' line (20 pt into the bar); the cluster stays hidden while it shows.

### Peek (spec §A.4, §I.6)

What each navigation from the pinned entry did on CEF (both appearances alike):

| Navigation | Result |
|---|---|
| Link to the same site (`/other.html`) | in place |
| Link to the other site | Peek over the pinned page (the page stays at `site.html`) |
| Link into a redirect chain the site starts (`/redirect?to=localhost…`) | in place, through to `localhost:8770/offsite.html?chain` |
| Direct OAuth authorize link on the other site | in place, back to `callback.html?code=room-test` |
| Form post to the other site (303 to it) | in place |
| `location.href = other site` in a click handler, gesture 0.2 s before | in place |
| the same, last input 3 s before | Peek |
| ⇧-click on an off-site link (Chrome's new-window disposition) | Peek |
| `target=_blank` | a new Today tab (as 2.6a), selected |

| Measure (5 opens per appearance) | Light | Dark |
|---|---|---|
| Peek decision → the overlay's first committed frame (`CATransaction` completion) | 22.4 ms median, 23.5 p95 | 22.4 / 23.0 |
| Peek decision → the Peek page's first contentful paint (`performance.timeOrigin` + FCP vs the decision's wall clock; a local page) | 113.7 ms median, 116.8 p95 | 99.7 / 101.8 |

The overlay's 22 ms includes the cancelled navigation's turn (Peek opens on the next main-actor turn after `decidePolicy` returns `.ignore`), the page's `CEFWebContents` creation and the first layout of the card.

Event isolation under the Peek dim: 3 moves over the dim (outside the card) reached the page under **0 times** (`__clicks 0`, `__downs 0`, `__moves 0`); a click inside the card reached the Peek page (its `__clicks` 1) and left Peek open; a click on the dim closed Peek and did not reach the page under. Both appearances.

The open animation starts at the click: after a posted click at (377, 135) the card's first presented frame read back was centred at (631–634, 292–295), 575–581 pt wide, moving from the click toward the card's centre (762, 409); the read-back comes one poll after the animation began, so the frame is already part-way.

Open as Tab made the Peek a Today tab (0 → 1) holding the same `WebContents` (`offsite.html?second`), selected, Peek gone. Esc (unused by the page) closed Peek; ⇧⌘T reopened the same URL over the pinned entry.

Delegate checklist after the card changed (`scripts/chrome-surfaces.sh --session 2.6b --no-captures light`, all checks): every 2.6b result as before (dialogs, auth, certificate and Go Back, permissions, files, menus with Open Link in Peek, popups, downloads, find 14.1 ms median keystroke → match, zoom, print, status pill 606 ms, site panel, withdrawn dialog and prompt, crash, element fullscreen, DevTools 325 ms, audio, keys, Copy URL). One spike-side fix: the status pill's dodge (`leading → trailing`, x 4 → 731) is now polled every 1 ms; at 20 ms the poll missed it because the page clears its status text a few ms after the posted move and the pill leaves.

## Phase 2.7b — split view, the View menu with a page focused, Peek over a split (2026-10-04, Mac mini M4, 24 GB, CEF, Debug)

Method: as 2.7a (`scripts/layout-modes.sh`, spike `layoutmodes`; `-RoomSpikeOnly menu` and `split`, `App/Sources/Debug/LayoutSpikes.swift`, `SplitSpikes.swift`; `-RoomSpikeCapturePrefix phase-2.7b`). Panes are Today tabs on `site.html?pane=N`, alternately on 127.0.0.1 and localhost, loaded before the measure unless said. Pointer input is synthetic `NSEvent`s through `NSApp`; keys are `NSEvent` key-downs handed to `NSApp.mainMenu.performKeyEquivalent` (the path a page's unhandled key takes). Display at **60 Hz**, Room's window main and key, load average 5.0–5.6 (11.0 on the first split-only run), light and dark.

### The View menu with a CEF page focused (2.7b carry-over)

After a click into the page, the responder chain an action walks was `RenderWidgetHostViewCocoa → WebContentsViewCocoa → CefBrowserHostView → RoomCEFContainerView → CEFPageView → PageContainerView → (SplitPaneView → SplitView →) CardContainerView → CardView → BrowserWindowView → RoomWindow → RoomWindowController`: the chain **does** reach the window controller, the window is key and main. Before the fix `NSApp.target(forAction: toggleSidebar:)` was **`RoomWindow`**: `NSWindow` implements `toggleSidebar:` itself (AppKit's own sidebar action) and validated it disabled, so View ▸ Hide Sidebar was disabled in every state, not only with a page focused (Keep Sidebar Open, `toggleSidebarOverlayPin:`, reached the controller and was enabled while hidden). After: both items target `AppDelegate` (`hideOrShowSidebar:`, `keepSidebarOpen:`) and validate enabled docked and hidden; ⌘S through the main menu hid the sidebar and a second ⌘S docked it.

### Split view (spec §D)

| Measure | Light | Dark |
|---|---|---|
| Split created (`joinIntoSplit`: store, sidebar row, card) → both panes laid out with their pages, main thread; both pages loaded before (6 runs) | 12.79 ms median, 13.10 p95, 15.02 max | 13.46 / 15.05 / 16.24 |
| … → the next committed frame (`CATransaction` completion) | 21.20 ms median, 22.88 p95 | 22.04 / 22.49 |
| … with the new pane's page made by the split (one run) | laid out 22.5 ms, page loaded 330 ms | 28.2 ms, 346 ms |
| Resizer drag with two loaded pages: 60 posted drag events ~16 ms apart, display-link intervals | 91 frames: median 16.67, p95 16.67, max 16.67 ms (none dropped) | 89 frames, same |
| Press in the other pane's page → focused pane changed and the header field shows its URL, main thread (9 switches) | 2.68 ms median, 3.03 p95 | 2.35 / 2.76 |
| … → the next committed frame | 7.04 ms median, 9.03 p95 | 6.52 / 6.63 |

The drag ended where it began (ratios committed 0.501 / 0.499), no press reached the page under the resizer (`__downs` 0); a double-click equalised to 0.5 / 0.5. The header field followed the focused pane in every switch. Two panes in a 1244 × 818 window with the sidebar at 280 pt: frames 479 and 478 pt wide with the 1 pt line between, each pane's own page in its own container.

Keys through the main menu (four panes): ⌥⌘G → grid, ⌃⇧1 → pane 1, ⌃⇧] → pane 2, ⌃⇧[ → pane 1, ⌥⌘V → side by side, ⌥⌘H → stacked, ⌥⌘G → grid, ⇧⌘= on four panes → refused (still 4) with the toast. On the first run ⌥⌘H matched the app menu's Hide Others (⌥⌘H, earlier in the menu bar) and hid the other apps; Hide Others lost its key (docs/shortcuts.md gives ⌥⌘H to the layout). ⌘W on the focused (Today) pane: 4 → 3 panes, the entry removed, the next pane focused. ⇧⌘O with Peek open over a two-pane split: 3 panes, the new one is the Peek's page right after A, focused, Peek gone. Element fullscreen of the focused pane: it filled the card alone, the others hidden; after exit all three back. ⌥⌘U left the focused pane alone in the card.

Event isolation with Peek over a three-pane split (Phase 1.4 method): Peek's overlay covers the whole card (the panes together, spec §D); 7 moves at points over the dim on every pane reached **no** pane's page (`__clicks 0`, `__downs 0`, `__moves 0` on A, B and C), and the click on the dim that closed Peek reached none either; the focus stayed on A. Both appearances.

The 2.7a checks re-run on the new card (the page container now inside a `SplitPaneView`): reveal 174.5 / 173.9 ms median, slide frames 16.67 ms throughout, grace 155.8 / 170.1 ms, cluster fade 2172 / 2167 ms, Peek decision → overlay frame 22.1 / 22.9 ms, every Peek rule as in 2.7a, event isolation 0 under the overlay and the dim. The 2.6b delegate checklist (`scripts/chrome-surfaces.sh --session 2.6b`, light): all 26 members called on CEF again (`didConsumeKey` as before never).

## Phase 2.8a — the menu bar, Settings v0, the sidebar on the right, fullscreen on a real Space (2026-10-04, Mac mini M4, 24 GB, CEF, Debug)

Method: `scripts/app-integration.sh` (spike `appintegration`, `App/Sources/Debug/AppIntegrationSpikes.swift`; serves `research/spikes/phase-2.7/` on 127.0.0.1:8770). One pinned entry and two Today tabs on `site.html`, the window 1244 × 818 with the sidebar at 280 pt, on a 1920 × 1080 display at **60 Hz**; load average 4.4–6.1; light and dark. Keys are `NSEvent` key-downs handed to `NSApp.mainMenu.performKeyEquivalent` (the path a page's unhandled key takes); pointer input is synthetic `NSEvent`s through `NSApp`. Captures in `research/screenshots/phase-2.8a/`.

### The menu bar (ROADMAP 2.8 task 1)

| Measure | Light | Dark |
|---|---|---|
| `NSMenu.update()` of every menu and submenu in the bar (validation of all 118 items, a CEF page focused), 50 runs | 0.60 ms median, 1.20 p95, 7.44 max (the first) | 0.32 / 1.27 / 6.72 |

The walk (every item, its key, validation state, the object its action reaches): 118 items incl. what AppKit adds (AutoFill, Start Dictation, Emoji & Symbols, Close All, the window list), 67 enabled in that state, 4 planned items without an action (⇧⌘N 4.8, ⇧⌘2 4.7, ⌥⇧⌘R 4.7, ⇧⌘L 4.1), 96 with a key. Every Room item reaches `AppDelegate` (none elsewhere) and every one has a validator; no key on two commands (AppKit's own hidden twins, Start Dictation 🌐D, share an action). AppKit hides an app's own `toggleFullScreen:` item and shows its own Enter Full Screen with 🌐F; the hidden item keeps ⌃⌘F (the fullscreen check below enters and leaves with it). ⌘← (History ▸ Back's alias): enabled with the page focused and Back possible, disabled while the palette's field edits, so the field keeps the key.

### Settings v0 and the sidebar on the right (task 2)

Settings sections (window width 480): General 220 pt tall, Appearance 269, Search 233, Downloads 168; the window's title follows the section. Settings ▸ Sidebar Right reached the window **22.4 / 21.9 ms** after the store changed (observation, next turn). Docked on the right: sidebar {964, 0, 280, 818}, card {6, 6, 958, 806}, splitter {962, 0, 8, 818} across the sidebar's edge; the traffic lights (19, 19, 60 × 14) sit over the card with the floating cluster shown, the header starts at the 16 pt edge inset. Hidden on the right: the band at the right edge revealed the overlay at {954, 10, 280, 798}; the cluster stays (the overlay is not under the buttons).

### Fullscreen on a real Space (task 6)

| Measure (3 rounds each) | Light | Dark |
|---|---|---|
| ⌃⌘F → `didEnterFullScreen` (the system's Space transition) | 575 / 572 / 561 ms | 568 / 586 / 576 |
| ⌃⌘F → the header laid out on the 16 pt fallback | 593 / 592 / 572 ms | 578 / 605 / 590 |
| ⌃⌘F again → `didExitFullScreen` | 563 / 570 / 560 ms | 572 / 563 / 581 |
| … → the header laid out after the traffic lights again (x = buttons' maxX + 12) | 575 / 594 / 565 ms | 587 / 583 / 592 |

Our part after the system's notification is 5–24 ms (the poll's resolution is a few ms). In fullscreen the window filled the 1920 × 1080 screen, the traffic lights left the window (`buttonsRect` nil), the header moved from x 91 to **16**, the empty `NSToolbar` was hidden (visible again after each exit), the card kept its 6 pt inset (280, 6, 1634 × 1068). Hover reveal in fullscreen: the sidebar hidden, a move into the 4 pt band showed the overlay after **432 / 452 ms** including the 150 ms dwell and the 250 ms slide, at {10, 10, 280, 1060}, its navigation row at the 16 pt inset; leaving hid it again. Back in the window the header was at x 91 as before.

## Phase 2.8b — links from other apps, the first run, Sparkle and Sentry behind opt-ins, the no-request check (2026-10-04, Mac mini M4, 24 GB, CEF, Debug)

Method: `scripts/app-integration.sh --session 2.8b` (spike `appintegration2`, `App/Sources/Debug/AppIntegration2Spikes.swift`): serves `research/spikes/phase-2.7/` on 127.0.0.1:8770 and `research/spikes/phase-2.8/server.py` on :8771 (a one-entry dev appcast, a stand-in Sentry endpoint, a refusing proxy; every request logged), launches Room **by a link** (`open -n -a Room.app <url> --args …`) on a throwaway state with the first-run card shown (`-RoomFirstRun YES`), and hands Room further links on request. The window 1244 × 818, sidebar 280 pt, 1920 × 1080 display at 60 Hz, load average 4.6–10.1 (screen sharing on). Hand-over times are wall clock (`perl Time::HiRes` in the script, `Date` in the app); event, requested and loaded are in-process. "Requested" = `TabController.openNewTab` returned (the entry made and selected, its CEF page created and told to load); "loaded" = the card's page at that URL with `isLoading` false.

### Links from other apps (ROADMAP 2.8 task 3)

| Measure | Light | Dark |
|---|---|---|
| Cold launch by a link: `application(_:open:)` after process start (inbox still closed, the link queued) | 294 ms | 225 ms |
| … queued → page requested (the inbox opens once the engine profile exists) | 183 ms | 205 ms |
| … requested → loaded | 73 ms | 72 ms |
| Running, `open -a Room.app <url>`: hand-over → event / event → requested / requested → loaded | 50.6 / 26.8 / 26.6 ms | 63.6 / 27.3 / 26.9 |
| Running, AppleScript `tell application id "com.lekevicius.room" to open location` (from `osascript`) | 109.6 / 25.2 / 26.4 ms | 92.5 / 25.9 / 26.5 |
| Running, another process's `NSWorkspace.open(_:withApplicationAt:)` (`scripts/lib/open-with-workspace.swift`) | 47.9 / 26.0 / 25.9 ms | 47.8 / 25.3 / 26.4 |
| After ⇧⌘W (no window shown): `open -a` → window shown again, main, tab selected; event → requested | 39.6 ms | 34.4 ms |

Every link became a Today tab at the end of the active space's list and was selected; the cold one was the selected entry once the spike started. All three routes arrive through `application(_:open:)` (no Apple-event handler is registered, `macos-ui-stack.md` §7.4). Room is not the default browser on this Mac (`http` and `https` → Google Chrome.app), so "a link clicked in another app opens in Room" is the user's check after the system dialog; the routes above are what such a click becomes once LaunchServices picks Room.

### The first run (task 4)

The card (238 pt tall at the 268 pt row width, above the footer) shows on a new profile docked left, docked right (window x 970) and inside the hidden sidebar's overlay (pinned; the card is a descendant of the overlay view). Choosing DuckDuckGo on it: the palette's engine read `google` before and `duckduckgo` after, the same `Settings.searchEngine`. Done: the card gone and the list back over the space in **150–153 ms** (a `Motion.fast` fade), `firstRunDone` stored; Settings ▸ Show Welcome Card brought it back (`firstRunDone` false) with the choices kept.

### Sparkle and Sentry behind their opt-ins (task 5)

At launch with both opt-ins off: no `SparkleUpdater` (so no `SPUStandardUpdaterController`) and no `SentryCrashReporter` exist; nothing reached :8771. Automatic checks on: the updater was made and started with `automaticallyChecksForUpdates` true and, with no earlier check in Sparkle's defaults, fetched the dev feed **9–45 ms** later (5 runs) (one `GET /appcast.xml`, user agent `Room/0.1.0 Sparkle/2.10.0`) and showed "A new version of Room is available!" (532 × 402); off again: the schedule off. Check for Updates… then resumed that pending update without a second request; on a run where the feed had been checked minutes before (light then dark, Sparkle's defaults kept), turning automatic checks on made **no** request (Sparkle's 1-day interval) and Check for Updates… made exactly one (the progress window 400 × 146, then the result). Crash reports on with a DSN pointing at :8771: the SDK started (`isReportingCrashes`), **0** requests over 2–3 s (no sessions, tracing or breadcrumbs are enabled; only a crash sends); off: `SentrySDK.close()`. With the build's real DSN (empty) the switch is kept and the reporter is never started.

### The no-request check (exit criterion)

`scripts/netlog-check.sh` (spike `netcheck`): a fresh state and engine directory, the first-run card shown and finished with nothing switched on (suggestions at their default, on), 8 s idle, a browse (`site.html` on 127.0.0.1, `other.html` on localhost, a same-tab navigation to `offsite.html`, a reload), 8 s idle, quit through `NSApp.terminate`. Sparkle's feed, Sentry's DSN and the suggestion proxy all point at the logging server, so any request from Room's own code would land there; `nettop` records every Room process; CEF writes its net-log (`--log-net-log`, capture mode Everything). Two runs, identical:

- **Room's own code: 0 requests** — the logging server got nothing; Room's main process (the app, Sparkle, Sentry, URLSession) moved **0 bytes in, 0 out** over the whole run, its only socket the DEBUG DevTools listener (`*:*` on lo0). No updater or crash reporter was ever created.
- **The engine** (CEF's network service in a `Room Helper` process, 83–87 KB in, 33–39 KB out including the pages), every request by host, attributed by Chromium's traffic annotation (hash → id from the checkout's `tools/traffic_annotation/summary/annotations.xml`), all with initiator "not an origin":

| Host | Requests (URL request jobs) | Traffic annotation | When |
|---|---|---|---|
| accounts.google.com | `POST /ListAccounts` (2 jobs) | `gaia_auth_list_accounts` | launch |
| www.google.com | `GET /async/folae` (3 jobs); a preconnect and a DNS lookup at quit | `aim_eligibility_fetch` | launch, launch idle, browse, quit |
| update.googleapis.com | `POST /service/update2/json` (2), QUIC | `update_client` (component updater) | launch, browse |
| edgedl.me.gvt1.com | `GET /edgedl/diffgen-puffin/…` (1) | `update_client` (a component download) | launch idle |
| clients2.google.com | `GET /time/1/current` (1) | `network_time_component` | launch |
| www.gstatic.com | `GET …/translate_ranker_model_20170329.pb.bin` (1) | `ranker_url_fetcher` (Translate's ranker) | browse |
| 127.0.0.1, localhost | 3 + 5 jobs | page loads and favicons | browse (excluded as page traffic) |

Against 2.4b's B-19 list this adds network time, the component download from `edgedl.me.gvt1.com` and the Translate ranker model (2.4b looked at a typing window only). All are the engine's, not fixed here (B-19, Chapter 3.1).

## Phase 2.9 — grand tour (2026-10-04, Mac mini M4, 24 GB, CEF, Debug)

Method: `scripts/grand-tour.sh` runs every Chapter 1–2 spike in sequence on one Debug build and, per appearance, one state directory and one engine directory, so each spike starts from what the ones before it left (sidebar, history, favicons, settings, profiles, cookies, permissions, windows). Order: layout (smoke launch, the 1.3/1.4 window captures, the 1.4 engine spikes, quit timing), sidebar (the 2.1 kill test, the 2.2 captures and scroll), spaces (2.5), palette (2.4, the suggestion checks through the logging proxy on :8771 so no query leaves the Mac), tabs (2.3), chrome surfaces (2.6a, 2.6b), layout modes (2.7), app integration (2.8a, 2.8b), and the net-log check last. The four test servers start once (:8765, :8766/:8767, :8770, :8771). Fixtures replace the sidebar they find (`-RoomFixtureReplaces YES`), so a spike that needs the 500 or `spaces` fixture gets it on the shared state; everything else accumulates (by the palette group the database holds 50,025 history URLs). `scripts/lib/tour_checks.py` judges each step: exit status, crash reports (the app's, and its helpers' apart: 2.6b's `chrome://crash` renderer is expected), nothing left running, the spike's end line, no `error:` or `capture_timeout:` line, then the phase's own criteria; a result line that is missing fails, so a section a spike skipped cannot pass. Display at **60 Hz**, Room frontmost, load average 4–10. Raw output and captures: `build/grand-tour/<stamp>/` (not committed; the summary below and `summary.md` there list every check, number and capture).

### Runs

| Run | Build | Wall time | Checks | What failed |
|---|---|---|---|---|
| 1, light only (20261004-124944) | 7ac5d84 + the tour's first changes | 20.0 min | 479 passed, 13 failed | the spike bugs and shared-state breaks below (11), Peek (2) |
| 2, light + dark (20261004-131719) | 868f996 | 37.6 min (19.0 + 18.5, build 6 s) | light 488 / 5, dark 488 / 5 | Peek (3, a spike assumption, below), the switch's p95 (1), suggestions left off by the tour's own `suggestoff` step (1) |
| 3, light + dark (20261004-145059) | bd98bf9 | **36.3 min** (18.6 + 17.6) | light **490 / 1**, dark **489 / 2** | the switch's p95 (B-41, both); one 29 ms frame in dark's reveal slide (2.7's bound is none dropped). Screen Sharing had disconnected and the display was a 1280 × 800 pt virtual one, so Dia's 818 pt framing could not fit (card 758 pt tall): reported as a note, not checked |

What running in sequence found (run 1 unless said), each fixed in a spike, not in the product:

| Finding | Kind | Fix |
|---|---|---|
| A fixture asked for on a state that already has entries did nothing (`guard entries.isEmpty`): 500-entry measurements would run on the demo | shared state | `-RoomFixtureReplaces YES` (tour only): the fixture replaces the sidebar; by-hand relaunches keep today's behaviour |
| `HistoryFixture` imported only into an empty history: `palettemeasure` would type over the few rows earlier spikes left | shared state | tops up to the asked row count |
| A second fixture with a "Work" profile made "Work 2" (and a second engine profile directory) | shared state | fixtures reuse "Work" |
| `-RoomFirstRun YES` only skipped auto-finishing: on a state where the first run was done, 2.8b's card checks and the net-log check had no card | shared state | it now resets `firstRunDone` (identical on a fresh state) |
| `palette2`'s captures switch search suggestions off and never back; run 2: `suggestcheck -RoomSuggestionsOff` and `palettemeasure` likewise. The "suggestions on" check then saw 0 requests, the net-log check launched with suggestions off | shared state | each spike restores the setting it found |
| Chromium remembers a profile's answers: 2.6b's re-run of the 2.6a checks found 2.6a's certificate exception and notification denial: no interstitial (B-25's empty card unchecked), no notification prompt, `didFailCertificateCheck` never called | shared state (and B-43) | the 2.6 spikes clear the test origins' permissions and certificate exceptions first |
| `chromesurfaces2` points Settings' download folder at a temp folder and leaves it | shared state | restored |
| `cdp` writes its two captures into `research/screenshots/phase-1.4/` (committed files overwritten) | shared path | writes to `-RoomSpikeCaptureDirectory` when given |
| `popups` took the new popup as `pages.last`; since 2.3 a page opened from another goes right below its opener, so `window.open` reported `inCard=false` | spike bug since 2.3 (fails alone too) | the new page by identity |
| `switch`'s page-visible probe decoded one JSON level too few and never recorded a sample (B-18 blamed the locked screen) | spike bug since 2.3 | decodes; first numbers below |
| Peek did not open in `layoutmodes` after 2.6b (runs 1 and 2, both appearances): the off-site click started no navigation. Bisected outside the tour to a fresh state with the `demo` fixture + the reveal check + Peek: the reveal check's five clicks over the overlay land on rows when the sidebar has any and select another entry, so the pinned page was in the background when Peek's clicks reached it (`peek_start: selected is the pinned entry=false`). An empty sidebar (2.7a/2.7b's runs) has no rows there | spike assumption (an empty sidebar) | Peek's checks select the pinned entry first; Peek decision → overlay frame 21.8 ms median after it |
| Only `layoutmodes`, `chromesurfaces*` and `appintegration*` set the tour's appearance; the 1.4 spikes followed the system | tour | `SpikeRunner` applies `-RoomSpikeAppearance` to every spike |

The screen locked during a later bisect run (macOS locks the session when a Screen Sharing connection drops; the session lock time matched `screensharingd` releasing its assertion both times): window captures fail and activation is refused. The tour now holds `caffeinate -dimsu` and stops with a message when it finds the session locked before a step.

### Numbers (run 2, light / dark; the phase's number for comparison)

| Measure | Light | Dark | Phase |
|---|---|---|---|
| Smoke quit | 0.24 s | 0.22 s | 1.1: 0.23–0.33 s |
| Quit with ten pages (3 runs) | 0.50 / 0.35 / 0.39 s | 0.31 / 0.32 / 0.32 s | 1.4: 0.54–0.66 s at load 35–40 |
| CDP `Runtime.evaluate` round trip, median / p95 | 0.07 / 0.15 ms | 0.17 / 0.45 ms | 1.4: 0.21 / 0.40 ms |
| Memory: baseline; per hidden page at 1 / 10 / 30 | 849 MB; +169 / +270 / +215 MB | 857 MB; +169 / +237 / +210 MB | 1.4: 670 MB; +193 / +327 / +242 MB |
| 30 hidden pages summed RSS, loaded | 7,292 MB, 30/30 | 7,145 MB, 30/30 | 1.4: 7,921 MB, 27/30 |
| Scroll (rAF, mask on), 60 Hz | 60.0 fps, one frame of 31–34 ms per run | 60.0–60.3 fps, one late frame in one run | 1.4: 120 fps, 0 frames > 12.5 ms (120 Hz panel) |
| Kill test, 100 kills | 0 failures, 43 mid-transaction rolled back, commit 6.9 / 13.7 ms | 0 failures, 45 rolled back, 7.0 / 12.4 ms | 2.1: 0 failures, 35 rolled back, 7.3 / 14.2 ms |
| 500 entries: full reload; select; 10-tab drop | 42.9 ms; 3.80 ms; 10.5 ms | 41.0; 3.42; 11.3 ms | 2.2b: 40.6; 0.93; 9.5 ms (select now drives the tab controller) |
| 500-entry scroll, 60 Hz: late frames; proxy120 steps over 8.33 ms | 0; 7 / 4 / 11 of 240 | 0; 7 / 4 / 10 of 240 | 2.2b: 1 in 1,437; 20 / 4 / 4 |
| Space switch, ⌃digit → first slide frame, median / p95 | 12.8 / 15.8 ms | 10.8 / 16.4 ms | 2.5: 10.9 / 17.1 ms |
| Space switch, our code; lists loaded during 60 switches | 6.3 ms; 0 | 5.6 ms; 0 | 2.5: 6.4 ms; 0 |
| 50 loaded pages over 5 spaces, summed RSS | 6,495 MB | 6,509 MB | 2.5: 5.9–6.5 GB |
| Palette open: our code; to the next frame (median / p95) | 2.7 ms; 6.0 / 13.9 ms | 2.5 ms; 5.5 / 14.1 ms | 2.4b: 2.3 ms; 6.2 / 15.0 ms |
| Palette at 50k rows: local results p95; later keys' turn p95; first key median | 7.9; 11.6; 18.8 ms | 7.9; 11.5; 17.9 ms | 2.6a: 6.5–6.7; 9.6–10.4; 17.9–18.9 ms |
| Suggestions through the proxy, on / off | 3 / 0 requests | 3 / 0 | 2.4b: 3 / 0 |
| Tab switch, visible window: `select` call; click → page committed in the card (median / p95) | 5.4 ms; 13.7 / 17.5 ms | 5.7 ms; 14.5 / 18.2 ms | 2.3 (occluded): 4.9; 9.4 / 14.5 ms — B-41 |
| … the page visible after the click; its first frame | 4.2 ms median | 3.9 ms | first measurement (isolated run: first frame 15.1 / 23.0 ms) |
| 10 loaded pages, summed RSS | 3,572 MB | 3,560 MB | 2.3: 4,095–4,215 MB |
| Relaunch: load start; selected page loaded | 0.82 s; 1.44 s | 0.83 s; 1.49 s | 2.3: 0.33–0.45 s; 0.48–0.60 s — B-42 |
| Discard 10 background pages | renderers 10 → 2, 1,853 → 800 MB | 10 → 2, 1,863 → 810 MB | 2.3: 9 → 2, 1,685 → 765 MB |
| Find, keystroke → highlighted match, median / p95 | 15.4 / 26.2 ms | 14.4 / 25.5 ms | 2.6b: 20.7–21.3 / 23.8–26.5 ms |
| DevTools ⌥⌘I → front-end loaded | 329 ms | 340 ms | 2.6b: 328–335 ms |
| Status text → pill (600 ms configured) | 608 ms | 602 ms | 2.6b: 605–619 ms |
| Hide/reveal: band → shown (150 ms dwell); leave → hidden (150 ms grace) | 193; 172 ms | 192; 156 ms | 2.7a: 177; 157–170 ms |
| Split created → laid out; → next frame | 14.2; 22.9 ms | 11.8; 22.3 ms | 2.7b: 12.8–13.5; 21.2–22.0 ms |
| Pane focus click → field; → next frame | 1.6; 5.9 ms | 2.0; 7.1 ms | 2.7b: 2.4–2.7; 6.5–7.0 ms |
| Peek decision → overlay frame; → the Peek page's first contentful paint (run 3) | 21.4; 91.7 ms | 30.0; 102.2 ms | 2.7a: 22.4; 99.7–113.7 ms |
| Menu bar `NSMenu.update()` (121 items) | 0.82 / 2.39 ms | 0.83 / 2.42 ms | 2.8a: 0.32–0.60 / 1.2 ms (118 items) |
| ⌃⌘F → header on the fallback; exit → header back | 625; 588 ms | 631; 592 ms | 2.8a: 572–605; 565–594 ms |
| Cold launch by a link: event → page requested; → loaded | 598; 68 ms | 610; 74 ms | 2.8b: 183–205; 72–73 ms — B-42 |
| Running link, event → requested (`open` / AppleScript / `NSWorkspace`) | 22.4 / 22.9 / 22.5 ms | 23.1 / 21.9 / 23.1 ms | 2.8b: 25.2–27.3 ms |
| Net-log: Room's own requests; main process bytes; engine hosts | 0; 0 in, 0 out; 3 (accounts.google.com, update.googleapis.com, www.google.com) | same | 2.8b: 0; 0; 6 on a fresh profile (B-19) |

Run 3 (1280 × 800 display, no Screen Sharing) moved little: switching 11.5 / 18.2 and 13.2 / 19.1 ms, the page visible after 4.1 / 3.9 ms, relaunch to the selected page 1.40 / 1.28 s.

Not regressions: tab switching and the palette's first key are where the phases left them once conditions are equal; the visible-window switch and the relaunch are new conditions (B-41, B-42). Two findings that are the product's, both in the backlog: `RoomStorage.open` runs `PRAGMA integrity_check` over the whole database at every launch, 0.35–0.56 s at 50k history rows (B-42); a certificate exception cannot be revoked from Room (B-43). The spikes' CEF-only driving paths are B-44.

## Phase 3.1a — merge, spike gate, identity, Room.app on RoomCore, bootstrap, driving surface (2026-10-04, Mac mini M4, 24 GB, RoomCore, Debug)

Component build `out/dev` (tag 154.0.8037.58, patches 0001–0009, 0011, 0012; 0010 parked), ad-hoc signed, mock keychain (no team signature). Load average 5–22 during the runs (Claude, VS Code and the usual background apps; the grand tours and builds in sequence, never concurrently). Console unlocked throughout.

### The baseline (`scripts/roomcore-baseline.sh`, embryo host)

| Run | nav (assertions) | Ten-page quit ×3 (`NSApp.terminate` → exit) | Helpers seen / left | Crash reports | load1 |
|---|---|---|---|---|---|
| After the merge (`build/baseline/3.1a-merge`) | passed, 17.4 s | **0.305 / 0.538 / 0.263 s** | 26 / 0 | 0 | 12.0 / 9.7 / 11.9 |
| After the spike gate, identity and bootstrap (`build/baseline/3.1a-identity`) | passed, 12.7 s | **0.276 / 0.259 / 0.233 s** | 26, 26, 24 / 0 | 0 | 6.4 / 10.9 / 12.1 |

Stub hits in the second nav run (first hit each): `GetAutofillBubbleHandler`, `GetCanResize`, `GetRestoredState`, `GetStatusBubbles`, `GetWindowShowState`, `GetWorkspace`, `IsVisibleOnAllWorkspaces`, `OnTabDetached`, `UpdateLoadingAnimations`, `UpdateReloadStopState`, `UpdateToolbar`, `UpdateToolbarSecurityState` (12). Room.app on RoomCore creates no `Browser` yet (pages are standalone `WebContents` until 3.2), so its runs hit no `RoomBrowserWindow` member.

### Identity and the data root

- `plutil -p` of `build/roomcore/DerivedData/Build/Products/Debug/Room.app`: `CFBundleIdentifier` app.room.desktop, `CFBundleName` Room; framework app.room.desktop.framework, `RoomCoreCommit` 13d9ebb-dirty. Helpers: Room Helper, (GPU), (Aperitif), (Aperitif GPU) → app.room.desktop.helper; (Renderer), (Aperitif Renderer) → app.room.desktop.helper.renderer; (Alerts), (Aperitif Alerts) → app.room.desktop.framework.AlertNotificationService (Chromium's own suffixes; PLAN's `.helper.gpu`/`.helper.plugin`/`.helper.alerts` are the CEF helpers', B-46).
- Fresh `-RoomEngineDirectory /tmp/room-3.1a/engine` after one launch of Room.app on RoomCore with `-RoomSidebarFixture demo`: `Local State`, `Room Profile Default` (the app's profile, Chapter 2 layout), `Default` (Chromium's startup profile), `RoomCore.log`, `Crashpad/{attachments,completed,new,pending,settings.dat}`, plus Chromium's component directories (43 entries while running, 39 after the quit: the `Singleton*` locks and a journal go). `RoomCore.log` carries `Room crash keys: room-app-version=0.1.0 (1) room-chromium=154.0.8037.58 room-commit=13d9ebb-dirty`; after resolving `/tmp` → `/private/tmp` no helper logs "Unable to initialize logging" (before: one line per sandboxed helper).
- Crashpad handlers (`ps`): `--database=/private/tmp/room-3.1a/engine/Crashpad --annotation=prod=Room_Mac --annotation=ver=154.0.8037.58`, no `--url` (B-14 verified).
- `RoomCore.framework` staged: **916 MB with all 228 locales (51 MB), 864 MB without** (component build, 518 dylibs; the release size is 3.1b's).
- `gn gen` of a scratch out directory with `room_enable_spikes = false`: 34,288 targets in 14.7 s, no `room_worker_shutdown_probe` target (deleted afterwards; no build).

### Room.app on RoomCore

`-RoomStateDirectory /tmp/room-3.1a -RoomEngineDirectory /tmp/room-3.1a/engine -RoomSidebarFixture demo`: the demo sidebar, the selected pinned entry (AppKit documentation) rendered in the card (`research/screenshots/phase-3.1a/roomcore-room-app-window.png`, a window-server capture; the in-process captures `roomcore-inprocess-card-page-{light,dark}.png` from `-RoomSpike capture` show the card empty, since own-window renders miss Chromium's GPU layer (B-9) and `captureViewport` is 3.3b). State opened in 10.4 ms (quick_check). AppleEvent quit: exit in ~1 s, no crash report; SIGTERM likewise.

### The grand tour's layout and sidebar sections (`--groups layout,sidebar light`)

| Engine | Tour | Checks | Wall time |
|---|---|---|---|
| CEF (`build/grand-tour/20261004-171019-cef`) | f736067 | **177 passed, 0 failed** | 7.5 min |
| RoomCore (`build/grand-tour/20261004-172247-roomcore`) | f736067 | **137 passed, 38 failed** | 9.1 min |

On RoomCore every step ran to its end line (no skipped section); the 38 failures, by cause:

| Step | Failed / checks | Why |
|---|---|---|
| smoke | 2 / 6 | `helpers_left=1` at 0.5 s: Chrome's `code-sign-clone-cleanup` helper exits 1–1.8 s after the browser (B-45); quit 0.17 s |
| quittiming | 3 / 9 | the same helper at 1 s; quits 0.30 / 0.29 / 0.42 s, 0 crash reports |
| cdp | 2 / 12 | `executeJavaScript`, `captureViewport` not supported (3.3b) |
| scroll | 3 / 10 | frame timing read by script (3.3b) |
| memory | 3 / 16 | the hidden-page rAF probe is a script (3.3b); the RSS rows ran |
| audio | 4 / 13 | `play()` and the oscillator are scripts (3.3b); `isAudible` is not reported (3.3a) |
| popups | 6 / 12 | element positions by script (3.3b); `window.open`/`target=_blank` need `AddNewContents` (3.2a); alerts need the dialog manager (3.4b) |
| hidden | 5 / 11 | the visibility probe is a script (3.3b) |
| keys | 6 / 16 | the field setup is a script (3.3b); ⌘T/⌘L from the page need the keyboard hooks of a `WebContentsDelegate` (3.2b) |
| devtools | 4 / 10 | no DevTools host (3.3b) |

Passed in full on RoomCore: window, resize, open10, diaframe, killtest, sidebardemo, sidebar500.

### B-42: the integrity check at launch

50,000-URL history fixture (`-RoomHistoryRows 50000`, `Room.sqlite` 40 MB), CEF Debug app, the open of the state database as the app logs it (`RoomStore.open`), three launches each, load 9–13:

| Previous session | Check | Open time |
|---|---|---|
| clean quit (after) | `PRAGMA quick_check` | **151.0 / 150.3 / 153.0 ms** |
| `kill -9` (and every launch before 3.1a) | `PRAGMA integrity_check` | **317.9 / 328.7 / 313.8 ms** |

A clean relaunch saves ~165 ms on this state.

## Phase 3.1b — release build, signing, notarization, network silence, Widevine, shutdown watchdog, Sparkle (2026-10-04, Mac mini M4, 24 GB, RoomCore)

**Conditions.** Every run below is on the **component build** (`out/dev`, tag 154.0.8037.58, eleven patches, `room_enable_spikes=true`) while the **official release build** (`out/release`, `args/release.gn`) compiled beside it at 6 jobs from 17:54: load average 11–35 for single-instance runs (160 at the concurrent watchdog harness), swap 1.6 of 2 GB used, `vm_stat` pageouts 53,796 at the build's start, 55,877 at 19:18 (+1,416 of that during the concurrent watchdog harness, which was stopped for it; swapouts flat at 359,844 after 18:23). Console unlocked throughout. Evidence (not committed): `build/evidence-3.1b/`.

### Signing and notarization (`scripts/roomcore-sign.sh`, component build)

`ROOM_SIGN_COPY=build/roomcore-signed scripts/roomcore-sign.sh build/roomcore/DerivedData/Build/Products/Debug/Room.app --no-notarize`: Developer ID Application: Jonas Lekevicius (N56PMJ99UT), hardened runtime, secure timestamp, inside-out (518 framework dylibs, crashpad handler and the two tools, eight helpers, the framework, Sparkle's two XPC services, Autoupdate and Updater.app, Sparkle and Sentry, the two debug dylibs, the app): **31.4 s**. Helper entitlements as Chrome's own signing config: `allow-jit` on (GPU), (Renderer), (Aperitif GPU), (Aperitif Renderer); none on Room Helper, (Aperitif), (Alerts), (Aperitif Alerts).

- `codesign --verify --deep --strict --verbose=2`: "valid on disk", "satisfies its Designated Requirement".
- `spctl --assess --type execute` before notarization: "rejected, source=Unnotarized Developer ID".
- Notarization: `ditto` zip **290 MB** in 44 s; `notarytool submit --keychain-profile room --wait`: submission **41d74c9a-dc7b-4fec-aaf7-f2ae65a8905b**, **Accepted** in 134 s, log: 0 issues, "Ready for distribution". The notary service accepted the component layout (945 MB app, 518 dylibs) as it is.
- `stapler staple`: "The staple and validate action worked!"; `spctl --assess`: "**accepted, source=Notarized Developer ID**".

### The keychain check on the signed build

`build/roomcore-signed/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-3.1b/kc -RoomEngineDirectory /tmp/room-3.1b/kc/engine -RoomStartURL https://example.com/` (team-signed, so `RoomApplication` uses the login keychain): 8 helpers by 10 s, and **SecurityAgent showed "Room wants to use your confidential information stored in “Room Safe Storage” in your keychain"** (`research/screenshots/phase-3.1b/keychain-check-prompt.png`) from ~10 s to the 60 s limit; the card stayed white with the row's spinner (the navigation waits on the cookie store, `keychain-check-page-waiting.png`); the net-log has the example.com request started and nothing completed. The item is from 2026-10-02 (created by the `com.lekevicius.room` identity), so the new identity is not on its access list: one prompt is the expected first-launch behaviour (PLAN §4 Keychain). Room was killed at 60 s; the dialog was left alone (by-hand 3.1b steps 1–2). The same net-log shows one engine request at launch: `www.gstatic.com` translate ranker model (below).

### Network silence

**Room.app on RoomCore, launch + 10 min idle + browse + quit** (`ROOM_APP=build/roomcore/…/Debug/Room.app ROOM_NETCHECK_IDLE=600 scripts/netlog-check.sh`; fresh state, first-run card shown and finished with nothing switched on; load 29 at launch, 17–21 during the idle): launch → idle 600.0 s → browse (`site.html`, `other.html`, a same-tab navigation, a reload on 127.0.0.1:8770/localhost:8770) → 8 s → quit.

| Who | Requests |
|---|---|
| Room's own code (logging server for the feed, the crash endpoint and the suggestion proxy; `nettop` of the main process) | **0** (main process 0 bytes in, 0 out; no updater or crash reporter created) |
| Page traffic (excluded) | 127.0.0.1 1, localhost 3 |
| **Engine** | **1**: `GET https://www.gstatic.com/chrome/intelligence/assist/ranker/models/translate/2017/03/translate_ranker_model_20170329.pb.bin`, traffic annotation `ranker_url_fetcher`, initiator "not an origin", in the **launch** phase (the first `WebContents` creates Translate's ranker, `TranslateRankerImpl`, which fetches its model when `TranslateRankerQuery` or `TranslateRankerEnforcement` is on; both are enabled by default) |

Not covered by `room/core/room_network_policy.cc` (the branch's idle audit ran on the embryo host's about:blank, where no Translate client is created). The same run with `--disable-features=TranslateRankerQuery,TranslateRankerEnforcement,MacAppCodeSignClone` appended (`netcheck-roomcore-ranker-off`, 8 s idle): **0 engine requests** (page traffic only; the network helper's only sockets loopback). The `//room` default is the follow-up's edit (the build reads `//room`).

**Embryo host, 600 s idle** (`scripts/roomcore-netlog.sh`, about:blank, fresh profile, load 18–21): exit 0, 645 s process, idle-complete 600; net-log 18 events over 637.9 s: **0 requests, 0 connections, 0 DNS, 0 TLS errors**. The branch's 62 → 0 holds on this machine's build.

**Browsing (B-39)**: `-RoomSpike open10` on the host with `--log-net-log` (ten real sites ready in 38 s, load 11–19, `roomcore-netlog-summary.py`): 3,384 request attempts, 640 connections; **94 TLS −107 failures on 26 hosts**, every one an ad or analytics host (googlesyndication, doubleclick, googletagmanager, google-analytics, optimizely, scorecardresearch, chartbeat, securemetrics.apple.com …) requested by the pages themselves (`blink_resource_loader`, initiators nytimes.com 14, theverge.com 12, bbc.com 8, stackoverflow.com 4, developer.apple.com 1); each resolves to `0.0.0.0` / `::` on this Mac (resolvers 100.100.100.100 and the router): DNS sinkholes, as on the laptop. Not the engine's. The engine's own requests while browsing: FedCM well-known fetches from pages (accounts.google.com, google.com, www.google.com; initiator null, page-triggered) and **`autofill_query` to content-autofill.googleapis.com, 13 attempts** (Autofill's crowdsourced field-type query, sent when a page has forms; feature `AutofillServerCommunication`, enabled by default): a request the user did not ask for and the policy does not cover (a `//room` default for the follow-up).

### Widevine on demand (`scripts/roomcore-features.sh widevine`, host)

| Run | EME result | Engine requests | Load |
|---|---|---|---|
| Fresh profile | `com.widevine.alpha` supported, MediaKeys created, **7.96 s** after the request; WidevineCdm 4.10.3050.0 installed | `update_client` only: `POST update.googleapis.com/service/update2/json` +0.006 s, `GET edgedl.me.gvt1.com/…/4.10.3050.0/` +0.198 s, completion ping `POST update.googleapis.com` +5.274 s (the stated exception) | 16 |
| Same profile, CDM installed (`ROOM_FEATURE_PROFILE_FROM`) | supported, MediaKeys created in **2.74 s** | **0 external** (loopback page and favicon only) | 15 |

### Licensed playback (Room.app on RoomCore)

`research/spikes/phase-3.1b/widevine-demo.html` served on 127.0.0.1:8790 (Shaka Player 4 from jsDelivr, Shaka's public Sintel Widevine DASH stream, Google's no-auth test license proxy `cwip-shaka-proxy.appspot.com/no_auth`, muted autoplay, the page's own `getVideoPlaybackQuality` counters in its title and status line), `-RoomStartURL` on a fresh state and engine directory: the CDM provisioned on the page's request (update_client 2 + 1, then the license POST from the page), and **playback started**: at 19 s "playing, keySystem=com.widevine.alpha, readyState=4, currentTime=4.39, decoded=109, dropped=0"; at 81 s currentTime 66.39, **decoded 1,597 frames, dropped 0** (`research/screenshots/phase-3.1b/widevine-demo-playing-{30,90}s.png`, window-server captures). The video rectangle is black in the captures (protected frames are not in a window capture); the counters are the evidence. The same run's net-log again has the `ranker_url_fetcher` request at launch. A real service (Netflix, Spotify) is the user's (by-hand 3.1b step 4).

### Shutdown watchdog (B-38, `scripts/roomcore-watchdog.sh`, embryo host on the component build)

**Serial** (`roomcore-watchdog.sh … 20 serial`: one ten-real-page quit through `NSApp.terminate` per run, fresh profile each, the `roomcore-baseline.sh` quit; nav baseline before it passed in 15.9 s): **20 quits, 20 clean** (exit 0, 0 helpers left after the 5 s grace, 0 crash reports), load1 33–49:

0.467, 0.836, 0.584, 0.830, 0.392, 0.597, 0.346, 1.222, 3.751, 0.468, 0.677, 1.007, 2.024, 0.860, 2.093, 0.530, 0.968, 0.729, 0.945, 0.973 s — **median 0.833 s**, max 3.751 s. Seven more attempts were rejected fixtures (a page, mostly Stack Overflow, still loading at "ready"; not quit samples). An earlier serial pass (`watchdog-component/serial`, load 15–26) quit 0.498 / 0.872 / 0.616 / 0.438 / 0.639 / 0.341 s, all clean, before its seventh fixture was rejected (that pass stopped at the first rejection, which is why the harness now retries).

**Concurrent** (the branch's reproduction, `roomcore-shutdown-local.py --mode room --corpus real`: three hosts each load the ten real sites, then quit): **stopped after 4 of 20 rounds** because `vm_stat` pageouts grew (+1,416 pages) while it ran beside the release build (load1 at the rounds' start 27 / 155 / 123 / 147; the release build's step rate fell from ~150 to ~70 a minute). Of the 12 quits, **11 hit Chrome's 10 s teardown watchdog** ("Teardown watchdog expired; recording dump and terminating", exit 2, a minidump each), one exited 0; helpers left after the 5 s grace 1–13 (all exited later); 0 macOS crash reports.

| Round / host | Ready s | Exit | Main thread in the watchdog dump | Threads not yet started |
|---|---:|---:|---|---:|
| 1/1, 1/3 | 50, 50 | 2, 2 | `ThreadPoolImpl::Shutdown` → `TaskTracker::CompleteShutdown` | 3, 3 |
| 1/2 | 49 | 2 | `BrowserProcessIOThread::ProcessHostCleanUp` (the network service wait) | 2 |
| 2/1, 2/2 | 45, 46 | 2, 2 | `CompleteShutdown` | 0, 0 |
| 2/3 | 47 | 2 | network service wait | 0 |
| 3/1, 3/2 | 48, 49 | 2, 2 | `CompleteShutdown` | 0, 0 |
| 3/3 | 63 | 2 | network service wait | 0 |
| 4/1, 4/3 | 46, 46 | 2, 2 | network service wait | 1, 1 |
| 4/2 | 63 | 0 | — | — |

(`scripts/roomcore-watchdog-stacks.py`: LLDB over each dump against the host that ran; full backtraces beside the dumps.) The two waits are the branch's two (its groups 2 and 3). "Threads not yet started" are threads in `ThreadFunc` → `_pthread_set_properties_self` (created during shutdown, not running yet: the worker-start/QoS lead behind parked 0010); present in 4 of the 11 dumps, absent in the other 7. In a `CompleteShutdown` dump without them (2/1) a background pooled worker is inside `fsync` (`sql::Transaction::Commit` from `PredictorDatabaseInternal::Initialize`, a SKIP_ON_SHUTDOWN task) while the release build loads the disk; background-QoS threads are I/O-throttled on macOS, which would make the stall load-sensitive (a lead, not investigated). After `NSApp.terminate` the host logs launches of new utility processes (audio, video capture enumeration) during teardown. Reproduction rate on the component build under this load: 11 / 12; serial with one host: 0 / 20.

### Sparkle packaging (`scripts/sparkle-package.sh`, the notarized component build)

`hdiutil create -fs HFS+ -format UDZO -srcfolder build/roomcore-signed/Room.app`: **DMG 339,023,043 bytes (323 MiB)** in 14.1 s from a 949 MiB app (the notarization zip of the same app: 290 MB). This is the component build (518 dylibs, `Room.debug.dylib`); the release build's archive is the number that matters (PLAN §7 risk 12), repeated by the follow-up. **The EdDSA signature and the appcast entry were not made**: `sign_update` blocked in `SecItemCopyMatching` → `SecKeychainItemCopyContent` reading the private key (login keychain, account `ed25519`), waiting on a keychain access prompt queued behind the stale "Room Safe Storage" dialog; killed after 2 min (by-hand 3.1b step 3).

### B-47 and B-45

- **B-47** (`scripts/lib/room-ae.swift` through `scripts/lib/room-process.sh`; `run-spike.sh`, `sidebar-snapshots.sh`, `window-snapshots.sh`, `smoke-launch.sh`, `quit-timing.sh`): `-RoomSpike diaframe` with `pgrep` afterwards — RoomCore ×2 and CEF ×4: Room frontmost from its window's appearance to its quit (`lsappinfo front` each second: RoomCore 5 of 5 s, CEF 2–3 s), exit 0, **no Room process left and no stray relaunch** in any run. The first attempt (JXA `Application(pid).activate()`) relaunched the CEF app without arguments once, when the 1 s spike quit during the call ("stopping stray relaunch 97471"; it opened the real CEF state for 3 s): JXA resolves the pid to the app and activates by bundle. A raw AppleEvent addressed to the pid (`NSAppleEventDescriptor(processIdentifier:)`) fails with procNotFound instead; it is retried for up to 1 s (activate) or 15 s (quit) while the pid lives, because a RoomCore app still launching under this load is not eligible for events for ~5–9 s.
- **B-45**: `--disable-features=MacAppCodeSignClone` (the feature in `chrome/browser/mac/code_sign_clone_manager.mm`, enabled by default) removes the `code-sign-clone-cleanup` helper (`smoke-launch.sh` with it: `clone_cleanup_seconds=0`); the `//room` default is the follow-up's edit. Meanwhile `smoke-launch.sh` and `quit-timing.sh` wait up to 5 s for that one helper type by name and report it as `clone_cleanup_seconds`. `smoke-launch.sh` on Room.app on RoomCore, 15 s before the quit, ×3: quit 0.12 / 0.11 / 0.12 s, exit 0, **helpers_left=0**, 0 crash reports, clone cleanup 1.7 / 2.0 / 1.7 s (load 14–19); with the default 5 s before the quit the app had not finished launching (quit 5.5–6.4 s, the AppleEvent waited for it; load 22–25). `quit-timing.sh` (ten real pages, AppleEvent quit) ×3: quit **1.67 / 0.62 / 0.39 s**, helpers_left=0, 0 crash reports, clone cleanup 1.4–1.5 s (load 15–29); the first is over the tour's 1.5 s bound at load 15.

### The release build

Still compiling at the end of the session (`build-log.md` "Phase 3.1b on the Mac mini"): its wall time, Room.app size (framework, helpers, locales, dSYMs apart), cold launch (three launches, process start to the first page loaded), the signing, notarization, keychain, watchdog (both harnesses, then 0010's comparison) and Sparkle numbers are the follow-up's, on `scripts/roomcore-package.sh --release`.


## Phase 3.1b-2 — release build measured, signed and notarized, network defaults, watchdog on the release build (2026-10-04/05, Mac mini M4, 24 GB, RoomCore release build)

**Builds and apps.** The official release build (`out/release`, `args/release.gn`, eleven patches with the amended 0001 and 0004, `//room` at `3086f4b`) and the component build (`out/dev`, same series and `//room`). Apps, each named per row below: **Release app** = Room.app on RoomCore, Release configuration, ad hoc (`build/roomcore-release/DerivedData/Build/Products/Release/Room.app`, mock keychain by itself); **Debug app over release** = the same Swift app in the Debug configuration over the same release framework (`CONFIGURATION=Debug scripts/roomcore-package.sh --release --app-only`; its DEBUG spikes go through the `Engine` protocol); **release host** = the embryo host, Release configuration, over the release framework (its `nav`/`open10`/`idle` drives are not spike-gated, so both watchdog harnesses run on it unchanged); **signed copy** = a Developer ID clone of the Release app (`build/roomcore-release-signed`), used only for `codesign`/`spctl`/notarization/size/DMG. **Dev app** = Room.app on RoomCore, component Debug build. No build ran during any measurement below; load is stated per run. Evidence (not committed): `build/evidence-3.1b2/`.

### `//room` defaults on the component build (dev app, the changed code)

`room/core/room_network_policy.cc` now disables `TranslateRankerQuery`, `TranslateRankerEnforcement`, `AutofillServerCommunication` and `MacAppCodeSignClone` (names checked in the M154 checkout: `components/translate/core/browser/translate_ranker_impl.cc:96–97`, `components/autofill/core/common/autofill_debug_features.cc:138`, `chrome/browser/mac/code_sign_clone_manager.mm:513`).

- **Baseline** (`scripts/roomcore-baseline.sh`, embryo host, dev): nav passed (10.6 s), ten-page quits **0.269 / 0.261 / 0.240 s**, 26 helpers observed, 0 left, 0 crash reports, exit 0 (load 11–15). A first pass (nav 20.6 s, quit 0.293 s) stopped when its second fixture was rejected (Stack Overflow still loading).
- **`smoke-launch.sh` ×3** (dev app, 15 s, throwaway state): quit **0.13 / 0.09 / 0.13 s**, exit 0, helpers_left 0, 0 crash reports, **`clone_cleanup_seconds` 0** each (3.1b: 1.7–2.0 s; B-45's helper is gone) (load 6–8).
- **`quit-timing.sh` ×3** (dev app, ten real pages, AppleEvent quit): **0.40 / 0.29 / 0.24 s**, helpers_left 0, 0 crash reports, `clone_cleanup_seconds` 0 (load 7–11).
- **Net-log, launch + 600 s idle + browse + quit** (`ROOM_NETCHECK_IDLE=600 scripts/netlog-check.sh`, dev app, fresh state, first-run card shown; 639 s from launch to browse; load 18–32 at launch, falling): Room's own code **0** (main process 0 bytes in/out); page traffic 127.0.0.1 1, localhost 3; **engine 0 requests** (3.1b: 1, `ranker_url_fetcher`).
- **Translate without the ranker** (dev app, `-RoomStartURL https://de.wikipedia.org/wiki/Webbrowser`, 25 s, `--vmodule=*translate*=2`): the page rendered (`research/screenshots/phase-3.1b-2/translate-de-wikipedia-dev.png`), exit 0, 0 helpers left, 0 crash reports, net-log 7 requests all page (`blink_resource_loader` 5, `navigation_url_loader` 1), no ranker fetch. No translate offer appears and the log has no language-detection line, only "Registering TranslateKit component": RoomCore's pages are standalone `WebContents` without Chrome's tab helpers (3.1a deviation 6), so the translate client is not attached yet; the offer path is 3.4/3.7's (infobar delegate). Nothing crashed.

### The release build (`build-log.md` "Phase 3.1b-2")

**4 h 43 min 28 s** of build work at 6 jobs (3.1b's 4 h 42 min 40 s + 48 s after the 0001 fix), the framework's ThinLTO link 18 min 12 s at **6.80 GiB `max_rss`**: it fits in 24 GB. Two more official-only failures surfaced in packaging and were fixed in patch 0004 (the framework's export list hid the public ObjC classes; the export-order check then rejected them); the relink after them took 329 s (ThinLTO cache) at 7.53 GiB.

### Release staging (`scripts/roomcore-package.sh --release`)

First run against a real static framework. What differed from 3.1b's assumptions, each fixed in the script or the patches:

1. The Swift app did not link: `_OBJC_CLASS_$_RoomApplication` and four more undefined. The official framework is linked with `-exported_symbols_list chrome/app/framework.exports` (three symbols); patch 0004 adds `//room/core/room_core.exports` (the five `ROOM_EXPORT` classes and their metaclasses) and points `verify_chrome_framework_order` at framework.order + that list. After it, `nm -jUng RoomCore`: `_ChromeAppModeStart_v8`, `_ChromeWebAppShortcutCopierMain`, `_ChromeMain`, then the ten class symbols.
2. dSYMs: `out/release` holds 128 dSYMs, 3.6 GB, including build tools (`v8_context_snapshot_generator` 0.9 GB, `mksnapshot` 0.3 GB); the copy filled the internal disk (3.7 GB free) during the first packaging. The script now stages only the dSYMs of binaries the framework ships: 15, **2.2 GB** (RoomCore.dSYM 2.13 GiB).
3. The release app is no longer team-signed in place: a team-signed `app.room.desktop` uses the keychain item that prompts, so measurements use the ad-hoc product and the signed product is a copy (`ROOM_TEAM_SIGN=1` restores the old behaviour, `ROOM_NOTARIZE=1` still signs and notarizes).
4. Otherwise as 3.1b wrote it: `component=0`, no dylib copy, `-lchrome_dll` dropped; the framework's own Libraries are libaperitif, libvk_swiftshader, libvulkan and three component data folders (ANGLE is static).

`ls RoomCore.framework/Versions/154.0.8037.58` (in the Release app): `Headers Helpers Libraries Modules Resources RoomCore _CodeSignature`; `plutil -p Room.app/Contents/Info.plist`: `CFBundleIdentifier` app.room.desktop, `CFBundleShortVersionString` 0.1.0, `CFBundleExecutable` Room, the HTML/URL document and http/https URL types (full output `release-layout.txt`). Packaging took 107 s (stage 3.1 s, host 14.5 s, app 89.8 s); the Debug app over release 37 s.

### Sizes (Release app, `du -sk`)

| Part | KB | MB |
|---|---:|---:|
| **Room.app** | 390,928 | **382** |
| RoomCore.framework | 372,472 | 364 |
| framework binary `RoomCore` (static; debug info in the dSYM) | 269,836 | 264 |
| Resources (paks, ICU, V8 snapshot, locales) | 83,264 | 81 |
| of which 220 locales (`*.lproj`) | 50,088 | 49 |
| Libraries (libvk_swiftshader 14.8 MB, libvulkan 0.5 MB, libaperitif 0.1 MB, component data) | 15,804 | 15 |
| Helpers (eight helper apps, crashpad handler, app_mode_loader, web_app_shortcut_copier) | 3,444 | 3.4 |
| Swift app executable (`Contents/MacOS`) | 15,468 | 15 |
| Sparkle.framework / Sentry.framework | 2,748 / 48 | 2.7 / 0.05 |
| dSYMs, beside the app (15; RoomCore.dSYM 2,237,148 KB) | 2,317,100 | 2,263 |
| signed copy (Developer ID) | 391,168 | 382 |

Against the component build: Room.app 945 MB, framework 916 MB (518 dylibs).

### Cold launch (Release app)

`scripts/roomcore-cold-launch.py` (new): process spawn to the start page's `load` event, three launches on fresh state each (`-RoomStateDirectory`, `-RoomStartURL` of a 127.0.0.1 page whose load handler beacons back, `--user-data-dir` and `--log-file` in the scratch directory so the real data root is untouched: checked, nothing under `~/Library/Application Support/Room/RoomCore` newer than the run), then a quit by pid. The Release app has no DEBUG flags; a scratch `HOME` does not move `URL.applicationSupportDirectory` (tested), so it was not used.

| Run | Launch → page loaded | Navigation → load | Quit | Exit | Helpers left | load1 |
|---|---:|---:|---:|---:|---:|---:|
| 1 (first launch of this build) | **2.715 s** | 58.5 ms | 0.085 s | 0 | 0 | 7.2 |
| 2 | **0.414 s** | 44.7 ms | 0.087 s | 0 | 0 | 8.0 |
| 3 | **0.412 s** | 48.9 ms | 0.115 s | 0 | 0 | 7.1 |

Median 0.414 s. The first launch of a newly built binary is 2.3 s slower (not profiled; the first execution of new code is when macOS assesses its signature, and the 264 MB binary was not in the page cache); later launches, each on a new profile, take 0.41 s. (2.3's relaunch on CEF, a different measure on an existing state: 0.48–0.60 s to the selected page loaded.)

### Signing and notarization (signed copy)

`ROOM_SIGN_COPY=build/roomcore-release-signed scripts/roomcore-sign.sh <Release app>`: signed in **9.3 s** (3.1b's component build: 31.4 s for 518 dylibs). `codesign --verify --deep --strict --verbose=2`: "valid on disk", "satisfies its Designated Requirement"; `codesign -dv`: `Identifier=app.room.desktop`, `flags=0x10000(runtime)`, `TeamIdentifier=N56PMJ99UT`; `spctl --assess` before notarization: "rejected, source=Unnotarized Developer ID". Notarization: zip **168,923,146 bytes (161 MB)**, submission **bfee631a-5b17-4400-80f0-25433022a0a7**, **Accepted** in 61.3 s, log "Ready for distribution", issues none; stapled; `spctl --assess`: "**accepted, source=Notarized Developer ID**". The signed copy was not launched (its keychain prompt is the user's, by hand).

### Ten real sites (release framework)

- **Debug app over release**, `-RoomSpike open10` (`run-spike.sh`, throwaway state): `pages: 10`, `ready: 40` s (load 7.0; an earlier run 11 s at load 3.8), every page's title in the sidebar (`research/screenshots/phase-3.1b-2/open10-release-debug-app.png`, a window-server capture); quit 0.177 s (0.230 s earlier), 0 helpers left.
- **Release host**, `-RoomSpike open10 --log-net-log` (all ten not loading at ready, 63 s): Wikipedia, GitHub, Hacker News, Apple AppKit docs, BBC News, Stack Overflow, The Verge, r/MacApps, The New York Times, YouTube, titles as expected; exit 0. Its net-log (8,003 request attempts over 64 s) has **no `autofill_query` and no `ranker_url_fetcher`** (3.1b: 13 and 1); the non-page annotations are page-triggered (`payment_manifest_downloader` 6 from pay.google.com, `reporting` 3, `fedcm` 4).

### Ten-page quits on Room.app (Debug app over release)

`ROOM_APP=<Debug app over release> scripts/quit-timing.sh 20` (the spike opens ten real pages through the `Engine` protocol, waits for them, then the quit AppleEvent to the pid, as ⌘Q; one throwaway state for all 20, so from run 2 the restored entry makes 11 pages), 00:39–00:45, load1 2.5–11.9: **20 / 20 clean** (exit 0, helpers_left 0, 0 crash reports, `clone_cleanup_seconds` 0): 0.21, 0.27, 0.15, 0.20, 0.17, 0.19, 0.19, 0.15, 0.15, 0.15, 0.18, 0.17, 0.18, 0.15, 0.19, 0.17, 0.19, 0.15, 0.18, 0.16 s — **median 0.175 s, max 0.27 s** (21–23 helpers running at the quit).

### Shutdown watchdog (B-38) on the release build, machine quiet (`ROOM_WATCHDOG_PRUNE=1 ROOM_APP=<release host> scripts/roomcore-watchdog.sh … 20`)

Nothing else ran (no build, no other Room); 23:58–00:20.

**Serial**: 29 attempts, 9 fixtures rejected (a page, mostly Stack Overflow, still loading at "ready"), **20 quits, 20 clean** (exit 0, 0 helpers left after the 5 s grace, 0 crash reports), load1 3.2–8.4: 0.236, 0.288, 0.263, 0.209, 0.199, 0.204, 0.207, 0.204, 0.242, 0.213, 0.251, 0.208, 0.219, 0.204, 0.167, 0.219, 0.194, 0.220, 0.210, 0.215 s — **median 0.211 s, max 0.288 s** (component build in 3.1b: median 0.833 s, max 3.751 s at load 33–49).

**Concurrent** (`roomcore-shutdown-local.py --mode room --corpus real`, three hosts × ten real pages, 20 rounds): 60 host quits; 26 rejected fixtures (pages still loading at "ready"; load1 at the rounds' start 6–57), **34 measured quits, 34 clean**: median **0.282 s**, max **0.633 s**, 0 helpers left, 0 crash reports. **Every one of the 60 processes exited 0, including the 26 rejected-fixture quits (they quit with a page still loading): 0 teardown-watchdog exits, 0 minidumps** (3.1b on the component build beside the release build: 11 of 12).

**Result: B-38 did not reproduce on the release build with the machine quiet (0 of 29 serial and 0 of 60 concurrent quits).** Patch 0010's comparison therefore did not run; 0010 stays parked (B-40 open, "not reproduced on the release build, machine quiet, 20 + 20 runs").

### Network silence on the product (Debug app over release)

`ROOM_APP=<Debug app over release> ROOM_NETCHECK_IDLE=600 scripts/netlog-check.sh` (fresh state, first-run card shown, 639 s launch → browse; load 3.8 at launch): Room's own code **0** (main process 0 bytes in, 0 out; updater and crash reporter not created); page traffic 127.0.0.1 1, localhost 3; **engine 0 requests** over launch, 600 s idle, browse and quit. The netcheck spike is DEBUG, so the Swift side is the Debug app; the engine is the release framework.

### Sparkle packaging (signed copy)

`ROOM_SPARKLE_UNSIGNED=1 scripts/sparkle-package.sh build/roomcore-release-signed/Room.app build/sparkle-3.1b2`: **DMG 184,497,802 bytes (176 MiB)** in 8.1 s from the 382 MB app (component build: 339,023,043 bytes). The unsigned appcast entry (`appcast-unsigned.xml`): version 1, short version 0.1.0, minimum system 26.0, enclosure `https://updates.room.invalid/Room-0.1.0-1.dmg` length 184497802; the EdDSA signature waits on the keychain approval (by hand, 3.1b step 3).

## Phase 3.2a — RoomBrowserWindow members, a RoomBrowser per window, new contents as host contents (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Component build `out/dev` (tag 154.0.8037.58, 13 patches: 0001–0009, 0011, 0012, **0014, 0015**; 0010 parked, 0013 reserved for 3.2b), ad hoc, mock keychain. `scripts/roomcore-apply.sh`: "2 applied, 11 already", then **"0 applied, 13 already"**. Load 3–35 (screen sharing's encoder and a Finder copy ran beside the later runs; noted per run). A stale SecurityAgent keychain dialog was frontmost at the start of the session (the user's to answer; it blocked app activation for the first spike runs, see B-52).

### The real-vs-stub table (`BrowserWindow` + `ui::BaseWindow`, 91 pure virtuals on M154)

49 real (+ `DeleteBrowserWindow`, protected), 41 stubs with first-hit logging, generated by `tools/gen_browser_window_stubs.py … --write room` from `tools/browser_window_real_members.txt` (the stubs file and the header's stub block are no longer edited by hand). "Hit" = a `RoomBrowserWindow stub hit:` line in any run of this session: the two baselines, the embryo drives (`fullscreen` ×2, `popups` ×2, `ui-document-pip`), Room.app's `popups` and `chromesurfaces2` (fullscreen, status) and both tours (every step's engine log that survived: the tour's engine log keeps the last launch only).

| Member | Real or stub | What it does / hit this session |
|---|---|---|
| `IsActive` | real | the `NSWindow` is key |
| `IsMaximized` / `IsMinimized` / `IsFullscreen` | real | `zoomed` / `miniaturized` / the full-screen style mask (window fullscreen, the host's) |
| `GetNativeWindow` | real | the host `NSWindow` (nil when headless) |
| `GetBounds` / `GetRestoredBounds` | real | the window frame in screen coordinates |
| `GetRestoredState` (3.2a) | real | maximized / fullscreen / normal, as `BrowserView` reports |
| `GetWindowShowState` (3.2a) | real | minimized / fullscreen / maximized / normal from the window |
| `GetCanResize` (3.2a) | real | the resizable style mask |
| `GetWorkspace` (3.2a) | real | empty (macOS Spaces have no public id; `BrowserView` on Mac too) |
| `IsVisibleOnAllWorkspaces` (3.2a) | real | `NSWindowCollectionBehaviorCanJoinAllSpaces` |
| `IsOnCurrentWorkspace` (3.2a) | real | `onActiveSpace` |
| `IsVisibleOnScreen` (3.2a) | real | visible and not occluded |
| `GetZOrderLevel` (3.2a) | real | floating above `NSNormalWindowLevel` |
| `Maximize` / `Minimize` / `Restore` (3.2a) | real | AppKit's zoom / miniaturize / deminiaturize (extension `windows.update`, session code) |
| `Show` | real | `DidBecomeActive`, then `makeKeyAndOrderFront` only while the app is active (else `orderFront` only if not visible); never activates the app |
| `ShowInactive` / `Hide` / `Close` / `IsVisible` | real | as before (`Close` runs `UnloadController`, destroys the Browser after the strip empties) |
| `Activate` | real (changed) | no `activateIgnoringOtherApps`: key and front only while the app is active; while another app is, nothing moves and RoomCore logs it (seen 1–2× per embryo drive: the drives run with the host inactive) |
| `Deactivate` | real | `DidBecomeInactive` |
| `UpdateTitleBar` | real | nothing (the host draws its title) |
| `OnActiveTabChanged` | real | tells `RoomBrowser` (`didActivate`) |
| `OnTabDetached` (3.2a) | real | nothing (the host owns the strip it draws) |
| `GetContentsSize` | real | the active page's container size |
| `GetStatusBubbles` (3.2a) | real | none, deliberately: `BrowserWebContentsDelegate::UpdateTargetURL` and `ContentsMouseEvent` static_cast every bubble to `StatusBubbleViews`; the hovered link reaches the host through patch 0015 |
| `UpdateLoadingAnimations` / `UpdateReloadStopState` / `UpdateToolbar` / `UpdateToolbarSecurityState` / `ResetToolbarTabState` (3.2a) | real | nothing: the host observes loading, URL and title itself; security state is 3.3a |
| `LinkOpeningFromGesture` (3.2a) | real | nothing (the host places the new contents) |
| `PreHandleKeyboardEvent` | real | `NOT_HANDLED` (3.2b: `isReservedKeyEvent`) |
| `HandleKeyboardEvent` | real | unhandled key-downs to `NSApp.mainMenu performKeyEquivalent:` |
| `AsBrowserView` | real | nullptr |
| `GetLocationBar` | real | `RoomLocationBar` |
| `GetExclusiveAccessContext` | real (changed) | `RoomExclusiveAccessContext`: tab fullscreen granted and told to the host (below); pointer and keyboard lock are Chrome's controllers; the exit bubble is recorded, not shown (B-49) |
| `GetWebContentsModalDialogHost` / `…For` | real | the branch's `RoomModalDialogHost` (unchanged; not created in these runs) |
| `CreateFindBar` | real (changed) | `RoomFindBar`, inert (text and visibility only): find is the host's (3.3b); the Views `FindBarHost` and `RoomFindBarOwner` are gone |
| `GetAutofillBubbleHandler` | real | the branch's `AutofillBubbleHandlerImpl` |
| `IsTabStripEditable` / `DisableTabStripEditingForTesting` | real | as the branch made them (no longer logged as stubs) |
| `ConfirmBrowserCloseWithPendingDownloads` (3.2a) | real | confirms (the generator's hand edit moved into the real file; 3.4a routes it to the host) |
| `ShowEmojiPanel` (3.2a) | real | `orderFrontCharacterPalette:` |
| `SetBounds`, `FlashFrame`, `SetZOrderLevel`, `SetTopControlsShownRatio`, `DoBrowserControlsShrinkRendererSize`, `GetNativeTheme`, `GetThemeProvider`, `GetColorProvider`, `GetTopControlsHeight`, `SetTopControlsGestureScrollInProgress`, `SetContentsSize`, `SetFocusToLocationBar`, `UpdateCustomTabBarVisibility`, `FocusToolbar`, `ToolbarSizeChanged`, `TabDraggingStatusChanged`, `FocusAppMenu`, `IsToolbarVisible`, `IsToolbarShowing`, `IsLocationBarVisible`, `ShowUpdateChromeDialog`, `ShowIntentPickerBubble`, `ShowBookmarkBubble`, `ShowTranslateBubble`, `GetDownloadBubbleUIController`, `ShowAppMenu`, `PreHandleDragUpdate`, `PreHandleDragExit`, `HandleDragEnded`, `ShowAvatarBubbleFromAvatarButton`, `MaybeShowProfileSwitchIPH`, `MaybeShowSupervisedUserProfileSignInIPH`, `ShowHatsDialog`, `OpenEyeDropper`, `ShowCaretBrowsingDialog`, `CreateTabSearchBubble`, `CloseTabSearchBubble`, `ShowIncognitoClearBrowsingDataDialog`, `ShowIncognitoHistoryDisclaimerDialog`, `IsUnframedModeEnabled`, `ShowChromeLabs` | 41 stubs | **none hit** in this session's runs (3.1a's nav baseline hit 12 members, all real now) |

A Browser `//room` did not create gets a headless `RoomBrowserWindow` (no `NSWindow`, `LOG(WARNING) RoomCore: refused a Chrome BrowserView …`): no run logged one.

### The baseline after the last engine change (`build/baseline/3.2a-final2`, embryo host)

| Run | nav | Ten-page quit ×3 | Helpers seen / left | Crash reports | load1 |
|---|---|---|---|---|---|
| after tasks 1–3 (`3.2a-1`) | passed, 16.4 s | **0.303 / 0.203 / 0.225 s** | 26, 25, 24 / 0 | 0 | 5.3 / 7.5 / 10.4 |
| after the fullscreen fix (`3.2a-final`) | passed, 10.7 s | **0.306 / 0.268 / 0.317 s** | 26, 24, 24 / 0 | 0 | 7.4 / 8.6 / 11.9 |
| after the session-restore fix, the last engine change (`3.2a-final2`) | passed, 10.4 s | **0.294 / 0.280 / 0.319 s** | 26, 25, 26 / 0 | 0 | 23.5 / 22.2 / 22.7 |

(The first `3.2a-final2` attempt stopped at the open10 fixture with one page still loading at "ready", stackoverflow.com, load 15; rerun.) Stub hits in every baseline: **none** (3.1a: 12).

### New contents (task 3)

| Run | Result |
|---|---|
| Embryo drive `popups` (`build/evidence-3.2a/feature-popups-2`) | `target=_blank` → disposition NEW_FOREGROUND_TAB, `window.open(…, 'width=400,height=300')` → NEW_POPUP with requested bounds 400×300, both with a gesture, both in the host's tab strip: **3 pages** (the branch's run: 1 page, the popups in Chrome `BrowserView` windows); exit 0 |
| Embryo drive `ui-document-pip` (`feature-ui-document-pip-1`) | `documentPictureInPicture.requestWindow({320×180})` → NEW_PICTURE_IN_PICTURE in the host's strip (the document's inner size is the tab's, 990×758: B-51); the PiP closes with its owner; exit 0 |
| Room.app on RoomCore, `scripts/run-spike.sh popups` (`build/evidence-3.2a/room-app-popups.txt`) | `target_blank: pages 1→2 current=true title=Popup target inCard=true`; `window_open: pages 2→3 … inCard=true`; `picture_in_picture: pages 3→4 title=Room PiP inCard=true`; each a Today tab under Popups, selected; **`windows: RoomWindow "Space"`**: the app's only `NSWindow` (no `NativeWidgetMacNSWindow`, no `BrowserView`); capture `research/screenshots/phase-3.2a/roomcore-popup-today-tab.png` (the `window.open` page as a selected Today tab) |

### Element fullscreen and the status text

| Run | Result |
|---|---|
| Embryo drive `fullscreen` (`feature-fullscreen-2`) | `requestFullscreen()` resolves (`fullscreen: 1`; the branch: refused, TypeError); `exitFullscreen()` → 0; enter again, then the host's `-exitFullscreen` → 0; delegate: `enter(origin),exit,enter(origin),exit`. The first run (`-1`) left the document fullscreen after the host's exit (Chrome tells the renderer through the window's resize, which the embryo never makes): the context now syncs visual properties on exit and `-exitFullscreen` passes `will_cause_resize=false` |
| Room.app on RoomCore, `chromesurfaces2 -RoomSpikeOnly fullscreen` | `element_fullscreen_enter: window fullscreen=true enter calls 0→1 card={{0, 0}, {1920, 1080}}`; `element_fullscreen_exit: window back=true exit calls=1 sidebar=true card={{280, 6}, {958, 806}}`; traffic lights at 19,19 before and after (load 12) |
| Embryo drive `popups`, CDP pointer over the link and off it | `status-text: http://127.0.0.1:…/popup-target.html#blank \| nil`: each change once, nil when the pointer leaves |
| Room.app on RoomCore, `chromesurfaces2 -RoomSpikeOnly status` (hover by point) | `status_pill_by_point: arrived=false`: a synthetic `mouseMoved` to the page's view produced no hover (B-52); by hand |

### The grand tour's layout, sidebar, spaces and tabs sections (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups layout,sidebar,spaces,tabs light`)

`layoutmodes` was left out: its Peek checks need `decidePolicy` (no `NavigationThrottle` until 3.3a) and its split checks read the page by script (3.3b), as 3.1a attributed.

| Run | Checks | layout + sidebar | spaces | tabs | Wall | load1 |
|---|---|---|---|---|---|---|
| 3.1a (layout, sidebar only) | 137 / 38 | 137 / 38 (175 checks) | — | — | 9.1 min | 5–22 |
| 3.2a run 1 (`build/grand-tour/20261005-014544-roomcore`) | 198 / 54 | 145 / 32 | 26 / 9 | 27 / 13 | 14.8 min | up to 35 |
| **3.2a run 2, after the session-restore fix** (`build/grand-tour/20261005-020801-roomcore`) | **202 / 50** | **144 / 33** (177 checks) | **28 / 7** | **30 / 10** | 14.6 min | 10–23 |

Run 1 found a real bug: Chrome's `SessionService` tracked the Room Browsers and restored the previous launch's tabs into the first Browser of the next launch (the tour shares one state across steps), so the host placed them as extra Today tabs: spaces counted 514 entries and 55 loaded pages (500 / 50 expected), tabsmeasure 57 / 17, quittiming's runs had 11, 20 and 25 pages. Fixed in `//room` (`omit_from_session_restore`, Room's store restores the host's entries); run 2: spaces 14/14, tabsmeasure entries right, quittiming 11 pages each run.

Every failure in run 2, by cause:

| Step | Failed / checks | Why |
|---|---|---|
| cdp | 2 / 12 | `executeJavaScript`, `captureViewport` (3.3b) |
| scroll | 3 / 10 | frame timing by script (3.3b) |
| memory | 3 / 16 | the hidden-page rAF probe is a script (3.3b) |
| audio | 4 / 13 | `play()` by script (3.3b); the audible edge (3.3a) |
| popups | 4 / 12 | `<select>`/date positions by script (3.3b), the alert sheet (3.4b). `window.open` and `target=_blank` now pass (3.1a: failed, 3.2a) |
| hidden | 5 / 11 | the visibility probe is a script (3.3b) |
| keys | 5 / 16 | the field setup by script (3.3b); ⌘T and ⌘L classified reserved needs `isReservedKeyEvent` (3.2b). ⌘T and ⌘L from the page now reach the host (`newPage=true`, `addressFocus=true`: the page is in a Browser, and `RoomBrowserWindow::HandleKeyboardEvent` gives unhandled keys to the main menu) |
| devtools | 4 / 10 | no DevTools host (3.3b) |
| quittiming | 3 / 9 | quits 0.32 / 0.33 / 0.32 s, no crash report, but one renderer outlives the browser by 1.0–1.5 s (`Room Helper (Aperitif Renderer)`, reparented to launchd, gone by 1.5 s; seen again by hand at 500 and 1,000 ms). Pages are tabs now: `tryToTerminate` closes them through the strip and the browser exits before the last renderer. 3.2b (`tryToTerminate` through `BrowserCloseManager`) |
| cookies | 7 / 14 | the cookie probe is a script (3.3b) |
| tabs | 6 / 19 | the clicks by selector are scripts (3.3b); same-site navigation and ⇧⌘T need `didCommitNavigation` (3.3a); discard (3.3a) |
| tabsmeasure | 3 / 12 | the visible-time probe is a script (3.3b); switching p95 **18.25 ms** against 16 ms (median 15.19, max 20.44; run 1 with 17 pages loaded: 21.27): within a quarter of the bound, B-53 |
| tabcapture | 1 / 9 | `captureViewport` (3.3b) |

Passed in full: smoke (6/6; 3.1a failed it on B-45), window, resize, open10, diaframe, killtest, sidebardemo, sidebar500, spaces, spacecaptures.

## Phase 3.2b — the AppController hook, the quit through Chrome's close path, key routing, isolated-world scripts (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Component build `out/dev` (tag 154.0.8037.58, **14 patches**: 0001–0009, 0011–0015; 0010 parked), ad hoc, mock keychain. `scripts/roomcore-apply.sh`: "3 applied, 11 already" (0013 new; 0014 and 0015 recommitted behind it, same content), then **"0 applied, 14 already"**. `gn check out/dev '//room/*'`: OK after three deps were added. Load 3–12 (screen sharing's encoder beside every run).

### The `AppController` shape: (ii), a separate `NSObject` behind the accessor

Patch 0013 (two files, 23 lines with the declarations): `+[AppController sharedController]` returns `room::g_app_controller_hook()` when `//room` installed it, and `ChromeBrowserMainPartsMac::PreCreateThreads` creates `//room`'s controller and returns before `CHECK_EQ(nil, NSApp.delegate)`, `chrome::BuildMainMenu` and `-mainMenuCreated`. A subclass (i) needed the same two hunks (`+sharedController` creates the base class from a function-local static, and the menu build and delegate CHECKs still had to go) and would have inherited `-init` (the keep-alive, `NSMenu`'s key-equivalent pre-search block that walks the File menu), every `NSApplicationDelegate` method and the menu-bridge state: same patch, larger surprise surface. `RoomAppController` (`room/core/room_app_controller.mm`) implements what Chrome calls and what a zero answer would get wrong; every other `AppController` message is forwarded to a first-hit log (`RoomAppController stub hit: <selector>`) with `AppController`'s method signature and a zeroed return.

Every Chrome caller of `AppController.sharedController` / `app_controller_mac::` (non-test code, M154) and what it gets now:

| Caller | Message | Now | Hit this session |
|---|---|---|---|
| `chrome_browser_main_mac.mm:159` `PreCreateThreads` | `sharedController`, `-mainMenuCreated`, `BuildMainMenu` | patch 0013: creates `RoomAppController` (its `APP_CONTROLLER` keep-alive), no delegate CHECKs, no Chrome menu | every launch |
| `chrome_browser_main_mac.mm:185` `DidEndMainMessageLoop` | `-didEndMainMessageLoop` | implemented: `TabRestoreServiceFactory::ResetForProfile` for every loaded profile without Browsers (AppController: the last profile) | every quit |
| `chrome_browser_application_mac.mm:319` `-terminate:` | `-tryToTerminateApplication` | implemented: `chrome::OnClosingAllBrowsers(true)` + `CloseAllBrowsersAndQuit()` (no downloads prompt, confirm-to-quit or apps check); reached after `RoomCrApplication -terminate:` asked the host's delegate, and from `-[RoomApplication tryToTerminateWithCompletion:]` | every quit |
| `chrome_browser_application_mac.mm:324` `-cancelTerminate:` | `-stopTryingToTerminateApplication` | implemented: `SetTryingToQuit(false)`; called by `JavaScriptAppModalDialogCocoa` (`javascript_app_modal_dialog_cocoa.mm:110`) when the beforeunload alert answers "stay" | after each "stay" |
| `browser_process_platform_part_mac.mm:40` `AttemptExit` (`chrome::AttemptUserExit`, chrome://quit) | `-confirmQuitIfNeeded` | implemented: `ConfirmQuitResultNotPrompted` (then `[NSApp terminate:]`, the host decides) | no |
| `app_controller_mac.mm:813` (AppController `-init`'s NSMenu pre-search block) | `-updateMenuItemKeyEquivalents` | never installed (`AppController -init` never runs) | no |
| `app_controller_mac.mm:2632` `UpdateProfileInUse` | `-setLastProfile:` | forwarded stub (menus only) | no |
| `app_controller_mac.mm:2686` `GetSafeProfile` | `-safeProfileForNewWindows:` | implemented: the profile itself | no |
| `app_controller_mac.mm:2741` `EnterpriseStartupDialogClosed` | `-applicationDidFinishLaunching:` | forwarded stub (no enterprise startup dialog in Room) | no |
| `app_controller_mac.mm:2748` `RunInLastProfileSafely` | `-lastProfileIfLoaded` | implemented: the most recently activated Room Browser's profile, else `ProfileManager::GetLastUsedProfileIfLoaded()` | no |
| `app_controller_mac.mm:2780` `AllowApplicationToTerminate` (`startup_browser_creator_impl.cc:410`) | `-allowApplicationToTerminate` | implemented: releases the keep-alive | no |
| `app_controller_mac.mm:2849` `ResetKeepAliveWhileHidden` (`app_shim_manager_mac.cc:1152`) | `-resetKeepAliveWhileHidden` | forwarded stub (no app shims) | no |
| AppleScript: `bookmark_item_applescript.mm:67`, `bookmark_node_applescript.mm:129`, `browsercrapplication+applescript.mm:84,105`, `window_applescript.mm:59` | `lastProfile` | implemented (as `lastProfileIfLoaded`); Room's sdef does not expose Chrome's classes | no |
| `bookmark_menu_cocoa_controller.mm:205`, `history_menu_cocoa_controller.mm:85`, `browser_native_widget_mac.mm:474` | `-keyWindowIsModal` | implemented: a modal window or a sheet on the key window (the menus and `BrowserView`'s widget are never created) | no |
| `group_menu_util.mm:30`, `history_menu_bridge.mm:403,444`, `tab_group_menu_bridge.mm:141` | `-lastActiveColorProvider` | a default `ui::ColorProvider`, logged as a stub (menu bridges are never created) | no |
| `session_service.cc:220`, `smart_restart_policy.cc:98,124` | `app_controller_mac::IsOpeningNewWindow()` | a file-static of `app_controller_mac.mm` set only by AppController's own command handling: always false (Room Browsers are omitted from session restore anyway) | — |
| `global_keyboard_shortcuts_mac.mm:52`, `browser_window_command_handler.mm:69–118`, `confirm_quit_panel_controller.mm:433` | `-commandDispatch:` / `-commandDispatchUsingKeyModifiers:` targets | implemented: `IDC_EXIT` → `[NSApp terminate:]`, everything else `chrome::ExecuteCommand` on the most recently activated Room Browser if enabled. No live caller today: those paths belong to `BrowserView` windows, Chrome's menu and the confirm-to-quit panel, none of which exist; extension commands go through Views' `ExtensionKeybindingRegistry` (BrowserView) or the global shortcut listener, not `AppController` (3.6 revisits) | no |
| `ui/base/cocoa/command_dispatcher.mm:165` (Views windows validating a `commandDispatch:` item) | `NSApp.delegate` `-validateUserInterfaceItem:` | the host's `AppDelegate` (it validates by `validateMenuItem:`); only items whose action is `commandDispatch:` ask, and the host's menu has none | no |

NSApp's delegate at launch, logged by RoomCore (`RoomCore: NSApp.delegate is …`) and the app: **`AppDelegate`** (Room.app on RoomCore), **`RoomCoreHost.HostController`** (embryo host), in every run of the session. The hidden Bookmarks menu item is gone (`RoomCrApplication -setMainMenu:` removed).

### Links from other apps reach Room on RoomCore (`ROOM_APP=… scripts/app-integration.sh --session 2.8b --no-captures light`, `build/evidence-3.2b-appintegration2.txt`)

| Route | RoomCore (3.2b) | CEF (2.8b, light / dark) |
|---|---|---|
| Cold launch by a link: `application(_:open:)` after process start (queued) | 9,472 ms (the first launch of a freshly packaged component build: dyld and 518 dylibs; `launch_to_spike` 9.61 s, 1.9–2.1 s on later launches) | 294 / 225 ms |
| … queued → requested / requested → loaded | 134.9 / 1,706 ms | 183 / 205 ms |
| Running, `open -a`: hand-over → event / event → requested / requested → loaded | **52.5 / 28.2 / 47.6 ms** | 50.6 / 26.8 / 26.6 ms |
| Running, AppleScript `open location` | **167.1 / 15.1 / 46.2 ms** | 109.6 / 25.2 / 26.4 ms |
| Running, another process's `NSWorkspace.open(_:withApplicationAt:)` | **45.2 / 20.6 / 661.1 ms** | 47.9 / 26.0 / 25.9 ms |
| After ⇧⌘W: `open -a` → window shown again, main, tab selected | event → requested 28.1 ms | 39.6 ms |

Every link became a selected Today tab; before 3.2b these went to Chrome's `AppController`.

### The baseline after the last engine change (embryo host)

| Run | nav | Ten-page quit ×3 | Helpers seen / left | Crash reports | load1 |
|---|---|---|---|---|---|
| after tasks 4–6 (`build/baseline/3.2b-1`) | passed, 16.8 s | **0.216 / 0.324 / 0.254 s** | 26, 26, 24 / 0 | 0 | 3.9 / 4.9 / 7.6 |
| after the Apple-event reply fix and the crash-mark commit (`3.2b-final`) | passed, 16.6 s | **0.240 / 0.210 / 0.244 s** | 26, 24, 24 / 0 | 0 | 6.0 / 5.3 / 8.2 |
| after the GN deps (the last engine change, `3.2b-final2`) | passed, 11.1 s | **0.302 / 0.313 / 0.231 s** | 26, 24, 24 / 0 | 0 | 3.6 / 7.3 / 9.5 |

(The first `3.2b-final2` attempt stopped at the open10 fixture: stackoverflow.com still loading at "ready", as in 3.2a; rerun.) Stub hits in the baselines: none from `RoomAppController`; one window-side line, `RoomBrowserWindow stub hit: CreateSadTab` in `3.2b-final` run 2 — the `RoomSadTab` fallback logging its first use after a renderer died on a Blink DCHECK in a real site's layout (`blink::Document::AssertLayoutTreeUpdatedAfterLayout` from `Element.clientWidth`, ptype renderer), not Room code; the run's quit was clean. `RoomAppController` lines in every baseline: `tryToTerminateApplication`, `didEndMainMessageLoop` only.

### ⌘Q with ten pages and a beforeunload "stay" (`quitstay`, Room.app on RoomCore)

`scripts/run-spike.sh quitstay --remote-debugging-port=9333 -RoomSpikeCDPPort 9333`: nine typical sites hidden, `research/spikes/phase-2.6/dialogs.html` selected and armed by a real click; `NSApp.terminate` (⌘Q's path) → `AppDelegate.applicationShouldTerminate` → `RoomCoreApplication.tryToTerminate` → Chrome's close path; the dialog is answered over the DevTools protocol on the Debug port (`Page.handleJavaScriptDialog`), "stay", then, after the spike's end, "leave" for the runner's own quit.

| Run | Dialog after the quit request | "Stay" | Pages / entries after | Then "leave" |
|---|---|---|---|---|
| 1 (`quitstay-1.txt`) | beforeunload, 25 ms | quit cancelled, `isTerminating` false | 10 → 10 alive, the same objects; 10 → 10 entries, the same ids; window visible | the app exited |
| 2 (direct launch, stderr kept: `quitstay-2.stderr`) | 15 ms | same | 11 → 11 (the previous run's selected entry restored), 20 → 20 entries | `Room: quit requested` 54.278 → `Room: final state written` 54.355 → `Room: quit proceeds` 54.355 (the reply), exit |
| 3 (final build) | 19 ms | same | 10 → 10, 10 → 10 | exit |

The engine side of run 1 (`RoomCore.log`): `tryToTerminateApplication` 40.639, `stopTryingToTerminateApplication` and `RoomCore: quit cancelled (1 waiting)` 40.677 (13 ms after the dialog event), `quit proceeds` 41.819 after the runner's quit. The spike's "cancelled after 1,077 ms" is the DevTools call's reply arriving late, not the cancel. The beforeunload dialog is Chrome's app-modal Cocoa alert (`JavaScriptAppModalDialogCocoa`), whose "stay" calls `chrome_browser_application_mac::CancelTerminate()`; 3.4b routes it to the host's sheet. The next launch on run 1's state (`quitstay-2`) read `previous exit clean=true (store uncleanExit=false, engine lastExitWasClean Default=true)` and the profile's `exit_type` pref was `Normal`.

### Clean-exit and crash flags (`quitflags`, kill -9)

| Sequence | `exit_type` on disk | The next launch reads |
|---|---|---|
| clean quit | Normal | `clean=true (store uncleanExit=false, engine … Default=true)` |
| kill -9 ~4 s after launch, before the crash-mark commit (first build) | **Normal** (the service's "Crashed" mark waits for the pref writer's ~10 s batch) | `clean=false (store uncleanExit=true, engine … Default=true)` |
| kill -9 15 s after launch | Crashed | `clean=false (store uncleanExit=true, engine … Default=false)` |
| … then a clean quit | Normal (RoomCore acknowledged the crash; without it Chrome keeps "Crashed" until a session-restored Browser gets a tab) | `clean=true` |
| final build: kill -9 ~1.5 s after the spike ended (`killb-*`) | **Crashed** (committed at profile load) | `clean=false (store uncleanExit=true, engine … Default=false)`; after the next clean quit `Normal`, `clean=true` |

### Quit timing and the lingering renderer (Room.app on RoomCore, `scripts/quit-timing.sh 3`, the quit Apple event)

| Build | Quits ×3 | helpers_left 1 s after exit |
|---|---|---|
| 3.2a tour (pages closed by `//room`, then Chrome's quit) | 0.32 / 0.33 / 0.32 s | 1 each |
| 3.2b first build | **did not exit within 15 s** ×3: AppKit's `-_handleAEQuit` asks the delegate itself and runs a modal loop until `replyToApplicationShouldTerminate:`, which `RoomCrApplication` swallowed (it only knew its own `-terminate:` path); the reply now goes to AppKit when `-terminate:` was not the caller | — |
| 3.2b, after the fix | **0.30 / 0.31 / 0.31 s** (load 9–12) | 1 each |
| 3.2b tour (`quittiming`) | 0.28 / 0.25 / 0.26 s | 1 each |

The process left behind is one `Room Helper (Aperitif Renderer)` (`--type=renderer`, the highest renderer client id of the run), reparented to launchd, gone 1.0–1.3 s after the browser (10 samples at 0.1 s, three quits). Unchanged by the close path: B-54.

### Keys (`scripts/run-spike.sh keys`; events built from each layout's data, sent through `NSApp.sendEvent`; the active input source is Colemak)

| Layout | RoomCore (3.2b) | CEF (same spike, same day) |
|---|---|---|
| ABC | ⌘T/⌘L reserved (2 `isReservedKeyEvent` calls, the page never saw them), menu dispatch: no (not the active layout); ⌘C copied, ⌘V `"select me and copy PASTED"`, ⌘Z restored, `o` typed (`"…copyo"`); page saw ⌘c, ⌘v, ⌘z, o; **consumed 1** (the `o` character) | reserved 2, dispatch no; ⌘V `" PASTED"` (the selection replaced), `o` typed (`"o"`); page saw the same; consumed 0 (CEF: never) |
| Colemak (active) | reserved 2, **⌘T opened the palette, ⌘L focused the address**; rest as ABC; consumed 1 | reserved 2, dispatch yes; consumed 0 |
| Lithuanian | as ABC; consumed 1 | as ABC on CEF |
| LithuanianColemak | not installed | not installed |

Unhandled keys in the delegate log: ⌘C, ⌘V, ⌘Z and the `o` key-down (a text field consumes the character event, not the key-down) went to `handleUnhandledKeyEvent` → the menu. The tour's `keys` step passes 19/19 with the checks made engine-neutral (they had codified CEF's `" PASTED"`).

### `executeJavaScript` (the `cdp` spike's 100 evaluations)

RoomCore isolated world: **median 0.14 ms, p95 0.51 ms, max 4.44 ms**; CEF over CDP `Runtime.evaluate`: 0.21 ms median (Phase 1.4). Promise results work (the transparent page's `visibilityAndFrames` probe resolved to `{"visibility":"visible","rafPerSecond":62}`).

### The grand tour's layout, sidebar, spaces, tabs and layout-modes sections (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups layout,sidebar,spaces,tabs,layoutmodes light`, `build/grand-tour/20261005-034756-roomcore`, 23.2 min, load 5–12)

| Section | 3.2a run 2 | 3.2b | 3.2b, keys checks fixed and popups rerun |
|---|---|---|---|
| layout + sidebar | 144 / 33 | **157 / 20** | 165 / 15 (`keys` 19/19, `popups` 11/12 in `20261005-042014-roomcore`) |
| spaces | 28 / 7 | **35 / 0** | 35 / 0 |
| tabs | 30 / 10 | **37 / 3** | 37 / 3 |
| layoutmodes | not run | **27 / 3** | 27 / 3 |
| total | 202 / 50 | **256 / 26** | 264 / 21 |

The `popups` step hung for 9 min in the tour (killed by hand): the page's `alert()` is Chrome's own dialog until 3.4b, and a script sent to a page with a dialog open never returns; `executeJavaScript` now gives up after 30 s with an error (rerun: 57 s, 11/12).

Every remaining failure, by cause:

| Step | Failed | Why |
|---|---|---|
| cdp | 1 / 12 | `captureViewport` (3.3b); `executeJavaScript` passes now |
| memory | 2 / 16 | the hidden-page probe runs now and reads `visibility: visible, 63 rAF/s` for hidden pages: RoomCore ignores `initiallyHidden` and the page views the host takes out of the window still render (3.3a, `createWebContents` options and visibility) |
| audio | 3 / 13 | the audible edge (3.3a); `play()` by script runs now |
| popups | 1 / 12 | the alert sheet (3.4b); `<select>`/date positions pass now |
| hidden | 1 / 11 | the never-shown page is visible to Chromium (3.3a, as memory) |
| devtools | 4 / 10 | no DevTools host (3.3b) |
| quittiming | 3 / 9 | the lingering renderer (B-54); quits 0.25–0.28 s, no crash report |
| tabs | 1 / 19 | discard (3.3a); same-site navigation and ⇧⌘T pass now |
| tabsmeasure | 1 / 12 | switching p95 **21.92 ms** (median 14.91, max 23.30; 3.2a 18.25). Standalone afterwards (`build/evidence-3.2b/tabsmeasure`, load 5–6): select call p95 11.78 ms, turn p95 **22.40 ms** (median 15.66). Over the 16 ms bound by more than a quarter; the lead is the same as memory's: every loaded page renders as if visible (B-53, 3.3a) |
| tabcapture | 1 / 9 | `captureViewport` (3.3b) |
| layoutmodes | 3 / 30 | Peek does not open (an off-site link from a pinned entry navigates in place): `decidePolicy` (3.3a); hide/reveal and split pass (27) |

Passed in full: smoke, window, scroll, resize, open10, diaframe, keys (rerun), killtest, sidebardemo, sidebar500, spaces, spacecaptures, cookies.

### The stub-hit log over the tour and the session

`RoomBrowserWindow stub hit:` lines in every surviving engine log (the two tour states' `RoomCore.log`, which keep each state's last launch; the embryo baselines; the quit, kill and keys runs): **none** of the 41 generated stubs (they are named in "Phase 3.2a" ▸ the real-vs-stub table); the one `CreateSadTab` line above is the SadTab fallback. `RoomAppController stub hit:` lines: **none**. `RoomAppController` members hit: `tryToTerminateApplication`, `stopTryingToTerminateApplication` (after a "stay"), `didEndMainMessageLoop`. No `refused a Chrome BrowserView` line.

## Phase 3.3a — page visibility, tab helpers, navigation, page state, discard (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Room.app on RoomCore (component build, `out/dev`), throwaway state and engine directories per run (`build/evidence-3.3a/`); CEF runs on the same day for the rules that changed on both engines. The machine was otherwise idle (load 3–9); the Claude desktop app was frontmost most of the time, and Room was often refused activation (`window_main: false` in several spikes and the tour; see the tour).

### Page visibility (`hidden`, `memory`)

`initiallyHidden` → `CreateParams::initially_hidden`, plus one finding: `WebContentsViewMac::CreateView` hides the `WebContentsViewCocoa` of a hidden contents (Chrome's Views `WebView` unhides it, `ViewsHostableSetVisible`), so the first build showed the page in the card and it still read `hidden` (the view had `isHiddenOrHasHiddenAncestor` true inside a visible window). RoomCore unhides it at wrap time (also for Chrome-created background tabs and a discard's replacement); the view's own window tracking does the rest.

| Probe (`visibilityAndFrames`) | 3.2b | 3.3a |
|---|---|---|
| visible page | visible, 62 rAF/s | visible, 63 |
| never shown (created hidden) | **visible, 63** | hidden, 1 |
| after being shown in the card | visible | visible, 62 |
| taken out of the card | visible | hidden, 1 |
| `memory`: page 0 of 1 / 10 / 30 hidden pages | visible, 63 | hidden, 1 (all three) |

(1 rAF/s is the probe's own frame, as on CEF in 1.4.) Memory with hidden pages: baseline 993 MB / 3 renderers; 1 hidden 1355 MB; 10 hidden 4628 MB (+363 MB each, 14 renderers, 10/10 loaded in 49 s); 30 hidden 10101 MB (+304 MB each, 34 renderers, 30/30 in 25 s). 3.3b's table measures properly.

### B-53: switching (`scripts/tabs-measure.sh`, 50 entries, 10 loaded, load 6–7)

| | 3.2b standalone | 3.3a standalone | 3.3a tour |
|---|---|---|---|
| select call p95 | 11.78 ms | 10.19 ms (median 6.78) | 9.82 |
| turn before display p95 | 22.40 ms (median 15.66) | **21.39 ms** (median 15.33) | — |
| main-thread turn p95 | — | 21.50 ms | **22.31** (median 15.14) |
| page visible p95 / first frame p95 | — | 16.20 / 26.02 ms | 15.84 / — |
| relaunch: launch → selected loaded | — | 5.01 s | 4.35 s |

Hidden pages no longer render, and the p95 barely moved: visibility was not B-53's cause. B-53 stays open (3.3b profiles the turn).

### Tab helpers

Room pages already get Chrome's tab helpers: inserting a WebContents into a `TabStripModel` creates a `tabs::TabModel`, a befriended class whose constructor calls `TabHelpers::AttachTabHelpers` (and `TabFeatures::Init`). Every page RoomCore creates for a host window joins its `RoomBrowser` at creation (3.2a), so no patch and no Chrome creation path was needed; 3.2b's "no tab helpers attached" held only for pages in no strip (the embryo host's). Logged on the first page: `favicon=1 zoom=1 lifecycle=1 resource_coordinator=1 find=1 session=1 permissions=1 translate=1 print=1`. Misbehaviour without a `BrowserView`: one, `HttpsOnlyModeTabHelper` → `AskBeforeHttpDialogController::ShowDialog` → `TabDialogManager::CreateTabScopedDialog` CHECKed `host` (`BrowserElementsViews::GetPrimaryWindowWidget()` null until a first web-modal dialog had made the modal host) on `http://neverssl.com/` (an HTTP-only site after the HTTPS upgrade fails): exit 134. Fixed in `//room` (each Room Browser makes its Views modal host at creation); since then the dialog opens (Views, hybrid UI). No helper disabled. No window or `RoomAppController` stub hit in any run of the session (one `CreateSadTab`: a renderer of the 30-page memory run died, the 3.2b fallback).

### Navigation: the Peek rules on RoomCore's `kind` (`scripts/layout-modes.sh --no-captures light -RoomSpikeOnly peek`)

| Navigation from the pinned entry (2.7a's table) | `kind` / transition / disposition / gesture / redirect, as RoomCore reported it | RoomCore | CEF (same day, status-text emulation) |
|---|---|---|---|
| link to the same site | linkActivated / link / currentTab / true / false | in place | in place |
| link to the other site | linkActivated / link / currentTab / true / false | Peek | Peek |
| link into a redirect chain the site starts | linkActivated, then the 302 step with redirect=true | in place | in place |
| direct OAuth authorize link | linkActivated (login flow), then redirect=true | in place | in place |
| form post to the other site (303) | formSubmitted / formSubmit, then redirect=true | in place | in place |
| `location.href` in a click handler, gesture 0.2 s before | **other** / link / currentTab / true | in place | in place |
| the same, last input 3 s before | other / link / true | Peek | Peek |
| ⇧-click an off-site link | linkActivated / link / **newWindow** / true (Navigate()'s disposition hook) | Peek | Peek |
| `target=_blank` | other / link / newForegroundTab (window.open path, contents attached) | a selected Today tab | a selected Today tab |
| the host's own load of the pinned URL | other / bookmark / false | in place | in place |

Peek decision → overlay frame median 21.19 ms (CEF 21.86); decision → Peek page FCP median **500 ms**, p95 545 (CEF 92 / 96; the tour's run 84 / 156, max 493): B-57. Event isolation, Open as Tab, Esc and ⇧⌘T as in 2.7a. The status-text workaround stays for CEF only, inside `EngineCEF` (a TT_LINK navigation not to the link under the pointer becomes `.other`); `PeekRules` reads `kind` alone and passes the table on both engines.

Same-site key (B-34), `EngineApplication.site(of:)`: RoomCore `shop.example.xn--1lqs71d.jp` → `example.xn--1lqs71d.jp` (東京.jp is a public suffix), `a.b.example.co.uk` → `example.co.uk`, `room.github.io` → itself, `127.0.0.1` → itself; the bundled list (CEF, the fake) gives `xn--1lqs71d.jp` for the first (IDN rules skipped).

Commits: the tour's `palette2` history checks pass on RoomCore now (typed recorded as typed, a script navigation as link, same-document pushState recorded, the DNS error page not recorded): the 3.2b failure needed only `didCommitNavigation`.

### Page state

- **Audio** (`audio` spike, `audio.html`): media element round 1 audible after 1605 ms (the file's first load), stopped 328 ms after `pause()`; round 2 109 / 278 ms; **Web Audio oscillator audible after 154 ms, still audible at 2 s, off 282 ms after `stop()`** (the Chapter 1 CEF cap: no off edge). The media poll is CEF-only.
- **Favicons** (`tabs` spike): Wikipedia's live favicon 16 × 16 pt with 2 representations; the app's cache has it (relaunch: 9 of 49 unloaded rows with a cached favicon, 3.2b 0); `Profile.favicon(for:)` from Chrome's `FaviconService` returns 16 × 16 pt, 2 reps for the visited URL. The rows show the app's cache (2.1), which `WebContents.favicon` now fills on RoomCore; nothing asks the engine's store yet.
- **Colours** (`colors` spike): Wikipedia themeColor nil, root background #f8f9fa, card #f8f9fa; `research/spikes/phase-3.3/dark.html` themeColor #1e3a5f, root background #121212, card #121212 (`research/screenshots/phase-3.3a/phase-3.3a-card-dark-page.png`, dark appearance, window-server capture).
- **Zoom** (`chromesurfaces2 -RoomSpikeOnly zoom`): ⌘= 1.1 with the indicator "110%", devicePixelRatio 2.2; ⌘- ⌘- 0.9, ⌘0 1.0; indicator hides. B-27: a loaded background page of the same host reads **1.1 at once** and 1.0 after ⌘0 (CEF, same spike: 1.0, stale until its next load).
- **Security** (`-RoomSpikeOnly security`): `https://example.com/` secure; `http://127.0.0.1:8766/` none (Chrome treats loopback as potentially trustworthy); `http://neverssl.com/` insecure (WARNING; Chrome's ask-before-HTTP dialog over it); `https://127.0.0.1:8767/secure.html` (self-signed) dangerous on Chrome's interstitial (the delegate is 3.4a).

### Lifecycle (`tabs`, `closeunload`)

| Step | Result |
|---|---|
| Wikipedia A loaded one link further (through `load`, `.link`) | `canGoBack=true` |
| Debug ▸ Discard Background Pages | 7 pages `discarded`, rows dimmed; log `page lifecycle 0 -> 1` ×7 and `a discarded page's old WebContents is destroyed` ×7 (Chrome replaced each WebContents; the wrapper moved on `kReplaced`) |
| A reselected (the tab controller's `reload()`) | `state=alive`, `canGoBack=true` (CEF: false, B-13); Back → `Web_browser`, `canGoForward=true` |
| ⌘W on the changed pinned entry, ⇧⌘T | page closed, entry reset to its stored URL, reopened at `?changed=1` (unchanged path) |
| renderers after the discard | 11 → 12 at 4 s, 12 at 10 s and until the quit (memory 2955 → 3095 MB); the tour's run of the same step: 10 pages, 16 → 13, 3809 → 3270 MB. B-56 |
| `close()` on `dialogs.html` with beforeunload armed, "stay" | Chrome's beforeunload dialog 14 ms after `close()` (answered over CDP), page alive |
| the same, "leave" | dialog after 11 ms, page `closed`; states alive → closed, reported once |

The first discard runs used Chromium's field-trial testing config, which enables `WebContentsDiscard` for Chromium builds (the experiment "EnabledIgnoreWorkers"): an in-place discard that kept every renderer process (renderers 11 → 12, memory up 140 MB, no `kReplaced`). `//room` disables it (Chrome's desktop default), so the replace path runs. `frozen`: M154 has no per-tab freeze in the lifecycle unit (`FreezingVote` and `WebContents::SetPageFrozen` exist, the protocol has no freeze member); `state` reports `.frozen` when `TabLifecycleUnitExternal::GetTabState()` says FROZEN (Chrome's own freezing policy), read at each refresh; not observed in a run.

### The baseline after the last engine change (`build/baseline/3.3a-final`, embryo host)

nav passed 16.3 s; ten-page quits **0.209 / 0.272 / 0.294 s** (load 3.9 / 6.4 / 8.1), 0 helpers left, 0 crash reports. (An earlier baseline in the session lost its third run to Stack Overflow still loading at the fixture's limit, the hardening branch's known flake.) Stub hits: none.

### The grand tour's palette, tabs and layout-modes sections (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups palette,tabs,layoutmodes light`, `build/grand-tour/20261005-054628-roomcore`, 6.6 min)

| Section | 3.2b | 3.3a | Failures |
|---|---|---|---|
| palette (not run in 3.2b) | — | 62 / 7 | `window_main` ×5; `captureViewport` ×2 (3.3b) |
| tabs | 37 / 3 | 36 / 4 | `window_main` ×3; switching p95 22.31 ms (B-53); `captureViewport` (3.3b). Discard passes now (renderers 16 → 13) |
| layoutmodes | 27 / 3 | 27 / 3 | `window_main`; hover reveal ×2 (`reveal_band_to_shown` 2003 ms = the 2 s timeout, no frames). Peek passes now (3.2b's three) |
| total | — | 125 / 14 | |

Every `window_main` failure and the two reveal checks are the activation of the run: the Claude desktop app stayed frontmost and macOS did not let Room become active (`lsappinfo front` → Claude during the run; the standalone spikes of the session read `window_main: false` too), so no window was main and the hover band saw no mouse-moved events. A standalone rerun of layoutmodes' reveal checks right after the tour had the window main and passed: band → shown median 172.69 ms, leave → hidden 155.10 ms (CEF, same minute: 173.27 ms). Nothing 3.3a owns fails.

## Phase 3.3b — find, capture, print preview, DevTools in the pane, memory and timing beside CEF (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug, 60 Hz)

Room.app on RoomCore (component build `out/dev`, `DCHECK_ALWAYS_ON`, Debug Swift app), throwaway state and engine directories per run (`build/evidence-3.3b/`). The display is the 1280 × 800 pt mode at **60.00 Hz** (`system_profiler`; the 2.9 tour's run 3 had the same mode, runs 1–2 a larger one), load average 3–12 (recorded per run). Room's window was main and key in every run below (`window_main: true`); the Claude desktop app was frontmost between runs. Three "Room quit unexpectedly" system dialogs were on screen throughout (05:24 ×2 from 3.3a's runs, 06:59 ×2 from this session's launch of today's app over the stale release framework, below); they were not answered and cover the middle of two captures.

### Find (`chromesurfaces2 -RoomSpikeOnly find`, `find.html`: 2,000 paragraphs, "lighthouse" 400×)

One `FindTabHelper::StartFinding(find_match=true)` per keystroke: the spike-gated log line counted 29 "new text" requests for 26 keystrokes (the bar re-sends its text when ⌘F reopens it) and 2 "same text, step" for ⌘G / ⇧⌘G; no counting request (CEF sent two per new text). "1 of 400" on the first request, ⌘G → "2 of 400", ⇧⌘G → "1 of 400", Esc closes with the focus back in the page.

| Keystroke → highlighted match | RoomCore | CEF (2.6b; 2.9 tour) |
|---|---|---|
| all 26 keystrokes, median / p95 | 36.7 / 424.6 ms | 20.7–21.3 / 23.8–26.5 ms (n = 9–11); tour 14.4–15.4 / 25.5–26.2 |
| keystrokes 1–3 of a word (12) | 406–713 ms | — |
| keystrokes 4+ of a word (14), median / p95 | **6 / 38 ms** | — |

The first three characters wait for Chromium: `FindRequestManager` delays queries shorter than `kMinKeystrokesWithoutDelay` (4) by `kDelayMs` (400 ms) so a page's script is not starved while the user types (`content/browser/find_request_manager.cc:187–195`); Chrome's own find bar behaves the same. CEF's `Find` does not go through that delay. Not a Room cost; recorded, not chased.

### Capture (`cdp`, `capture`)

`captureViewport` through `CopyFromSurface`: 20 captures of Wikipedia, **16.6 ms median, 18.7 p95**, 990 × 758 pt (CEF's CDP `Page.captureScreenshot`: the same spike reported its round trip in 1.4/2.9). The tabs spike's in-process composites now carry the page (`research/screenshots/phase-3.3b/tabs/phase-2.3-card-page-light.png`, `-dark.png`, the switcher, the empty card): B-9's in-process evidence gap is closed for the page. The transparent-background capture (`cdp/phase-1.4-transparent-cdp-capture.png`) shows the page; RoomCore ignores `transparentBackground` (3.1a table), so the page is opaque. `executeJavaScript` 0.16 / 0.71 ms (3.2b: 0.14 / 0.51).

### Print preview (`chromesurfaces2 -RoomSpikeOnly print`)

`print()` → `printing::StartPrint`: Chrome's print preview, a `NativeWidgetMacNSWindow` 1000 × 660 pt centred over the card, a child of the Room Browser's modal anchor, itself a child of Room's window; shown **24–50 ms** after `print()` (CEF's system panel: 285 ms); "Print — 1 page — Save as PDF"; Esc closes it in 225 ms (`phase-2.6b-print-preview-light.png`, a screen-rect capture: the stale crash dialog covers its middle). Two findings before it showed: (1) the anchor was ordered **below** Room's window, so the preview (its child, ordered above the anchor) sat behind the window, `occlusionState` not visible; ordered above now (the anchor is transparent and ignores the mouse). (2) Printing the demo's developer.apple.com page, the preview appeared and vanished within 250 ms: Chrome closes print preview when the initiator navigates, and that page changes its URL by script; the spike prints `status.html` now.

### Element fullscreen (`-RoomSpikeOnly fullscreen`)

3.2a's `-exitFullscreen` is what `exitFullscreen()` maps to: enter → window fullscreen with the card 1280 × 800, exit → window back, sidebar, card 958 × 758, traffic lights at 19,19 with the toolbar (`phase-2.6b-element-fullscreen-light.png`).

### DevTools in the host's pane (`devtools`, `chromesurfaces2 -RoomSpikeOnly devtools`)

Shape (a): `DevToolsWindow` with its bindings and lifetime; without a `DevtoolsUIController` it cannot dock and makes a DevTools Browser, which RoomCore keeps headless (3.2a); the front-end `WebContents` stays in that strip and its view is adopted into the pane. No `//room` front-end host, no patch.

| Step | RoomCore | CEF (2.6b, 2.9 tour) |
|---|---|---|
| ⌥⌘I → front-end loaded, median / p95 (n = 4) | **330.6 / 335.6 ms** | 328–335 ms; tour 329 / 340 |
| ⌥⌘I → attached to the page (front-end's primary page target) | 530.7 / 557.7 ms | 328–337 ms |
| inspect element at (60, 160) | DevTools open after 24 ms; `INPUT#color` selected in Elements (the spike polls 200 ms apart for up to 10 s: 11.2 s, CEF 10.6 s in the 2.9 tour) | `SELECT#sel` |
| resize handle dragged 150 pt | fraction 0.420 → 0.617 | 42% → 60.7% |
| ⌥⌘J | console panel | console |
| ⌥⌘C with DevTools open | element picker on (`elements.toggle-element-search` toggled) | — |
| close | `closed=true pane=false`, front-end `closed`, page alive | same |

Capture with the pane open on Elements: `research/screenshots/phase-3.3b/phase-2.6b-devtools-pane-light.png`. The front-end's own scripts: content allows main-world scripts on devtools: pages (`RenderFrameHost::ExecuteJavaScript`), its CSP (`script-src 'self'`) forbids `eval`, and a script injected from the browser has no base URL for `import('./…')`, so the spikes import the front-end's modules by their devtools://devtools/bundled/ URLs (the CEF front-end has the same URLs).

**No remote-debugging port in the product** (`build/evidence-3.3b/debugging-port*.txt`, scratch `--user-data-dir`, nothing under the real data root newer than the runs): the Release-configuration app (built over the dev framework, see the deviation) has no process with `--remote-debugging-port` and no TCP listener; launched *with* `--remote-debugging-port=9557` it still opens no listener (Release drops `--remote-debugging-*`). The Debug app: no listener by default; with a spike's `--remote-debugging-port=9558`, `127.0.0.1:9558`. The release framework itself (3.1b-2's `out/release`, not rebuilt) cannot run today's app: `-[RoomApplication setApplicationDelegate:]` (3.2b) is missing there, the app aborts in `main`.

### Memory and timing, RoomCore beside CEF

Standalone spikes, each on a fresh state (`build/evidence-3.3b/numbers-1/`), visible window, main and key, 60 Hz, Debug app on the component framework. CEF's column is `chapter-2-review.md` "Numbers", tour column (visible window, frontmost, load 4–10, run 2 light / dark, the tour's accumulated state).

| Measure | CEF (tour) | RoomCore (3.3b) | Condition (RoomCore run) |
|---|---|---|---|
| Memory baseline (one blank page, summed RSS of every Room process) | 849 / 857 MB | **996 MB**, 9 processes, 3 renderers | `memory`, load 3.1 |
| 10 loaded pages of 50 entries, summed RSS | 3,572 / 3,560 MB (2.3: 4,095–4,215) | **6,398 MB**, 27 processes, 19 renderers (5,811 after the 100 switches) | `tabsmeasure` switch, load 12 at start |
| per hidden page at 1 / 10 / 30 | +169 / +237–270 / +210–215 MB | +366 / +442 / +363 MB | `memory` |
| 30 hidden pages, loaded | 7,292 / 7,145 MB, 30/30 | **11,880 MB**, 30/30, 39 renderers | `memory` |
| 50 loaded pages over 5 spaces | 6,495 / 6,509 MB | **10,317 MB**, 58 processes, 52 renderers | `spaces -RoomSidebarFixture spaces500`, load 6.9 |
| Tab switch: click → page committed in the card, median / p95 | 13.7 / 17.5 and 14.5 / 18.2 ms | **15.41 / 22.33 ms** (`select` call 6.43 / 10.38) | `tabsmeasure`, 100 switches among 10 loaded |
| … the page visible after the click (median); first frame (median / p95) | 4.2 / 3.9 ms; isolated 15.1 / 23.0 | 5.17 ms (p95 13.50); 12.51 / 26.00 ms | same run |
| Relaunch: process start → selected page loading; → loaded | 0.82 / 0.83 s; 1.44 / 1.49 s (50k history rows) | **2.10 s; 4.08 s** (fresh state, 50 entries) | `relaunch`; the component app reaches its first line of Swift 2.0–2.5 s after spawn in every spike (`launch_to_spike_s`); the release app opened a first page 0.41 s after spawn in 3.1b-2 |
| Peek decision → overlay frame; → first contentful paint (median) | 21.4 / 30.0 ms; 91.7 / 102.2 ms | 22.5 ms; **493 ms** (p95 545) | `layoutmodes -RoomSpikeOnly peek`, 5 opens |
| Quit with ten pages | 0.31–0.50 s, 0 helpers left | **0.281 / 0.220 / 0.228 s**, 0 helpers left (embryo baseline) | `roomcore-baseline.sh` after the last engine change, load 6–8 |
| Find, keystroke → highlighted match | 14.4–15.4 / 25.5–26.2 ms | 4+ characters 6 / 38 ms; 1–3 characters ~410 ms (Chromium's short-query delay) | above |
| DevTools ⌥⌘I → front-end loaded | 329 / 340 ms | 330.6 ms | above |

The tour's own `tabsmeasure` (below, on the tour's shared state) read 10 loaded pages 4,919 MB in 27 processes, switching 16.93 / 22.62 ms, relaunch 2.76 s to loading and 4.95 s to loaded: the ten live sites' weight varies by run by more than a gigabyte; the table keeps the standalone run.

**The component build inflates both memory and launch.** One look, the embryo host's `open10` (the same ten sites, the same embryo, peak summed RSS, `build/evidence-3.3b/embryo-rss10-component-vs-release.txt`): component framework **6,585 MB**, release framework (3.1b-2) **4,975 MB**, both 24 processes and 18 renderers: −24 %, ~67 MB per process (the component build's 518 dylibs each dirty their own pages in every process). Release RoomCore is still ~1.4 GB above CEF's ten pages: more processes (18 renderers for ten pages against CEF's 15 in 2.3; Chrome's site isolation and a spare renderer) and more per renderer. B-2 has its comparable number now; the discard policy (3.7b) and the release-build measurement (3.8) are the levers.

**B-53 (switching p95 22.3 vs 16 ms; CEF 17.5–18.2): one profile.** `sample` at 1 ms over 38 s of the 100 switches (`build/evidence-3.3b/b53/sample.txt`; the sampling slows the run, median 40 ms under it); main thread 21,243 samples, 1,650 busy. Where the busy time goes, as samples of the main thread (top-most frame of each kind):

| Part | Samples | What |
|---|---|---|
| Core Animation commit (layout, display, commit handlers) | 479 (29 %) | AppKit's display cycle after the swap; the window's constraint layout 110 |
| `SidebarController.select` → `TabController.activate` | 467 / 372 | the card's view swap: `removeFromSuperview` 179 (the old page's `WasHidden`: `RenderWidgetHostViewMac::Hide` → `BrowserCompositorMac` → `~RecyclableCompositorMac` → `DestroyCompositorFrameSink`, **a synchronous mojo call to the GPU process**, 66), `addSubview` 171 (the new page's `WasShown` → `SynchronizeVisualProperties` 43, of which `RoomBrowserWindow::IsMaximized` → `-[NSWindow isZoomed]` **37**) |
| Chromium tasks | 457 (28 %) | cookie-access notifications of the ten live pages 174 (not the switch); `room_activateWebContents` → `TabStripModel::ActivateTab` **73** |
| sequence checkers (`DCHECK_ALWAYS_ON`) | 233 (14 %, across the above) | the dev build checks every sequence; CEF ships a release build |

No single Room-side cause: the strip's activation (73, ~4 %) and the uncached `isZoomed` (37, ~2 %; Views caches it in `NativeWidgetMacNSWindowHost::is_zoomed_`) are Room's and together well under the 5 ms gap; the rest is Chromium's hide/show path and the dev build's checks. Per the scope rule no fix was made; the number stands as the row (B-53), next step: measure on a current release build (no DCHECKs, no component dylibs) and cache the zoom state.

**B-57 (Peek paint 493 vs 92 ms): one look.** A Peek is an off-site page in a new `WebContents`, so it needs a new renderer process (a new site instance); the overlay itself is as fast as CEF's (22.5 vs 21.4 ms) and the throttle's cancel → `openPeek` round trip is the same on both engines (2.7a/3.3a). A renderer helper of the component framework, started with an unknown `--type` (it loads, initialises and exits), takes **1.35–1.37 s** warm; the release framework's helper **0.02–0.03 s** (`/usr/bin/time`, three runs each, the first of each ~2.7–3.0 s: the new binary's assessment). The gap is the dev build's process launch, not Peek's path; B-57 stays a row until the release build measures it (3.8).

### The crashed-page view (`chromesurfaces2 -RoomSpikeOnly crash`)

The tour (below) found the crash view missing on RoomCore: no `processGone`. The 3.3 exit names the crash view among the chrome surfaces, and the member is one `WebContentsObserver` call, so it came forward from 3.4's checklist: `chrome://crash` → `processGone(.crashed)`, the host's crashed-page view with the keyboard in it (`CrashedPageView`), Return reloads (`phase-2.6b-crashed-page-light.png`). No crash report reaches `~/Library/Logs/DiagnosticReports`: RoomCore's Crashpad writes under the data root (3.1a), so the tour's "one helper crash report" check stays CEF-shaped.

### The baseline after the last engine change (`build/baseline/3.3b-final2`, embryo host)

nav passed 15.9 s; ten-page quits **0.281 / 0.220 / 0.228 s** (load 5.7 / 6.0 / 8.4), 0 helpers left, 0 crash reports; stub hits: none. (Before the anchor reorder: nav 16.5 s, 0.276 / 0.252 / 0.236 s; before `processGone`: 0.250 / 0.218 / 0.238 s.) Over the session's runs: one `CreateSadTab` (chrome26b's `chrome://kill`, the 3.2b fallback); `RoomAppController` logged only its implemented members; "refused a Chrome BrowserView for a devtools Browser" 27× (each DevTools open: the headless DevTools Browser, by design).

### The grand tour's tabs and chrome sections (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups tabs,chrome light`, `build/grand-tour/20261005-071621-roomcore`, 29.4 min)

| Section | 3.3a | 3.3b | Failures, attributed |
|---|---|---|---|
| tabs (`tabs`, `tabsmeasure`, `tabcapture`) | 36 / 4 | **37 / 3** | discard's "renderers released" (11 → 12: B-56); switching median 16.93 and p95 22.62 ms (B-53). `tabcapture` 9/9 now (3.3a: `captureViewport`) |
| chrome surfaces 2.6a (`chrome26a`) | not run on RoomCore | 15 / 10 | 3.4: JS dialogs, beforeunload "stay" (3.4b); certificate interstitial ×3 (3.4a `strict_enforcement`/SSL delegate); location and notification prompts (3.4a permissions); link context menu ×2 (3.4a); `window.open` opener messages read `null` (the check reads a page global from the isolated world: B-55) |
| chrome surfaces 2.6b (`chrome26b`) | not run on RoomCore | 36 / 17 | the 2.6a ten again; delegate members never called (15, below); downloads pause/resume/cancel and badge (3.4a `DownloadManagerDelegate`); site panel Block and Clear (3.4a permission settings, `clearSiteData`); `chrome://crash` view (no `processGone`: implemented after the tour, above) and its helper crash report (Crashpad writes under the data root) |
| total | | **88 / 30** | nothing 3.3 owns fails |

What 3.3 owns in the chrome sections passes: find (1 of 400 on the first request, ⌘G/⇧⌘G, Esc with the focus back), zoom with the indicator, print preview over the window and Esc, the status pill (shown 610.6 ms after its text for a configured 600, dodges the pointer), element fullscreen and the traffic lights after it, ⌥⌘J console, ⌥⌘C picker, audible on and off, copy URL. Both chrome steps hung after their `end:` line: Chrome's own app-modal "Leave site?" dialog (a beforeunload page the 2.6a checks leave behind; the host cannot answer Chrome's dialogs until 3.4b) held the quit; the window was found with `CGWindowListCopyWindowInfo` (layer 8, 260 × 218, `build/evidence-3.3b/chrome26b-quit-blocking-dialog.png`) and the instance was killed so the tour could continue (chrome26a's 1,286 s is that wait). Delegate members called on RoomCore in chrome26b: `decidePolicy`, `didChangeAudible`, `didChangeSecurityState`, `didChangeStatusText`, `didCommitNavigation`, `didCreate`, `handleUnhandledKeyEvent`, `isReservedKeyEvent`, `webContentsDidClose`, `webContentsDidRequestEnterFullscreen`/`…ExitFullscreen`; `didChangeMuted` was missing (the host's own ⇧⌘M changed `isMuted` without the delegate hearing it; CEF calls it for every change) and is called now (`-RoomSpikeOnly keys`: `didChangeMuted=2`). Never called (3.4; `processGone` is called since the fix above): `didFailCertificateCheck`, `didReceiveAuthChallenge`, `didUpdateDownload`, `willBeginDownload`, `runBeforeUnloadDialog`, `runFileChooser`, `runJavaScriptAlert`/`Confirm`/`Prompt`, `webContentsDidDismissJavaScriptDialogs`, `webContentsDidDismissPermissionPrompt`, `willAskForPermission`, `willShowContextMenu`. Chrome's own UI stood in for two of them: the file choosers opened as sheets (Chrome's `FileSelectHelper` panel; the checks for the sheet pass, the delegate is not called) and HTTP auth signed in through Chrome's login dialog.

## Phase 3.4a — permission prompts, context menus, downloads with history, auth, certificates, file choosers (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Room.app on RoomCore (component build `out/dev` with patches 0017–0022, Debug Swift app) through `scripts/chrome-surfaces.sh --session 2.6b light -- -RoomSpikeOnly <steps>` with throwaway state and engine directories (`build/evidence-3.4a/cs-*`), the display at 60 Hz, Room's window main (`window_main: true` in every run), load 3–7; the embryo host through `scripts/roomcore-features.sh <drive>` (`build/evidence-3.4a/feature-*`). A delegate member reaches the host only on pages (profiles) whose delegate implements it; the embryo host implements the permission prompt and the auth challenge (recording, not answering: its drives answer through Chrome's `PermissionRequestManager` and `LoginHandler` list) and nothing else, so its other drives exercise Chrome's own UI as before.

### Permissions (patch 0017, `RoomPermissionPrompt`)

| Check | RoomCore | CEF (2.6b) |
|---|---|---|
| Location → Room's popover, Allow | prompt `geolocation` (system authorization *not determined*), answered | same |
| Notifications → Don't Allow | prompt `notifications` (system *authorized*), answered | same |
| `navigator.permissions.query` after the answers, then after a reload | geolocation **prompt**, notifications denied; the same after the reload | prompt / denied |
| Notifications again | no prompt, the page reads `denied` | — |
| The site panel's stored settings after Allow / Don't Allow | geolocation Allow, notifications Block (`HostContentSettingsMap`) | same |
| Camera and microphone | no prompt: `NotFoundError` (no device) | same |
| A location prompt open, then a navigation | popover gone, `webContentsDidDismissPermissionPrompt` 0 → 1 (answered prompts: none reported) | same |
| Site panel: Location → Block, Pop-ups → Allow, reload | page reads geolocation `denied`; Clear: cookie `""`, storage `null`; Reset Permissions: nothing stored | same |
| Embryo `permissions` | notifications (kind 4, system authorized) and geolocation (kind 3, not determined) reach the host; denied through the manager: `notification: denied`, `geo: 1`; both prompts reported withdrawn (no host answer) | Views bubble (PR #1) |
| Embryo `ui-local-network` | local network (kind 17) and loopback network (kind 18) reach the host, 4 prompts; deny → `TypeError` and `denied`, accept → the fixture's text and `granted`, reuse without a prompt, reset → `prompt`; a page without a delegate (the replacement tab) keeps Chrome's bubble (`network-owned-dialogs: 1`), its pending request gone with the tab | Views bubble |

Geolocation reads `prompt` although the grant is stored: Chrome's `GeolocationPermissionContextSystem` answers ASK while macOS has not determined the app's location authorization (`LocationSystemPermissionStatus::kNotDetermined`), which is what CEF's B-26 saw. No macOS prompt appeared during the runs (`CGWindowListCopyWindowInfo`: only the stale "Room quit unexpectedly" dialog); by hand: authorize Room's location and rerun (`chapter-3-by-hand.md` "Phase 3.4a" 1). Every request type the fixtures raise without a device reached the host with its kind: geolocation, notifications, local network, loopback network; camera and microphone need a device.

### Context menus (patch 0018, `RoomContextMenu`)

`menu.html` (with a misspelled field added) through `-RoomSpikeOnly menus`; every menu was Room's `NSMenu` (`willShowContextMenu` 4 for 4 right-clicks), the windows after the menus `RoomWindow, NativeWidgetMacNSWindow` (the modal anchor, 3.3b).

| Target | Menu (Room's items, then Chrome's) | Element |
|---|---|---|
| Link | Open Link in New Tab, Open Link in Peek, Copy Link — Open Link in New Tab, Open Link in New Window, Open Link in Split View — Save Link As…, Copy Link Address, Add Link to Reading List — Copy "…", Copy Link to Highlight, Search Google for "…", Print "…", Translate "…" — Inspect — Speech | link, **link text "A link to the dialogs page"** (CEF: not available) |
| Image | Open Image in New Tab, Copy Image Address — Open Image in New Tab, Save Image As…, Copy Image, Copy Image Address — Search This Image with Image Search — Inspect | media image; cancelled, closed |
| Misspelled "mispelled" in a field | misspelled, dispelled — Add to Dictionary, Use Enhanced Spell Check — Look Up "mispelled" — Import Passwords — Undo, Redo — Cut, Copy, Paste — Search Google for "mispelled", Translate "mispelled" — Inspect — Speech | editable, misspelled `mispelled`, suggestions `misspelled`, `dispelled` |

Room's Open Link in New Tab opened the link below the page (today 5 → 6, selection stays); Chrome's Copy Link Address (`IDC_CONTENT_CONTEXT_COPYLINKLOCATION`, chosen in the host's menu) ran in the engine: pasteboard `http://127.0.0.1:8766/dialogs.html`. Its first run crashed: Chrome's link-copied toast (`ToastController::CreateToast`, `CHECK_IS_TEST()` without a BrowserView anchor); `//room` disables Chrome's copy toasts now (B-58).

### Downloads (patch 0019, `room_downloads.mm`)

| Check (`downloads.html`) | RoomCore | CEF (2.6b) |
|---|---|---|
| The slow file (6 MB at 1 MB/s) at 1.5 s | in the host's folder, ring 0.24, "1,4 MB of 6 MB — 721 KB/s, 7 s left" | the same |
| The same file twice | `room-2.6b-small.txt`, `room-2.6b-small (1).txt`, both on disk | the same |
| No length | `totalBytes` nil, ring spins (-1) | the same |
| Pause, resume, cancel through `Profile` | paused, resumed, cancelled, partial file removed; `canResume` **true while paused** (Chrome's) | tracked by `EngineCEF` |
| End | 4 complete + 1 cancelled, badge 2, slow file 6,000,000 bytes; opening the popover clears the badge; Clear empties the list | the same |
| Delegate calls | `willBeginDownload` 5, `didUpdateDownload` 47 | 5, 52 |
| **Relaunch on the same state (B-28)** | the popover lists **5 of 5** (`room-2.6b-cancel.bin` cancelled, the other four complete), newest first, from Chrome's `DownloadHistory` | empty |
| Quit with the slow download running | no Chrome prompt (macOS: `BrowserCloseManager` leaves the question to `AppController`, which Room does not install); the quit continues; after a relaunch the download is listed as cancelled | — |
| Embryo `ui-download-close` | `ConfirmBrowserCloseWithPendingDownloads` reaches `//room` ("closing with 1 downloads in progress asks the host"); the embryo's browser delegate has no answer: closing continues | auto-confirmed (PR #1) |
| Embryo `downloads`, `ui-download-destination` | Chrome's determiner (the embryo profile has no downloads delegate): bytes 26, the Save panel as a sheet, cancel | the same |

### Auth, certificates, files (patches 0020–0022)

| Check | RoomCore |
|---|---|
| `/auth` | Room's sign-in sheet (realm "Room test", basic, the username field focused), room / secret → "Signed in as room"; `didReceiveAuthChallenge` 1; Chrome's dialog never shown |
| Embryo `auth` | the challenge reaches the host (realm "RoomCore fixture", basic); cancel and supply through Chrome's `LoginHandler` list (the handler is `//room`'s subclass) → the fixture loads |
| `https://127.0.0.1:8767/secure.html` | Room's interstitial: -202 `ERR_CERT_AUTHORITY_INVALID`, overridable, chain 1, the row titled by the host; Go Back with nothing behind → the entry kept, the page closed, the empty card (B-25); again → Visit … Anyway offered → "Self-signed page" (`dangerous`) |
| **`https://subdomain.preloaded-hsts.badssl.com/` (B-24; one request)** | Room's interstitial: -200 `ERR_CERT_COMMON_NAME_INVALID`, **not overridable, no Visit … Anyway** (`research/screenshots/phase-3.4a/phase-2.6b-certificate-hsts-light.png`); net-log `build/evidence-3.4a/cs-prompts/netlog.json`: `GET https://subdomain.preloaded-hsts.badssl.com/` (annotation 63171670, the navigation), no other badssl host |
| Embryo `certificate` | Chrome's interstitial (no delegate member on the embryo), leave restores the page |
| `files.html` | Room's open panel as a sheet three times: `public.image`; CSV + PDF, multiple; folders only; cancelled; `runFileChooser` 3 |
| Embryo `ui-file-input` | Chrome's `NSOpenPanel` sheet (no delegate member), cancel once, gone with its tab |

### The baseline after the last engine change (`build/baseline/3.4a-final3`, embryo host)

nav passed 10.8 s; ten-page quits **0.241 / 0.284 / 0.216 s** (load 5.4 / 6.2 / 11.0), 0 helpers left, 0 crash reports; stub hits none. Two earlier attempts after the same change stopped at run 3 with "ten-page fixture incomplete": stackoverflow.com never finished loading (it answers this machine's plain requests with 403, a bot check); `3.4a-2`, before the toast change, passed 3/3 (0.413 / 0.284 / 0.230 s).

### The grand tour's chrome section (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups chrome light`, `build/grand-tour/20261005-093813-roomcore`, 8.8 min)

| Step | 3.3b | 3.4a | Failures, attributed |
|---|---|---|---|
| chrome26a | 15 / 10 | **22 / 3** | JS dialogs, beforeunload Stay (3.4b); `window.open` opener messages read `null` (B-55) |
| chrome26b | 36 / 17 | **48 / 5** | JS dialogs, beforeunload Stay, delegate members never called (`runBeforeUnloadDialog`, `runJavaScriptAlert/Confirm/Prompt`, `webContentsDidDismissJavaScriptDialogs`: 3.4b); opener messages (B-55); the helper crash report count (RoomCore's Crashpad writes under the data root, the check is CEF-shaped, as 3.3b) |
| total | 51 / 27 | **70 / 8** | nothing 3.4a owns fails |

Both steps again hung after their `end:` line behind Chrome's app-modal "Leave site?" alert (a layer-8 260 × 218 Room window; the beforeunload page the dialogs check leaves): the instances were killed 30–45 s after the end so the tour could go on (3.4b's).

## Phase 3.4b — JavaScript dialogs, beforeunload and the quit, the hung page, external protocols, notices, capture state, media session, the Views bubbles that stay (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Room.app on RoomCore (component build `out/dev`, series 22, Debug Swift app) through `scripts/chrome-surfaces.sh --session 2.6a|2.6b|3.4b light` (throwaway engine directories, the `demo` fixture, 1244 × 818 pt, 60 Hz, `window_main: true` in every run, load 3–8) and `scripts/run-spike.sh closeunload|quitstay` (throwaway state and engine directories, no DevTools port); the embryo host through `scripts/roomcore-features.sh <drive>` (`build/evidence-3.4b/feature-*`). Evidence: `build/evidence-3.4b/`. Captures: `research/screenshots/phase-3.4b/`.

### How each surface reaches the host (seams before patches, B-61)

| Surface | Chrome's path | Room's route | Patch? |
|---|---|---|---|
| alert, confirm, prompt | `BrowserWebContentsDelegate::GetJavaScriptDialogManager` → `TabModalDialogManager::FromWebContents` → its delegate's `CreateNewDialog` (Views) | the page's `TabModalDialogManager` recreated with a `//room` delegate (Chrome's desktop delegate inside); its view is the host's sheet | no (the 0023-shaped hook in `GetJavaScriptDialogManager` was not needed) |
| beforeunload (⌘W, reload, quit) | always app-modal: `AppModalDialogManager` → its native dialog factory (Chrome's Cocoa alert) | `SetNativeDialogFactory` (Chrome's factory kept for other pages) | no |
| hung renderer | `RendererUnresponsive` → `TabDialogs::ShowHungRendererDialog` (Views) | the page's `TabDialogs` user data wrapped by `RoomTabDialogs` | no |
| external protocol | `ExternalProtocolHandler::RunExternalProtocolDialog` (Views static) | patch 0023 → the host's sheet → `LaunchUrlWithoutSecurityCheck` | **0023** (no seam: the only override is `SetDelegateForTesting`, which replaces the whole handler) |
| infobars | `ContentInfoBarManager` (container: BrowserView, never drawn for Room pages) | `InfoBarManager::Observer` → toast | no |
| translate offer | desktop: `ChromeTranslateClient::ShowBubble` → `TranslateBubbleFactory::Show` (a bubble, not an infobar) | `TranslateBubbleFactory::SetFactory` → the same notice path | no |
| capture state | `MediaStreamCaptureIndicator` | its `Observer`, `StopMediaCapturing` | no |
| media session | `content::MediaSession` | `MediaSessionObserver` (mojo) | no |

### Task 5: dialogs and beforeunload (`chromesurfaces2 -RoomSpikeOnly dialogs,dismissals`, then the full 2.6a/2.6b runs)

| Check | RoomCore 3.4b | RoomCore 3.4a | CEF 2.6b |
|---|---|---|---|
| confirm ×2, prompt, alert ×2 | Room's sheet each time (`DialogPanelView`; the prompt's field has the keyboard); answers `[confirm,true],[confirm,false],[prompt,"Grace"],[alert,"ok"]` (read from the page's DOM mirror, B-55); engine log: 7 "to the host", 0 Chrome dialogs | Chrome's Views dialogs, the tour failed | the same answers |
| the second alert withdrawn by a navigation | sheet gone, `webContentsDidDismissJavaScriptDialogs` 0 → 1 (`TabModalDialogManager::DidStartNavigation` → `CloseDialogWithoutCallback`), the page reached the new URL | — | the same (CEF needs Room's own dismissal) |
| ⌘W with beforeunload armed: Stay | Room's Leave/Stay sheet; page in the card, **the same entry** (`entry kept=true`) | Chrome's alert, entry already removed | sheet; page back in a **new** Today entry |
| ⌘W: Leave | page closed, entry removed | — | the same |
| `closeunload` (no CDP): `close()` stay / leave | sheet after 22 / 21 ms; alive / closed | CDP answered Chrome's alert | — |
| `closeunload`: ⌘W stay / leave | sheet after 22 ms; page alive, entry kept and selected, Today 1 → 1 / page closed, entry removed, Today 1 → 0 | — | — |
| `quitstay` (no CDP): ten pages, ⌘Q's path, Stay | the host's sheet (541 ms after `NSApp.terminate`, through Chrome's close path); `RoomAppController: stopTryingToTerminateApplication`, `quit cancelled (1 waiting)` 177 ms after the sheet (150 ms of it the spike's own pause); 10 → 10 pages alive, the same objects, 10 → 10 entries, window visible | CDP answered Chrome's alert (15–25 ms) | — |
| the runner's quit after it: Leave | the sheet again after 28 ms; `quit proceeds (1 waiting)` | — | — |
| embryo `dialogs` (no dialog members: Chrome's own) | Chrome's tab-modal dialogs and its beforeunload, answered over CDP; `beforeunload-cancelled: true` (Chrome's factory kept for pages that do not answer) | the same | — |

The first run showed the confirm in Room's sheet and then a page that never answered a script: the view deleted itself before running the manager's button callback, and `TabModalDialogManager::CloseDialog` returns early once its view is gone; fixed (callback first). A renderer of one of the ten typical sites hit a Blink `DCHECK` (`layout_object.h:518`, `NeedsLayout`) during the quit-stay run (Chromium's, the dev build's `DCHECK_ALWAYS_ON`); the pages stayed alive.

### Task 6: the hung page, external protocols, notices (`pageservices`, `--enable-features=RendererHangWatcher:delay/3s`)

| Check | Result |
|---|---|
| `hang.html`: a two-minute busy loop, then a key | the unresponsive-page view after **4,013 ms** (3 s delay + Chrome's 1 s ping), "This Page Is Not Responding" with Wait and Exit Page (`phase-3.4b-unresponsive-light.png`) |
| Wait | the view goes, the page stays (`alive`); still hung, asked again after 3,600 ms |
| Exit Page | `RESULT_CODE_HUNG`: `processGone(.killed)`, the crashed-page view ("This Page Was Stopped", Reload); Return/Reload brings the page back (`…-unresponsive-exited-light.png`). Chrome's Views hung-page dialog never shown; `webContentsDidBecomeUnresponsive` 2. The responsive edge (`Hide…`) was not exercised: the fixture's loop outlasts the run |
| `external.html` → `roomtest://open` (a throwaway applet handling `roomtest:`, `scripts/external-protocol-fixture.sh`; Launch Services ignores applets under `$TMPDIR`) | Room's sheet "Open “RoomTestHandler”?" (`…-external-sheet-light.png`); request: gesture, initiating origin `http://127.0.0.1:8766/`; Cancel → blocked, no launch |
| the same link again | asked again (a refusal is not remembered); Open → the applet launched and recorded the URL |
| `roomtest://again` | the delegate asked, **no sheet** (scheme allowed for the session), launched (2 records) |
| `nosuchscheme-room://x` | the host never asked: Chrome's "does not have a registered handler" console error before its dialog step |
| `translate.html` (German) | Chrome's offer as a notice: "Translate this page from German to English?" with Translate, as a toast (`…-translate-offer-light.png`); Translate → the offer withdrawn (`didRemoveInfoBar`), the toast gone, the heading "Welcome to the library", `lang=en` after 8 s. Needs an API key: Chrome's `TranslateManager` offers nothing without `google_apis::HasAPIKeyConfigured()`; the run sets `GOOGLE_API_KEY=room-placeholder-no-key` (the element script loaded and translated anyway). Chrome's translate bubble never appeared |
| an engine infobar: CDP `Emulation.setAutomationOverride` | `AUTOMATION_INFOBAR_DELEGATE` (73), "Chrome is being controlled by automated test software", no buttons, as a toast (`…-infobar-light.png`); `enabled: false` → removed, the toast taken down |
| page unresponsive as an infobar | not on the desktop in M154 (it is the hung-page dialog above) |

### Task 7: capture state and the media session

| Check | Result |
|---|---|
| `capture.html` with `--use-fake-device-for-media-stream` (no fake UI): Camera and microphone | Room's popover (camera + microphone), Allow → `captureState` camera + microphone (3) 21 ms after the answer; the row shows the red camera symbol beside the speaker (`…-capture-on-light.png`); the page: `audio:live,video:live` |
| `stopCapturing(.userMedia)` | `captureState` empty after 22 ms, the row's indicator gone; the page: `audio:ended,video:ended` |
| the first run | Allow crashed: 3.4a's prompt asked `GetGeolocationPromptType()`, which CHECKs one request (camera + microphone are two); fixed |
| embryo `ui-capture` | Chrome's indicator 3 → 0 after `StopMediaCapturing`; `//room`'s state 0 → 2 → 3 → 1 → 0 on the page |
| embryo `ui-screen-share` | the desktop picker (Views) opened and cancelled: `NotAllowedError` |
| `media.html`: `navigator.mediaSession.metadata` and a playing tone | `mediaSession`: "Room Test Tone" / "Phase 3.4b" / "Fixtures", artwork `http://127.0.0.1:8766/image.svg`, playing; logged by the tab controller (`Room: media session …`). Before the fix every page reported a session (Chrome's default metadata: title and host); now only while the session is not inactive |

### Task 8: the Views bubbles that stay

| Drive | Result |
|---|---|
| embryo `fedcm` (15 s, exit 0) | the passive failure bubble and the active loading modal shown and destroyed (`fedcm-passive: 1`, `fedcm-active: 1`) through patch 0008's anchor |
| embryo `ui-usb` (7 s) | one owned chooser, cancelled: `NotFoundError` |
| embryo `ui-hid` (8 s) | one owned chooser, cancelled: empty list, `granted: 0` |
| embryo `ui-bluetooth` (8 s) | CDP `DeviceAccess.deviceRequestPrompted`, one owned chooser with 0 devices, cancelled: `NotFoundError` |
| embryo `ui-extension-device` (8 s) | the extension page's `requestDevice` settles `NotFoundError`: patch 0012's safe rejection, **not** a chooser (3.6b) |
| embryo `ui-serial` | **not verified**: the host is ended by macOS (TCC, "must contain an NSBluetoothAlwaysUsageDescription key") when Web Serial enumerates Bluetooth ports. The drive launches the host from a shell, so the responsible process for TCC is the launching app (here the Claude desktop app), not Room; the key is now in Room's Info.plist (Chrome ships it), the crash stays for shell launches. Next: launch the drive through `open` or disclaim responsibility; by hand on Room.app |
| Room.app: `chooser.html` → `navigator.usb.requestDevice` | Chrome's USB chooser (`NativeWidgetMacNSWindow`, 448 × 444 pt) over Room's window, anchored at the header (`phase-3.4b-usb-chooser-light.png`; a stale "Room quit unexpectedly" dialog is on screen beside it); Esc → closed, the page `NotFoundError` |

### The 2.6 checklist on RoomCore (`chrome-surfaces.sh --session 2.6b light`, recording proxies)

| Member | RoomCore 3.4b calls | CEF 2.6b |
|---|---|---|
| `didCreate` | 2 | 2 |
| `webContentsDidRequestEnterFullscreen` / `…Exit` | 1 / 1 | 1 / 1 |
| `didChangeStatusText` | 6 | 32 |
| `willShowContextMenu` | 4 | 2 |
| `runJavaScriptAlert` / `Confirm` / `Prompt` | 2 / 2 / 1 | 2 / 2 / 1 |
| `runBeforeUnloadDialogForReload` | 2 | 2 |
| `webContentsDidDismissJavaScriptDialogs` | 1 | 8 (CEF also resets on navigations) |
| `willAskForPermission` / `webContentsDidDismissPermissionPrompt` | 3 / 1 | 3 / 1 |
| `didReceiveAuthChallenge` | 1 | 1 |
| `didFailCertificateCheck` | 2 | 2 |
| `runFileChooser` | 3 | 3 |
| `isReservedKeyEvent` / `handleUnhandledKeyEvent` | 11 / 9 | 11 / 9 |
| `didConsumeKey` | 0 in this run (no key the page consumed; 3.2b's `keys` spike measured it) | not available |
| `didChangeAudible` / `didChangeMuted` | 2 / 2 | 2 / 2 |
| `didChangeSecurityState` | 2 | 24 (CEF on every load) |
| `processGone` | 1 (`.crashed`) | 1 |
| `webContentsDidClose` | 4 | 3 |
| `decidePolicy` / `didCommitNavigation` | 36 / 30 | 33 / 26 |
| `willBeginDownload` / `didUpdateDownload` | 5 / 47 (downloads step rerun after a spike race fix; the full run had 4 / 41) | 5 / 52 |
| 3.4b: `webContentsDidBecomeUnresponsive` / `…Responsive` | 2 / 0 (`pageservices`) | — |
| `shouldOpenExternalURL` | 3 | — |
| `didAddInfoBar` / `didRemoveInfoBar` | 2 / 2 | — |
| `didChangeCaptureState` | 4 | — |

New rows of the exit: permission types (3.4a: geolocation, notifications, local and loopback network; 3.4b: camera + microphone with fake devices), capture state (above), download restore (3.4a: 5 of 5), HSTS (3.4a). The downloads step's "(1)" name was missing in the full run: the spike clicked the second link before the first download's row existed (an `allSatisfy` on an empty list) and Blink dropped the second navigation as a duplicate (14 ms apart); the spike waits for the row now: `room-2.6b-small.txt`, `room-2.6b-small (1).txt`.

### The baseline after the last engine change (`build/baseline/3.4b-final`, embryo host)

nav passed 10.4 s; ten-page quits **0.244 / 0.245 / 0.253 s** (load 4.5 / 6.4 / 11.2), 0 helpers left, 0 crash reports; stub hits none. Two earlier attempts: one stopped at run 3 on stackoverflow.com's 403 (as 3.4a), the other hung at launch behind AppKit's "reopen windows?" alert, which the host showed after this session's crashes (the TCC ends and the profile CHECK below); the engine scripts pass `-ApplePersistenceIgnoreState YES` now. Earlier baselines found two of this session's bugs: the capture observer's list must be empty when the dispatcher singleton goes at exit (removed at the quit and by an at-exit task), and `closeunload` crashed after closing a window's only page: Chrome destroyed the profile with its last Browser and the next page found it gone (each `RoomProfile` holds a `ScopedProfileKeepAlive`).

### The grand tour's chrome section (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups chrome light`, `build/grand-tour/20261005-113816-roomcore`, 2.4 min)

| Step | 3.4a | 3.4b | Failures, attributed |
|---|---|---|---|
| chrome26a | 22 / 3 | **23 / 2** | the dialog answers and the `window.open` opener messages read page globals from the isolated world (B-55): both read the page's DOM mirror after the tour (`dialog_results` and `opener messages=["hello from open"]` in a standalone rerun) |
| chrome26b | 48 / 5 | **50 / 3** | the same two (B-55); the helper crash report count (CEF-shaped; Crashpad writes under the data root) |
| total | 70 / 8 | **73 / 5** | nothing 3.4b owns fails; both steps quit without a hang (wall time 2.4 vs 8.8 min) |

## Background hardening (laptop, 2026-10-03)

PR #1 (`bg/roomcore-hardening`), merged in 3.1a. Measured on the laptop (M1 Max, 64 GB), component build. Backlog ids renumbered at the merge: the shutdown watchdog and concurrent teardown are B-38, the TLS attribution B-39, parked patch 0010 B-40.

### RoomCore background hardening — laptop M1 Max (2026-10-03)

Component build with active DCHECKs, five original patches unchanged. Each
feature uses an isolated profile and warning-level first-hit stub logging.
Native visual/click checks remain explicit reviewer tasks under AGENTS.md.

| Feature | Chrome path | Window members needed | Fixed how / result |
|---|---|---|---|
| dialogs | JavaScriptTabModalDialogManagerDelegateDesktop → JavaScriptTabModalDialogViewViews → constrained_window_views.cc:295; NativeWidgetMac::InitNativeWidget at native_widget_mac.mm:589 | GetWebContentsModalDialogHostFor, GetWebContentsModalDialogHost; native Views parent | Previous null host CHECK (exit 134), then arbitrary NSView parent DCHECK (exit 134). //room supplies a lazy WebContentsModalDialogHost and transparent noninteractive Views child anchor tied to the Swift NSWindow; host observers follow resize/move and teardown. Three dialogs opened/closed, cancelled results undefined/false/null, page alive, exit 0; no watchdog. Native appearance/focus still needs review. |
| keys | CDP Input.dispatchKeyEvent → RenderWidgetHost input | common activation/toolbar stubs only in this page-event drive | Page recorded a/KeyA, exit 0, no watchdog. Native reserved shortcuts and alternate layouts unverified. |

Evidence: `feature-dialogs-cdp-close`, `feature-keys-cdp-close` (local ignored
raw logs). Modal rebuilds: 24 s initial, 20 s final teardown version; final
package stage 3.5 s + host 8.1 s, signature valid. Post-fix baseline
`baseline-modal-final`: nav **11.935 s**, assertions passed; ten loaded pages,
quit **0.442 s**, load1 **32.85**, 28 helpers observed, **0 left**, **0 new
crash reports**, exit **0**. Private API headers and patch files unchanged.

| Feature | Chrome path | Window members needed | Fixed how / result |
|---|---|---|---|
| permissions | PermissionPromptBaseView::AnchorToPageInfoOrChip → bubble_anchor_util_views.cc GetPageInfoAnchorConfiguration | GetLocationBar → GetChipAnchor; Views native parent | Null BrowserView fallback caused SIGSEGV (exit 139). Return a 1×1 Views anchor via the existing LocationBar hook. Notification/geolocation trigger survives, exit 0 in 16 s. Native prompt completion/layout is still unverified. |

Permission-anchor baseline: nav **13.694 s**, ten-loaded-page quit **0.647 s**
at load1 **18.40**; 28 helpers observed, **0 left**, **0 new crash reports**,
exit **0**. Evidence `feature-permissions-anchor`, `baseline-permissions`,
TMPDIR `roomcore-quit-7h1b5zin`. No raw patch or public header changes.

| Feature | Chrome path | Window members needed | Fixed how / result |
|---|---|---|---|
| find | chrome::Find → BrowserWindowFeatures::GetFindBarController → FindBarPlatformHelperMac::UpdateFindBarControllerFromPasteboard | CreateFindBar, native Views owner/bounds | Null FindBar caused SIGSEGV, exit 139. //room FindBarOwner returns Chrome FindBarHost; find and next survive, exit 0 in 18 s. Native keyboard/focus and match counts pending. |

Find baseline: nav **11.970 s**, ten loaded pages, quit **2.262 s**, load1
**15.57**, 27 helpers observed, **0 left**, **0 crash reports**, exit **0**.
Evidence `feature-find-owner`, `baseline-find`, TMPDIR `roomcore-quit-99uooayy`.

#### Feature surface matrix after three crash fixes

All 18 feature triggers have run on the component build. The 17 completed
drives below exit 0 without watchdog intervention; fullscreen exits 0 but its
promise is rejected, so the driver correctly reports an error. This is **not**
a claim that all 18 functional acceptance checks are complete. Native UI gaps
are listed explicitly. The final regression is recorded below.

`C` below is the common first-hit set observed in every feature process:
`GetCanResize GetRestoredState GetStatusBubbles GetWindowShowState GetWorkspace
IsVisibleOnAllWorkspaces OnTabDetached UpdateLoadingAnimations
UpdateReloadStopState UpdateToolbar UpdateToolbarSecurityState`.
The log lists called stubs, not every real member Chrome uses. Extra real
interfaces required to repair a crash are named separately.

| Feature | Chrome path driven | Window members needed / logged | Fix and observed result | Remaining acceptance |
|---|---|---|---|---|
| popups | Browser navigation / AddNewContents; Blink date picker | C + LinkOpeningFromGesture | 10 s, two windowOpen events; host still owns 1 page; popup Browsers fall back to Chrome BrowserView | Swift ownership of new pages/windows, native select/color/date anchoring |
| dialogs | JavaScriptTabModalDialogViewViews / constrained_window | C + GetWebContentsModalDialogHostFor/GetWebContentsModalDialogHost | Modal-host fix; all 3 opening/closed events, cancelled undefined/false/null, exit 0 | Native focus/appearance, beforeunload |
| keys | CDP Input.dispatchKeyEvent / renderer input | C | a/KeyA received, exit 0 | Native reserved shortcuts, alternate keyboard layout |
| audio | Blink HTMLMediaElement → audio service | C | 11 s; playback clock reached 0.076211 s after 201.8 ms polling, readyState 4, not paused | Audible output and Web Audio oscillator |
| scroll | Blink rAF / compositor scroll | C | 180 frames / 3006.4 ms, scrollY 1440; exit 0 in 12 s | Native wheel / clipped composite |
| transparent | CDP Emulation background / Blink paint | C | alpha-zero background drive, exit 0 in 9 s | Native material composite capture |
| corners | Blink paint / native web contents view | C | body rgb(208,16,90), exit 0 in 8 s | Native resize/clipping/hairline capture |
| band | CDP Input.dispatchMouseEvent | C | page coordinates [200,8], [200,34], exit 0 in 9 s | Native toolbar hit testing |
| form | Blink form submit / Chrome password manager | C | HTTP GET submitted test fields, password-save IPH code reached, exit 0 in 8 s | Save prompt and stored autocomplete selection |
| extension | Chrome extension loader / MV3 worker / content script | C | worker-installed console message; content-script-ran after reload, exit 0 in 10 s | chrome.tabs/windows, action popup, extension manager |
| downloads | Browser download manager, local Content-Disposition | C | exact 26-byte fixture saved, exit 0 in 8 s; CDP selects destination | Native destination chooser and cancellation UI |
| permissions | PermissionPromptBubble → bubble_anchor_util_views | C + modal host; LocationBar.GetChipAnchor | Views anchor fix; 2 real Deny actions; notification denied + geolocation error 1; 19 s, exit 0 | Native prompt anchoring/focus and dismissal UI |
| auth | HTTP login handler / constrained-window dialog | C + both modal-host getters | 401 challenge cancelled, then fixture credentials produce HTTP 200; serial 10 s, exit 0 | Native credential fields/focus; concurrent teardown failure retained below |
| certificate | SSL blocking page / security interstitial | C | Privacy error title for self-signed fixture, exit 0 in 10 s | Back/leave action |
| find | Chrome Find command / FindBarController / FindBarHost | C + CreateFindBar/modal host; FindBarOwner | Find owner fix; 400 matches / 400 DOM rows; next and close commands; 17 s, exit 0 | Native focus and typing |
| zoom | Chrome zoom commands / ZoomController | C | scale ratios 2.2 → 2 → 1.8 → 2; exit 0 in 23 s | Native zoom feedback UI |
| print | Chrome print command / print preview / constrained-window | C + both modal-host getters | Print trigger and close survive, exit 0 in 9 s | Preview contents and native cancellation; no print job sent |
| fullscreen | FullscreenController / ExclusiveAccessContext | C + IsTabStripEditable | Safe rejection: TypeError not granted; exit 0 in 6 s | Unsupported: RoomExclusiveAccessContext::CanUserEnterFullscreen returns false |

Chapter 3 must provide host ownership for popup/new-tab windows, native
address/permission anchors, find focus and keyboard routing, permission/auth
completion, download status/cancellation, extension actions, and a page
fullscreen state machine with visible origin/escape affordance. Null-returning
stubs cannot provide those contracts. A safe rejection is recorded as an
unsupported surface, never as successful fullscreen. Native composition and
input checks need reviewer interaction under the current AGENTS.md rule.

#### Final regression after network and Crashpad changes

2026-10-03, feature-final2-* evidence, ad-hoc packaged component build.
The first final attempt found a driver race (pending URL before committed DOM),
not an engine crash. After adding explicit document readiness, all 18 processes
exit 0 without watchdog intervention. Fullscreen remains an explicit refused
promise; this does not establish working fullscreen or close the native UI gaps.

| Feature | Process seconds | Result |
|---|---:|---|
| popups | 16 | 2 windowOpen events; host-owned page count 1 |
| dialogs | 9 | 3 dialogs dismissed through Chrome callbacks |
| keys | 8 | a/KeyA received |
| audio | 11 | Playback clock advanced |
| scroll | 11 | rAF scrolling completed |
| transparent | 8 | rgba(0,0,0,0) |
| corners | 9 | Fixture loaded |
| band | 8 | Both page coordinates received |
| form | 8 | Form submitted |
| extension | 10 | content-script-ran |
| downloads | 8 | Exact 26 bytes saved; native chooser bypassed by CDP |
| permissions | 8 | Prompt trigger survived |
| auth | 10 | Challenge observed |
| certificate | 10 | Privacy error interstitial observed |
| find | 10 | Find/next commands survived |
| zoom | 12 | Plus/reset/minus/reset completed |
| print | 9 | Chrome print command survived |
| fullscreen | 5 | Unsupported safe rejection; no functional pass |

Last engine-change baseline: nav 19.676 s, ten loaded pages, quit 2.591 s,
load1 43.40, 26 helpers observed, 0 left, 0 new crash reports, exit 0.
The net-log parser's 8 regression tests pass. No public-header changes.

#### Stronger completion probes

- Permissions: 2 Chrome PermissionRequestManager::Deny calls complete the
  actual page promises: notification "denied", geolocation PERMISSION_DENIED
  (1). 19 s process, exit 0. No synthetic Browser.setPermission override.
- HTTP auth: LoginHandler cancel, reload, supply room/spike, then fixture HTTP
  200 and expected H1. Serial repeats exit 0 in 13 s and 10 s. The first
  concurrent run hit Chrome's teardown watchdog and exited 2 after completion;
  this is a rejected sample, not a pass. Raw evidence retained.
- Find: private helper starts "Row", waits for the current request ID and full
  count; 400 DOM rows / 400 matches, then Find Next and Close Find. 17 s, exit 0.
  Earlier probe reads of 0 and 189 were rejected; the first was a stale query,
  and the second was sampled before the count settled. No DCHECK disabled.
- New actions are private ObjC selectors, require -RoomSpike and a 127.0.0.1
  active page, and use Chrome's real completion paths. Public headers unchanged.

Post-probe baseline: nav 11.274 s; ten-page quits 1.209 s (load1 23.93) and
0.742 s (load1 46.18), each 26 helpers / 0 left / 0 crash reports, exit 0.
Third repeat rejected: Stack Overflow remained loading at 63 s, only 9/10
pages loaded. Earlier concurrent sample quit 1.910 s but retained 9 helpers
past the unchanged 5 s grace; helpers later exited. Do not include either
rejected sample in successful quit statistics. HTTP-auth concurrent teardown
watchdog is a known unresolved load-sensitive failure despite serial passes.

#### Regression after demand-CDM hook

2026-10-03, feature-cdm-final-*; final patch 0007 / registration callback
build. All 18 processes exit 0 without a timeout. The first 17 drives pass;
fullscreen again rejects with TypeError: not granted, so its driver correctly
returns failure. This is unsupported behavior, not a functional pass.
Native UI gaps remain.

| Feature | Process seconds |
|---|---:|
| popups | 9 |
| dialogs | 9 |
| keys | 8 |
| audio | 10 |
| scroll | 11 |
| transparent | 8 |
| corners | 8 |
| band | 9 |
| form | 10 |
| extension | 11 |
| downloads | 8 |
| permissions | 10 |
| auth | 10 |
| certificate | 10 |
| find | 9 |
| zoom | 12 |
| print | 10 |
| fullscreen | 5 |

Post-change baseline: nav 12.058 s; ten loaded pages, quit 0.354 s at
load1 15.50, 26 helpers, 0 left, 0 new crash reports, exit 0.
Widevine fresh installation and MediaKeys creation now pass; negative-key,
installed-profile reuse and bounded offline behavior are recorded in the
network audit. Licensed playback is not established by MediaKeys creation.

#### Additional surface found by live open10: FedCM

| Feature | Chrome path | Window members it needs | Fixed how / evidence |
|---|---|---|---|
| Federated sign-in bubble / modal | FedCmAccountSelectionView::CreateDialogWidget / GetAnchorView → BubbleDialogDelegate; then TabDialogManager::ShowDialog | Views anchor/native parent and initialized BrowserElements primary widget | Patch 0008 anchor hook returns the existing Room modal bridge only for Room windows; initialize BrowserElementsViewsImpl through Init(view). Private -RoomSpike fedcm opens and destroys a real passive failure bubble and active loading modal; both return true, 18 s process, exit 0 |

Original live open10 aborted at bubble_dialog_delegate_view.cc:207 because
kActiveContentsWebViewRetrievalId returned null. First probe after providing
an anchor exposed a second null-primary-widget crash in TabDialogManager
(line 360). That second dependency is supplied through the existing context
initialization API, without another patch. The opaque Swift page view is not
registered as a fake views::WebView. Native focus, account selection, IdP popup
and token exchange remain unverified; this spike does not sign into a service.

Post-FedCM baseline: nav 12.447 s; ten loaded pages, quit 0.635 s at load1
28.40, 27 helpers / 0 left / 0 new crash reports, exit 0. The earlier failed
open10 sample remains rejected and separate from the old shutdown watchdog.

#### Full repeat on committed FedCM engine 2a04498

All 18 original processes plus FedCM exit 0 without a watchdog; 18 drivers
pass and fullscreen remains the explicit unsupported driver failure.

| Feature | Process seconds | Driver exit |
|---|---:|---:|
| popups | 8 | 0 |
| dialogs | 8 | 0 |
| keys | 9 | 0 |
| audio | 10 | 0 |
| scroll | 11 | 0 |
| transparent | 8 | 0 |
| corners | 8 | 0 |
| band | 9 | 0 |
| form | 8 | 0 |
| extension | 10 | 0 |
| downloads | 8 | 0 |
| permissions | 8 | 0 |
| auth | 10 | 0 |
| certificate | 10 | 0 |
| find | 10 | 0 |
| zoom | 13 | 0 |
| print | 9 | 0 |
| fullscreen | 4 | 1 |
| fedcm | 10 | 0 |

Raw evidence: feature-complete-*; receipts identify 2a04498.

#### Extension tabs/windows lifecycle

The stronger worker probe reached real chrome.tabs.create and initially got
"Tabs cannot be edited right now (user may be dragging a tab)." The generated
IsTabStripEditable stub always returned false. //room now permits edits while
the TabStripModel is not closing and the explicit test-disable flag is unset.
No patch/public API change; first-hit logging remains enabled.

First post-fix run: content script marker present, service worker connected,
tab count 1 → 2 → 1 across create/remove, popup window created then removed,
process 24 s, exit 0. action.openPopup could not find an active browser window;
this is an explicit UI gap, not a popup acceptance pass. A focused-window
probe follows. Host tab/popup ownership and drag-state integration remain
Chapter 3 requirements.

Focused-window repeat still reports "Cannot show popup for an inactive
window" after awaiting chrome.windows.update({focused:true}) with the explicit
original window ID. Tab/window lifecycle assertions still pass. The action
popup is therefore unverified; native activation and toolbar ownership are
remaining Room/Chapter 3 work, not hidden by a passing process exit.

Post-tab-edit baseline: nav 11.570 s; ten loaded pages, quit 0.534 s at load1
12.39, 24 helpers / 0 left / 0 new crashes, exit 0.

#### Explicit activation for extension action requests

Room Activate now matches Chromium's application-before-key-window ordering.
The 18 s extension run exits 0, with NSApp active and Room window key/main.
Tabs/windows lifecycle still passes. The action API now reaches toolbar
availability and returns "Browser window has no toolbar"; action UI is still
unsupported and must be supplied by Chapter 3. Source path:
NativeWidgetNSWindowBridge::SetVisibilityState and ActionOpenPopupFunction.
No patch/public ObjC change. Baseline nav 11.419 s; ten-page quit 0.549 s,
26 helpers / 0 left / 0 new crashes, exit 0.

#### Completion probes on activation engine eb55062 — 2026-10-03

| Feature | Measured result | Remaining boundary |
|---|---|---|
| Download completion/cancel | Exact 26-byte attachment; real Browser.cancelDownload yields canceled event for its GUID; server disconnect after 131,072 / 33,554,432 bytes; no finalized/partial slow file remains; 17 s process, exit 0 | Native chooser/cancel button and product status UI |
| Certificate leave | net::ERR_CERT_AUTHORITY_INVALID, Privacy error page, real primary-button handler returns to committed safe HTTP fixture; 11 s process, exit 0 | Native pointer/focus; no certificate override used |
| beforeunload | Actual Page.javascriptDialogOpening type beforeunload; Chrome cancellation callback preserves original page; handler cleared for cleanup; 16 s process including alert/confirm/prompt, exit 0 | Native focus/keyboard; window-close-specific prompt |
| Web Audio | Muted oscillator, state running, 48,000 Hz, render clock advances 0.261333 s, AudioContext closes; media element also advances 0.120587 s; 11 s process, exit 0 | Audible output still needs listening |

Raw feature-download-cancel, feature-certificate-leave, feature-beforeunload,
feature-web-audio evidence retained locally. No additional engine fix was
needed for these stronger probes. Probe receipts name engine commit eb55062;
the tested host additions are committed separately. Destination selection and
callback execution are never presented as native click acceptance.

#### Renderer-loss containment — 2026-10-03

| Feature | Chrome path | Window members it needs | Fixed how / measured result |
|---|---|---|---|
| Renderer crash/reload | SadTabHelper::PrimaryMainFrameRenderProcessGone → SadTab::Create → SadTabController::ReinstallInWebView → FindContentsWebView | A crash surface in the page native view; Room has no BrowserView or ContentsWebView. First-hit CreateSadTab logged | Patch 0009 nullable SadTab factory; Room-owned tabs get a Cocoa fallback owned by existing SadTabHelper, Chrome fallback windows retain default UI. Intentional Page.crash reaches crashed + overlay; reload reaches ready + overlay removed. 39 s process, exit 0 |

The actual discovery was a renderer Blink layout DCHECK during a diagnostic
--disable-gpu run, followed by a browser DCHECK on absent BrowserView. The
renderer defect is not claimed fixed; its failure no longer takes down the
Room host. No disable-gpu production switch was added. Patch 0009 is required
because SadTab::Create directly constructs the Views controller and neither
SadTab nor SadTabHelper has an existing replacement factory.

Baseline: nav 21.170 s; ten loaded pages quit 0.554 s, load1 18.00,
26 helpers / 0 left / 0 new crash reports, exit 0. Chapter 3 still needs
accessible crash status, retry interaction and reporting controls. The fallback
label is containment, not finished product UI. Public ObjC headers unchanged.


### 2026-10-03 — bounded UI compatibility: address bubbles

The new scope/results documents separate real Chrome UI from the original
18 crash-survival drives. Address save reproduced SIGSEGV in ShowSaveBubble
at the missing BrowserWindow lookup; its first repair still hit that lookup.
Second/final repair provides a Room-tab lookup hook, lazily owns Chrome's
AutofillBubbleHandlerImpl with the existing Views parent, and guards the
Chrome-only iOS promotion after accept. New UI patch0011 is separate from
the archived/deferred shutdown candidate0011. Original five patches and
public ObjC headers unchanged.

| Feature | Chrome path | Window members / ownership | Fixed how / measured result |
|---|---|---|---|
| Address save/update | AddressBubblesController → FindBrowserWindowWithWebContents → AutofillBubbleHandlerImpl → SaveAddressProfileView/UpdateAddressProfileView | Registered Room tab/window, GetAutofillBubbleHandler, stable Views anchor; handler owned by Room window | Tiny nullable lookup hook + optional promo guard, private anchor adapter. Save cancel/accept/owner-close each callback1; final-tab exit failed100s/143. Update with second tab passes11s/0 with one owned dialog and three exactly-once decisions. Persistent save/native focus not accepted. |
| Web USB/HID/Serial chooser | chrome::ShowDeviceChooserDialog → ChooserBubbleUiViewDelegate → DeviceChooserContentView::Cancel | Existing permission anchor/native parent | No new engine repair needed. Each10s/exit0; one visible owned dialog; USB/Serial NotFoundError, HID empty list. No hardware connected. |

Required new serial baseline nav15.105s, ten loaded pages quit2.933s,
28helpers/0left,0crashes,exit0. Full evidence and remaining subfeatures are in
roomcore-ui-compatibility-results.md. This checkpoint does not finish the Goal.


### 2026-10-03 — UI pass: local card save registration

| Feature | Chrome path / failure | Window requirement | Fix / verification |
|---|---|---|---|
| Synthetic local card save | SaveCardBubbleControllerImpl::DoShowBubble+156, null handler, SIGSEGV7s/exit139 | AutofillBubbleHandler registered on BrowserWindowInterface user-data host before any caller; Chrome payment path bypasses legacy getter | Initialize existing handler at Room window construction. One visible SaveCardBubble; cancel and accept each callback1,19s/exit0. Baseline nav17.169s,ten-page quit4.840s,26helpers0left0crashes. Final owner-close fixture fails third-bubble setup, so lifetime/persistence unaccepted. |

No new raw patch/public header or network-policy change. Full bounded outcomes, including actual3-row suggestions without accepted fill and password toolbar prerequisite, live in roomcore-ui-compatibility-results.md.


### 2026-10-03 — UI pass: extension device chooser

| Feature | Chrome path / failure | Window requirement | Fix / verification |
|---|---|---|---|
| Extension-origin USB request | chrome::ShowDeviceChooserDialog+992 → BrowserView::toolbar_button_provider+0, SIGSEGV6s/139 | Registered ToolbarButtonProvider and extension container; Room has neither | Patch0012 uses nullable provider lookup and existing no-container rejection. Real request now NotFoundError/No device selected,18s/0; no functional chooser claim. Baseline nav12.168s,ten-loaded-page quit0.694s,25helpers0left0crashes. |

Separate web USB owner cleanup11s/0 and local/loopback permission deny/allow/reuse/revoke19s/0 pass. All network fixture targets are127.0.0.1. Full qualification, identities and Chapter3 contracts: roomcore-ui-handoff.md and roomcore-ui-compatibility-results.md.
