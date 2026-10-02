# Progress

Current: **Chapter 1 — Foundations**, Phase 1.1 done; Phase 1.2 not started.

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
- [ ] Exit: compiles under Swift 6 strict concurrency; tests pass; mapping reviewed

### Phase 1.3 — The window
- [ ] `Design` package: tokens, dynamic colors, symbol names
- [ ] `UIKitCore`: `RoomWindow`, controller, material view, space tint layer, traffic-light layout, fullscreen, appearance, inactive dimming
- [ ] Sidebar placeholder with splitter (180–500, snap under 120)
- [ ] `Card` package: clipped container, border, shadow sibling, settable background
- [ ] Snapshot tests light/dark, active/inactive, sidebar open/closed
- [ ] Exit: empty window visually matches Dia's chrome

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
