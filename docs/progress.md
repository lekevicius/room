# Progress

Current: **Chapter 1 — Foundations**, Phases 1.1–1.3 done; Phase 1.4 not started.

Legend: `[ ]` todo · `[x]` done · `[-]` dropped (say why in the log).

## Chapter 1 — Foundations

### Phase 1.1 — Repository and toolchain
- [x] git init, `.gitignore`, `README.md`, `CLAUDE.md`, directory skeleton
- [x] Record decisions: min macOS 26, product name, bundle id prefix, framework name
- [x] `project.yml` (app + five helper targets, entitlements, framework copy/sign phase, local packages)
- [x] `scripts/bootstrap-cef.sh` (pinned CEF 154.0.32 arm64 minimal, SHA check, CMake wrapper build, cefsimple run)
- [x] Chromium checkout at `~/chromium` on tag 154.0.8037.58; `Engine/roomcore/args/dev.gn`; first component build started; `research/notes/build-log.md`
- [x] CI stub (compile-only `xcodebuild`)
- [x] Exit: `xcodegen && xcodebuild` builds `Room.app` with helpers + CEF framework; launches to an empty window; quits cleanly. Chromium checkout complete, first build finished or ETA logged.

**Phase 1.1 done (2026-10-02).** Review: the app shell, five helpers, CEF embedding and orderly `CefShutdown` work (quit 0.23–0.33 s, no leftover helpers, no crash reports over 8 runs); the no-engine CI spec builds with the CEF dist absent. The checkout is pinned to the exact Chromium commit CEF 154.0.32 uses, and the first `chrome` component build finished. Two spec items were wrong for M154/Xcode 27 (`safe_browsing_mode=0`, missing Metal toolchain) and are recorded below. The big surprise is build cost: 4 h 24 min clean vs. the 1.3–2 h estimate (partly self-inflicted via nice +5); incrementals are fine (27–39 s). Re-measure a clean build at normal priority before trusting rebase-cost estimates in Phase 1.5/1.6.

### Phase 1.2 — The `Engine` protocol
- [x] `Packages/Engine` protocols and value types (§1.2 of ROADMAP)
- [x] `FakeEngine` + tests
- [x] `docs/engine-api.md` mapping table (Engine ↔ CEF ↔ Chromium/ArcCore)
- [x] Exit: compiles under Swift 6 strict concurrency; tests pass; mapping reviewed

**Phase 1.2 done (2026-10-02).** Review: the `Engine` package now has the full Chapter 1 surface (application/profiles/features, `Profile` with nil-able Chrome-only capabilities, `@Observable` `WebContents`, `DevTools`, UI/navigation/downloads delegates, value types), modeled on ArcCore's shape but in Swift idiom. It builds clean under Swift 6 with `-warnings-as-errors -strict-concurrency=complete`; `FakeEngine` passes 53 Swift Testing tests via `swift test`, the Room scheme's test action and the CI spec. `docs/engine-api.md` maps all ~83 members to CEF and Chromium; a row-by-row check against the headers and the M154 checkout fixed 19 entries, and the CEF gap list (7 items, mostly emulatable over JavaScript/CDP) is the input for Phase 1.4. Mapping doc read and accepted (planner, 2026-10-02); spot checks against `cef_download_item.h`, `cef_audio_handler.h` and `alloy_browser_host_impl.cc` agree. The 1.4 findings are now folded into `ROADMAP.md` Phase 1.4 (tasks 1–3, three new spike items).

### Phase 1.3 — The window
- [x] `Design` package: tokens, dynamic colors, symbol names
- [x] `UIKitCore`: `RoomWindow`, controller, material view, space tint layer, traffic-light layout, fullscreen, appearance, inactive dimming
- [x] Sidebar placeholder with splitter (180–500, snap under 120)
- [x] `Card` package: clipped container, border, shadow sibling, settable background
- [x] Snapshot tests light/dark, active/inactive, sidebar open/closed
- [x] Exit: empty window visually matches Dia's chrome

**Phase 1.3 done (2026-10-02).** Review: the window, material, space tint, sidebar placeholder with snap-closing splitter and the clipped/bordered/shadowed card are built in `Design`, `Card` and `UIKitCore`, with no engine work; `Room.app` now opens this window. Measured against Dia's capture at 1× (`research/notes/spike-results.md`), card edges, corner and title position match to the pixel and the shadow within 3 levels; the remaining visible difference is material brightness, which comes from what sits behind the window. Two ROADMAP guesses were wrong (inset 8 → 6, radius 12 → 10), and Dia's traffic-light position turned out to come from an empty unified toolbar, not from moving the buttons. 90 package tests pass (37 new, including 10 window-state captures with pixel checks); screenshots of all states and the Dia comparisons are in `research/screenshots/phase-1.3/`.

### Phase 1.4 — CEF inside the card and the spike checklist
- [ ] Bootstrap (NSApplication subclass with CefAppProtocol, main.swift, helper main, sandbox)
- [ ] `CEFClient` handlers → Engine delegates
- [ ] `CEFWebContents` with `SetAsChild` into the card; hidden browsers; DevTools pane
- [ ] Throwaway debug toolbar
- [ ] Spike checklist recorded in `research/notes/spike-results.md` (clipping, resize, overlay, keyboard, popups, DevTools, memory, extensions, autofill dropdown, signing+notarize, shutdown)
- [ ] Exit: all items recorded; page-in-card screenshot matches Dia chrome; every red item has a fallback

### Phase 1.5 — RoomCore embryo
- [ ] Fork layout (branch `room`, `//room/` symlink, patches/, chromium_src/, scripts)
- [ ] Branding/build with our names; `chrome` target builds
- [ ] `//room/core` ObjC API: RoomApplication, RoomProfile, RoomWebContents, RoomBrowser + stub RoomBrowserWindow; factory patch; `AsBrowserView()` count
- [ ] Swift host executable driving the framework; helpers
- [ ] Packaging script; ad-hoc signed `Room.app` from the fork
- [ ] Measurements in build-log
- [ ] Exit: page renders in the Phase 1.3 window from RoomCore; clean quit

### Phase 1.6 — Chapter review
- [ ] `research/notes/chapter-1-review.md`
- [ ] Engine plan confirmed/amended; `PLAN.md` §4 updated
- [ ] Design tokens v0 and reserved shortcuts frozen
- [ ] Chapter 2 detailed spec + `docs/backlog.md`

## Log

- 2026-10-01 — Research completed (`research/notes/`), `PLAN.md` and `ROADMAP.md` written, repository initialized. Next: Phase 1.1.
- 2026-10-01/02 — Phase 1.1 (Claude Code session).
  - Done: decisions recorded in `PLAN.md` §4 (Identity, Minimum macOS rows); `scripts/bootstrap-cef.sh` (pinned CEF 154.0.32 minimal, SHA-1 vs pin and CDN index, wrapper via CMake with `api_version=15400`, cefsimple built and run once); six local packages; XcodeGen spec split into `xcodegen/base.yml` + `xcodegen/cef.yml` (included by `project.yml`) and `xcodegen/ci.yml` (no engine); five helper targets, per-target entitlements, framework copy + sign phase (`scripts/embed-cef-framework.sh`); minimal CEF bootstrap (`RoomCEFApplication` NSApplication subclass with `CefAppProtocol`, `CefInitialize`/`CefRunMessageLoop`/`CefShutdown`, helper main with sandbox) — Phase 1.4 expands it; `scripts/smoke-launch.sh`; CI workflow; `scripts/chromium-checkout.sh`; `Engine/roomcore/args/dev.gn`; first component build. Numbers in `research/notes/build-log.md`.
  - Deviations: (1) `safe_browsing_mode=0` removed from `dev.gn`: `gn gen` fails on M154 because Chrome targets depend on Safe Browsing; default (1) kept, inert without an API key; `PLAN.md` §4 Build config row amended. (2) Xcode 27 lacks the Metal toolchain by default; installed with `xcodebuild -downloadComponent MetalToolchain` (ANGLE needs it). (3) The CEF minimal distribution has no `tests/`; the bootstrap extracts `tests/` from the standard distribution only for the cefsimple check. (4) The NSApplication subclass is named `RoomCEFApplication`, not `RoomApplication`, to keep that name free for the RoomCore engine object (§2.3). (5) `ARCHS=arm64` (CEF dist is arm64-only; Release builds were universal by default). (6) `EngineConfiguration.usesSystemKeychain`: ad-hoc-signed builds get a new code identity per build, so Chromium's "Chromium Safe Storage" keychain read prompted for the login password on every launch and blocked shutdown until `MacShutdownWatchdog` killed the process; builds without a Team ID now pass `--use-mock-keychain`. Signing with the author's Apple Developer team (available) in Phase 1.4 should make this unnecessary. (7) PLAN §4 build-time row updated with the measured 4 h 24 min.
  - Observations for later phases: on M154 the GPU process runs from `Room Helper.app` unless SwiftShader is allowed (`gpu_process_host.cc`), so `Room Helper (GPU)` is idle and the base helper may need `allow-jit` under hardened runtime (Phase 1.4 signing spike). `MacShutdownWatchdog` (`chrome/browser/shutdown_watchdog_mac.cc`) kills teardown after 10 s (60 s in some builds). CI not run on GitHub: the repo has no remote; the same commands pass locally. Long builds must be started from bash, not zsh `&` (`BG_NICE`).
  - Next: Phase 1.2 (Engine protocol), when the user says go.
- 2026-10-02 — Phase 1.2 (Claude Code session).
  - Done: `Packages/Engine` protocols and value types (`EngineApplication` extended in place, `Profile`, `WebContents`, `DevTools`, `WebContentsUIDelegate`, `NavigationDelegate`, `DownloadsDelegate`, `PermissionRequest`, `MenuModel`/`MenuItem`, `ContextMenuElement`, `NavigationAction`, `Disposition`, `DownloadItem`, `SecurityState`, `WebContentsConfiguration`, `EngineError`, …); `FakeEngine` library in the same package with `simulate…` hooks for page-side events; 53 tests in 5 suites (navigation state, observation, delegate dispatch, profiles/termination, downloads, menu model); Room scheme test action (`package: Engine/EngineTests`) and CI now runs `xcodebuild build test`; `docs/engine-api.md`. `CEFApplication` adopts the new members as stubs (`profiles` empty, `createProfile` throws `notSupported`) and passes `EngineConfiguration.features` to `--enable-features`/`--disable-features`, merged with CEF's own (verified in the helpers' command lines). App still launches and quits cleanly (smoke: exit 0, no helpers left, no crash reports).
  - Deviations / additions beyond the ROADMAP list: (1) `MenuModel` is a `@MainActor` class, not a value type, because it carries the one-shot select/cancel completion; `MenuItem` is a value type. (2) Delegates use completion handlers, not `async`, so the engine can dismiss a pending dialog/prompt itself (`webContentsDidDismissJavaScriptDialogs`, `webContentsDidDismissPermissionPrompt`), as ArcCore and CEF do. (3) Added members the CEF/Chromium mapping needs: `isReservedKeyEvent`/`handleUnhandledKeyEvent` (pre/unhandled key routing, PLAN §2.4), `webContentsDidClose`, observable `securityState` and `findResult`, `.closed` in `WebContentsState`, download pause/resume/cancel on `Profile`. (4) `features` is the startup override set (`EngineFeatures` in `EngineConfiguration`), since Chromium fixes `base::FeatureList` at startup and CEF cannot query it. (5) `WebContentsUIDelegate` members have default "no UI" implementations (dismiss/deny/cancel; unhandled keys to the main menu), standing in for ObjC `@optional`. (6) Value types are `nonisolated` + `Sendable` so they are usable off the main actor despite the package's MainActor default isolation.
  - Findings for Phase 1.4 (from the mapping review): CEF cannot make a windowed browser transparent through `background_color` (CDP override instead); `CefWindowInfo::hidden` is ignored with `SetAsChild`; `CefAudioHandler` capture mutes the speakers, but returning `false` from `GetAudioParameters` still gives a "became audible" edge; `LoadURL` always uses TYPED|FROM_ADDRESS_BAR. For Chapter 3: `SecurityStateTabHelper` is gone in M154 (`chrome_security_state::` functions), `TabHelpers::AttachTabHelpers` is friend-gated, main-world JavaScript needs CDP or a `//room` hook.
  - Observation: quit time is load-sensitive. At load average ~40–48 (Chrome, Spotlight, a parallel source scan) quits took 0.4–7.9 s and one run exceeded the smoke script's 10 s limit; the pre-phase build (360c68f) built side by side also exceeded 10 s once under the same load, so this is not a regression. Phase 1.4's "⌘Q < 1 s" spike should be measured on an idle machine and record the load average.
  - Next: Phase 1.3 (the window), when the user says go.
- 2026-10-02 — Phase 1.3 (Claude Code session).
  - Done: `Design` (spacing/radii/sidebar/card/type/material/motion tokens, springs via `CASpringAnimation(perceptualDuration:bounce:)`, asset-catalog colors, 84 SF Symbol names checked to exist); `Card` (`CardView` = `ShadowBackingView` sibling + `CardContainerView`: continuous corner, `masksToBounds`, 1px hairline as `CALayer` border, which composites above sublayers so the page cannot cover it; settable background; `contentView` slot; never drags the window); `UIKitCore` (`RoomWindow`, `RoomWindowController`, `BrowserWindowView` manual layout, `WindowMaterialView` + `SpaceTintView` gradient 10–25% with animated color change, `TrafficLightLayout` re-measuring on resize/fullscreen/title/style/appearance/backing/titlebar re-layout, `WindowActivity`, sidebar dimming to 60% alpha and 80% saturation when inactive, `SidebarSplitterView` with a tracking loop and direction-aware column-resize cursor, snap closed under 120 pt with `sidebarDidSnapClosedNotification`, width restored on reopen; View ▸ Hide/Show Sidebar ⌘S); DEBUG `WindowSnapshot` capture and app snapshot runner; `scripts/window-snapshots.sh`; tests: Design 9, Card 7, UIKitCore 21 (traffic-light stability across title/appearance/resize, buttons never moved, layout math, splitter outcomes, titlebar-band hit testing, dimming, 10 window-state captures incl. FakeEngine page in the card), all also in the Room scheme's test action; the no-engine CI spec builds and tests locally. Smoke launch after the change: quit 0.25 s / 0.32 s, no helpers left, no crash reports (load average 33).
  - Deviations: (1) Card inset 6 pt and corner radius 10 pt instead of the ROADMAP's 8 and 12, measured from `dia-window.jpg`; PLAN §2.4 and the ROADMAP 1.4 clipping item updated. (2) The window has an empty `NSToolbar` with `.unified` style: that is what puts AppKit's traffic lights where Dia's are (19,19 vs 9,9); buttons are never moved, consistent with the rule; PLAN §2.4 notes it. (3) The window is moved by `performDrag(with:)` from the sidebar background's `mouseDown` (plus `mouseDownCanMoveWindow`), with `isMovableByWindowBackground = false`; the card and material refuse window drags. (4) Double-click on the sidebar background does nothing yet: the feature spec reserves it for "new tab" (§F). (5) Snapshot tests check invariants (clipping, fill, shadow, inset, title contrast) and write PNGs for review instead of diffing against stored references, because the behind-window material varies with the desktop. Test-process windows never become main, so "active" in tests is forced with `activityOverride`; the real-app captures use real focus. (6) Dark card fill darkened to rgb(24,24,25) after the dark+inactive snapshot showed too little contrast with the inactive material. (7) No sidebar width persistence yet (Chapter 2.1 store). (8) The macOS 26 window-capture API is unavailable in the SDK; `CGWindowListCreateImage` is called through `dlsym` in DEBUG builds only.
  - Observations for later phases: with the sidebar closed, the traffic lights overlap the card's top-left corner; spec §E's floating 38 px cluster (Chapter 2.7) resolves it. Fullscreen sets `TrafficLightGeometry.none` and the header falls back to a 16 pt leading inset; not exercised in tests (needs a real Space transition). Script-launched apps are often refused activation while the user works elsewhere; any future UI automation needs the same retry/verify pattern.
  - Next: Phase 1.4 (CEF inside the card), when the user says go.
