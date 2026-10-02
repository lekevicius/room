# Chapter 1 review — Foundations

Date: 2026-10-03. Phases 1.1–1.5 done (reviews in `docs/progress.md`); this is Phase 1.6's write-up. Numbers come from `build-log.md` and `spike-results.md`; nothing here is new measurement except where marked.

## The three unknowns, answered

| Unknown (ROADMAP Chapter 1) | Answer |
|---|---|
| Does Chromium's layer-hosted view clip cleanly into the inset card? | Yes. On CEF the page is clipped at the 10 pt continuous corner to the pixel (first fill pixel at k=3 on the diagonal, as in Dia), the 1 px hairline composites above the page, and scrolling holds 120 fps with the mask (median frame 8.30 ms, 0 frames > 12.5 ms over 3 s; mask off: 1 frame > 12.5 ms). Live resize never showed the material (576/576 samples). Whether the mask forces WindowServer into an extra composite of the IOSurface is **still unmeasured** (below). |
| Can a stub-`BrowserWindow` Chromium fork be driven from a Swift app with reasonable effort? | Yes. Our fork (5 small patches, everything else in `//room`) renders Wikipedia in the Phase 1.3 card from a Swift host through our own ObjC API, with KVO navigation state, real mouse/scroll input and a 0.18–0.55 s quit with ten pages. First contact with a non-Views window cost ten small fixes (`spike-results.md` Phase 1.5), roughly a day. Over ten real sites Chrome called 12 of the 68 stubbed `BrowserWindow` members. |
| What does Chromium build iteration cost here? | Clean component build ~4 h 15–24 min on both machines (M1 Max 64 GB; M4 24 GB at 6 jobs). Incremental: 27–39 s for a touched core file, 45–63 s for a `//room` change, 4 s no-op. Checkout: ~55 min fetch (57–75 GB), 113 GB on disk. |

## Spike results summary

From `spike-results.md` (Phase 1.4 on CEF, Phase 1.5 on RoomCore):

| Item | Status | Note |
|---|---|---|
| Clipping | green (was amber) | pixel-exact; composite cost measured 2026-10-03 after the review: no extra WindowServer GPU work with the mask (2.89 vs 2.88 ms/frame) |
| Empty toolbar band over the page | green | clicks reach the page; no scroll-edge effect; toolbar hidden in fullscreen |
| Live resize | green | page colour in 576/576 samples; frames median 8.30 ms, max 10.4 ms |
| Overlay z-order (glass over the page, hover reveal) | green | page receives no events under the overlay |
| Keyboard (Colemak, Lithuanian, ABC) | green | reserved keys never reach the page; ⌘C/V/Z go page-first then to the menu |
| Popups, `<select>`, date picker, JS dialogs | green | |
| DevTools | green with a cap | docked pane needs the 127.0.0.1 debug port (Debug builds) |
| Memory (CEF hidden browsers) | green | see below |
| Extensions on CEF | as expected | content scripts and workers run; no popups/toolbar (Alloy) |
| Autofill dropdown | green | anchored 1 pt under the field |
| Signing | amber | Developer ID signing works; notarization waits for the user's credential profile |
| Shutdown | green | CEF 0.54–0.66 s (load 35–40); RoomCore 0.18–0.55 s (load 8–16) |
| CDP channel | green | 0.21 ms median round trip |
| Audibility on CEF | amber | Web Audio stop not visible until RoomCore |
| RoomCore page in window, navigation, input, quit | green | Phase 1.5 |

Totals: 15 items, 12 green, 3 amber with fallbacks, 0 red at the review; clipping turned green the next day (13 green, 2 amber).

### The unmeasured one: does the card mask cost an extra composite?

**Update 2026-10-03:** measured after the user enabled Developer mode. Mask on and off cost the same WindowServer GPU time per frame (2.89 vs 2.88 ms, same number of GPU passes); details in `spike-results.md`, "Card mask composite cost". The paragraph below is the review as written.

Not measured. The ROADMAP's suggested route (Instruments' Metal System Trace or Animation Hitches, mask on vs. off, on the Phase 1.4 scroll page) needs Developer Tools access on this Mac (`DevToolsSecurity -status`: disabled), which takes an administrator password, so it did not fit in this session. What we have: with the mask on, scrolling holds 120 fps with 0 frames over 12.5 ms, the same as with the mask off, at load 30–44; whatever the extra cost is, it does not show as dropped frames on this hardware. Decision: keep the planned fallback (a Chromium-side `RoundedCornersF`/clip on the web contents layer in RoomCore, as Electron does) and measure power/composite cost in Chapter 5 with Instruments once Developer mode is on. Backlog item B-1.

## Build timings

| Step | M1 Max 64 GB (laptop) | M4 24 GB (Mac mini, disk image on USB SSD) |
|---|---|---|
| CEF bootstrap, cold | 201 s | 199 s |
| Room (CEF) clean Debug build | 21 s | 23.5 s |
| Chromium fetch | 52 min | 57 min (75 GiB announced) |
| sync + runhooks | 6 min | 7 min |
| Clean component build | 4 h 24 min (vanilla, partly at nice +5) | 4 h 15 min (branded; 10 jobs swapped, finished at 6 jobs) |
| Incremental (core file / `//room` / no-op) | 27–39 s / — / 4 s | — / 45–63 s / — |
| Package RoomCore + host | — | 10 s |

Consequence: a rebase onto a new milestone is close to a clean build (~4 h) plus fix-up time. At Chrome's two-week cadence that is one background build per fortnight, affordable if the patch set stays this small. The Extended Stable fallback stays in PLAN §4.

## Memory

| Engine | Measurement | Number |
|---|---|---|
| CEF | baseline, one blank page, all processes | 670 MB RSS, 6 processes |
| CEF | per hidden browser (1 / 10 / 30 typical sites) | +193 / +327 / +242 MB each |
| CEF | 30 hidden browsers | 7.9 GB summed RSS, 40 renderers (double-counts shared pages) |
| RoomCore | browser process with 10 typical sites loaded | 329–443 MB RSS, 24–35 helper processes |

The RoomCore number is the browser process alone; a summed figure comparable to CEF's is a Chapter 3 measurement (B-2).

## What surprised us

1. **Build cost and memory.** 4+ hours for a clean component build on both machines (the research estimated 1.3–2 h), and on 24 GB the default parallelism swaps, so throughput drops about 10×.
2. **Dia's look is mostly AppKit defaults, measured.** The traffic-light position comes from an empty `.unified` toolbar, not from moving the buttons; the card is 6 pt / 10 pt, not the 8 / 12 we guessed.
3. **CEF on macOS fights embedding.** `ShowDevTools` into a view crashes, `DoClose` → `false` closes the host window, profiles must be direct children of the cache root, CDP results can arrive synchronously, own-window captures miss Chromium's GPU layer.
4. **The keychain gates navigation.** On an ad-hoc RoomCore build the cookie store waits for the "Room Safe Storage" key, so a pending login-password prompt stalls *every* navigation with no error. The same mechanism made CEF builds prompt on every launch in Phase 1.1.
5. **Chrome's UI code CHECKs rather than tolerates.** Read Anything, the Bookmarks menu bridge, the exclusive-access manager and feature teardown all assumed a `BrowserView` or Chrome's main menu, and crashed the process rather than degrading. Each fix was small, but they only show up by running real input through a real window.
6. **A Swift host touches ObjC classes earlier than you think.** Naming `RoomHostApplication.self` ran Chromium's `+initialize` before `main` reached our code.
7. **Chromium phones home on launch** even without API keys: component updater, `accounts.google.com/ListAccounts`, `google.com/async/folae`.
8. **The framework binary has no Mach-O header room**, so rpaths cannot be added after linking; packaging works around it in the host.

## Engine plan: confirmed, with amendments

The plan in PLAN §1.2 holds: CEF scaffold for Chapter 2, RoomCore in Chapter 3, CEF deleted at the gate. Phase 1.5 did not fail in a way that changes Chapter 3's estimate; it showed the work is the expected kind (implement the window-side objects Chrome reaches for, one at a time) at the expected size. Amendments, recorded in PLAN §4 and the ROADMAP:

- **Chapter 3 starts where Phase 1.5 stopped.** `RoomLocationBar`, `RoomExclusiveAccessContext`, feature teardown and the Bookmarks menu placeholder already exist; 3.2 grows them into real implementations instead of starting from stubs.
- **Main menu ownership** goes into Chapter 3.2: Chrome's `AppController` stays `NSApp.delegate` and walks the main menu by command tag (File, Tab, History, Bookmarks, Profile), so either the host's menus carry Chrome's tags or `//room` owns the main menu. Decide there; the hidden Bookmarks item is the placeholder.
- **A network-call audit** joins Chapter 3.1: every launch-time request is either user-initiated or switched off (prefs, switches, or `//room` hooks), per CLAUDE.md.
- **Keychain**: RoomCore uses the real keychain only when team-signed; development builds that need it must be Developer ID–signed (`scripts/sign-and-notarize.sh … --no-notarize`). PLAN §4 gains a row.
- **Build machines**: under ~32 GB RAM build with 6 jobs (PLAN §4 build row, amended in Phase 1.5).

## Risks, re-ranked

Compared with PLAN §7 (2026-10-01). Changes in rank are explained in the last column; PLAN §7 now carries this table.

| # | Risk | Was | Status after Chapter 1 / mitigation |
|---|---|---|---|
| 1 | Rebase and build cost at a 2-week cadence | 3, 4 | Up. Clean builds take 4+ h and swap on 24 GB; a milestone rebase ≈ a clean build. Keep the patch set tiny (5 today), script the rebase (3.8), build overnight, Extended Stable fallback |
| 2 | `BrowserWindow` replacement entanglement (Chrome UI code that assumes `BrowserView`/Chrome's menu and CHECKs) | 2 | Confirmed real but tractable: 10 first-contact failures, each a small `//room` fix or a one-line patch. Mitigation: run real input through a real window early in every Chapter 3 phase; keep stub-hit logging |
| 3 | Unrequested network calls from Chrome components | new | Seen on every RoomCore launch. Audit in 3.1; prefs/switches first, `//room` hooks second |
| 4 | Keychain and signing identity (dev builds stall on prompts; notarization credentials) | new | Mock keychain for ad-hoc builds; Developer ID signing for keychain tests; user stores the notarytool profile once |
| 5 | Widevine CDM download / playback | 5 | Unchanged, unverified; verify in Chapter 3 |
| 6 | Chrome Web Store access for non-Chrome brands | 6 | Unchanged; keep unpacked/CRX path |
| 7 | Card mask costs an extra IOSurface composite (power, not frames) | 1 | Retired 2026-10-03: no extra WindowServer GPU work measured (B-1) |
| 8 | CEF caps make Chapter 2 a weak daily driver (mock-keychain cookies, no extension popups, no password prompts) | new | Stated in the Chapter 2 spec; Chapter 2 dogfooding avoids sensitive accounts |
| 9 | Passkey entitlement lead time | 9 | Unchanged; request from Apple before Chapter 4 |
| 10 | Sparkle update size (RoomCore component bundle 917 MB; release static size unknown) | 10 | Measure the static release build in 3.1 |
| 11 | Crashpad → Sentry minidumps | 11 | Unchanged; one forced renderer crash in Chapter 3 |
| 12 | Overlay z-order over the web view | 7 | Retired as a risk: green in Phase 1.4 |
| 13 | Traffic-light geometry drift | 8 | Retired as a risk: one layout manager, six-state tests, AppKit's own placement |
| 14 | CEF single-maintainer dependency | 12 | Only until Chapter 3.9 |
