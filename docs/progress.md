# Progress

Current: **Chapter 1 — Foundations**, Phase 1.1 in progress.

Legend: `[ ]` todo · `[x]` done · `[-]` dropped (say why in the log).

## Chapter 1 — Foundations

### Phase 1.1 — Repository and toolchain
- [x] git init, `.gitignore`, `README.md`, `CLAUDE.md`, directory skeleton
- [x] Record decisions: min macOS 26, product name, bundle id prefix, framework name
- [x] `project.yml` (app + five helper targets, entitlements, framework copy/sign phase, local packages)
- [x] `scripts/bootstrap-cef.sh` (pinned CEF 154.0.32 arm64 minimal, SHA check, CMake wrapper build, cefsimple run)
- [ ] Chromium checkout at `~/chromium` on tag 154.0.8037.58; `Engine/roomcore/args/dev.gn`; first component build started; `research/notes/build-log.md`
- [ ] CI stub (compile-only `xcodebuild`)
- [ ] Exit: `xcodegen && xcodebuild` builds `Room.app` with helpers + CEF framework; launches to an empty window; quits cleanly. Chromium checkout complete, first build finished or ETA logged.

### Phase 1.2 — The `Engine` protocol
- [ ] `Packages/Engine` protocols and value types (§1.2 of ROADMAP)
- [ ] `FakeEngine` + tests
- [ ] `docs/engine-api.md` mapping table (Engine ↔ CEF ↔ Chromium/ArcCore)
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
