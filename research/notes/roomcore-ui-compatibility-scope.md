# RoomCore UI compatibility pass — agreed scope, 2026-10-03

## Objective

Establish the concrete Chromium UI hosting requirements for Chapter 3 through
one bounded compatibility pass in the existing RoomCore spike host. Exercise
the real feature paths, fix small demonstrated integration defects, and hand
off the larger ownership/API requirements with reproducible evidence.

This replaces the previous broad hardening/shutdown investigation as the
active Goal. The deliverable is an evidence-backed compatibility assessment
and narrow fixes, not a completed Chapter 3 browser UI. The existing
[22-family audit](roomcore-ui-surface-audit.md) is the inventory; it is not
evidence that these features work. The original18 drives remain historical.

## Six work packages

| Order | Package | Required exploration and evidence |
|---|---|---|
| 1 | Autofill and credential bubbles | Reach real address suggestion/save/update and password save/update presentation using synthetic local data. Record handler, parent/anchor, accept/cancel and owner-destruction behavior. Card-save is a local synthetic boundary probe only; no payment or account upload. Separate suggestions from save bubbles. |
| 2 | Permissions, device choosers and connections | Drive web USB/HID/Serial/Bluetooth chooser open/cancel or a concrete enabled-feature blocker, with empty/fake devices. Cover extension-origin chooser separately. Map local/loopback-network permission to actual enabled paths and origin/grant lifetime; retain existing auth/certificate results instead of repeating them. Identify OS permission and real-device acceptance requirements. |
| 3 | Print preview and docked DevTools | Treat these as two independent results. Trigger real Chrome print preview, generated preview pages, cancellation/reopen and temporary PDF output if reachable. For DevTools, reach the frontend and inspect docking, resize, undock/redock, focus and inspected-tab close. IDC_PRINT survival, Page.printToPDF and CDP connectivity are not substitutes. |
| 4 | Extension action UI | Reach a real MV3 action popup from the Room-owned window; establish content ownership, anchor, focus, resize and close behavior. Source-map installation/site-access consent and side-panel dependencies for Chapter3; no full extension manager implementation. Tabs/windows probes already passed and need not be repeated unless affected. |
| 5 | Media and capture | Drive camera/mic and screen-share denial/cancellation without real capture by default. Use generated local audio/video and synthetic media devices for playback, mute/audible state and capture lifecycle where available. Investigate persistent recording/sharing indicators and stop callbacks, video/document PiP, and fullscreen boundaries. Map output selection/media keys; preserve native/hardware acceptance gaps. Reuse existing Widevine provisioning evidence; licensed playback is outside this pass. |
| 6 | Downloads and file dialogs | Exercise the missing close-with-pending-download decision, destination/file-picker cancellation and owner destruction. Reuse verified download bytes/cancel evidence. Use isolated temporary files for ordinary file input and filesystem permission boundary probes. Record persistent progress/cancel/revoke requirements; do not build Room's download manager. |

## Method and stopping rules

- Start with the known missing contract and one controlled fixture. Prefer
  loopback pages, synthetic records/devices and actual Chrome controllers.
  Each executable probe has a timeout and cleans up only its own processes,
  profiles and temporary files. Preserve failed receipts and crash evidence.
- Per distinct feature path: one initial drive, then at most two targeted
  repair/verification rounds. Each round must name a new source-backed
  hypothesis or a specific fix. No repeated stress loops or clean runs merely
  to accumulate a reassuring count. A failed setup is not a feature pass.
- If a shared bridge fixes several paths, verify each affected path once.
  Do not copy the same bridge into several controllers. Prefer existing
  hooks and Room code; a tiny upstream hook needs a written no-existing-hook
  justification. Preserve the first five patches and public ObjC headers.
- Stop work on a path when it works in the spike, or when a concrete boundary
  requires Chapter3 API/product ownership, native interaction, unavailable
  hardware, or more than a narrow compatibility fix. Record the trigger,
  source location, observed failure, exact missing contract and next step,
  then continue with independent packages. Do not call that feature supported.
- Fixing a crash is not finishing the UI. Verify the requested callback/result,
  close/cancel behavior and owned object lifetime where command-line probes
  can observe them. Tab navigation/destruction must not strand a decision.
- Build and rerun the focused regression plus nav/ten-loaded-page serial quit
  after every engine fix. Failed/rejected baselines stay failures. If a new
  fix regresses the baseline, repair narrowly or withdraw that fix while
  preserving evidence; do not broaden into shutdown research.
- Repeat the complete600-second idle audit only if this pass changes network
  policy or adds a path that can start unsolicited activity. Otherwise retain
  the exact package identity of existing audit evidence without relabeling it.
- Provide concise updates on discoveries, fixed defects and blocked contracts.
  Final reporting is a compact results matrix; raw logs remain artifacts.

## Out of scope

- Chapter3 public API design/implementation, EngineRoomCore product migration,
  polished native presentation, toolbar/sidebar design, full settings or
  extension/download managers. Describe necessary contracts instead.
- The earlier concurrent shutdown issue (historically B-16 in this branch),
  scheduler/QoS experiments, broader stress/benchmark work and rebuilding the
  original completed component build. Preserve findings for later work.
- Enabling real camera/microphone/screen capture, connecting to arbitrary
  attached devices, sending hardware commands, pairing, printing to a physical
  printer, entering real credentials, payments or licensing-service work.
  Their native/device acceptance requirements must remain explicit.
- Accessibility/computer-use driving. Follow AGENTS: CLI/private test hooks,
  source inspection and output/log reading; native checks go to the reviewer.
- Expanding into every inventory row. Cast, account/sync, cloud services,
  Chrome promotions, full passkey UX and optional browser features remain
  design inputs unless required to explain a scoped boundary.

## Workspace and checkpoint rules

Use /Users/j/.codex/worktrees/35bc/room on bg/roomcore-hardening. Allowed edits:
Engine/roomcore/, scripts/, App/RoomCore/, research/notes/, docs/engine-api.md
and docs/backlog.md. Never edit protected Chapter2 files, push main or merge.
Inspect actual processes before touching //room; never edit while compiling.
Use the existing out/dev build and ad-hoc package with mock keychain.

Before engine work, preserve and isolate the local patch0011 shutdown candidate
and its modified diagnostic source. It is not part of this Goal and must not
be silently bundled with UI fixes. Record exact source/package identities;
do not test a preserved package while claiming it contains new source changes.
The candidate's latest comparison still failed helper cleanup; it is not a
completed shutdown fix.

Main advanced after the last rebase. Reconcile only when compiler/tests are
stopped and local candidate work is safely preserved. Retain main's Chapter2
changes and resolve the duplicate B-16 identifier if editing the backlog.
Verify branch scope from merge base and final direct-main scope separately.

One coherent commit per fix, phase-bg prefix, no trailers. Push checkpoints to
bg/roomcore-hardening and update the existing draft PR1; no new scheduled task.
Measurements and justified deviations live under research/notes/.

## Completion criteria

Create research/notes/roomcore-ui-compatibility-results.md with one row per
required subfeature, grouped into the six packages. Each row contains:

- actual fixture/command, source and package identity;
- observed result and duration/crash/exit/callback evidence where run;
- status: works in spike, fixed and reverified, or blocked/deferred with a
  concrete reason (never substitute a source-only claim for a runtime pass);
- reused Chrome surface, Room parent/anchor/content ownership requirement;
- smallest implementation/public-contract requirement for Chapter3;
- native/hardware verification still required.

All six packages must be explored. A documented architectural/hardware boundary
can finish that investigation row; a vague “untested” cannot. Source-mapping
only is acceptable for the explicitly source-map items in the table, or when
a reproduced/verified prerequisite prevents the runtime drive.

The Goal is complete when the bounded pass and result matrix are finished,
accepted narrow fixes have passed their baselines, work is committed/pushed,
PR1 is updated, and the Chapter3 handoff clearly separates working spike
behavior from product work and unavailable native acceptance. It does not
require resolving the old shutdown issue or delivering every Chrome feature.
