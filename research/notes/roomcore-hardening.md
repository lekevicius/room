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
