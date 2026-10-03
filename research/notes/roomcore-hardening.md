# RoomCore background hardening — laptop, 2026-10-03

Branch: `bg/roomcore-hardening`; worktree: `/Users/j/.codex/worktrees/35bc/room`.
Base: `b71f298` (main was already up to date after `git pull --ff-only`).

## Checkpoint 1 — build resumed

- Chromium: `/Users/j/chromium/src`, branch `room`, HEAD `4930cc45a85ce`.
- Replaced `src/room` symlink from `/Users/j/Code/room/Engine/roomcore/room`
  to this worktree's `Engine/roomcore/room`.
- Apply output: **`patches: 0 applied, 5 already on the room branch`**.
  Clean tracked Chromium files before apply. Existing `out/dev` reused;
  `out/vanilla` and `out/scratch` untouched.
- Build launched from bash with nohup; default job count (no `-j` override).
  `ps -o pid,nice,etime,command`: build PID 94522 and Siso PID 94622 both
  **nice 0**, elapsed 16 / 12 seconds at initial observation.
- Live log: `research/notes/roomcore-build-laptop.log` (ignored by Git;
  checkpoint summaries are versioned in `build-log.md`).
- No edits to `Engine/roomcore/room` while this build runs.

## Working-rule deviations

The user's assigned path list supersedes edits to `docs/progress.md`,
`PLAN.md`, and screenshots elsewhere. Progress, deviations, fallback paths,
and measurements are recorded here and in the existing research notes.
The task replaces a numbered phase; commits use `phase-bg:` with no trailers.
The explicit checkpoint push instruction supersedes the implementer prompt's
no-push rule. Never push main or merge.

The first literal detached bash/nohup launch returned with an empty log and
no build process. A second launch retains a waiting bash parent in the exec
session (18754), while the build itself still runs under nohup with stdin
`/dev/null`. It started successfully at nice 0; this is launcher recovery,
not a failed compiler retry.

## Completion status

Checkpoint 1: apply verified and rebuild started. Runtime baseline, feature
hardening, idle network audit, TLS attribution, and Crashpad verification
remain unverified until the component build completes.

## Checkpoint 2 — preparation

18-feature plan in `roomcore-feature-plan.md`. Host-only CDP driver and
isolated loopback fixtures prepared. Net-log tooling defaults to 600 idle
seconds, terminates through NSApp, rejects an incomplete run, and attributes
request components from Chromium traffic annotation hashes. Seven parser
fixture tests pass (redirects, annotation hashing, TLS dependency chain,
unknown attribution, preconnect/DNS without URL requests, non-network URLs,
invalid input). Swift 6 host typecheck against copied public headers in a
stand-in framework passed; package modules read from the matching main
checkout's existing build. This is **compile-only**, not linked fork proof.

Find/zoom/print require the private command hook drafted in
`roomcore-command-hook-draft.md`. No public header additions. Crashpad's
PathService override is drafted in `roomcore-crashpad-draft.md`.
The 18 feature drives are not runtime-verified yet. Several native UI checks
are explicitly marked review-required in the plan/driver.

Additional checkpoint 2 checks: six live loopback fixture checks passed
(original popup/form pages, feature page, 26-byte attachment, unauthenticated
401 challenge, authenticated 200). `bash -n` passed for the three launch/
typecheck scripts. `git diff --check` uses an inherited `indent-with-non-tab`
setting that flags the repository's existing Swift space indentation; checked
with `core.whitespace=blank-at-eol,blank-at-eof,space-before-tab` instead,
preserving the repository's indentation style.

## Ten-page termination tooling and continuation

`ROOM_QUIT_MODE=spike scripts/quit-timing.sh 3` now invokes the RoomCore host
as an exact child, with a fresh profile per run, reads the host's
`terminate-request-time`, checks ten pages/no outstanding loads, records
exit status, observed child helpers and crash-report delta. It allows 5 s for
Chrome's code-sign clone cleanup. The original AppleEvent mode remains the
default for existing callers. This prepares B-8 but does not close it until
real RoomCore measurements pass. Swift typecheck, shell syntax, Python compile,
and a synthetic child termination-marker test pass (synthetic timing is not
included as a browser baseline).

A thread heartbeat `roomcore-hardening-build-and-continuation` is active every
25 minutes, implementing the requested build polling and continuation after
completion. It stays quiet for unchanged progress and resumes checkpoint 3
and the original hardening/network/Crashpad work when compilation completes.
The live build remains in exec session 18754 under nohup with a waiting bash
parent; build PID 94522, Siso PID 94622. Last observed at 02:46:19 EEST:
5,385/51,154 graph steps, elapsed 18m12s, nice 0, load 440.95/443.86/348.54.

Main advanced during compilation (Chapter 2 and working-rule changes).
`git diff main...HEAD` verifies this branch's changes stay in assigned paths.
A plain `git diff main` also shows newer main-side Chapter 2 content absent
from this older base; this is divergence, not edits made by this task. Do not
rebase while the build reads //room. After compilation, inspect upstream
changes and rebase safely, preserving Chapter 2, before the final exact-scope
check requested by the user. No main push or merge is authorized.

Draft PR: https://github.com/lekevicius/room/pull/1 (attached to this chat).
Update this PR as evidence arrives; do not create a duplicate. Keep it draft
until the runtime exit gates are met or the final partial scope is explicit.

## Checkpoint 3 — component build and laptop baseline

Build succeeded at about 05:41:37 EEST: 11,610 s resumed, 14,620 s cumulative
including the prior partial run (4h03m40s). Siso confirms localexec capacity
10, action pool 10, retry 0. Final load 404.72/462.97/478.30. No //room or
patch edits during compilation. Packaged and deep/strict ad-hoc signing passed.

nav: 14.209 s, exit 0, expected history/KVO state. open10: ready 15 s, all 10
finished, exit 0. Valid ten-page quits: 0.493/0.471 s, 0 helpers left, 0 crash
reports. A third attempt exceeded the 60 s page-loading bound (1 still loading)
and was rejected; not counted as a successful measurement. See build-log.md.

The first run's Chromium stderr omitted WARNING stub logs. Host spike launches
now explicitly use --enable-logging=stderr --log-level=0; logger itself stays
on. Per-page diagnostics now name any page that remains loading.

The ten-site NetLog reproduced 88 TLS handshake failures: all 88 socket
address lists were `[::]:443`, with local address `[::1]`, a received fatal
TLS alert 80 and BoringSSL reason 1080 (TLSV1_ALERT_INTERNAL_ERROR). This is
local/sinkholed endpoint behavior, not a Chromium certificate-validation
failure. Known hosts are page advertising/measurement resources. Sixteen
connections still need hostname attribution; do not close B-3 yet.

### Runtime findings after checkpoint 3

Rebased onto main `3c7fafc` after all compiler processes exited. Exact protected
path diff now contains App/RoomCore only. The newer AGENTS.md directs sessions
to command-line hooks/logs rather than accessibility/computer-use; remaining
native click/visual checks will be listed for review. No Chapter 2 edits.

A logging-enabled ten-loaded-page quit passed at 8.939 s (load1 44.52), with
28 helpers observed, 0 left, no crash report. This slower result is retained;
clean quit is verified, subsecond latency is not universal.

Harness fixes from first runtime contact: system Bash 3 needs guarded empty
array expansion; Chromium CDP requires text WebSocket messages, not binary
frames. Watchdogs now sleep in a single Python process so cancelling a
watchdog does not leave an orphan sleep. Host typecheck/package passed.

First engine crash: `dialogs`, exit 134. Chrome
`components/constrained_window/constrained_window_views.cc:295` CHECKs
`dialog_host` while creating `JavaScriptTabModalDialogViewViews`;
`GetWebContentsModalDialogHostFor` returned null. Fix in progress: provide an
NSWindow-backed WebContentsModalDialogHost with bounds, observer lifetime and
resize notifications, keeping Views dialogs per PLAN §4. No raw patch needed.

The first modal-host implementation compiled in 24 s but exposed a second
fatal DCHECK at `ui/views/widget/native_widget_mac.mm:589`: a child-modal
Views widget requires a `NativeWidgetMacNSWindowHost` parent; an ordinary
AppKit NSView is insufficient. The current fix adds a transparent,
noninteractive Views child-widget anchor scoped to the Room window, with
explicit resize/move positioning and destruction notifications. Both checks
remain enabled. The component build's non-official default sets
`dcheck_always_on=true`, despite `is_debug=false`; corrected the plan's earlier
assumption. Runtime verification of the bridge is in progress.

The post-CDP shutdown stall was a harness issue: Chromium
`ChromeDevToolsManagerDelegate` deliberately holds REMOTE_DEBUGGING when
`--no-startup-window` and remote debugging are enabled, releasing it through
`Browser.close` (covered upstream by KeepsAliveUntilBrowserClose). A keys-only
control also stalled; its sampled main thread was idle in NSApplication.run.
Feature drives now close via the browser CDP endpoint. The ordinary nav,
open10 and idle/network runs still quit through NSApp.terminate. Watchdog
intervention is explicitly rejected even if SIGTERM leads to exit status 0.
Corrected keys and dialogs drives both exited 0 without the 90 s watchdog.

Modal-host fix verified: three dialog open/close events, page survives, exit 0
without watchdog. Post-fix baseline nav 11.935 s; ten-loaded-page quit 0.442 s
at load1 32.85, 28 helpers observed, 0 left, 0 new crash reports. No patches or
public API changes. Native focus/appearance review remains open.

Private command hook (find/next, zoom in/out/reset, print) now compiles in
19 s; allowlisted and gated by -RoomSpike, no public header change. Nav
passed in 23.827 s. First ten-page quit exited 0 in 6.839 s but failed the
5 s helper grace with 5 helpers; these were gone at follow-up inspection.
Added leftover PID/command evidence to future failed receipts. Unchanged-grace
repeat: 0.431 s at load1 50.53, 10 loaded pages, 28 helpers observed, 0 left,
0 crash reports, exit 0. The rejected cleanup sample remains recorded.
TLS source attribution is now complete for all 88 laptop failures; see
roomcore-tls-audit.md. The historical mini count is not reconstructed.

Permission drive initially exited 139: PermissionPromptBaseView →
GetPermissionPromptBubbleAnchorConfiguration →
bubble_anchor_util::GetPageInfoAnchorConfiguration dereferenced a null
BrowserView. Existing LocationBar::GetChipAnchor is an earlier supported
hook, so no raw patch is needed: return a real Views anchor in the auxiliary
window. An internal forward-declaration compile error was corrected; build
19 s. Permission drive then exited 0 in 16 s; native interaction review still
pending. Idle-before audit began 06:40:58 EEST from a fixed cloned app copy,
so incremental packaging does not mutate the measured executable.

Permission-anchor baseline passed: nav 13.694 s, ten-loaded-page quit 0.647 s
at load1 18.40, 28 helpers observed, 0 left, 0 new crash reports, exit 0.

Find initially exited 139 in FindBarPlatformHelperMac::
UpdateFindBarControllerFromPasteboard because CreateFindBar returned null.
A //room FindBarOwner now supplies the existing Chrome FindBarHost and its
bounds/native parent. The anchor lives through BrowserWindowFeatures teardown
because find widgets retain it. Build 26 s; find/next drive exits 0 in 18 s.
Baseline nav 11.970 s, ten-page quit 2.262 s at load1 15.57, 27 helpers observed,
0 left, 0 crash reports, exit 0. Keyboard/focus and actual matches remain to
be measured; this verifies the formerly crashing command path.

### Network policy work in progress

Switch smoke (60 s) still had 12 requests; feature smoke (30 s) still had 9.
Gaia's AvoidAutoTriggerListAccountsOnStale only moves its initial fetch into
OnNetworkInitialized, so it is not a suppression. GCM persisted only Chrome
policy invalidation project IDs 245350905893/585406161706. Model manifest
component ceofaddefefcbblgcgnibnonglccbfja registers/downloads independently of
--disable-component-update and the model-execution feature. The supported
local manifest override accepts an empty JSON catalog and performs no fetch.

Drafted //room policy using existing service factory seams for browser-account
networking and cloud-policy invalidations. These upstream APIs are named for
tests but do not require or create a test context. Deviation is explicit;
no test fake is linked. Patch 0006 is narrowly justified: the default component
scheduler is constructed directly in BrowserProcessImpl with no factory,
pref, or switch to disable periodic checks while retaining registration and
explicit Widevine updates. --disable-component-update skips registration
(including Widevine), and a huge initial delay would merely conceal traffic.
The new hook selects an on-demand-only scheduler; the original five patches
remain byte-for-byte unchanged. This policy is not built/verified yet.

The next build stopped before compilation because roomcore-apply.sh incorrectly
tried to reapply committed 0006 (Chromium 9fda24ebc9370). Under pipefail,
grep -q can exit early and make git log fail with SIGPIPE. Consume the full
history with grep -xF redirected to /dev/null instead. One retry reported
0 applied, 6 already and completed; no Chromium source failure occurred.

Network policy is now built and baseline-verified (16 s incremental;
nav 23.598 s, ten-page quit 4.240 s, 0 helpers left/0 crash reports).
The last requests were SODA preemptive downloads enabled by developer field
trials. A 30 s smoke with PreemptiveSodaDownload disabled has zero requests,
connections and DNS. Fixed-copy 600 s audit started 07:18 EEST; result pending.

Crashpad checkpoint: build 18 s; both primary and monitor handler commands
use the selected profile/Crashpad directory. Post-fix nav 19.676 s, ten-page
quit 2.591 s, 0 helpers left, 0 new crash reports. B-14 closed for component
build; see roomcore-crashpad-draft.md for the two captured handler PIDs.

Final regression initially stopped on a harness race: the popup CDP target
reported a pending URL before the committed DOM existed. No engine crash.
The driver now waits for matching committed location + readyState complete.
Rerun popup passes; download now verifies exact saved bytes through a CDP-
selected destination. Actual fixture is 26 bytes, including newline; the
previous 25-byte note was a counting error and is corrected in the plan.

## Checkpoint — 2026-10-03 07:29 EEST

- Full idle-after audit passed: 600.0275 s between host timer markers,
  605 s process, exit 0, no watchdog; 0 requests/connections/DNS/TLS errors.
  Before was 62 HTTP attempts, 86 connections and 9 DNS over 600 s idle.
- Final18 regression: all processes exit 0 without watchdog or engine crash;
  fullscreen remains rejected, and native UI completion/appearance/input
  checks remain open under AGENTS.md. Exact 26-byte download verified.
- Crashpad primary/monitor handlers both use selected-root/Crashpad.
- Latest engine baseline: nav 19.676 s; ten loaded pages; quit 2.591 s;
  26 helpers observed, 0 left, 0 new crash reports, exit 0.
- Laptop B-3: all 88 TLS errors attributed by host; local DNS sinkholes and
  fatal TLS alert 80. Historical mini ~220 cannot be mapped without its NetLog.
- Original five patches and public ObjC headers unchanged. Sixth patch adds
  only a justified component scheduler factory hook. Chromium HEAD
  9fda24ebc9370. Main/origin/main remain 3c7fafc; protected diff only App/RoomCore.
- Task is still partial: native feature acceptance, working fullscreen, and
  runtime Widevine first-use behavior are not verified. Next independent work:
  strengthen command-line permission/auth/find/extension completion probes
  and measure Widevine first-use before declaring the feature gate complete.
  Chapter 3 UI contracts are listed with the full surface matrix.

### Completion probes in progress — 07:37 EEST

Added private loopback-only actions (no public headers) to call Chrome's actual
permission Deny, HTTP LoginHandler cancel/supply, and FindTabHelper query.
Build 25 s / 2 steps; packaged. Permissions complete two denials: notification
"denied", geolocation error 1; exit 0, 19 s. HTTP-auth cancellation and valid
credentials both complete and load the fixture, but first process exits 2 via
Chrome's 10 s teardown watchdog. Concurrent baseline nav 20.423 s; ten-page
quit 1.910 s with 9 helpers left after 5 s (rejected). They disappeared by the
next process check; no new macOS crash report. Keep both rejected samples.
Repeat serially, diagnose if reproducible; never count watchdog exit as pass.

Widevine probe confirms NotSupportedError and no CDM download on first use.
Before-policy profile had Widevine 4.10.3112.0; explicit component registration
alone does not implement demand-triggered provisioning. Idle silence passes,
but first-use CDM behavior remains a real gap; see network audit next step.

### Completion-probe checkpoint — 07:45 EEST

Find now observes 400 DOM rows / 400 current-request matches, then next/close;
17 s, exit 0. The probe had to reject stale/early counts (0 and 189).
HTTP auth serial repeats complete cancel + credentials + HTTP 200 in 13 s
and 10 s, exit 0. Native field/anchor/focus review remains.
Latest private-hook build 19 s / 2 steps. Nav 11.274 s. Two serial ten-page
quits pass: 1.209 s (load1 23.93) and 0.742 s (load1 46.18), both 26 helpers,
0 left, 0 new crash reports, exit 0. A third repeat is rejected: Stack Overflow
still loading after the host's 63 s wait, 9/10 loaded. Do not include it in quit
statistics. The earlier concurrent auth watchdog and 9-helper sample remain
known rejected results, not explained away as an engine success.

Next continuation should start at the Widevine provisioning gap, not rebuild
from scratch. The original rebuild, zero-network audit, and Crashpad path are
complete. No compiler is running. Keep public headers and first five patches
unchanged; preserve the original 600 s zero-network result and rerun it after
any demand-update change. Private completion probes and native acceptance
gaps are recorded in spike-results.md; PR remains draft/partial.

### Demand-only CDM implementation in progress — 07:58 EEST

There is no existing per-key-system provisioning hook. Content's EME factory
constructs Blink's client directly; the browser key-system observer receives
all-key capability subscriptions without the requested key name. Downloading
there would also fire for unrelated key systems. Draft patch 0007 adds only
an encrypted-media-client factory pointer and a frame-interface binder hook.
The renderer wrapper and document-scoped Mojo service live entirely in //room;
no public ObjC header changes. Helpers install the factory when the framework
loads because they enter ChromeMain directly.

Only an explicit com.widevine.alpha request invokes the browser service. The
browser checks active document, trustworthy origin and encrypted-media policy;
its interface accepts no component ID or URL. It coalesces callers, waits for
normal registration, uses public ComponentUpdateService::MaybeThrottle (with
Chromium's update cooldown), and waits for actual CdmRegistryImpl registration.
Installed CDMs return without network; failure is bounded and stays Blink's
ordinary unsupported result. No startup provisioning task is scheduled.

First //room compile failures: moved permission-policy namespace/header and
reference-valued interface broker; then private OnDemandUpdater API and lack
of GetComponent on the public service. Replaced those with public MaybeThrottle
and GetComponentIDs; rebuilding. Chromium patch 0007 applied as 0147142699fbc,
original six patches untouched. Runtime verification is still pending.

Link step then failed for three Blink EME implementation symbols referenced
only by new //room code (23 steps done). The implementation lives in the
separate blink_platform_media component, exposed through the public
platform/media GN target. Add that direct dependency and retry once; this is
not an unrelated Chromium source failure. No CHECK/visibility rule is removed.

Demand-CDM build now passes (18 s final link after direct Blink media dependency).
Fresh profile feature-widevine-demand: com.widevine.alpha supported=true,
MediaKeys created=true, Widevine 4.10.3050.0 installed, process 43 s, exit 0.
NetLog: 2 loopback fixture/favicon requests plus exactly 3 external updater
requests (update.googleapis.com 2, edgedl.me.gvt1.com 1); 0 TLS failures.
Latest engine baseline nav 13.512 s; ten loaded pages, quit 0.540 s at load1
14.19, 26 helpers, 0 left, 0 crash reports, exit 0. Fresh-profile 600 s idle
audit started 08:03 EEST from a fixed app copy; negative key-system probe and
final network result remain pending. Receipts name parent commit 2ea76e8;
these measurements test the uncommitted 0007/room_cdm working-tree change.

### CDM registration hook refinement — 08:14 EEST

GN check correctly rejected a private CdmRegistryImpl include even though the
first build linked. Do not relax visibility. Patch 0007 now adds a third tiny
callback at CDM initialization/registration, passing public CdmInfo to //room.
The Room service observes enabled software-secure Widevine registration there.
Chromium patch commit 3095c582bfba9; original six patches unchanged. The final
incremental took 27 s / 15 steps; GN header dependency check passes. Also add
the direct login-handler GN dependency required by the prior auth probe.
Ad-hoc package remains valid, 518 dylibs, 918 MB host.

Final fresh-profile feature-widevine-final: EME and MediaKeys creation pass
in 6.812202 s; 44 s process, exit 0. Five requests total: page/favicon loopback
2, update.googleapis.com 2 and edgedl.me.gvt1.com 1, all external traffic
annotated update_client; 0 TLS failures. This proves provisioning and CDM
instantiation, not licensed playback. A separate final 600 s idle audit is
running against immutable build/roomcore/audit-cdm-final/Room.app. The earlier
implementation's 600 s audit completed in 606 s with 0 requests/connections/
DNS/TLS, exit 0, but is kept distinct from the final callback refinement.

Final CDM engine serial baseline: nav 12.058 s, ten-page quit 0.354 s,
load1 15.50, 26 helpers, 0 left, 0 crash reports, exit 0. All 18 feature
processes survive the repeat; first 17 drives pass and fullscreen remains an
explicit unsupported rejection (its driver correctly fails). Unrelated EME
key rejects in 2.342 ms without external requests; installed-profile reuse
creates MediaKeys in 2.099 s without external requests. Forced updater DNS
failure gives bounded NotSupportedError after 60.163 s, clean process exit.

The concurrent teardown investigation found a new, separate FedCM bubble
parent DCHECK during open10, before readiness. Auth itself passed in 11 s.
This does not invalidate the recorded serial sample, but baseline reliability
is not complete. See roomcore-shutdown-investigation.md for exact call sites
and the older IO-thread watchdog stack; neither failure is dismissed.

08:24 EEST checkpoint: final demand-CDM 600 s audit completed, exit 0, no
watchdog, 0 HTTP requests/connections/DNS/TLS. Eight net-log parser tests,
GN dependency check and shell syntax pass. Apply reports 0 applied, 7 already.
Main/origin-main remain 3c7fafc; protected diff is only App/RoomCore, original
five patches and public ObjC headers unchanged. Saving the demand-CDM fix
separately before the new FedCM parent fix; the latter remains open.

### FedCM failure from live open10 — fix in progress, 08:31 EEST

The original 18-drive matrix missed federated sign-in. A concurrent auth /
baseline repeat reached webid::FedCmAccountSelectionView::CreateDialogWidget
with no bubble anchor and aborted at bubble_dialog_delegate_view.cc:207.
The existing retrieval seam is typed as views::WebView; Room owns a Cocoa page
view, and registering an empty fake WebView would mislead other consumers.
Patch 0008 adds a single anchor hook used for the passive bubble and active
modal native parent. //room returns its existing Views anchor only for tracked
RoomBrowserWindow instances; fallback Chrome windows retain their default.
Original seven patches/public headers unchanged. Chromium 1d6a6abe5bcd2.

First build: 24 s / 4 steps, package valid. New private -RoomSpike fedcm probe
reaches the real IdentityDialogController and reproduced a second crash:
TabDialogManager::ShowDialog dereferences a null GetHostWidget (line 360).
Room never initialized BrowserElementsViewsImpl with its Views context.
Initialize through the existing Init(view) seam when the modal bridge is
created, keeping its normal teardown ordering. No extra patch for this.
The probe separately opens/closes a passive failure bubble and an active
loading modal (active failure UI itself falls back to a bubble upstream).
GN check also found missing direct LocationBar and identity-controller
dependencies; adding them rather than weakening header checks. Rebuilding.

FedCM fix verified: passive failure bubble and active loading modal both return
true, close and exit 0 (18 s). Full //room GN header check passes. Baseline nav
12.447 s; ten-page quit 0.635 s, load1 28.40, 27 helpers / 0 left / 0 crashes,
exit 0. Shared dialog/permission/find regression passes in 8/8/10 s. Saving
this as a separate fix. Another 600 s fresh-profile audit is running from a
fixed copy with the final FedCM engine (netlog-idle-fedcm); the demand-CDM
checkpoint's completed audit remains the current proven zero-network result.

### Extension lifecycle probe — 08:42 EEST

Extended the existing worker/content-marker probe with real chrome.tabs.query,
create/remove, chrome.windows.create/remove and action.openPopup calls. The
first attempt failed cleanly: "Tabs cannot be edited right now (user may be
dragging a tab)." Chrome's ExtensionTabUtil checks IsTabStripEditable across
browser windows; Room's generated stub always returned false. Move that
method into the implementation: allow edits on a non-closing TabStripModel,
while honoring DisableTabStripEditingForTesting. The Cocoa host does not run
Chrome's TabDragController; Chapter 3 host drag suppression remains a future
contract. No new patch or public ObjC API. Build/probe in progress.

08:43 EEST: the post-FedCM full audit completed: 600 s idle / 610 s process,
18 events / 603.051 s event span, 0 HTTP/connections/DNS/TLS, exit 0 and no
watchdog. The fixed copy's engine code is 2a04498, preceding only the tab-edit
correction now building. Network policy is unchanged. The full original 18
plus FedCM regression on 2a04498 completed without process crashes; fullscreen
remains unsupported (driver failure), all other drivers passed.

Tab editing correction verified: extension count 1→2→1, popup create/remove,
exit 0 in 24 s. Action popup initially could not find an active browser window;
focused-window probe is pending. Build 22 s / 6 steps; GN all //room passes.
Post-change nav 11.570 s; ten-page quit 0.534 s, load1 12.39, 24 helpers / 0
left / 0 new crashes, exit 0. Network policy and patches are unchanged.

Focused-window extension action repeat: lifecycle still passes; action popup
returns an inactive-window error even after awaiting windows.update(focused).
Do not call the action UI verified. Next independent work can inspect the
native activation/BrowserActiveStateManager handoff, then download cancellation
and certificate-leave callbacks; retain the old teardown failure separately.

### Explicit native activation — 08:54 EEST

Chromium's NativeWidgetNSWindowBridge activates NSApp before making a window
key; its source documents why the reversed/incomplete sequence can leave
Widget::IsActive false. Room Activate lacked the application step. Add the
same activation before makeKeyAndOrderFront, retaining the existing active
browser manager notification. No patch/public API changes.

Build 20 s / 2 steps; extension process 18 s, exit 0. AppKit now reports
applicationActive/windowKey/windowMain/canBecomeKey/visible all true. Actual
chrome.action.openPopup advances from inactive-window failure to the precise
remaining error: "Browser window has no toolbar." No dummy toolbar is added;
Chapter 3 must own the action UI. Tabs 1→2→1 and popup create/remove still pass.
Baseline nav 11.419 s; ten-page quit 0.549 s, load1 11.05, 26 helpers / 0 left /
0 new crashes, exit 0. CI checks for prior checkpoint both pass (74/92 s).

08:58 EEST: stronger completion probes all pass on eb55062. Download cancelled
after server sent 131,072 / 33,554,432 bytes; canceled GUID event, only the
26-byte completed fixture remains (17 s process). Certificate authority error
and real interstitial leave back to safe fixture (11 s). Beforeunload canceled
and original page preserved (16 s). Muted Web Audio oscillator advances
0.261333 s at 48 kHz and closes (11 s). All exit 0; native interaction boundaries
remain. Corrected consolidated report's stale latest-baseline row to 11.419 s
nav / 0.549 s quit. No new network policy or patch changes.

### Shutdown reproduction checkpoint — 09:15 EEST

The bounded three-browser / ten-page exercise reproduced two 10 s watchdog
exits (all pages loaded); a third was rejected for Stack Overflow still
loading. Live samples show network-service process wait before the final
watchdog stacks. One targeted helper capture then passed slowly at 6.017 /
5.691 s and showed network-service ThreadPool shutdown waiting while two
workers were still setting their initial macOS QoS. This narrows the
investigation without proving a cause or a production fix. Details, matching
UUIDs and rejected samples are in roomcore-shutdown-investigation.md. Added
failure.json evidence to the quit runner; actual exit-2 fixture and Python
syntax checks pass. No engine/network/patch changes in this checkpoint.

09:32 EEST diagnostic checkpoint: a longer helper capture passed all three
Room ten-page quits at 5.474 / 2.919 / 6.969 s (0 helpers/crashes). Native QoS
calls did not reproduce delay (background max 0.238 ms). Installed Chrome
control quit under 1 s but all three had NYTimes still loading and are rejected.
Same-component stock-window control obtained one complete ten-page quit in
1.091 s; two setup timeouts are rejected. No configuration reproduced another
watchdog and no root cause is claimed. Reproduction sources and preparation
failures are documented in roomcore-shutdown-investigation.md. No engine,
patch, policy, public API or protected Chapter 2 edits. CI passed 70/78 s.

09:54 EEST: targeted teardown logging reproduced helper-grace failures,
including with network-only sampling. Captured leftover renderer waits on
GPU-channel disconnect while its IO thread deallocates Mojo Mach VM. Sampling
can affect timings; no root-cause claim or production scheduling change.
A diagnostic --disable-gpu run uncovered a separate host crash: Blink renderer
loss enters SadTabController, which DCHECKs on Room's absent BrowserView.
Next work is renderer-crash containment/reload, not disabling GPU. Details and
all rejected samples are retained in roomcore-shutdown-investigation.md.

Renderer recovery fix: SadTab::Create directly constructs a
SadTabController, and neither SadTab nor SadTabHelper exposes a replacement
factory. New patch 0009 adds only a nullable factory hook; //room installs a
Cocoa fallback for tabs owned by tracked Room windows. Chrome fallback windows
retain SadTabController. SadTabHelper owns/removes the fallback through its
existing renderer-ready lifecycle. A private local-fixture probe checks
intentional Page.crash, continued host operation, and reload/overlay removal.
Public ObjC headers and the original eight patches are unchanged.

10:04 EEST: intentional renderer crash/reload passes in 39 s, exit 0.
CreateSadTab first-hit logging is present; private status reaches crashed +
fallback (3), then loaded + no fallback (0). Page.crash disconnects its own
CDP socket as expected; the host reconnects after reload. No public API added.
The receipt names pre-commit 781cf1e; the tested dirty source is this fix.
First incremental failed in //room on deprecated NSBox.borderType (19 s);
use borderWidth=0. Final build 22 s / 3 steps, load 21.29/34.83/46.76,
nice 0/default jobs; GN check passes. Package remains strict-valid ad hoc,
518 dylibs, 918 MB app. Baseline nav 21.170 s; ten loaded pages quit 0.554 s,
load1 18.00, 26 helpers / 0 left / 0 new crashes, exit 0, no sampling.
Original patches 0001–0008 are unchanged. Apply reports 0 applied, 9 already;
Chromium HEAD 0811f471258ac. Network policy is unchanged; the last 600 s audit
belongs to engine 2a04498, not this new binary. The original concurrent
shutdown failure remains open; renderer containment does not fix its cause.

10:18 EEST: deterministic loopback shutdown controls completed. Three Room
browsers each loaded ten storage/cache/canvas fixtures; quits 1.028/1.596/2.336 s,
0 helpers left/0 crashes. Same-current-component stock window entry completed
three at 5.107/3.790/4.585 s, also clean. No stack sampling. Different host
setup/termination paths and machine load forbid a performance ranking; these
are controls, not the required real-site baseline. No engine or network
policy change, no new hook. Test-only host rebuild 8.6 s, signature valid;
Python/Node checks pass. CI0f87b84 passed78/81s. B-16 remains open. A final
600-second fresh-profile idle audit on the current package is started under
netlog-idle-sadtab-final; its result is pending, not counted as passed.

Audit launch correction: detached launcher 86596 ended before an app or idle
marker appeared (only an empty netlog-idle-sadtab directory). No audit result
is inferred. Restarted once in managed execution session 96817 with a fresh
netlog-idle-sadtab-final directory; browser PID86910 is nice0, idle-start
1791012022.020894 (10:20:22 EEST), 600 seconds requested. Both Crashpad handler
commands again point into this selected profile's Crashpad directory.

10:35 EEST: final current-package idle audit passed. netlog-idle-sadtab-final:
600 requested idle seconds, 601.491092 s idle-start→terminate, 614 s process,
18 NetLog events / 600.419 s span, 0 HTTP / connections / DNS / TLS, exit0.
No compiler/test/helper remains. CI e5ad547 passed75/83s. Engine0f87b84 and
hosta4f8c25 are now covered by this complete fresh-profile measurement.

10:43 EEST: process-census diagnostic checkpoint. Thirty full ps listings
cost 1.771 s wall / 1.717322 s child CPU. Optional 250 ms census interval passed three
real-site quits 5.010/3.331/3.930 s; original cadence on the same package then
reproduced three watchdogs (two non-loading ten-page fixtures, one still loading).
Census cost 27 s versus48–50s per runner; load/swap/live-site differences forbid
causal attribution. Preserved exact audit-sadtab package and symbolized all
three dumps: two network-service waits, one ThreadPool shutdown. No engine,
network, public API, patch, timeout, grace or default cadence change. B-16
remains open; next useful work is a lower-overhead process observer validated
against child/PID lifecycle, not another blind stress loop.
