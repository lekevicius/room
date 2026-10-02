# Room

A macOS browser: Chromium engine, native Swift/AppKit chrome, the Arc/Zen sidebar model, Dia-level polish. No AI.

- `PLAN.md` — decisions and architecture (why a Chromium fork behind an ObjC API, what the engine/UI boundary is, settled engineering choices, risks).
- `ROADMAP.md` — Chapters and Phases; the current chapter is specified in detail.
- `docs/progress.md` — phase tracker and log.
- `research/` — the research reports the plan is based on (`research/README.md` is the index).

Status: Chapter 1 (Foundations), Phases 1.1–1.4 done; next Phase 1.5.

## Layout

```
App/               Swift app target: main.swift, AppDelegate, menus, composition root
Helpers/           helper app targets (Info.plist + entitlements per helper)
Packages/          local Swift packages (Engine, EngineCEF, UIKitCore, Card, Design, Infra, …)
Engine/cef/        pinned CEF distribution + CMake wrapper build (dist/ is gitignored)
Engine/roomcore/   the Chromium fork: room/ (our GN targets), patches/, chromium_src/, args/
Design/            tokens, reference material
scripts/           bootstrap, build, sign, notarize, appcast
docs/              engine API mapping, backlog, progress
research/          notes/, screenshots/, repos/ (gitignored clones)
```

## Requirements

macOS 26+ on Apple silicon, Xcode 27, XcodeGen, CMake, jq, depot_tools (for the fork; checkout lives outside the repo at `~/chromium`).

## Build

```
scripts/bootstrap-cef.sh       # pinned CEF into Engine/cef/dist, builds libcef_dll_wrapper
xcodegen                       # project.yml → Room.xcodeproj
xcodebuild -scheme Room -derivedDataPath build/DerivedData build
scripts/smoke-launch.sh        # launch, quit, check for a clean exit
scripts/chromium-checkout.sh   # ~/chromium on the pinned tag (hours, ~100 GB)
```
