# RoomCore hardening checkpoint report — 2026-10-03

Branch: bg/roomcore-hardening. Draft PR: https://github.com/lekevicius/room/pull/1.
This is a partial engineering checkpoint, not full browser acceptance.

Coverage clarification after user review: the original18 drives are not a
complete Chrome UI inventory. The [expanded source audit](roomcore-ui-surface-audit.md)
records22 surface families, source-confirmed missing boundaries and the next
bounded UI probe batch. It adds no runtime passes. In particular, autofill
save/update, docked DevTools, device choosers, capture indicators, real print
preview and extension action hosting remain open.

## Measured gates

| Gate | Evidence / status |
|---|---|
| Laptop build | Complete: M1 Max 64 GB, nice 0, default 10 jobs, existing out/dev. Resumed 11,610 s; cumulative with prior partial 14,620 s. Original build retry 0. Final load 404.72 / 462.97 / 478.30 |
| Package | Ad-hoc strict signature valid; 518 component dylibs, 916 MB framework, latest host 918 MB; mock keychain |
| Initial baseline | nav 14.209 s; open10 ready 15 s; valid ten-page quits 0.493 / 0.471 s, 0 helpers left / 0 new crashes |
| Latest serial baseline | After shutdown-worker-start correction: nav 20.447 s; ten loaded pages, quit 3.083 s, load1 29.759, 26 helpers / 0 left / 0 new crashes, exit 0 |
| Concurrent repetition | Three-browser exercise reproduced 2 watchdog exits after all ten pages loaded; third fixture rejected. Helper-capture repeat passed at 6.017 / 5.691 s but does not resolve the failure |
| Surface coverage | Original 18 processes driven without crashes. 17 drives pass; fullscreen deliberately rejects and its driver fails. Added deterministic FedCM passive bubble / active modal probe passes. Native UI acceptance remains partial |
| Network before | Fresh profile, 600 s idle, 608 s process: 62 HTTP / 86 connections / 9 DNS, 0 TLS errors |
| Network current package | Patch0010 / engine3f091cb: fresh profile, 600 s requested idle, 616 s process; 0 HTTP / 0 connections / 0 DNS / 0 TLS errors, 18 events over 601.581 s, exit 0 |
| On-demand exception | Widevine 4.10.3050.0 installed only after EME request; MediaKeys created in 6.812 s; 3 external updater requests. Installed reuse and unrelated-key probe: 0 external requests. Forced updater DNS failure bounded at 60.163 s. Licensed playback unverified |
| TLS B-3 | All 88 reproduced laptop failures attributed by host to local DNS sinkholes ([::]:443), TLS alert 80 / BoringSSL 1080. Exact historical mini ~220 still needs its original NetLog |
| Crashpad B-14 | Both primary and monitor command lines verified at selected-root/Crashpad, prod=Room_Mac |
| Patch/API scope | Original 0001–0005/public ObjC headers unchanged. New 0006 scheduler, 0007 demand-CDM, 0008 FedCM anchor and 0009 SadTab factory hooks, plus 0010 shutdown-worker-start correction, each justified; Room-specific implementation stays in //room, with the documented base startup correction in0010 |
| Chapter 2 scope | Branch changes from merge base contain only App/RoomCore in protected paths. Main advanced to8b5f79f; direct-main scope needs a later safe rebase. No Packages, other App or ROADMAP edits by this branch; no main push or merge |

Before request list: accounts.google.com 1 (Gaia), android.clients.google.com
9 (GCM check-in/registration), clients2.google.com 1 (time),
edgedl.me.gvt1.com 22 and update.googleapis.com 27 (component updater),
safebrowsing.googleapis.com 1 (Safe Browsing), www.google.com 1 (AIM).
After request list: empty. Detailed attribution: roomcore-network-audit.md.

## Fixes and verification boundaries

Room supplies a real Views parent for web dialogs, a permission bubble anchor,
Chrome FindBarOwner, and FedCM bubble/modal anchors with initialized primary
Views context. Extension tab edits now reflect live model state instead of an
always-false stub; actual tab 1→2→1 and popup create/remove probes pass. Explicit activation now activates NSApp before making the window key; action.openPopup advances to the expected missing-toolbar boundary. Stub-hit logging remains enabled. Each engine fix has an
incremental build and navigation/ten-page quit baseline. The full surface,
Chrome call sites and members are in spike-results.md.

The old concurrent auth completion hit Chrome's 10 s shutdown watchdog (exit
2), and its concurrent baseline retained 9 helpers beyond 5 s. These samples
remain failures. The minidump shows the main thread joining the IO thread,
which is in macOS VM deallocation during Mojo channel teardown. A later
concurrent run found and led to fixing the separate FedCM crash. Two new
watchdogs reproduced after all ten pages loaded: live samples first wait for
the network service, then one final dump reaches thread-pool shutdown. A
targeted slow successful repeat captured the network helper waiting on worker
startup/QoS setting. This is a diagnostic lead, not a proven cause or fix. See
roomcore-shutdown-investigation.md for stacks and next diagnostic step.

Chapter 3 must supply popup/window ownership, native address/permission/FedCM
anchors and focus, find keyboard routing, permission/auth completion UI,
download chooser/status/cancellation, extension actions, fullscreen state
with visible origin/escape UI, and accessible crash/retry/reporting controls. Stub behavior cannot stand in for these. Current
AGENTS.md prohibits accessibility/computer-use driving; native click/focus/
compositing checks remain explicitly listed for reviewer interaction.

Completion probes additionally verify cancellation after 131,072 of 33,554,432
advertised download bytes (no final/partial file remains), certificate-error
leave back to the safe page, beforeunload cancellation preserving its page,
and a muted Web Audio oscillator advancing 0.261333 s at 48 kHz before close.
All four processes exit 0. Audible output and native controls remain unverified.

Shutdown controls remain inconclusive: a longer Room capture passed three
quits in 5.474 / 2.919 / 6.969 s; a stock-window entry point using the same
component libraries passed one complete ten-page quit in 1.091 s. Other
control samples failed page readiness/setup and are rejected. Native QoS
calls did not reproduce the delay. No scheduling/watchdog workaround was added.

Renderer-loss containment now passes intentional Page.crash and reload (39 s,
exit 0): crashed + Cocoa fallback transitions to loaded + fallback removed.
A real Blink renderer DCHECK previously triggered a second browser crash in
SadTabController's absent BrowserView. Patch 0009 redirects its otherwise
unreplaceable factory; existing SadTabHelper owns the Cocoa fallback. Renderer
Blink layout behavior is not changed. Original 0001–0008/public headers are
unchanged; apply is 0 applied / 9 already, Chromium 0811f471258ac. Final build
22 s / 3 steps and GN check pass. Native retry UI remains Chapter 3 work.

Later targeted shutdown captures rejected 6 complete-page samples for helpers
remaining beyond 5 s, despite browser exit 0. Network-only captures measured
network-service waits 5.933 / 6.913 / 6.813 s; leftover renderer stacks show
GPU-channel disconnect waiting while IO deallocates Mojo Mach VM. Sampling
may affect timings; this does not establish a cause or production fix. The
software-GPU diagnostic exposed the separate SadTab crash fixed above. No
watchdog, grace, QoS or GPU policy workaround was added.

A bounded loopback control now completes ten distinct storage/cache/canvas
origins in each of three concurrent browsers. Room quits 1.028/1.596/2.336 s;
stock-window entry on the same component libraries quits 5.107/3.790/4.585 s.
All leave 0 helpers and 0 new crashes, with no stack sampling. This eliminates
external-page readiness as a problem in this control but does not reproduce
or fix the real-site shutdown failure. Different setup/termination paths and
load prevent a performance ranking. The final current-package 600-second idle
audit (netlog-idle-sadtab-final) passes: 614 s process, 18 events, zero traffic,
exit 0. CI e5ad547 passes 75/83 s.

The latest engine also reproduced three watchdog exits without live stack
sampling at the original process-census cadence (two non-loading ten-page
fixtures; one incomplete fixture rejected). A preceding optional 250 ms census
run passed 5.010/3.331/3.930 s with no helpers/crashes. Census wall time was about
27 s versus 48–50 s per runner, but load, swap and site challenges differed.
This supports reducing diagnostic overhead, not declaring an engine fix.
Exact current-library minidumps again show network-service waits or ThreadPool
shutdown; all raw failures remain rejected. B-16 remains open.

The opt-in native process observer now passes child exec/reparent/exit and
PID-start identity checks, including a real runner rejection of a lingering
helper after five seconds. One three-browser real-site run passes7.723/2.885/
1.326s with0helpers/crashes. Observer census wall time is10–11s per runner,
compared with48–50s in the earlier full-ps run; this reduces diagnostic overhead
but does not establish a shutdown fix. Default baseline behavior is unchanged.
The user replaced the periodic heartbeat with an active hardening Goal.

Latest read-only network-thread diagnostic: two valid ten-page quits at
1.148/2.193s, zero leftovers/crashes; a third watchdogexit2 also has an
unfinished-page rejection. Its network-service wait completes in3831ms, while
the final browser dump waits for ThreadPool shutdown with a policy-loader
filesystem-watch open still active. This is evidence of unfinished work, not a
measured open duration or root cause. Diagnostic thread-handle lifecycle and
reuse are validated; no engine/scheduling/default-baseline behavior changed.
B-16 remains unresolved.

Branch refreshed onto main af1fab0 after the compiler stopped. Both concurrent
spike-note sections are preserved. Engine/roomcore and App/RoomCore tree hashes
are unchanged by rebase; original measured package IDs above remain valid
historical artifact identities. Protected-path diff again contains only
App/RoomCore. Original five patches and public ObjC headers remain unchanged.

Patch0010 corrects a separately demonstrated startup invariant: workers created
after shutdown begins now enter at least default priority (probe QoS9 to25),
while normal worker startup remains atQoS9. Build30.66s/15steps and required
serial baseline pass. Existing blocked workers and all teardown deadlines are
unchanged. B-16 is not claimed resolved. The new completed idle audit above qualifies this base-library correction;
network policy source is unchanged.

Concurrent follow-up on patch0010: all ten pages ready in each of three hosts;
quits2.766/2.453/2.090s, zero helpers left/crash reports, exit0. Same observer as
the preceding clean control; changing site/load conditions prevent performance
or root-cause claims. Apply0applied/10already, Chromium7ac71cfacf83f.

An isolated callback-based probe now demonstrates another remaining priority
path: four already-blocked worker/task variants stay at effective priority4
while the pool starts waiting for shutdown. A diagnostic-only native override
raises all four to31 and they finish normally. This establishes a reproducible
priority invariant and validates the observer; it does not establish the full
cause of historical browser watchdogs. Safe production override lifetime and
synchronization are not implemented, so B-16 remains open.
