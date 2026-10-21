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

## Phase 3.5 — Chrome's history and omnibox feed the palette; the history migration; the location bar (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug, 60 Hz)

Room.app on RoomCore (component build, Debug app, ad hoc), `window_main` true on every run, display 60 Hz (16.67 ms frames), load 3.4–9.3 stated per run. Every RoomCore number beside the Chapter 2 CEF one it replaces.

### The migration and launch time on the 50k state (`build/3.5/s50k`, `relaunch` spike)

State: `-RoomSidebarFixture 500 -RoomHistoryRows 50000` (the fixture's visits now within 85 days, deviation 2), made by one launch with `-RoomHistoryMigration NO` (27 s: the fixture's local import). Method: the 2.3/3.1a relaunch spike (process start → session running → the selected page loaded; the selected entry is `tab200.example.org`, an unresolvable host, so "loaded" is its error page) and the state open as the app logs it (B-42's line), three launches each, same state and engine directory, load 3.5–6.3.

| Launch | Process start → spike (session up) | → selected page loaded | State open (B-42) | Migration line |
|---|---|---|---|---|
| before ×3 (`-RoomHistoryMigration NO`) | 2.22 / 2.18 / 2.14 s | 4.14 / 3.88 / 3.88 s | 156.6 / 155.9 / 158.3 ms (quick_check) | skipped |
| **the import launch** | **6.01 s** | (16.02 s: the page finished before the spike began watching; not a number) | 158.6 ms | **50,000 local URLs → 50,000 URLs, 151,779 visits imported (0 expired) in 3.83 s** |
| after ×3 | 2.22 / 2.17 / 2.16 s | 3.98 / 3.92 / 3.92 s | 156.7 / 158.1 / 158.2 ms | "already imported (flag set); nothing read" |
| 3.1a B-42 (CEF, the same 50k state shape) | — | — | 151.0 / 150.3 / 153.0 ms after a clean quit | — |

The import costs one launch 3.8 s (awaited before the session's spikes; the page loads meanwhile) and nothing after: launch times before and after are equal within 0.1 s, and the state open is unchanged (the local tables stay until 3.9). Chrome's history then holds 50,000 URLs (`engine_history_rows`), the store's 50,000 rows stop growing (palette2: 50,000 before and after a navigation).

### Visits, ⌘Y, inline completion on Chrome's data (`palette2`, then the engine checks)

| Navigation | Chrome's history (`ProfileHistory.visits`) | CEF 2.4b (the store) |
|---|---|---|
| ⌘T "example.com" Enter | `["typed"]`, "Example Domain" | `[typed]` |
| `location.href` (script) | `["link"]` | `[link]` |
| `pushState('/pushed')`, then reload | `["link", "reload"]`: Chrome keeps the reload as a visit of its own (deviation 3) | `[link]` (reloads not recorded) |
| ⌘L DNS error page | not recorded | not recorded |
| ⌘T "room browser palette" | the Google results page, 1 visit | 1 visit |
| a navigation on RoomCore | in Chrome's history (`["typed"]`); the store's table 50,000 → 50,000 | the store grows |

The palette then: `exa` completes `mple.com` from Chrome's history (HistoryURL provider's typed host), `room35` finds the visit just made, ⌘Y lists 8 rows from Chrome's history (most recent first; deviation 4), `gi` completes `thub.com` and switches to the open GitHub tab (`has_tab_match` resolved to the entry, capture `research/screenshots/phase-3.5/roomcore-palette-history-inline-light.png`), `yt` ⇥ `lofi` keeps only YouTube's history, `>re` lists Reload and Reload without Cache. The `palette` spike (2.4a's semantics): every check as on CEF (19/19 in the tour).

### Keystroke to rows at 50k imported rows (`palettemeasure`, the 2.4b method)

Queries, fixture and probes as 2.4b/2.6a (14 queries, 120 keystrokes, first key 100 ms after ⌘T). "Local results" now includes Chrome's synchronous pass (`AutocompleteController::Start` from inside the keystroke: HistoryQuick's in-memory index and the typed-URL database); Chrome's asynchronous passes arrive after the keystroke's turn and re-rank with the highlight kept.

| Measure (ms) | RoomCore run 1 (load 3.5) | run 2 (4.9) | run 3 (5.8) | tour (`--groups palette`) | switch off (5.9) | CEF 2.6a | CEF 2.9 tour |
|---|---|---|---|---|---|---|---|
| Local results, all keys, median / **p95** | 3.16 / **10.93** | 3.12 / **14.76** | 3.03 / **12.73** | 3.09 / **12.25** | 2.99 / **10.30** | 2.57–2.58 / 6.47–6.71 | 7.9 (p95) |
| … first key of a query, median | 10.93 | 14.76 | 12.73 | — | 10.30 | 5.14–5.25 | — |
| **Later keys' whole turn, median / p95** | 4.90 / **11.49** | 4.96 / **12.14** | 4.60 / **10.43** | 5.34 / **9.21** | 4.85 / **9.27** | 4.90–5.13 / 9.6–10.4 | 11.5–11.6 |
| First key's whole turn, median | 20.48 | 24.69 | 20.80 | 20.57 | 20.35 | 17.9–18.9 | 17.9–18.8 |
| Providers phase, later / first key median | 2.12 / 9.75 | 2.12 / 12.59 | 2.08 / 9.92 | — | 1.97 / 8.59 | — | — |
| Chrome's async updates after a key: count; key → update median / p95 | 15; 4.95 / 6.20 | 15; 4.89 / 5.31 | 15; 4.58 / 7.76 | 15; 4.92 / 8.77 | 95; 4.91 / 20.34 | — | — |
| History rows per keystroke (mean); keystrokes completed inline | 2.8; 55 | 2.7; 55 | 2.8; 55 | — | 2.8; 72 | 4.7; 62 (2.4b) | — |
| Palette open: our code median; to next frame median / p95 | 1.11; 6.97 / 15.24 | 1.05; 4.56 / 13.74 | 1.06; 4.11 / 14.29 | 1.91; 6.10 / 15.24 | — | 2.50–2.75; 7.1–7.6 / 13.4–13.5 | 2.5–2.7; 5.5–6.0 / 13.9–14.1 |

The bound (ROADMAP 3.5 exit: keystroke to rows p95 under 16 ms at 50k imported rows) is met on both readings: local results p95 10.3–14.8 ms and the later keys' turn p95 9.2–12.1 ms (the 2.6a/2.9 reading of the turn; the first key runs on an efficiency core after idle, 2.6a). Against CEF the later keys are equal; the local results' p95 and the first key are 3–8 ms slower, all of it the first key's query (Chrome's `Start` costs 8.6–12.6 ms on a first key at E-core speed, ~2 ms on later keys). Not chased (inside the bound). With suggestions on, SearchProvider's verbatim match takes the default for query-like text and Chrome inlines on fewer keys (55 vs 72 off; B-65).

### Suggestions: on and off (`suggestcheck` through the logging server; `scripts/netlog-check.sh`)

`-RoomSuggestProxy 127.0.0.1:8771` now also points the engine's default search engine's suggestion URL at `research/spikes/phase-2.8/server.py`, which answers `/complete/search?q=` with three OpenSearch suggestions and logs each request.

| Check | RoomCore | CEF (2.4b, 2.9) |
|---|---|---|
| Switch on: requests while typing 3 queries (47 keys, 60 ms apart, 1.2 s pause each) | **34** `GET /complete/search?client=room&q=…` from Chrome's network stack (SearchProvider polls every ~100 ms: B-64); every query's suggestions shown ("swift concurrency one/two/three", …) | 3 `CONNECT suggestqueries.google.com` (one per pause) |
| Switch off: requests while typing | **0** (server log empty); the engine was asked for `historyQuick+historyURL+bookmark+shortcuts+openTab` only | 0 |
| `netlog-check.sh` (`ROOM_NETCHECK_SUGGESTIONS_OFF=1`: launch, browse, then three queries typed in the palette with the switch off) | Room's own code: none; engine net-log: 127.0.0.1 and localhost page traffic only (6 URL requests, browse phase), **0 requests in the typing phase**, 0 hosts not page traffic | 2.8b: 0 Room requests; engine requests named |

### The location bar (task 4)

| Path | Result |
|---|---|
| `IDC_FOCUS_LOCATION` through `+[AppController sharedController]` (patch 0013: `RoomAppController`) `-commandDispatch:` | `RoomLocationBar: FocusLocation (user initiated 1) to the host` → `RoomBrowser: focus the location bar asked; active page yes` → the page's delegate → the palette in edit mode on the page's URL (`requests=1 palette_open=true mode=edit(…)`). First run: 0 requests, because `BrowserCommandController` returns before `FocusLocationBar` while `IsLocationBarVisible()` (a stub) says false: made real (true) |
| The same command on the window's Browser (`chrome::ExecuteCommand`) | executed, 1 request, the palette open |
| ⌘L typed in a page (`keys` spike, active layout Colemak) | reserved for the host (2 `isReservedKeyEvent` calls per layout), `⌘L addressFocus=true`; Chrome never sees it (3.2b's routing, unchanged) |
| The chip, `https://example.com/` | host `securityState` secure; Chrome's `LocationBarModel` SECURE |
| The chip, `http://http.badssl.com/` | host insecure; `LocationBarModel` WARNING |
| Does Chrome code ask the model by itself? | Once per session so far, at launch, before any spike (`RoomLocationBar: GetLocationBarModel asked; security level 3` for the selected https page); the model is the Browser's own (`BrowserWindowFeatures::location_bar_model()`) |

### Baseline after the last engine change (`build/baseline/3.5-final`)

nav passed (16.4 s), ten-page quits **0.276 / 0.224 / 0.247 s** (load 9.7–12.7), 0 helpers left, 0 crash reports; stub hits: none (39 stubs). The first attempt in this session (`3.5-a`) stopped at run 2 on stackoverflow.com's Cloudflare challenge still loading (the external corpus); `3.5-b` passed (0.230 / 0.234 / 0.261 s) before the last engine change.

### The grand tour's palette section (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups palette light`, `build/grand-tour/20261005-130538-roomcore`, 2.5 min)

**78 passed, 0 failed** (3.3a's run of the same group: 62 / 7): palette 19/19, palette2 26/26 (nine new engine checks: the store does not grow, the visit in Chrome's history, the palette finds it, ⌘Y, `IDC_FOCUS_LOCATION`, the chip ×2, Chrome's pushState visit), suggeston 10/10 (Chrome's requests for each of the three queries, suggestion rows shown), suggestoff 10/10, palettemeasure 13/13 (Chrome's history ≥ 50,000 rows). The first run of the session was 69 / 2, both the checks' own faults (spike keys with spaces the tour parser does not read; an exact 50,000 where the tour's own visits add 18), fixed in the checks and the spike's key names.

## Phase 3.6a — Chrome extensions: the installed list and management, Web Store installs through Room's consent sheet, update checks on the host's timer (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Room.app on RoomCore (component build `out/dev`, 24 patches, `room_enable_spikes=true`), Debug, 60 Hz, `window_main` true in every run, throwaway `-RoomStateDirectory`/`-RoomEngineDirectory` under `/tmp/room-3.6a`; load 3.7–10 except where stated. Spike outputs and net-logs in `build/evidence-3.6a`; captures in `research/screenshots/phase-3.6a`.

### Task 1: the unpacked fixture through `ProfileExtensions` (`-RoomSpike extensions`, final engine)

| Check | Result |
|---|---|
| Load unpacked (`research/spikes/phase-3.6/extension`, `UnpackedInstaller`) | id `dibedkfpfkdkkcbjmblmfdbjdhdnlgkp` in 32 ms (earlier runs 6–7 ms); developer mode turned on |
| In `installed` | "Room 3.6 fixture" 1.0, enabled, unpacked, icon16 16×16 pt and icon32 32×32 pt, options `options.html`, action "Room fixture" with its 16 pt icon and a popup, pinned at install (Chrome's "Pin new extensions to Toolbar" is on by default), permissions "Read and change all your data on all websites", hosts `<all_urls>` |
| Content script and `chrome.tabs` | on two Today pages (example.com, example.org) the content script ran; the worker's `chrome.tabs.query({})` saw **2 tabs** (the two Today pages' URLs) and `chrome.windows.getAll()` **1 window**; the host's Today pages 2 (Phase 1.4 on CEF: `tabs.query` `[]`, 0 windows) |
| Badge | the worker's `setBadgeText`: defaults "2", the asking page "T2" (per tab id), colour #2f7de1; 7 action updates reached the delegate, the last per page |
| Disable, enable, reload, pin | each reflected in `installed` within 5 s; pin toggled and back |
| `chrome://extensions` | renders in a Today tab ("Extensions", developer mode on, the fixture's card); a real click on its switch disabled the extension in `ExtensionRegistrar` (Room's list followed), a second click enabled it (`chrome-extensions.png`) |
| Options page | `chrome-extension://…/options.html` opened as a Today tab; its script wrote `chrome.storage.local` ("storage written") |
| Settings ▸ Extensions | the fixture listed with Options, Reload, Unpin, Remove… and its switch (`settings-extensions.png`) |
| Uninstall | Room's sheet "Remove “Room 3.6 fixture”?" (`fixture-uninstall-sheet.png`); Cancel kept it (`removed=false`), Remove removed it |

### Task 2: three Chrome Web Store installs (`-RoomSpike webstore`, `build/evidence-3.6a/ws1.txt`)

The unbranded build's user agent: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36`; client-hint brands `Not A(Brand` 99, `Chromium` 154 (no "Google Chrome"; nothing spoofed). On a fresh profile from this (EU) address Google first shows its cookie consent page ("Before you continue", consent.google.com); the run clicked **Reject all** (the privacy-preserving answer) and the store page followed. The store page shows a "Switch to Chrome?" banner and "Switch to Chrome to install extensions and themes · Install Chrome" text, and the **"Add to Chrome" button is there and works**: `webstorePrivate.beginInstallWithManifest3` reaches the install prompt, which patch 0024 hands to Room's sheet.

| Extension | Store page → sheet | Installed (click to `installed`) | On a page | Service worker (`chrome://serviceworker-internals`) | Uninstall |
|---|---|---|---|---|---|
| uBlock Origin Lite (`ddkjiahejlhfcafbddmgiahcphecmpfh`) | "Add to Chrome" → "Add "uBlock Origin Lite"?", It can: • Read and change all your data on all websites (`webstore-install-sheet.png`, the final run) | 2026.930.1227 in 7.3 s (7.1 s in the second run); options `dashboard.html`, action with popup | example.com: badge "2"; an ad script added to the page (`pagead2.googlesyndication.com/…/adsbygoogle.js`) never reached the network stack (0 net-log events for the host, `ws2`), the page got uBOL's stand-in script | ACTIVATED, RUNNING | Room's sheet, removed |
| 1Password (`aeblfdkhhhdcdjpifhhbdiojplfjncoa`) | six lines: all your data on all websites, notifications, downloads, apps/extensions/themes, native applications, privacy-related settings | 8.12.38.34 in 7.5 s; opened its welcome tab (`chrome.tabs.create` → a Today tab) | action "1Password", enabled; no page popup set on example.com; nothing injected on a page without a form; sign-in not tried (by hand) | ACTIVATED, RUNNING | removed |
| Dark Reader (`eimadpbcbfnmbkopoojfekhnkhdbieeh`) | one line (all websites) | 4.9.133 in 6.9 s (6.4, 6.5, 6.6 s in other runs); the store button became "Remove from Chrome" | example.com dark: 10 `style.darkreader` elements, body and html background rgb(24, 26, 27) (`dark-reader-example-com.png`) | ACTIVATED, RUNNING | removed |

The final run on the final engine (`ws3`) repeated all three: installed in 7.5 / 7.4 / 6.6 s (1Password now 8.12.40.31: the store had a new version between runs), the same effects, three service workers RUNNING, three uninstalls with consent, browser requests `webstore_install_helper` 3 and navigations only (no `update_client`), and `~/Applications/Chromium Apps.localized` untouched. Every sheet answered on the prompt's `DoneCallback` (`ACCEPTED`); no Chrome install dialog and no post-install bubble appeared. Settings ▸ Extensions listed the three with their versions, enabled (`settings-extensions-webstore.png`).

**Net-log of the installs by traffic annotation** (`--log-net-log`, capture mode Everything; requests made by the browser process are "browser", by a page or an extension "page"):

| Annotation | Count | What |
|---|---|---|
| `webstore_install_helper` (browser) | 1 per install | the extension's icon from the store's data (lh3.googleusercontent.com) for the sheet |
| `webstore_installer` (download) | 1 per install | `GET clients2.google.com/service/update2/crx?…` (redirected to clients2.googleusercontent.com), the CRX |
| `navigation_url_loader` (browser) | the store page, consent page, example.com, welcome pages | navigations |
| `blink_resource_loader`, `favicon_loader` (page) | 244 over three installs | the store page's own scripts, fonts, images, logging (play.google.com/log, googletagmanager), and the extensions' own requests (1Password: my.1password.com, watchtower.1password.com, client-log-forwarder.1password.com; Dark Reader: darkreader.org, count.darkreader.app, paddle) |
| `update_client` (browser) | **1 per uninstall in the first run → 0** | Chrome's uninstall ping for Web Store extensions (`POST update.googleapis.com/service/update2/json`, event uninstall): telemetry, not asked for; turned off (update client config without a ping URL); the second run (`ws2`, install + uninstall of uBO Lite): browser requests `webstore_install_helper` 1, `webstore_installer` 1, navigations 4, no `update_client` |

### Task 3: update checks only when the host asks

| Run | Window | Engine requests | Notes |
|---|---|---|---|
| No extension (`ROOM_NETCHECK_IDLE=600 scripts/netlog-check.sh`, fresh state, first-run card shown) | launch + 600 s idle + browse + quit | **0** | Room's own code 0 (main process 0 bytes); page traffic 127.0.0.1 2, localhost 4. 3.1b-2's number holds with the extension system created |
| Dark Reader installed, timer not due (seed state, `extupdate -RoomExtensionsIdle 600 -RoomExtensionsNoCheck YES`) | launch + 600 s idle | **0** | Chrome's own startup check (5 s after launch) was refused at the gate (1 logged); the timer's next fire 2026-10-06 11:32 (24 h after the install); Dark Reader's own service worker fetched `darkreader.org/blog/posts.json` once (initiator the extension: the extension's request, not the engine's) |
| One host check (`extupdate`, `checkForUpdatesNow`) | 30 s idle, the check, 20 s | **1**: `update_client` `POST update.googleapis.com/service/update2/json` | 1 extension asked, 0 updates found (4.9.133 is current), 81 ms; so no CRX fetch. Web Store extensions update through update_client (the JSON protocol), the CDM's annotation; `extension_manifest_fetcher`/`extension_crx_fetcher` (the XML `ExtensionDownloader`) did not appear |

How Chrome's own schedule is held: `ExtensionUpdater` keeps its five-hour schedule and its startup check, and every check it starts on its own (and an extension's `runtime.requestUpdateCheck`) reaches `IsBackgroundUpdateAllowed`, which patch 0025 answers false outside the host's call; `ScopedSkipScheduledCheckForTest` was not used. The host's timer (`ExtensionUpdateTimer`, Chrome package) fires once a day while an extension is installed, keeps the last check in Settings (`extensionsLastUpdateCheck`) so a relaunch inside the day does not check, starts the day at the first install and disarms at the last uninstall (unit tests).

### Baseline after the last engine change (`build/baseline/3.6a-final2`)

nav passed 11.6 s; ten-page quits **0.374 / 0.338 / 0.464 s**, 0 helpers left, 0 crash reports, exit 0 (load 20: DaisyDisk was scanning the disk, the user's); stub hits none (39 stubs); the first attempt (`3.6a-final`) stopped on stackoverflow.com's Cloudflare challenge in run 2 (external corpus; run 1 0.273 s). Earlier baseline after the first engine change (`3.6a-1`): nav 16.5 s, quits 0.310 / 0.246 / 0.262 s. Series 24, "0 applied, 24 already".

Found on the way: an extension uninstall made Chrome's `AppShortcutManager` create `~/Applications/Chromium Apps.localized` with an icon (14:05, the first uninstall; macOS logged a simulated `EXC_GUARD` fault from IconServices for its icon each time, four `ExcUserFault_Room` reports, non-fatal); turned off (`SuppressShortcutsForTesting`); the final run's uninstall left the folder untouched and logged no fault. The folder stays for the user to delete.

## Phase 3.6b — action popups from the header, action.openPopup, extension commands, side panels unsupported, the Phase 3.6 exit (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug, 60 Hz)

Room.app on RoomCore (component build `out/dev`, 24 patches, `room_enable_spikes=true`), Debug, 60 Hz; throwaway `-RoomStateDirectory`/`-RoomEngineDirectory` under `/tmp/room-3.6b`; load 3.9–10. Outputs in `build/evidence-3.6b` (`pop1`, `pop6`, `pop7`, `ws1`, `ws2`, the two embryo drives); captures in `research/screenshots/phase-3.6b`. Conditions: a system dialog (UserNotificationCenter) was frontmost from ~16:12 to ~16:40, so runs `pop2`–`pop6` and `ws1`/`ws2` had the application inactive (`window_main` false); `pop1` (16:11) and `pop7` (16:45) were active. Window captures (`CGWindowListCreateImage`) show no engine pixels on this machine (the card and the popover's page are empty glass in every window capture, 3.6a's included); the popup pages are captured from the page itself (`captureViewport`, `*-page.png`).

### How it is built

| Piece | Chrome's | Room's |
|---|---|---|
| The window's extension UI | `ExtensionsContainer` user data on the `BrowserWindowInterface` (Views `ExtensionsToolbarDesktop`, `WebUIBrowserWindow`) | `room/core/room_extension_popups.mm`: a container registered with `ui::ScopedUnownedUserData` on every Room Browser; `HideActivePopup`, `ShowToolbarActionPopupForAPICall`, `HasAnyExtensions` real; `GetActionForId`, `CloseExtensionsMenuIfOpen`, `ToggleExtensionsMenu` log their first hit (none hit in any run) |
| `action.openPopup` gate | `WindowFeatureController kFeatureToolbar` + `BrowserWindow::IsToolbarVisible()` | `RoomBrowserWindow::IsToolbarVisible` real (true unless headless); stubs 39 → 38 |
| A click | `ExtensionActionViewModel::ExecuteUserAction` → `ExtensionActionRunner::RunAction(grant_tab_permissions)` → `CreatePopupHost` → `ExtensionPopup` (Views bubble) | the same runner call, then `ExtensionViewHostFactory::CreatePopupHost` with Room's `ExtensionView`; the host contents' page reaches the host at `DocumentOnLoadCompletedInPrimaryMainFrame` (`ExtensionPopup::ShowBubble`'s moment), shown in an `NSPopover` (`.transient`, no animation) on the header's button, then `WebContents::Focus` |
| Size | `WebView::EnableSizingFromWebContents(25×25, 800×600)` | `RenderWidgetHostView::EnableAutoResize` on the primary main frame (`RenderFrameCreated`, `RenderFrameHostChanged`); the first build compared `IsInPrimaryMainFrame()`, false at frame creation: no resize until fixed |
| Close | widget deactivation, `window.close()`/Esc (close handler), tab change, unload | the popover's transient close → `ExtensionsCenter.popoverDidClose` → `closePopup` → the host destroyed (posted); the engine's closes → `popupDidClose` → the popover |
| Commands | `ExtensionKeybindingRegistryViews` (only with a `BrowserView` focus manager) | an `ExtensionKeybindingRegistry` per Room Browser shaped like `ExtensionKeybindingRegistryAndroid` (accelerator sets, `_execute_action` handled itself); `RoomBrowserWindow::PreHandleKeyboardEvent` asks it before the host's reserved keys (Chrome's extension accelerators are high priority). No extension path sends `IDC_*` to the app controller in M154 (`commandDispatch:` callers are menu items only), so `RoomAppController` is unchanged |
| Side panel | `SidePanelUI::Show` from `OpenGlobalExtensionSidePanel` | none: `SidePanelService` options held disabled (an observer); see task 5 |

### Task 4: the fixture through the header (`-RoomSpike extpopup`, `pop7` active, final engine)

| Check | Result |
|---|---|
| Header | one button for the fixture (pinned at install), badge "T1" from the page's action (the content script's tab count), tooltip "Room fixture" |
| Click → popup | popover on the button, its page "popup open"; **77.3 ms** click → loaded (then 26.6, 35.6 ms; earlier runs 64–86 ms first, 26–56 ms after); popover window key, anchored on the button |
| Resize by the page | 264×65 at load (auto-resize of the 240 px body), **384×285** after the page's own script grew it 400 ms later (one `didResizeTo`), popover followed |
| Focus loss | a click on the page (posted mouse events): the popover closed itself, `popoverDidClose` told the engine, the `ExtensionViewHost` and its page were destroyed (page state `closed`), nothing left in the center |
| Esc | three times: Esc in the popup page → `ExtensionViewHost` closed (`IsEscapeInPopup`) → `popupDidClose` → popover closed by the engine, page destroyed |
| `action.openPopup()` | from the service worker (a page event → content script → worker): popover on the fixture's button in **43 ms**, the worker's promise resolved ("opened"); with the application inactive Chrome refuses it ("Could not find an active browser window": `pop2`–`pop6`), Chrome's own rule |
| `_execute_action` (⇧⌘Y) | real key events to the page: popover in **37 ms**; ⇧⌘Y again inside the popup closed it (as Chrome's button toggles) |
| Named command (⇧⌘U) | `commands.onCommand` in the worker ("room-named"), which wrote its result into the action's title |
| Capture | `fixture-popup-over-header.png` (popover glass over the header with the badge), `fixture-popup-page.png` (384×285, "popup grown") |
| Embryo `ui-extension-popup` | unchanged: Chrome's Views `ExtensionPopup` on the bubble anchor 66×80 → 374×266, closes with its owner tab |
| Embryo `ui-extension-device` | still `NotFoundError` ("No device selected"): the extension-origin chooser asks `ToolbarButtonProvider::From(browser)->GetExtensionsContainerViews()` (a Views container), not `ExtensionsContainer`, so Room's container does not open it; patch 0012's safe rejection stays (series 24 unchanged). From a Room popup page `FindBrowserWithTab` finds no Browser (a popup is not a tab) and Chrome returns without a chooser. What it needs: an `ExtensionsContainerViews` (Views) or a hook routing extension-origin choosers through the web-origin path anchored on the bubble anchor |

### Task 5: side panels (`pop1`, then `pop6`/`pop7`)

| Run | `chrome.sidePanel.open({tabId})` from the named command's handler (a user gesture) |
|---|---|
| `pop1` (first engine) | the browser process died (Crashpad dump, no CHECK in the log): `SidePanelService::OpenSidePanelForTab` → `side_panel_util::OpenGlobalExtensionSidePanel` → `SidePanelUI::Show` on a null `SidePanelUI` (`BrowserWindowFeatures` makes one only with a `BrowserView` or a WebUI window) |
| `pop6`, `pop7` (guard) | rejected: **"No active side panel for tabId: 1846071027"**; no crash, no CHECK; the run went on |

The guard is a seam, not a patch: every extension's options in `SidePanelService` are set disabled at load and an extension's `setOptions({enabled: true})` is undone in the observer before the call returns (the same entry is updated), so `open()` and the action's open-panel-on-click find no active panel. The rejection text is Chrome's, not "unsupported" (deviation 3).

### The exit: three Web Store extensions with their popups (`-RoomSpike webstore -RoomWebstorePopups YES`, `ws2`, app inactive)

| Extension | Installed (click → `installed`) | Popup from the header (click → loaded, three runs) | Popup | Scripts / worker / badge | Uninstall |
|---|---|---|---|---|---|
| uBlock Origin Lite 2026.930.1227 | 7.0 s (7.1 s in `ws1`) | 74.2, 41.7, 42.0 ms, **median 42.0 ms** (`ws1`: 154.9, 46.4, 50.3) | 273×374, "uBlock Origin Lite \| example.com filtering mode optimal …" (`popup-ddkj…-page.png`) | ad script blocked, worker RUNNING, badge "2" | with consent |
| 1Password 8.12.40.31 | 7.0 s | **no popup**: the extension clears its popup for the tab (`action` on example.com: popup false) until it finds its desktop app or an account; the click delivered `action.onClicked` (its handler tried native messaging, "Specified native messaging host not found", then its welcome-page flow) | — (by hand with an account; B-69) | worker RUNNING, welcome tab at install | with consent |
| Dark Reader 4.9.133 | 6.4 s (6.5 s) | 55.5, 35.8, 37.5 ms, **median 37.5 ms** (`ws1`: 64.9, 44.8, 36.4) | 276×580, "Dark Reader settings … example.com …" (`popup-eima…-page.png`) | example.com dark (rgb 24, 26, 27), worker RUNNING | with consent |

The header showed the three buttons in the pinned order with uBO Lite's badge; every popup closed with Esc (engine-side) and its page was destroyed. Requests: the store installs repeated (the user's), nothing new.

### Baseline after the last engine change (`build/baseline/3.6b-final`, embryo host)

nav passed 11.4 s; ten-page quits **0.335 / 0.296 / 0.305 s** (load 10–17), 0 helpers left, 0 crash reports. Stub hits: none of the 38 `RoomBrowserWindow` stubs, none of the container's three logged members; `RoomAppController`: `tryToTerminateApplication`, `didEndMainMessageLoop` (implemented). After the first engine change (`3.6b-1`): nav 17.4 s, quits 0.284 / 0.249 / 0.244 s. Series 24, "0 applied, 24 already".

## Phase 3.7a — passwords and autofill through Chrome's Views bubbles anchored on Room's chrome (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug, mock keychain)

Room.app on RoomCore (component build `out/dev`, series 24, Debug Swift app, ad hoc, `--use-mock-keychain` decided by `RoomApplication`) through `scripts/passwords-autofill.sh` (`App/Sources/Debug/PasswordSpikes.swift`: `-RoomSpike passwords -RoomPasswordsPhase save`, the relaunch `… fill`, then `-RoomSpike autofill`, all on one throwaway state and engine directory; window 1200 × 800 pt centred, 60 Hz; fixtures `research/spikes/phase-3.7` on `http://127.0.0.1:8772` and `http://localhost:8772` (two sites) and `https://127.0.0.1:8773` (self-signed, its SPKI hash passed as `--ignore-certificate-errors-spki-list`: the card form and the sign-up page)); the embryo host through `scripts/roomcore-features.sh <drive>`. Evidence: `build/evidence-3.7a/` (`pa-1` before the leak-check fix, `pa-3` the complete run with Room's window key, `pa-final`/`pa-final2` the final build with another application frontmost). Captures: `research/screenshots/phase-3.7a/` (screen captures; the stale "Room quit unexpectedly" dialogs are the user's and sit over the page area in several).

Input is real events only: typing and clicks on the page's view (`PageDriver`), Return to Chrome's bubble (its default button: Save, Update; the bubble made key first; the click fallback was never needed), Down and Return on the page for the suggestion popups.

### Bubbles and popups

| Bubble | Chrome source | Anchor | Run (`pa-3`; times from the submit click) |
|---|---|---|---|
| Save password, site A (127.0.0.1) | `PasswordSaveUpdateView` via `ManagePasswordsUIController` → `PasswordBubbleViewBase::ShowBubble` → `ToolbarButtonProvider::GetBubbleAnchor` | site button (16 × 28 pt at 157,42); bubble 320 × 386 at 62,70: its top edge at the button's bottom (gap 0), spanning the button | shown **609 ms** after the submit (the navigation commits first; final build 555–679 ms), Return → saved, the page "Signed in as alice" (`phase-3.7a-save-bubble-a.png`) |
| Save password, site B (localhost) | same | same | **469 ms** (455–466), Return → saved (`…-save-bubble-b.png`) |
| Update password (site A, new password) | `PasswordSaveUpdateView` (pending update) | same; 320 × 394 | **552 ms** (457–460), Return → updated (`…-update-bubble-a.png`) |
| Save password, sign-up page (`autocomplete=new-password`) | same | same | **48 ms** (51–53: no navigation wait), Return → saved |
| Password suggestions, both sites after the relaunch | `PopupViewViews` (`ChromeAutofillClient::ShowAutofillSuggestions`) | the username field: 1 pt below its bottom edge, 95 pt right of its left edge (CEF's 1.4 popup sat at the same 95 pt); 225 × 119 | shown **42 / 24 ms** after the click; Down + Return: username and password filled (read from the DOM: `alice`/matches, `bob`/matches), popup closed; the sign-in completes ("Signed in as alice", "… bob"); no second save offer (`…-fill-popup-a/b.png`) |
| Password generation | `PasswordGenerationPopupViewViews` | — | **not offered**: none within 4 s on the new-password field (an origin with no saved logins); M154 offers generation only with password Sync (`PasswordFeatureManagerImpl::IsGenerationEnabled`); B-72 |
| Save address | `SaveAddressProfileView` (`AddressBubblesController`, `AutofillBubbleHandlerImpl`) | site button; 320 × 367 at 157,70 (left edge at the button, top at its bottom) | **23 ms** (25–30), Return → saved (`…-address-save-bubble.png`) |
| Update address (the same address with a phone) | `UpdateAddressProfileView` | same; 320 × 180 | **26 ms** (27–28), Return → the profile gains the phone (`…-address-update-bubble.png`) |
| Address suggestions | `PopupViewViews` | the name field, 1 pt below, 95 pt right; 223 × 119 | **24 ms**; Down + Return filled every field: `Room Fixture`, `1600 Amphitheatre Parkway`, `Mountain View`, `CA`, `94043`, country `US`, phone `16502530000`, `room.fixture@example.com` (`…-address-popup.png`) |
| — Esc | | | the popup closed, nothing filled (name empty) |
| — a window move (+60, −40 pt) | | | first run (`pa-2`): the popup **stayed** at 461,173 while the field moved to 426,178 (Chrome closes it on its browser widget's bounds change; a Room window has none); after the fix (`RoomBrowserWindow::HideAutofillSuggestions` on move/resize): **closed** (`pa-3`) |
| Save card (local) | `SaveCardBubbleViews` (`SaveCardBubbleControllerImpl::OfferLocalSave`) | site button; 320 × 338 at 157,70 | **25 ms** (24–34), Return → saved (`…-card-save-bubble.png`); page security `secure` with the SPKI flag |
| Card suggestions | `PopupViewViews` | the number field, 1 pt below, 95 pt right; 237 × 119 | Down + Return filled name, `4111111111111111`, `12`, `2030` and the stored CVC `123`; no CVC or re-authentication prompt, no other Chrome window (`…-card-popup.png`) |

Every bubble asked the host once for the anchor (`anchor_queries=1`). With another application frontmost (`pa-final`, `pa-final2`: Dia and a UserNotificationCenter dialog in front, Room inactive, no key window) the bubbles still showed at the same place and Return still accepted them; the suggestion popups did not open (Chrome shows them only for a focused page), so their results are `pa-3`'s, where Room's window was key. Provider members beyond the anchor: no first hit in any run; the one window stub the bubbles hit is `GetNativeTheme` (returns null; the bubbles draw with their own theme).

The stores after the run (sqlite3 on copies of the profile's files): `Login Data` `logins`: `http://127.0.0.1:8772/login.html` alice, `http://localhost:8772/login.html` bob, `https://127.0.0.1:8773/signup.html` carol (each password 19 bytes encrypted with the mock-keychain key); `Web Data`: one address (name, street, city, state, ZIP, country, email, and the phone from the update), one card (Room Fixture, 12/2030, number 35 bytes encrypted). `chrome://password-manager/passwords` loads in a Room tab ("Password Manager") and lists both sites (127.0.0.1 and localhost found in its text; `phase-3.7a-password-manager.png`).

Host while a bubble is up: the update bubble left Room's window key (`key_window=room`) and the page's view first responder. A synthetic ⌘T did not open the palette, but it did not open it after the bubble closed either (the engine logged ⌘T as reserved; the 3.2b keys runs found menu dispatch of synthetic ⌘-keys depends on the active layout, which on this Mac is not ABC): inconclusive, by hand.

### Network (`--log-net-log`, default capture mode, `scripts/lib/netlog-summary.py`, page hosts 127.0.0.1 and localhost)

| Run | Engine requests beyond the fixtures |
|---|---|
| `pa-1` (before the fix), each passwords launch | **1**: `POST passwordsleakcheck-pa.googleapis.com/v1/leaks:lookupSingle` (`lookup_single_password_leak`, no account needed) |
| `pa-3`, `pa-final`, `pa-final2`, every launch (passwords save 15 page requests, fill 9–11, autofill 16–20) | **0**; nothing to `autofill` or `clients*.google.com` hosts |

The fix: `kPasswordLeakDetectionEnabled` defaults to false for Room profiles (`room_network_policy.cc`).

### The embryo drives (`build/evidence-3.7a/feature-*`), beside PR #1

| Drive | PR #1 (`roomcore-ui-compatibility-results.md`) | 3.7a |
|---|---|---|
| `ui-passwords` | presentation returned at the missing `ToolbarButtonProvider`, no bubble (17 s, exit 0) | first run: the forced presentation now reached `CreateBubble` and hit Chrome's `NOTREACHED` for the inactive model state (exit 134: the drive shows a bubble without a submitted form, which Chrome never does). The probe now reads the provider and the model state: **provider present, model inactive, no bubble**, 7 s, exit 0. The save/update flow is the `passwords` spike above |
| `autofill-save` | real `SaveAddressProfileView`, decisions through callbacks, then **hung after the last tab closed** (100 s, exit 143) | the same decisions (cancel, accept: one callback each; owner close), **exit 0 in 10 s**, no hang |
| `autofill-update` | real `UpdateAddressProfileView`, decisions, 11 s exit 0 | the same, 9 s exit 0 |
| `ui-address-suggestions` | 3 rows, **no fill** (CDP `keyDown` is `kKeyDown`; the popup listens for `kRawKeyDown`) | 3 rows, still no fill with CDP `rawKeyDown` (11 s, exit 1): CDP's key events do not reach the popup's handlers either way; real `NSEvent`s fill (the `autofill` spike) |
| `ui-card-save` | cancel and accept with one callback each; the third (owner-close) bubble never visible | the same (10 s, exit 1): the drive's third local-save offer of the same card in one tab shows no bubble; the card save itself passes in the `autofill` spike |

### The baseline after the last engine change (`build/baseline/3.7a-final`, embryo host)

nav passed 19.7 s; ten-page quits **0.256 / 0.251 / 0.299 s** (load 7.9 / 10.3 / 11.1), 0 helpers left, 0 crash reports; stub hits none (38 window stubs, the provider's members unhit). The two baselines before it (`3.7a-1` after the provider, `3.7a-2` after the leak/popup fixes): nav 18.6 / 19.2 s, quits 0.318 / 0.481 / 0.252 and 0.282 / 0.250 / 0.254 s, 0 helpers, 0 crash reports.

## Phase 3.7b — session history per entry, host-driven discarding with the engine's blockers, memory pressure, translate and spellcheck (2026-10-05, Mac mini M4, 24 GB, RoomCore, Debug)

Room.app on RoomCore (component build `out/dev`, tag 154.0.8037.58, series 24 unchanged, ad hoc, mock keychain), throwaway state and engine directories per run under `build/evidence-3.7b/`; fixtures `research/spikes/phase-3.7/{step,form,tone,pip}.html` and `phase-2.6/capture.html` served by `python3 -m http.server 8774 -d research/spikes` (`scripts/session-lifecycle.sh`). The Claude desktop app was frontmost for part of the session (`window_main: false` in the session build and check runs; nothing in them depends on activation). Load 3.5–6.

### How it is built (seams, no patch)

| Piece | Chromium | Room |
|---|---|---|
| a page's history as data | `ContentSerializedNavigationBuilder::FromNavigationEntry` → `SerializedNavigationEntry::WriteToPickle` (63 KiB page state per entry at most, `gMaxPersistNavigationCount` = 6 entries each side, as Chrome's session commands) | `RoomWebContents.navigationState`: a `base::Pickle` with a header (magic, format 1, the Chromium version, the selected index, the count) |
| restoring it | `ReadFromPickle` → `ToNavigationEntries` → `NavigationController::Restore(selected, kRestored)` before the page joins its strip (Chrome's tab-restore order), then `LoadIfNecessary` | `-restoreNavigationState:` from `RoomCoreProfile.makeWebContents`; `-reload` is `LoadIfNecessary` when the controller needs a reload |
| changes | `NavigationEntryCommitted`, `NavigationListPruned`, `NavigationEntryChanged`, `NavigationEntriesDeleted` | `-webContentsDidChangeNavigationState:` once per run-loop turn → the tab controller stores the state in the entry (`entry.navigationState`, schema v5) through the 2.1 debounced single transaction, quietly (no sidebar observer); `unload` stores the page's state once more before it closes |
| why not to discard | `DiscardEligibilityPolicy::CanDiscard(PROACTIVE, ignore_recent_visibility=true)` on the main thread (PM lives there in M154: `PerformanceManager::GetGraph()`), `CannotDiscardReason` | `RoomWebContents.discardBlockers` → `WebContents.discardBlockers`; the 2.3 policy asks it for every page its own rules would discard |
| Chrome never discards a Room page | `TabLifecycleUnitExternal::SetAutoDiscardable(false)` → `kExtensionProtected` (protected); `PageDiscardingHelper::DiscardAPage(URGENT)` skips protected pages | set when a page joins a strip and on a discard's replacement |
| memory pressure | `base::MemoryPressureListener` (registration tag `kBackgroundTabLoadingPolicy`: the enum is closed) | `-roomApplication:didChangeMemoryPressure:` → `EngineApplicationDelegate` → the tab controller (the host's own `DISPATCH_MEMORYPRESSURE` source only on CEF) |
| the translate bubble's later steps | `TranslateBubbleController::ShowTranslateBubble` (every Browser has one, `BrowserWindowFeatures::Init`) | `RoomBrowserWindow::ShowTranslateBubble` real (stubs 38 → 37), anchored on the window's bubble anchor; the offer stays the host's toast |

### Task 3: the session spike (`scripts/session-lifecycle.sh`, `build/evidence-3.7b/s1`, `c1`, `c2`)

Ten Today tabs on the ten typical sites, each navigated twice (`step.html?e=<i>&s=1`, then `s=2`, as links), the last one selected; then a clean quit and a relaunch on the same directories.

| | Result |
|---|---|
| state per entry after the real page alone | **868 – 10,904 B, median 3,508 B** (Hacker News 868, Stack Overflow 980, GitHub 1,728, Apple 2,264, NYT 3,056, YouTube 3,508, BBC 4,288, Wikipedia 5,300, Reddit 6,340, The Verge 10,904); sum 39.2 KB |
| after the two steps (three entries) | 2,652 – 8,156 B, median 5,336 B; sum 51.4 KB (a real page's own state is rewritten by the renderer as it settles: BBC 4,288 → 3,296) |
| stored in the entries 1 s after the last step | 10 of 10 |
| write cost, 10 entries (`RoomStore.flush()`: diff, one transaction, JSON snapshot; 20 each) | state change **0.88 ms** median / 4.02 p95; a title change 0.72 / 1.07 ms; `Room.sqlite` 233 KB, snapshot 73 KB |
| write cost, the 50k state with every one of its 500 entries carrying an 8.1 KB state (+ the ten) | state change **18.9 ms** median / 19.7 p95; a title change 18.6 / 19.5 ms; snapshot **5.66 MB** (the states as base64), `Room.sqlite` 46 MB. On the writer's queue for the debounced writes; on the main thread only for `flushAndWait` (quit, window close). B-73 |
| clean relaunch: every entry selected | **10 of 10**: the restored page at `s=2` with `canGoBack` true at creation (before its load), loaded in 318–756 ms, Back → `s=1` with its title |
| ⌘W on a Today entry with history, ⇧⌘T | removed, reopened at its page, `canGoBack` true, Back → the page before |
| ⌘W on a changed pinned entry (reset-unload-switch), reselected | unloaded; the new page at the stored URL (`s=0`) with `canGoBack` true; Back → `s=1` (spec §A.3) |
| a discarded background page revived (3.3a's check) | `discarded`, revived at `s=1`, `canGoBack` true, Back → github.com |

`kill -9` (`-RoomSessionPhase crash`: the same build, then one more step on the selected entry, `s=3`, and the script's SIGKILL as soon as the commit was seen):

| Kill after the last commit | Next launch | The last entry | The other nine |
|---|---|---|---|
| **59 ms** (`c1`) | `unclean_exit: true`; previous exit `clean=false (store uncleanExit=true, engine lastExitWasClean Default=false)` | restored at `s=2` (the `s=3` step lost), Back → `s=1` | 10 of 10 restored and Back |
| **746 ms** (`c2`, `ROOM_SL_KILL_DELAY_MS=600`) | the same | restored at **`s=3`**, Back → `s=2` | 10 of 10 |

The loss window: a navigation reaches the database one run-loop turn (the engine's coalescing) plus the store's 300 ms debounce plus the write (~1 ms at 10 entries, ~19 ms at 500) after its commit; a kill inside it restores the previous step, never a damaged state. The kill test (`scripts/persistence-kill-test.sh 100 300`, its writer now also setting 1–8 KB states on half the live-page changes): **100 kills, 0 failures**, 43 mid-transaction rolled back, commit 6.63 / 11.66 ms (median / p95; 2.1: 7.3 / 14.2 ms), database 424 KB.

Launch on the 50k state (`build/3.5/s50k` copied; the `relaunch` spike, process start → session → the selected page loaded; the selected entry `tab200.example.org` is unresolvable, so "loaded" is its error page):

| Launch | → spike | → selected loaded | state open |
|---|---|---|---|
| the v4 → v5 migration launch | 3.10 s | 5.05 s | 304.3 ms (quick_check) |
| v5, no states ×2 | 2.19 / 2.25 s | 4.02 / 4.07 s | 159.7 / 159.6 ms |
| v5, 500 entries × 8.1 KB states (4.07 MB) ×3 | 2.30 / 2.24 / 2.23 s | 4.27 / 3.98 / 3.96 s | 165.1 / 169.3 / 169.4 ms |
| 3.5 (v4) | 2.22 / 2.17 / 2.16 s | 3.98 / 3.92 / 3.92 s | 156.7 / 158.1 / 158.2 ms |

The states cost the open ~10 ms (reading 4 MB of blobs); launch to the selected page is unchanged within the runs' spread. The selected entry carried another page's state (the session run's Wikipedia list): its URL differs from the restored entry, so it loads its own URL with that list behind it (`NavigationRestore.navigate`).

### Task 4: the discard policy (`discardpolicy`, `build/evidence-3.7b/d1`, `--use-fake-device-for-media-stream`)

Three plain pages, a form typed into with real keys ("Room"), a Web Audio tone playing, video Picture-in-Picture (`requestPictureInPicture` on a click; the page logged "video pip"), a page capturing the fake camera and microphone (the host's prompt answered Allow), then a selected page; every one a Today tab.

| Page | `discardBlockers` | Idle sweep, clock 61 min ahead |
|---|---|---|
| plain ×3 | none | **discarded** |
| form (typed) | formInteractions, userEdits | kept (`keptByEngine`) |
| tone (playing) | audible | kept by the host's own 2.3 rule (audible pages are not candidates; the engine says the same) |
| video PiP | pictureInPicture | kept |
| capture | capturing | kept |
| selected | (not asked) | kept |

`auto-discardable` Room pages in the window's strip: **0**. Renderers (B-56): **10 before, 10 four seconds and ten seconds after** discarding three pages (2,518 → 2,662 → 2,609 MB summed): the discarded pages' renderers outlive the discard, as in 3.3a; recorded, not chased.

Memory pressure, the three plain pages revived first (oldest plain1, then plain2, plain3):

| Step | Result |
|---|---|
| Chrome's urgent discarding asked directly (`PageDiscardingHelper::DiscardAPage(URGENT, ignore_recent_visibility)`, spike hook), host policy off | **nothing discarded**; every page alive |
| simulated critical pressure through Chromium's notification (`MemoryPressureListener::SimulatePressureNotification`), host policy off, 6 s | the host heard `critical`; **0 discards, every page alive** (performance_manager discarded nothing by itself) |
| the same, policy on, 6 s, then `none` | **plain1 at 0 ms, plain2 at +1.02 s, plain3 at +2.02 s** (one per `Timing.criticalPressureStep`, oldest first), then nothing left eligible; form, tone, PiP, capture and the selection alive; level `none` after |

### Task 5: translate and spellcheck

Translate (`scripts/chrome-surfaces.sh --session 3.4b light -- -RoomSpikeOnly translate`, `GOOGLE_API_KEY=room-placeholder-no-key` through `ROOM_SPIKE_ENV`, B-63): the offer as the host's toast ("Translate this page from German to English?", Translate); Translate → the offer withdrawn, the toast gone, `lang=en` after 8 s, the heading "Welcome to the library". **Chrome's translate bubble now shows** for the later steps (Views, `TranslateBubbleView` 312 × 86 pt: German | English tabs, "Choose Language to Translate to"), through the toolbar provider's anchor; with the window at the screen's top-left the bubble sat at the window's top-left corner over the header (its top 23 pt above the site button's bottom, the button within its width; `research/screenshots/phase-3.7b/phase-3.4b-translate-bubble-light.png`), not below the button as the 3.7a password bubbles in a centred window. Without a key Chrome offers nothing (`TranslateManager` checks `google_apis::HasAPIKeyConfigured()`): the condition of "one page translated" is the placeholder key.

Spellcheck (`spelling`, `build/evidence-3.7b/sp1`; `SpellcheckService` with the macOS checker, on by default for Room profiles, no change needed): "This is misspeled " typed with real keys into `form.html`'s text area; the context menu on the word: **misspelled** | Add to Dictionary | Use Enhanced Spell Check | Look Up "misspeled" | … ; the suggestion chosen through the menu (`IDC_SPELLCHECK_SUGGESTION_0`) → the DOM reads **"This is misspelled "**. Add to Dictionary (`IDC_SPELLCHECK_ADD_TO_DICTIONARY`) on "roomzorbify": macOS `hasLearnedWord` true, then unlearned by the spike. Look Up (`IDC_CONTENT_CONTEXT_LOOK_UP`) offered on a selected word and chosen (the system's lookup panel itself: by hand). "Use Enhanced Spell Check" (Google's spelling service, opt-in with Chrome's consent) is in the menu: B-74.

### The grand tour's tabs section (`ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build --groups tabs light`, `build/grand-tour/20261005-185449-roomcore`, 2.4 min)

**38 passed, 2 failed** (3.3a: 36 / 4). The two: Discard Background Pages' "renderers released" (pages=4, renderers 11 → 12, every state `discarded`, rows dimmed: B-56) and switching p95 23.79 ms (median 15.29: B-53). `window_main` passed this time (3.3a's three activation failures gone). ⌘W/⇧⌘T on Today and pinned entries, the discarded tab's reload on selection, related tabs, ⌃Tab, ⌘1/⇧⌘], mute, the relaunch with only the selection loaded: pass.

### The baseline after the last engine change (`build/baseline/3.7b-final`, embryo host)

nav passed 20.4 s; ten-page quits **0.291 / 0.236 / 0.249 s** (load 8.6 / 10.6 / 13.0), 0 helpers left, 0 crash reports; stub hits none (37 window stubs; none in the session's spike logs either). The baseline after the first engine change (`build/baseline/3.7b-1`): nav 19.0 s, quits 0.261 / 0.323 / 0.245 s. `scripts/roomcore-apply.sh`: "0 applied, 24 already".

## Phase 3.8 — rebase 1 verify (2026-10-05, Mac mini M4, 24 GB, RoomCore 154.0.8037.98, Debug)

`scripts/roomcore-rebase.sh --verify 154.0.8037.98` on the rebuilt `out/dev` (component, `room_enable_spikes`), packaged at 22:39 (app and embryo host, framework `Versions/154.0.8037.98`), 60 Hz, the Claude desktop app frontmost, load 7–16 during the tour. Record: `build-log.md` "Rebase 154.0.8037.58 → 154.0.8037.98: verify".

| Section | 154.0.8037.98 | Before | Failures, attributed |
|---|---|---|---|
| layout | 154 / 1 | 3.3a layout + sidebar 165 / 15 (activation) | `popups` alert completed: the check reads `window.__alerted` from the isolated world (B-55's page-global read); the sheet appears and is answered |
| sidebar | 25 / 0 | (with layout) | — |
| tabs | 37 / 3 | 3.7b 38 / 2 | discard renderers 15 → 16 (B-56); switching median 16.31 ms, p95 24.50 ms (B-53; 3.7b 15.29 / 23.79) |
| chrome | 77 / 1 | 3.4b 73 / 5 | helper crash-report count 0 for the killed renderer (the CEF-shaped count) |
| **total** | **293 / 5** | | none new with the tag |

Numbers from the tour (light): memory baseline 1,230 MB, 10 hidden 5,816 MB (19 renderers), 30 hidden 11,825 MB; ten loaded (tabsmeasure) 6,250 MB (17 renderers); switch select call 6.97 / 11.02 ms, main-thread turn 16.31 / 24.50 ms, page visible 6.11 / 13.91 ms; relaunch 2.09 s to load start, 4.51 s to the selected page loaded; quits 0.60 / 0.69 / 0.63 s with 0 helpers left and 0 crash reports; open10 all loaded in 12 s; DevTools 28 ms (docked, already warm) and 325 ms median to the front-end loaded in chrome26b; find 32 / 426 ms median / p95 (Chromium's short-query delay in the first keys); killtest 100 kills, 0 failures; sidebar500 full reload 43.8 / 50.9 ms. Stub hits: one `CreateSadTab` (the crash step).

Baseline (`build/baseline/rebase-154.0.8037.98-223920`): nav passed 16.2 s; the external ten-page quits did not complete in four attempts: Stack Overflow kept loading behind Cloudflare's Turnstile challenge after the ready check (the host log carries the challenge script), so the fixture refused to quit-measure; the tour's `quittiming` above stands in for the three quits. 0 new crash reports in the session.

## Phase 3.9 — grand tour on RoomCore 154.0.8037.98 (preview under the 155 build) (2026-10-06, Mac mini M4, 24 GB, RoomCore, Debug)

The full tour (Phase 2.9's method: `scripts/grand-tour.sh`, 34 steps, one Debug build, one state and one engine directory per appearance, the four test servers once; "Phase 2.9 — grand tour" above) on the packaged component build of rebase 1 (`build/roomcore`, framework `Versions/154.0.8037.98`, ad hoc, mock keychain), run as `ROOM_TOUR_ENGINE=roomcore scripts/grand-tour.sh --no-build light dark` at `43720a4` before anything was deleted (`build/grand-tour/20261006-002018-roomcore`, binary sha256 `68390aebfa34`). Conditions: **under build load**: the clean 155.0.8059.36 `out/dev` build ran beside it at 6 jobs the whole time (load average 10–30, 18–20 typical; the quit-timing steps record load1 35–39); pageouts grew 76,505 → 77,072 over the 48 min (no swapping to speak of, so dark ran too); 60 Hz external display; the Claude desktop app frontmost; console unlocked. A preview: the exit's run is 3.9-2's on 155 without the build.

| Run | Wall time | Checks | Failed |
|---|---|---|---|
| CEF, Phase 2.9 run 3 (bd98bf9) | 36.3 min (18.6 + 17.6) | light 490 / 1, dark 489 / 2 | B-41 (switching p95) ×2, one 29 ms reveal frame |
| **RoomCore 154.0.8037.98, 3.9-1 (43720a4)** | **48.3 min (24.1 + 24.2)** | **light 498 / 7, dark 499 / 6** | below |

Per step (light / dark; the tour's checks grew since 2.9: 505 per appearance against 491):

| Step | Group | Time (s) | Light | Dark |
|---|---|---|---|---|
| smoke | layout | 15 / 6 | 6/6 | 6/6 |
| window | layout | 26 / 26 | 10/10 | 10/10 |
| cdp | layout | 16 / 16 | 12/12 | 12/12 |
| scroll | layout | 19 / 20 | 12/12 | 12/12 |
| resize | layout | 13 / 13 | 9/9 | 9/9 |
| memory | layout | 171 / 173 | 16/16 | 16/16 |
| audio | layout | 20 / 20 | 12/13 | 12/13 |
| popups | layout | 15 / 16 | 11/12 | 11/12 |
| hidden | layout | 16 / 15 | 11/11 | 11/11 |
| open10 | layout | 27 / 26 | 9/9 | 9/9 |
| diaframe | layout | 11 / 11 | 7/7 | 7/7 |
| keys | layout | 15 / 15 | 19/19 | 19/19 |
| devtools | layout | 22 / 22 | 10/10 | 10/10 |
| quittiming | layout | 88 / 89 | 9/9 | 9/9 |
| killtest | sidebar | 78 / 91 | 7/7 | 7/7 |
| sidebardemo | sidebar | 26 / 26 | 7/7 | 7/7 |
| sidebar500 | sidebar | 34 / 34 | 11/11 | 11/11 |
| spaces | spaces | 107 / 107 | 14/14 | 14/14 |
| spacecaptures | spaces | 40 / 41 | 7/7 | 7/7 |
| cookies | spaces | 18 / 18 | 14/14 | 14/14 |
| palette | palette | 27 / 26 | 19/19 | 19/19 |
| palette2 | palette | 43 / 44 | 26/26 | 26/26 |
| suggeston | palette | 20 / 20 | 10/10 | 10/10 |
| suggestoff | palette | 19 / 20 | 10/10 | 10/10 |
| palettemeasure | palette | 48 / 51 | 13/13 | 13/13 |
| tabs | tabs | 37 / 36 | 18/19 | 18/19 |
| tabsmeasure | tabs | 105 / 104 | 10/12 | 10/12 |
| tabcapture | tabs | 20 / 19 | 9/9 | 9/9 |
| chrome26a | chrome | 48 / 48 | 25/25 | 25/25 |
| chrome26b | chrome | 117 / 117 | 51/53 | 52/53 |
| layoutmodes | layoutmodes | 82 / 81 | 30/30 | 30/30 |
| app28a | appintegration | 36 / 37 | 29/29 | 29/29 |
| app28b | appintegration | 28 / 27 | 25/25 | 25/25 |
| netlog | netlog | 33 / 33 | 10/10 | 10/10 |

Every failure, attributed:

| Failure | Light / dark | Kind | Attribution, fix, rerun |
|---|---|---|---|
| popups: "alert as a sheet, completed" | ✗ / ✗ | spike fault | B-75: the check read `window.__alerted` from the isolated world (B-55's read). `popups.html` marks the DOM (`data-alerted`) and the spike reads it; `--only popups` passes light and dark (`build/grand-tour/20261006-011329-roomcore`). B-75 closed |
| chrome26b: "one helper crash report, the renderer `chrome://crash` killed: 0" | ✗ / ✗ | check fault (CEF-shaped) | the tour counted helper crashes in `~/Library/Logs/DiagnosticReports`, where RoomCore's Crashpad never writes; the tour now counts the engine directory's `Crashpad/{pending,completed}` minidumps per step and names each with its FATAL line (`steps/<step>.crashpad`); `--only chrome26b` 53/53 light and dark, then 54/54 light after the line fix (`20261006-013947-roomcore`) |
| chrome26b: "⌥⌘C turns on the element picker" (`panel="console picker=false"`) | ✗ / ✓ | conditions | light only; the front-end loaded in 439 ms median, 1.48 s max under the load (3.3b: 331 ms); passes in dark and in all three `--only` reruns |
| audio: "round1_became_audible within 2 s" (2,652 / 2,619 ms) | ✗ / ✗ | conditions (dev-build process launch) | the first play in a fresh page; round 2 and Web Audio 141–149 ms; 1,572 ms in 3.8-2's verify (load 7–16), 2,533–2,594 ms in the `--only` reruns (load 15–20): the component build's first audio-service launch under load, the same cause as B-57; B-57 annotated, judged on 3.9-2's run without the build |
| tabs: "Discard Background Pages: … renderers released" (15 → 16) | ✗ / ✗ | known row | B-56 |
| tabsmeasure: switching median and p95 under 16 ms | ✗ ✗ / ✗ ✗ | known row | B-53: median 16.18 / 17.83 ms, p95 23.23 / 24.28 ms (3.8-2: 16.31 / 24.50) |
| renderer minidumps (not counted by this run's harness, found by the fix above) | 9 + 1 / 9 + 1 | product finding (dev build) | **B-76** (new): per appearance 8 × `layout_object.h:518 DCHECK failed: !NeedsLayout() || ChildLayoutBlockedByDisplayLock()` (memory ×4, open10 ×1, quittiming ×3: live sites) and 1 × `inline_node.cc:2330 DCHECK failed: (*max_size_out)->Round() == content_size.Round() (1193 vs. 1177)` (palette), plus the expected `chrome://crash` kill. Since 3.1a every RoomCore tour had 0–10 such dumps, unseen. Under the fixed harness these steps fail "no helper crash report" with the DCHECK named (`--only memory,open10,quittiming,palette light`: 4 / 1 / 3 / 1 dumps, `20261006-013454-roomcore`); quittiming's run 3 there took 1.55 s at load1 37.6 (bound 1.5 s: conditions) |
| Stack Overflow's Cloudflare challenge, `window_main` / activation | — | — | not hit in this run (no external quit baseline in the tour; every `window_main` check passed) |

Product findings: one (B-76, a dev-build condition; the release build has no DCHECKs). Nothing fixed in the product from the tour.

Numbers from the run (light / dark; the conditions above; CEF's 2.9 tour and RoomCore's phase numbers beside them in `chapter-3-review.md` "Numbers"):

| Measure | Light | Dark |
|---|---|---|
| Memory baseline; 1 / 10 / 30 hidden pages | 1,233 MB; 1,627 / 5,249 / 10,283 MB (30 loaded, 36 renderers) | 1,243 MB; 1,385 / 5,080 / 8,627 MB (41 renderers) |
| 10 loaded of 50 entries (tabsmeasure) | 4,164 MB, 17 renderers | 4,649 MB |
| 50 loaded over 5 spaces | 9,790 MB, 52 renderers | 9,234 MB |
| Tab switch: select call; click → committed (median / p95); page visible | 6.74 / 8.17; 16.18 / 23.23; 5.88 ms | 7.78 / 10.94; 17.83 / 24.28; 6.36 ms |
| Relaunch: load start; selected loaded | 2.54 s; 6.03 s | 2.54 s; 6.30 s |
| Quit with ten pages (3 runs) | 1.14 / 0.78 / 0.89 s, 0 helpers left (load1 35–39) | 0.80 / 1.47 / 0.92 s |
| Smoke quit | 9.36 s (the first launch of the packaged binary; under the 10 s watchdog) | 0.68 s |
| Palette at 50k rows (engine): first key median; later keys p95; query only p95 | 22.99; 10.12; 15.52 ms | 22.41; 13.25; 14.33 ms |
| Palette open: call; to next frame median | 2.21; 5.32 ms | 1.28; 4.28 ms |
| Space switch, ⌃digit → first slide frame median / p95; lists loaded in 60 switches | 12.69 / 18.05 ms; 0 | 12.57 / 18.36 ms; 0 |
| Find keystroke → match median / p95 | 37 / 424 ms (Chromium's short-query delay in the first keys) | 40 / 424 ms |
| DevTools ⌥⌘I → front-end loaded, median | 439 ms | 431 ms |
| Peek decision → overlay frame; → first contentful paint | 27.2; 1,646 ms | 27.6; 761 ms (B-57) |
| Split created → laid out; → next frame | 5.38; 11.76 ms | 5.23; 11.86 ms |
| Kill test, 100 kills | 0 failures, 50 rolled back, commit 8.3 / 22.4 ms | 0 failures, 52 rolled back, 8.7 / 18.8 ms |
| 500-entry sidebar: full reload; select | 49.2; 4.38 ms | 48.4; 4.28 ms |
| CDP-free `executeJavaScript` round trip median / p95 | 0.15 / 0.61 ms | 0.14 / 0.59 ms |
| Cold launch by a link: event → requested; running link (open / AppleScript / NSWorkspace) | 479 ms; 25.6 / 23.3 / 20.9 ms | 496 ms; 33.8 / 26.3 / 26.9 ms |
| Suggestions on: requests through the proxy; net-log engine hosts | 34 (B-64); 0 | 34; 0 |
| Stub hits | `CreateSadTab` (the crash step) only | same |

## Phase 3.9 — schema v6: the local history dropped, the archive, the open time (2026-10-06, Mac mini M4, 24 GB, RoomCore 154.0.8037.98, Debug, under build load)

v6 (`Schema.createV6`) writes `history-archive.json` beside `Room.sqlite` (`HistoryArchive`: for a profile 3.5 imported, the URLs with visits older than 89 days, with those visits; for a profile never imported, every URL and visit), then drops `history_fts` (and its three sync triggers), `history_visit`, `history_host` and `history_url`; `RoomDatabase` then vacuums a file that is more than half free pages once. Method: the 3.5 50k state (`build/3.5/s50k`: 500 entries, 50,000 URLs, 151,779 visits, imported in 3.5) copied, and the `relaunch` spike as in 3.5 (`build/3.9/`), load 11–22.

| State | Launch | Process → session | → selected loaded | State open (B-42's line) | Archive | History |
|---|---|---|---|---|---|---|
| imported (flag set), first v6 launch | 1 | 2.76 s | 6.04 s | **251.8 ms** (v5 → v6, archive, drop, vacuum) | 631 B: the profile, 50,000 table URLs, 0 archived (the fixture's visits are within 85 days of 2026-10-05) | Chrome's, unchanged |
| imported, later launches | 3 | 2.30 / 2.24 / 2.27 s | 5.34 / 5.38 / 5.73 s | **12.0 / 12.1 / 11.9 ms** (quick_check) | — | — |
| 3.5's numbers on the same state (v5) | 3 | 2.22 / 2.17 / 2.16 s | 3.98 / 3.92 / 3.92 s | 156.7 / 158.1 / 158.2 ms | — | — |
| never imported (flag cleared, fresh engine directory), first v6 launch | 1 | 7.77 s | 8.17 s | 1,377.8 ms (the archive written) | **32,079,196 B (30.6 MiB, pretty-printed JSON): 50,000 URLs, 151,779 visits** | imported from the archive at the same launch: "50000 archived URLs -> 50000 URLs, 151779 visits imported (0 visits, 0 URLs older than the engine keeps) in 3.46 s" (3.5's from the table: 3.83 s) |
| never imported, next launch | 1 | 2.29 s | 5.32 s | 11.5 ms | — | "already imported (flag set)" |

The database file: 41.8 MB before; after v6 10,163 of 10,215 pages were free (the first build, without the vacuum), and with the vacuum 52 pages, 213 KB. The launch to the selected page is ~1.4 s slower than 3.5's on this run's load (18–22 vs 3.5–6.3), not by the state (the open is 146 ms faster). Kill test on v6 (`scripts/persistence-kill-test.sh 100 300 2101`): 100 kills in 67.6 s, 0 failures, 50 mid-transaction rolled back, commit 7.2 / 16.2 ms. `palettemeasure` with the history fixture now writing straight into Chrome's history (the tour's `--only` rerun, light / dark): `engine_history_rows` 50,000, first key 21.56 / 21.94 ms, later keys p95 11.12 / 10.67 ms, query only p95 12.94 / 13.05 ms (3.5: 20.5–24.7 / 9.2–12.1 ms).

## Phase 3.9 — grand tour on RoomCore 155.0.8059.36 (the exit) (2026-10-06, Mac mini M4, 24 GB, RoomCore, Debug)

The full tour (34 steps, one state and one engine directory per appearance, the four test servers once) on the packaged component build of rebase 2 (`build/roomcore`, framework `Versions/155.0.8059.36`, staged by `roomcore-rebase.sh --verify`, ad hoc, mock keychain), run as `scripts/grand-tour.sh --no-build light dark` at `fa44470` (`build/grand-tour/20261006-041307-roomcore`, binary sha256 `19d7ec6f5e0f`). Conditions: **no build beside it** (the machine quiet but for the tour: load1 7–13 at the quit steps), 60 Hz external display, the Claude desktop app frontmost, console unlocked. Patch series 24 (0012 still in; dropped after this run). The harness is 3.9-1's fixed one (the engine's Crashpad minidumps counted per step, B-76; the popups DOM mark, B-75), so each appearance has **511 checks**: the preview's 505, plus the "no helper crash report" check that the harness lists only for a step that left a minidump (4 steps here), plus one check each in chrome26b and palettemeasure from 3.9-1's harness fixes (54 and 14).

| Run | Wall time | Checks | Failed |
|---|---|---|---|
| CEF, Phase 2.9 run 3 (bd98bf9) | 36.3 min (18.6 + 17.6) | light 490 / 1, dark 489 / 2 of 491 | B-41 (switching p95) ×2, one 29 ms reveal frame |
| RoomCore 154.0.8037.98, 3.9-1 preview (43720a4), under the 155 build | 48.3 min (24.1 + 24.2) | light 498 / 7, dark 499 / 6 of 505 | the old harness; attributed in "Phase 3.9 — grand tour on RoomCore 154.0.8037.98" |
| **RoomCore 155.0.8059.36, 3.9-2 (fa44470)** | **41.4 min (20.8 + 20.6)** | **light 505 / 6, dark 505 / 6 of 511** | below: B-76 ×4 steps, B-56, B-53 |

Per step (light / dark; time in seconds):

| Step | Group | Time | Light | Dark |
|---|---|---|---|---|
| smoke | layout | 6 / 6 | 6/6 | 6/6 |
| window | layout | 24 / 24 | 10/10 | 10/10 |
| cdp | layout | 15 / 15 | 12/12 | 12/12 |
| scroll | layout | 18 / 18 | 12/12 | 12/12 |
| resize | layout | 12 / 12 | 9/9 | 9/9 |
| memory | layout | 195 / 183 | 16/17 | 16/17 |
| audio | layout | 18 / 18 | 13/13 | 13/13 |
| popups | layout | 14 / 14 | 12/12 | 12/12 |
| hidden | layout | 14 / 14 | 11/11 | 11/11 |
| open10 | layout | 16 / 16 | 9/10 | 9/10 |
| diaframe | layout | 9 / 8 | 7/7 | 7/7 |
| keys | layout | 14 / 13 | 19/19 | 19/19 |
| devtools | layout | 20 / 20 | 10/10 | 10/10 |
| quittiming | layout | 56 / 55 | 9/10 | 9/10 |
| killtest | sidebar | 69 / 69 | 7/7 | 7/7 |
| sidebardemo | sidebar | 26 / 26 | 7/7 | 7/7 |
| sidebar500 | sidebar | 34 / 34 | 11/11 | 11/11 |
| spaces | spaces | 77 / 77 | 14/14 | 14/14 |
| spacecaptures | spaces | 33 / 34 | 7/7 | 7/7 |
| cookies | spaces | 12 / 13 | 14/14 | 14/14 |
| palette | palette | 23 / 23 | 19/20 | 19/20 |
| palette2 | palette | 40 / 40 | 26/26 | 26/26 |
| suggeston | palette | 18 / 18 | 10/10 | 10/10 |
| suggestoff | palette | 18 / 18 | 10/10 | 10/10 |
| palettemeasure | palette | 21 / 21 | 14/14 | 14/14 |
| tabs | tabs | 30 / 30 | 18/19 | 18/19 |
| tabsmeasure | tabs | 90 / 90 | 11/12 | 11/12 |
| tabcapture | tabs | 17 / 17 | 9/9 | 9/9 |
| chrome26a | chrome | 43 / 43 | 25/25 | 25/25 |
| chrome26b | chrome | 103 / 103 | 54/54 | 54/54 |
| layoutmodes | layoutmodes | 73 / 73 | 30/30 | 30/30 |
| app28a | appintegration | 34 / 33 | 29/29 | 29/29 |
| app28b | appintegration | 22 / 22 | 25/25 | 25/25 |
| netlog | netlog | 32 / 33 | 10/10 | 10/10 |

Every failure, attributed (no `--only` rerun was needed: no harness fault, no condition failure):

| Failure | Light / dark | Kind | Attribution |
|---|---|---|---|
| memory: "no helper crash report" | 4 / 5 dumps | dev-build condition (B-76, the planner's decision) | light 4 × `layout_object.h:518 DCHECK failed: !NeedsLayout() \|\| ChildLayoutBlockedByDisplayLock()` (renderers on live sites); dark 4 × the same plus **1 × `net/http/http_cache_transaction.cc:4112 DCHECK failed: cache_entry_status_ == ENTRY_UNDEFINED \|\| new_cache_entry_status == ENTRY_OTHER (6, 3)`** in the network service (`ptype=utility`, `network.mojom.NetworkService`; new: the first `//net` DCHECK the tour has seen; Chromium restarts the service, the step's 16 other checks pass); B-76 annotated |
| open10: "no helper crash report" | 1 / 1 | dev-build condition (B-76) | `layout_object.h:518` (a live site of the ten) |
| quittiming: "no helper crash report" | 3 / 3 | dev-build condition (B-76) | `layout_object.h:518` ×3; the three quits themselves 0.30–0.37 s, 0 helpers left |
| palette: "no helper crash report" | 1 / 1 | dev-build condition (B-76) | `inline_node.cc:2297 DCHECK failed: (*max_size_out)->Round() == content_size.Round()` (1181 vs 1166 / 1193 vs 1177; the same DCHECK as 154's `:2330`, moved) |
| tabs: "Discard Background Pages: … renderers released" | 15 → 16 / 15 → 16 | known row | B-56 |
| tabsmeasure: switching p95 under 16 ms | 22.97 / 23.79 ms | known row | B-53 (the median passes both: 15.38 / 15.98 ms) |

Versus the preview: the conditions failures are gone without the build beside it (audio's first audible edge 1,558 / 1,588 ms under the 2 s bound; the element picker passes; quits 0.29–0.37 s against 0.78–1.47 s); B-76's renderer DCHECKs are unchanged by the milestone (the same two Blink DCHECKs on the same four steps, 9 per appearance as on 154); the switching median passes again. No `window_main` failure, no Stack Overflow quit in the tour. Stub hits in the surviving engine logs: none (the logs keep each appearance's last launch; the verify run on this build saw `CreateSadTab` only, no `GetAcceleratorProvider`). Product findings: none new (the `//net` DCHECK is B-76's class, a dev-build DCHECK on live sites). Nothing fixed in the product.

**Green for what 3.9 owns**: every failure carries a row (B-53, B-56) or the planner's stated dev-build condition (B-76: DCHECK minidumps on live-site steps of the component build; the release framework's crash count is "Phase 3.9 — crashes on the release framework" below).

Numbers from the run (light / dark; no build beside it):

| Measure | Light | Dark |
|---|---|---|
| Memory baseline; 1 / 10 / 30 hidden pages | 1,241 MB; 1,625 / 4,962 / 11,720 MB (30 loaded, 38 renderers) | 1,246 MB; 1,630 / 4,584 / 9,888 MB (36 renderers) |
| 10 loaded of 50 entries (tabsmeasure) | 5,565 MB, 17 renderers | 5,429 MB |
| 50 loaded over 5 spaces | 9,723 MB, 52 renderers | 9,727 MB |
| Tab switch: select call; click → committed (median / p95); page visible | 6.63 / 10.80; 15.38 / 22.97; 5.74 ms | 7.10 / 10.74; 15.98 / 23.79; 4.63 ms |
| Relaunch: load start; selected loaded | 2.08 s; 4.17 s | 2.21 s; 4.75 s |
| Quit with ten pages (3 runs) | 0.33 / 0.30 / 0.37 s, 0 helpers left (load1 7.8–11.1) | 0.29 / 0.36 / 0.31 s (load1 7.1–13.3) |
| Smoke quit | 0.11 s | 0.08 s |
| Palette at 50k rows (engine): first key median; later keys p95; query only p95 | 21.75; 9.79; 15.60 ms | 21.73; 10.00; 14.61 ms |
| Palette open: call; to next frame median | 2.23; 3.74 ms | 2.71; 4.90 ms |
| Space switch, ⌃digit → first slide frame median / p95 | 14.90 / 20.49 ms | 15.74 / 20.50 ms |
| Find keystroke → match median / p95 | 19.45 / 426 ms | 30.93 / 427 ms |
| DevTools ⌥⌘I → front-end loaded, median | 331 ms | 334 ms |
| Peek decision → overlay frame; → first contentful paint median / p95 | 22.4; 110 / 525 ms | 21.1; 469 / 494 ms (B-57) |
| Split created → laid out; → next frame | 4.76; 11.45 ms | 4.57; 12.68 ms |
| Audio: first audible edge; later edges | 1,558; 126–157 ms | 1,588 ms |
| Kill test, 100 kills | 0 failures, 44 rolled back, commit 8.31 / 13.77 ms | 0 failures, 41 rolled back, 7.92 / 13.29 ms |
| 500-entry sidebar: full reload; select | 44.1; 3.53 ms | 41.6; 3.54 ms |
| Script round trip median / p95 | 0.15 / 0.55 ms | 0.25 / 0.56 ms |
| Cold launch by a link: event → requested; running link (open / AppleScript / NSWorkspace) | 287 ms; 24.4 / 17.9 / 18.6 ms | 273 ms; 25.5 / 13.6 / 21.1 ms |
| Suggestions on: requests through the proxy; net-log engine hosts | 34 (B-64); 0 | 34; 0 |

## Phase 3.9 — patch 0012 dropped (series 23) (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36, Debug)

After the exit tour: `0012-extension-chooser-toolbar-guard.patch` removed from `series` and the tree (B-61: upstream's own `if (!browser_view) return base::DoNothing();` in `ShowDeviceChooserDialogForExtension` gives a Room Browser the same safe rejection on 155). `scripts/roomcore-apply.sh` refuses to drop a branch commit that left the series ("the room branch has a commit outside the series (room: 0012-…)": its guard for experiments), so the commit was dropped from the `room` branch by hand without touching the worktree (`git replay --onto <0012>^ <0012>..room`, which in git 2.54 moves the branch itself; the one file 0012 changed, `chooser_bubble_ui.cc`, then went back to upstream's content through a `git stash push` of the stale copy: only that file's mtime changed). Then `scripts/roomcore-apply.sh` twice: **"patches: 0 applied, 23 already on the room branch"** both times; `git describe --tags` = `155.0.8059.36-23-g62be06cc2bcd5`; the checkout's `chooser_bubble_ui.cc` is upstream's (the `BrowserView` lookup and its null check at lines 296–297).

- **Rebuild** (`ROOM_BUILD_JOBS=6 scripts/roomcore-build.sh`, nohup, `build/roomcore-0012-drop-build.log`): **"build done in 59 s"** (one `chrome/browser/ui` file and the relink of its component), load 6.6 → 9.1. Package 38 s.
- **Baseline** (embryo host): attempt 1 nav passed (17.1 s), the ten-page fixture rejected on Stack Overflow still loading (its challenge; known); attempt 2 **nav passed (10.7 s), quits 0.396 / 0.348 / 0.274 s** (load1 7.3 / 10.2 / 11.6), 0 helpers left, 0 crash reports, exit 0 each.
- **The chooser without the patch** (`scripts/roomcore-features.sh ui-extension-device`, embryo host, the fixture extension's popup asks `navigator.usb.requestDevice` from `chrome-extension://jkog…`): `extension-device-result: NotFoundError "No device selected."`, `drive-complete`, no FATAL or Check line in the host log, 0 minidumps under the profile's Crashpad: **the same safe rejection as 3.6b's run with 0012** (`build/evidence-3.6b-ui-extension-device.log`). A safe rejection is not a chooser: B-71 keeps the extension-origin chooser's future.

## Phase 3.9 — the release build on 155.0.8059.36: crashes, memory, size, launch, signing, Sparkle (2026-10-06, Mac mini M4, 24 GB, RoomCore release build)

**Build** (`build-log.md` "Phase 3.9-2: the release build on 155.0.8059.36"): the official build of the 23-patch series at `43b3213`, clean after rebase 2's clang roll: 4 h 8 min 29 s to a failure at the export-order check with the framework already linked (B-77: `room_core.exports` was alphabetical; nm lists the 52 class symbols in address order), the list rewritten in nm's order in `//room`, then 423 s (the framework relinked in 328 s at **12.17 GB `max_rss`** from the ThinLTO cache, the rest of the bundle). **4 h 15 min 32 s** of build in all (3.1b-2 on 154.0.8037.58: 4 h 43 min 28 s). Packaged with `scripts/roomcore-package.sh --release` (87 s: Release app and release host) and `CONFIGURATION=Debug … --release --app-only` (24 s). Apps as in 3.1b-2: **Release app** (ad hoc), **Debug app over release** (the spikes and the tour steps), **signed copy** (`build/roomcore-release-signed`, Developer ID, never launched).

### Crashes on the release framework (B-76's question)

`ROOM_TOUR_APP=<Debug app over release> scripts/grand-tour.sh --no-build --only smoke,open10,quittiming,memory light` (`build/grand-tour/20261006-093253-roomcore`; `ROOM_TOUR_APP` added to the tour for this, a harness option; load 4–7): **40 / 40 checks, 0 minidumps** under the engine's `Crashpad/{pending,completed}` (the database exists; the steps' `.crashpad` files are empty), 0 crash reports, 0 helpers left. The same four steps on the 155 dev build left **9 renderer minidumps per appearance** (the exit tour: 8 × `layout_object.h:518`, 1 × `inline_node.cc:2297`, plus one `//net` DCHECK in dark): the live sites that trip the dev build's DCHECKs do not crash the product. B-76 stays a dev-build condition.

The switching p95 on the release framework (20.87 ms) still misses the 16 ms bound by more than a quarter (B-53: the release build removes ~3 ms at the median and ~2 ms at the p95 against the dev build; the profile of 3.3b already found no single Room-side cause; performance work is a later chapter). tabsmeasure: 11 / 12, 0 minidumps.

From the same steps (release framework, light, the machine quiet but for the session):

| Measure | Release framework (155) | Dev build, exit tour (155, light) | CEF (2.9 tour, light) |
|---|---|---|---|
| Memory baseline (summed RSS) | **559 MB** (9 processes) | 1,241 MB | 849 MB |
| 1 / 10 / 30 hidden pages | 748 / **4,097** / 8,725 MB (4 / 17 / 46 renderers) | 1,625 / 4,962 / 11,720 MB | — / 3,572 (10 loaded) / 7,292 MB |
| open10: seconds to all loaded | 5 | 11 | — |
| Quit with ten pages (3 runs) | 0.24 / 0.26 / 0.30 s, 0 helpers left (load1 5.4–6.5) | 0.30–0.37 s | 0.35–0.50 s |
| Smoke quit | 0.10 s | 0.11 s | — |
| Tab switch (tabsmeasure, `--only`, `20261006-093907-roomcore`): select call; click → committed median / p95; page visible | 5.19 / 8.28; **12.88 / 20.87**; 4.17 ms | 6.63 / 10.80; 15.38 / 22.97; 5.74 ms | 13.7 / 17.5 ms (committed) |
| 10 loaded of 50 entries (tabsmeasure) | 4,801 MB, 19 renderers | 5,565 MB, 17 renderers | 3,572 MB |
| Relaunch: load start; selected loaded | **0.56 s; 1.33 s** | 2.08 s; 4.17 s | 0.82 s; 1.44 s |

### Sizes (Release app, `du -sk`)

| Part | KB | MB | 3.1b-2 (154.0.8037.58) |
|---|---:|---:|---:|
| **Room.app** | 395,640 | **386** | 382 |
| RoomCore.framework | 375,940 | 367 | 364 |
| framework binary `RoomCore` | 272,196 | 266 | 264 |
| Resources | 84,300 | 82 | 81 |
| of which 220 locales | 50,400 | 49 | 49 |
| Libraries | 15,820 | 15 | 15 |
| Helpers | 3,428 | 3.3 | 3.4 |
| Swift app executable | 16,712 | 16 | 15 |
| Sparkle / Sentry | 2,748 / 48 | 2.7 / 0.05 | same |
| dSYMs (15; RoomCore.dSYM 2,251,312 KB) | 2,331,268 | 2,277 | 2,263 |
| signed copy | 395,880 | 387 | 382 |

`nm -jUng` on the framework binary: 55 exports (Chrome's three and the 52 class symbols).

### Cold launch (Release app)

`scripts/roomcore-cold-launch.py <Release app> build/evidence-3.9b/cold-launch 3` (fresh state and engine directory per run, the page on 127.0.0.1, quit by pid; load1 4.1–4.5):

| Run | Launch → page loaded | Navigation → load | Quit | Exit | Helpers left | Minidumps |
|---|---:|---:|---:|---:|---:|---:|
| 1 (first launch of this build) | 2.506 s | 68.7 ms | 0.111 s | 0 | 0 | 0 |
| 2 | **0.456 s** | 45.8 ms | 0.109 s | 0 | 0 | 0 |
| 3 | **0.457 s** | 51.6 ms | 0.111 s | 0 | 0 | 0 |

Median **0.457 s** (3.1b-2: 0.414 s, first launch 2.715 s).

### Signing and notarization (signed copy)

`ROOM_SIGN_COPY=build/roomcore-release-signed scripts/roomcore-sign.sh <Release app>` (91 s in all): signed in **9.9 s**; `codesign --verify --deep --strict`: valid, satisfies its Designated Requirement; `flags=0x10000(runtime)`, `TeamIdentifier=N56PMJ99UT`; `spctl` before: "rejected, source=Unnotarized Developer ID". Notarization: zip **171,141,853 bytes**, submission **cc579ee0-5121-4ec5-80cf-159cb1cec861**, **Accepted** in 70.2 s; stapled ("The staple and validate action worked!"); `spctl --assess`: "**accepted, source=Notarized Developer ID**". Not launched (its keychain prompt is the user's).

### Sparkle packaging (signed copy)

`ROOM_SPARKLE_UNSIGNED=1 scripts/sparkle-package.sh build/roomcore-release-signed/Room.app build/sparkle-3.9`: **DMG 186,841,560 bytes (178 MiB)** in 8 s (3.1b-2: 184,497,802); the unsigned appcast entry: version 1, short version 0.1.0, minimum system 26.0, enclosure `https://updates.room.invalid/Room-0.1.0-1.dmg` length 186841560. The EdDSA signature (`sign_update` reading the `ed25519` key from the login keychain) and an update delivered through a feed to one machine are the user's (the keychain approval and the feed URL, B-6).

## Laptop (M1 Max, 64 GB), 2026-10-06: Chapter 3's laptop checks — on the 60 Hz external display, not the 120 Hz panel

**Conditions, for every number below.** The laptop drives two displays: the Pro Display XDR (3008 × 1692 @ **60 Hz**, the main display) and the built-in panel (1728 × 1117 @ 120 Hz, not main). A spike's window opens on the main display, so every run measured **60 Hz** (`display_frame_interval` 16.67 ms on every run that reports it); the user was away and chose to measure as is rather than change the display arrangement. The machine was loaded the whole session: load average **70–145** (1 min), 4–5 of 10 cores busy (the Claude desktop app's renderer ~120 %, OrbStack, bun, Zen, Remote Desktop, `avconferenced`), and the user's own Room (`/Applications/Room.app`, the notarized 0.1.0 (1), pid 10481) running on the real state. `window_main: true` on every run. Spikes on `-RoomStateDirectory` and `-RoomEngineDirectory` under `/tmp/room-laptop`. Raw output: `build/evidence-laptop/` and `build/grand-tour/20261006-1{20827,22639}-roomcore` (not committed).

**Apps.** (a) The Mac mini's Debug app over the release framework (155.0.8059.36, `43b3213`), copied by rsync as `docs/laptop-build.md` says; (b) the same app built on the laptop (§A step 3, 28 s, `aa57233` plus this session's chooser spike) over the copied release framework, whose `RoomCore` binary is byte-identical to (a)'s. (a)'s spikes find their `file://` fixtures through `#filePath`, i.e. under `/Users/eve/Code/room`, which does not exist here: its spaces fixture's 50 "loaded" pages were error pages (14 renderers, 1,568 MB against 52 renderers, 5,000 MB on (b)), and its tour run failed 19 checks on missing elements (audio, popups, keys, tabs). Palettemeasure, tabsmeasure and the sidebar snapshots use no file fixtures, so their (a) numbers stand; the space switch and the tour are (b)'s.

**Harness fixes (laptop reasons, said):** the wrappers matched any `Room.app/Contents/MacOS/Room` and any `Room Helper`, so with the user's Room running every wrapper refused to start, `tabs-measure.sh` and the tour would have waited forever for its helpers, and the tour's step cleanup would have sent SIGTERM to it; they now match their own app's path (`room_scope` in `scripts/lib/room-process.sh`; ea4aaa9). `tabs-measure.sh` passed no engine directory, so its spike opened the **real** engine root, which the user's Room holds: Chromium's process singleton ended each of four launches at once, and the launches truncated the user's `~/Library/Application Support/Room/RoomCore/RoomCore.log` (0 bytes at 12:01); it now passes `-RoomEngineDirectory "$STATE/engine"` (aa57233); the app-side default is B-78. `docs/laptop-build.md` §A: the `EngineRoomCore` package compiles against `build/roomcore` whatever `ROOMCORE_STAGE` says, and the laptop had a 2026-10-02 stage there (build failed: "cannot find type 'RoomPermissionRequest'"); moved to `build/roomcore-stale-2026-10-02`, `build/roomcore/RoomCore.framework` is a symlink to the release framework (ca9f4c6).

### Laptop, 2026-10-06: B-20, the palette (`palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000`, app (a), three runs)

| Measure (ms) | run 1 (load 75) | run 2 (88) | run 3 (91) | Mac mini exit tour, 155 dev, light | Bound |
|---|---|---|---|---|---|
| Palette open: our call median; to next frame median / p95 | 3.23; 6.66 / 14.45 | 3.84; 7.45 / 14.82 | 2.92; 6.27 / 14.43 | 2.23; 3.74 / — | one frame (16.7 ms at 60 Hz, 8.3 at 120) |
| First keystroke of a query: turn median / p95 | 14.04 / 22.19 | 17.00 / 27.19 | 15.60 / 24.18 | 21.75 (median) | — |
| **Later keys' turn, median / p95** | 8.20 / **15.08** | 7.77 / **14.28** | 8.18 / **14.74** | p95 9.79 | **16 ms p95** |
| Query only (all keys), median / p95 | 4.84 / 8.20 | 4.63 / 8.33 | 4.89 / 7.14 | p95 15.60 | 16 ms p95 |
| History rows per key (mean); keys completed inline | 2.8; 55 | 2.8; 55 | 2.8; 55 | 2.8; 55 (3.5) | — |

The 16 ms bound holds at 60 Hz on all three runs (later keys p95 14.3–15.1 ms; Chrome's async updates p95 11.0 ms). At 120 Hz one frame is 8.3 ms: the open's median (6.3–7.5 ms to the next frame) would fit, the later keys' median (7.8–8.2 ms) is at the edge and their p95 is not; the 120 Hz reading itself is still open (the window was on the 60 Hz display).

### Laptop, 2026-10-06: B-21, the space switch (`spaces -RoomSidebarFixture spaces500 -ApplePersistenceIgnoreState YES`, app (b), three runs)

| Measure (ms, median / p95) | run 1 (load 112) | run 2 (145) | run 3 (120) | Mac mini exit tour, 155 dev | CEF 2.5 (60 Hz, not key) | Bound |
|---|---|---|---|---|---|---|
| ⌃digit key to the switch starting | 6.09 / 7.58 | 5.91 / 7.84 | 5.79 / 8.16 | — | 1.93 / 2.54 | — |
| The switch's main-thread code | 3.75 / 4.21 | 3.72 / 4.74 | 3.80 / 4.31 | — | 6.37 / 8.70 | — |
| … the card (`TabController.activate`) | 2.19 / 2.55 | 2.15 / 2.62 | 2.19 / 2.60 | — | 3.47 / 4.56 | — |
| **⌃digit to the slide's first frame** | **10.84 / 15.12** | **11.67 / 15.47** | **11.54 / 15.84** | 14.90 / 20.49 | 10.85 / 17.10 | one frame at the median |
| Lists loaded during 60 switches | 0 | 0 | 0 | 0 | 0 | 0 |
| 50 loaded pages over 5 spaces | 5,000 MB, 52 renderers | 5,001 MB | 4,998 MB | 9,723 MB, 52 | 5.9–6.5 GB | — |

Window key and frontmost this time (2.5's window was never key). At 60 Hz the median first slide frame is within one frame of the key (10.8–11.7 ms); the switch's own code is 3.7–3.8 ms median, so at 120 Hz (8.3 ms) the code fits but the key's ~6 ms before the switch starts does not leave room for the first frame at the median. App (a) on error pages gave the same timings (10.07–11.06 / 15.67–15.85 ms).

### Laptop, 2026-10-06: B-18 and B-53, tab switching (`scripts/tabs-measure.sh`, app (a), three runs; the tour's tabsmeasure on app (b))

| Measure (ms) | run 1 (load 81) | run 2 (86) | run 3 (89) | laptop tour, app (b) | Mac mini, release framework (3.9-2) | Mac mini exit tour, dev | Bound |
|---|---|---|---|---|---|---|---|
| `select` call median / p95 | 4.10 / 6.78 | 3.96 / 6.00 | 4.20 / 6.70 | 4.16 / 6.23 | 5.19 / 8.28 | 6.63 / 10.80 | — |
| **Click → committed (whole turn) median / p95** | 9.29 / **12.41** | 9.37 / **11.44** | 9.59 / **12.24** | 9.06 / **11.10** | 12.88 / **20.87** | 15.38 / 22.97 | **16 ms p95** |
| Page visible median / p95 | 3.78 / 8.20 | 3.59 / 6.75 | 4.40 / 8.57 | 3.69 / 5.79 | 4.17 (median) | 5.74 | — |
| Page's first frame median / p95 | 8.62 / 13.77 | 8.93 / 11.59 | 8.83 / 13.41 | — | — | — | — |
| 10 loaded of 50 entries (summed RSS) | 3,503 MB, 19 renderers | 3,525 MB | 3,630 MB | 4,228 MB, 17 | 4,801 MB, 19 | 5,565 MB | — |
| Relaunch: load start; selected loaded | 1.05; 1.94 s | 1.04; 1.85 s | 1.26; 2.46 s | 0.90; 1.97 s | 0.56; 1.33 s | 2.08; 4.17 s | — |

B-18's conditions are met (screen unlocked, window key, pages visible: `switch_page_visible` and `switch_page_first_frame` recorded on all 300 switches). **The 16 ms p95 bound holds on the laptop** (11.1–12.4 ms) on the same framework that misses it on the Mac mini by 30 % (20.87 ms), both at 60 Hz: a machine difference, not the panel (below). Max over the 300 switches: 39.0 ms once (run 1); runs 2–3 max 12.3 / 13.5 ms.

### Laptop, 2026-10-06: B-16, the 500-entry scroll (`scripts/sidebar-snapshots.sh 500`, app (a); the tour's sidebar500 on app (b))

| Run (4 s each) | Late frames (> 1.5 × nominal) | Step median / p95 / max (ms) | Steps over 8.33 ms (of 241) | Tour (b): steps over 8.33 ms | Mac mini 2.2b (of 240) |
|---|---|---|---|---|---|
| native 1500 pt/s | 0 | 4.23 / 7.47 / 8.72 | 4 | 0 | 2 |
| proxy120 1500 pt/s | 0 | 5.37 / 8.88 / 19.95 | 19 | 5 | 20 |
| native 4000 pt/s | 0 | 4.89 / 7.92 / 26.97 | 5 | 3 | 7 |
| proxy120 4000 pt/s | 0 | 4.39 / 8.09 / 11.67 | 11 | 13 | 4 |
| native 9000 pt/s | 0 | 6.57 / 9.27 / 19.69 | 65 | 36 | 6 |
| proxy120 9000 pt/s | 0 | 3.92 / 7.95 / 10.61 | 10 | 16 | 4 |

The display link ran at 60 Hz (the report says "display 60.0 Hz"), so these are 60 Hz frames: 0 late frames of 1,440. The proxy120 rows estimate the 120 Hz step: 4–8 % of steps over 8.33 ms at load ~95 (Mac mini 2–8 %). The native 120 Hz run and the trackpad fling stay the user's (the window has to be on the built-in panel). The same report's update timings are ~2× the Mac mini's: full reload 100.4 ms (Mac mini 44.1), select 7.81 ms (3.53), drop of a 10-tab group 20.3 ms (9.5), insert 9.3 ms (4.7).

### Laptop, 2026-10-06: the exit tour's layout, sidebar and tabs sections (`scripts/grand-tour.sh --no-build --groups layout,sidebar,tabs light`, app (b))

| Run | Wall time | Checks | Failed |
|---|---|---|---|
| Mac mini, exit tour 155 dev (same 20 steps, light) | 11.6 min (the steps' sum) | 218 / 223 | memory, open10, quittiming (B-76 dev-build minidumps), tabs (B-56), tabsmeasure (B-53) |
| Laptop, app (a) (`20261006-120827`) | 11.8 min | 202 / 222 | 19 on missing fixture pages (`#filePath`, above: audio 3, popups 6, keys 7, tabs 3), the scroll mask run 2 at 24.7 fps once |
| **Laptop, app (b)** (`20261006-122639`) | **10.0 min** | **219 / 222** | quittiming run 2 (2.17 s at load1 98: the load), killtest's ack check (below), tabs (B-56) |

The kill test's failing line is "reopened at a generation committed after the last ack: 2": the database was *ahead* of the last acknowledged commit (`dbGeneration > lastAcked` in `PersistenceHarness`: the commit landed and the kill beat its ack), not behind; 100 kills, 0 failures, every reopen intact. Under load ~100 the ack lost the race twice; the check's label ("no generation lost after its acknowledgement") reads as a loss when it counts the opposite (B-79). No minidump in any step (the release framework; the dev build's B-76 DCHECKs do not exist here).

| Measure | Laptop, app (b) | Mac mini, release (3.9-2) | Mac mini, exit tour dev |
|---|---|---|---|
| Memory baseline; 1 / 10 / 30 hidden | 734 MB; 895 / 4,348 / 11,573 MB (5 / 18 / 43 renderers) | 559 MB; 748 / 4,097 / 8,725 MB | 1,241 MB; 1,625 / 4,962 / 11,720 MB |
| open10: seconds to all loaded | 7 | 5 | 11 |
| Quit with ten pages (3 runs) | 0.62 / **2.17** / 0.89 s, 0 helpers left (load1 97–101) | 0.24–0.30 s | 0.30–0.37 s |
| Smoke quit | 0.14 s | 0.10 s | 0.11 s |
| Audio: first audible edge; later | 426; 149 ms | — | 1,558; 126–157 ms |
| Kill test: in flight / rolled back; commit median / p95 | 50 / 48; 5.91 / 9.47 ms | — | 44 rolled back; 8.31 / 13.77 ms |
| 500-entry sidebar: full reload; select | 95.0; 7.52 ms | — | 44.1; 3.53 ms |
| CDP `Runtime.evaluate` round trip median / p95 | 0.15 / 0.26 ms | — | 0.15 / 0.55 ms (script round trip) |

### Laptop, 2026-10-06: devices (B-26, B-62; app (b), the test servers up)

| Check | What happened |
|---|---|
| `chromesurfaces2 -RoomSpikeOnly permissions`: Location ▸ Allow in Room's popover | popover shown, answered; the page reads `geolocation: prompt` before and after a reload (as 3.4a: B-26) |
| Notifications ▸ Deny | remembered after the reload: no prompt, `denied` |
| Camera ▸ Allow This Time | **no Room popover within 8 s**; a macOS dialog appeared during this run (a `UserNotificationCenter` window, 260 × 234, window number 16611, created right after the spike's window 16607); its text could not be read (the session has no Screen Recording, and system dialogs are the user's), and it is still on screen |
| `pageservices -RoomSpikeOnly capture` (`capture.html`, Camera and microphone) | no Room popover within 8 s; the page stayed "idle" for 10 s (`getUserMedia` neither resolved nor failed), capture state 0, the row no indicator; consistent with Chromium waiting on macOS's camera/microphone authorization (Room's ad-hoc Debug build has none), the dialog above. Stopped here; Allow This Time / Allow with real devices and the capture indicator are the user's |
| `pageservices -RoomSpikeOnly serial` (`chooser.html` ▸ "Connect a serial port", Room launched by `open`) | **the browser's main thread hangs**: no chooser, no new dialog; `sample` (`build/evidence-laptop/serial-hang.sample.txt`): 2,130 of 2,130 main-thread samples in `-[IOBluetoothDeviceInquiry init]` → `+[IOBluetoothCoreBluetoothCoordinator sharedInstance]` → `dispatch_semaphore_wait` (Chromium's Bluetooth start-up, reached through Web Serial's Bluetooth ports). The quit AppleEvent and SIGTERM could not be handled; ~6 min later Chrome's shutdown watchdog ended it (minidump: `shutdown_watchdog_mac.cc`) |
| `pageservices -RoomSpikeOnly bluetooth` (`requestDevice({acceptAllDevices: true})`) | the same hang (1,412 of 1,412 samples in the same frames, `bluetooth-hang.sample.txt`); killed with SIGKILL after 150 s (a throwaway instance) |
| The macOS prompts | location: none seen beyond the dialog above; Bluetooth: no prompt window appeared while the main thread waited on CoreBluetooth. Likely, not shown: macOS's Bluetooth authorization for this build is held behind the pending dialog, and Chromium waits for CoreBluetooth synchronously on the UI thread (B-62) |

B-62's TCC crash (3.4b, a shell launch) did not recur under `open`: the process is now its own responsible process, and Web Serial reaches Bluetooth, where it waits instead of crashing.

### Laptop, 2026-10-06: the signed DMG

`~/Downloads/Room-0.1.0-1.dmg` (scp from the Mac mini, sha256 `ddce9376…8317`, 186,841,560 bytes) is byte-identical to the copy the user had already installed from: `/Applications/Room.app` (0.1.0 (1), signed 6 Oct 2026 09:36:47, Developer ID N56PMJ99UT) was installed and **running** (launched 11:41), so it was not overwritten. On it: `codesign --verify --deep --strict`: valid on disk, satisfies its Designated Requirement; `spctl --assess --type execute`: **accepted, source=Notarized Developer ID**; `stapler validate`: worked. The keychain prompt was the user's (already answered: the app is running on the real state).

### Laptop, 2026-10-06: what differed from the Mac mini that is not the panel

- **Tab switching passes here**: click → committed p95 11.1–12.4 ms on the laptop against 20.87 ms on the Mac mini, same release framework, both at 60 Hz, the laptop under 10× the load. The 3.3b profile put a third of a switch in the old page's compositor teardown (a synchronous call to the GPU process) and the display cycle: the M1 Max's GPU (32 cores) and the XDR (6K panel, 3008 × 1692 points) against the M4's (10 cores) and a 4K panel at 1920 × 1080 points are the obvious differences; not profiled.
- **Main-thread AppKit work is ~2× slower**: the 500-entry sidebar's full reload 95–100 ms (44), select 7.5–7.8 ms (3.5), drops and inserts ~2×; the first space switch per space 13.5–16.4 ms of code. M1 single-core against M4 plus load ~95; the per-key palette costs (later keys p95 14–15 ms vs 9.8) follow.
- **Memory is lower for real sites**: ten loaded sites 3.5–4.2 GB against 4.8 GB (release); this laptop's DNS blocker sinks ad hosts (B-3), so the pages load less; not verified per site. The local colour pages (spaces, 5.0 GB for 50) and the baseline (734 vs 559 MB) do not show it.
- **Quit under load**: 0.62–2.17 s at load1 97–101 (Mac mini 0.24–0.30 s quiet).
- **The copied Debug app** only half works here (`#filePath` fixtures); the laptop's `build/roomcore` held a stale stage. Both in `docs/laptop-build.md` now.

## Phase 4.1a — the Archive, the sweep, the Library (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

Conditions: the Claude desktop app frontmost; no Chromium build; no other Room running (the tour's new conditions line); the main display as in 3.9-2 (the `display.tsv` of each run). Dev build = `build/roomcore` (component `out/dev`), release = the Debug app over the staged release framework (`build/roomcore-release`, `ROOM_TOUR_APP`).

### Tour step `archive` (group `lifecycle`), light

| Run | Build | load1 at start | Checks | Step time | launch → spike | Minidumps |
|---|---|---|---|---|---|---|
| `build/grand-tour/20261006-162023-roomcore` (with `killtest`) | dev, c6c1731 | 6.83 | **28 / 28** | 18.9 s | 8.09 s | 0 |
| `build/grand-tour/20261006-162512-roomcore` | release framework, c6c1731 | 6.28 | **28 / 28** | 13.6 s | 2.24 s | 0 |

Every check's result line (identical on both builds):

    - pass — exit 0
    - pass — no crash report
    - pass — no Room left running
    - pass — spike reached its end
    - pass — no error lines
    - pass — no capture timeouts
    - pass — window main
    - pass — the clock is injected (-RoomClock)
    - pass — launch sweep archives the five old Today tabs
    - pass — the selected, split-with-pinned and young tabs stay
    - pass — the archive's rows are reason auto
    - pass — the rows are in the database
    - pass — 13 h later the young tabs go
    - pass — the selected and split tabs still stay
    - pass — the Library replaces the spaces view
    - pass — the Library lists the seven rows by reason
    - pass — Restore from the Library: back at the top of its space, selected, the row gone
    - pass — Clear writes its tabs to the Archive (reason clear) with the Undo toast
    - pass — one clear row per Today tab
    - pass — Clear's Undo puts the tabs back and takes the rows out
    - pass — the palette's History row has the Archived chip
    - pass — Enter on it restores the tab to its space, selected
    - pass — Delete Space
    - pass — Delete Space archives its entries (B-15)
    - pass — its Undo brings the space and takes the rows out
    - pass — ⌘Y opens the Library at History
    - pass — Esc returns to the spaces
    - pass — Clear Archive empties the table

The spike's result lines on the release framework (the dev build's differ only in the date, the load and the clock offset, 7192 vs 7197 s):

    clock: injected=true offset_s=7197 store=2026-10-06T15:25:13Z
    launch_sweep: archived=5 [Old 1,Old 2,Old 3,Two Old A,Two Old B]
    launch_sweep_kept: Selected=true Split=true Young=true Two Young=true
    archive_rows: 5 auto=5 clear=0 spaceDeleted=0 windowClosed=0 manual=0
    database_archive_rows: 5
    sweep_after_13h: archived=2 [Two Young,Young]
    sweep_after_13h_kept: Selected=true Split=true
    library_shown: true
    library_rows: archive=7 (auto=7 clear=0 spaceDeleted=0 windowClosed=0 manual=0) downloads=0 history=0 history_archived=0 days=2
    capture_library: phase-4.1a-library.png
    library_restore: space=Two top=true selected=true row_gone=true library_still_shown=true
    clear: today_before=2 rows_clear=2 done=true toast=2 tabs closed
    clear_undo: today=2 rows_clear=0
    palette_archived_row: title=Archive Fixture Old 1 chip=Archived group=history
    palette_highlighted: true
    palette_restore: selected=true space=Space row_gone=true
    delete_space: entries=2 rows_spaceDeleted=2 space_gone=true toast=Deleted “Two”
    delete_space_undo: space_back=true rows_spaceDeleted=0
    cmd_y: library_shown=true history_expanded=true search_has_keyboard=true
    esc_returns: library_shown=false
    archive_rows_before_clear_archive: 5 auto=5 clear=0 spaceDeleted=0 windowClosed=0 manual=0
    clear_archive: rows=0 database_rows=0
    end: archive

The Library with the seven `auto` rows: `research/screenshots/phase-4.1a/library-light.png` (dev run; evidence, not an assertion).

### Kill test with the Archive (`--only killtest`, dev run above)

    summary: 100 kills in 83.049738375 seconds, 0 failures
      kills with a transaction in flight: 54 (rolled back to the previous generation: 54)
      reopened ahead of the last ack (committed, ack not yet read; informational): 0
      reopened behind the last ack (an acknowledged write lost): 0
      final generation 106, 106 commits, 70 entries, 18335 archived, database 17752 KB
      commit time median 11.408 ms, p95 15.672 ms, max 38.675 ms

Checks 7 / 7, including the renamed "no reopen behind the last ack (no acknowledged write lost)" (B-79). The harness now archives (2 % of steps), restores from the Archive (2 %), and Clear and Delete Space write rows, so the Archive grew to 18,335 rows in 100 writers: commit median 11.4 ms against 3.9-2's 5.91–8.31 ms without it (B-80; a fast path for an unchanged Archive measured no change: 11.59 ms, reverted). The failing direction is covered by `scripts/tests/test_tour_checks.py` (3 tests: ahead informational, behind fails, missing line fails) and by `verify`, which already failed a round whose reopened generation is behind the last ack and now counts it.

### B-78

`scripts/run-spike.sh hidden -RoomStateDirectory /tmp/room-b78` (no `-RoomEngineDirectory`, dev build): `/tmp/room-b78/engine` holds the engine root (`Local State`, `Room Profile Default`, `Crashpad`, …); `~/Library/Application Support/Room/RoomCore/RoomCore.log` mtime 1791239540 (Oct 6 01:32:20) before and after.

### Unit tests (`CI=1 swift test`)

Model 83, Store 41, Tabs 63, Sidebar 38, Palette 24, Omnibox 45, UIKitCore 47, Chrome 51, Design 9, Library 2 (new): all pass; `room-persistence-harness` builds (release).

## Phase 4.1b — backups, crash recovery, `Profile.removeDownload`; the incremental official build (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

### The engine step: `//room` incremental, package, baseline (dev, before the official build started)

`ROOM_BUILD_JOBS=6 scripts/roomcore-build.sh` after the `removeDownload` change (4 `//room` files, +23 lines): "patches: 0 applied, 23 already on the room branch", **"build done in 59 s"** (89 s with the apply step; load 2.97 → 4.33). `scripts/roomcore-package.sh` 55 s (host 29.1 s, app 15.7 s). `scripts/roomcore-baseline.sh build/evidence-4.1b/baseline-1` (load 5.5–8.6, no other build): nav **passed** (16.36 s); ten-page quits **0.277 s** (load1 5.47) and **0.283 s** (6.66), helpers left 0, 0 new crash reports, exit 0; run 3 stopped twice at "ten-page fixture incomplete" with stackoverflow.com on Cloudflare's "Just a moment..." (`loading-at-ready 1`; the 3.4a-2 condition), then `quit-timing.sh 1` passed: **0.298 s** (load1 8.60), helpers left 0, 0 crash reports (`baseline-1/quit-run3-rerun2.txt`).

### Download Remove and Clear across a relaunch (B-59)

`scripts/download-remove-check.sh <dir>` (new): `chromesurfaces2 -RoomSpikeOnly downloadremove` on a fresh state (the 2.6 test server; a 20 KB file removed through `LibraryController.removeDownload`, a second through `DownloadList.clear`, a 3 MB file kept), then `-RoomSpikeOnly downloadsrestore` on the same state.

Dev build (`build/evidence-4.1b/download-remove-dev`; the official build compiling beside it, load1 5.68):

    download_remove: library removed=true rows after=0 cleared=true rows before clear=1 after=0 kept=room-2.6b-unknown.bin rows=1
    download_restored: rows=1 room-2.6b-unknown.bin:complete:canResume=false
    minidumps: 0
    result: passed (only the kept download is listed after the relaunch)

Before this change the relaunch listed every download Chrome's `DownloadHistory` held (3.4a's B-28 check: 5 of 5 after Clear).

Release framework (`ROOM_APP=build/roomcore-release/DerivedData/Build/Products/Debug/Room.app`, restaged from the new `out/release` by `roomcore-package.sh --release`, `RoomCoreCommit ccb9ff0`; `build/evidence-4.1b/download-remove-release`, load1 8.89, no build running):

    download_remove: library removed=true rows after=0 cleared=true rows before clear=1 after=0 kept=room-2.6b-unknown.bin rows=1
    download_restored: rows=1 room-2.6b-unknown.bin:complete:canResume=false
    minidumps: 0
    result: passed (only the kept download is listed after the relaunch)

### Tour step `recovery` (group `lifecycle`; `scripts/recovery-check.sh`, spike `recovery` in two launches)

**18 / 18 on the dev build** (`build/grand-tour/20261006-173552-roomcore`, 22 s, load1 3.62, no build running, 0 minidumps) and **18 / 18 on the release framework** (`build/grand-tour/20261006-173512-roomcore`, 17 s, load1 3.76; the first release run `20261006-172320` also 18 / 18). The dev run's lines:

    prepared: spaces=Recovery Kept,Recovery Gone entries=6 selected=Room Test Site loaded=1
    backup_taken: Room-2026-10-06T14-36-20.229Z.sqlite entries=6 spaces=2 generation=13
    deleted: space_gone=true entries=3 archived=3 generation=14
    kill_now: 84181
    killed: 84181 with SIGKILL at 1791297380.290
    == check
    previous_exit: store_unclean=true clean=false (store uncleanExit=true, engine lastExitWasClean Default=false)
    crash_recovered: true toast=none logged=true
    restored_unloaded: entries=3 loaded=0 selected=Room Test Site card=card-empty-state
    click_loads: loaded=1 selected_loaded=true
    restore: ok=true space_back=true entries=3 database_space=true database_entries=3 generation=14->16 toast=Sidebar restored from 6 Oct 2026 at 17:36
    before_restore_backup: count=1 entries=3
    after_restore: spaces=Recovery Kept,Recovery Gone active=Recovery Kept selected=127.0.0.1:8770/site.html?recovery=kept1 loaded=1 footer_spaces=2
    backups: files=4 before-restore:3e/1s/g15,rolling:3e/1s/g14,rolling:6e/2s/g13,rolling:6e/2s/g10
    launch_backup: Room-2026-10-06T14-36-24.790Z.sqlite generation=14 4.8 ms

The toast "Room restarted after a crash" (2 s, `Timing.toast`) is usually gone by the time the spike reads it (`toast=none`; it read the toast in the first standalone run); the check reads the launch log's line, written when the toast is shown (`logged=true`). The restore's generation moves by two: the unloads' navigation states flushed, then the restore's one write. `window_main: false` in every run (the Claude app frontmost; the check is not in this step).

The first standalone run of the check crashed the dev build at Restore (`FATAL:chrome/browser/ui/browser.cc:645] Check failed: !IsDeleteScheduled()`, a `DUMP_WILL_BE_CHECK`, a dump without a crash on the release build): unloading every page empties the window's `Browser` strip, Chrome schedules its deletion, and the restored selection's page joined it in the same turn, because `RoomCoreProfile` retires a `RoomBrowser` only at `browserDidClose`. EngineRoomCore is frozen after the official build started: the restore holds a hidden blank page per engine profile in the window until the selection has its page (B-81).

The launch backup: 2.0–4.8 ms for a 3–6-entry state (`VACUUM INTO` on the writer connection, off the main thread); none on a never-written state (generation 0).

### Memory pressure across two spaces (`discardspaces`, `ROOM_SL_ONLY=discardspaces scripts/session-lifecycle.sh`)

Space 1: a1, a2; space "Two": b1, b2, a playing tone; back in space 1, a3 opened and selected; last seen a1 < b1 < b2 < tone < a2. Critical pressure, the host's policy on.

Dev (`build/evidence-4.1b/discardspaces-dev`, load1 4.8; Chromium's own notification through the spike hook):

    twospaces_pages: a1@space1 a2@space1 b1@space2 b2@space2 tone@space2 a3@space1 selected=a3 active_space=1
    twospaces_pressure: source=chromium=2 discards=a1@20ms,b1@1049ms,b2@2043ms,a2@3044ms
    twospaces_order: a1,b1,b2,a2
    twospaces_states_after: a1=discarded a2=discarded b1=discarded b2=discarded tone=alive a3=alive
    twospaces_kept: a3_selected=alive tone_audible=alive audible=true

Release framework (`build/evidence-4.1b/discardspaces-release`, load1 3.7; no spike hooks in the official framework, so the level goes to the host's policy directly):

    twospaces_pressure: source=host discards=a1@10ms,b1@1027ms,b2@2026ms,a2@3032ms
    twospaces_order: a1,b1,b2,a2
    twospaces_states_after: a1=discarded a2=discarded b1=discarded b2=discarded tone=alive a3=alive
    twospaces_kept: a3_selected=alive tone_audible=alive audible=true

Least recently seen first across both spaces, one page a second (`Timing.criticalPressureStep`), the selected page and the audible one never; 0 minidumps on both. The first release run called the dev-only `roomSpikeAction:` and crashed on an unrecognized selector (the 3.7b `discardpolicy` spike does the same on the release framework, B-82); the spike now checks the hook first.

### Kill test after B-73 and B-80 (`scripts/grand-tour.sh --no-build --only killtest light`, dev, `build/grand-tour/20261006-172052-roomcore`)

    summary: 100 kills in 83.113661583 seconds, 0 failures
      kills with a transaction in flight: 54 (rolled back to the previous generation: 54)
      reopened ahead of the last ack (committed, ack not yet read; informational): 0
      reopened behind the last ack (an acknowledged write lost): 0
      final generation 106, 106 commits, 49 entries, 18348 archived, database 17460 KB
      commit time median 11.671 ms, p95 16.646 ms, max 39.387 ms

7 / 7 checks with the harness's `snapshotHash` blanking the navigation states too (B-73). Commit time unchanged against 4.1a (11.41 / 15.67 ms): the harness archives at its own present, so the 30-day retention prunes nothing in an 83 s run, and the 18k rows (2 % of steps archive) are still diffed on every commit; in use the Archive holds at most 30 days of rows and the rows past 7 days carry no navigation state. The diff cost stays 5.4's (B-80).

### The JSON snapshot without navigation states (B-73)

510 Today entries each with an 8.1 KB state (3.7b's worst case; a throwaway Model test, not committed): the snapshot **5,762,018 B before, 157,246 B after**; encoding it 17.4 → 4.3 ms (Debug test build, 20 encodes each). 3.7b's measured file on the 50k state was 5.66 MB.

### Tour step `archive` after the retention (dev and release)

27 / 28 on both (`20261006-173552` dev, `20261006-173512` release): the one failure is `window_main: false` (the Claude app frontmost). Before a spike fix, 25 / 28: the selected fixture tab loaded and took its page's title, so the spike's title lookup missed it ("Selected=false"); the 4.1a app built from `aecd3c5` gave the same 25 / 28 on this machine today, so it was the run's condition, not the retention; the spike now finds the fixture's tabs by URL too.

### Unit tests (`CI=1 swift test`)

Model 92 (+9: the backup planner ×6, the backup file, the snapshot without states, the retention rule), Store 43 (+2: restore, retention), Tabs 64 (+1: crash recovery), Chrome 52 (+1: Remove), Engine 59 (+1: FakeEngine's remove), Sidebar 38, UIKitCore 47, Design 9, Library 2: all pass; `scripts/tests/test_tour_checks.py` OK.

## Phase 4.2 — space routing, the routing sheet, Peek's last gaps (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

No engine step: `//room`, `Engine/roomcore` and `Packages/EngineRoomCore` untouched; every app build is `xcodebuild` over the staged frameworks (the dev framework `build/roomcore`, `RoomCoreCommit ccb9ff0`; the release framework `build/roomcore-release`, restaged in 4.1b). Display: the Mac mini's 3840 × 2160 main display, the window at its spike size; the Claude app frontmost during the runs (`window_main: true` in every run below). Evidence in `build/evidence-4.2/` (the four tour runs' summaries and step files under `tours/`).

### B-82: spike hooks on the release framework

`ROOM_APP=<the Debug app over build/roomcore-release> ROOM_SL_ONLY=discard scripts/session-lifecycle.sh` (3.7b's `discardpolicy`, which calls `roomSpikeAction:` five times; load1 8.7): the spike ran to `end: discardpolicy` with no crash; `spike_hooks: spike hooks unavailable (roomSpikeAction: on RoomBrowser)` once, the hook results `-98` (`auto_discardable_pages`, `pm_urgent_discard`, `pressure_policy_off`), the host-side parts unchanged (`idle_discarded: plain3,plain2,plain1`, `b56_renderers: before 10 (1452 MB) … discarded 3`). Before the guard this run crashed on the unrecognized selector (4.1b). `build/evidence-4.2/b82-discardpolicy-release.txt`.

### Tour step `routing` (group `appintegration`; `scripts/routing-check.sh`, fixture `routing`)

External links are handed to Room by calling `AppDelegate.application(_:open:)` in the spike with the URL: the delegate method AppKit calls for `open -a`, AppleScript's `open location` and another app's link, which hands them to `URLInbox` (2.8b measured those three hand-overs into the same method). Fixture: spaces Space (shown), Work, Play in one profile; rules 1. `contains` "route=work" → Work, 2. `equals` "localhost" → Play, 3. `contains` "site.html" → Work, disabled.

**25 / 25 on the dev build** (`build/grand-tour/20261006-182329-roomcore`, 26 s, load1 4.17, no other Room, no Chromium build, 0 minidumps) and **25 / 25 on the release framework** (`20261006-182433-roomcore`, 16 s, load1 7.35, 0 minidumps). The release run's lines (the dev run's are the same):

    rules: 1. contains route=work → Work | 2. equals localhost → Play | 3. contains site.html → Work (disabled)
    invalid_regex: refused=true rules 3 → 3 message=Not a valid regular expression (The value “([a-z” is invalid).
    external_rule_contains: space=Work selected in its space=true shown space=Space in the card=false page=http://127.0.0.1:8770/other.html?route=work toast="Opened in Work" button=Switch
    external_rule_equals: space=Play selected in its space=true shown space=Space in the card=false page=http://localhost:8770/other.html?n=1 toast="Opened in Play" button=Switch
    external_no_rule: space=Space selected in its space=true shown space=Space in the card=true page=http://127.0.0.1:8770/site.html?plain toast=none
    toast_switch: shown space=Work card=the routed tab page=http://127.0.0.1:8770/other.html?route=work&n=2
    external_most_recent: space=Work selected in its space=true shown space=Work in the card=true page=http://127.0.0.1:8770/other.html?recent toast=none
    external_chosen_default: space=Play selected in its space=true shown space=Work in the card=false page=http://127.0.0.1:8770/other.html?chosen toast="Opened in Play" button=Switch
    cross_space_off_blank: space=Space … in the card=true page=…?route=work&from=page1 toast=none under its opener=true
    cross_space_on_blank: space=Work selected in its space=true shown space=Space in the card=false page=…?route=work&from=page2 toast="Opened in Work" button=Switch under its opener=false
    cross_space_on_command_click: space=Work selected in its space=true shown space=Space in the card=false page=…?route=work&from=page3 toast="Opened in Work" button=Switch
    cross_space_on_no_rule: space=Space … in the card=true page=…?from=page4 toast=none under its opener=true
    sheet: shown=true editing=true match=contains pattern=127.0.0.1 target=Space rules listed=3
    sheet_try_url: localhost:8770/anything → Opens in Play (rule 2); example.com → Opens in the default: Space
    sheet_invalid_regex: inline=Not a valid regular expression (The value “([a-z” is invalid). save refused=true rules=3
    sheet_save: saved=true rules=4 last=contains 127.0.0.1:8770/sheet → Space
    sheet_closed: true
    rules_in_database: 3 of 3

The routed tabs load behind the card (`page=` is the loaded page's URL). The sheet's capture: `captures/routing/phase-4.2-routing-sheet.png` in each run (eyes only).

### The Peek table (2.7a's `layoutmodes`, `--only layoutmodes light`)

**35 / 35 on the dev build** (`20261006-182456-roomcore`, 78 s, load1 7.12) and **35 / 35 on the release framework** (`20261006-182620-roomcore`, 71 s, load1 4.47); 0 minidumps in both. Five checks are new (Open as Tab's selection, its placement under a pinned and under a Today parent, B-35's fullscreen and its exit).

| Number (n=5, local page, from the Peek decision) | dev build | release framework |
|---|---|---|
| to the overlay's first committed frame | median 24.47 ms, p95 25.02 ms | median 24.18 ms, p95 26.63 ms |
| to the Peek page's first contentful paint (B-57) | median 454.49 ms, p95 503.10 ms | **median 69.54 ms, p95 70.89 ms** |

B-57 is closed as a dev-build condition (69.54 ms against 150 ms; the dev build's cost is the component framework's renderer launch, 3.3b).

    peek_open_as_tab_placement: parent=pinned index in Today=0 under the parent=true
    peek_open_as_tab_today_parent: parent index=1 new tab index=2 directly under=true today=5
    peek_fullscreen: request="ok" Peek gone=true today 1 → 2 card page is the Peek's=true index in Today=0 window fullscreen=true page fullscreen=true document.fullscreenElement="true" entered=true
    peek_fullscreen_exit: window back=true the tab stays=true

(the same lines on both builds). Before the fix's second part (the card taking the page before the Peek overlay lets go of it), the same check read `window fullscreen=true page fullscreen=false document.fullscreenElement="false"`, then `window back=false`: the host's events were `cardDidShow, enter, exit` — Chromium ended the page's fullscreen at once while its view was out of the window, and the window stayed fullscreen (B-83).

### Unit tier and the kill test

`CI=1 swift test`: Model 104 (92 before: the v8 migration, the snapshot's rules, 9 routing rule and decision tests), Store 45 (43: rules CRUD and refusal; deletion with Undo), Tabs 70 (64: four routed-link tests, B-35's expansion, Open as Tab under a Today parent), Sidebar 38, Integration 10; all passing. The engine-free CI build and tests (`xcodegen/ci.yml`, `CI=1`): BUILD and TEST SUCCEEDED in 49 s. The kill test with routing-rule mutations in the writer's mix (`scripts/persistence-kill-test.sh 20 300 4201`): 20 kills, 0 failures, commit median 10.38 ms, p95 15.13 ms.

## Phase 4.3a — import: readers, plan, sheet (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

No engine step: `//room`, `Engine/roomcore` and `Packages/EngineRoomCore` untouched (the series 23); every app build is `xcodebuild` over the staged frameworks (dev `build/roomcore`, `RoomCoreCommit ccb9ff0`; release `build/roomcore-release`). Display: the Mac mini's main display; `window_main: true` in every run. Never a real browser profile: every reader ran on `research/spikes/phase-4.3` (README there). Evidence in `build/evidence-4.3a/tours/`.

### The fixtures

| Fixture | Bytes | Content |
|---|---|---|
| `chrome/Default/History` (Chrome 154.0.8037.98 headless, then six rows by sqlite3) | 163,840 | 11 URLs, 17 visits (meta version 70) |
| `chrome/Default/Bookmarks` | 18,567 | 31 links, 9 folders (7 levels deep), 3 duplicates by normalised URL, 1 `javascript:` |
| `chrome/Profile 1/Bookmarks` | 1,364 | 1 link |
| `chrome/Default/Preferences` | 1,325 | 3 extensions (1 unpacked) |
| `chrome/Local State` | 431 | 3 profiles (1 without a directory) |
| `safari/Bookmarks.plist` (binary) | 1,920 | 10 links, 4 folders (Reading List one), 1 leaf without a URL, 1 proxy |
| `safari/History.db` | 36,864 | 5 items, 7 visits (1 failed load) |
| `arc/StorableSidebar.json` | 13,453 | 3 spaces, 2 profiles, 3 essentials, 6 pinned in 2 folders, 3 Today tabs, an easel, a tab without a URL |
| `netscape/bookmarks.html` | 1,628 | 7 links, 3 folders, an anchor without HREF, a `place:` query |

Making the History fixture: `research/spikes/phase-4.3/make-history.sh` (7 headless runs × 12 s on `/tmp/room-4.3/chrome`, 84 s wall); with 4 s per run Chrome had not committed and `History` was empty (the backend commits on a timer), so the script holds each page 12 s. Chrome headless takes one target per run ("Multiple targets are not supported in headless mode").

### Tour step `import` (group `appintegration`; `scripts/import-check.sh`, `-RoomImportSource research/spikes/phase-4.3`, fixture `import`)

**31 / 31 on the dev build** (`build/grand-tour/20261006-192250-roomcore`, 8 s, load1 8.54, no other Room, no Chromium build, 0 crash reports) and **31 / 31 on the release framework** (`20261006-192259-roomcore`, 6 s, load1 8.29, 0 crash reports), the final code. Earlier runs, 31 / 31 each: dev `20261006-191442`, `-191536`, `-191942` (load1 24.08 after two builds), release `-191959` (load1 21.11); the counts were identical in all six, the times within the spread below.

| Step (final runs) | dev build | release framework |
|---|---|---|
| Chrome read (bookmarks / extensions / history) | 2.2 ms (0.3 / 0.1 / 1.8) | 5.4 ms (0.7 / 0.3 / 4.1) |
| Safari read (bookmarks / history) | 1.8 ms (0.2 / 1.5) | 4.7 ms (0.2 / 4.5) |
| Netscape read | 0.9 ms | 0.5 ms |
| Arc read (sidebar) | 0.5 ms (0.3) | 0.5 ms (0.3) |
| Plan (Chrome / Safari / Netscape / Arc) | 0.33 / 0.12 / 0.08 / 0.33 ms | 0.33 / 0.10 / 0.07 / 0.21 ms |
| Import: Chrome (sidebar + flush + 1 history batch) | 98 ms | 89 ms |
| Import: Safari (5 spaces + flush + 1 batch) | 33 ms | 38 ms |
| Import: Netscape / Arc (sidebar + flush) | 26 / 9 ms | 25 / 10 ms |

Reads include the SQLite copies into a temporary directory. The release run's lines (the dev run's counts are identical; the two `generation_*` lines are in the final runs only):

    sheet_open: shown=true picked=none fixtures=arc (fixture),chrome (fixture),netscape (fixture),safari (fixture)
    detected_installs: Google Chrome,Brave,Microsoft Edge,Vivaldi,Arc,Safari        (directories that exist; nothing read)
    read_chrome: bookmarks=31 folders=9 skipped=0 history=10 visits=16 extensions=2 skipped=1 errors=0 profiles=Person 1/Work
    read_safari: bookmarks=10 folders=4 skipped=1 history=4 visits=6 errors=0
    read_netscape: bookmarks=7 folders=3 skipped=1 errors=0
    read_arc: arc spaces=3 profiles=2 essentials=3 pinned=6 folders=2 today=3 skipped=2 errors=0
    nothing_before_import: unchanged=true generation 0 → 1 dirty=false spaces=1 profiles=1 folders=0 pinned=0 essentials=0 today=0
    chrome_preview: spaces=1 profiles=0 folders=7 pinned=15 essentials=12 today=0 history=9 visits=15 duplicates=3 flattened=2 overflow=2 skipped=3
    chrome_applied: spaces=1 profiles=0 folders=7 pinned=15 essentials=12 today=0 equal=true history urls=8 visits=12 expired=2/1
    toast: "Imported from chrome (fixture): 1 space, 15 pinned tabs, 7 folders, 12 essentials, 8 history pages"
    essentials_cap: essentials=12 cap=12 overflow=2 overflow pinned=Site 11,Site 12
    depth_clip: max depth=5 flattened=2 L5 holds=Level 5,Six,Seven
    safari_preview: spaces=5 profiles=0 folders=0 pinned=8 essentials=0 today=0 history=4 visits=6 duplicates=2 flattened=0 overflow=0 skipped=2
    safari_applied: spaces=5 … equal=true history urls=4 visits=5 expired=1/0
    safari_spaces: Space,Google Chrome,Safari,Dev,Recipes,Reading List,Travel
    netscape_preview: spaces=0 profiles=0 folders=3 pinned=5 essentials=0 today=0 … duplicates=1 skipped=2
    netscape_applied: … equal=true
    arc_preview: spaces=3 profiles=1 folders=2 pinned=7 essentials=1 today=2 … duplicates=2 overflow=2 skipped=2
    arc_applied: … equal=true
    arc_spaces: Home icon=🏠 colors=#3366CC profile=Default pinned=4 today=1 | Work icon=💼 colors=#CC4D33 profile=Work pinned=1 today=1 | Side icon=none colors= profile=Default pinned=1 today=0
    arc_profiles: profiles=Default,Work work profiles=1 work essentials=Chat
    history_search: Typed three times=https://example.org/typed visits=3 typed=3 | Import fixture Gamma=http://127.0.0.1:8780/gamma.html?q=1 visits=1 typed=0 | Swift.org=https://swift.org/ visits=1 typed=0 | Old and new=https://www.example.com/old visits=1 typed=0
    database: entries 62 of 62, spaces 10 of 10, profiles 2 of 2
    sheet_closed: true

Reading them: the persistence generation moved 0 → 1 while the sheet opened (`generation_at_start: 0 dirty=true`, `generation_sheet_open: 1 dirty=false`: a write the launch had pending before the sheet existed landed then), but the sidebar's content hash (profiles, spaces, entries) did not change and nothing was dirty; Chrome's history: 9 URLs planned (the hidden subframe left out by the reader, `chrome://settings/` by the plan), the engine took 8 URLs and 12 visits and counted 2 visits and 1 URL as older than its 89 days (the reload visit is not a visit, `HistoryImportEntry`); Safari's 100-day visit likewise; Safari's preview has 2 duplicates in the tour (Alpha is one of the profile's essentials after Chrome's import) against 1 on a fresh state (the unit test); Arc's two default-profile essentials found the grid full (12 after Chrome) and were pinned in Home. Captures (eyes only): `captures/import/phase-4.3-import-preview.png` (the sheet with Chrome's preview) and `phase-4.3-import-done.png` in each run.

### Unit tier (`CI=1 swift test`)

Import 25, Model 104, Store 47 (2 new: `applyImport`), Tabs 70, Omnibox 45, Design 9, Palette 24: all passing. The engine-free CI build and tests locally (`xcodegen/ci.yml`, `xcodebuild build test`): succeeded in 73 s, the Import tests found their fixtures under `xcodebuild test` (25 passed).

## Phase 4.3b — passwords through Chrome's importer, extensions through their store pages, first run, Firefox, import at scale (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

The engine step (`Profile.importPasswords`, `//room` `room_passwords.mm`; B-81 in `EngineRoomCore`), then app work over the staged frameworks: dev `build/roomcore` (`out/dev` after the member) and release `build/roomcore-release` (the official incremental below, `--release` restaged; the Debug app over it per `docs/laptop-build.md` §A step 3). The Claude app frontmost during the session; the user's own Room not touched; every launch on a state under `/tmp`; never a real browser profile (Safari, Arc, Firefox and Chrome were detected on a fake home holding the fixtures).

### The engine step

- Dev incremental after the change: **91 s** of build (133 s with the apply step; the `BUILD.gn` change regenerated the ninja files), `patches: 0 applied, 23 already`; `roomcore-package.sh` 51 s.
- Baseline (`build/evidence-4.3b/baseline-1`, dev, embryo host, load1 11.5–16.3, the official build not yet started): **nav passed** (19.7 s); ten-page quits **0.387 / 0.347 / 0.319 s**, helpers left 0, 0 new crash reports, exit 0 each.
- The official incremental (`build-log.md` "Phase 4.3b"): **538 s of build, 9 min 39 s wall**, the ThinLTO link 407 s at 7.95 GiB, the export-order check passed (no new class: the answer is an `NSDictionary`, B-77); `--release` 125 s.

### `Profile.importPasswords` (`scripts/passwords-autofill.sh` with `ROOM_PA_ONLY=import`: `-RoomPasswordsPhase import`, then the relaunch's `fill`; the 3.7a server on :8772/:8773)

Fixtures `research/spikes/phase-4.3/passwords-saved.csv` (alice `secret-a0` on 127.0.0.1:8772, standing for a saved password) and `passwords.csv` (alice `secret-a2` on 127.0.0.1:8772: the conflict; bob on localhost:8772; carol on https 127.0.0.1:8773; one row whose URL does not parse). The engine's answers, identical on both builds:

| Pass | Dev (`build/evidence-4.3b/pw-dev-1`, load1 10.2) | Release (`pw-release-1`, load1 15.0) |
|---|---|---|
| `passwords-saved.csv`, `.skip` | success, imported 1 — **2,434 ms** (the presenter's first load and the sandboxed CSV parser's first launch) | success, imported 1 — **38 ms** |
| `passwords.csv`, `.skip` | success, **imported 2, conflicts 1 kept, skipped 1** (`alice@http://127.0.0.1:8772=conflictKept`, `mallory@not a url=invalidURL`) — 1 ms | the same — 1 ms |
| `passwords.csv`, `.replace` | success, **imported 3 (bob and carol counted as already saved, alice replaced), conflicts 1 replaced 1**, skipped 1 — 1 ms | the same — 0 ms |
| a second import while one runs | `first=success second=busy` | the same |
| a CSV without Chrome's header | `badFormat` | the same |

After the relaunch (`fill`): **site A fills alice with `secret-a2`** (`username_matches=true password_matches=true`, the popup 81 ms dev / 35 ms release after the click), **site B fills bob** (23 / 22 ms), both sign in ("Signed in as alice", "… bob"), `chrome://password-manager` lists both hosts. `Login Data` after the runs: 127.0.0.1:8772 alice, 127.0.0.1:9 zed (the busy check's first import), localhost bob, https 127.0.0.1:8773 carol, each password 19 bytes encrypted (mock keychain). Net-log: 0 engine requests in both launches on both builds (the import's launch 0 URL requests at all; the fill launch 9, all page traffic). Captures (dev): `research/screenshots/phase-4.3b/phase-4.3b-dev-import-fill-popup-{a,b}.png`, `…-password-manager.png`.

### B-81 (`scripts/recovery-check.sh`, tour step `recovery`)

The first form (the `RoomBrowser` dropped from `RoomCoreProfile.browsers` at `browserWillClose`) crashed the check launch at Restore Sidebar on dev: SIGBUS in `RoomBrowserWindow::~RoomBrowserWindow` ← `BrowserManagerService::DeleteBrowser` ← `UnloadController::OnWindowCloseComplete` (the wrapper's dealloc reset the window's client, which the destructor then called), `build/evidence-4.3b/tours/20261006-200130-roomcore` 13 / 19. The kept form (retired from `browsers` at `browserWillClose`, retained in `closingBrowsers` until `browserDidClose`), with 4.1b's hidden holder pages removed from `restoreSidebar`: **18 / 18 on dev** (`20261006-200304-roomcore`, load1 7.4, no `browser.cc:645` DCHECK, 0 minidumps) and **18 / 18 on the release framework** (`20261006-200337-roomcore`, load1 7.7, 0 crash reports).

### Tour step `import` (extended: 31 → 51 checks)

`scripts/import-check.sh`: the fixtures with `-RoomImportSource`, a fake home under `/tmp/room-4/importhome.*` (`-RoomImportHome`: Safari's files at `Library/Safari`, Arc's at `Library/Application Support/Arc`, Firefox's profile at `Library/Application Support/Firefox/Profiles/x1y2z3.default-release`, Chrome's at `Library/Application Support/Google/Chrome`) and `-RoomWebStorePage file://…/webstore/detail.html?id={id}` (no store request). **51 / 51 on dev** (`build/grand-tour/20261006-201515-roomcore`, 0.3 min, load1 10.5, `window_main: true`, 0 minidumps) and **51 / 51 on the release framework** (`20261006-201534-roomcore`, 0.2 min, load1 9.6, 0 crash reports). The two runs before the last code change (`200827` dev, `200907` release): 50 / 51 each, the failure `window_main: false` (the Claude app frontmost). Copies in `build/evidence-4.3b/tours/`. Every check, release run:

- exit 0
- no crash report
- no Room left running
- no error lines
- no capture timeouts
- spike reached its end
- window main
- the sheet opens over the window, nothing picked, the four fixtures listed
- Chrome's readers: Bookmarks, History, Preferences, Local State's profiles
- Safari's readers: plist, History.db
- the Netscape reader
- Arc's sidebar reader
- nothing is written before Import (four reads and previews)
- chrome: the store's rows after the import equal the preview
- safari: the store's rows after the import equal the preview
- netscape: the store's rows after the import equal the preview
- arc: the store's rows after the import equal the preview
- Chrome's preview: one space, the bar into Essentials, the clip, the duplicates
- Chrome's history into the engine (visits over 89 days counted out)
- the Essentials cap: 12, the rest pinned
- folders clipped at depth 5
- Safari: a space per top-level folder plus the target
- Safari's folders became spaces (the Reading List one of them)
- Netscape into Space: the essential Docs is a duplicate
- Arc's preview
- Arc's spaces with their icons, colours and profiles
- one Work profile (made or reused) with its essential
- imported history is found through ProfileHistory.search in the same launch
- the toast names the import
- the rows are in the database
- the sheet closes
- Firefox's places.sqlite reader
- firefox: the store's rows after the import equal the preview
- Firefox: the toolbar first, then the menu and Other Bookmarks, then mobile
- a passwords CSV alone can be imported
- the CSV's passwords through the engine's importer (the malformed row skipped)
- the toast names the passwords
- the Web Store extensions listed, the unpacked one skipped with its reason
- the summary names the store pages
- the first store page opens as a Today tab of the target space
- the next page waits while the first is open
- closing the page opens the next
- the sequence ends with its toast
- the sheet says cookies are not imported
- the browsers detected at their real paths (a fake home)
- Safari read from ~/Library/Safari
- Arc read from ~/Library/Application Support/Arc
- Firefox's profile found under Profiles/
- a file macOS refuses: the sheet offers the open panel
- Settings ▸ General ▸ Import… opens the sheet
- the first-run card's Import from another browser… opens the sheet

Numbers, release run (dev in parentheses): Firefox read 3.2 ms (2.5), plan 0.17 ms (0.09), import 87 ms (70) with one history batch; the passwords-only import through the sheet 36 ms (1,552 ms: the dev build's first password import in the profile); Chrome's import 101 ms (130). Spike lines (release):

    read_firefox: bookmarks=10 folders=3 skipped=1 history=4 visits=7 errors=0
    firefox_space: Firefox pinned=Firefox,MDN,Dev,Python,Recipes,News,Maps,On the phone
    passwords_chosen: line=passwords.csv: 4 rows phase=choosing can_import=true profile=Default
    passwords_sheet: status=success imported=3 conflicts=0 skipped=1 line=3 imported, 1 skipped
    passwords_toast: "Imported from passwords.csv: 3 passwords, 1 password row skipped"
    extensions_row: web_store=uBlock Origin,Bitwarden Password Manager chosen=2 skipped=[My Unpacked Tool: unpacked (loaded from a folder)] can_import=true
    extensions_import: pages_to_open=2 summary="Imported from chrome (fixture): 2 extension pages to open, one at a time"
    store_page_first: opened=1 pending=1 current=cjpalhdlnbpafiamejdnhcphjbkeiagm tab=today space=Space url=file:///…/webstore/detail.html?id=cjpal… new_tabs=1
    store_page_waits: new_tabs=1 opened=1 pending=1 (after 1.5 s)
    store_page_next: opened=2 pending=0 current=nngceckbapebfimnlniiiahkandclblb … first_tab_gone=true
    store_pages_done: finished toast="Extensions from the Web Store: 0 added, 2 not added"
    home_detected: home=fake Google Chrome=~/Library/Application Support/Google/Chrome Arc=~/Library/Application Support/Arc Safari=~/Library/Safari Firefox=~/Library/Application Support/Firefox
    home_safari: bookmarks=10 folders=4 history=4 visits=6 errors=0 needs_access=false
    home_firefox: bookmarks=10 folders=3 history=4 visits=7 profiles=default-release errors=0 needs_access=false
    permission_denied: needs_access=true error=true message=macOS keeps Room out of Safari's files. Click Choose a File or Folder… and choose its folder (…): choosing it there lets Room read it.
    settings_import: sheet=true
    first_run_import: card=true sheet=true

The install that moves the sequence on (`extensionsDidChange`) is the unit tier's (`StorePageSequenceTests`) and by-hand step 27's: a store install needs the Web Store and a click. Captures: the sheet with the Passwords box, the Extensions list and the access message, `phase-4.3b-import-{passwords,extensions,permission}.png` (in the run's capture directory).

### B-84: import at scale (`scripts/import-large.sh`, spike `importlarge`; `make-large.py`'s generated profile)

The generated profile (`research/spikes/phase-4.3/generated/large`, 17,212,909 bytes, not committed): **5,000 bookmarks in 200 folders** (40 top-level folders on the bar and in Other bookmarks, 4 subfolders each, 25 links per folder) and a Chrome `History` with **50,000 URLs and 100,000 visits** within the last 80 days. Imported into one new space in the default profile with history. The main thread's longest stall: the longest gap between 5 ms ticks of a main-actor task during each part. Release framework, two runs (`build/evidence-4.3b/importlarge-release-{1,2}.txt`, load1 7.3 and 6.6, no build running); dev once (load1 6.7):

| Part | Release run 1 | Release run 2 | Dev |
|---|---|---|---|
| Read (off the main thread): Bookmarks / History (copy + read) | 318 ms: 21 / 297 | 323 ms: 26 / 297 | 324 ms: 23 / 301 |
| Plan (off the main thread); a replan after an option change | 73 ms; 70 ms | 74 ms; 70 ms | 76 ms; 71 ms |
| Pick to plan, main thread's longest stall | 411 ms, **51 ms** | 415 ms, **51 ms** | 422 ms, 54 ms |
| Two option changes (two replans), longest stall | 192 ms, 27 ms | 191 ms, 26 ms | 187 ms, 21 ms |
| Import: the sidebar write (`applyImport`, 5,200 rows in one `SidebarChange`, and the flush) on the main thread | **568 ms** | **569 ms** | 573 ms |
| Import: 25 history batches of 2,000 URLs (`importEntries`, awaited) | **1,425 ms** | 1,439 ms | 2,378 ms |
| Import in all; main thread's longest stall | **2,025 ms; 604 ms** | 2,036 ms; 596 ms | 2,980 ms; 609 ms |
| The sidebar's full reload after (5,200 rows; five times) | 80.4, 80.3, 85.5, 84.8, 84.4 ms | 90.2, 81.4, 81.5, 83.0, 75.9 ms | 75.9–79.6 ms |
| Summed RSS before → after (6 processes, no renderer) | **334 → 497 MB** | 335 → 497 MB | 596 → 736 MB |

Every URL and visit reached the engine (`history urls=50000 visits=100000 expired=0/0`); `ProfileHistory.search("Large history page 49999")` finds it in the same launch; the database holds 5,200 of 5,200 entries (reloaded in 35 ms). Against the bounds (100 ms of main thread per step, 10 s in all): the whole import is 2.0 s (inside), reading and planning stay off the main thread (stalls ≤ 51 ms), **the sidebar's write blocks the main thread for ~570 ms** (5.7× the bound: B-85), and the reload of a 5,200-row sidebar is 80–90 ms (inside 100 ms, over a frame: the 2.2a number scaled).

## Phase 4.4a — shortcut remapping, Settings ▸ General, Search, Downloads (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

App work only (no `//room`, no `EngineRoomCore`, series 23): the Debug app on the dev framework (`build/roomcore`, `roomcore-package.sh --app-only`, 29–43 s) and the Debug app over the release framework (`build/roomcore-release`, `docs/laptop-build.md` §A step 3, 30 s). Display 1920 × 1080 @ 60 Hz; the Claude app frontmost (Room activated by `run-spike.sh`; every key press of the spike went through `NSApp.sendEvent`, "via=app"). Tour step `settings` = `scripts/settings-check.sh`: two launches on one state (`-RoomSpikeOnly set`, then `verify`), the 2.6 server on :8766 for the downloads.

| Run | Build | load1 at start | Checks | Tour directory |
|---|---|---|---|---|
| `settings` | dev | 7.61 | **32 / 32** | `build/grand-tour/20261006-211728-roomcore` |
| `settings` | release framework (`ROOM_TOUR_APP`) | 7.34 | **32 / 32** | `build/grand-tour/20261006-211823-roomcore` |
| `keys` (1.4's spike, no overrides) | dev | 10.31 | **19 / 19** | `build/grand-tour/20261006-211104-roomcore` |

The `settings` result lines (identical on both builds but for the timings):

- `defaults`: overrides 0, Pin Tab ⌘D, Reopen Closed Tab ⇧⌘T, 17 reserved keys, ⇧⌘T among them.
- `remap_pin` (a real ⌥⌘P key event into Pin Tab's recorder in Settings ▸ Shortcuts): recording=true, stored `togglePin:=⌥⌘P`, **menu ⌥⌘P, the palette's command ⌥⌘P, the sidebar's context menu ⌥⌘P**; `palette_hint`: the drawn row "Pin Tab" with hint **⌥⌘P** (`>pin`).
- `old_key`: **the page's keydown log `["⌘d/KeyD"]`: the old ⌘D reaches the page**, the tab stays a Today tab (`kind=today`).
- `new_key`: ⌥⌘P → the page saw `⌘⌥π/KeyP` first (Pin is page-first), then the menu: **pinned=true**; again: unpinned=true. The delegate's log: `unhandled keyCode=35 … | unhandled sent fresh handled=true` (B-86 below).
- `conflict`: ⌘P (Print's) for Pin → `conflict(["printPage:"])`, pending, **both rows marked** (`printPage:`, `togglePin:`), "⌘P is Print…'s shortcut. Use it for Pin Tab instead?"; `conflict_cancel`: Pin ⌥⌘P, Print ⌘P, nothing marked; `conflict_resolved` (Use for Pin Tab): **Pin ⌘P, Print none**, 0 conflicts.
- `refused`: ⌘Q ("⌘Q is Quit: it belongs to macOS."), ⌘H, K (no ⌘ or ⌃), Quit to ⌥⌘T refused; Pin and Print unchanged.
- `reserved_set`: Reopen Closed Tab under ⌥⌘T → the reserved set has ⌥⌘T, not ⇧⌘T, still 17 keys; `reserved_remap`: **⇧⌘T reaches the page** (`["⌘⇧T/KeyT"]`) and reopens nothing; **⌥⌘T never reaches the page** (`[]`) and **reopens the closed tab once** (`tabs reopened=1`).
- `applied`: toolbar shown, sidebar right, the palette's engine "Spike Search" (the profile's default), the keyword `spk` offers its Tab row, suggestions off.
- `save_panel`: a save panel as a sheet on the browser window, proposed `spike-ask.bin` in the chosen folder; ended with OK: the download completes at the panel's file (`complete=true file=true`); a second panel cancelled: the download is cancelled and **not listed** (rows 1 → 1).
- After the relaunch: `relaunch_equal` **13 of 13** settings read back (⌘W behaviour, archive hours, Peek, routing between spaces, toolbar, sidebar side, appearance, suggestions, the engines list, the per-profile default, the download folder, ask where, PDFs), applied again at launch (toolbar, side, engine); `relaunch_keys`: Pin ⌥⌘P, Reopen ⌥⌘T, Print ⌘P, ⌥⌘T reserved and ⇧⌘T not; `reset_all`: 0 overrides, ⌘D and ⇧⌘T back, the reserved set equal to `ReservedShortcuts.all`.

Timings (`remap_timing`): key press in the recorder → stored and on the menu item **76.9 ms dev / 78.2 ms release** (one main-queue hop for the reload, one observation `Task` hop for the app, the spike polling every 20 ms); `MainMenuBuilder.apply` (walk the bar, ~150 items, set the changed keys in place) **0.31 / 0.30 ms**.

`keys` with no overrides (the reserved set from the table): ABC, Colemak, Lithuanian, Lithuanian Colemak as before (`20261005-042014`): 2 reserved calls per layout, ⌘C/⌘V/⌘Z through the page to the menu, page saw ⌘c ⌘v ⌘z o, consumed 1.

Evidence for the reviewer: `research/screenshots/phase-4.4a/` (Settings ▸ Shortcuts during the conflict, General, Search, Downloads; light, dev).

Found on the way: an ⌥ key whose character ⌥ changed (⌥⌘P arrives with `characters` "π") no longer matched its menu item once the page's view had handled the event: `NSApp.mainMenu.performKeyEquivalent` returned false for the original `NSEvent` and true for a fresh `NSEvent` with the same type, flags, characters and key code (and for the same constructed event sent straight to the menu). The host now retries with a fresh copy, on the unhandled path and, for reserved keys, in `isReservedKeyEvent` (RoomCore's own call with the original then fails as measured, so the action runs once: `tabs reopened=1`). B-86.

## Phase 4.4b — the engine step (deleteProfile, clearBrowsingData, contentSettings, the Google-service defaults), Settings ▸ Spaces & Profiles and Privacy, palette sections (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

Display 1920 × 1080 @ 60 Hz; the Claude app frontmost (Room activated by `run-spike.sh`). Dev = `build/roomcore` (component `out/dev`, `//room` at `6429da8`); release = the Debug app over the official framework (`build/roomcore-release`, `RoomCoreCommit 6429da8`, `docs/laptop-build.md` §A step 3, 28 s). Builds and their times: `build-log.md` "Phase 4.4b".

### The engine step

| Run | Result |
|---|---|
| Dev incremental (`roomcore-build.sh`) | 98 s build (2 min 20 s with apply), then the deletion fix 54 s; "0 applied, 23 already" |
| Baseline after the members (`build/evidence-4.4b/baseline-1`) | nav passed 18.4 s; ten-page quits **0.367 / 0.299 / 0.372 s** (load1 20.5 / 22.3 / 19.4), 0 helpers left, 0 crash reports |
| Baseline after the deletion fix (`baseline-2`) | nav passed 17.9 s; quits **0.381 / 0.291 / 0.375 s** (load1 8.3 / 14.1 / 16.7), 0 helpers left, 0 crash reports |
| Net-log, launch + 600 s idle + browse + quit (`ROOM_NETCHECK_IDLE=600 scripts/netlog-check.sh`, the dev app at `6429da8`, fresh state, first-run card shown; launch_idle → browse 600.3 s; load1 6.7 at launch, the official build running beside it) | Room's own code **0** (main process 0 bytes in/out; updater and crash reporter not created); page traffic 127.0.0.1 2 requests, localhost 4; **engine 0 requests**, 0 hosts besides the page's (`build/evidence-4.4b/netlog`) |
| Context menu on a misspelled word (`ROOM_SL_ONLY=spelling scripts/session-lifecycle.sh`, dev, `build/evidence-4.4b/spelling`) | "Add to Dictionary \| — \| Look Up “misspeled” \| — \| Undo \| Redo \| — \| Cut \| Copy \| Paste \| — \| Search Google for “misspeled” \| Translate “misspeled” \| — \| Inspect \| — \| Speech": **no "Use Enhanced Spell Check"**. The 4.3b release framework the same minute: "Add to Dictionary \| Use Enhanced Spell Check \| …" (`spelling-release-old`). Neither offered the "misspelled" suggestion today (3.7b's run did): the macOS checker's answer, the same on the old framework |
| Engine smoke (`-RoomSpike profiles -RoomSpikeOnly engine`, dev) | `deleteProfile` refused with a page open (`profileInUse("1 pages open")`), then **deleted in 285 ms**, the directory gone ("directory deleted after 2 attempt(s)"); Clear for the last hour 4 ms: the cookie gone, this hour's visit gone, an imported visit 3 h old kept; `contentSettings(.notifications)` = `http://127.0.0.1:8766=block` (origin `http://127.0.0.1:8766/`, not embedded), the page reads `notifications: denied`, reset → listed 0, `prompt` |

**Found on the way (B-87):** the first deletion took **177 s**: Chrome unloaded the profile at once (`RemoveKeepAlive … keep_alives=[]`, "Unloading profile" in the same millisecond, `--vmodule=profile_manager=1`), but its `NukeProfileFromDisk` retries run at best-effort priority, and Chrome holds best-effort work until its startup is complete, which a Room window never signals: the 3-minute fallback released them (the new profile's README written and the extension updater's keep-alive at the same second). `room::DeleteProfileDirectory` now deletes at user-visible priority after `OnProfileWillBeDestroyed`, retrying every 250 ms: 2 attempts, 285 ms.

Translate and generation (B-63, B-72): `//room` sets no API key and enables no translate or generation feature (grep over `Engine/roomcore/room` and `args/`: only the ranker features disabled in 3.1b-2 and the translate client's wiring); nothing added.

### Tour steps `settings2` (new) and `settings` (B-86's engine-side copy)

| Run | Build | load1 | Checks | Tour directory |
|---|---|---|---|---|
| `settings`, `settings2` | dev | 7.00 | **32 / 32, 26 / 26** | `build/grand-tour/20261006-223230-roomcore` |
| `settings`, `settings2` | release framework (`ROOM_TOUR_APP`) | 11.67 | **32 / 32, 26 / 26** | `build/grand-tour/20261006-223416-roomcore` |
| `settings2` after the Privacy list's refresh on appear | dev | — | **25 / 26**: the cookie read right after Clear was still `room_profile=work` | `20261006-223903-roomcore` |
| `settings2`, the cookie read 1 s after Clear from a new page (three runs) | dev | — | **26 / 26 ×3** (`cookie=""` each) | `20261006-224027`, `-224110`, `-224146` |
| `settings2`, the final code | release framework | 8.50 | **26 / 26** (Clear 6 ms, delete 324 ms) | `20261006-224237-roomcore` |

0 crash reports in every step. The one 25 / 26: Clear had returned (BrowsingDataRemover's reply, 5 ms) but a new page of the site, in the renderer still holding the site's earlier page, read the cookie from that renderer's cookie cache, which the network service's change notice refreshes a moment later; the step now reads the jar from a page loaded 1 s after the Clear (Chrome behaves the same; a page loaded later sees the jar). The `settings2` result lines (identical on both builds but for ids and timings):

- `set`: a profile Work with a space Office; the spaces reordered as Settings' rows move them (`up=["Office", "Space"] back=["Space", "Office"] positions=[0, 1]`); the 2.5 fixture's cookie in Office: `room_profile=work`, Work's engine profile named by its id; **renamed** to "Office Profile" through Settings' path (an empty name refused "A profile needs a name."; the space keeps the profile); the directory is `Room Profile <work id>` (nothing moved by the rename); a space's Routing… opens the sheet over Settings with a new rule targeting Office.
- Between the launches the wrapper puts Work's directory back as `Room Profile Office Profile` and Local State's `last_used` with it (a pre-4.4b state).
- `verify`: **moved at launch** `Room Profile Office Profile → Room Profile <work id>`, Local State updated, `last_used=Room Profile <work id>`, no directory left or re-made under the old name; **the cookie after the relaunch `room_profile=work`**.
- Clear browsing data, last hour, history + cookies, Work only (the sheet's path): before `fresh=true old=true`, **after `fresh=false old=true`, cookie `""`**, **5 ms dev / 6 ms release**; the toast "Cleared history and cookies from the last hour in “Office Profile”".
- Permission through Settings' path: `contentSettings` lists `http://127.0.0.1:8766=block`; **permissions.html reads `notifications: denied`**; Reset → listed 0, the page reads `prompt` (geolocation stays `prompt` on both: macOS's location authorization, B-26).
- Delete: a profile Doomed with a space, a pinned tab and a Today tab, both loaded: counts 1 space, 2 tabs; **deleted in 316 ms dev / 317 ms release** (pages closed, the engine's deletion included), the directory gone, **2 of 2 entries in the Archive** (`spaceDeleted`), profile and space gone, 2 engine profiles left, the shown space Space; deleting Default refused ("the Default profile stays").
- The palette: 8 "Settings ▸ …" commands; Settings ▸ Privacy's command shows the window with the title Privacy.
- All Site Data… (the bounded attempt): `chrome://settings/content/all` loads in a Room tab, title "Settings - All sites", alive, `settings-ui` with its shadow root, the viewport drawn (7 grey levels in a 40 × 40 grid); the capture shows "All sites … Sites you visit will appear here" (B-88).
- `settings`: unchanged lines; `reserved_remap`: ⇧⌘T reaches the page, **⌥⌘T never does and reopens once** with the fresh copy now made by `RoomCoreWebContents` (B-86).

Unit tier with `CI=1`: Engine 66, Store 49, Tabs 71, Model 105, Chrome 55, Omnibox 51, UIKitCore 55, all passing; the engine-free CI build and its tests locally (`xcodegen/ci.yml`): TEST SUCCEEDED in 69 s.

Evidence for the reviewer: `research/screenshots/phase-4.4b/` (Settings ▸ Spaces with the renamed profile, Settings ▸ Privacy with the listed permission and the statements, Chromium's All sites page in a Room tab; light, dev).

## Phase 4.5 — extensions UX: site access and Run, commands with the sidebar focused, pin/unpin and the overflow menu, the site panel's Extensions section, extension pages in their profile's space (2026-10-06, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

Room.app Debug on the dev framework (`out/dev`, component, `room_enable_spikes=true`, `//room` at `462745e`) and the Debug app over the release framework (`build/roomcore-release`, official, `RoomCoreCommit 462745e`, `ROOM_TOUR_APP`); display 1920 × 1080 @ 60 Hz; the window main in every run (`window_main: true`); the Claude desktop app frontmost between runs. Every run on its own state and engine directory under `/tmp/room-4/extensions.*` (also inside the tour), the test servers on :8770/:8771. Captures in `research/screenshots/phase-4.5/` (evidence, not assertions).

### Baseline after the engine change (`build/evidence-4.5/baseline-1`, embryo host, dev framework)

nav **passed** in 18.3 s; ten-page quits **0.366 / 0.296 / 0.318 s** (load1 14.4 / 14.1 / 18.2: the dev package had just run), 0 helpers left, 0 new crash reports, exit 0 in each. Series "patches: 0 applied, 23 already on the room branch".

### Tour steps `extpopup` (18 checks) and `extensions` (33 checks)

| Run | App | load1 | extpopup | extensions |
|---|---|---|---|---|
| `20261006-232920-roomcore` | dev | 5.5 | 18 / 18 | 33 / 33 |
| `20261006-233155-roomcore` (final code) | dev | 8.4 | 18 / 18 | 33 / 33 |
| `20261006-233118-roomcore` | release framework | 10.2 | 18 / 18 | 33 / 33 |

0 new crash reports, 0 engine minidumps in the runs' own engine directories, nothing left running, in all three.

| Check (`extux`) | dev (final) | release framework |
|---|---|---|
| Default access of the fixture on `http://127.0.0.1:8770/site.html` | on all sites; selectable on click, on this site, on all sites; `canAffect` true; the content script ran | same |
| `setSiteAccess(.onClick, host: "127.0.0.1")` + reload | set; the content script **did not run** in 3 s; `wantsToRun` true | same |
| `runAction` (the Run button's member) | ran: the page's mark within **207 ms** (polled every 200 ms); `wantsToRun` false | 210 ms |
| `setSiteAccess(.onSite)` + two reloads | ran after both; level on this site | same |
| `commands(for:)` | `_execute_action=⇧⌘Y action room-named=⇧⌘U` (Chrome's "Command+Shift+Y" in Room's notation) | same |
| ⇧⌘U with the sidebar's `SidebarOutlineView` first responder (`pageHasKeyboard` false) | the router took it, `commands.onCommand` reached the worker in **23 ms** (the action's title read back) | 22 ms |
| ⇧⌘Y with the sidebar focused | the popover in **79 ms** | 56 ms |
| ⇧⌘C with the sidebar focused (no extension's key) | `routed=⇧⌘C false`: on to the menu | same |
| Two pinned actions (the fixture, a second unpacked "Room 4.5 second") | header `[fixture, second]`, no overflow button | same |
| Unpin the fixture (Settings' path) | header `[second]`; the overflow button shown; menu `["Room 3.6 fixture  T1", "Pin"]` (the page's badge "T1") | same |
| The overflow item | the popup in **50 ms**, anchored on the overflow button | 37 ms |
| The overflow menu's Pin | header `[second, fixture]` (`ToolbarActionsModel`'s order: a newly pinned action goes last) | same |
| Site panel on the page, fixture on click after a reload | the Extensions section lists the fixture: On click, Run shown, the script not run (`site-panel-run.png`) | same |
| The section's Run | the script ran in **229 ms**; "Ran on this page. Always on 127.0.0.1" offered (`site-panel-after-run.png`) | 229 ms |
| "Always on 127.0.0.1", then two reloads | ran after both, level on this site, `wantsToRun` false | same |
| Back to On all sites | set | same |
| Options with two profiles, Work's "Office" shown | the page opened in "Space" (Default's: the extension's profile), shown; `chrome-extension://…/options.html` in the extension's engine profile wrote its storage ("storage written") | same |
| An extension page for a profile with no space ("Spare") | an "Extensions" space made for it and shown | same |
| Keyboard Shortcuts… | `chrome://extensions/shortcuts` ("Extensions") as a tab in the extension's profile's space | same |
| Settings ▸ Shortcuts' extension rows | "Room 3.6 fixture: Activate the extension ⇧⌘Y", "…: Room fixture named command ⇧⌘U", no conflict with a Room key (`settings-shortcuts.png`) | same |
| Allow in incognito | stored for the profile, not for Work | same |

`extpopup` (3.6b's checks after the pinned-order change, dev final / release): header button with the page's badge "T1"; click → popup **90.6 / 41.9 / 40.4 ms (median 41.9)** / **54.6 / 35.6 / 36.3 ms (median 36.3)**, 264×65 at load → 384×285 after its own resize; focus loss and Esc ×3 closed it with the page destroyed; `action.openPopup` 44 / 44 ms; ⇧⌘Y in the page 38 / 40 ms; ⇧⌘U reached `onCommand`; `sidePanel.open()` still "No active side panel for tabId: N" (the fixture's new fetch runs after it: the first order lost the command's user gesture, "may only be called in response to a user gesture", fixed before the tour).

### The extension's own request apart from the engine's

The fixture's named command fetches `http://127.0.0.1:8771/room-extension-fetch?command=room-named` (the endpoint server logs every request). In each run: the server's log **1 request** to it during the run; the net-log (`--log-net-log`, capture mode Everything) **9 URL requests, 1 initiated by an extension: `GET http://127.0.0.1:8771/room-extension-fetch?command=room-named · initiator chrome-extension://dibedkfpfkdkkcbjmblmfdbjdhdnlgkp`**; by host (`netlog-summary.py`): `hosts: 1 (0 not page traffic: none)`, i.e. **the engine's own requests 0**. Release framework the same (1 / 1 / 0).

### Unit tier (`CI=1 swift test`)

Engine 70 (+4: on click waits for Run and on this site is per host; a level the extension cannot take is refused; commands run only when the extension has them; Chrome's accelerator text in Room's notation, 8 cases), Chrome 58 (+3: pin/unpin and the overflow; commands by key; the site panel's section; the pages test now checks the profile), Model 108 (+3: the B-67 space choice; the settings round trip with an extension allowed in incognito), UIKitCore 56 (+1: extension rows and their conflicts), Sidebar 39, Tabs 71: all passing. The engine-free CI build and tests locally (`xcodegen/ci.yml`): TEST SUCCEEDED (74 s).

## Phase 4.6 — media: the media session controls, the footer's media row, Now Playing and the media keys, document and video picture-in-picture (2026-10-07, Mac mini M4, 24 GB, RoomCore 155.0.8059.36)

### Baseline after the engine change (`build/evidence-4.6/baseline-1`, embryo host, dev framework `2ca0dd2`)

| Run | Result |
|---|---|
| nav | passed, 13.0 s |
| ten-page quits | **0.346 / 0.308 / 0.298 s** (load1 8.1 / 9.8 / 13.9), helpers left 0, 0 crash reports, stub hits 0 |
| first attempt (`baseline-1-so`) | nav passed 19.5 s; the first quit run stopped at the ten-page fixture ("loading-at-ready 1": Stack Overflow still loading at ready), the known live-site condition |

### The engine probe (`scripts/media-check.sh "" -RoomSpikeOnly engine`, dev build, before the official build started; fixture `research/spikes/phase-4.6/media.html?quiet=1` on :8776)

The fixture's `#play` is clicked (a gesture), track 0 plays; then each member is called and the page's own log (its action handlers append to `#log`) is read back.

| Member | Result (probe; then the tour runs dev / release) |
|---|---|
| `mediaSession` after the click | "Room Tone A" by "Phase 4.6", playing, actions `[nextTrack, pause, play, previousTrack, seekBackward, seekForward, seekTo, stop]`, position 1.6 / 30.0 s at rate 1, artwork URL `data:`, **artwork PNG 1,412 B** (Chrome's `GetMediaImageBitmap`, 96 px) |
| `mediaPause()` | page logged `pause` in **8 ms** (12 / 2 / 2 ms); session paused, rate 0 |
| `mediaPlay()` | `play` in 3 ms (7 / 2 / 1); session playing |
| `mediaNextTrack()` | `nexttrack` in 10 ms (9 / 8 / 13); session "Room Tone B", artwork 1,361 B (the second canvas) |
| `mediaPreviousTrack()` | `previoustrack` in 6 ms (11 / 9 / 10); "Room Tone A" again |
| `mediaSeek(to: 12)` | `seekto 12.0` in 1 ms (2 / 1 / 1); position 12.0 / 30.0 |
| the page's log | `click,pause,play,nexttrack,previoustrack,seekto 12.0` |

At `quiet=1` (volume 0.02) the page is never `isAudible` (Chrome's level threshold): the row's rule takes the playing session. The fixture's `currentTime` advanced ~0.1 s per second of "playing" in these runs (`time=0.3` after ~3 s); not chased (the `audio` step below measures real output).

### Tour step `media` (`scripts/media-check.sh`, own state and engine directories; `--only media light`)

| Run | Checks | Conditions |
|---|---|---|
| dev `20261007-002511` (final code) | **32 / 32** | load1 8.06, no build, no other Room, 0 minidumps |
| release framework `20261007-002536` (`ROOM_TOUR_APP`, Debug app over `RoomCoreCommit 2ca0dd2`, final code) | **32 / 32** | load1 7.96, 0 minidumps |
| earlier: dev `20261007-002055`, release `20261007-002131` (31 checks, before the viewport check) | 31 / 31 each | load1 5–8 |

Result lines (dev / release):

| Check | Dev | Release |
|---|---|---|
| Row hidden while the playing entry is selected | hidden | hidden |
| Space switch → row shown (fixture in the second space "Media") | **24 ms**, "Room Tone A" / "Phase 4.6", playing, next enabled, artwork 96×96, frame {{6, 40}, {228, 40}} (window coordinates, above the footer) | 25 ms, same |
| Row's pause → page's `pause` handler; row shows Play | 1 ms; 21 ms | 2 ms; 21 ms |
| Row's play → `play`; row shows Pause | 1 ms; 21 ms | 1 ms; 21 ms |
| Row's next → `nexttrack`; row retitled "Room Tone B" | 1 ms; 22 ms | 2 ms; 20 ms |
| Click on the row → its entry selected in its space, row hidden | 30 ms | 33 ms |
| × → hidden, still hidden after 500 ms while the page plays | yes | yes |
| The page pauses, plays again 300 ms later → row back | 21 ms | 21 ms |
| Document PiP: panel shown after the click | 29 ms; requested {320, 180} → content **320×180**, frame {{1286, 761}, {320, 204}} (title bar 24 pt), floating level, non-activating, `hidesOnDeactivate` false, all Spaces; panel top-right (1606, 965) = the card's (1622, 981) less 16 pt; Today tabs 1 → 1 | 34 ms, same frame |
| The PiP page painted | `captureViewport` 320×180 with the page's text (`phase-4.6-docpip-viewport.png`) | same |
| Opener while PiP shows | alive, discard blockers `pictureInPicture` (3.7b's exemption holds) | same |
| PiP page's `window.close()` → panel closed | 6 ms; opener alive, entry kept | 8 ms |
| User closes the panel → the page | closed; opener alive | same |
| The opener's entry closed → panel closed | 29 ms | 30 ms |
| Video PiP (`requestPictureInPicture` on a click) | `NativeWidgetMacFramelessNSWindow` {{1523, 24}, {373, 210}}, level 3 (floating), page logged "video pip"; the opener's blockers `pictureInPicture`; `exitPictureInPicture()` → window gone, "video pip left" | same |

The window server's capture (`CGWindowListCreateImage`) shows Chromium's page layers white in the panel **and** in the main window's card (`phase-4.6-docpip-opener-window.png`: pip.html's canvas and heading absent), so it cannot judge the panel's content; the engine's own capture is the evidence and the user's by-hand step the judge.

### Now Playing and the media keys (the finding)

| Check (dev / release) | Result |
|---|---|
| `MPNowPlayingInfoCenter.default().nowPlayingInfo` in Room's process with the fixture playing | **set by Chrome**: title "Room Tone A", artist "Phase 4.6", duration 30.0, rate 1.0, artwork present, `playbackState` 1 (playing), 8 keys; after a pause: elapsed 3.5, rate 0.0, state 2 (paused) |
| `MPRemoteCommandCenter.shared()` | play, pause, toggle, next, previous, change-position all enabled (Chrome's `SystemMediaControls` registered them) |
| MediaRemote's `MRMediaRemoteSendCommand(kMRPause)` (what Control Center's button sends to the Now Playing app; the system routes it) | **the page's `pause` handler ran in 30 / 23 ms** |
| A synthetic play/pause key (`NSEvent.otherEvent` subtype 8, `NX_KEYTYPE_PLAY`, posted to the HID tap) | posted, `AXIsProcessTrusted` false: nothing reached the page in 3 s (a spike cannot post a system key without accessibility trust); the key is the user's by-hand step |

**Finding:** Chrome's own system media controls (`content`'s `MediaKeysListenerManagerImpl` → `SystemMediaControlsNotifier` → `system_media_controls::SystemMediaControlsMac`) reach macOS from a Room window without Room's help: Now Playing carries the active session and MediaRemote's command reaches the page. The host registers no `MPRemoteCommandCenter` handlers (they would compete with Chrome's).

### The audible edge after the observer work (`--only audio light`, dev, `20261007-002155`, load1 5.4)

13 / 13: first audible edge **1,783 ms** (bound 2 s; 3.9-2: 1,558 ms), later 128 ms, Web Audio 144 ms; reported stopped 297 / 302 ms.

### Unit tier (`CI=1 swift test`)

Engine 72 (+2: the controls recorded, the state moved; none without a session), Tabs 75 (+4: the rule, × and the next start, the row on the fake with its buttons and selection), Sidebar 39, Design 9; the engine-free CI build and tests locally (`xcodegen/ci.yml`): TEST SUCCEEDED (95 s).

## Phase 4.7a — documents: Save Page, the full-page capture through the DevTools protocol, Chrome's PDF viewer and the PDFs setting, View Source, ⇧⌘2 (2026-10-07, Mac mini M4, 24 GB, display 1920 × 1080 @ 60 Hz, RoomCore 155.0.8059.36)

### Baseline after the engine change (`build/evidence-4.7a/baseline-1`, embryo host, dev framework `02de228`)

| Run | Result |
|---|---|
| nav | passed, 18.4 s |
| ten-page quits | **0.313 / 0.289 / 0.336 s** (load1 11.8 / 16.0 / 17.0), helpers left 0, 0 crash reports, stub hits 0 |

### The engine probe (`scripts/documents-check.sh … -RoomSpikeOnly engine`, dev build, before the official build started; fixtures `research/spikes/phase-4.7` on :8777; `build/evidence-4.7a/probe-1.txt`)

| Member | Result (probe; then the tour runs dev / release) |
|---|---|
| `savePage(as: .html)` | 26 ms (25 / 21), `Page-html.html` 543 B |
| `savePage(as: .completeHTML)` | 36 ms (39 / 18), `Page-completeHTML.html` 775 B + `Page-completeHTML_files/` with `page.css` 176 B and `swatch.png` 322 B (the fixture's own bytes) |
| `savePage(as: .mhtml)` | 3 ms (4 / 3), `Page-mhtml.mhtml` 2,542 B |
| the MHTML reopened as `file://` | title "Room Save Page fixture", `#swatch` complete 240 × 120; `captureViewport` at the image: (233, 161, 72) in the orange part, (67, 113, 220) in the blue band (the fixture's (240, 140, 20) and (40, 90, 220) after colour management) |
| `sendDevToolsCommand`: `Page.getLayoutMetrics` + `Page.captureScreenshot` (`captureBeyondViewport`, clip = CSS content size) on `tall.html` | 168 ms (163 / 134): PNG **2068 × 8000** px (104,458 B) for content 1034 × 4000 CSS px, viewport 1034 × 788 pt at 2× |
| the same with DevTools' front-end open (3.3b's pane, a second agent-host client) | 136 ms (143 / 136), the same 2068 × 8000 PNG: no conflict, nothing refused |
| the viewport after the capture | `[innerWidth, innerHeight, scrollHeight]` `[1034, 788, 4000]` before and after |
| an unknown method (`Room.noSuchMethod`) | the protocol's error: "'Room.noSuchMethod' wasn't found" |
| a HTML and a complete-HTML save in the host's downloads list | yes: Chrome's `SavePackage` makes download items, which 3.4a's observers report and Chrome's download history restores after a relaunch (`pdf_download`'s rows list `Page-completeHTML.html`, `Page-html.html`); the MHTML (`GenerateMHTML`) makes none |

### Tour step `documents` (`scripts/documents-check.sh`, own state and engine directories; `--only documents light`)

| Run | Checks | Conditions |
|---|---|---|
| dev `20261007-012640` | **42 / 42** | load1 7.09 (the official build had ended), no other Room, 0 minidumps, 57 s |
| release framework `20261007-012849` (`ROOM_TOUR_APP`, Debug app over `RoomCoreCommit 02de228`) | **42 / 42** | load1 13.38, 0 minidumps, 36 s |

Result lines (dev / release):

| Check | Dev | Release |
|---|---|---|
| PDF opened in Chrome's viewer (`document.contentType` application/pdf, title from the PDF's info) | loaded in 4,083 ms (5,697–6,848 ms in the probes) | **349 ms** |
| The viewer painted (`captureViewport`, every 8th pixel) | 2068 × 1576 px, 30.5 % not white | same |
| ⌘F's find (`find("zebracorn")`, Chrome's `FindTabHelper` across the PDF frame) | **3 matches**, final in 43 ms; the next step → active 2 | 3, 43 ms |
| Zoom (`zoomFactor = 1.5`) | redrawn | redrawn |
| Print (`print()`) | Chrome's preview (`NativeWidgetMacNSWindow` 1000 × 660) after 30 ms; Esc closed it | 24 ms; closed |
| The viewer's Download button (clicked 116 pt left of the right edge, 28 pt down) | Chrome's save panel (`NSSavePanel` sheet on Room's window) after 666 ms, "sample.pdf" proposed in Downloads; cancelled by the spike | 692 ms |
| PDFs ▸ Download, next launch (`RoomPdfsDownload` passed) | the PDF navigation downloaded `sample.pdf` (1,477 B) in 2,799 ms; the new tab closed | 628 ms |
| View ▸ Developer ▸ View Source | `view-source:` tab right under the entry, selected, 15 source lines, in 1,583 ms | 339 ms |
| The context menu's View Page Source (Chrome's `IDC_VIEW_SOURCE`, already in the menu) | opened under the page (position +1), selected, in 786 ms | 773 ms |
| File ▸ Save Page… | the panel with "Web Page, Complete / HTML Only / Web Archive (MHTML)", name "Room Save Page fixture.html" → ".mhtml" on MHTML; Save → 2,542 B in 291 ms, toast "Saved “Room Save Page fixture.mhtml”" with Show; the file reopened with its image 240 × 120 | 295 ms |
| Save Page… on the PDF | refused with the toast "Could not save the page: a application/pdf page cannot be saved" | same |
| ⇧⌘2 overlay | over the page's frame {{240, 6}, {1034, 788}}, first responder, in 5–14 ms | 5–16 ms |
| A dragged rectangle over the swatch (24, 102.08, 240 × 120 pt) | 480 × **241** px (the fractional top rounds outward) in 48 ms; the bar under it | 49 ms |
| Copy | the pasteboard: PNG 480 × 241 (3,014 B) + TIFF, pixel (233, 162, 72); toast "Copied the screenshot" | same |
| Return (the viewport) then Save | 2068 × 1576 px, `Screenshot 2026-10-07 at 01.27.12.png` 102,108 B in the downloads folder, toast with Show | same |
| Open as Tab | a `file://` Today tab under the page, selected, the image 800 × 600 (a 400 × 300 pt drag) | same |
| Esc | overlay closed, the window first responder | same |
| Full Page on `tall.html` | 2068 × 8000 px in 166 ms (taller than the viewport), saved | 151 ms |

Chrome's save panels are out of process on macOS 26 (ViewBridge): `-[NSSavePanel ok:]` raises "not implemented" (it crashed the first PDF run: an uncaught `NSException` from the spike's call, found with lldb) and setting `directoryURL` or the name while the panel shows is refused (`NSViewBridgeErrorIncorrectPhase`). Room's own Save Page… panel is answered by ending its sheet with OK (its folder is the run's downloads folder, set before it shows); Chrome's PDF panel is only checked to appear (its folder is Chrome's download pref, `~/Downloads`), and the landing is by-hand step 55.

### Unit tier (`CI=1 swift test`)

Engine 75 (+3: `SavePageFormat`'s names, the fake's three formats and a closed page, the DevTools handler or `notSupported`), Chrome 64 (+6: the drag's rectangle, a click, the cut at 1× and 2× with outward rounding and the edge, the file names and their uniqueness, the full page's clip, Save Page's names), Model 109 (+1: `storedSettings` without opening the store), UIKitCore 56 (the menu against `docs/shortcuts.md`: the new row, ⇧⌘S unique), Omnibox 51, Design 9; the engine-free CI build and tests locally (`xcodegen/ci.yml`): TEST SUCCEEDED (90 s).

## Phase 4.7b — reader mode, translate, print (2026-10-07, Mac mini M4, 24 GB, display 1920 × 1080 @ 60 Hz, RoomCore 155.0.8059.36, no engine change)

Tour step `reader` (`scripts/reader-check.sh`, spike `reader`, own state and engine directories, `research/spikes` on :8777; the window 1280 × 800, the card's page 1034 × 788 pt):

| Run | Checks | Conditions |
|---|---|---|
| dev `20261007-022020` (`build/roomcore`, Debug app) | **34 / 34** | load1 9.5, 0 minidumps, 42 s |
| release framework `20261007-022102` (`ROOM_TOUR_APP`, Debug app over `RoomCoreCommit 02de228`) | **34 / 34** | load1 7.3, 0 minidumps, 24 s |

Result lines (dev / release):

| Check | Dev | Release |
|---|---|---|
| ⌥⇧⌘R typed (key event through `NSApp`, page first, then View ▸ Reader Mode) to the reader page in the card | 163 ms | **107 ms** |
| — the distiller (`executeJavaScript` in the isolated world, 112 KB script + `applyWithOptions`), article1 (3,673 characters, 655 words, 2 images) | 23 ms (distiller's own `total_time` 12.9 ms) | **13 ms** (7.3 ms) |
| — the reader page's load (`file://<state>/Reader/<entry>.html`, until `isLoading` false) | 82 ms | **58 ms** |
| article2 (1,069 characters, 1 image): distilled / loaded | 33 / 66 ms | 23 / 38 ms |
| notarticle (the dashboard): distiller → 0 characters (threshold 400) → toast "No article found on this page", no reader page | 32 ms | 23 ms |
| articlecsp (article1 under `<meta>` CSP `script-src 'self'`) | distilled, 3,673 characters in 23 ms | 24 ms |
| Reader page DOM (article1) | title, host `127.0.0.1`, the original link, Exit; 4 headings, 10 paragraphs, 2 figures; 0 sidebar links, 0 scripts; `file:` | same |
| Images (DOM `complete`, natural size, absolute `src`) | swatch 240 × 120, field 320 × 180 | same |
| Text size (`getComputedStyle(main p).fontSize` after Settings ▸ Appearance ▸ Reader text size) | small 16 px, medium 19 px, large 23 px | same |
| Appearance (`NSApp.appearance` → `data-appearance` → `getComputedStyle(html).backgroundColor`) | light `rgb(255, 255, 255)` (text `rgba(0, 0, 0, 0.847)`); dark `rgb(24, 24, 25)` (text `rgba(255, 255, 255, 0.847)`) = `Palette.cardBackground` resolved | same |
| Captures (`captureViewport`, `research/screenshots/phase-4.7b/`) | light 2068 × 1576 px 7.8 % not white; dark 100 % not white | same |
| Row glyph (`row-reader` image view in the entry's cell) | shown at {{208, 4}, {22, 28}} while reading, hidden after | same |
| Back while reading | the article's page unchanged (the reader page has no history) | same |
| Esc typed into the reader page | back to the page in 29 ms; scroll 420 → 420; `canGoBack` true → true; reader page closed; `<state>/Reader/<id>.html` removed | 35 ms |
| History after Exit (`ProfileHistory.search("Lighthouse Keepers")`) | `[article1.html]`, no `file:` row | same |
| Back after Exit | the entry's page goes back to `page.html` | same |
| View ▸ Exit Reader Mode (article2) | back to the page | same |
| A link in the reader page (article2's link to article1) | reader mode left and the link loaded in the entry's page in 52 ms (`canGoBack` true) | 48 ms |
| Translate on a German page (`phase-2.6/translate.html`, `lang=de`, 3 s) | no main-menu item, no context-menu item (Chrome's `CanManuallyTranslate` is false without a key), no offer toast | same |
| The page's context menu | "… Search with Image Search \| Open in Reader Mode \| Cast… …" (Chrome's Open in Reading Mode is Room's reader; Listen to This Page dropped) | same |
| ⌘P (`printPage:`) | Chrome's preview (`NativeWidgetMacNSWindow` 1000 × 660, a child of Room's window) after 24 ms; key window = the preview, first responder its `RenderWidgetHostViewCocoa` | 26 ms |
| Return in the preview (destination Save as PDF, the default) | Chrome's save panel for "Why Sourdough Starters Smell Like Apples — Room Reader fixture.pdf" after 3,497 ms (the preview's first render on the dev build); cancelled by the spike | **427 ms** |
| After the panel's Cancel | key window = Room's window, not the preview (`makeKeyAndOrderFront` on the preview, then Esc closed it) | same |
| File ▸ Page Setup… | `NSPageLayout`'s sheet (`NSPanel`) on the window; portrait, iso-a4; cancelled | same |

Findings: (1) Chrome's `domdistiller_wrapped.js` way (the module on `Object.create(window)`) throws "Illegal invocation" at `window.document`'s getter in the isolated world; Chrome's current wrapper (timers stubbed on `window`, the isolated world's own global) works, so `ReaderRules.distillerScript` follows it. (2) A meta CSP `script-src 'self'` did not stop the isolated-world evaluation (`executeJavaScript`'s `(0, eval)`); a header CSP on a live site is by-hand step 60. (3) The distiller's title is the document's `<title>` ("… — Room Reader fixture"); the article's own `<h1>` stays in the content, so the title shows twice on the fixture (B-94). (4) Chrome's print preview starts each job from a copy of `NSPrintInfo.sharedPrintInfo` (`PrintingContextMac::UseDefaultSettings`/`UpdatePrinterSettings`) and then sets orientation and paper from its own Layout and paper controls: Page Setup sets the macOS shared print info, which the preview's own choices override.

### Unit tier (`CI=1 swift test`)

Chrome 72 (+8: the distiller's dictionary, the markup-text fallback, `null`/malformed answers, the article threshold, the script's options, the template's one-pass fill with escaping, the CSS variables from the tokens; the context menu's reading-mode items), Tabs 79 (+4: the swap and Exit with the page and its history untouched, Esc / the original link / another link, unload, `ReaderNavigation`), Model 109 (the sample state carries `readerTextSize`), Design 9, Sidebar 39, UIKitCore 56, Omnibox 51, all passing.

## Phase 4.8a — several windows: per-window Today tabs, page ownership, the drag out (2026-10-07, Mac mini M4, 24 GB, display 1920 × 1080 @ 60 Hz, RoomCore 155.0.8059.36, no engine change)

**Method.** Tour step `windows` (group `windows`, `scripts/windows-check.sh`, spike `windows` in `App/Sources/Debug/WindowSpikes.swift`, fixtures `research/spikes/phase-4.8/` on 127.0.0.1:8777), its own state and engine directories, four launches: `main` (three pinned entries A, B, C; B navigated to its second page in window 1; ⌘N as a key event through the menu bar; a rename of A through the store read back from window 2's row cell; two Today tabs in window 2; B selected in window 2; ⌘1 as a key event in window 2; "Open in New Window" performed from window 2's context menu; `SidebarController.debugDragEnded` at 20 pt and 100 pt past window 1's edge, the mouse drag itself being by-hand step 65; a second space and a frame of its own for window 2; the quit), `relaunch` on the same state (the windows read back; window 2 closed with `performClose`; every window closed; ⌘N as a key event with no window; the Dock's reopen through `applicationShouldHandleReopen`), then `memory` twice on fresh states (`-RoomWindowsMemoryWindows 1` and `2`: the `memory` spike's ten live sites, summed RSS over the process tree with `ps` after every page loaded and 8 s, one page shown per card; a fresh launch each because pages closed earlier leave renderers behind, B-56).

**Results.** Dev build `20261007-031209-roomcore` (load1 7.5): **30 / 31**, the one failure 2 renderer minidumps, both `layout_object.h:518 DCHECK failed: !NeedsLayout() || ChildLayoutBlockedByDisplayLock()` from the memory launches' live sites (B-76's dev-build condition; the other launches 0). Release framework (`ROOM_TOUR_APP`, the Debug app over `build/roomcore-release`) `20261007-031532-roomcore` (load1 10.6, something else running on the Mac mini): **31 / 31**, 0 minidumps.

| Check (release framework) | Line |
|---|---|
| ⌘N | `by ⌘N windows=2 in 62.2 ms key=2 active_is_new=true frame1=348,187 1280x800 frame2=370,165 1280x800 cascade=22,22 same_space=true today=0 selected=none card_empty=true rows=2 window_menu=2` (dev 92.8 ms) |
| Shared rename | `window2_row "Pinned A"→"Renamed in window 1" window1_row="Renamed in window 1" in 0.69 ms (same turn)` (dev 0.73 ms): the store's change reaches both sidebars synchronously |
| Today per window | `window2_today=2 window1_today=0 tab_window=2 listed_window2=true listed_window1=false pinned_listed_both=true` |
| Pinned page moves | `in 82 ms window1_page_closed=true window1_holds=false window1_selected=C (its MRU) window1_card_shows_mru=true window2_url=next-b.html window2_canGoBack=true history_length=2 window2_card=true owners=2` (dev **1,582 ms**: the component build's restore and renderer launch); Back then shows `b.html` |
| ⌘1 in window 2 | `key=2 selected_first=true is_pinA=true window1_selection_kept=true`; ⌃Tab's list `window2_has_its_tab=true window1_has_window2_tab=false` |
| Open in New Window | `item=true enabled=true windows=3 selected=true tab_window=3 window2_lists=false window3_lists=true page=e.html window2_holds=false cascade=22,22` |
| Drag out | `near(20pt)_windows=3 past(beyond 40pt)_windows=4 drop=248,947 frame=248,147 1280x800 top_left_at_drop=true selected=true kind=today tab_window=4` |
| Relaunch | four windows, `frame_matches=true` each (window 2 at 260,140 1100×720), window 2 on space "Second", the Today tab `d.html` in window 2 only, `loaded_windows=1 key=1` (only the front window's selection loaded, spec §H) |
| Close window 2 | `windows 4→3 rows=3 entry_gone=true archived=windowClosed library_row=Windows fixture D windowClosed_rows=1`; restored from the Archive into the active window |
| Last window | `windows=0 visible=0 app_running=true rows_kept=1`; ⌘N (the menu bar's key equivalent with no window) `menu_took=true windows=1 same_row=true frame=248,147 1280x800 visible=true`; the Dock's reopen `windows=1 visible=true` |

**Memory with two windows** (summed RSS of every Room process; each row a fresh launch on a fresh state; ten pages = the `memory` spike's ten live sites, one shown per card):

| Build | Baseline (one blank page) | 10 pages, one window | 10 pages, two windows (5 + 5) | Two minus one |
|---|---|---|---|---|
| Release framework (load1 10.6) | 568 / 565 MB, 9 processes, 3 renderers | **4,628 MB**, 28 processes, 20 renderers (renderers 3,996 MB), loaded in 12 s | **4,653 MB**, 28 processes, 20 renderers (renderers 3,992 MB), loaded in 5 s | **+25 MB**, renderers 20 → 20 |
| Dev build (load1 7.5) | 993 / 968 MB | 4,548 MB, 21 processes, 13 renderers, 49 s | 5,651 MB, 26 processes, 18 renderers, 12 s | +1,103 MB, renderers 13 → 18 |

Beside one window's earlier numbers on the release framework (3.9-2, `memory` and `tabsmeasure`): baseline 559 MB, ten hidden pages 4,097 MB (17 renderers), ten loaded of 50 entries 4,801 MB (19 renderers); 4.1b measured the discard order under pressure, no RSS. A second window (its own `RoomBrowser` per profile, 3.2a) costs nothing measurable on the release framework: the renderer count follows the sites, not the windows. Renderers cannot be attributed to a window from the host (no process id in the `Engine` protocol); the pages per window were 10 and 5 + 5. The dev build's +1.1 GB with five more renderers is one run of live sites on the component build (its 49 s load against 12 s says the first run met slower pages); not chased (B-53's rule: measure, do not chase), the release framework is the judge.

### Window-level wiring, not regressed (dev, `20261007-031645-roomcore`)

`extpopup` **18 / 18** (the popups and the key router, now per window through `ExtensionPopupRouter`), `media` **32 / 32** (the media row per tab controller, the PiP panels per window), 0 minidumps.

### Kill test with windows (dev, `20261007-031732-roomcore`)

`--only killtest`: **7 / 7, 100 kills, 0 failures** (52 with a transaction in flight, all rolled back to the previous generation). The harness opens a second window with Today tabs, adds to it and closes it (`archiveToday(window:)` with `removeWindow` in one write); a 15-kill run of the same harness left 2 window rows, Today tabs of 2 windows, 236 `windowClosed` archive rows, no permanent entry with a window and no Today tab without one.

### Unit tier (`CI=1 swift test`)

Model 111 (+2: v9 on a v8 state with two windows → Today rows to the first by position, permanent rows NULL, a state without a window row; a pre-v9 JSON snapshot), Store 57 (+8: per-window Today lists and the shared sections, a shared rename's one change, conversions taking or dropping the window, Clear per window and `archiveToday` with `windowClosed` and its restore into a window, window rows created/removed/moved to front, a relaunch with both windows, orphans adopted, Restore Sidebar's window remap), Tabs 85 (+6: the claim and fallback rules, a pinned page moving with its history and the MRU fallback, per-window Today lists and ⌘1/⌘9 and the switcher's list, the discard policy with another window's visible set, an entry removed elsewhere), Sidebar 42 (+3: the drag-out threshold, the drop frame, the cascade), UIKitCore 56, Design 9, Palette 24, Library 2, Chrome 72, Omnibox 51: all passing; the window tier (no `CI`) UIKitCore 56, Sidebar 42, Tabs 85 passing.

## Phase 4.8b — incognito and the page move through the engine (2026-10-07, Mac mini M4, 24 GB, display 1920 × 1080 @ 60 Hz, RoomCore 155.0.8059.36 with the 4.8b `//room` change, no patch)

### The engine probe (`incognito -RoomSpikeOnly engine`, the dev build, `build/evidence-4.8b/engine-probe-dev.txt`)

On RoomCore's members directly, two windows, load1 11.7:

- `move(toHostWindow:)`: a page with two entries in window 1's `RoomBrowser` (`browsers=w1:1`, `canGoBack=true`, `history.length` 2) moved in **6.1 ms** (6.3–9.9 ms over five runs) into window 2's (`browsers=w2:1`: window 1's Browser closed with its emptied strip); `canGoBack=true`, `history=2`, the same `WebContentsViewCocoa` inside the page's view (`same_chromium_view=true`), in window 2, a 480 × 320 `captureViewport` after the move, Back to `a.html`; a closed page refused (`EngineError.closed`).
- `offTheRecord()`: the twin made in 5.0 ms, the same object on a second call, `offTheRecord()` of the twin refused (`notSupported`), no history service of its own; `cookies.html?set=incognito-engine` in the twin: `room_profile=incognito-engine`, the regular profile's page on the same origin: `""`; the regular history 3 rows, 0 of the incognito URL; `closeOffTheRecord()`: `hasOffTheRecordProfile` false **21 ms** later (no page open); a new twin: a new object, no cookie.
- The navigator hook (B-50): "Open Link in Incognito Window" in RoomCore's context menu on a regular page's link → `didCreate` with `.offTheRecord`, the page in the twin (not the regular profile), `document.referrer` `""` and `window.opener === null` (Chrome's navigator drops both across profiles), into the twin's Browser in window 2 when it had one (`twin_browsers_before=["w2:2"]`); with no twin page open, into a Browser `//room` made for the twin in the opener's window, which the move emptied and Chrome closed (`twin_browsers_before=[]` → `["w2:1"]`). 0 minidumps.

### Tour step `windows` with the move member

Release framework (`ROOM_TOUR_APP`, `build/grand-tour/20261007-044216-roomcore`, load1 ~8): **31 / 31**; the pinned page selected in window 2 is **the same page** (`same_page=true page_state=alive`) moved in **6 ms** (4.8a's unload and reload: 82 ms) with `canGoBack` and `history.length` 2, Back to its first page; ⌘N 70.1 ms; memory, ten live pages on fresh launches: one window 4,178 MB (16 renderers), two windows 5 + 5 4,555 MB (20 renderers), not chased (live sites; 4.8a: 4,628 / 4,653 MB). Dev (`20261007-043732-roomcore`): **30 / 31**, the move in 8 ms (4.8a: 1,582 ms); the one failure 2 × `layout_object.h:518` minidumps from the memory launches' live sites (B-76, as in 4.8a).

### Tour step `incognito` (`scripts/incognito-check.sh`, own state, :8777, :8765, :8772)

Release framework: **20 / 20**; dev: **20 / 20**, 0 minidumps on both. Release lines:

- ⇧⌘N by the menu key: the window in **49.6 ms** (dev 80.5 ms), titled "Incognito" (listed in the Window menu), `NSAppearanceNameDarkAqua` (`Palette.incognitoAppearance`) in both system appearances, the tint `#2A2A33` (`Palette.incognitoTintHex`), the label "Incognito", key; the store's windows 1 / 1 (no row for it), its store ephemeral.
- Its sidebar: `note, separator, newtab` (no essentials grid, no pinned section, one space); the regular window's first row is its space title.
- `cookies.html?set=incognito-main` in incognito: `room_profile=incognito-main`; the regular window on the same page: `""`. After 1.5 s the regular profile's history has 1 row (its own visit of the cookie page) and **0** of the incognito URL; Room's store has 0 entries of it.
- `login.html`, typed sign-in: the regular window's save bubble in 47 ms (the control); the incognito window: **no bubble in 8,010 ms**, the form submitted (`/login`).
- "Open Link in Incognito Window" from a regular page's context menu (Chrome's item, now offered): the incognito Today list 2 → 3, the regular list 3 → 3, `next-a.html` in the incognito window, which is key, in 60 ms.
- The 3.6 fixture extension, pinned in the regular profile: in the incognito header only after "Allow in incognito" (the engine's `IsIncognitoEnabled` true), gone again after it is turned off (engine false); the regular header shows it throughout.
- Captures (`research/screenshots/phase-4.8b/`): the incognito window light and dark (identical: the window is dark in both), the regular window in each for contrast.
- Closing the window: closed in 14 ms, its 3 pages closed (the twin's page count 3 → 0), the twin gone **38 ms** after the close (dev 50 ms), renderers 0 (launch) → 8 (open) → 4 (closed: the regular window's three pages and the fixture extension), the store's windows still 1, the reader folder removed.
- Reopened: a new twin, `cookies.html` shows `""`.
- Net-log (`--log-net-log`, a fresh state, the incognito window opened at launch and left 20 s idle): **0 hosts, 0 URL requests** (27 events).

### Unit tier (`CI=1 swift test`)

Engine 80 (+5: the twin one object until closed with its own cookies, a closing twin refused, an off-the-record open belongs to the twin, a moved page keeps its history and opens in its new window, Allow in incognito per extension), Tabs 85 (the move test now checks the same page and its window), Sidebar 43 (+1: the incognito tree), Store 58 (+1: the incognito store writes nothing), UIKitCore 56, Design 9; all passing; the window tier (no `CI`) UIKitCore 56, Sidebar 43, Tabs 85.

## Phase 4.9 — the full tour (2026-10-07, Mac mini M4, 24 GB, display 1920 × 1080 @ 60 Hz, RoomCore 155.0.8059.36 with 4.8b's `//room`, `RoomCoreCommit 5c039c3`, series 23)

**Method.** `scripts/grand-tour.sh --no-build light dark`, one state per appearance, the test servers once, the Claude desktop app frontmost throughout, no Chromium build running, the user's own Room not touched. Two builds: the **dev build** (`build/roomcore/DerivedData/Build/Products/Debug/Room.app`, the component framework with `DCHECK_ALWAYS_ON`, rebuilt with `scripts/roomcore-package.sh --app-only` from `8e891ff`) and the **release framework** (`ROOM_TOUR_APP=build/roomcore-release/DerivedData/Build/Products/Debug/Room.app`, the Debug app over the official framework, rebuilt with xcodebuild per `docs/laptop-build.md` §A step 3 from `1555793`, i.e. with this session's B-92, harness fixes and the validator line). 47 steps in eleven groups (Chapter 3's 34 plus the chapter's 13: `archive`, `recovery`, `routing`, `import`, `settings`, `settings2`, `extpopup`, `extensions`, `media`, `documents`, `reader`, `windows`, `incognito`). Crashes and numbers are judged on the release framework; the dev tour is for correctness.

### Totals

| Run | Directory | Conditions at the start (`conditions.tsv`) | Wall time | Light | Dark |
|---|---|---|---|---|---|
| Dev build | `build/grand-tour/20261007-045544-roomcore` | load1 7.13, 0 other Room processes, no build | **61.6 min** (31.6 + 30.0) | **893 passed / 15 failed** of 908 | **894 / 14** of 908 |
| Dev build, the same outputs re-evaluated with the three fixed checks (below) | (the tour's own top-level `summary.md`, written after the fixes landed in `tour_checks.py` mid-run) | — | — | 896 / 12 | 897 / 11 |
| Release framework | `build/grand-tour/20261007-060609-roomcore` | load1 8.85, 0 other Room processes, no build | **45.9 min** (22.8 + 23.1) | **899 / 5** of 904 | **897 / 7** of 904 |

The release framework lists 4 fewer checks per appearance: the per-step crash check is listed only for steps that left a minidump (none there). Chapter 3's exit tour (3.9-2, dev only): 505 / 6 of 511 per appearance, 41.4 min.

**Minidumps.** Dev: **11 DCHECK minidumps per appearance**, the same in light and dark: memory 4, quittiming 3, open10 1, `windows`' memory launches 2 (its own engine directory), all `layout_object.h:518 !NeedsLayout() || ChildLayoutBlockedByDisplayLock()`, and palette 1 × `inline_node.cc:2297`; no `//net` DCHECK this time (3.9-2 had one in dark). Release framework: **0** in both appearances. Both builds: the one renderer `chrome://crash` kills in `chrome26b` (no FATAL line, expected, the step passes).

### Every failure attributed

| Step | Build | Appearance | Failed check(s) | Cause | Row / commit |
|---|---|---|---|---|---|
| memory, open10, quittiming, palette | dev | light, dark | no helper crash report (4, 1, 3, 1 minidumps) | the dev build's Blink DCHECKs on live sites (stated condition; 0 on release) | B-76 |
| windows | dev | light, dark | no engine minidump in the run's own engine directory (2) | the same, from the memory launches' live sites (as in 4.8a, 4.8b) | B-76 |
| cookies | dev | light, dark | engine profiles are direct children of the root | **harness fault**: the check wanted `Room Profile Default, Room Profile Work`; since 4.4b the directories are keyed by the profile's id (B-22). Check fixed (`e1d91e1`); rerun `--only cookies` 14 / 14 | `e1d91e1` |
| palette2 | dev | light, dark (2 checks each) | `>re` filters commands (light; dark) | **harness fault**: the check wanted exactly `["Reload", "Reload without Cache"]`; 4.7a's Capture Screenshot and 4.7b's Reader Mode match `>re` too. Check fixed; rerun 26 / 26 | `e1d91e1` |
| app28a | dev | light, dark | `menu_app_items_without_validation: none` | **product, one line**: 4.4b's Room ▸ Settings Section items had no validator; added (`1555793`); rerun 29 / 29 dev, 29 / 29 in the release tour | `1555793` |
| app28b | dev | light, dark | a link after ⇧⌘W brings the window back with it | **harness fault**: the spike read the window it had closed; since 4.8a the close tears its session down and the link reopens the kept row as a new window. Spike reads the app's window now; rerun 25 / 25 dev, 25 / 25 in the release tour | `e1d91e1` |
| import | dev; release | light, dark; light, dark | imported history is found through ProfileHistory.search in the same launch | **harness fault, partly fixed**: the spike took the search's first row, and the tour's shared state has other history matching "Swift.org" (palettemeasure's 50,000 generated rows: `https://www.bikeissue1366.org/swift/game/blog/26986`); it now takes the row with the fixture's title among 1,000 (`e1d91e1`): `--only palettemeasure,import` 65 / 65 with `Swift.org=https://swift.org/` (`20261007-060431`), but the release tour, run with the fix, still read the generated row in both appearances: something else in the full tour's history outranks it (not chased). The import itself passed every other check (`safari_applied … history urls=4 equal=true`) | B-100 |
| tabs | both | light, dark | Discard Background Pages: renderers released | renderers 15 → 16 after seven discards (dev 3,638 → 3,776 MB; release 1,957 → 2,014 MB) | B-56 |
| tabsmeasure | dev | light, dark | switching median and p95 under 16 ms | dev 16.23 / 19.02 and 17.13 / 19.47 ms | B-53 |
| tabsmeasure | release | light, dark | switching p95 under 16 ms | median passes (14.20 / 15.72 ms), p95 17.27 / 18.26 ms (3.9-2: 12.88 / 20.87) | B-53 |
| settings2 | dev | light only | Clear browsing data, last hour: … the cookie goes | the cookie `room_profile=work` survived "Last hour, History and Cookies" in the full tour's shared state (history went: `fresh=false old=true`); `--only settings2` 26 / 26 (`20261007-055912`), the dark run and both release runs passed: not reproduced, not chased | **B-99** |
| palette2 | release | light, dark | the chip: secure / insecure for Chrome's LocationBarModel (2) | **cannot run on the release framework**: the check reads Chrome's `LocationBarModel` through a spike hook the official framework does not have (`spike hooks unavailable (roomSpikeCommand: on RoomBrowser)`, B-82's guard); the host's chip half passed (`host=secure`, `host=insecure`); the dev tour passed both | B-82 (by design) |
| layoutmodes | release | dark only | reveal slide drops no frame | one frame of 72 at 26.2 ms (median and p95 16.67 ms): a run condition; `--only layoutmodes,incognito dark` 55 / 55 (`20261007-065223`, load1 4.52) | — (condition) |
| incognito | release | dark only | Open Link in Incognito Window lands in the incognito window | the context-menu item was not found in 10 s with another app key (`item="none" … key=other`): the run's activation condition; the standalone rerun found it and landed in 52 ms | — (condition) |

`--only` reruns used for attribution: dev `cookies,palette2,palettemeasure,settings2,documents,app28a,app28b,import light` (`build/grand-tour/20261007-055912-roomcore`, load1 6.49: **226 / 1**, the one failure `import` before the second spike fix), dev `palettemeasure,import light` (`20261007-060431`: **65 / 0**), release `layoutmodes,incognito dark` (`20261007-065223`: **55 / 0**). No `window_main` failure and no Stack Overflow quit in any run.

**B-92 on the dev build.** The prune at launch on a throwaway state (`/tmp/room-4/b92`, 55 PNGs 1–55 min old and 3 eight days old in `Screenshots/`): `Room: screenshots pruned 8 of 58`, 50 left, the oldest kept `new-50.png`; then `documents` 42 / 42 in the rerun above (the step's result lines as in 4.7a: the full page 2068 × 8000 px, the swatch 480 × 241 px, the MHTML 2,542 B reopened).

### Numbers (release framework, light / dark; dev in brackets, light / dark)

| Measure | 4.9 tour, release framework | 4.9 tour, dev | Chapter 3 / 4 reference (release) |
|---|---|---|---|
| Memory baseline (summed RSS) | 731 / 745 MB | [1,236 / 1,243 MB] | 559 MB (3.9-2) |
| 1 / 10 / 30 hidden pages | 887 / 4,641 / 8,242 and — / 4,433 / 9,056 MB (21 / 18 renderers at ten) | [1,623 / 5,071 / 10,481 and — / 5,031 / 10,882 MB] | 748 / 4,097 / 8,725 MB (3.9-2) |
| 10 loaded of 50 entries (tabsmeasure) | 4,448 / 4,499 MB, 17 renderers | [6,170 / 6,270 MB, 17] | 4,801 MB, 19 renderers (3.9-2) |
| 50 loaded over 5 spaces | 4,964 / 4,970 MB, 52 renderers | [10,381 / 10,380 MB] | — |
| Ten live pages, one window / two windows (fresh launches) | 3,046 / 4,633 and 3,293 / 4,664 MB (16 / 20 and 17 / 20 renderers) | [4,570 / 5,652 and 4,627 / 5,751 MB] | 4,628 / 4,653 MB (4.8a), 4,178 / 4,555 MB (4.8b) |
| Tab switch: click → committed, median / p95 | 14.20 / 17.27 and 15.72 / 18.26 ms | [16.23 / 19.02 and 17.13 / 19.47 ms] | 12.88 / 20.87 ms (3.9-2) |
| Relaunch: load start; selected loaded | 0.65 s; 0.78 s and 0.65 s; 1.26 s | [2.56 s; 6.47 s and 2.53 s; 7.51 s] | 0.56 s; 1.33 s (3.9-2) |
| Quit with ten pages (3 runs) | 0.37 / 0.37 / 0.31 and 0.30 / 0.29 / 0.30 s, 0 helpers (load1 6.3–7.9) | [0.36–0.37 and 0.34–0.36 s, load1 13.8–22.8] | 0.24–0.30 s (3.9-2) |
| Kill test, 100 kills: commit median / p95 | 16.54 / 24.32 and 16.17 / 24.62 ms, 0 failures | [16.22 / 24.54 and 15.74 / 24.39 ms] | 11.41–11.67 / 15.67–16.65 ms (4.1a, 4.1b, dev, a fresh state) |
| Peek: decision → overlay frame; → first paint, median | 25.7 / 27.1 ms; **76.5 / 76.9 ms** | [28.6 / 31.5; 479 / 885 ms] | 69.54 ms first paint (4.2) |
| Palette at 50k rows: first key median; later keys p95 | 17.06 / 17.00; 10.57 / 11.01 ms | [17.39 / 18.33; 12.57 / 11.10 ms] | — (3.9-2 dev: 21.75; 9.79–10.00) |
| Space switch ⌃digit → first slide frame, median / p95 | 13.76 / 18.88 and 13.26 / 16.94 ms | [20.11 / 30.26 and 18.68 / 32.73 ms] | — |
| ⌘N → second window | 68.6 / 67.6 ms | [96.4 / 91.0 ms] | 62.2 ms (4.8a) |
| A pinned page moved to another window | 6 / 6 ms, the same page | [8 / 8 ms] | 6 ms (4.8b) |
| ⇧⌘N → incognito window | 53.3 / 47.5 ms | [71.2 / 68.5 ms] | 49.6 ms (4.8b) |
| ⌥⇧⌘R → reader page | 104 / 106 ms (distilled 13 ms) | [153 / 148 ms] | 107 ms (4.7b) |
| The PDF fixture loaded | 340 / 340 ms | [4,105 / 4,050 ms] | 349 ms (4.7a) |
| Find, keystroke → match median / p95 | 9.1 / 416 and 9.7 / 415 ms | [44 / 425 and 27 / 423 ms] | — |
| Cold launch by a link: event → requested | 374 / 382 ms | [232 / 224 ms] | — |
| The state opened at the first launch (a fresh state) | 5.1 / 5.2 ms | [5.4 / 5.7 ms] | 11.9–12.1 ms on the 50k state (3.9-1) |
| Engine requests (netlog step) | 0 / 0 hosts | [0 / 0] | 0 (3.9-2) |
| Suggestions on, requests for three queries | 34 / 34 | [34 / 34] | 34 (3.5, B-64) |

The release framework's memory rows read higher at rest than 3.9-2's (baseline 731–745 against 559 MB) and lower with ten loaded pages (4,448–4,499 against 4,801 MB): the tour's state now carries more (Archive rows, backups, imported profiles, extensions from earlier steps) and the live sites differ by day; not chased (5.4). No cold launch of a Release app and no DMG size in 4.9: no release app was built (the DMG is build 10's, 188,415,784 B).

## B-30 — built-in ad and tracker blocking, the `adblock` spike (2026-10-18, M1 Max laptop, 64 GB, RoomCore 155.0.8059.36 + patches 0026/0027, component dev build, Debug app)

Measured with `scripts/adblock-check.sh` (fixture `research/spikes/phase-5-adblock/`, served on 127.0.0.1:8777 and opened as `news.test`, with third-party files from `ads.test`, via `--host-resolver-rules`). The final run is `build/adblock-check-final.txt` (load 10.6); its capture is `research/screenshots/chapter-5/adblock-fixture.png`.

**Engine**

| What | Number |
|---|---|
| Rules in the bundled lists | EasyList 83,332; EasyPrivacy 56,345; EasyList Cookie List 25,318 |
| Engine built from text, first launch | 128–139 ms; serialized 7,305,837 B, which is also the cache file |
| Engine read from cache, later launches | 37–39 ms |
| Launch wait before the first page | 0.14 s first launch, 38–40 ms cached (0.30–0.40 s before the rule counting moved off the main thread) |
| Rebuild after a custom-rule edit | 117–124 ms, off the UI thread; pages keep the old engine until the new one is in |

**Decisions on real list URLs** (source `https://news.example/`)
- Blocked: `pagead2.googlesyndication.com/.../adsbygoogle.js`, `securepubads.g.doubleclick.net/tag/js/gpt.js`, `www.google-analytics.com/analytics.js`, `facebook.com/tr?…` (image).
- Allowed: the site's own script and a cdnjs script.

**The fixture page with the spike's custom rules**

| Request or element | Result |
|---|---|
| Third-party script, pixel and `fetch` | blocked |
| EasyList's own `/jquery.overlayad.js` | blocked |
| `$redirect=noop.js` script | served the empty body: `onload` fired, the original did not run |
| First-party script | loaded |
| Site-specific `news.test##.ad-slot` | hidden |
| Generic `##.room-generic-ad` | hidden: the class collector asked the browser and got a user-origin stylesheet back |
| Content | visible |
| CookieYes-style banner | autoconsent detected `cookieyes`, clicked Reject in one click (3 ms), cookie `advertisement:no`, banner gone |
| Page's blocked count | 5 |

**Per-site switch**
- With `news.test` allowed, after a reload: everything loaded, nothing hidden, the banner left alone, count 0.
- Blocked again, after a reload: everything blocked again, count 5. This needs the renderers' memory cache cleared when the configuration changes; without it the scripts loaded while the site was allowed came back from memory unchecked (first run).

**Load time** (`timing.html`: 40 allowed requests, 400 elements with classes, reloaded in one tab, `performance` load event end, medians of 5, two interleaved rounds)

| Mode | Median |
|---|---|
| Blocking off | 62–63 ms |
| Lists only | 62–63 ms (no measurable cost) |
| Lists + cookie banners Reject | 80–85 ms (+18–22 ms: autoconsent's 426 KB script, parsed in every document) |

**Memory.** The browser process's footprint does not show the engine (114.3 MB with the defaults, 115.1 MB with no lists: the allocator keeps freed pages). The engine's own size is its 7.3 MB flatbuffer.

**What the first runs found** (fixed, one commit each)
1. The RoomCore app's spec did not copy `Resources/ContentBlocking`, so the engine had only the custom rules (869 B).
2. EasyList exempts `127.0.0.1` and `localhost` from generic hiding (`@@://127.0.0.1$generichide`); the fixture moved to `.test` hosts.
3. Isolated-world scripts run from `DidCreateDocumentElement` were silently not run. Blink forbids script inside that notification; `ExecuteScriptInIsolatedWorld` returned nothing, and a direct `v8::Script` run hit `Check failed: !ScriptForbiddenScope::IsScriptForbidden()` (minidump). They now run from `ExtensionFrameHelper::ScheduleAtDocumentStart`, the step extensions' document-start scripts use, still before the page's own scripts.
4. autoconsent 16.55.0's constructor initializes before creating its DOM helper when given a config (`TypeError … 'prehide'`); it is now constructed bare and initialized after, as its standalone build does.
5. autoconsent's eval requests are already-invoked expressions (`(()=>!!window.Cookiebot)()`); the wrapper called them again, so every check answered false.

### B-30 — uBlock Origin's scriptlets, the `scriptlets` section (2026-10-18, M1 Max laptop, 64 GB, branch `claude/adblock-scriptlets`)

`scripts/adblock-check.sh` (full run `build/adblock-check-scriptlets.txt`, load 30). The fixture's custom rules add `news.test##+js(set-constant, roomFlag, true)` and `news.test##+js(trusted-set-cookie, roomTrusted, 1)`; the page reports `typeof roomFlag` and the cookie.

| Step | `room_flag` | `roomTrusted` cookie | `redirect=googletagmanager_gtm.js` |
|---|---|---|---|
| No uBlock list (Room's resources only) | unset | no | blocked, no body |
| uBlock filters – Unbreak turned on: list, uBO 1.75.0's 151 scriptlets and 46 redirect bodies fetched, engine rebuilt, in 0.7–2.7 s | **true** | no (custom rules are not trusted) | **served** (uBO's stand-in: `window.ga` is a function) |
| Turned off again | unset | no | blocked, no body |

The redirect column is from the second session (full run `build/adblock-check-redirects.txt`).

- **Conversion** (Release harness, the same Swift code): 35 modules, 343 KB fetched; linking 28 ms, JavaScriptCore 17 ms, converting 2 ms; 326 KB of resources JSON, 158 resources once merged with Room's 7.
- **Redirect bodies:** the index (47 entries, `click2load.html` left out) read in 1.6 ms, 46 bodies of 103 KB made into resources in 2.4 ms. The merged file is 197 resources, 469 KB. adblock-rust on it: `redirect=googletagmanager_gtm.js` serves `google-analytics_analytics.js` (an alias), `redirect=noopvast-4.0` an empty VAST, `redirect=noop.js` Room's own body, and `redirect=google-ima-dai.js` nothing (it needs trust, and permissioned resources are never redirects).
- **Second session found:** the spike's own scripts run in an isolated world, so reading `window.ga` there said `undefined` while the stub had run. An inline script now reads it in the page's world.
- **adblock-rust's `resource-assembler`** on 1.75.0's `scriptlets.js`, or on all 32 resource files concatenated: 0 resources.
- **Trust** (adblock-rust 0.13.3 on the merged file): `+js(set-constant, …)` injects from any list (15.4 KB of script); `+js(trusted-set-cookie, …)` only from a list with the trusted bit (19.2 KB).
- **First run found:** with the list on, `room_flag` stayed unset. uBO's helpers read `scriptletGlobals`, which uBO's injector declares and Room's did not (JavaScriptCore, the real injected script: `ReferenceError: Can't find variable: scriptletGlobals`, caught by adblock-rust's `try`). Fixed in `content_blocker.cc`: the script runs inside a function that declares it.
- **Rest of the spike:** unchanged with the wrapper (engine, page, allowed, timing; every check as before). `ublock_scriptlet_files_in_app: 0`.
- **Build:** `//room` incremental 48 s at 8 jobs (load 13–32), `roomcore-package.sh --app-only` 27 s.

## Phase 5.0a — the dev bundle id, the live-site check, B-106 to B-109, B-100 (2026-10-21, M1 Max laptop, 64 GB, 60 Hz Pro Display XDR main, RoomCore 155.0.8059.36, series 25, `RoomCoreCommit 981429c`)

Load average 20–45 throughout (the official incremental build and packaging beside some runs). Dev = `build/roomcore/…/Debug/Room.app` (component framework, spikes); release = the Debug app over the official framework (`build/roomcore-release/…/Debug/Room.app`). Both are `app.room.desktop.dev` now.

### The dev bundle id

- `CFBundleIdentifier`: dev Debug app, release-engine Debug app and the Debug embryo host `app.room.desktop.dev`; the Release app and the Release host `app.room.desktop` (`/usr/libexec/PlistBuddy`, after `roomcore-package.sh`, `--release`, `CONFIGURATION=Debug --release --app-only`).
- A running Debug app with no state flags (pid 60396, `lsappinfo`: `bundleID="app.room.desktop.dev"`) opened `~/Library/Application Support/Room Dev/Room.sqlite` and `Room Dev/RoomCore/Default/History` (`lsof`); Chromium's singleton was `Room Dev/RoomCore/SingletonLock -> JL.localdomain-60396` with its socket in `$TMPDIR/app.room.desktop.dev.vYKydi/` (the base bundle id keys the directory); the real root `Room/RoomCore` had no `SingletonLock`; the defaults domain `app.room.desktop.dev` was empty. Quit by pid (`room_quit`), clean.
- Beside a Release Room: not run. The user's Room was not running, and a Release app on a throwaway state is not possible (the Release build has no `-RoomEngineDirectory`, so it would open the real engine root). The handoff is Chromium's `ProcessSingleton` on the engine root (`SingletonLock`/`SingletonSocket` in the user data directory), so a Debug app on `Room Dev/RoomCore` or `<state>/engine` cannot reach the Release app's; the keychain: ad-hoc Debug builds run with `--use-mock-keychain` (`main.swift`, `room_application.mm` `IsTeamSigned`), so no "Room Safe Storage" item is shared.

### The live-site check (`scripts/live-check.sh`, `-RoomSpike live`)

Per site two passes, each in a fresh tab: `off` (the site panel's switch off) then `on` (the defaults: bundled EasyList, EasyPrivacy, EasyList Cookie List; cookie banners Reject). "lists hid" = elements the bundled lists' `##` hiding rules (generic and the site's, 28,907 selectors, prefiltered by the page's ids and classes) match, and of those hidden.

| site | pass | blocked dev / release | lists hid (dev) | lists hid (release) | consent | autoconsent | player |
|---|---|---|---|---|---|---|---|
| delfi.lt | off | 0 / 0 | 0/0 | 0/0 | `#CybotCookiebotDialog` visible | none | — |
| delfi.lt | on | 15 / 15 | 0/0 | 0/0 | none visible | none | — |
| 15min.lt | off | 0 / 0 | 0/117 | 0/117 | `#CybotCookiebotDialog` visible | none | — |
| 15min.lt | on | 47 / 44 | 116/116 | 116/116 | none visible | none | — |
| dailymail.com | off | 0 / 0 | 1/20 | 1/23 | none | none | — |
| dailymail.com | on | 13 / 13 | 23/23 | 23/23 | none | none | — |
| youtube.com/watch | off | 0 / 0 | 4/5 | 4/5 | `tp-yt-paper-dialog#dialog` visible | none | `#movie_player`, `video` |
| youtube.com/watch | on | 4 / 4 | 5/5 | 5/5 | none visible | `youtube-desktop: opted-out` | `#movie_player`, `video` |

`live-check: 0 failure(s)` on both builds (dev 2026-10-21T01:21Z, release 01:33Z). Findings: EasyList has no delfi.lt hiding rules and its generic ones match none of delfi's elements, so delfi's checks are its blocked requests and the banner; the Cookiebot banners on delfi and 15min go through the EasyList Cookie List's hiding, not autoconsent (no `didHandleCookieBanner`); YouTube's consent dialog is answered by autoconsent. The page with blocking off held 50,212 (delfi) and 53,348 (15min) elements against 2,664 and 6,051 with it on. dailymail.co.uk redirects to dailymail.com from Lithuania (the per-site switch keys on the site loaded, so the file names the .com). First attempts: a reload of delfi in the same tab left it with no live document (`executeJavaScript` "the page has no live document" 4 times); the probe over all 28,907 selectors on a 50k-element page did not answer (`error`): a fresh tab per pass and the id/class prefilter fixed both.

### B-106 (`-RoomSpike downloadprompt`)

The setting set through the store as Settings' switch writes it; the step's URL `http://127.0.0.1:8766/download?name=asked.bin&size=200000` typed as a new tab, then a link click: dev `panel=true sheet=true proposed=asked.bin` and `proposed=clicked.bin`, both cancelled, nothing listed, no file; release the same. Not reproduced. The by-hand state `/tmp/room-4/hand`: `RoomCore.log` has one `asks the host (asked.bin)` (02:03:32) and the saved settings `askWhereToSave: false`. Each download now logs `Room: download <id> (<name>): asking where to save | to <path>`.

### B-107 (`-RoomSpike media -RoomSpikeOnly backtotab`)

- Dev: `backtotab_video: overlay=true other_selected_before=true hook=1 opener_selected=true opener_shown=true overlay_closed=true` (the overlay's back-to-tab path, `ExitPictureInPictureViaWindowUi(kCloseWindowAndFocusOpener)`, through the dev framework's `pip-back-to-tab`); `backtotab_document: button=Back to Tab other_selected_before=true opener_selected=true opener_shown=true panel_closed=true opener_alive=alive`.
- Release: `hook=-98` (no spike hooks in the official framework; the overlay button's click is a click check), the document panel's button as on dev.
- The fixture link of step 53: `curl http://127.0.0.1:8776/phase-3.7/pip.html` 200 once `test-servers.sh` serves :8776.

### B-108 and B-109 (`-RoomSpike sidebarfixes`)

Dev and release the same: `b108_resize: width 300 → 420: before pill x=8 w=284 row x=8 w=284; after pill x=8 w=404 row x=8 w=404 follows=true` (the width set as the edge's drag sets it, six steps); `b109_close: hovered before=two after=three close_button=true` (the outline's pointer held still over "two", "two" closed). Without the fixes the two unit tests fail (`HoverAndPillTests`, checked by removing them).

### Engine step (B-107) and B-100

- Baseline on the dev host after the step: nav assertions passed (21.3 s), three ten-page quits 0.343 / 0.738 / 0.424 s, 0 helpers left, no crash reports (load 29–39).
- `grand-tour.sh --no-build --only palettemeasure,import light`: dev 65 / 65 (0.9 min), release 65 / 65; `history_search` found all four fixture rows by title search (`Swift.org=https://swift.org/ visits=1`), so the new `via=row` fallback was not needed in these runs (the full tour, 5.9, is where it was).

## Phase 5.0b — the skipped Chapter 4 steps, `-RoomSpike skipped` (2026-10-21, M1 Max laptop, 64 GB, 60 Hz Pro Display XDR main, RoomCore 155.0.8059.36, series 25, `RoomCoreCommit 981429c`, no engine change)

Load average 17–25 throughout (no Chromium build). Dev = `build/roomcore/…/Debug/Room.app`; release = the Debug app over the official framework (`build/roomcore-release/…/Debug/Room.app`); both `app.room.desktop.dev`. `scripts/skipped-steps.sh <dir> [41 … 48]`: one launch per group (two for 42, 45 and 48: the relaunch on the same state), each on its own state under `/tmp/room-5/skipped/`, search suggestions off; output `build/5.0b/{dev,release}/`. Every line below is the same on both builds unless it says otherwise.

### 4.1 (group 41, `archive`)

- Step 3, the context menu's items through `performActionForItem`, the toast's button through `ToastQueue.performAction` (the button's own path): Archive Tab `gone=true row=manual toast="1 tab archived" button=Undo`, Undo `back=true order abcde→abcde`; Archive Tabs Below on the first of five `archived=4 of 4`, toast "4 tabs archived", Undo restores the order; the item is disabled on the last row; Archive 2 Tabs on a ⌘-click pair (the clicked menu, `debugClickedMenu`) `toast="2 tabs archived"`, rows reason `manual`.
- Step 2: the Library `archive=3 (manual=3)`; Restore of a tab navigated to a second page `top=true selected=true url=a2 canGoBack=true` (the row kept its back/forward list); × (`deleteArchived`, the row button's closure) `rows 2→1`, nothing restored; Clear Archive… asks "Clear the Archive?", Cancel keeps the rows.
- Step 5: ⌘↩ on the palette's Archived row (index 2) `today 3→4 copy=true copy_selected=true row_kept=true`.
- Step 4: `ArchivePolicy.afterHoursOptions` = 12, 24, 168, 720 h; with 24 h a tab unused for 13 h (the store's clock moved) stays (`archived=0`), with 12 h it goes (`archived=3`, the selected one kept).
- Step 6: Delete Space with its toast left to go (`"Deleted “Skipped Gone”" button=Undo`, rows `spaceDeleted` ×2), then Restore from the Library lands in the active space, selected. The rows' chip reads "Deleted space" (B-124).
- Step 7: History `rows=6` under one day, a row's click (`onOpen`) opens a new tab, Delete All from 127.0.0.1 leaves 0 rows of the host. Downloads: `scripts/download-remove-check.sh` on both builds `result: passed` (the Library's Remove and the popover's Clear stay gone after a relaunch; the kept one is listed again).
- Step 8: Help ▸ Restore Sidebar… (`showRestoreSidebar:` sent through the responder chain) after a backup and a real deletion: the sheet lists the backup ("4 entries · 2 spaces · 5 archived"); the Restore button's closure brings the space back, the toast "Sidebar restored from 21 Oct 2026 at 5:39", the selection loaded; reopened, two rows, the newest first and labelled `before-restore`. (5.0a's click check a, by the sheet's own closures.)

### 4.2 (group 42, `routing` on the routing fixture, then `routingverify`)

- Step 11, links from another process: the wrapper runs `open -a <app> <url>` for each line the spike asks for (LaunchServices' event; `debugIncomingLog` `event` → `requested`): `other.html?route=work` → `space=Work shown=Space toast="Opened in Work" button=Switch 5 s`; `localhost:8770/site.html` → Play with "Opened in Play"; `site.html?x` → Space, no toast.
- Step 12: the pointer over the toast (`setHovering(true)`) holds it 6 s past its 5 s; Switch shows Work with the routed tab in the card, the toast gone.
- Step 13: the sheet from the space's menu (`onRoutingSettings`): rule 2 unticked and back; rule 3 up and down by the chevrons' `move(by:)`; rule 1 edited to `equals example.com → Work`; a regex `([a-z` → inline "Not a valid regular expression (…)", Save greyed; Try a URL `localhost:8770 → Opens in Play (rule 2)`, `apple.com → Opens in the default: Space`; the relaunch reads `1.equals example.com→Work | 2.equals localhost→Play | 3.contains site.html→Work off`. Return and Esc as synthetic key events to the sheet: Return did not save the valid regex (`saved_by_return=false`, the model's save then did), Esc closed the whole sheet with an edit open (`sheet_open=false`); the field had no keyboard focus (the model was set directly), so real keys in the field are a click check.
- Step 14: Add Route for Domain… on a Today tab (`pattern=localhost`: that row was the routed localhost tab) and on a pinned entry (`pattern=127.0.0.1 target=Space`); Cancel adds no rule (`rules 3→3`).
- Step 16: with "Route links between spaces" on, a ⌘-click on the page's `#offsite` (localhost) goes to Play with the toast; off, it opens directly under Home with no toast; ⇧-click opens Peek and a plain same-site click navigates in place, on and off alike.
- Step 18: ⌘D pinned the Home tab; its off-site link in Peek, ⌘O (`expandPeek:`) → the first Today tab, selected; from a Today tab with tabs below it, ⇧-click then ⌘O → directly under it.
- Step 19: Delete Space on Work takes its rule (`1.equals localhost→Play` left); the toast's Undo brings the space and the rules back in their order (`same=true`).

### 4.3 (group 43, `importsheet` on the 4.3 fixtures)

- Step 20: ⌘T `import`: the command is row 2 under the typed text; ↓ Enter opens the sheet, nothing picked, Import greyed; Chrome's fixture: "Person 1", "31 bookmarks in 9 folders", "10 pages, 16 visits", extensions "2 found" unticked, passwords unticked; the preview: "Will add 1 new space, 7 folders, 27 pinned, 9 history pages." → bar into Essentials "… 15 pinned, 12 essentials …" with "2 past the Essentials cap (12) pinned instead" → one space per folder "4 new spaces, 5 folders" → into Space "3 new spaces" → no history (the history part gone); Cancel: `spaces=1 entries=0` before and after.
- Step 21: the open panel's answer (`addChosen`): `safari` "10 bookmarks in 4 folders", "4 pages, 6 visits"; `netscape/bookmarks.html` "7 bookmarks in 3 folders"; `pages` "Room cannot import from pages: choose a browser's folder, a profile folder or a bookmarks .html file." The chosen source is read but not listed first (the fixtures stay above it).
- Step 22: the toast and the summary "Imported from chrome (fixture): 1 space, 15 pinned tabs, 7 folders, 12 essentials, 8 history pages" (the step's text); Google Chrome: Site 11, Site 12, Work, L1 (L2–L5 inside), Beta, Reading, Example, Mobile; 12 essentials; ⌘T `typed three` → the history row "Typed three times".
- Step 23: Arc's Home: News, [Projects], Mail, Calendar pinned, Today "Search"; Work on profile Work with its own grid (Chat, shown).
- Step 24: spaces Safari, Dev, Recipes, Reading List, Travel; ⌘T `swift.org` → the top hit "Swift" (the history row).

### 4.4 (group 44, `search`)

- Step 33 through the editor's save path: a URL without %s refused ("Put %s in the search URL where the search terms go."); MDN (on the local server) saved and made the profile's default; its Remove refused ("It is a default: choose another default first."); ⌘T `fetch api` Enter → `site.html?mdn=fetch%20api`; `yt` Tab → the YouTube chip, `cats` Enter → `https://www.youtube.com/results?search_query=cats` (the one live request); back to the default, MDN removed. ⌘T sent as a synthetic key with the results page focused (`RenderWidgetHostViewCocoa`) did not open the palette in this run; the palette was opened directly for the keyword part (the `keys` tour step covers ⌘T from a page).

### 4.5 (group 45, `extensions` with the 3.6 fixture, then `extensionsverify`)

- Step 47, Details: `version=1.0`, "Unpacked from …/research/spikes/phase-3.6/extension", ID `kdlkcobhfhjkbkgckadmghlkpbinlpen`, 57 KB, "Read and change all your data on all websites"; Allow in incognito stored, still stored after the relaunch; the engine's bit is set when an incognito window opens (`engine=false` before, `true` after).
- Step 46: On click: the site panel's row with Run; its menu: Unpin (the header loses the action) and Pin again, Options opens the options page as a tab, Manage Extensions… closes the panel and shows Settings ▸ Extensions; Run, Always on 127.0.0.1, reload: badge `T1` without Run.
- Step 73 (fixture): in the incognito window the allowed extension's button is in the header and its popup opens over the incognito window (`over_incognito=true`).

### 4.6, 4.7 (groups 46, 47)

- Step 54: the Privacy line "Autoplay follows Chromium's default: sound may start only after you interact with a site."; before any click an unmuted `play()` → `NotAllowedError` (muted audio too: Chromium allows muted autoplay for video only; not probed), after a click → `played`, audible.
- Step 64: a click into the page, ⌘P as a key → the preview has the keyboard; three Tabs keep it there; Return **not pressed**: this Mac has three printers and the preview's default destination is the system's (the tour's and this group's first runs printed three real pages, B-126); Esc closes the preview.

### 4.8 (group 48, `windows` then `windowsrelaunch`)

- Step 66: ⌘D in window 1 → the entry pinned and listed in window 2; a pinned reorder shows in window 2's rows (C at y 36 above A at 72); ⇧⌘D → in both windows' grids; ⌘T in each window opens that window's palette and puts the tab in its own Today list only; Open in New Window on a pinned entry → a third window, cascaded 22,22, still pinned.
- Step 74: a pinned page with a script variable and a half-filled input moved to window 2 and back: the same page object, `[74,"half-filled"]` both times, the other window releasing it.
- Step 65: a pinned entry's drag ending 200 pt past the window: a new window on the same space with it selected and loaded, still pinned and listed in both.
- Step 68: three windows on three spaces at 900×640, 980×680, 1060×720, each with its selection; after the relaunch every one is back with its space, size and selection, the Window menu names them by space, only the front one loaded; a background window loads its selection when it becomes key.
- Step 67: all three closed: no window, the Window menu empty, their Today tabs archived (`windowClosed 0→4`); the Dock's reopen (`applicationShouldHandleReopen`) brings a window back with the same frame, space and selection.

### The tour steps that already drove skipped steps (`grand-tour.sh --no-build --only …`, light)

- Dev (`build/grand-tour/20261021-045427-roomcore`, 9.1 min, archive, recovery, settings, settings2, extensions, media, documents, reader, routing, import, windows, incognito): **367 passed, 5 failed**: settings2's "spaces reordered" (the subset's shared state held recovery's two spaces; alone `--only settings2`: 26/26), extensions' two header checks (B-125, stale since the top bar design), reader's "Return → save panel" (the preview's default was the laptop's printer: the Return printed, B-126; after `7c3f0a9` alone 34/34, Return not pressed), windows' two renderer DCHECK minidumps (B-76's dev-build condition; 0 on release).
- Release (`build/grand-tour/20261021-053228-roomcore`, archive, recovery, settings, settings2, extensions, reader, routing, import, windows, incognito): **295 passed, 3 failed**: settings2's reorder (the same shared-state cause; alone 26/26, `20261021-053829-roomcore`) and B-125's two.
- `scripts/download-remove-check.sh` (steps 7, 10): `result: passed` on both builds.
- The print jobs: CUPS lists `HP_LaserJet_MFP_M234sdw__8BA835_-67` (04:58:37, the tour's reader step), `-68` (05:07:20) and `-69` (05:08:10, the first two runs of the `print` section), 52,224 B each, completed; none after the guard.
