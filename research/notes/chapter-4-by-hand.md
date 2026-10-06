# Chapter 4 — by hand

What the Chapter 4 sessions could not check without a click, a device, an account or a decision: one ordered list, grouped by the phase that left it, each phase's list written the same day as the phase (ROADMAP Chapter 4 "Decisions": at most ten steps per phase), for the user's pass when the chapter ends. The implementer appends its "needs a hand" items under its phase; the planner keeps the file tidy. Friction goes into `docs/backlog.md` as a new row with the phase as the source ("4.x by-hand"), as in Chapters 2 and 3.

## The current DMG

- **3.9-2's** `build/sparkle-3.9/` DMG (155.0.8059.36, series 23, schema v6) is what the user runs on 2026-10-06. The Chapter 4 DMGs are listed here as each phase ends, newest first, with "run `scripts/reset-state.sh` first" when the schema moved on.

## Setup

1. **Launch** on a fresh throwaway state, never the real one: `build/roomcore/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-4/hand -RoomEngineDirectory /tmp/room-4/hand/engine -RoomSidebarFixture demo` (written "Room …" below). The Debug app over the release framework (`build/roomcore-release/DerivedData/Build/Products/Debug/Room.app`) is the one to use for anything judged on feel or memory: no DCHECKs (B-76), a renderer starts in 0.03 s.
2. **The test servers**, in a second terminal: `scripts/test-servers.sh`. Steps marked **[S]** need it.
3. **Light, then dark** for anything visual (Settings ▸ Appearance).
4. **System dialogs**: sessions never answer them; answer any you find as you see fit.

## Phase 4.1a — the Archive, the sweep, the Library

The DMG with 4.1a moves the schema to v7 (the `archive` table): the first launch archives the Today tabs you have not used for 12 hours (Settings ▸ General ▸ Archive tabs after); they are in the Library (⇧⌘L) and come back with Restore. No reset is needed (v6 → v7 migrates); `scripts/reset-state.sh --dry-run` shows what a reset would move.

"Room-A" below is the Debug app over the release framework on the archive fixture, two hours ahead, with the test servers running **[S]**:
`build/roomcore-release/DerivedData/Build/Products/Debug/Room.app/Contents/MacOS/Room -RoomStateDirectory /tmp/room-4/41a -RoomSidebarFixture archive -RoomClock $(date -u -v+2H +%Y-%m-%dT%H:%M:%SZ)`
(its engine root is `/tmp/room-4/41a/engine` by default now, B-78; delete `/tmp/room-4/41a` to start over).

1. **The Library** [S]: Room-A. The sidebar shows "Selected", "Split" (beside "Docs") and "Young" in Space, "Two Young" in Two; the old ones are gone. ⇧⌘L: the essentials and lists give way to the search field and Archive (5, by day), Downloads, History; the header and the footer stay. Click a section title to collapse it; type "two" in the field (Archive filters); Esc clears the field, a second Esc returns to the spaces; ⇧⌘L again returns too; click a space dot in the footer while the Library shows (the spaces come back). ⌘Y: the Library with History open and the field focused. Judge: usable, rows readable in light and dark (looks are Chapter 5's).
2. **Restore and ×** [S]: in the Library click "Two Old A" (or its ↺): it is selected at the top of Two's Today list and its page loads with Back available if it had history; × on another row removes it; "Clear Archive…" asks first, Cancel keeps the rows.
3. **Archive from the menu** [S]: right-click a Today tab ▸ Archive Tab; ▸ Archive Tabs Below on the first of several; ⌘-click two tabs ▸ Archive 2 Tabs. Each shows "N tabs archived · Undo"; Undo puts them back in place; without Undo they are in the Library (reason shown nowhere, the Archive is one list).
4. **Clear** [S]: ⇧⌘K in a space with Today tabs: the rows slide out, "N tabs closed · Undo"; open the Library: the tabs are there; ⇧⌘K again on new tabs and Undo: they come back and leave the Archive. Settings ▸ General ▸ Tabs ▸ Archive tabs after offers 12 hours, 24 hours, 7 days, 30 days; set 24 hours, quit, relaunch Room-A on a fresh directory: "Old 3" (13 h) stays.
5. **The palette** [S]: with something archived, ⌘T and type part of its title: a History row with the "Archived" chip and the hint "Restore"; Enter brings it back to its space, selected; ⌘Enter instead opens a copy as a new tab and keeps the archived row.
6. **Delete a space** [S]: Two's menu ▸ Delete Space…: the alert says its tabs go to the Archive; after Delete the Library lists them with the chip "Two"; within 8 s the toast's Undo brings the space back with its tabs (and the rows leave the Archive); after the toast, Restore puts a row into the active space (its space is gone).
7. **Downloads and History in the Library** (your real profile or Room-A after a download from [S] `http://127.0.0.1:8766/download?size=1000000`): Downloads lists it with Show in Finder and ×; × removes it from the list, and a relaunch lists it again until 4.1b (B-59). History lists the last week by day; a click opens the page as a new tab; right-click ▸ Delete All from <host>. On a state that has `history-archive.json` (the real state if 3.9's migration wrote one), search for an old site: rows from the file carry the "Archived" chip.
