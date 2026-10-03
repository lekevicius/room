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
