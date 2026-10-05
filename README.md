# Room

A macOS browser: Chromium engine, native Swift/AppKit chrome, the Arc/Zen sidebar model, Dia-level polish. No AI.

- `PLAN.md` — decisions and architecture (why a Chromium fork behind an ObjC API, what the engine/UI boundary is, settled engineering choices, risks).
- `ROADMAP.md` — Chapters and Phases; the current chapter is specified in detail.
- `docs/progress.md` — phase tracker and log.
- `research/` — the research reports the plan is based on (`research/README.md` is the index).

Status: Chapter 3 (RoomCore), Phase 3.9: Room runs on its own Chromium fork only (CEF, the Chapters 1–2 scaffold, was deleted in 3.9).

## Layout

```
App/               Swift app target: main.swift, AppDelegate, menus, composition root;
                   App/RoomCore is the embryo host the engine-level scripts drive
Packages/          local Swift packages (Engine, EngineRoomCore, UIKitCore, Card, Design, Infra, …)
Engine/roomcore/   the Chromium fork: room/ (our GN targets, the ObjC API), patches/, args/
Design/            tokens, reference material
scripts/           bootstrap, build, sign, notarize, appcast
docs/              engine API mapping, backlog, progress
research/          notes/, screenshots/, repos/ (gitignored clones)
```

## Requirements

macOS 26+ on Apple silicon, Xcode 27, XcodeGen, jq, depot_tools (for the fork; the checkout lives outside the repo, `CHROMIUM_ROOT` in `local.env`, default `~/chromium`). `docs/setup.md` has every step.

## Build

```
scripts/chromium-checkout.sh   # Chromium on the pinned tag (hours, ~110 GB)
scripts/roomcore-apply.sh      # the room branch with the patches, gn gen
scripts/roomcore-build.sh      # the component build (hours; ROOM_BUILD_JOBS=6 under 32 GB)
scripts/roomcore-package.sh    # stage RoomCore.framework, build Room.app (scheme "Room (RoomCore)")
scripts/smoke-launch.sh        # launch, quit, check for a clean exit
xcodegen && xcodebuild test -scheme Room -derivedDataPath build/DerivedData   # the engine-free app and the unit tests (CI)
```
