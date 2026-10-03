# RoomCore hardening checkpoint report — 2026-10-03

Branch: bg/roomcore-hardening. Draft PR: https://github.com/lekevicius/room/pull/1.
This is a partial engineering checkpoint, not full browser acceptance.

## Measured gates

| Gate | Evidence / status |
|---|---|
| Laptop build | Complete: M1 Max 64 GB, nice 0, default 10 jobs, existing out/dev. Resumed 11,610 s; cumulative with prior partial 14,620 s. Original build retry 0. Final load 404.72 / 462.97 / 478.30 |
| Package | Ad-hoc strict signature valid; 518 component dylibs, 916 MB framework, latest host 918 MB; mock keychain |
| Initial baseline | nav 14.209 s; open10 ready 15 s; valid ten-page quits 0.493 / 0.471 s, 0 helpers left / 0 new crashes |
| Latest serial baseline | After FedCM fix: nav 12.447 s; ten loaded pages, quit 0.635 s, load1 28.40, 27 helpers / 0 left / 0 new crashes, exit 0 |
| Concurrent repetition | After FedCM fix: auth 20 s; ten-page quit 1.881 s, 26 helpers / 0 left / 0 crashes, exit 0. Does not resolve the retained older watchdog |
| Surface coverage | Original 18 processes driven without crashes. 17 drives pass; fullscreen deliberately rejects and its driver fails. Added deterministic FedCM passive bubble / active modal probe passes. Native UI acceptance remains partial |
| Network before | Fresh profile, 600 s idle, 608 s process: 62 HTTP / 86 connections / 9 DNS, 0 TLS errors |
| Network after demand-CDM and FedCM | Fresh profile, 600 s idle, 610 s process: 0 HTTP / 0 connections / 0 DNS / 0 TLS errors, 18 events, clean exit. Fixed app code 2a04498 |
| On-demand exception | Widevine 4.10.3050.0 installed only after EME request; MediaKeys created in 6.812 s; 3 external updater requests. Installed reuse and unrelated-key probe: 0 external requests. Forced updater DNS failure bounded at 60.163 s. Licensed playback unverified |
| TLS B-3 | All 88 reproduced laptop failures attributed by host to local DNS sinkholes ([::]:443), TLS alert 80 / BoringSSL 1080. Exact historical mini ~220 still needs its original NetLog |
| Crashpad B-14 | Both primary and monitor command lines verified at selected-root/Crashpad, prod=Room_Mac |
| Patch/API scope | Original 0001–0005/public ObjC headers unchanged. New 0006 scheduler, 0007 demand-CDM, 0008 FedCM anchor hooks each justified; implementation remains in //room |
| Chapter 2 scope | Protected diff contains only App/RoomCore. No Packages, other App, ROADMAP edits; no main push or merge |

Before request list: accounts.google.com 1 (Gaia), android.clients.google.com
9 (GCM check-in/registration), clients2.google.com 1 (time),
edgedl.me.gvt1.com 22 and update.googleapis.com 27 (component updater),
safebrowsing.googleapis.com 1 (Safe Browsing), www.google.com 1 (AIM).
After request list: empty. Detailed attribution: roomcore-network-audit.md.

## Fixes and verification boundaries

Room supplies a real Views parent for web dialogs, a permission bubble anchor,
Chrome FindBarOwner, and FedCM bubble/modal anchors with initialized primary
Views context. Extension tab edits now reflect live model state instead of an
always-false stub; actual tab 1→2→1 and popup create/remove probes pass. Stub-hit logging remains enabled. Each engine fix has an
incremental build and navigation/ten-page quit baseline. The full surface,
Chrome call sites and members are in spike-results.md.

The old concurrent auth completion hit Chrome's 10 s shutdown watchdog (exit
2), and its concurrent baseline retained 9 helpers beyond 5 s. These samples
remain failures. The minidump shows the main thread joining the IO thread,
which is in macOS VM deallocation during Mojo channel teardown. A later
concurrent run found and led to fixing the separate FedCM crash. A clean
repeat cannot prove the original shutdown issue fixed. See
roomcore-shutdown-investigation.md for stacks and next diagnostic step.

Chapter 3 must supply popup/window ownership, native address/permission/FedCM
anchors and focus, find keyboard routing, permission/auth completion UI,
download chooser/status/cancellation, extension actions, and fullscreen state
with visible origin/escape UI. Stub behavior cannot stand in for these. Current
AGENTS.md prohibits accessibility/computer-use driving; native click/focus/
compositing checks remain explicitly listed for reviewer interaction.
