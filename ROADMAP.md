# Room — roadmap: Chapters and Phases

Development runs in **Chapters** (broad arcs with a clear end state) made of **Phases** (units of work with an exit criterion). Only Chapter 1 is specified in detail here; later chapters are scoped, and each gets its own detailed spec when the previous chapter closes. Decisions and architecture live in `PLAN.md`; the product spec lives in `research/notes/feature-spec.md`.

Chapter overview:

| # | Chapter | End state | Engine |
|---|---|---|---|
| 1 | Foundations | A real web page inside a Room window that already looks like Dia, on both engines; architecture proven; build pipeline measured | CEF + RoomCore embryo |
| 2 | The sidebar browser | Daily-drivable for light use: spaces, pinned/today entries, palette, split, hide/reveal, downloads, dialogs | CEF |
| 3 | RoomCore | Our own ADK: Chromium fork framework with the full `Engine` API; CEF deleted | RoomCore |
| 4 | A complete browser | Everything a daily driver needs on RoomCore: extensions UX, passwords, archive, routing, Peek, import, settings, multi-window | RoomCore |
| 5 | Polish | Dia-level motion, visuals, accessibility, performance, input details | RoomCore |
| 6 | Ship | Release pipeline, updates, crash loop, rebase operations, onboarding, public release | RoomCore |

Chapter 3 is sequenced after Chapter 2 in this document, but Chromium builds and the RoomCore embryo run in the background from Chapter 1 on, so Chapter 3 work overlaps Chapter 2 whenever a build or a C++ task is waiting on nothing.

---

## Chapter 1 — Foundations

**Theme.** Prove the architecture end to end before building features. At the end of this chapter there is no sidebar content, no tabs model, no persistence; there is a window that looks right, renders a page from CEF, renders a page from a Chromium fork compiled by us, and a written record of what the spikes found.

**Why this chapter exists.** Three unknowns can invalidate the plan: whether Chromium's layer-hosted view clips cleanly into the inset card, whether a `BrowserWindow`-less (or stub-`BrowserWindow`) Chromium fork can be driven from a Swift app with reasonable effort, and what Chromium build iteration actually costs on this machine. Everything downstream depends on the answers.

**Non-goals.** Tabs, spaces, palette, persistence, downloads UI, extensions, signing for distribution, any feature from the spec.

### Phase 1.1 — Repository and toolchain

Goal: an empty, correctly structured app that builds, embeds CEF, launches, and quits cleanly; Chromium checkout started.

Tasks:
1. `git init`; commit `PLAN.md`, `ROADMAP.md`, `research/`, `.gitignore`. Add `README.md` (one paragraph + pointers).
2. Decide and record: minimum macOS = **26 (Tahoe)** (we use `NSGlassEffectView` for overlays; the dev machine is 27). Product name "Room"; bundle id prefix `com.lekevicius.room` (confirm); framework name `RoomCore`.
3. XcodeGen `project.yml` with:
   - app target `Room` (Swift 6, macOS 26, `@main`-less `main.swift`), five helper targets `Room Helper`, `Room Helper (GPU)`, `Room Helper (Renderer)`, `Room Helper (Plugin)`, `Room Helper (Alerts)` (each `LSUIElement`, `LSEnvironment MallocNanoZone=0`, bundle id suffixes `.helper`, `.helper.gpu`, …);
   - entitlement files per target: main app (camera, audio-input, location, print), Renderer/GPU (`com.apple.security.cs.allow-jit`), others none;
   - script phase that copies the engine framework into `Contents/Frameworks` with the `Versions/A` layout and re-signs it;
   - local Swift packages: `Engine`, `EngineCEF`, `UIKitCore`, `Card`, `Design`, `Infra`. UI packages compiled with MainActor default isolation.
4. `scripts/bootstrap-cef.sh`: download the pinned CEF (`154.0.32+g682c378+chromium-154.0.8037.58`, macOS arm64 minimal) into `Engine/cef/dist/`, verify the SHA from the CDN index, build `libcef_dll_wrapper` with CMake (C++20, ARC on), and build/run `cefsimple` once to validate the Xcode 27 toolchain. Pin `CEF_API_VERSION` to the 154 stable API.
5. Chromium checkout (outside the repo, `~/chromium`): install depot_tools, `fetch chromium`, check out the stable tag matching CEF (`154.0.8037.58`), `gclient sync`. Write `Engine/roomcore/args/dev.gn` (`is_component_build=true is_debug=false symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 proprietary_codecs=true ffmpeg_branding="Chrome" enable_widevine=true safe_browsing_mode=0 enable_updater=false use_siso=true`) and start the first `autoninja -C out/dev chrome` in the background. Record checkout size, sync time, clean build time, and a touch-one-file incremental time in `research/notes/build-log.md`.
6. CI stub: a GitHub Actions workflow that runs `xcodebuild` on the app without CEF (compile-only), so package/code hygiene is checked from day one. Full engine builds stay local in this chapter.

Deliverables: `project.yml`, `scripts/bootstrap-cef.sh`, helper targets, entitlements, `build-log.md` (started), CI stub.

Exit criteria:
- `xcodegen && xcodebuild` produces `Room.app` with five helpers and the CEF framework embedded; launches to an empty window and quits without a crash or a hang (orderly `CefShutdown`).
- Chromium checkout complete and the first component build finished (or still running with a logged ETA).

### Phase 1.2 — The `Engine` protocol

Goal: a Swift API that both engines will implement, shaped by the ArcCore headers so the Chapter 3 bridge maps one to one.

Tasks:
0. Build on what Phase 1.1 left in `Packages/Engine` (`EngineApplication`, `EngineConfiguration` with `usesSystemKeychain`): extend, do not replace, and keep `Room.app` building and launching on `EngineCEF` at every commit (the CEF classes only need to adopt new protocol members as stubs that throw or return `nil`).
1. In `Packages/Engine`, define (all `@MainActor`):
   - `EngineApplication`: `initialize(config)`, `run()`, `tryToTerminate(completion)`, `createProfile(name)`, `profiles`, `features`.
   - `Profile`: `createWebContents(config)`, `downloadsDelegate`, `favicon(for:)`, `clearSiteData`, later: history, bookmarks, extensions, autocomplete (declared as optional capabilities so CEF can return `nil`).
   - `WebContents`: `nativeView`, `load(url, transition, fromAddressBar)`, `goBack/goForward/reload/reloadIgnoringCache/stop`, `canGoBack/canGoForward`, observable `title/url/favicon/isLoading/loadProgress/themeColor/rootBackgroundColor/isAudible/isMuted/state(alive|discarded|frozen)`, `find/stopFind`, `zoom`, `discard()`, `captureViewport`, `devTools` (open/close/inspect at point; hosted in a view we provide), `executeJavaScript`, `print`, `close()`.
   - `WebContentsUIDelegate`: `didCreateNewWebContents(_, targetURL, disposition)`, `requestEnterFullscreen/exit`, `statusText`, `willShowContextMenu(MenuModel, elementInfo) -> Bool`, JS alert/confirm/prompt/beforeunload, `willAskForPermission([PermissionRequest], quiet:) completion`, `httpAuth`, `certificateError`, `fileChooser`, `didConsumeKey`, `audibleChanged/mutedChanged`, `processGone`, `didChangeSecurityState`.
   - `NavigationDelegate`: `decidePolicy(for: NavigationAction) -> Disposition`.
   - Value types: `PermissionRequest`, `MenuModel/MenuItem`, `NavigationAction`, `Disposition`, `DownloadItem`, `SecurityState`, `WebContentsConfiguration` (`initiallyHidden`, `transparentBackground`, `initiallyMuted`, `disallowAutoplay`).
2. `FakeEngine` (pure Swift, renders an `NSTextView` with the URL) for unit tests and UI previews. Tests use Swift Testing in `Packages/Engine/Tests`, run with `swift test` in the package and also added to the Xcode scheme's test action so CI runs them.
3. `docs/engine-api.md`: table mapping each protocol member to its CEF handler/method and to the Chromium/ArcCore equivalent, with "CEF: not available" where applicable. This table is the Chapter 3 checklist.

Exit criteria: package compiles under Swift 6 strict concurrency; `FakeEngine` passes a small test suite (navigation state, delegate dispatch); mapping doc reviewed.

### Phase 1.3 — The window

Goal: the Dia look with no engine: window, material, sidebar placeholder, card.

Tasks:
1. `Design` package: tokens (spacing 4/8/12/16, radii 6/10/12, sidebar width 240 default / 180–500 range, card inset 8, type styles 13pt regular rows / 13pt semibold space title / 11pt secondary, materials, animation durations 120/150/250/350ms, spring presets), dynamic colors (asset catalog), SF Symbols set with names for every control in the spec.
2. `UIKitCore`: `RoomWindow` (`.fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility .hidden`, `tabbingMode .disallowed`, `NSWindow.allowsAutomaticWindowTabbing = false`, `isMovableByWindowBackground` only via sidebar background's `mouseDownCanMoveWindow`), `RoomWindowController`, `WindowMaterialView` (`NSVisualEffectView` behind-window `.sidebar` + `SpaceTintLayer` gradient at 10–25% alpha with animated color change), `TrafficLightLayout` (reads `standardWindowButton` frames; re-layout on title/fullscreen/appearance change; no repositioning), fullscreen handling, light/dark observation, inactive-window dimming of the sidebar.
3. Layout: manual `NSSplitView`-free layout (sidebar `NSView` placeholder with a draggable splitter, min 180 / max 500, snaps closed under 120 with a notification for Chapter 2's toast).
4. `Card` package: `CardContainerView` (layer-backed, `cornerRadius 12`, `cornerCurve .continuous`, `masksToBounds`, hairline border layer at 6–8% label color, shadow on a sibling `ShadowBackingView` with `shadowPath`), `backgroundColor` settable (will track page root background), inset 8pt top/right/bottom, 0 on the sidebar side. Give it a `contentView` slot; put a `FakeEngine` page's `nativeView` (Phase 1.2) in it for the snapshot tests, so the `Engine` protocol is exercised in the window once before CEF arrives. No `EngineCEF` work in this phase.
5. Snapshot tests of the window in light/dark, active/inactive, sidebar open/closed, plus one with the `FakeEngine` page in the card; compare by eye against `research/screenshots/dia-window.jpg`.

Exit criteria: screenshots of the empty window are visually within a hair of Dia's chrome (material, inset, radius, shadow, header inset around traffic lights) in light and dark.

### Phase 1.4 — CEF inside the card (`EngineCEF`) and the spike checklist

Goal: a real page renders in the card through the `Engine` protocol, and the open questions about clipping, overlays, keys, popups and memory are answered with numbers.

Tasks:
1. Bootstrap: Phase 1.1 already has `RoomCEFApplication: NSApplication <CefAppProtocol>`, `RoomCEFRuntime` (`CefScopedLibraryLoader`, `CefInitialize`/`CefRunMessageLoop`/`CefShutdown`, mock keychain, feature switches) and the helper `main`. Extend, do not rewrite: route `terminate:` through browser close (`TryCloseBrowser` on every browser, then `CefQuitMessageLoop`), and add `CEFProfile: Profile` over `CefRequestContext` (`cache_path` = `<root_cache_path>/Profiles/<name>`, resumed on `OnRequestContextInitialized`) so `createProfile` stops throwing. `docs/engine-api.md` is the row-by-row spec for this phase.
2. `CEFClient` handlers → the Phase 1.2 delegates (`WebContentsUIDelegate`, `NavigationDelegate`, `DownloadsDelegate`): life span (`OnBeforePopup` → `didCreate(_:targetURL:disposition:)`; `OnAfterCreated`; `DoClose`/`OnBeforeClose` → `webContentsDidClose`), display (title, URL, favicon via `DownloadImage`, loading state/progress, status text, fullscreen), load (errors → error page), keyboard (`OnPreKeyEvent` → `isReservedKeyEvent`; `OnKeyEvent` → `handleUnhandledKeyEvent`, IME-normalized), request (`OnBeforeBrowse`/`OnOpenURLFromTab` → `decidePolicyFor`; `GetAuthCredentials` hops from the IO thread to main; `OnCertificateError`), permission (`OnShowPermissionPrompt`, media access), download (`OnBeforeDownload` → `willBeginDownload`; `OnDownloadUpdated`; pause/resume/cancel callbacks kept per id), JS dialog (+ `OnResetDialogState` → `webContentsDidDismissJavaScriptDialogs`), context menu (build `MenuModel` from `CefMenuModel`, run `NSMenu`), find, focus, audio (`CefAudioHandler::GetAudioParameters` returning `false` for the "became audible" edge; there is no `OnAudioStateChanged` in CEF, see the spike item).
3. `CEFWebContents: WebContents` (`@Observable`): `CefBrowserHost::CreateBrowserSync` with `SetAsChild(parentView, rect)`; `nativeView` = the view CEF created; `initiallyHidden` = create under a hidden parent view (`CefWindowInfo::hidden` is ignored for child browsers); `transparentBackground` = CDP `Emulation.setDefaultBackgroundColorOverride`; `themeColor`/`rootBackgroundColor` read with JavaScript after `OnLoadEnd`; `executeJavaScript`/`captureViewport` over CDP (`Runtime.evaluate`, `Page.captureScreenshot`); DevTools via `ShowDevTools` with `SetAsChild` into a `DevToolsPaneView` we size.
4. A throwaway `DebugToolbar` (SwiftUI in an `NSHostingView`, in the sidebar placeholder's `contentView`) with a URL field, back/forward/reload, "new hidden tab", "show DevTools", "open overlay" — strictly for this chapter. The page goes into `CardView.contentView`; bind `CardView.backgroundColor` to `rootBackgroundColor`. For the exit-criterion screenshot, extend the Phase 1.3 DEBUG `SnapshotRunner`/`scripts/window-snapshots.sh` with a page-in-card state rather than writing a new capture path.
5. Spike checklist (write results in `research/notes/spike-results.md`):
   - [ ] Clipping: card corners clip the page at the card radius (10pt since Phase 1.3); the 1px hairline border (a `CALayer` border on `CardContainerView`) stays visible above the page layer; verify in Quartz Debug that the IOSurface layer still scans out without an extra composite; 120 Hz scrolling stays smooth with the mask on.
   - [ ] Empty toolbar vs. the page: the window's empty unified `NSToolbar` (Phase 1.3, it positions the traffic lights) must not draw a scroll-edge effect, separator or tint over the CEF view in the 52pt band, and clicks in that band must reach the page; in fullscreen, hovering at the top must not slide down an empty 52pt toolbar strip with the menu bar (if it does, hide the toolbar on `willEnterFullScreen` and restore it on exit, and record that).
   - [ ] Live resize: no material shows through at the card edges; card `backgroundColor` tracks `rootBackgroundColor`.
   - [ ] Overlay z-order: a test `NSGlassEffectView` overlay above the card receives hover/click and visually layers correctly; a test "hover-reveal" sidebar slides over the card; mouse tracking across the web view works via a local event monitor.
   - [ ] Keyboard: ⌘T/⌘L/⌘W never reach the page; ⌘C/⌘V/⌘Z reach the page and fall through to the menu when unhandled; ⌘` works; a Lithuanian layout sends the right key equivalents.
   - [ ] Popups: `window.open` and `target=_blank` arrive via the delegate and can be hosted in the card (temporary parent + re-parent as cefclient does); `<select>` dropdowns and date pickers position correctly after a window move.
   - [ ] DevTools: opens in a child view beside/below the page; inspect element works; closes cleanly.
   - [ ] Memory: 1, 10, 30 hidden browsers on typical sites; RSS per browser; confirm hidden views stop compositing. Record numbers.
   - [ ] Extensions: `--load-extension` with an unpacked MV3 extension; confirm content scripts run; note what breaks (expected: no popup/toolbar).
   - [ ] Autofill dropdown: does the in-page autofill/password dropdown render in Alloy on macOS? Record.
   - [ ] Signing: sign the framework, dylibs, helpers, app with Developer ID + hardened runtime + entitlements; run once through `notarytool` to validate the pipeline (keep the script).
   - [ ] Shutdown: ⌘Q with 10 open browsers exits in under 1 s with no zombie helpers. Measure on an idle machine (load average under 5, recorded next to the number); Phase 1.2 saw 0.4–7.9 s quits at load 40–48 on an app with no browsers.
   - [ ] CDP channel: round-trip time of `Runtime.evaluate` and `Page.captureScreenshot` on a live page; `Emulation.setDefaultBackgroundColorOverride` lets the window material show through where the page paints nothing (screenshot), and what it costs during resize.
   - [ ] Audibility: with `GetAudioParameters` returning `false`, does a `<video>` starting to play fire the "became audible" edge, and can a JavaScript poll of media elements report "stopped" within 2 s? Record the cost of the poll; a red result means `isAudible` stays "became audible only" on CEF.

Exit criteria: all checklist items have a recorded result; the page-in-card screenshot sits next to the Dia screenshot and the chrome is indistinguishable in material/inset/radius; no item is red without a fallback noted.

### Phase 1.5 — RoomCore embryo

Goal: the same page in the same window, but from `RoomCore.framework` built from our Chromium fork, driven by a Swift executable. Not the full `Engine` protocol: application bootstrap, one profile, one `WebContents` with a native view, a stub `BrowserWindow`, and a clean quit.

Tasks:
1. Fork layout: branch `room` in the Chromium checkout; `//room/` directory committed in this repo at `Engine/roomcore/room/` and symlinked into `~/chromium/src/room`; `Engine/roomcore/patches/` (quilt-style, applied by script); `Engine/roomcore/chromium_src/` (Brave-style shadow headers, initially empty); `scripts/roomcore-{apply,build,package}.sh`.
2. Branding/build: a `room` branding directory (`chrome/app/theme/room` equivalent) with product name, bundle ids, icon placeholder; GN `branding_path_component`; disable `enable_updater`, Google-specific features; confirm the `chrome` target builds with `is_chrome_branded=false` and our names, producing `Room Framework.framework` (renamed `RoomCore.framework` in packaging). The keychain item name follows the branding product name: confirm a launch of the branded build creates `Room Safe Storage` in the login keychain and never touches `Chromium Safe Storage` (Phase 1.4 found CEF cannot do this, so CEF builds run on the mock keychain; RoomCore must not).
3. Public ObjC API target `//room/core` (compiled into the framework; umbrella `RoomCore.h` + `module.modulemap`; `NS_SWIFT_UI_ACTOR` on every class):
   - `RoomApplication` (`initialize:` with argc/argv/profile path, `run`, `tryToTerminate:`, `createProfile`, `profiles`) over `ChromeMainDelegate`/`BrowserMainParts`; the host `NSApplication` conforms to `CrAppProtocol` (patch `chrome_browser_application_mac` to accept a host-provided application object instead of creating `BrowserCrApplication`).
   - `RoomProfile` over `Profile` (`createWebContents:`).
   - `RoomWebContents` over `content::WebContents` (`nativeView`, `load:`, `goBack/goForward/reload`, title/url/isLoading KVO via `WebContentsObserver`).
   - `RoomBrowser` over `Browser` with `RoomBrowserWindow : BrowserWindow` (all virtuals stubbed; `GetNativeWindow` returns the host `NSWindow`; `Show/Close/Activate` forward to the host). Patch `browser_window_factory.cc` to construct it. `grep AsBrowserView() chrome/` on the pinned tag and record the count and the first crashes hit.
4. Host executable: the Swift app (`App/main.swift`) `dlopen`s `RoomCore` and calls `RoomMain(argc, argv)` which runs `ChromeMain`; helpers reuse Chromium's helper executables renamed. (If handing the main loop to Chromium conflicts with our `NSApplication` subclass, record the fix: ArcCore does exactly this, so it is solvable.)
5. Packaging script: assemble `Room.app` from `out/dev` artifacts (framework, helpers, resources), ad-hoc sign, launch. Reuse the helper layout and per-helper entitlements that `scripts/sign-and-notarize.sh` established in Phase 1.4 (base helper hosts the GPU process on M154 and needs no `allow-jit`; Renderer/GPU helpers get it), so the Developer ID run of that script works on the fork build too.
6. Measure: incremental build time for a change in `//room/core`; full relink time; framework size. The branding change forces a large rebuild anyway, so run it as a clean build at normal priority (started from `bash`, never zsh `&`) and record it as the true clean-build time; Phase 1.1's 4 h 24 min was mostly at nice +5.

Exit criteria: `Room.app` built from the fork shows a page in the Phase 1.3 window; back/forward/reload work; quit is clean (measure with `scripts/quit-timing.sh`, record the load average); `RoomBrowserWindow` stubs did not need more than a handful of real implementations to reach this point; build-log has fork numbers.

### Phase 1.6 — Chapter review

Tasks:
1. Write `research/notes/chapter-1-review.md`: spike results summary, build timings, memory numbers, what surprised us, re-ranked risk table. The one unmeasured spike (does the card mask cost an extra composite of Chromium's IOSurface layer) can be answered without Quartz Debug: Instruments' Metal System Trace / Animation Hitches on the mask-on vs. mask-off scroll page from Phase 1.4; do it if it fits in a morning, otherwise keep the RoomCore `RoundedCornersF` fallback and say so.
2. Confirm or amend the engine plan (CEF scaffold → RoomCore). If Phase 1.5 failed in a way that changes the estimate materially, re-plan Chapter 3 before starting Chapter 2.
3. Freeze design tokens v0 and the reserved-shortcut set.
4. Draft the Chapter 2 detailed spec (phases below expanded into tasks/exit criteria) and a backlog in `docs/backlog.md`.

Carry-overs the Chapter 2 spec must place (from Phase 1.3): with the sidebar closed the traffic lights sit over the card's top-left corner and nothing in the window is a drag handle (card and material refuse drags), so the floating traffic-light cluster (2.7) also has to be the drag region; sidebar width persistence (2.1 store); double-click on the sidebar background = new tab (§F); fullscreen behaviour of the header (traffic lights leave the window, header falls back to a 16pt inset) needs a real-Space test.

CEF caps the Chapter 2 spec must state (from Phase 1.4), all lifted by RoomCore: cookies and saved passwords are encrypted with the mock keychain key, not the login keychain, so a Chapter 2 build is not a safe daily driver for sensitive accounts; docked DevTools needs the Debug-only 127.0.0.1 debugging port (default 9339, any local process can attach), Release builds get CEF's separate DevTools window; `isAudible` sees Web Audio start but not stop; extension action popups and `chrome://extensions` do not exist; no autofill/password save prompts; Close Window is ⇧⌘W because ⌘W closes the tab.

Chapter 1 exit: Phases 1.1–1.6 closed; `PLAN.md` §4 decisions updated with anything learned; Chapter 2 spec written.

---

## Chapter 2 — The sidebar browser (on CEF)

**End state.** You use Room all day for light browsing. All Arc/Zen interaction decisions are implemented and felt; the only complaints are the known CEF caps (below). Spec: `feature-spec.md` sections A–I minus items that need RoomCore; shortcuts: `docs/shortcuts.md`; tokens: `docs/design-tokens.md` (both frozen in Phase 1.6).

**Detailed spec written in Phase 1.6** (`research/notes/chapter-1-review.md` for the reasoning). Each phase below has tasks and exit criteria like Chapter 1; `docs/progress.md` carries the checklists.

**New packages** (PLAN §2.2, `macos-ui-stack.md` §9.4): `Model` (GRDB), `Store`, `Sidebar`, `Palette`, `Omnibox`, `Chrome` (toasts, popovers, dialogs, downloads). The Chapter 1 throwaways (`DebugSession`, `DebugToolbar`, `OverlaySpike`, the flat page list) are deleted as their replacements land (2.3 at the latest); the DEBUG `SpikeRunner` stays.

**CEF caps this chapter lives with** (from Phase 1.4; all lifted by RoomCore in Chapter 3):
- Cookies and saved passwords are encrypted with the mock keychain key, not the login keychain: a Chapter 2 build is **not a safe daily driver for sensitive accounts**. Dogfooding (2.9) uses accounts you can afford to expose on disk.
- No extension action popups, toolbar or `chrome://extensions`; content scripts and service workers work.
- No password/address save prompts; the autocomplete dropdown works on http(s).
- Docked DevTools needs the Debug-only 127.0.0.1 debugging port (default 9339; any local process can attach); Release builds get CEF's separate DevTools window.
- `isAudible` sees Web Audio start but not stop (media elements are exact).
- No engine omnibox ranking or history: the palette's history is our own throwaway FTS5 table until 3.5.

**Carried in from Chapter 1 and placed below:** sidebar width persistence (2.1); double-click on the sidebar background = new tab (2.2); with the sidebar closed the traffic lights sit over the card and nothing is a drag handle, so the floating traffic-light cluster is also the drag region (2.7); the header's fullscreen fallback (16 pt inset) needs a real-Space test (2.8); Close Window is ⇧⌘W because ⌘W closes the tab (done).

**Background RoomCore work** (Chapter 3 overlap) that may run whenever a build is waiting on nothing: the network-call audit and the static release build measurement (3.1). It never blocks a Chapter 2 exit.

### Phase 2.1 — Model and store

Goal: the sidebar's data, persisted crash-safely, with no UI.

Tasks:
1. `Model` package on GRDB (SwiftPM dependency, pinned): schema v1 — `profile`, `space` (name, icon, theme colors/algorithm/opacity, profileId, position, pinnedCollapsed), `entry` (kind `essential|pinned|folder|today`, spaceId (null for essentials), profileId, folderId, splitGroupId, position, storedURL, storedTitle, customLabel, customIcon, faviconId, createdAt, lastActiveAt, liveURL, liveTitle), `split_group` (layout, ratios), `window` (frame, sidebarWidth, sidebarVisible, activeSpaceId), `window_space` (selected entry per space per window), `favicon` (host, png, sha256, updatedAt), `history_url` + `history_visit` + `history_fts` (FTS5 trigram, external content; throwaway until 3.5), `kv` (settings JSON). Migrations through `DatabaseMigrator`; one database in `~/Library/Application Support/Room/`.
2. `Store` package: `@Observable` `MainActor` stores (`SidebarStore` per profile/space tree, `WindowStore`, `SettingsStore`) as the only writers; value snapshots for the UI; no state-diffing of the whole tree on hot paths.
3. Persistence pipeline: every mutation schedules a debounced write (300 ms; flushed on quit, window close, `applicationWillTerminate`), one transaction per write, a monotonically increasing generation so a stale write never lands after a newer one; after each successful write a JSON snapshot (`Data.write(.atomic)`); `running` flag in `kv` for unclean-exit detection.
4. Domain rules as pure functions with tests: entry type conversions (spec §A.9), the Essentials cap (12), `isChanged` normalisation (§A.1: trailing slash and fragment ignored, query counts), MRU order per space, ⌘W behaviour selection (§A.3 `permanentCloseBehavior`), folder depth ≤ 5, sidebar order for ⌘1–9.
5. Window state: sidebar width and visibility per window persist and restore (Chapter 1 carry-over).
6. Seed: first launch creates profile "Default", space "Space", no entries.

Exit criteria: a test harness writes continuously and is `kill -9`'d at random points 100 times; every reopen succeeds, passes `PRAGMA integrity_check`, and holds exactly the last committed generation; domain-rule and migration tests pass in the Room scheme and CI.

### Phase 2.2 — Sidebar

Goal: the whole sidebar tree, interactive against `FakeEngine`.

This is the largest Chapter 2 phase. Run it as two sessions with a report after each: **2.2a** = tasks 1–4 and 7 (tree, rows, clicks, menus, toasts), **2.2b** = tasks 5, 6 and 8 (drag and drop, keyboard, snapshots). The phase is done when both are.

Tasks:
1. `Sidebar` package: view-based `NSOutlineView` for space title → pinned (folders) → separator/Clear → Today; Essentials as a grid row above it (`NSCollectionView` or a custom grid; ≤12, 36 pt squircles, favicon-tinted background); footer placeholder (filled in 2.5/2.6). Header (address field showing the domain only, site button, copy button on hover) laid out by `TrafficLightLayout`.
2. Row states (spec §A.1, §I.2–I.4, I.8): unloaded (60% favicon), loaded, changed dot + reset button on hover with the ⌘ sublabel swap, audio indicator, hover background 6%, close × for Today rows; selection pill animated with `Motion.pill`; insert/remove animation 150 ms; reduced-motion crossfades.
3. Click semantics (spec §A.2): select, click-selected-changed = reset, ⌘-click = reset + open current page as Today, middle-click unload/remove, double-click rename (inline field, pulse on commit), Enter renames the focused row.
4. Context menus (spec §A.8, §A.6 folders) with the palette's command names; commands that need later phases are present and disabled.
5. Drag and drop (spec §A.9): reorder with insertion line and lifted row; cross-section type conversion with the Essentials cap shake; drop on a folder (middle 60%, 500 ms); ⌥-drag duplicates; text/URL drops from outside; multi-select (⌘-click, ⇧-click within a section) with group drag; haptic tick on insertion-line moves. Drag-to-space-icon and drag-out-to-new-window wait for 2.5 / Chapter 4.8.
6. Keyboard focus in the sidebar (spec §I.13), overflow indicator (§I.11), Clear (⇧⌘K) with staggered slide-out, Pin ⌘D, Essentials ⇧⌘D, double-click on empty sidebar = new tab (Chapter 1 carry-over).
7. `Chrome` package, first piece: toasts (spec §F: one at a time, spring in, 2 s / 5 s with a button, hover pauses) — needed here for Clear · Undo, rename and pinned-URL toasts.
8. Snapshot tests of rows in every state, light/dark, active/inactive.

Exit criteria: every interaction in spec §A.2–A.9 works against `FakeEngine` (checklist in `docs/progress.md`, one line per spec bullet); a 500-entry sidebar scrolls without dropped frames on the 120 Hz panel; drag-conversion and Clear/Undo have tests.

### Phase 2.3 — Tabs and the card

Goal: entries become real pages on CEF; the card shows the selected one.

Tasks:
1. `TabController` (App or `Store`-side coordinator): one `WebContents` per loaded entry, created on first selection; background loaded pages stay hidden browsers; the card swaps `nativeView` on selection; `rootBackgroundColor` binding per page (Phase 1.4 `PageHost` becomes this).
2. Lifecycle (spec §H): unloaded entries; restore on launch with only the selected entry per window loaded; discard after idle (Today 60 min, permanent 3 h) and on memory pressure (`DISPATCH_MEMORYPRESSURE_WARN`, LRU across spaces, never selected/audible); discarded entries keep URL/title/favicon (CEF has no navigation-history serialisation: back/forward is lost on discard and recorded as a CEF cap).
3. ⌘W (spec §A.3) with MRU fallback, ⇧⌘T reopen stack, related-tab insertion under the opener (§A.7), MRU on close, closing the last Today tab → empty state ("Press ⌘T…").
4. Tab switching: ⌃Tab MRU overlay (5 recent, hold ⌃, W closes), ⌘1–9, ⇧⌘] / ⇧⌘[, ⌥⌘↓ / ⌥⌘↑ (reserved set, `UIKitCore.ReservedShortcuts`).
5. Page state into the store: title, favicon (download + cache by host, letter-tile fallback), live URL, `isChanged`, loading, audible (mute ⇧⌘M), `lastActiveAt`.
6. Links from permanent entries navigate in place this phase (Peek in 2.7).
7. Delete the Chapter 1 debug page list; keep the debug toolbar's URL field, back/forward/reload until 2.4 replaces them with the palette (there is no other way to enter a URL before then); keep `SpikeRunner`.

Exit criteria: 50 entries with 10 loaded; switching selection under 16 ms main-thread from click to the new page in the card (median and p95 recorded in `spike-results.md`), summed RSS recorded; quit and relaunch restore the tree with only the selected entry loaded; ⌘W/⇧⌘T/MRU behave per spec in tests against `FakeEngine` and by hand on CEF.

### Phase 2.4 — Palette v1

Goal: ⌘T/⌘L as one centred palette with our own suggestion pipeline.

Tasks:
1. `Palette` package: in-window overlay on `NSGlassEffectView`, 640 pt wide at 18% from the content top, `NSTextField` with field-editor commands (↑/↓/⏎/⎋/⇥), results list (SwiftUI rows in `NSHostingView`), open/close animation 120 ms; focus returns to the page on close.
2. Semantics (spec §C): ⌘T new (no tab until commit; Enter = new Today tab, ⌘Enter = current tab, ⌥Enter = background), ⌘L edit (prefilled, selected; Enter unchanged = reload), ⌘T/⌘L again closes, header-field click edits in place, typed text kept per tab for 45 s, inline host completion from history only.
3. `Omnibox` package: providers (verbatim/URL fixup, open tabs across spaces, pinned & essentials, history FTS5 + frecency, search suggest, commands registry with the spec §C list), one scorer in Chromium-like bands, dedupe by normalised URL, max 8 rows, Tab cycles groups, `>` or Tab-from-empty enters commands, site-search keywords (`yt` + Tab).
4. History recording: committed main-frame navigations → `history_url`/`history_visit` (Model), delete-suggestion (⇧Delete / ⌘⌥Delete).
5. Delete the Chapter 1 debug toolbar once the palette opens URLs.
6. Search suggest: DuckDuckGo, Google, Kagi clients, 120 ms debounce, cancel in flight; **off switch in Settings and honoured immediately** (CLAUDE.md); suggestions on by default; default engine Google until the first-run choice (2.8) (user decision, 2026-10-03).

Exit criteria: spec §C works minus engine-provided ranking; scorer and provider unit tests; keystroke-to-local-results p95 under 16 ms with 50k history rows (synthetic) — measured and recorded; with suggestions off, no network request leaves the app while typing (verified with a net-log or proxy).

### Phase 2.5 — Spaces

Goal: many spaces, each with its own lists, look and (optionally) profile.

Tasks:
1. Space CRUD and the creation/edit form (spec §B: name, icon picker emoji/SF Symbol, up to 3 colours with the five algorithms, profile menu) as a SwiftUI leaf; the space context menu.
2. Switching: footer icons (active 1.15×, hover labels, ≤1 space hides the row), ⌃1…⌃9/⌃0, ⌥⌘←/→ with wrap, two-finger swipe over the sidebar (25% threshold + velocity, rubber band, edge → new-space form), ⌃+wheel, palette "Focus on {space}"; slide 250 ms + tint crossfade; reduced-motion crossfade.
3. Per-space selection memory; essentials crossfade when the profile changes.
4. Profiles as CEF request contexts at `<root>/Room Profile <name>` (Phase 1.4 finding); moving an entry to a space with another profile reloads it in the new context with a one-time warning.
5. Drag an entry onto a space icon (500 ms) to move it (2.2 carry).

Exit criteria: spec §B minus routing (routing is 4.2); two profiles keep separate cookies (verified with a test page setting a cookie); switching spaces with 10 loaded pages per space shows no material flash.

### Phase 2.6 — Chrome surfaces

Goal: every CEF delegate callback has real UI.

Tasks:
1. Downloads: footer button with progress ring, bounce and badge; popover (name, progress, cancel, reveal, Clear); fly-in animation from the click point; filename decision and location from Settings; ⇧⌘J.
2. Permission popover anchored to the header's site button; JS dialogs and `beforeunload` as in-card sheets; HTTP auth sheet; certificate-error interstitial (our page, proceed only for non-HSTS); file chooser; context menus (`MenuModel` → `NSMenu`) with Room items (open in new tab/Peek, copy link); popups and `window.open` → new Today entries (or the opener's split in 2.7).
3. Find bar (⌘F/⌘G/⇧⌘G, "3 of 12") at the card's top-right; zoom ⌘=/⌘-/⌘0 with a transient zoom indicator; print (CEF's dialog); status pill for link hover (600 ms, 1.5 s full URL, dodges the cursor); Copy URL / Markdown with toasts; site panel (permissions per origin, clear site data).
4. DevTools pane with a resize handle (Phase 1.4 front-end over the debug port in Debug; separate window in Release).

Exit criteria: a checklist of every `WebContentsUIDelegate`, `NavigationDelegate` and `DownloadsDelegate` member in `docs/engine-api.md` with its UI, each exercised once on CEF (test pages in `research/spikes/phase-2.6/`).

### Phase 2.7 — Hide/reveal, split view, Peek

Goal: the three layout modes that make Arc feel like Arc.

Tasks:
1. Sidebar hide/reveal (spec §E): ⌘S (page-first), ⌥⌘S pin, 4 pt edge band with 150 ms dwell, floating glass overlay with 10 pt inset, 150 ms keep-open grace, 200/100 pt outside-window tolerance, popups/menus/palette keep it open; splitter snap-close toast once; background-tab, new-space and download-complete toasts while hidden.
2. Floating traffic-light cluster (38 pt) when the sidebar is hidden; it fades after 2 s without pointer movement near it and is **the window's drag region** together with the top 5% of the card (Chapter 1 carry-over); optional "Show toolbar" (View menu) 36 pt toolbar.
3. Split view (spec §D): groups of ≤4 panes, `hbox`/`vbox`/`grid`, persisted ratios, resizers (7 pt hit, double-click equalises), pane header on hover (domain, grip, layout, ×), focus follows click (URL field follows the focused pane), group row in the sidebar with tinted focused segment, drag-to-split zones in the card, row-centre join (500 ms), ⌥-click duplicate into split, keyboard ⇧⌘=, ⌃⇧-, ⌥⌘G/V/H/U, ⌃⇧1…4, ⌃⇧] / ⌃⇧[; ⌘W closes only the focused pane.
4. Peek (spec §A.4, §I.6): off-site links from permanent entries and ⇧-click open an overlay card (86%, 24 pt radius, 30% dim) with Open as tab (⌘O), Split (⇧⌘O), close (Esc, ⌘W, click outside), reopen with ⇧⌘T; login/OAuth exemptions per §A.4.

Exit criteria: spec §D, §E and §I.6 work on CEF; window-state snapshot tests extended to hidden-sidebar and split states; the overlay never passes events to the page under it (Phase 1.4 method).

### Phase 2.8 — Shortcuts, menus, app integration

Goal: Room behaves like a Mac app and can be your default browser.

Tasks:
1. Main menu in code from `docs/shortcuts.md` (every row present; unimplemented ones disabled with their chapter in the tooltip), `validateMenuItem` everywhere, the reserved set from `UIKitCore.ReservedShortcuts`. Remapping moves to 4.4 with the full settings window (amended in Phase 1.6: one place for shortcut editing).
2. Settings v0 (SwiftUI window): search engine and suggestions off switch, download location, Peek on/off, sidebar side, appearance; the rest lands in 4.4.
3. Default browser: first-run in-sidebar card, `NSWorkspace.setDefaultApplication` for http/https with the CoreServicesUIAgent activation, Settings entry; URL ingestion via `application(_:open:)` queued until the engine is up; Handoff out of scope.
4. First run: default search engine choice, default-browser card, crash-reporting consent.
5. Sparkle 2 wired to a dev feed with automatic checks **off until the user enables them** at first run; Sentry wired, **off unless the user opted in** (no network calls the user did not ask for).
6. Fullscreen on a real Space: header fallback (16 pt inset), toolbar hidden, hover reveal works (Chapter 1 carry-over).

Exit criteria: every `docs/shortcuts.md` row is either working or a disabled menu item naming its chapter; Room set as default opens links from other apps into the right window; with all opt-ins declined, a launch + browse session makes no request we did not ask for (net-log check, excluding page traffic).

### Phase 2.9 — Dogfood week

Tasks:
1. Use Room as the only browser for a week (accounts you can afford under the mock keychain); log friction in `docs/backlog.md` as it happens.
2. Triage; fix the top 20.
3. `research/notes/chapter-2-review.md`: what worked, CEF caps hit in practice, numbers (memory with real use, switching latency, launch time), re-ranked risks; confirm the order of Chapter 3 phases.

Exit criteria: a week of exclusive use; top 20 fixed; review written; Chapter 3 spec drafted.

---

## Chapter 3 — RoomCore

**End state.** `RoomCore.framework` implements the whole `Engine` protocol plus the Chrome-only capabilities (extensions, passwords, autocomplete, session service, discarding); `EngineCEF` is deleted; the fork rebases to a new Chromium stable with a script.

Phases:
- **3.1 Bootstrap and packaging.** Everything from Phase 1.5 made production-grade: profiles directory, `Local State`, crash keys, feature flags, logging, resource bundle, locale pruning, codesign/notarize scripts for the framework and helpers, dev and release GN args, static release build measured. **Added in Phase 1.6:** network-call audit (component updater, `accounts.google.com`, `google.com/async` seen at launch; disable by prefs/switches, then `//room` hooks); Developer ID–signed keychain check; packaging for the static build (no `libchrome_dll` link in the host, no `Libraries/` rpath).
- **3.2 `RoomBrowserWindow` and `RoomBrowser`.** Real implementations of the `BrowserWindow` methods we need (activation, bounds, fullscreen, `ExclusiveAccessContext`, tab strip observer → delegate, command dispatch, status bubble, find bar interface), stubs for the rest with telemetry on hits; `Browser` per window; `takeOwnership(webContents)`; popups and PiP browser types. **Added in Phase 1.6:** starts from the embryo's `RoomLocationBar`, `RoomExclusiveAccessContext`, feature teardown and hidden Bookmarks item; decides main-menu ownership (host menus carrying Chrome's command tags vs. `//room` owning the menu, since `AppController` walks it by tag).
- **3.3 `RoomWebContents` parity.** Every `WebContents` member of the `Engine` protocol: navigation controller with transitions, back/forward list, find, zoom, capture, discard/freeze votes, PDF controller, media session/PiP, DevTools with CDP, print preview (Views, parented to our window), tab traits, `rootBackgroundColor`/`themeColor`.
- **3.4 UI delegates.** Permission prompt factory → delegate; context menu model export (`RenderViewContextMenu` → `MenuModel`); downloads via `DownloadManager` with `onDeterminingFilename`; auth/cert; new contents with disposition; fullscreen/pointer lock; hung renderer; external protocol; infobars model; WebUI dialogs; consumed keys; security state.
- **3.5 Omnibox.** Expose `AutocompleteController` (`autocomplete:cursor:preventInline:startFresh:keyword:` with streaming results, deletable matches, keyword/site search, tab match); `LocationBar` interface backed by the Swift address field; replace the Chapter 2 local history FTS with engine history.
- **3.6 Extensions.** `ExtensionsContainer` implementation; toolbar actions with icons and pinned order; action popups delivered as `WebContents` → `NSPopover`; Web Store install with consent prompt; unpacked install; commands; `chrome://extensions` reachable; uninstall consent.
- **3.7 Passwords, autofill, session, lifecycle, translate.** Keep Chromium's managers; save/update prompts to delegate; autofill popup via Views anchored to our view (native later); `SessionService` restore of navigation state; tab discarding/freezing policy hooks; Translate bubble delegate; spellcheck.
- **3.8 Rebase automation.** `scripts/roomcore-rebase.sh` (fetch tag, rebase `room` branch, reapply patches, build, smoke test); first two rebases done by hand, third by script; decide Stable vs Extended Stable.
- **3.9 Switch and delete CEF.** `EngineRoomCore` replaces `EngineCEF`; remove CEF scripts/dist; migrate the local history table away; dogfood on RoomCore for a week; `chapter-3-review.md`.

---

## Chapter 4 — A complete browser (on RoomCore)

**End state.** Nothing you need from Arc or Chrome is missing for everyday use.

Phases:
- **4.1 Lifecycle and archive.** Auto-archive sweep, Archive view in the Library, restore, rolling sidebar backups, "Restore sidebar…", crash-recovery restore (all unloaded), memory-pressure discard across spaces.
- **4.2 Routing and Peek.** Space routing rules UI (contains/equals/regex), external-link default, "Add route for domain", Peek refinements (⌘O expand, split from Peek, reopen closed Peek).
- **4.3 Import.** Chrome/Arc/Brave/Safari bookmarks, history, passwords (CSV), cookies where allowed; map Arc's `StorableSidebar.json` spaces/pinned/folders to our model; first-run import flow.
- **4.4 Settings.** SwiftUI settings window: general, search engines, shortcuts (conflict detection), spaces/profiles, privacy (site data, permissions per origin), downloads, appearance, extensions. Shortcut remapping lives here (moved from 2.8 in Phase 1.6); the reserved set follows remapped keys.
- **4.5 Extensions UX.** Management list, enable/disable/reload, pinned toolbar actions in the sidebar header, commands, popups polish, per-site access.
- **4.6 Media and audio.** Audible indicator and mute click, media row above the footer, PiP, media keys.
- **4.7 Documents.** PDF viewer polish, print preview, reader mode (basic), translate bubble UI, view source, save page, screenshots (⌘⇧2).
- **4.8 Windows.** Multiple windows sharing spaces/pinned state live, per-window Today tabs, drag entry out to a new window, window restore, incognito windows (separate profile type).

---

## Chapter 5 — Polish

**End state.** It feels like Dia or better. Spec §I is the checklist.

Phases:
- **5.1 Motion.** Selection pill spring, row insert/remove, space slide, palette scale, Peek arc, toast springs, download fly-in, folder collapse; Reduce Motion variants; 120 Hz verification.
- **5.2 Visual audit.** Light/dark, active/inactive, materials over busy wallpapers, tint contrast per space theme, hairlines, icon weights, typography pass against Apple HIG; icon design.
- **5.3 Accessibility.** VoiceOver on the sidebar/palette/footer, full keyboard operation, focus rings, Dynamic Type-ish scaling, announcements for toasts, high-contrast.
- **5.4 Performance and memory.** Launch time, switching latency, scroll smoothness with overlays, memory per tab, discard tuning, energy impact, leak hunts.
- **5.5 Input.** IME and non-US layouts, trackpad gestures (space swipe, back/forward swipe with overscroll UI), haptics, mouse buttons, drag-and-drop of text/URLs/files into the sidebar, overflow indicator, status pill dodging.
- **5.6 Details.** Empty states, inactive desaturation, favicon letter tiles, custom icons picker, rename pulse, unread-count dots, hover sublabels.

---

## Chapter 6 — Ship

**End state.** Public, updating, observable, maintainable by one person.

Phases:
- **6.1 Release pipeline.** Mac mini or Depot runner for release builds; static official build; sign, notarize, staple, DMG; versioning; changelog.
- **6.2 Updates.** Sparkle 2 appcast on static hosting, EdDSA keys, delta measurement, in-app update UI, channel for betas.
- **6.3 Crash and health loop.** Crashpad → Sentry for helpers, Sentry SDK for the app, symbol upload, triage routine, opt-in diagnostics only (no analytics by default).
- **6.4 Rebase operations.** Scheduled Chromium stable bumps (2-week) with the script; weekly security refresh checks; smoke-test suite gating a release.
- **6.5 Onboarding and defaults.** First-run flow (import, default browser, essentials picker, theme), docs, website, release notes, support channel.
- **6.6 Public release.** Beta cohort → public; license and repository decisions; roadmap for Chapter 7+ (sync, Windows, AI only if ever wanted).
