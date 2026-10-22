# Chapter 5 review — polish

Date: 2026-10-22. **Draft** by the implementer (Phase 5.9, one session on the Mac mini, worktree `phase-5.9`), written while the full tour ran on the Debug app over the 156 release framework and on the dev app; section 2 is filled in from those runs. The planner's columns and closing are left empty. Phases 5.0–5.8 are recorded in `docs/progress.md` (checklists and dated entries); numbers come from `research/notes/spike-results.md` ("Phase 5.0a" … "Phase 5.8 — 5.8a", the table v3 under "Phase 5.4 — 5.4b"), build costs from `research/notes/build-log.md`, the loop's own decisions from `research/notes/chapter-5-loop.md`, the user's steps from `research/notes/chapter-5-by-hand.md`, the taste items from `research/notes/ui-iteration.md`. The chapter ran on two machines: 5.0–5.4a on the M1 Max laptop (60 Hz XDR), 5.4b–5.9 on the Mac mini M4 (the Screen Sharing virtual display, 1920 × 1080 at 60 Hz), with the laptop building the engines from 5.4b on.

## 1. End state against the ROADMAP

Chapter 5's end state: "It feels like Dia or better. Spec §I is the checklist; the hybrid bubbles the week disliked are native; the numbers table has no open row; and the taste items the sessions cannot judge are a list with screenshots for the UI and UX iteration that follows."

| Part of the end state (ROADMAP Chapter 5) | Status | Evidence | Open |
|---|---|---|---|
| 5.0 The pass's bugs, the sessions' own checks | done (2026-10-21) | the dev bundle id `app.room.desktop.dev` in every Debug build and wrapper; `scripts/live-check.sh` 0 failures on both builds; B-107, B-108, B-109 fixed and shown by spikes; B-100 65 / 65; every skipped Chapter 4 step a result line (`-RoomSpike skipped`: 32 passed, 8 passed with a click part left, 5 the user's) | B-106 not reproduced; computer use on the session's own process never ran (the `app.room.desktop.dev` grant declined, then several Debug Rooms shared the id): the click checks are on the user's list |
| 5.1 Motion | closed, exit not met | the motion harness (`-RoomSpike motion`): every §I.1 animation at its token value, 0 dropped frames at 60 Hz once running, on both builds; Reduce Motion tables and a test per package; B-111 (one hover and press style), B-114 (no traffic-light pill, the reveal 282–292 ms from ≥ 400) | the 120 Hz run (the user's Phase 5.1 step 1: B-16, B-20, B-21, B-128); B-129 (⌘S still drops 2 frames before its animation) |
| 5.2 Visual audit | done (2026-10-21) | the matrix (17 surfaces × light/dark × active/inactive); `design-audit.sh` 52 → 0 undeclared literals; one control metric (B-110), split as cards (B-113); secondary text over the tints 800 / 800 under 4.5:1 → 0 / 800; the inactive tint that never applied; B-37; Chromium's name out of Chrome's pages without a patch (B-103: 48 → 0 visible) | B-132 (contrast over real wallpapers needs a display capture), B-130 (`chrome://version`'s wordmark: a patch), taste |
| 5.3 Accessibility | done (2026-10-21) | the in-process audit 14 findings → 0 over 40 states (and at large text); Tab order sidebar → header → card → footer with rings; Sidebar text in three sizes (0 of 48 clipped); Increase Contrast, Reduce Transparency, Differentiate Without Colour injected and followed live | VoiceOver, the real keyboard and display switches (the user's steps 1–3) |
| 5.4 Performance and memory | open | B-53's one host fix (p95 16.0–17.6 → 14.2–16.4 ms on the laptop's release framework); the relaunch broken down (`LaunchMarks`); B-85 (the import's stall 1,045 → 105–126 ms); B-80 closed; no host leak; energy by `proc_pid_rusage`; 5.4b's engine step (B-139, B-127, B-87, B-140, B-58); the table v3 on 156 (section 3); B-152 found and fixed | B-56 (discarded pages' renderers alive at 10 s: `54b-2`'s second half not built yet), B-53 on the Mac mini (18.1–18.5 ms p95), B-153 (the suggestions row), the 120 Hz column |
| 5.5 Input | open (the user's hardware) | B-65, B-102; IME by marked text in the palette, rename and page; mouse buttons 4 and 5 anywhere; Chrome's `HistorySwiper` reaches the window; the drop matrix 27 / 27 on both builds; B-96, B-97; haptics only on alignment | a real input method, the swipe on a trackpad, the gesture script, real drags between apps (the user's steps 1–4) |
| 5.6 Details | done (2026-10-22) | §I.3 titles with the unread dot, Change Icon…, B-94, B-116, B-117, B-118; the card's drag band gone (B-32), the hint, the Dock and Window menus, several incognito windows (B-98); Chrome's toasts bridged (B-58: Copy Link Address says "Copied Link") | B-150 (⌘M with the sidebar hidden), B-151 (Services from a page's selection), B-119 measured and not shipped |
| 5.7 Settings and onboarding | done (2026-10-21) | every pane scrolls and fits 1024 × 543; each setting once (the audit table); Privacy's lists in sheets; Archive's Never as default with a migration; the right-hand sidebar gone; the space window (B-122); onboarding (B-121) | the click paths by pointer; taste |
| 5.8 Native bubbles | done (2026-10-22, 5.8e in the main checkout) | 5.8a's host side (the password popover, four `WebContentsUIDelegate` members, FakeEngine) and the engine half (`b1a9445`: the page's `//room` `TabDialogs` offers Chrome's save and update bubbles to the host, Chrome's `SaveUpdateBubbleController` behind the answers); the 3.7a fixtures pass through the popover on release and dev (save, update, Not Now, Never, fill after a relaunch); PLAN §4's Hybrid UI row rewritten | the suggestion popup needs a patch (B-155); the popover's taste (5.8 step 1) |
| 5.9 Integration, release, review, the iteration list | this session | the full tour on both builds on 156, light and dark, every failure attributed (section 2); the reruns on the shipping engine `80b2b9e`; the rebase's dev baseline; this review; the iteration list (`ui-iteration.md`, 70 rows) | the release is the planner's (build 23's DMG); B-156, B-127 |
| "It feels like Dia or better" | not judged by any session | the review sheets and the iteration list (70 rows) | the user's pass over `ui-iteration.md` before Chapter 6 |
| "The numbers table has no open row" | **not met** | the table v3 at 60 Hz on 156 (section 3) | B-53, B-56, B-153; the 120 Hz column |

## 2. The grand tour

`scripts/grand-tour.sh` runs **47 steps** per appearance on one state, as at Chapter 4's end (the chapter added no tour step; its checks live in the phases' own spikes and wrappers, run standalone). 5.9 ran it once per build and appearance on 156 (`spike-results.md` "Phase 5.9" has every table): the Debug app over the release framework `f05f3d6` and the dev app over 156's first `out/dev` of `f05f3d6` (landed 01:40; the planner asked for it, so the 155 dev engine of `c5a4032` was not toured). Conditions: the Mac mini, the Screen Sharing virtual display 1920 × 1080 at 60 Hz, load1 10.2 / 3.2 at the start, 5.8's and the planner's Debug Rooms on screen during the release tour (none during the dev tour). The tour's wrappers that capture from the shell ran with a no-op `screencapture` (the machine rule; B-157).

| Run | Wall time | Light | Dark | Minidumps per appearance |
|---|---|---|---|---|
| Release framework `f05f3d6` (`20261022-014907`) | 47.6 min (25.1 + 22.5) | **893 / 20** of 913 | **900 / 13** of 913 | `chrome26b`'s intended crash; `media`'s host crash (harness) |
| Dev `f05f3d6` (`20261022-023645`, `-030410`) | 54.5 min (27.4 + 27.1) | **901 / 16** of 917 | **901 / 16** of 917 | 11 Blink DCHECKs (B-76) + the two above |
| Chapter 4's exit (4.9, release on 155) | 45.9 min | 899 / 5 of 904 | 897 / 7 of 904 | 0 + the intended |

| Step | Cause | Attribution | After |
|---|---|---|---|
| `diaframe` (all four) | the check expected Dia's 6 pt inset; the card is 8 pt in since `beea283` | harness, fixed (`a1055b2`) | passes |
| `spacecaptures` (all four) | seven captures expected; B-122 took the space form's two out of the sidebar | harness, fixed (`3e06182`) | passes |
| `media` ×4 and a "no crash report" in the next step (all four) | the spike took a menu-bar status item's window for Chrome's PiP overlay and its capture asserted | harness, fixed (`623b708`); the window is B-156 | 32 / 32 on `80b2b9e` (release, dev) |
| `incognito`'s save offer (the `80b2b9e` reruns) | 5.8's engine half shows the host's popover, the spike looked for a Views bubble | harness, fixed (`530611e`) | 20 / 20 release dark |
| `incognito`'s Open Link in Incognito Window (release dark, dev light), `sidebar500` (release light), `documents`' screenshot drag (release light), `extpopup`'s focus loss (dev dark; release dark rerun) | another app's or Room's window key, another Room on screen | run condition | each passed on its rerun or in the other runs |
| `palette2`'s chip (release) | the official framework has no spike hook | known, B-82 (by design) | — |
| `suggeston` ×2 (all four) | the shared state's suggestions off | known, B-153 | — |
| `tabs` (all four) | a discarded page's renderer stays (15 → 16; 16 → 16 and 11 → 12 on `80b2b9e`) | known, B-56 | — |
| `tabsmeasure` (all four) | switching p95 18.3–19.9 ms release, 21.2–22.3 dev | known, B-53 | — |
| dev minidumps | Blink DCHECKs on live sites (`memory`, `open10`, `quittiming`, `palette`, `windows`) | known condition, B-76 | 0 on release |
| `incognito`'s extension action while allowed (dev light rerun only) | the regular window's action gone after "disallowed again" | unattributed: passed in all four full-tour runs | — |

**Green for what Chapter 5 owns, with two rows open.** No product line failed that a one-liner fixes; every failure is a harness fault this session fixed and reran, a run condition with a passing rerun, or a known row (B-53, B-56, B-76, B-82, B-153). The tour found two things that are not failures of a check: **B-156**, a menu-bar status item's window in Room's process on every 156 build (Glic disabled in `80b2b9e` did not remove it; its owner is unknown), and **B-127 not fixed** (IconServices' fault under `-[NSWorkspace setIcon:forFile:]` in `layoutmodes` in all four runs, `~/Applications/Chromium Apps.localized` rewritten from a throwaway state; none in the one `80b2b9e` rerun). B-154 closed (the rerun passed its three checks; `chrome26b` passed in all four runs). B-152's fix holds in the tour (`spaces`: 0 of 60 missed, all four runs).

## 3. Numbers: the table v3

From `spike-results.md` "Phase 5.4 — 5.4b" (2026-10-22, the Mac mini, the Debug app over the release framework on 156.0.8078.48, light, window key and visible, load1 2.0–4.4 for the table's runs; B-152's row from the `fix-b152` worktree, load1 4.2–10.9). The 120 Hz column is the user's (Phase 5.1 step 1, extended by 5.4a); this Mac has no 120 Hz panel. Chapter 3's column is 3.9-2's release on 155 or its tour.

| Measure | Chapter 3 (3.9-2, 155) | **v3: release on 156, 60 Hz, Mac mini** | 120 Hz (the user's) | Bound, owner |
|---|---|---|---|---|
| Memory, baseline (summed RSS) | 559 MB | 791 MB, 4 renderers (`30a60f7`) | | recorded |
| 10 loaded pages | 4,801 MB, 19 renderers | **4,661 MB, 16 renderers** (`30a60f7`); 5,126 / 5,127 MB, 18 (`f05f3d6`); 10 hidden 4,905 MB, 20 | | B-56 |
| 30 hidden pages | 11,720 MB (tour) | **9,443 MB, 41 renderers** | | recorded |
| 50 loaded over 5 spaces | 9,723 MB (tour) | **4,959–4,992 MB, 52 renderers** | | recorded |
| Tab switch, click → committed, median / p95 | 12.88 / 20.87 ms | **15.40 / 18.08** (`30a60f7`); 15.81 / 18.44 and 15.15 / 18.50 ms (`f05f3d6`) | | 16 ms p95: 13–16 % over, **a row (B-53)**; the laptop's 14.2–16.4 ms (5.4a) |
| Relaunch: load start; selected loaded | 0.56 s; 1.33 s | 0.70 s; **0.77 s** (`30a60f7`); 1.02–1.27 s (`f05f3d6`, a different selected site per run) | | recorded |
| Palette at 50k rows: first key median; later keys p95 | 21.75; 9.79 ms | **22.05; 12.59 ms** (suggestions off) | | later keys under 16 ms: passed |
| Palette open: our code; to next frame | 2.23; 3.74 ms | **3.29; 6.41 ms** | | recorded |
| Space switch, ⌃digit → first frame, median / p95 | 14.90 / 20.49 ms | **18.00 / 32.14 ms** (0 of 60 missed after B-152's fix; dev on 155 17.80 / 31.25) | | recorded (B-21) |
| Split created → laid out; → next frame | 4.76; 11.45 ms | **17.80; 28.76 ms** | | recorded |
| Find, keystroke → match, median; p95 | 19–31 ms; 426 ms | **11.40 ms; 413 ms** (Chromium's delay for 1–3 characters) | | recorded |
| DevTools ⌥⌘I → front-end loaded | 331–334 ms | **330 ms** | | recorded |
| Peek decision → overlay frame; → first paint | 22.4; 110 ms | **28.7; 105.8 ms** | | recorded |
| Quit with ten pages | 0.24–0.30 s | **0.26 / 0.35 / 0.53 s**, 0 helpers left | | recorded |
| Cold launch by a link, event → requested | 287 ms | **293 ms** | | recorded |
| Running link (open / AppleScript / NSWorkspace) | 24.4 / 17.9 / 18.6 ms | **26.7 / 28.4 / 24.9 ms** | | recorded |
| Script round trip (isolated world) | 0.15 ms | **0.12 ms**, p95 0.48 | | recorded |
| Kill test, 100 kills | 0 / 0 | **0 failures** (commit median 12.4, p95 16.7 ms) | | passed |
| Engine requests (net-log) | 0 | **0** | | passed |
| Suggestions on, requests for three queries | 34 | **not measured** (the tour's shared state has suggestions off) | | B-153 |
| Bundle | Room.app 386 MB, DMG 178 MiB | **Room.app 425 MB** (framework 378 MB) | | recorded |

What the rows say: on 156 the per-page memory fell (ten loaded pages 4.7 GB against 4.8, fifty over five spaces 5.0 GB against 9.7, thirty hidden 9.4 against 11.7) while the baseline rose (791 against 559 MB, the tour's state rather than a fresh one); switching is 2–3 ms over its bound on this Mac's virtual display and under it on the laptop's, the gap 5.4a profiled to Chromium's view swap and AppKit's display cycle; the space switch and the split's layout got slower than 3.9-2's (18 against 15 ms, 18 against 5 ms) and are recorded, not bounded; quit, link handling, DevTools and Peek are where Chapter 3 left them; the engine makes no request.

Other Chapter 5 numbers (each phase's own, `spike-results.md`): the reveal band → in place 282–292 ms (5.1b, from ≥ 400); the first palette open 17.0 → 8.3–9.9 ms of main thread and the first ⌃Tab 29.6 → 8.0–11.1 ms (5.4a, B-129); the relaunch's engine start 348 ms, 56 % of it Chrome's unused startup profile and the managed-device check (5.4a, B-140: 156 moved the cost, saved nothing); the import of 5,000 bookmarks and 50,000 URLs' longest stall 1,045 → 105–126 ms (B-85); energy, ten loaded pages idle 600 s: 5.19 % of a core and 19.7 mW, nine discarded 0.24 % and 0.7 mW (5.4a); the 500-entry scroll with overlays 0 late frames of 1,440 (5.4a), at large text 0–1 (5.3b); Chrome's startup signal on 156 3.4–4.0 s after launch by itself (B-87: it was the 3-minute failsafe on 155); a shown page's capture 15–16 ms, off screen none (B-119).

## 4. What Chapter 5 built, in size

**Engine.** Four engine steps and one rebase, no new patch (the series 25 throughout: 0026 and 0027 are the blocker's, B-30, from before the chapter): 5.0a B-107's activation member (`981429c`, out/dev 38 s, the laptop's first official incremental 250 s); 5.2b B-103's branding (`c5a4032`, `//room/branding`, 608 strings overridden at startup in about 3 ms, out/dev 19 s of build); the rebase 155.0.8059.36 → 156.0.8078.48 (the planner's, on the laptop: one conflicting hunk in 25 patches, 84 changed lines in five `//room` files, one of Chapter 4's twelve members changed by 4 lines; the official build about 3 h 10 min there; `build-log.md`); 5.4b's step (`e0ad4ee`, `f05f3d6`, `e96c4ba`: B-139, B-127, B-56's check, B-87, B-140, B-58's toast controller; the release incremental 509 s of build on the laptop, out/dev 11 s); 5.8a's engine half (`b1a9445`: the password bubbles offered through `TabDialogs`). `Engine/roomcore/room` +1,040 / −61 lines over the chapter (rebase fixes included); no new exported class, so B-77's export order never moved. The engines came from the laptop through `/Volumes/JL4/laptop-engines/requests/` from 5.4b on: the first request waited 68 min for the laptop's session to answer; 156's first `out/dev` landed at 01:40 on 2026-10-22, and 5.9's baseline on it passed on its rerun (quits 0.30–0.35 s, 0 helpers; `build-log.md` "Rebase … the verify on the Mac mini").

**The app.** `App/` +8,933 / −743 and `Packages/` +7,005 / −1,277 lines since 5.0a's first commit (`023919b^..HEAD`), of which the DEBUG spikes in `App/Sources/Debug` +7,078: the chapter's harness is mostly spikes (motion, matrix, contrast, a11y, keyboard, input, drops, details, settings, spacewindow, onboarding, passwords, skipped steps, live sites); `scripts/` +785 / −61. New packages: none; new Design types: `ControlFeedback`, `ControlMetrics`, `IconStyle`, `Hairline`, `TextScale`, `DisplayOptions`, `AccessibilityAudit`, `KeyboardAccess`, `FocusRing`, `Motion.preferences`. Schema unchanged except Settings fields (Archive's Never with `Settings.revision` 1, the text size, grey buttons, the hint).

**Tests.** The unit tier 647 at 4.8b → **740** at B-152's CI spec run (2026-10-22), 0 failed; window suites added: `AccessibilityAuditTests` (a new target in Palette's package). One test per spec rule or real bug (B-37, B-152, B-108, B-109, the migration, Reduce Motion tables, `TextScale`, `DisplayOptions`, onboarding's skip rules, the password answers).

**DMGs.** Builds 15–19 on the laptop (Phases 5.0–5.4a), 20 and 21 the first published release (`updates.room.app`, Cloudflare R2), 22 the Mac mini's first DMG (Phases 5.5, 5.7, 5.6a; not yet published at this draft). The planner builds the next one after this session.

## 5. The review sheets (index)

Every sheet is a contact sheet of in-process captures of Room's own windows with the token values printed on it, for the user; the sessions do not judge them. The marks go into `ui-iteration.md`'s "Your call" column. Paths under `research/screenshots/`.

| Phase | Sheets | Iteration rows |
|---|---|---|
| 5.1b | `phase-5.1/phase-5.1b-controls.png` (each control at rest, hovered, pressed, pressed under Reduce Motion; light and dark), `phase-5.1/phase-5.1b-reveal.png` (the reveal at 0–100 % and its fade) | T4, T5, M1, M2 |
| 5.2a | `phase-5.2/phase-5.2-{footer,rows,split,extensions,header}.png` with their `-before` sheets; `phase-5.2-{palette,peek,toasts,downloads,sitepanel,prompts,library,settings,incognito}.png` | S1, S2, S11, T1–T3, C1, P1, O1, O6–O8, O10 |
| 5.2b | `phase-5.2/phase-5.2-{themes,rows,menus,split,spaceform}.png` with `-5.2b-before` sheets, `phase-5.2-icon.png`, `phase-5.2-branding-light-before.png` → `phase-5.2-branding-{light,dark}.png` | S3–S5, T6, C4, ST5, W3 |
| 5.3a | `phase-5.3/phase-5.3a-focus-{address-field,back,outline,space-icon}.png` | A8 |
| 5.3b | `phase-5.3/phase-5.3-{rows,header,palette,toasts}-{modes,sizes}.png` | A1–A7 |
| 5.4a | `phase-5.4/phase-5.4a-500-overlays-release.png` (evidence only) | — |
| 5.5b | `phase-5.5/phase-5.5b-*.png` (single captures: the insertion line, the split snap, the overflow, the pill, the sublabels) | M7 |
| 5.6a | `phase-5.6/phase-5.6a-details-{light,dark}.png` (14 captures) | S6–S10, C2, O9 |
| 5.6b | `phase-5.6/phase-5.6b-details-{light,dark}.png` (5 captures) | S13, C3, O4, O5 |
| 5.7a | `phase-5.7/phase-5.7-settings.png`, `phase-5.7-settingssheets.png` | ST1–ST4 |
| 5.7b | `phase-5.7/phase-5.7-spaceform.png`, `phase-5.7-onboarding.png` (before: `phase-5.2/phase-5.2-spaceform.png`, `phase-2.8b/phase-2.8b-firstrun-*.png`) | W1, W2, W4–W8 |
| 5.8a | `phase-5.8/phase-5.8a-passwords-{light,dark}.png` and `phase-5.8a-password-{save,update,saved-toast,save-sidebar-hidden,manager-tab}-*.png` | PW1–PW4 |
| 5.9 | none new: the tour's in-process captures stay under `build/grand-tour/` (not committed; its shell captures were a no-op, section 2) | O11, PW5, PW6 (5.4b's and 5.8's, added by 5.9); the tour added no taste row |

## 6. The bubbles: native and not

From 5.8a's and 5.8e's log entries and PLAN §4's Hybrid UI row as 5.8e rewrote it (merged into main after this branch was cut; the merged text is authoritative).

| Surface | Native (Room draws it) or Chrome's Views | Since | Why |
|---|---|---|---|
| JavaScript dialogs, beforeunload, permissions, the context menu, downloads, HTTP auth, certificate errors, the file chooser, external protocols, the hung page | native | 2.6, 3.4 | the delegate surfaces, never Views |
| Chrome's confirmation toasts (link, image, video frame, link to highlight copied) | native | 5.4b (B-58) | `RoomToastController` in Chrome's `ToastController` slot; Room's toast |
| The password save and update offers, the saved confirmation | native | 5.8 (host `e13fd73`, engine `b1a9445`) | the week named this bubble alone; a popover on the site button, reached through the page's `//room` `TabDialogs` (the seam `ManagePasswordsUIController` already shows its bubble through) with Chrome's `SaveUpdateBubbleController` behind it, so the blocklist, dismissal counts and update semantics stay Chrome's; no patch; the 3.7a fixtures pass through it on release and dev (5.8e). Shipping from the engine of `b1a9445` on (`80b2b9e` adds Glic off) |
| Password and address suggestion popups | Views | — | the only seam is `AutofillPopupView::Create`, a free factory in Views code: a host list needs a patch, which Chapter 5's rule does not allow (5.8b's bounded attempt; B-155) |
| Address and card save bubbles | Views | — | the week did not name them (the user, 2026-10-18) |
| The manage-passwords bubble from a user action, generation, leak, move and post-save bubbles | Views | — | rare, or unreachable without Sync (B-72) |
| FedCM, device choosers, client certificates | Views | — | the week did not ask (B-60, B-71) |
| Print preview | Views | — | Chrome's preview is the feature (B-29); its keyboard path works (4.7b) |
| Translate | absent | — | no Google API key (B-63), stated in Settings |

## 7. What surprised us

1. **A menu glyph fix broke four shortcuts for a day.** Drawing Focus Pane as ⌃⇧1–⌃⇧4 (B-37, 5.2b) made AppKit match those disabled items to ⌃1–⌃4 before the Spaces menu, so ⌃digit switched no space outside a split from 2026-10-21 to 2026-10-22 (B-152). The unit tier reproduced it in one test once a spike's 59-of-60 misses pointed at the host; the spike had been the only thing measuring the key path.
2. **The harness found bugs the eye never had.** The motion harness's read-back found Core Animation's implicit 0.25 s animations on plain sublayers, a ⌃Tab fade that never ran, and a 40 ms re-parenting at the start of the reveal (5.1); the contrast probes found that the inactive window's tint had never reached its layer since 2.5 (5.2b); the modes sheet found an unloaded title keeping its old appearance after a light/dark switch (5.3b); the clipping read-back found the palette a point short at two text sizes (5.3b).
3. **Self-verification moved the work into spikes, and computer use never ran.** The user's 2026-10-21 rule put every check on the sessions; the `app.room.desktop.dev` grant was declined that night, and on the Mac mini several sessions' Debug Rooms shared the id, so no click could be kept to one process. The spikes drove menu items, sheets and drags through their own code (`performActionForItem`, in-process `NSDraggingInfo`, the outline's validate and accept); what only a pointer, a real key, a panel or the Dock can show stayed on the user's list (about 40 click parts across the phases). The DEBUG spikes are now 7,078 of the chapter's 15,938 added app lines.
4. **Shell captures and print preview were the two dangerous defaults.** A display-capture helper raised macOS's screen-capture bypass dialog (5.2b), and Chrome's print preview printed three real pages on the laptop's default printer (5.0b, B-126). Both became prompt rules for every later session; the tour's own wrappers still call `screencapture` from the shell (`chrome-surfaces.sh`, `app-integration.sh`, `layout-modes.sh`, `spaces-capture.sh`), which 5.9 found after its first `chrome26b` attempt had taken 16 window captures and then answered with a no-op on its `PATH` (B-157).
5. **156 made B-87 disappear.** Chrome's startup-complete signal, which Room never sent on 155 (best-effort work held 177 s), arrives by itself 3.4–4.0 s after launch on 156: the rebase fixed a Chapter 4 row the engine step was written for.
6. **A discarded page's renderer is held by a second view, not by Room.** B-56's check found every discarded page's process still has an active view after its WebContents goes, so Chrome's own `FastShutdownIfPossible` refuses it (5.4b); the owner is `54b-2`'s question, unbuilt at this draft.
7. **The double-click that zoomed the window was AppKit's titlebar, not the drag band.** B-32's removal alone would not have fixed it: with the sidebar hidden the page lies under the 52 pt titlebar, and AppKit ran its double-click action over the engine's view (5.6b).
8. **The parallel night worked, with seams.** From 5.5a on, sessions ran in worktrees beside each other on the Mac mini and the laptop built the engines; the cost was the shared test-server ports (sessions ran tour steps standalone, 5.7a and later), Debug Rooms taking each other's key window (reruns attributed as run conditions), backlog numbers that collided (B-142 to B-151) and two Release-only compile failures that the Debug-only CI spec missed (build 22: the Release compile is now a rule before a push).
9. **The engine member a host chooses is a `Bool`.** Chrome cannot tell whether a Swift protocol default ran, so "suppress Chrome's bubble for a host that implements the member" became "for a host that answers `true`" (5.8a); the same shape as `willShowContextMenu`.
10. **The rebase brought a guest into the menu bar, and it is not the one we suspected.** Every 156 build has a menu-bar status item's window in Room's process (B-156), found only because a spike picked it for a PiP window. Chromium's field-trial testing config, which an unbranded build applies, turns on about 40 Glic (Gemini) features including its status icon, so the planner disabled them (`80b2b9e`); the window stayed. Two lessons: a rebase's new defaults need a check of their own (the feature state, the windows a process owns), and the window list, not a hypothesis, is the evidence.

## 8. Test tiers

Unit tier (CI, blocking): **740 tests** at B-152's local CI spec run (`xcodegen/ci.yml`, `CI=1`), from 647 at Chapter 4's end; GitHub CI stayed off all chapter (B-93), so every push ran the spec locally; from build 22 also a Release compile (`swift build -c release` per touched package and the Release app). Window tier (local): UIKitCore 63, Sidebar 53, Palette 27 + 4 (`AccessibilityAuditTests`), Tabs 89 and the others, passing at their phases' runs. Engine tier: the baseline after each engine step that had a dev engine (5.0a, 5.2b) and 5.9's on 156's first `out/dev`. Eyes tier: the review sheets (section 5). The tour: section 2.

## 9. Open user items

The user's list is `chapter-5-by-hand.md` "For the user": per phase at most ten steps (5.0 four, 5.1 three, 5.2 five, 5.3 five, 5.4 one optional, 5.5 four, 5.6 four, 5.7 four, 5.8 one, 5.9's below); in kind: the 120 Hz runs (B-16, B-20, B-21, B-128, B-53 at 120 Hz), VoiceOver and the real accessibility switches, a real input method, a Force Touch trackpad and drags between apps, macOS's prompts for the new id, the user's own browsers, accounts and signed build (import, the keychain, Netflix: B-101), the click checks a grant would let a session run, and taste (`ui-iteration.md`).

## 10. Risks, re-ranked

Against PLAN §7 (re-ranked at Chapter 4's end) and ROADMAP's "Chapter 5 risks". "Implementer" is what Chapter 5 showed; "Proposed" the implementer's ranking; the planner's column is the planner's.

| # (PLAN §7) | Risk | Chapter 5 evidence (implementer) | Proposed | Planner |
|---|---|---|---|---|
| 1 | Rebase cost by surface | One rebase (155 → 156): one conflicting hunk in 25 patches, 84 lines in five `//room` files, one of Chapter 4's twelve members changed (4 lines), about 3 h 10 min of official build on the laptop; the chapter added more surface (B-103's string overrides, B-58's toast controller, the password `TabDialogs` adapter, B-56's check) | #1, lower in cost than feared: the measured rebase was a night's build and an hour's fixes; the next ones are Chapter 6.4's scheduled bumps. New with it: a rebase brings new defaults the patches do not show (156's testing config turned Glic on; B-156's status window), so each rebase gets a feature-state and window-list check | |
| 2 | Memory | Ten loaded pages 4.7–5.1 GB, fifty over five spaces 5.0 GB (from 9.7), thirty hidden 9.4 GB (from 11.7) on 156; B-56 named (a second active view holds the process), not fixed | #2, unchanged until `54b-2` | |
| 3 | Main-thread budget | B-53 p95 14.2–16.4 ms on the laptop, 18.1–18.5 on the Mac mini's virtual display (the display path); the triggers before animations (B-129) mostly prewarmed; the space switch and the split's layout slower than 3.9-2 | #3, unchanged; the 120 Hz run decides how much is left | |
| 4 | The specs run ahead of the user's use | The user's pass on build 14 and ten days of notes did arrive (B-101 to B-122) and reshaped the chapter (5.0, 5.7); the taste of every phase is still unjudged (70 iteration rows, about 40 click parts) | #4, unchanged in kind: the iteration list is the gate before Chapter 6 | |
| 5 | Hybrid Views bubbles | The password bubble native without a patch (`TabDialogs`); the suggestion popup needs a patch (`AutofillPopupView::Create`) | #6 (one down): what the week disliked is native or waits on one framework build; the popup is a patch decision for the user | |
| new | **Self-verification's blind spots** | No computer-use check ran in the chapter; pointer, Dock, panel and drag paths are proved through their code, not their events; two regressions reached a DMG between a change and the next measurement (B-152 from 5.2b to 5.4b, the Release-only compile failures of build 22) | **#5, new**: a grant on the dev id (and one Debug Room per machine at a time) or the user's click pass; the tour's key and menu steps run on every DMG | |
| 6 | Chrome's lifetime rules | None new in Chapter 5's engine steps; 156's API renames were compile errors, not behaviour | #7 | |
| 7 | Dev-build DCHECKs on live sites | See section 2's minidump column | #8 | |
| 8 | Unrequested network calls | 0 engine requests on 156; two spike-made requests (a Google suggest, a Google search) before the suggestions-off and no-Return rules; B-153 leaves the shared state's suggestions off | #9 | |
| 9 | Widevine on a real service | Unchanged (B-101: VMP signing) | #10 | |
| 10 | Keychain, signing, Apple's queue | Builds 15–22 notarized in 63–82 s each; the publish chain to R2 in place (builds 20, 21) | #11 | |
| 11 | Passkey entitlement | Unchanged | #12 | |
| 12 | Sparkle update size | The Release app 425 MB on 156 (386 on 155); DMG about 208 MB (build 15) | #13 | |
| 13 | Crash collector | Unchanged (Chapter 6.3) | #14 | |
| 14 | Shutdown watchdog | Quits 0.26–0.53 s on 156, 0 helpers | #15, low | |
| 15 | The machine's automation limits | Grew: a virtual display without 120 Hz, no printer guard by default, out-of-process panels, the shared dev id across sessions | merged into the new #5 | |
| (Ch. 5 risk 3) | Native bubbles over changing Chrome code | One adapter (`TabDialogs`), no patch | folded into #1's surface | |

## 11. Planner's closing

(The planner's.)
