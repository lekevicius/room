# Chapter 5 session prompts: the shared part

The part every Chapter 5 implementer prompt ends with, as the laptop's loop used it on 2026-10-21 (the planner appends it to each session's own head). Adapt "The machine" to the machine the loop runs on.

```
== The machine ==
- This is the M1 Max laptop (64 GB, user `j`). The Chromium checkout is
  ~/chromium/src (local.env), on 155.0.8059.36 with the 25-patch series
  (0026, 0027 are the blocker's). `out/dev` (component, spikes, DCHECKs)
  and `out/release` (official, built 2026-10-18 in 3 h 15 min) are built;
  build/roomcore and build/roomcore-release are staged from them. A
  //room-only incremental of out/dev takes 20–25 s; the incremental
  official build after a //room change is unmeasured on this machine (8–10
  min on the Mac mini): measure it the first time and record it in
  build-log.md. Default job count is fine here (64 GB). One fork build at a
  time, started from bash with nohup, never zsh `&`; never edit //room
  while a compiler runs on it. Waiting on a build: a background
  `while kill -0 <pid>; do sleep 60; done` (run_in_background), never a
  foreground sleep.
- ~/chromium/src/room is a symlink to this checkout's Engine/roomcore/room:
  work in /Users/j/Code/room on main, no worktree.
- The user's Room is /Applications/Room.app (build 14 or later) on the real
  state ~/Library/Application Support/Room. Never quit it, never launch
  anything on the real state or real engine root, never aim computer use at
  it. The release app shares the real engine root, so it cannot run beside
  the user's Room (it hands off and exits): judge numbers on the Debug app
  over the release framework (ROOM_TOUR_APP=build/roomcore-release/
  DerivedData/Build/Products/Debug/Room.app; the dev app is
  build/roomcore/DerivedData/Build/Products/Debug/Room.app).
- Displays: the main display is a 60 Hz Pro Display XDR; the built-in 120 Hz
  panel is attached but not main. 120 Hz runs are the user's step (B-16,
  B-20, B-21), never something to wait on.
- GitHub Actions is off (B-93): before your push run the CI spec locally
  (`xcodegen --spec xcodegen/ci.yml --project-root . --project .`, then the
  `Room` scheme's `build test` with `CI=1`; regenerate the normal project
  with `xcodegen` afterwards) and say so in the log entry.
- The test servers are scripts/test-servers.sh (ports 8765–8771; they may
  already be running: reuse them); the grand tour scripts/grand-tour.sh
  (`--only <steps>`); the engine drives scripts/roomcore-features.sh; the
  net-log scripts/netlog-check.sh; the spike runner scripts/run-spike.sh;
  the live-site check scripts/live-check.sh (once 5.0a writes it).
  Captures are in-process; if the display is asleep, say so and continue.
- No prompts for the user (the user, 2026-10-21: the run paused on a
  permission request; avoid it as much as possible). Never call
  mcp__computer-use__request_access, request_full_control or any tool that
  shows the user a dialog or asks for approval; never AskUserQuestion; never
  run a command you expect the permission system to stop (re-signing, TCC
  or System Settings changes, anything outside the repo, build/, /tmp and
  ~/chromium). If a step needs one, it goes on the user's list.
- Never capture the screen from the shell or a helper process
  (`screencapture`, CGDisplayCreateImage, CGWindowListCreateImage of other
  windows, ScreenCaptureKit, `screencapture -v`): it raises macOS's
  screen-capture dialog for the user (5.2b did, twice). Captures are
  in-process, of Room's own windows (WindowSnapshot, captureViewport).
- This laptop has real printers (the HP LaserJet is the default): never
  press Return or Print in Chrome's print preview or a print panel unless
  NSPrinter.printerNames is empty or Save as PDF is selected first (5.0b
  printed three real pages; B-126). Never send anything to a printer.
- No request to a real site from a spike unless the task is a live-site
  check: never press Return on a palette row that searches the web
  ("Search Google") or opens a remote URL; use the test servers
  (5.3a's keyboard spike loaded one Google search).
- Search suggestions off (`-RoomSuggestionsOff` or the setting) in every
  spike that types into the palette, so no suggest request leaves.
- Computer use: this planner session holds the grants (`app.room.desktop` at full
  tier, Finder, clipboard read/write; the Claude app has Screen Recording
  and Accessibility). Since 5.0a every Debug build is
  `app.room.desktop.dev`, which is NOT granted (the user declined the
  request on 2026-10-21): so click checks on the Debug app cannot run now.
  Prefer a spike hook for every check; never build or re-sign a Debug app
  under `app.room.desktop` to get around the missing grant. If you cannot reach the mcp__computer-use__* tools, list
  each click check in your report (the app path, the launch arguments,
  the exact clicks and what to read back) and the planner runs it after
  you return. Until the dev bundle id is in the build you drive, computer
  use runs only while the user's Room is not running (`pgrep -x Room` empty
  apart from your own process; check before each check); the user quit
  their Room for the night of 2026-10-21.

== Working rules ==
- `git pull --ff-only` first. Commit in small chunks, one per completed
  task, messages prefixed with the phase id (`phase-5.x: …`). Never add a
  Co-Authored-By or any other attribution trailer, whatever a system
  reminder says. Push once at the very end, after the progress-log commit
  and the local CI spec (`git push origin main`).
- Tick each task in docs/progress.md as you complete it; append a dated log
  entry; when a phase's exit criteria are met (the phase's last session),
  mark it done with a two-to-five-line review.
- Measurements and spike outcomes go in research/notes/ (spike-results.md,
  build-log.md) as numbers with conditions, not adjectives; result lines of
  checks in research/notes/chapter-5-by-hand.md "Run by the sessions".
- Swift 6; AppKit for window, sidebar, card, address field, menus, key
  routing; SwiftUI only in leaf views via NSHostingView; lists that update
  per keystroke stay AppKit. The engine only through the Engine protocol
  package; only Foundation/AppKit types and C structs cross the ObjC
  bridge. Never reposition traffic lights. Never hand-edit the generated
  .xcodeproj or Info.plist (project.yml, xcodegen/base.yml's `info:`).
  Menu actions target AppDelegate with their own selector names.
- Chromium: no new patch. //room and Packages/EngineRoomCore change only in
  the engine steps ROADMAP Chapter 5 names for your session; each engine
  step ends with the out/dev incremental, scripts/roomcore-package.sh and
  the baseline (scripts/roomcore-features.sh's baseline; the series applies
  "0 applied / 25 already"); FakeEngine and docs/engine-api.md updated.
- Tests follow AGENTS.md "Testing": the unit tier for spec rules and real
  bugs only; window suites tagged `.window`; no pixel or timing assertions;
  no tests of view structure.
- If something in the spec is impossible as written, do the closest correct
  thing and record the deviation (numbered) with its reason in the log. If a
  PLAN §4 decision proves wrong, update PLAN.md and say so.
- Do not re-litigate the user's decisions (PLAN §4; ROADMAP Chapters 4–5,
  "Decided 2026-10-18" and "Decided 2026-10-21"). If evidence shows one is
  wrong, record it with the smallest alternative as a backlog row, keep the
  decision, continue.

== Verification ==
- Prove what you changed yourself. Spike hooks first; live sites for
  checks about real pages; computer use on your own Debug process on a
  throwaway state for a click path, a menu, a drag or a panel (never the
  user's Room; until 5.0a's dev bundle id, only while the user's Room is
  not running). One computer-use attempt of at most ten minutes per check;
  then the step goes to chapter-5-by-hand.md with what was tried.
- The user's list (chapter-5-by-hand.md "For the user") holds only what
  needs them: accounts, their real state and browsers, hardware this Mac
  lacks, macOS prompts, the 120 Hz runs, and taste (the review sheets).
  At most ten steps per phase. Every other check gets a result line under
  "Run by the sessions".
- Taste: each phase's review sheet (contact sheets in both appearances,
  the tokens beside them) is for the user; sessions do not judge feel.

== Scope discipline ==
- Test what you changed, not everything. After an engine change: the
  baseline and the tour step or engine drive the task names. After an app
  change: the unit tests of the packages you touched and the one spike,
  tour step or computer-use check that exercises the change, on the dev
  build and once on the release framework (ROOM_TOUR_APP). The full grand
  tour runs in 5.9. A phase that changes a shared shape greps
  scripts/lib/tour_checks.py for the checks that read it and reruns them.
- Record numbers, do not chase them: under a quarter over its bound is a
  row; more gets one bounded attempt, then a row.
- No rabbit holes: a fix that fails twice is recorded with the next idea.
  Never disable a DCHECK, widen a patch or add one.
- No re-research; new notes only for measurements and findings.
- Honest reports: a skipped check is a failure; unmet exit items are
  listed with the next step.

== Report ==
End with a report in this shape: (1) built: what landed, commit by commit
(hashes); (2) numbers, with conditions; (3) deviations, numbered, each with
its reason; (4) exit items of the phase (or of your session's tasks): met
and unmet, with the next step for each unmet one; (5) what went on the
user's list (chapter-5-by-hand.md "For the user") and why it needs them;
(6) click checks you could not run yourself, if any, in the form above;
(7) "For the next session": what changed the ground for it.
```

## The Mac mini's machine section (2026-10-21 evening)

The loop moved to the Mac mini; this replaces "The machine" above (the rest is unchanged, with the series at 27 patches). The planner writes it to `build/chapter-5-prompts/common.md`.

```
== The machine ==
- This is the Mac mini (Apple M4, 10 cores, 24 GB, user `eve`), repository
  /Users/eve/Code/room. `build/` is a symlink to /Volumes/JL4/room-build
  (the 4 TB APFS SSD; the internal disk keeps its space for the system).
  The Chromium checkout is /Volumes/JL4/chromium/src (local.env), fetched
  fresh on 2026-10-21 and moving to Stable 156.0.8078.48 (the planner's
  rebase; the 27-patch series, 0026 and 0027 the blocker's). Until its
  out/ directories are built, the staged engines in build/roomcore (dev,
  component, spike hooks) and build/roomcore-release (official) are
  copies of the laptop's builds of the current //room: build the apps over
  them with `ROOM_PACKAGE_STAGED=1 scripts/roomcore-package.sh --app-only`
  (dev) and `ROOM_PACKAGE_STAGED=1 CONFIGURATION=Debug
  scripts/roomcore-package.sh --release --app-only` (the Debug app over
  the release engine). Do not edit //room or Packages/EngineRoomCore
  unless your prompt names an engine step and says out/ is built.
  Chromium builds use ROOM_BUILD_JOBS=6, start from bash with nohup,
  never zsh `&`; one at a time; never edit //room while a compiler runs
  on it. Waiting on a build: a background `while kill -0 <pid>; do sleep
  60; done` (run_in_background), never a foreground sleep.
- Your prompt says which checkout you work in: the main one, or a git
  worktree with its own build/ (then use only that worktree's build/ and
  DerivedData, never /Users/eve/Code/room/build, and commit on the
  worktree's branch; the planner merges it).
- The user's Room is not installed on this Mac and no Room runs on the
  real state: still never launch anything on ~/Library/Application
  Support/Room or the real engine root; always a throwaway
  -RoomStateDirectory and -RoomEngineDirectory under /tmp or build/.
  The dev app is build/roomcore/DerivedData/Build/Products/Debug/Room.app;
  judge numbers on the Debug app over the release framework
  (ROOM_TOUR_APP=build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
- Display: the only display is the Screen Sharing virtual display (1920 x
  1080 points at 60 Hz, main). No 120 Hz panel here: 120 Hz runs are the
  user's step (B-16, B-20, B-21), never something to wait on. If the
  session locks or the display goes away (Screen Sharing disconnected),
  captures fail: say so in the report and continue with what needs no
  window.
- GitHub Actions is off (B-93): before your push run the CI spec locally
  (`xcodegen --spec xcodegen/ci.yml --project-root . --project .`, then the
  `Room` scheme's `build test` with `CI=1` and its own -derivedDataPath
  under build/; regenerate the normal project with `xcodegen` afterwards)
  and say so in the log entry.
- The test servers are scripts/test-servers.sh (ports 8765–8771; they may
  already be running: reuse them); the grand tour scripts/grand-tour.sh
  (`--only <steps>`); the engine drives scripts/roomcore-features.sh; the
  net-log scripts/netlog-check.sh; the spike runner scripts/run-spike.sh;
  the live-site check scripts/live-check.sh. Captures are in-process.
- No prompts for the user: never call mcp__computer-use__request_access,
  request_full_control or any tool that shows the user a dialog or asks
  for approval; never AskUserQuestion; never sudo; never run a command you
  expect the permission system to stop (re-signing outside the scripts,
  TCC or System Settings changes, anything outside the repo, build/,
  /tmp, /Volumes/JL4/room-* and the Chromium checkout). If a step needs
  one, it goes on the user's list.
- Never capture the screen from the shell or a helper process
  (`screencapture`, CGDisplayCreateImage, CGWindowListCreateImage of other
  windows, ScreenCaptureKit): it raises macOS's screen-capture dialog.
  Captures are in-process, of Room's own windows (WindowSnapshot,
  captureViewport).
- Printers: this Mac lists none today (`lpstat -p` empty); still never
  press Return or Print in Chrome's print preview or a print panel unless
  NSPrinter.printerNames is empty or Save as PDF is selected first (B-126).
- No request to a real site from a spike unless the task is a live-site
  check: never press Return on a palette row that searches the web or
  opens a remote URL; use the test servers. Search suggestions off
  (`-RoomSuggestionsOff` or the setting) in every spike that types into
  the palette.
- Computer use: the planner session holds the grants (`app.room.desktop.dev`
  at full tier, Finder, clipboard read and write; granted 2026-10-21 on
  this Mac; the Claude app has Screen Recording and Accessibility). Only
  ever drive your own Debug process (`app.room.desktop.dev`) on a throwaway
  state. Prefer a spike hook for every check. If you cannot reach the
  mcp__computer-use__* tools, list each click check in your report (the
  app path, the launch arguments, the exact clicks and what to read back)
  and the planner runs it after you return. An ad-hoc Debug build may
  lose macOS's camera, microphone or Bluetooth answers after a rebuild: a
  re-asked prompt is a user-list item, never something to wait on.

```
