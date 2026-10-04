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
