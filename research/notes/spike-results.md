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
## RoomCore background hardening — laptop M1 Max (2026-10-03)

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

### Feature surface matrix after three crash fixes

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

### Final regression after network and Crashpad changes

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

### Stronger completion probes

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

### Regression after demand-CDM hook

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

### Additional surface found by live open10: FedCM

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

### Full repeat on committed FedCM engine 2a04498

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

### Extension tabs/windows lifecycle

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

### Explicit activation for extension action requests

Room Activate now matches Chromium's application-before-key-window ordering.
The 18 s extension run exits 0, with NSApp active and Room window key/main.
Tabs/windows lifecycle still passes. The action API now reaches toolbar
availability and returns "Browser window has no toolbar"; action UI is still
unsupported and must be supplied by Chapter 3. Source path:
NativeWidgetNSWindowBridge::SetVisibilityState and ActionOpenPopupFunction.
No patch/public ObjC change. Baseline nav 11.419 s; ten-page quit 0.549 s,
26 helpers / 0 left / 0 new crashes, exit 0.

### Completion probes on activation engine eb55062 — 2026-10-03

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
