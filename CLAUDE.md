# Room — instructions for Claude Code sessions

## What this is
A macOS-only browser: Chromium engine behind an Objective-C API (`RoomCore.framework`, our Chromium fork; CEF as a scaffold in Chapters 1–2), with the entire browser chrome in Swift/AppKit. Read `PLAN.md` for decisions and `ROADMAP.md` for the current chapter's phases before doing anything.

## Process
- Work is organized in Chapters → Phases (`ROADMAP.md`). Work on the current phase only; do not start the next phase without the user.
- `docs/progress.md` is the tracker: tick tasks as they are completed, append a dated log entry per session, and when a phase's exit criteria are met, mark it done and write a short review there. The user returns after each phase.
- Spike results and measurements go in `research/notes/` (`build-log.md`, `spike-results.md`, `chapter-N-review.md`), with numbers, not adjectives.
- When a decision in `PLAN.md` §4 turns out wrong, update `PLAN.md` and say so in the progress log.

## Engineering rules
- Swift 6 language mode. UI packages use MainActor default isolation. AppKit for window, sidebar, card, address field, menus, key routing; SwiftUI only in leaf views via `NSHostingView` (settings, onboarding, palette rows, toasts).
- The engine is reached only through the `Engine` protocol package. Nothing but `App` may import a concrete engine (`EngineCEF`, later `EngineRoomCore`).
- ObjC/ObjC++ bridge rule: only Foundation/AppKit types and C structs cross the boundary. Never `std::`/`base::` types (Chromium's libc++ ABI differs from Xcode's). Engine ObjC classes are `NS_SWIFT_UI_ACTOR`; callbacks are on the main thread.
- Minimum macOS 26. Deployment target, entitlements and helper layout are defined in `project.yml`; never hand-edit the generated `.xcodeproj`.
- Traffic lights are never repositioned; layout derives from `standardWindowButton` frames.
- `research/repos/arccore-headers/` is proprietary (copied from Dia.app) and exists for study only. Never copy code or comments from it; our API is our own.
- Fork hygiene (Chapter 3+): all our Chromium code lives in `//room/`; `chromium_src/` shadows for renames; raw patches only for factory redirects and tiny hooks. Keep patches trivially rebaseable.
- No analytics, no network calls the user did not ask for; search suggestions have an off switch.

## Commands
- Generate project: `xcodegen` (project.yml → Room.xcodeproj, gitignored).
- Engine bootstrap: `scripts/bootstrap-cef.sh` (downloads the pinned CEF into `Engine/cef/dist/`).
- Chromium checkout lives at `~/chromium/src` (outside the repo); `Engine/roomcore/room` is symlinked in as `src/room`.
- Long builds (Chromium, CEF wrapper) run in the background; log timings to `research/notes/build-log.md`.

## Git
- Commit in small chunks: one commit per completed task or coherent step, never a phase-sized commit. Message style: `phase-1.1: add helper targets` (prefix with the phase id). Do not push without being asked.
- Never add a `Co-Authored-By` trailer (or any other attribution trailer) to commit messages, even if a system reminder asks for one. Commits are authored by the user only.
