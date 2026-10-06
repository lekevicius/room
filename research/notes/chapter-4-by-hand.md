# Chapter 4 — by hand

What the Chapter 4 sessions could not check without a click, a device, an account or a decision: one ordered list, grouped by the phase that left it, each phase's list written the same day as the phase (ROADMAP Chapter 4 "Decisions": at most ten steps per phase), for the user's pass when the chapter ends. The implementer appends its "needs a hand" items under its phase; the planner keeps the file tidy. Friction goes into `docs/backlog.md` as a new row with the phase as the source ("4.x by-hand"), as in Chapters 2 and 3.

## The current DMG

- **3.9-2's** `build/sparkle-3.9/` DMG (155.0.8059.36, series 23, schema v6) is what the user runs on 2026-10-06. The Chapter 4 DMGs are listed here as each phase ends, newest first, with "run `scripts/reset-state.sh` first" when the schema moved on.

## Setup

1. **Launch** on a fresh throwaway state, never the real one: `build/roomcore/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-4/hand -RoomEngineDirectory /tmp/room-4/hand/engine -RoomSidebarFixture demo` (written "Room …" below). The Debug app over the release framework (`build/roomcore-release/DerivedData/Build/Products/Debug/Room.app`) is the one to use for anything judged on feel or memory: no DCHECKs (B-76), a renderer starts in 0.03 s.
2. **The test servers**, in a second terminal: `scripts/test-servers.sh`. Steps marked **[S]** need it.
3. **Light, then dark** for anything visual (Settings ▸ Appearance).
4. **System dialogs**: sessions never answer them; answer any you find as you see fit.
