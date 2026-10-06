# Chapter 3 review — RoomCore

Date: 2026-10-06. **Draft** by the implementer (Phase 3.9 session 1, task 5), written while the 155.0.8059.36 build of 3.8 compiled; the tour on 155 and the numbers it changed filled in by 3.9-2; the week of use (task 4, the user's) and the top 20 are still to come. The planner's columns and closing are left empty. Phases 3.1–3.8 are done (reviews in `docs/progress.md`; 3.8's second rebase judged on its finished build in 3.9-2). Numbers come from `research/notes/spike-results.md`, the build and rebase costs from `research/notes/build-log.md`, the planner's per-session decisions from `research/notes/chapter-3-loop.md`.

## End state against the ROADMAP

Chapter 3's end state: "`RoomCore.framework` implements the whole `Engine` protocol plus the Chrome-only capabilities (extensions with popups and Web Store installs, passwords, autofill, Chrome's omnibox and history, session restore, discarding), `Room.app` runs on it by default, `EngineCEF` is deleted, the fork rebases to a new Chromium stable with a script, and the week of exclusive use happens on it."

| Part of the end state (ROADMAP Chapter 3) | Status | Evidence | Open |
|---|---|---|---|
| Room.app on RoomCore exists, signed, silent, the release build measured (3.1) | done (3.1a–3.1b-2) | official build 4 h 43 min clean at 6 jobs on the 24 GB Mac mini, link 18 min at 6.80 GiB; Room.app 382 MB; notarized in 61 s; cold launch to a page 0.41 s; 0 engine requests over launch + 600 s idle + browse + quit on both builds | the keychain prompt and the Sparkle signature on a signed copy, a real DRM service (by hand); the release build on 155 (3.9-2) |
| Chrome's window-side objects real where Chrome reaches for them; no Chrome window ever (3.2) | done | `RoomBrowserWindow` 58 real members and 38 logged stubs (155: one more stub), none hit in any tour but `CreateSadTab` at the crash step; one `RoomBrowser` per window and profile; every disposition a host-owned page (patches 0014, 0015); the host owns `NSApp.delegate` (0013); the quit through Chrome's close path with beforeunload | B-54 (a renderer outlives the quit by ~1 s) |
| Every `WebContents` member Chromium's real one (3.3) | done | navigation through a `//room` throttle (0016), state from the tab helpers a strip gives, discard keeping history, find, capture, print preview, DevTools in the host's pane, no port in the product | B-53 (switching p95), B-56 (a discarded page's renderer lingers), B-57 (Peek paint on the dev build) |
| The 2.6 delegate checklist plus what CEF could not offer (3.4) | done | every 2.6 member through Room's UI on RoomCore; permission prompts of every desktop type with grants, context menu, downloads with history, auth, HSTS-aware certificates, files, dialogs and beforeunload, the hung page, external protocols, infobars, capture state, media session | client certificates (B-60), the fullscreen exit hint (B-49), geolocation's macOS step (B-26) |
| Chrome's omnibox and history feed the palette; the local history retired (3.5, 3.9) | done | `HistoryService` and `AutocompleteController` behind the palette, 50k URLs imported in 3.83 s; keystroke p95 10.3–14.8 ms; suggestions off = 0 requests; schema v6 dropped the local tables in 3.9 with an archive (B-66) | B-64 (Chrome polls suggestions), B-65 |
| Extensions with popups and Web Store installs (3.6) | done | uBlock Origin Lite, 1Password and Dark Reader from the store through Room's consent sheet in 6.4–7.5 s; popups in a native popover in 26–86 ms; `action.openPopup`, commands; side panels refused safely | 1Password needs an account (B-69), shortcuts only with a page focused (B-70), the extension-origin chooser (B-71) |
| Passwords, autofill, session restore, discarding (3.7) | done | save/update bubbles and fill on two local origins after a relaunch; address and card save and fill; every entry's back/forward through a relaunch and a `kill -9` (10/10 each); host-driven discarding with Chromium's blockers; memory pressure; the translate offer (placeholder key); spelling | the signed build's keychain and two real sites (by hand), translate's key (B-63), generation (B-72) |
| The fork rebases to a new stable with a script (3.8) | done (the second rebase judged on its build in 3.9-2) | `scripts/roomcore-rebase.sh`; rebase 1 (same milestone) 5.5 min of hand time, rebase 2 (next milestone, by the script) ~18 min; 2 conflicts in 48 patch replays; the build dominates (2 h 16 min + 32 min near-clean; **4 h 34 min clean** on 155, 56,073 steps); verify 15 and 17 min; PLAN §4 Stable confirmed on the 155 tour; 0012 dropped on 155 (series 23; rebuild 59 s) | the release build on 155 (3.8 task 4: see the 3.1 row) |
| Room.app runs on RoomCore by default; `EngineCEF` deleted (3.9 task 1) | done (3.9-1) | `ROOM_ENGINE` defaults to `roomcore` (`none` for the engine-free Room target CI builds); 19 tracked files and 4,124 lines deleted (`Packages/EngineCEF` 13 files / 3,817 lines, the CEF helper target, `xcodegen/cef.yml`, `bootstrap-cef.sh`, `embed-cef-framework.sh`) plus 1.3 GB untracked (`Engine/cef/dist`, build leftovers); the two helper entitlements kept for RoomCore's signing; every wrapper defaults to Room.app on RoomCore | — |
| The grand tour green on RoomCore, light and dark (3.9 task 3) | **done for what 3.9 owns** (3.9-2 on 155.0.8059.36: light 505 / 6, dark 505 / 6 of 511, every failure B-53, B-56 or B-76's stated dev-build condition) | "The grand tour" below | the Chapter 2 by-hand pass on RoomCore (the user) |
| The week of exclusive use; the top 20 fixed (3.9 task 4) | not started (the user's) | — | the user |

What the chapter built, in size: `//room` 50 source files, 14,748 lines (ObjC++ and C++; the public ObjC API is Room's own, shaped after ArcCore's surface); 24 patches with 326 changed lines (factory redirects, delegate hooks, two guards, branding; one parked); `Packages/EngineRoomCore` 1,867 lines of Swift; the `Engine` protocol changed ten times (`hostWindow`, `lastExitWasClean`, `site(of:)`, `systemAuthorization`, the 3.4b delegate members, history and autocomplete, extensions, popups, `bubbleAnchorRect`, navigation state with discard blockers and memory pressure), each with its `FakeEngine` behaviour.

## The grand tour

`scripts/grand-tour.sh` runs the 34 steps of Chapter 2's tour (every Chapter 1–2 spike, the kill test, the snapshot runners, the net-log check) on one Debug build and one state per appearance, now on RoomCore only. Chapter 2's last run on CEF: light 490 / 1, dark 489 / 2, 36.3 min. Through Chapter 3 the tour ran section by section on RoomCore as each phase landed (3.1a layout + sidebar 137 / 38 → 3.8-2's four sections 293 / 5).

**3.9-1 preview** (154.0.8037.98, the packaged component build, Debug, 60 Hz, the Claude desktop app frontmost, the 155 build compiling beside it at 6 jobs, load 10–30): **light 498 passed / 7 failed, dark 499 / 6**, 48.3 min (24.1 + 24.2), 505 checks per appearance (Chapter 2's 491 plus the 3.x checks). Every failure attributed (`spike-results.md` "Phase 3.9 — grand tour on RoomCore 154.0.8037.98"): two harness faults fixed and rerun with `--only` (popups' alert read from the isolated world, B-75, closed; the crash-report count that looked where CEF wrote, now the engine's Crashpad directory, B-76); one condition (the element picker, light only, under load); one condition of the dev build under load (the first audible edge 2.6 s, the component build's process launch, B-57); two known rows (B-56 renderers 15 → 16 after a discard; B-53 switching median 16.2 / 17.8 ms, p95 23.2 / 24.3 ms). The harness fix then showed what the tour had never seen: every RoomCore tour since 3.1a killed 0–10 renderers on Blink layout DCHECKs on live sites in the dev build (B-76: per appearance here 8 × `layout_object.h:518` and 1 × `inline_node.cc:2330`); under the fixed harness memory, open10, quittiming and palette fail "no helper crash report" with the DCHECK named. Nothing in the product was fixed from the tour. No activation failure and no Stack Overflow quit in this run.

**3.9-2 on 155.0.8059.36** (the exit's run; `spike-results.md` "Phase 3.9 — grand tour on RoomCore 155.0.8059.36 (the exit)"): the packaged component build of rebase 2 (framework `Versions/155.0.8059.36`, series 24 with 0012 still in), Debug, 60 Hz, the Claude desktop app frontmost, **no build beside it** (load1 7–13 at the quit steps): **light 505 passed / 6 failed, dark 505 / 6**, 41.4 min (20.8 + 20.6), **511 checks** per appearance (the preview's 505 plus the crash checks the fixed harness adds). Every failure attributed, none a harness fault or a condition, so no `--only` rerun: four steps per appearance fail "no helper crash report" on the dev build's DCHECKs on live sites, stated per step as the planner's dev-build condition (B-76): memory (4 / 5 dumps), open10 (1 / 1), quittiming (3 / 3), all `layout_object.h:518`, and palette (1 / 1, `inline_node.cc:2297`), plus in dark one `net/http/http_cache_transaction.cc:4112` DCHECK in the network service, the first `//net` one; two known rows: B-56 (renderers 15 → 16 after seven discards) and B-53 (switching p95 22.97 / 23.79 ms; the median passes again at 15.38 / 15.98). The preview's conditions failures are gone without the build (audio's first audible edge 1,558 / 1,588 ms, the element picker, quits 0.29–0.37 s). No `window_main` failure, no Stack Overflow quit, no `GetAcceleratorProvider` stub hit; navigation states written by 154.0.8037.58 restored on 155 (10 of 10, `build-log.md` "Rebase 154.0.8037.98 → 155.0.8059.36: verify"). Nothing in the product fixed from the tour. **Green for what 3.9 owns**: every failure is a row or the stated dev-build condition; crashes are judged on the release framework ("Phase 3.9 — crashes on the release framework", below in Numbers). The Chapter 2 by-hand pass on RoomCore stays the user's.

## Numbers

RoomCore beside CEF. CEF: Chapter 2's tour (run 2, light / dark, visible window, frontmost, load 4–10). RoomCore phase: the Chapter 3 phase's own standalone measurement (component build unless "release"; 60 Hz; window key). RoomCore tour: 3.9-2's exit tour on 155.0.8059.36 (light / dark, no build beside it, load1 7–13 at the quits; 3.9-1's preview under the 155 build's load is in `spike-results.md`).

| Measure | CEF (2.9 tour) | RoomCore, phase | RoomCore, 3.9-2 tour on 155 (light / dark) |
|---|---|---|---|
| Memory, baseline (summed RSS) | 849 / 857 MB | 996 MB (3.3b) | 1,241 / 1,246 MB |
| 10 loaded pages | 3,572 / 3,560 MB | 6,398 MB, 19 renderers (3.3b); **release framework 4,975 MB** (3.3b, embryo `open10`) | 5,565 / 5,429 MB, 17 renderers (tabsmeasure); 4,962 / 4,584 MB (memory's 10 hidden) |
| 30 hidden pages | 7,292 / 7,145 MB | 11,880 MB (3.3b) | 11,720 / 9,888 MB |
| 50 loaded over 5 spaces | 6,495 / 6,509 MB | 10,317 MB (3.3b) | 9,723 / 9,727 MB |
| Tab switch: click → committed, median / p95 | 13.7 / 17.5 and 14.5 / 18.2 ms | 15.41 / 22.33 ms (3.3b) | 15.38 / 22.97 and 15.98 / 23.79 ms (B-53: the p95) |
| Relaunch: load start; selected loaded | 0.82 / 0.83 s; 1.44 / 1.49 s | 2.10 s; 4.08 s (3.3b); 50k state 2.16–2.22 s; 3.92–3.98 s (3.5); **release: first page 0.41 s** (3.1b-2) | 2.08 / 2.21 s; 4.17 / 4.75 s |
| State open on the 50k state | 151–153 ms (3.1a, quick_check) | 156–158 ms (3.5) | **11.9–12.1 ms after schema v6** (3.9-1; the migration launch 252 ms) |
| Palette at 50k rows: first key median; later keys p95 | 18.8 / 17.9; 11.6 / 11.5 ms | 20.5–24.7; 9.2–12.1 ms (3.5) | 21.75 / 21.73; 9.79 / 10.00 ms |
| Palette open: our code; to next frame | 2.7 / 2.5; 6.0 / 5.5 ms | — | 2.23 / 2.71; 3.74 / 4.90 ms |
| Space switch, ⌃digit → first frame, median / p95 | 12.8 / 15.8 and 10.8 / 16.4 ms | — | 14.90 / 20.49 and 15.74 / 20.50 ms |
| Split created → laid out; → next frame | 14.2 / 11.8; 22.9 / 22.3 ms | — | 4.76 / 4.57; 11.45 / 12.68 ms |
| Find, keystroke → match | 15.4 / 14.4 ms median | 6 / 38 ms at 4+ characters; ~410 ms for 1–3 (Chromium's delay) (3.3b) | 19 / 31 ms median, p95 426 ms |
| DevTools ⌥⌘I → front-end loaded | 329 / 340 ms | 331 ms (3.3b) | 331 / 334 ms |
| Peek decision → overlay frame; → first paint | 21.4 / 30.0; 91.7 / 102.2 ms | 22.5; 493 ms (3.3b, B-57) | 22.4 / 21.1; 110 / 469 ms median (p95 525 / 494) |
| Quit with ten pages | 0.35–0.50 / 0.31–0.32 s | 0.22–0.28 s embryo (3.3b); release 0.175 s median of 20 (3.1b-2) | 0.30–0.37 / 0.29–0.36 s (load1 7–13); embryo baseline on 155 0.261–0.280 s |
| Cold launch by a link: event → requested | 598 / 610 ms | — | 287 / 273 ms |
| Running link (open / AppleScript / NSWorkspace) | 22.4 / 22.9 / 22.5 ms | — | 24.4 / 17.9 / 18.6 and 25.5 / 13.6 / 21.1 ms |
| Script round trip (CEF: CDP `Runtime.evaluate`; RoomCore: isolated world) | 0.07 / 0.17 ms | 0.14 ms (3.2b) | 0.15 / 0.25 ms |
| Kill test, 100 kills | 0 failures | 0 (3.7b, v5) | 0 / 0 (on v6) |
| Engine requests (net-log) | 3 hosts (B-19) | 0 over launch + 600 s idle + browse + quit, dev and release (3.1b-2) | 0 / 0 |
| Suggestions on, requests for three queries | 3 (Room's client) | 34 (3.5, Chrome's SearchProvider, B-64) | 34 / 34 |
| Bundle | — (CEF dist 1.2 GB) | Room.app 382 MB release (framework 364), 945 MB component; DMG 176 MiB (3.1b-2) | — |

The component build's cost: on the same ten pages the release framework is 24 % lighter (4,975 vs 6,585 MB) and launches a renderer in 0.02–0.03 s against 1.35 s (3.3b); every RoomCore number here except the release rows is the component build's, with `DCHECK_ALWAYS_ON`. The release-build table on 155 (3.8 task 4, then 3.9-2) is the one memory and switching are judged by.

## CEF caps lifted

Every cap Chapter 2's review listed ("CEF caps hit"), what lifted it on RoomCore and in which phase. The longer list, member by member, is `docs/engine-api.md` "What CEF could not do".

| Cap (Chapter 2) | Backlog | Lifted by | Phase |
|---|---|---|---|
| Cookies and passwords under the mock-keychain key | — | "Room Safe Storage" in the login keychain on team-signed builds (patch 0002); ad-hoc builds keep the mock keychain | 3.1b (signed), checked by hand on the next signed build |
| No extension popups, toolbar or `chrome://extensions` | — | `ProfileExtensions`, Web Store installs through Room's consent sheet, popups as `ExtensionViewHost`s in a native popover | 3.6a, 3.6b |
| No password or address save prompts | — | Chrome's password manager and autofill, Views bubbles anchored on the site button through `RoomToolbarButtonProvider` | 3.7a |
| Docked DevTools only over the Debug port | — | `DevToolsWindow`'s front-end adopted into the pane; no port in a Release build | 3.3b |
| `isAudible` never saw Web Audio stop | — | `OnAudioStateChanged` (both edges; off 282 ms after the oscillator stops) | 3.3a |
| No engine omnibox ranking or history | — | `HistoryService` and `AutocompleteController` behind the palette; the local tables dropped (schema v6) | 3.5, 3.9 |
| Back/forward lost on discard, ⌘W's unload and ⇧⌘T | B-13 | `TabLifecycleUnitExternal` keeps the entries; each entry stores its page's serialised navigation state | 3.3a, 3.7b |
| Discard blind to forms and Picture-in-Picture | B-17 | `discardBlockers` from `DiscardEligibilityPolicy` (forms, edits, PiP, sound, capture) asked by the host's policy | 3.7b |
| The engine's own Google requests | B-19 | network policy (PR #1) plus three `//room` feature defaults: 0 engine requests | 3.1a, 3.1b-2 |
| Certificate interstitial blind to HSTS | B-24 | Chrome's verdict through the SSL error hook (0021) | 3.4a |
| Geolocation grant stored, page reads "prompt" | B-26 | grants in `HostContentSettingsMap`; the remainder is macOS's location authorization for Room (by hand) | 3.4a (partly) |
| Zoom per host caught up late | B-27 | `ZoomController` events per host; per host vs per tab is a Settings question | 3.3a; Chapter 4 decides |
| The downloads list in memory only | B-28 | `DownloadHistory` (5 of 5 restored after a relaunch) | 3.4a |
| Print: app-modal panel, no preview | B-29 | Chrome's print preview (Views) over the window | 3.3b |
| Site panel: permissions and site data only | B-30 | not lifted: Chapter 4 (tracking protection and extensions per site) | — |
| Peek told link from script by the status text | B-33 | `RoomNavigationThrottle` with `WasInitiatedByLinkClick` (0016) | 3.3a |
| A bundled Public Suffix List without IDN | B-34 | `net::registry_controlled_domains` | 3.3a |
| `didConsumeKey` never called | — | the input-event ack | 3.2b |
| CEF behaviours worked around in `EngineCEF` (find's first request, `alert()` blocking a commit, answered prompts reported dismissed, download names lost, effective-value content settings) | — | gone with `EngineCEF`; Chromium's own behaviour behind each member | 3.3b, 3.4a, 3.4b, 3.9 (deleted) |

What remains hybrid (accepted for Chapter 3, PLAN §4 Hybrid UI): Chrome's Views bubbles for autofill, passwords, FedCM, device choosers, print preview, the translate bubble, client certificates, the "ask before HTTP" dialog; Chrome's own dialog for removing an extension from `chrome://extensions`. Not available yet: `Profile.bookmarks` (4.3), side panels (refused), a per-tab freeze (none in M154), the extension-origin device chooser (B-71).

## What surprised us

1. **Chrome restored our tabs behind our back.** The first Room Browsers took part in Chrome's session restore, and the tour found the previous launch's pages reopened as duplicates beside the host's own (3.2a); Room Browsers are omitted from it, and 3.7b then had to give each entry its own serialised back/forward list because `SessionService` records nothing for them.
2. **Hidden pages ran at 63 frames a second.** Nothing called `WasHidden`: every page the host never showed rendered every frame until 3.3a made visibility follow the host. It was the obvious suspect for the switching gap (B-53) and was not the cause.
3. **The hard part came free.** `TabHelpers::AttachTabHelpers` is friend-gated, and attaching them was expected to need a patch; a page joining the Room Browser's tab strip (`tabs::TabModel`) attaches them all by itself (3.3a). Favicons, zoom, lifecycle, find, translate and print followed from one strip insertion.
4. **Seams beat hooks after 3.4a.** The series grew 11 → 22 by one hook per delegate member (3.2–3.4a), then barely moved: 3.4b took seven members through one patch, 3.5, 3.6b and 3.7 needed none (keyed services, user data on the Browser, factories Chrome already exposes, `*ForTesting` seams). It ended at 24.
5. **The official build needed three fixes the component build never asked for** (3.1b-2): libaperitif's install name, `room_core.exports` beside `framework.exports`, and the export-order check reading both; and the 24 GB Mac mini links it (6.80 GiB), so the laptop is not needed for releases.
6. **The Chrome Web Store works in an unbranded build** (3.6a), consent sheet and all; Google's "Switch to Chrome?" banner and a cookie-consent page from this address are the only friction. PLAN §7's Web Store risk retired in a day.
7. **Chrome adds requests by default that the net-log only finds when a feature turns on.** Password leak checks posted once per launch (3.7a, off now); the translate ranker and Autofill server queries at launch (3.1b-2); SearchProvider polling every ~100 ms while typing with suggestions on: 34 requests where Chapter 2's client made 3 (B-64). Each was found by the session's own net-log, which is why every phase ran one.
8. **Rebases cost builds, not patches.** Two rebases: 2 conflicts in 48 patch replays, both context; the work moved into `//room` (five API fixes on the milestone rebase) and into the build, which a DEPS roll makes near-clean even within a milestone (3.8). A power outage cut rebase 1's build in two (21:45, 2026-10-05; siso resumed from its log).
9. **The component build is not the product's weight.** Memory 24 % lower and renderer launch 45× faster on the release framework (3.3b); Peek's 493 ms first paint is mostly the dev renderer's process launch (B-57).
10. **Chrome UI code assumes a `BrowserView`.** Its toast framework CHECKs without one (B-58), the side panel's open path dereferences a null `SidePanelUI` (3.6b), `HttpsOnlyModeTabHelper`'s dialog CHECKs without a modal host (3.3a); and Chrome's lifetime rules bit once more (a profile destroyed with its last Browser, 3.4b). Each was met in `//room` without a patch.
11. **The tour's harness was CEF-shaped in two places it could not see.** Spikes read page globals that RoomCore's isolated-world `executeJavaScript` cannot see (B-55, B-75), and the tour counted helper crashes in `~/Library/Logs/DiagnosticReports`, where RoomCore's Crashpad never writes: renderer DCHECK failures on live sites in the dev build (Blink layout, 1–10 per tour since 3.1a) went unseen until 3.9-1 counted the engine's Crashpad directory (B-76).
12. **Google services are gated in ways a fork cannot see from the code.** Translate needs a Google API key (B-63), password generation needs Sync (B-72), Enhanced Spell Check is Google's service (B-74): each became a decision for the user rather than a task.

## Test tiers

Unit tier (CI, blocking): **465 tests in 12 packages**, all passing with `CI=1` here (3.9-1, after the CEF deletion and schema v6): Model 75, Tabs 62, Engine 58, Chrome 51, UIKitCore 47, Omnibox 43, Sidebar 38, Store 35, Palette 23, Card 14, Integration 10, Design 9 (`EngineRoomCore` and `Infra` have none; Chapter 2 ended at 450, 3.7b's window tier counted 491; 3.9-1 removed the local history's tests with the code: Model −17 +3, Tabs −3 +2, Omnibox −9, Palette −2). CI generates the engine-free spec (`xcodegen/ci.yml`, the Room target with `ROOM_ENGINE=none`) and runs the same 465 with the window suites skipped; 34 runs in Chapter 3 to 2026-10-06 00:09, 32 green, one red (2026-10-05 03:03, 3.2b) and one cancelled; **median 155.5 s** (131–1,084 s, the longest waiting for a runner). The CI spec built and tested locally before 3.9-1's push.

Window tier (local): the Room scheme with `CI` unset, the same 465 with UIKitCore's and Card's `.window` suites live: all pass (2026-10-06, 1280 × 800 display).

Engine tier (local, Chapter 3's addition): the embryo host's baseline (`scripts/roomcore-baseline.sh`: nav assertions, three ten-page quits) after every engine change, and the feature drives (`roomcore-features.sh`); the tour sections on Room.app on RoomCore per phase.

Eyes tier: the phases' captures under `research/screenshots/phase-3.1a` … `phase-3.7b`; the tour's full set per appearance under `build/grand-tour/` (not committed).

The tour (local): 34 steps, 505 checks per appearance, ~24 min each under load (CEF's 18 min idle); since 3.9-1 it also counts the engine's minidumps (B-76).

## Open user items

Every open backlog row owned by the user, and the by-hand list.

| Item | What it needs | Backlog |
|---|---|---|
| The by-hand pass | `research/notes/chapter-3-by-hand.md` (67 numbered items in nine groups, 63 to do and 4 pointers or stale notes) and the Chapter 2 list once more on RoomCore (121 steps) | — |
| The week of exclusive use | Room as the default browser with real accounts, friction daily as "3.9 week" (ROADMAP 3.9 task 4) | — |
| 120 Hz numbers on the laptop | the sidebar scroll, the tab switch, the palette, the space switch at 120 Hz | B-16, B-18, B-20, B-21 |
| Location authorization | allow Room in macOS's Location Services, then the page reads "granted" | B-26 |
| The card's drag band over selectable text | try it with a pointer | B-32 |
| Helper bundle-id suffixes | PLAN §4 Identity amended to Chromium's suffixes in 3.9 (the provisional choice); object if PLAN's should stay | B-46 |
| Disk layout on the Mac mini | what moves to the external SSD; 88 GB free on 2026-10-06 | B-48 |
| The external drive | reformat to APFS when possible | B-10 |
| A translate key | a Google API key, a `//room` override for the element script, or no Translate | B-63 |
| The history archive | whether an archive view (4.1's Library) reads `history-archive.json` | B-66 |
| Extensions' own requests | whether Settings ▸ Extensions says installed extensions make their own requests | B-68 |
| Native messaging hosts | which directories Room reads (1Password's desktop app) | B-69 |
| Password generation | a behaviour hook (outside the patch policy) or none | B-72 |
| Enhanced Spell Check | keep Chrome's item or hide it (Google's service) | B-74 |
| Signing, keychain, Sparkle signature | on 3.9-2's signed release build (`chapter-3-by-hand.md` 3.1 step 3) | — |
| Widevine on a real service | Netflix or Spotify with an account | — |
| The passkey entitlement, the Sentry DSN, the update feed URL | Chapter 2's items, unchanged | — |

## Risks, re-ranked

Against PLAN §7 (re-ranked at the end of Chapter 2). "Implementer" is what Chapter 3 showed; the planner's column is the planner's.

| # (PLAN §7) | Risk | Chapter 3 evidence (implementer) | Proposed | Planner |
|---|---|---|---|---|
| 1 | Rebase and build cost at a 2-week cadence | Two rebases measured (3.8): hand time 5.5 min and ~18 min, 2 conflicts in 48 replays, 5 `//room` API fixes on the milestone; builds 2 h 16 min + 32 min (near-clean, a DEPS roll) and ~4 h 15 min (clean, a clang roll); the official build 4 h 43 min; the series 24 patches, 326 lines. The cost is machine time, about a night per milestone, plus the tour | down in effort, stays #1 by machine time; Stable confirmed by 3.9-2's tour on 155 | |
| 2 | `BrowserWindow` entanglement | 58 real members, 38 stubs, none hit in any tour but `CreateSadTab`; one new pure virtual per milestone so far (`GetAcceleratorProvider`, 155); Chrome UI code that assumes a `BrowserView` failed three times (B-58's toast CHECK, the side panel's null deref, the HTTPS-only dialog CHECK), each met in `//room` without a patch | down, mid-table | |
| 3 | The tour can pass by skipping | Closed by 3.1a's `PageDriver` and checks that require each result line; but two CEF-shaped checks hid things: the isolated-world reads (B-55, B-75) and the crash count that never looked in RoomCore's Crashpad directory (B-76, fixed in 3.9-1) | retire as written; keep "checks shaped by the old engine" as a low note until 3.9-2's tour is green | |
| 4 | Unrequested network calls | Room's code 0 (since 2.8b); the engine 0 over launch, 600 s idle, browse and quit on dev and release (3.1b-2); each new Chrome feature brought a request found by its phase's net-log (leak check, ranker, Autofill queries); with suggestions on Chrome polls (B-64) | down, low; the net-log stays a per-phase step | |
| 5 | Main-thread budget at 120 Hz | Still no 120 Hz measurement (the laptop items); RoomCore's dev-build switching misses 16 ms at p95 by 6–8 ms and now at the median by ~2 % (B-53; CEF 17.5–18.2 p95); the palette's later keys stay inside the bound on Chrome's omnibox | unchanged; the release build and the laptop decide | |
| 6 | Hybrid Views bubbles look like Chrome | Every bubble anchored on the site button or the field, 320 pt wide; the translate bubble sat 23 pt off (3.7b) | unchanged (Chapter 5) | |
| 7 | Widevine licensed playback on a real service | Demand-only Widevine verified with a public test stream (3.1b); a real service is still by hand | unchanged | |
| 8 | Shutdown watchdog | Not reproduced on the release build with the machine quiet (0 in 89 processes); 11 of 12 concurrent quits on the component build under build load (3.1b); patch 0010 parked | unchanged, low | |
| 9 | Memory | Ten pages: CEF 3.6 GB; RoomCore component 6.4 GB (19 renderers), release 5.0 GB (3.3b); host-driven discarding with Chromium's blockers (3.7b); the release table on 155 is still to come | unchanged; up if the 155 release table stays ~1.4 GB above CEF | |
| 10 | Keychain and signing identity | Release build signed in 9 s, notarized in 61 s (3.1b-2); the keychain prompt on the signed copy is by hand on the next signed build | down | |
| 11 | Passkey entitlement lead time | Unchanged (the user files the request) | unchanged | |
| 12 | Sparkle update size | Release DMG 176 MiB (184,497,802 bytes), component 339 MB (3.1b-2); the EdDSA signature by hand | down, retire once signed | |
| 13 | Crashpad → Sentry | RoomCore's Crashpad writes minidumps under the engine directory with no upload URL (3.1a); the tour now counts them (B-76); Sentry stays app-process only behind its opt-in with no DSN | unchanged | |
| 14 | Launch time grows with the state | `quick_check` at launch (3.1a); history left `Room.sqlite` (3.5 recording, 3.9 schema v6): open time on the migrated 50k state 11.9–12.1 ms (157 ms in 3.5 on the same state; the migration launch 252 ms; the file 41.8 MB → 213 KB after the once-only vacuum) | retire | |
| — | CEF caps as the daily-driver limit; the single-maintainer dependency on CEF | CEF deleted (3.9-1) | retire | |
| new | **Dev-build renderer DCHECKs on live sites.** Blink layout DCHECKs (`layout_object.h:518`, `inline_node.cc:2330`, `document.cc:2621`) kill a renderer 1–10 times per tour on the component build with `DCHECK_ALWAYS_ON`; the release build has no DCHECKs, so the product does not crash there, but every dev-build number and by-hand pass meets them (B-76) | add, low: a dev-build condition; watch on 155 | |

## Planner's closing

*Left to the planner.*
