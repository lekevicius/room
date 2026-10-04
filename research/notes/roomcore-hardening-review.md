# Review of PR #1 — `bg/roomcore-hardening` (planner, 2026-10-04)

Branch: 57 commits, 82 files, +9,238 / −40, on main `8522d6f` (reconciled; a merge onto today's main conflicts only in `docs/backlog.md`, `docs/engine-api.md` and `research/notes/spike-results.md`, all append-on-append). Draft PR, never merged. Public ObjC headers and patches 0001–0005 untouched, as instructed.

## Verdict

Merge it at the start of Chapter 3 (3.1a), with three adjustments: park patch 0010, gate the spike hooks out of release builds, and renumber its backlog items. The branch did what it was asked and said so honestly: it turned "RoomCore crashes on first contact with Chrome UI" into a measured table of what Chrome needs from a non-Views window, fixed the crashes with the smallest hooks, made the engine silent on the network, and wrote down exactly which product contracts Chapter 3 owes. Its notes are dense but every number has a method and the failed samples are kept as failures.

## What it delivers, by value

| Piece | Where | Keep? | Note |
|---|---|---|---|
| Network policy: launch + 600 s idle + quit from 62 requests / 86 connections / 9 DNS to **0 / 0 / 0** | `room/core/room_network_policy.cc`, patch 0006 (10 lines, component-update scheduler factory) | yes | Uses Chromium's `*ForTesting` factory seams for the signin client and the invalidation provider; they carry no test-only behaviour, but a rebase may move them. 3.1 keeps them and re-verifies after every rebase |
| Widevine on demand: first EME request provisions the CDM (6.8 s), installed CDMs reused with 0 requests, failure bounded at 60 s | patch 0007 (96 lines across `//content` and `//chrome`), `room_cdm_*` | yes, watched | The heaviest patch and the only one in `//content`; the alternative (`--disable-component-update`) would remove Widevine registration. Licensed playback still unverified (3.1) |
| Crashpad under the selected user-data root (B-14) | `room_application.mm` PathService override | yes | Handler command lines verified |
| Views modal parent + bubble anchor for a non-Views window: JS dialogs, permission prompts, FedCM, print preview, auth, choosers all open and complete | `RoomModalDialogHost`, `RoomLocationBar::GetChipAnchor`, patch 0008 (FedCM, 16 lines) | yes | This is PLAN §4's hybrid ("keep Views bubbles, anchor by rect") made real; it is the seed of 3.2 and 3.4 |
| Find through Chrome's `FindBarHost` | `RoomFindBarOwner` | spike only | The product drives find through `FindTabHelper` (the host owns the bar); `CreateFindBar` returns a no-op in 3.3 |
| SadTab fallback for crashed renderers | patch 0009 (10 lines), `RoomSadTab` | yes | The host's crashed-page view (2.6b) replaces the NSBox in 3.4; the factory hook stays |
| Autofill bubble handler + window lookup hook | patch 0011 (18 lines), `RoomAutofillAnchors` | yes | Address save/update bubbles work; passwords stop at a missing `ToolbarButtonProvider` (3.7 supplies a minimal one) |
| Extension chooser guard | patch 0012 (5 lines) | yes | Safe rejection, not a feature |
| Shutdown-worker start priority | patch 0010 (8 lines in `//base`) | **park** | The watchdog it addresses stays unresolved ("a diagnostic lead, not a proven cause"); a `//base` scheduling change with no reproducible fix behind it is the one patch I would not carry across rebases. Keep the file under `patches/parked/` with its note; 3.1b retries the reproduction on the release build with and without it |
| Private `-RoomSpike` command and action hooks (~400 lines in `room_browser.mm`), host spikes (`App/RoomCore/Host*Spike.swift`), fixtures, netlog summariser, process/thread observers | `room_browser.mm`, `App/RoomCore`, `scripts/` | yes, gated | They are the engine-level test harness Chapter 3 needs. Compile them only under a GN arg (`room_enable_spikes`, true in `args/dev.gn`, false in release) so the shipped framework carries no probe code |
| Stub-hit table: 18 feature drives + FedCM + renderer loss, with the window members each path needs | `spike-results.md` (branch) | yes | The direct input to 3.2's member list |
| Six-package UI compatibility results (autofill, choosers, print/DevTools, extensions, media, downloads) with what passed and what is blocked | `roomcore-ui-*.md` | yes | Read before designing 3.4, 3.6, 3.7 |

## Findings that change the Chapter 3 plan

1. **Popups fall back to Chrome's own `BrowserView` window** today (`Browser::AddNewContents` has no Room path). 3.2 must route every disposition to the host; a Chrome window must never appear.
2. **Docked DevTools needs a `DevtoolsUIController`** (constructed with `ContentsContainerView`s). 3.3 either implements a minimal controller or hosts the front-end `WebContents` undocked in the host's pane. Decide by size.
3. **Password bubbles need a `ToolbarButtonProvider`**; a minimal provider that anchors on the host's site button is the 3.7 answer. Do not register a fake extensions container to get past it.
4. **`ConfirmBrowserCloseWithPendingDownloads` auto-confirms**; 3.4 routes it to the host's decision.
5. **Fullscreen is refused by design** (`RoomExclusiveAccessContext`); 3.2 implements the context against the host's element-fullscreen state from 2.6b.
6. **Extension action popups open and resize under Room ownership** (66×80 → 374×266); `action.openPopup` from the API still wants a toolbar. 3.6's `ExtensionsContainer` is the real fix.
7. **Shutdown watchdog**: an intermittent 10 s teardown watchdog with ten real pages under load, main thread joining the IO thread during Mojo channel teardown. Not reproduced on loopback fixtures. 3.1b owns it on the release build.
8. **TLS −107 errors on the laptop are DNS sinkholes** (the local blocker answers blocked hosts with `[::]:443`). Closes B-3 for the laptop; the Mac mini's ~220 need its own net-log once (B-39).

## Housekeeping for the merge (3.1a)

- Backlog ids: the branch's "B-16" (shutdown watchdog) and "B-19" (concurrent teardown) clash with main's; they become B-38; its TLS note becomes B-39; patch 0010 parked is B-40.
- `docs/engine-api.md`: the branch's additive sections go under a "RoomCore (Chapter 3 inputs)" heading after the Phase 2.6 checklist.
- `spike-results.md`: the branch's sections are appended as "Background hardening (laptop, 2026-10-03)"; `build-log.md` gains the laptop's resumed build (11,610 s resumed, 14,620 s cumulative).
- Scripts: keep all; the Python observers and the netlog summariser get a line in `docs/setup.md`.
- Chromium checkout on the laptop is on the branch's `room` branch with 12 patches; after the merge `scripts/roomcore-apply.sh` from main must report 0 applied / 11 already (0010 parked).
