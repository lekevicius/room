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
2. Branding/build: a `room` branding directory (`chrome/app/theme/room` equivalent) with product name, bundle ids, icon placeholder; GN `branding_path_component`; disable `enable_updater`, Google-specific features; confirm the `chrome` target builds with `is_chrome_branded=false` and our names, producing `Room Framework.framework` (renamed `RoomCore.framework` in packaging).
3. Public ObjC API target `//room/core` (compiled into the framework; umbrella `RoomCore.h` + `module.modulemap`; `NS_SWIFT_UI_ACTOR` on every class):
   - `RoomApplication` (`initialize:` with argc/argv/profile path, `run`, `tryToTerminate:`, `createProfile`, `profiles`) over `ChromeMainDelegate`/`BrowserMainParts`; the host `NSApplication` conforms to `CrAppProtocol` (patch `chrome_browser_application_mac` to accept a host-provided application object instead of creating `BrowserCrApplication`).
   - `RoomProfile` over `Profile` (`createWebContents:`).
   - `RoomWebContents` over `content::WebContents` (`nativeView`, `load:`, `goBack/goForward/reload`, title/url/isLoading KVO via `WebContentsObserver`).
   - `RoomBrowser` over `Browser` with `RoomBrowserWindow : BrowserWindow` (all virtuals stubbed; `GetNativeWindow` returns the host `NSWindow`; `Show/Close/Activate` forward to the host). Patch `browser_window_factory.cc` to construct it. `grep AsBrowserView() chrome/` on the pinned tag and record the count and the first crashes hit.
4. Host executable: the Swift app (`App/main.swift`) `dlopen`s `RoomCore` and calls `RoomMain(argc, argv)` which runs `ChromeMain`; helpers reuse Chromium's helper executables renamed. (If handing the main loop to Chromium conflicts with our `NSApplication` subclass, record the fix: ArcCore does exactly this, so it is solvable.)
5. Packaging script: assemble `Room.app` from `out/dev` artifacts (framework, helpers, resources), ad-hoc sign, launch.
6. Measure: incremental build time for a change in `//room/core`; full relink time; framework size. The branding change forces a large rebuild anyway, so run it as a clean build at normal priority (started from `bash`, never zsh `&`) and record it as the true clean-build time; Phase 1.1's 4 h 24 min was mostly at nice +5.

Exit criteria: `Room.app` built from the fork shows a page in the Phase 1.3 window; back/forward/reload work; quit is clean; `RoomBrowserWindow` stubs did not need more than a handful of real implementations to reach this point; build-log has fork numbers.

### Phase 1.6 — Chapter review

Tasks:
1. Write `research/notes/chapter-1-review.md`: spike results summary, build timings, memory numbers, what surprised us, re-ranked risk table.
2. Confirm or amend the engine plan (CEF scaffold → RoomCore). If Phase 1.5 failed in a way that changes the estimate materially, re-plan Chapter 3 before starting Chapter 2.
3. Freeze design tokens v0 and the reserved-shortcut set.
4. Draft the Chapter 2 detailed spec (phases below expanded into tasks/exit criteria) and a backlog in `docs/backlog.md`.

Carry-overs the Chapter 2 spec must place (from Phase 1.3): with the sidebar closed the traffic lights sit over the card's top-left corner and nothing in the window is a drag handle (card and material refuse drags), so the floating traffic-light cluster (2.7) also has to be the drag region; sidebar width persistence (2.1 store); double-click on the sidebar background = new tab (§F); fullscreen behaviour of the header (traffic lights leave the window, header falls back to a 16pt inset) needs a real-Space test.

Chapter 1 exit: Phases 1.1–1.6 closed; `PLAN.md` §4 decisions updated with anything learned; Chapter 2 spec written.

---

## Chapter 2 — The sidebar browser (on CEF)

**End state.** You use Room all day for light browsing. All Arc/Zen interaction decisions are implemented and felt; the only complaints are the known CEF caps (no extension popups, no password save prompts). Spec: `feature-spec.md` sections A–I minus items that need RoomCore.

Phases:
- **2.1 Model and store.** GRDB schema (spaces, entries with kind/storedURL/title/favicon/customIcon, folders, split groups, windows, settings), `@Observable` store, debounced transactional session writes with generation counter + JSON snapshot, favicon cache, migrations. Exit: store survives kill -9 mid-write; unit tests.
- **2.2 Sidebar.** `NSOutlineView`-based tree: essentials grid row, space title row, pinned section with folders, separator/Clear, today section, footer; selection pill; hover states; inline rename; context menus; drag/drop within and across sections with type conversion; multi-select; keyboard navigation. Exit: every interaction in spec §A.2–A.9 works against `FakeEngine`.
- **2.3 Tabs and the card.** One `WebContents` per loaded entry; hidden views for background tabs; selection switching; unloaded entries; ⌘W semantics (`reset-unload-switch`); discard on idle; audio state; changed-dot and reset; link-from-pinned behavior (in place for v1; Peek in 2.7). Exit: 50 entries, 10 loaded, switching under 16ms.
- **2.4 Palette v1.** Centered overlay; ⌘T/⌘L semantics; groups: top hit, open tabs, pinned/essentials, local history (small FTS5 table recorded from navigations; throwaway), search suggest (Google/DDG/Kagi), commands; inline host completion; site-search keywords. Exit: spec §C minus engine-provided ranking.
- **2.5 Spaces.** Create/edit (name, icon, theme colors, algorithm), per-space lists, window tint, footer icons/dots, ⌃1–9, ⌘⌥←/→, two-finger swipe, drag-to-space-icon, per-space `CefRequestContext` (container). Exit: spec §B minus routing.
- **2.6 Chrome surfaces.** Downloads (footer button with progress ring, popover, fly-in animation, filename decision), permission popover anchored to the address field, JS dialogs as in-card sheets, context menus, file chooser, HTTP auth, certificate errors, popups → entries, find bar, zoom, print, DevTools pane with resize, status pill. Exit: all CEF delegate callbacks have UI.
- **2.7 Hide/reveal, split view, Peek.** ⌘S/⌘⌥S, edge hover band + overlay, splitter snap toast; split groups ≤4 with layouts, drag-to-split zones, pane header; Peek overlay for off-site links from permanent entries. Exit: spec §D, §E, §I.6.
- **2.8 Shortcuts, menus, app integration.** Full §G table, main menu in code with validation, settings for remapping, default-browser prompt, URL ingestion from other apps, Sparkle wired (dev feed), Sentry wired.
- **2.9 Dogfood week.** Use it exclusively for a week; triage; fix the top 20; write `chapter-2-review.md`.

---

## Chapter 3 — RoomCore

**End state.** `RoomCore.framework` implements the whole `Engine` protocol plus the Chrome-only capabilities (extensions, passwords, autocomplete, session service, discarding); `EngineCEF` is deleted; the fork rebases to a new Chromium stable with a script.

Phases:
- **3.1 Bootstrap and packaging.** Everything from Phase 1.5 made production-grade: profiles directory, `Local State`, crash keys, feature flags, logging, resource bundle, locale pruning, codesign/notarize scripts for the framework and helpers, dev and release GN args, static release build measured.
- **3.2 `RoomBrowserWindow` and `RoomBrowser`.** Real implementations of the `BrowserWindow` methods we need (activation, bounds, fullscreen, `ExclusiveAccessContext`, tab strip observer → delegate, command dispatch, status bubble, find bar interface), stubs for the rest with telemetry on hits; `Browser` per window; `takeOwnership(webContents)`; popups and PiP browser types.
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
- **4.4 Settings.** SwiftUI settings window: general, search engines, shortcuts (conflict detection), spaces/profiles, privacy (site data, permissions per origin), downloads, appearance, extensions.
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
