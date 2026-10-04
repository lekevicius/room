# Chapter 2 review — The sidebar browser

Date: 2026-10-04. Drafted by the implementer (Phase 2.9 task 3), the planner's columns and closing section added the same day; the Chapter 3 spec is `ROADMAP.md` Chapter 3. The user's by-hand pass (`chapter-2-by-hand.md`) is still to come: its friction goes into `docs/backlog.md` as "2.9 by-hand" and is triaged at the 3.9 week, not appended here. Phases 2.1–2.8 are done (reviews in `docs/progress.md`). Numbers come from `spike-results.md`; the grand tour's are new measurements (Phase 2.9, same file, "Phase 2.9 — grand tour").

## End state against the ROADMAP

Chapter 2's end state: "Room is usable for light browsing. All Arc/Zen interaction decisions are implemented and felt; the only complaints are the known CEF caps."

| Part of the end state (ROADMAP chapter table and overview) | Status | Evidence | Open |
|---|---|---|---|
| Model and store: one database, crash-safe, the only writers | done (2.1) | 100 random `kill -9`s reopen intact at the last committed generation, again in the tour (0 failures, 42 kills mid-transaction rolled back) | B-42: the open-time integrity check grows with history |
| Sidebar tree: essentials, pinned with folders, Today, every §A.2–A.9 interaction | done (2.2) | every §A bullet done or placed in a later phase (`progress.md` checklist); captures in every row state | B-16 (120 Hz scroll), drag-out to a new window (4.8) |
| Pinned/Today entries as real pages, lifecycle, ⌘W/⇧⌘T/MRU, switching | done (2.3) | `tabs` and `tabs-measure` in the tour; relaunch loads only the selection | B-41 (visible-window switch p95), B-13/B-17 (CEF) |
| Palette: ⌘T/⌘L, history, commands, site search, suggestions with an off switch | done (2.4, rows on AppKit in 2.6a) | `palette`, `palette2`, `palettemeasure` and both suggestion checks through a logging proxy in the tour | B-20 (120 Hz); engine ranking is 3.5 |
| Spaces with their own lists, look and profile | done (2.5) | `spaces`, `spacecaptures`, `cookies` in the tour; 0 lists loaded during 60 switches | B-21 (120 Hz), B-22 (profile rename), B-23 |
| Downloads, dialogs and every other delegate surface | done (2.6) | `chromesurfaces` and `chromesurfaces2`: every recorded delegate member called on CEF except `didConsumeKey` | B-24, B-26 to B-30 (CEF) |
| Split view, hide/reveal, Peek | done (2.7) | `layoutmodes`: hide/reveal, the cluster, Peek's rules, split keys, event isolation | pointer-only §D checks (the by-hand list) |
| A Mac app: the menu bar from one table, Settings, fullscreen, default browser and links, first run, opt-in updates and crash reports | done (2.8) | `appintegration`, `appintegration2`, `netcheck` in the tour; Room's own code made 0 requests | the default-browser dialog and real link clicks (the user); B-19 (engine) |
| Chapter 1 carry-overs (sidebar width, double-click = new tab, the drag-region cluster, fullscreen header on a real Space, ⇧⌘W) | done | 2.1, 2.2b, 2.7a, 2.8a | — |
| "All Arc/Zen interaction decisions implemented and felt" | implemented; **felt** waits for the user's by-hand pass | `chapter-2-by-hand.md` | the pass |
| "The only complaints are the known CEF caps" | to be judged from the pass; the tour found no unknown cap, three spike bugs and seven places where a spike assumed a fresh state | the caps table below | the pass |

New packages as planned (`Model`, `Store`, `Sidebar`, `Palette`, `Omnibox`, `Chrome`) plus `Tabs` (2.3) and `Integration` (2.8b); the Chapter 1 throwaways are gone and the DEBUG `SpikeRunner` stayed, now with 28 spikes (plus the sidebar and window snapshot runners).

## The grand tour

`scripts/grand-tour.sh` (Phase 2.9) runs all 34 steps (every Chapter 1–2 spike, the kill test, the snapshot runners, the net-log check) on one Debug build and one state directory per appearance, with the four test servers started once. Run 2 (light and dark, build 868f996): **37.6 min** wall time, **488 checks passed and 5 failed per appearance**; run 3 after the last fixes (bd98bf9): **36.3 min**, light **490 passed, 1 failed**, dark **489 passed, 2 failed** — the visible-window switch's p95 in both (B-41) and one 29 ms frame in dark's reveal slide (2.7's bound is none dropped; 0 in light and in runs 1–2). Every step, check, number and capture is in `spike-results.md` "Phase 2.9 — grand tour" and the run's `summary.md`.

What the tour found: three spike bugs that also fail alone or on any sidebar with rows (`popups` since 2.3; the `switch` page-visible probe never decoded, so B-18's number never existed; Peek's checks after the reveal check on a sidebar with rows), seven places where a spike assumed a fresh state or left one behind (fixtures, the history fixture, the Work profile, the first-run flag, the suggestions setting three times, Chromium's remembered certificate and permission decisions, the downloads folder), a spike writing into committed captures, and three product findings: launch time grows with history because the database's integrity check runs at every launch (B-42), a certificate exception cannot be revoked from Room (B-43), and visible-window tab switching misses 2.3's p95 bound (B-41). The one that looked like a product bug, Peek not opening after the sidebar's reveal check, was a spike too: on a sidebar with rows the reveal check's clicks over the overlay selected another entry, so the off-site click went to a background page (bisected to fresh state + the demo fixture + reveal + Peek). None blocks Chapter 3 or makes a feature unusable, so none was fixed in the product; the spikes were fixed, the product findings are in the backlog with a phase.

## Numbers

Conditions for every Chapter 2 number unless a row says otherwise: Mac mini M4, 24 GB, Debug build, CEF 154.0.32, one external display at **60 Hz** (no 120 Hz panel on this machine), load average 4–13. The laptop's 120 Hz runs are open user items (below). "Phase" is the phase's own measurement; "Tour" is the same spike run inside the grand tour on the shared state (light / dark).

| Measure | Phase (conditions) | Tour, light / dark (visible window, frontmost, load 4–10) |
|---|---|---|
| Launch: process start → session running, selected page loaded | 2.3: 0.33–0.45 s, 0.48–0.60 s (locked screen, small state) | relaunch on the tour's state (50k history rows): load start 0.82 / 0.83 s, loaded 1.44 / 1.49 s (B-42: the open-time integrity check, 0.35–0.56 s) |
| Launch by a link: event → page requested | 2.8b: 183–205 ms (fresh state) | 598 / 610 ms on the tour's state (B-42) |
| Memory, baseline and 10 loaded pages (summed RSS, double-counts shared pages) | 1.4: 670 MB baseline; 2.3: 4,095–4,215 MB for 10 (50 entries) | 849 / 857 MB; 3,572 / 3,560 MB |
| Memory, 50 loaded pages over 5 spaces | 2.5: 5.9–6.5 GB (51 renderers) | 6,495 / 6,509 MB |
| Memory, 30 hidden pages (1.4 method) | 1.4: 7,921 MB, 27/30 loaded | 7,292 / 7,145 MB, 30/30 |
| Tab switching: click → new page committed in the card, median / p95 | 2.3: 9.4–9.5 / 14.5–15.4 ms (occluded) | 13.7 / 17.5 ms and 14.5 / 18.2 ms; the page visible 4.2 / 3.9 ms after the click (B-41) |
| Palette open: our code; to the next frame, median | 2.4b: 2.3 ms; 6.2 ms (60 Hz, screen sharing) | 2.7 / 2.5 ms; 6.0 / 5.5 ms |
| Palette keystrokes at 50k history rows: local results p95; later keys' turn p95; a query's first key median | 2.6a: 6.5–6.7; 9.6–10.4; 17.9–18.9 ms (7.5 ms on a P core) | 7.9 / 7.9; 11.6 / 11.5; 18.8 / 17.9 ms |
| 500-entry sidebar scroll (programmatic, 60 Hz) | 2.2b: 1 late frame in 1,437; proxy120 steps over 8.33 ms 2–8% | 0 late frames; proxy120 1.7–4.6% of steps over 8.33 ms (120 Hz still B-16) |
| Space switch: ⌃digit → the slide's first frame, median / p95 | 2.5: 10.9 / 17.1 ms (window not key) | 12.8 / 15.8 ms and 10.8 / 16.4 ms; 0 lists loaded in 60 switches |
| Split creation → both panes laid out; → next frame | 2.7b: 12.8–13.5; 21.2–22.0 ms | 14.2 / 11.8; 22.9 / 22.3 ms |
| Find: keystroke → highlighted match, median / p95 | 2.6b: 20.7–21.3 / 23.8–26.5 ms | 15.4 / 26.2 ms and 14.4 / 25.5 ms |
| Downloads: the 6 MB file at 1 MB/s, 1.5 s in | 2.6b: ring 0.24, "1,4 MB of 6 MB — 721 KB/s" | the same (light); 0.16 (dark: the server's pacing). No latency is measured for the fly-in |
| Link ingestion while running: event → page requested (`open` / AppleScript / `NSWorkspace`) | 2.8b: 25.2–27.3 ms | 22.4 / 22.9 / 22.5 ms and 23.1 / 21.9 / 23.1 ms |
| Quit with ten pages | 1.4: 0.54–0.66 s (load 35–40) | 0.35–0.50 / 0.31–0.32 s, 0 helpers left |

## CEF caps hit

Every cap Chapter 2 ran into, where it is recorded and the RoomCore phase that lifts it (`ROADMAP.md` Chapter 3 as written 2026-10-04).

| Cap | Where it showed | Backlog | Lifted in |
|---|---|---|---|
| Cookies and passwords under CEF's mock-keychain key (not a safe daily driver for sensitive accounts) | every build since 1.4 | — (ROADMAP Chapter 2 caps; PLAN §4 Keychain) | 3.1b (signed build, real keychain), used for real in 3.9 |
| No extension action popups, toolbar or `chrome://extensions` | 1.4 extension spike | — (Chapter 2 caps) | 3.6 |
| No password or address save prompts | 1.4 autofill spike | — (Chapter 2 caps) | 3.7a |
| Docked DevTools only over the Debug 127.0.0.1:9339 port | 1.4, 2.6b pane | — (Chapter 2 caps) | 3.3b (front-end `WebContents` in the pane, no port in the product) |
| `isAudible` sees Web Audio start, never stop | 1.4 audio spike, again in the tour | — (Chapter 2 caps) | 3.3a (`OnAudioStateChanged`) |
| No engine omnibox ranking or history; the palette's FTS5 table is ours | 2.4 | — (Chapter 2 caps) | 3.5 (history migrated, local tables dropped in 3.9) |
| Back/forward lost on discard, ⌘W's unload and ⇧⌘T | 2.3 | B-13 | 3.3a (discard keeps entries), 3.7b (session restore) |
| Discard cannot see unsaved forms or Picture-in-Picture | 2.3 | B-17 | 3.7b |
| The engine's own Google requests (six hosts at launch, idle, quit) | 2.4b, 2.8b net-log; again in the tour | B-19 | 3.1b (net-log silence; PR #1's policy took idle traffic 62 → 0) |
| Certificate interstitial cannot tell HSTS hosts, so public hosts cannot be visited | 2.6a | B-24 | 3.4a (`strict_enforcement`) |
| A geolocation grant is stored but the page still reads "prompt" | 2.6a, 2.6b | B-26 | 3.4a (grants persisted, macOS authorization state) |
| Zoom is Chrome's per-host level, other pages catch up only at their next load | 2.6b | B-27 | 3.3a (`ZoomController` events); per-host vs per-tab is a Chapter 4 Settings question |
| The downloads list lives in memory | 2.6b | B-28 | 3.4a (`DownloadHistory`) |
| Print is an app-modal panel, no preview | 2.6b | B-29 | 3.3b (print preview, Views) |
| Site panel has permissions and site data only | 2.6b | B-30 | Chapter 4 |
| Peek tells a link click from script by the status text | 2.7a | B-33 | 3.3a (`NavigationThrottle`) |
| The Public Suffix List is a bundled copy without IDN rules | 2.7a | B-34 | 3.3a (the `NavigationThrottle` uses `net::registry_controlled_domains`; `SiteRules` goes) |
| `didConsumeKey` is never called | 1.2, 2.6b checklist | — (`engine-api.md`) | 3.2b (input-event ack) |
| CEF behaviours with workarounds in `EngineCEF`: find's first request only counts; an `alert()` blocks a navigation's commit on Alloy; answered permission prompts also report "dismissed"; download updates lose the name; content settings answer with effective values | 2.6b | — (`engine-api.md` rows) | 3.3b (find), 3.4a (permissions, downloads), 3.4b (dialogs) |

Not CEF caps but carried with them: B-35 (a page in Peek cannot go fullscreen; 4.2), B-9 (own-window captures miss Chromium's GPU layer; window-server captures need Screen Recording; tooling).

## What surprised us

1. **Where the time went was rarely where we guessed.** The palette's open cost was AppKit's password AutoFill walking all 500 sidebar rows on focus (2.4b); a query's first keystroke is slow because it runs on an efficiency core after idle, not because of SwiftUI (2.6a, PLAN §4 amended); 3 ms of every tab switch was a hidden debug panel re-rendering (2.3); a space's list costs nothing to reload hidden but 65–105 ms on its first display (2.5). Each was found by a profile, none by reading code.
2. **AppKit owns names and keys.** `NSWindow` answers `toggleSidebar:` ahead of the window controller, so View ▸ Hide Sidebar was disabled in every state (2.7b, now an AGENTS rule); shifted key equivalents only match as the shifted character, so ⇧⌘T, ⇧⌘D and ⇧⌘K never fired until 2.3 (and the menu now draws "⌘}", B-37).
3. **CEF's behaviour is not its documentation.** Find's first request only counts, an `alert()` blocks a navigation's commit on Alloy, answered permission prompts also report "dismissed", download updates lose the file name, content settings answer with effective values (2.6b); each has a workaround in `EngineCEF` and a row in `engine-api.md`.
4. **The real engine finds what tests cannot.** Quitting removed every Today tab (CEF's closes looked like `window.close()`, fixed with `isTerminating`), the outline lost its last rows after the window got shorter, the focus ring ignored key state, the switcher's highlight never showed (2.2b–2.3); the kill test found a JSON snapshot two generations behind (2.1).
5. **The engine phones home; Room's code does not.** With every opt-in declined, Room's own code made 0 requests and its process moved 0 bytes, while CEF's network service asked six Google hosts (2.8b, B-19). The rule holds for our code by a check; for the engine it waits for 3.1b.
6. **The CI runner's compiler is older and stricter.** Xcode 26.6 rejected `self` captured in `@Sendable` closures that Xcode 27 accepts (2.7b): `MainActorWeak`, and an AGENTS rule that a red CI for an old compiler's diagnostic is real.
7. **Conditions moved the numbers more than code did.** 2.3 and 2.4a ran with the session locked (an occluded window composites nothing), 2.4b and 2.6a with screen sharing, everything at 60 Hz. The tour's visible-window switch is ~5 ms slower than 2.3's occluded number and misses 2.3's p95 bound (B-41); the page-visible probe B-18 waits on had never measured anything (a decoding bug, fixed in 2.9).
8. **Every spike assumed a fresh state.** Run in sequence on one state directory, five steps broke or measured the wrong thing: fixtures did nothing on a non-empty sidebar, the history fixture skipped a non-empty history, a second fixture made "Work 2", the first-run card never showed again, the suggestions setting was left off by three spikes, and Chromium's remembered certificate and permission answers hid 2.6b's prompts. Each is now a spike fix (`spike-results.md` 2.9); none was a product bug, but each would have made the tour lie on RoomCore.
9. **Chromium remembers a profile's answers.** "Visit … Anyway" on a certificate error and a denied notification prompt survive a relaunch (Chrome keeps certificate decisions for a week); Room's site panel resets permissions but cannot revoke a certificate exception (B-43).

## Test tiers

Unit tier (CI, blocking): **450 tests in 12 packages**, all passing with `CI=1` here and on the runner: Model 86, Engine 57, Tabs 50, UIKitCore 47, Omnibox 45, Chrome 39, Sidebar 38, Store 34, Palette 21, Card 14, Integration 10, Design 9 (`EngineCEF` and `Infra` have none). Per-package `swift test` here: 4–29 s each. CI: the no-engine spec builds and runs the same 450 (window suites skipped by `CI`); 38 green runs since 2026-10-03, **median 99 s** wall time (77–141 s); one red run in Chapter 2 (7d2b59e, Xcode 26.6's region-isolation diagnostic, 2.7b).

Window tier (local): the Room scheme with `CI` unset runs the same 450 with the `.window` suites in UIKitCore and Card live: all pass (2026-10-04, after the tour, on the 1280 × 800 display).

Eyes tier: the phases' captures under `research/screenshots/phase-1.3` … `phase-2.8b` (138 MB committed); the tour writes a full set per appearance under `build/grand-tour/` (not committed).

The tour itself is a fourth, local tier: 34 steps, about 490 checks per appearance, ~19 min each. It is what Chapter 3 runs on `EngineRoomCore` section by section (`--groups`).

## Open user items

| Item | What it needs | Backlog |
|---|---|---|
| 500-entry scroll at 120 Hz | `scripts/sidebar-snapshots.sh 500` and a trackpad fling on the laptop | B-16 |
| Phase 2.3 numbers with the screen unlocked | the tour measured switching and the page's visible time on the Mac mini at 60 Hz (B-18's probe works now); the laptop's 120 Hz run of `scripts/tabs-measure.sh` remains | B-18 |
| Palette at 120 Hz without screen sharing | `scripts/run-spike.sh palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000` on the laptop | B-20 |
| Space switch at 120 Hz | `scripts/run-spike.sh spaces -RoomSidebarFixture spaces500 -ApplePersistenceIgnoreState YES` on the laptop | B-21 |
| Camera, microphone and location | `permissions.html` on the laptop (devices); whether location reads "granted" after Allow | B-26 |
| The Sparkle private key | `generate_keys -x` here, `-f` on the release machine (`docs/setup.md` §5.4) | — |
| The Sentry DSN | a Sentry project; its DSN in `ROOM_SENTRY_DSN` (`xcodegen/base.yml`) | — |
| The update feed URL | the identity is decided (`app.room.desktop`, B-6 closed 2026-10-04); `ROOM_UPDATE_FEED_URL` waits for the update host | B-6 (closed) |
| The passkey entitlement request | unblocked by the identity; the Account Holder files it | B-6 |
| The by-hand pass | `research/notes/chapter-2-by-hand.md`, a day at most, friction as "2.9 by-hand" | — |

## Risks, re-ranked

Against PLAN §7 (re-ranked at the end of Chapter 1). "Implementer" is what Chapter 2 and the tour showed; the planner's column is the planner's (the Chapter 3 spec added six risks of its own, listed after the eleven).

| # (PLAN §7) | Risk | Chapter 2 evidence (implementer) | Proposed | Planner |
|---|---|---|---|---|
| 1 | Rebase and build cost at a 2-week cadence | No fork work in the Chapter 2 phases; PR #1 ran beside them. Nothing new from the CEF side | unchanged | stays #1; the official build (3–6 h, LTO memory) joins it; 3.8 measures two rebases before the cadence is chosen |
| 2 | `BrowserWindow` entanglement | Not exercised on CEF. The Chapter 2 app now has a spike for every feature, so 3.2's "real input through a real window" can be the tour itself, section by section (`--groups`) | unchanged; mitigation stronger | stays #2; the tour section by section is 3.2's harness, once B-44 is fixed in 3.1a |
| 3 | Unrequested network calls | Room's own code: 0 requests, 0 bytes (2.8b, again in the tour). CEF's engine: six Google hosts on a fresh profile, three on the tour's reused one (B-19). PR #1 took RoomCore's idle traffic 62 → 0 | down: Room's half is proven, the engine's has a branch | down to #4: Room's half is proven by a check; PR #1's policy merges in 3.1a and the release build is net-logged in 3.1b |
| 4 | Keychain and signing identity | CEF stayed on the mock keychain all chapter; nothing new. The identity is decided (`app.room.desktop`) | unchanged | down to #10; the identity is decided, the signed-build keychain check is a 3.1b task |
| 5 | Widevine | Not touched | unchanged | #7 together with the Web Store: both verified in 3.1b/3.6a with fallbacks |
| 6 | Web Store for non-Chrome brands | Not touched | unchanged | #7 with Widevine |
| 7 | CEF caps make Chapter 2 a weak daily driver | Every cap was hit as listed and none surprised us (table above); the by-hand pass uses throwaway accounts | down; retires at 3.9 | retires at 3.9; the by-hand pass uses throwaway accounts |
| 8 | Passkey entitlement lead time | Unblocked 2026-10-04 by the identity decision; the request can go now | unchanged until filed | #11; unblocked, the user files it |
| 9 | Sparkle update size | Sparkle 2.10 wired behind its opt-in (2.8b); the size is still the release build's (3.1b) | unchanged | #12; a number in 3.1b |
| 10 | Crashpad → Sentry | Sentry 9.30 wired for the app process only, crash reports only (2.8b); helper crashes and minidumps are Chapter 3 | unchanged | #13; one forced helper crash in 3.4b |
| 11 | CEF single maintainer | Ends at 3.9 | unchanged | ends at 3.9 |
| new | **Main-thread budget at 120 Hz.** Every Chapter 2 timing is at 60 Hz. Visible-window tab switching is 14–15 ms median and 17–19 ms p95 (B-41); a query's first keystroke 18 ms on an E core; 2–8% of 120 Hz-sized scroll steps over 8.3 ms (B-16) | three 120 Hz measurements are user items (B-16, B-20, B-21); RoomCore's own numbers come in 3.3b | add, mid-table | #5; three user runs on the laptop, and 3.3b takes RoomCore's numbers under the tour's conditions |
| new | **The tour as Chapter 3's harness can pass by skipping.** Seven spike files drive pages through CEF-only paths (`as? CEFWebContents`, CDP `Input.dispatchMouseEvent`, `Runtime.evaluate`) and `return` silently when the cast fails. The tour's checks require each result line, so a skipped section fails rather than passes; the spikes still need an engine-neutral input and script path before 3.2 | add, high for Chapter 3 | #3 and a 3.1a task: an engine-neutral DEBUG driving surface (click, key, script, capture) before any tour section runs on RoomCore |
| new | **Launch time grows with the state.** `RoomStorage.open` runs `PRAGMA integrity_check` over the whole database on the main thread at every launch: 0.35–0.56 s on the tour's 42 MB database (50,025 history URLs, 151,824 visits); relaunch to the selected page 1.41 s on that state against 0.48–0.60 s in 2.3 (B-42). History leaves `Room.sqlite` in 3.5/3.9; until then a check only after an unclean exit would do | add, low | #14 and a one-line 3.1a task: `quick_check` at every launch, the full `integrity_check` only after an unclean exit |
| (Chapter 3 spec) | Official build time and memory; rebase churn in `chrome/browser/ui/views/frame/`; hybrid Views bubbles; Web Store and Widevine; the shutdown watchdog (B-38); memory (4.1 GB for ten pages on CEF) | — | — | #6 hybrid bubbles, #8 shutdown watchdog, #9 memory, and the build/rebase items folded into #1; the full ranking is PLAN §7 |

## Planner's closing (2026-10-04)

Chapter 2 did what its overview asked: every Arc/Zen interaction decision is implemented, measured and captured, on one engine, in nine phases over four days across two machines, with a spike for each feature and a tour that runs them all in 36 minutes. The only product findings of the integration check are three backlog rows and one bound missed by two milliseconds on a visible window. Nothing blocks Chapter 3.

What Chapter 3 inherits from this review, now in its spec: the tour as the acceptance harness, which first needs an engine-neutral driving surface (B-44, 3.1a); the 120 Hz numbers as user items and 3.3b's conditions; the launch-time check (B-42, 3.1a); the Public Suffix List placed in 3.3a; and the CEF caps table as the checklist of what RoomCore must lift, phase by phase.

What stays open from Chapter 2 itself: the user's by-hand pass, whose friction is triaged with the 3.9 week's; the four laptop measurements (B-16, B-18, B-20, B-21); camera, microphone and location on a machine with devices (B-26). The chapter is closed with those named; the risk ranking in PLAN §7 is the planner's.
