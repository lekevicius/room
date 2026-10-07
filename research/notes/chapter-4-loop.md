# Chapter 4 loop — the planner's session log

The planner session that runs Chapter 4 end to end on the Mac mini (`docs/chapter-loop-prompt.md`): one entry per implementer session (outcome, wall time, decisions, what went on the user's list in `chapter-4-by-hand.md`, which DMG the user has), a closing section at the end. This file and `docs/progress.md`'s log are the planner's memory between sessions.

Machine: Mac mini M4, 24 GB, user `eve`; the checkout is `/Users/eve/Code/room`. Chromium at `/Volumes/Chromium/chromium/src` (APFS sparse bundle, `local.env`), on `155.0.8059.36` with the 23-patch series; `out/dev` and `out/release` built and staged (`build/roomcore`, `build/roomcore-release`). The user's notarized Room (3.9-2's DMG, `build/sparkle-3.9`) runs on the real state while the loop works; nothing here touches it. The Claude desktop app is frontmost throughout (activation failures in a tour step are the run's condition when a standalone rerun passes). Session prompts are saved under `build/chapter-4-prompts/` (gitignored).

Started 2026-10-06 15:50. Disk 86 GB free at the start.

## Sessions

### 4.1a — accepted (2026-10-06 15:52 → 16:38, 46 min)

Outcome: accepted. Tasks 0–5 done: the five tooling carry-overs (B-78, B-79, `--drop`, the tour's conditions line, `reset-state.sh`), schema v7's Archive, the sweep with the engine's blockers, `Packages/Library` in the sidebar, the palette's Archived chip, tour step `archive` 28 / 28 on both builds, CI green on the implementer's push. Decisions: B-80 (no Archive retention; the kill test's 18k rows doubled the commit time) is 4.1b's with a 30-day retention and navigation states dropped after 7 days as the provisional rule; the Archive stays out of the JSON snapshot (the database backups carry it). No "3.9 week" rows yet. User's list: `chapter-4-by-hand.md` "Phase 4.1a" 1–7. DMG: the user still has 3.9-2's (the phase's DMG comes after 4.1b).

### 4.1b — accepted; Phase 4.1 closed; the DMG (2026-10-06 16:42 → 17:46, 64 min; the DMG 17:46 → 17:49)

Outcome: accepted; the phase closed with every exit item behind a measured line. The engine step went first and the official incremental ran beside the app work: **8 min 5 s wall** (404 s of build, the link 353 s at 8.58 GiB), the export-order check passed, so **a DMG follows every engine step** for the rest of the chapter (PLAN §4 amended). Backups, Restore Sidebar…, crash recovery, the snapshot without navigation states (5.76 MB → 157 KB), the Archive's retention; tour step `recovery` 18 / 18 on both builds. Decisions: B-81 (a Browser reused after its deletion is scheduled; the app holds a blank page during a restore) to 4.3b's engine step; B-82 (`roomSpikeAction:` on the release framework) to 4.2 as a guard. The DMG: version 2, Release app rebuilt (66 s), signed and notarized (82 s), `build/sparkle-4.1/Room-0.1.0-2.dmg` (178 MiB), unsigned appcast entry; at the top of the by-hand list with the reset note (v7 is additive). User's list: Phase 4.1 at 10 of 10 steps. DMG the user has: 3.9-2's until they install 4.1's.

### 4.2 — accepted; Phase 4.2 closed; the DMG (2026-10-06 17:52 → 18:36, 44 min; the DMG 18:37 → 18:40)

Outcome: accepted; the phase closed in one session with every exit item behind a measured line. Routing rules (schema v8), the external and cross-space evaluation with the toast, the sheet from three entry points, B-35 (a Peek page's fullscreen expands it first), B-57 closed on the release framework (69.5 ms median first paint), B-82's guard; tour step `routing` 25 / 25 and the Peek table 35 / 35 on both builds. Decisions: 4.8a's schema is v9; "most recent space" is the key window's active space until 4.8a; B-83 (the fullscreen restore during the enter animation) to 5.6. The DMG: version 3, `build/sparkle-4.2/Room-0.1.0-3.dmg`, no engine change. User's list: Phase 4.2 steps 11–19 (nine). No "3.9 week" rows yet.

### 4.3a — accepted (2026-10-06 18:44 → 19:29, 45 min)

Outcome: accepted. The readers for every format on hand-made fixtures (Chrome's History from a headless run on a throwaway profile), the plan with its preview, the sheet, tour step `import` 31 / 31 on both builds. Decisions: extensions from another browser are installed by opening their Web Store pages one after another through 3.6a's consent (no twelfth member); a Firefox `places.sqlite` reader is 4.3b's bounded item; B-84 (scale) measured on a generated fixture in 4.3b; B-81's engine fix rides 4.3b's engine step. User's list: Phase 4.3a steps 20–24. DMG: 4.2's (the phase's DMG comes after 4.3b).

### 4.3b — accepted; Phase 4.3 closed; the DMG (2026-10-06 19:33 → 20:22, 49 min; the DMG 20:23 → 20:26)

Outcome: accepted; the phase closed with every exit item behind a measured line. The engine step (`importPasswords`, `//room` +314 lines, no patch, no new exported class) went first; the official incremental **9 min 39 s** beside the app work; B-81 fixed in EngineRoomCore (one crash on the first form, the second holds the closing Browser until `browserDidClose`); the Firefox reader; extensions through their store pages; the first-run and Settings entry points; B-84 measured (B-85 for the 604 ms stall, 5.4); tour step `import` 51 / 51 on both builds, the CSV's passwords filling after a relaunch on both. Decisions: the DMG (version 4, `build/sparkle-4.3/Room-0.1.0-4.dmg`); B-85 to 5.4; B-22's move covers imported profiles. User's list: Phase 4.3 at 10 of 10 (steps 20–29). No "3.9 week" rows yet.

### 4.4a — accepted (2026-10-06 20:30 → 21:25, 55 min)

Outcome: accepted. Shortcut remapping end to end (the table, the menu in place, the palette's hints, the sidebar's menus, the reserved set computed, conflicts, refusals, the AppKit Shortcuts table), General, Search (one engines list with per-profile defaults), Downloads (the save panel, the PDFs setting for 4.7a), tour step `settings` 32 / 32 on both builds; B-86 found and fixed app-side. Decisions: B-86's engine-side copy only if it is a few lines in 4.4b's engine step; Settings at 560 pt. User's list: Phase 4.4a steps 30–34. DMG: 4.3's (the phase's DMG comes after 4.4b). No "3.9 week" rows yet.

### 4.4b — accepted; Phase 4.4 closed; the DMG (2026-10-06 21:32 → 22:51, 79 min; the DMG 22:48 → 22:52)

Outcome: accepted; the phase closed with every exit item behind a measured line. Three members (`//room` +455 lines, no patch, no new exported class), the Google-service defaults (B-74 hidden), B-86's engine copy, the official incremental **9 min 47 s** beside the app work, the net-log 0 engine requests over launch + 600 s idle + browse + quit; profiles renamed with the directory keyed by id (B-22) and deleted (B-87: Chrome's best-effort deletion waits 3 min for a startup signal Room never sends, so `//room` deletes the directory itself), Privacy with the statements and Chromium's site-data page in a tab (B-88); `settings` 32 / 32 and `settings2` 26 / 26 on both builds. Decisions: the DMG (version 5, `build/sparkle-4.4/Room-0.1.0-5.dmg`; the first launch moves the engine directories, said at the top of the by-hand list); B-87 to 5.4, B-88 to 5.6. User's list: Phase 4.4 at 10 of 10 (steps 30–39). No "3.9 week" rows yet.

### 4.5 — accepted; Phase 4.5 closed; the DMG (2026-10-06 22:57 → 23:42, 45 min; the DMG 23:41 → 23:44)

Outcome: accepted; the phase closed in one session with every exit item behind a measured line. Five members (`//room` +425 lines, no patch, no new exported class), the key router (B-70), the overflow menu, site access and Run in Settings and the site panel (B-30's extensions part), extension pages in their profile's space (B-67), the official incremental **8 min 6 s** beside the app work; `extpopup` 18 / 18 and `extensions` 33 / 33 on both builds; the extension's own request counted apart (engine 0). Decisions: the DMG (version 6, `build/sparkle-4.5/Room-0.1.0-6.dmg`); B-89 to 5.2; B-62 waits (no laptop by-hand run yet); Allow in incognito stored host-side for 4.8b. User's list: Phase 4.5 steps 40–47 (eight). No "3.9 week" rows yet.

### 4.6 — accepted; Phase 4.6 closed; the DMG (2026-10-06 23:46 → 2026-10-07 00:32, 46 min; the DMG from 00:33, notarization slow)

Outcome: accepted; the phase closed in one session with every exit item behind a measured line or a recorded finding. The media controls (`//room` +191 lines, no patch), the media row, document PiP in a floating panel (B-51 closed), video PiP's overlay verified, Now Playing found to work through Chrome's own controls (no host code), the autoplay line; the official incremental **8 min 58 s** beside the app work; `media` 32 / 32 on both builds. Decisions: B-62 waits (no laptop run yet); B-90 rides 4.7a's engine step; the DMG (version 7) packaged once Apple returns. User's list: Phase 4.6 steps 48–54 (seven). No "3.9 week" rows yet.

### Note — the 4.6 DMG and GitHub (2026-10-07 01:05–01:45)

Apple's notarization of the 4.6 release app never returned (the background command hit its 30-minute bound; the previous two submissions that evening took 70–85 s), so build 7 was abandoned and the next DMG is build 8 over 4.7a's framework. GitHub Actions stopped running CI at 01:35 on a billing hold (B-93, the user's); the sessions build and test the CI spec locally until then.

### 4.7a — accepted (2026-10-07 00:41 → 01:29, 48 min; the DMG from 01:45 in the background)

Outcome: accepted. `savePage` and the DevTools command (`//room` +324 lines, no patch), B-90, the PDFs-download default through `EngineConfiguration.features`, Save Page…, View Source, ⇧⌘2 with the crop overlay and Full Page (2068 × 8000 in 168 ms), the PDF viewer verified without a fix; the official incremental **8 min 48 s**; `documents` 42 / 42 on both builds; CI not run (B-93), the CI spec green locally. Decisions: B-91 to 5.6, B-92 to 4.9; build 8 for 4.7a. User's list: Phase 4.7a steps 55–59. No "3.9 week" rows yet.

### 4.7b — accepted; Phase 4.7 closed; the DMGs (2026-10-07 01:47 → 02:32, 45 min; build 8 landed 02:12, build 9 from 02:35)

Outcome: accepted; the phase closed with every exit item behind a measured line (the PDF toolbar save's landing is the user's: macOS 26's out-of-process save panel). Reader mode as a second page from a `file://` template with the token CSS (163 / 107 ms to the reader page), the distiller in the isolated world even under a strict CSP, no translate item (B-63), Page Setup with the finding that Chrome's preview overrides it, `reader` 34 / 34 on both builds; the CI spec green locally (GitHub still on the billing hold). Decisions: B-94 to 5.6, B-95 to 5.7; the Phase 4.7a DMG is build 8 (Apple's queue recovered), the Phase 4.7 DMG build 9 app-only. User's list: Phase 4.7 at 10 of 10 (steps 55–64). No "3.9 week" rows yet.

### 4.8a — accepted (2026-10-07 02:36 → 03:34, 58 min)

Outcome: accepted. Multi-window end to end: schema v9, a `WindowSession` per window with every per-window piece of 4.2–4.7b made per window, page ownership by unload and reload (82 ms on release, history kept), the drag out and Open in New Window, the close path archiving `windowClosed`; `windows` 31 / 31 on the release framework (30 / 31 on dev: two live-site DCHECK dumps, B-76); memory with two windows +25 MB over one. Decisions: B-97 (rows no longer drag outside Room) a user row with the provisional choice that the drag out wins; B-96 to 5.5. The Phase 4.7 DMG landed (build 9). User's list: Phase 4.8a steps 65–69. No "3.9 week" rows yet.

### 4.8b — accepted; Phase 4.8 closed; the DMG (2026-10-07 03:42 → 04:59, 77 min; build 10 from 05:02 in the background)

Outcome: accepted; the phase closed with every exit item behind a measured line on the release framework. Incognito without a patch (the series stays 23: patch 0014's hook answers the twin's Browser), the page move through the strip (6 ms, the same page), the off-the-record twin kept alive by a headless Browser (`AddKeepAlive` CHECKs on OTR: the 3.4b lesson in its OTR form), nothing persisted, extensions per the setting; the official incremental **8 min 36 s**; `incognito` 20 / 20 and `windows` 31 / 31 on the release framework; 0 engine hosts with an incognito window open. Decisions: B-98 (one incognito window per profile) to 5.6, the user's; the chapter's members end at twelve. User's list: Phase 4.8 at 10 of 10 (steps 65–74). No "3.9 week" rows yet.
