# Chapter loop prompt (written for Chapter 4, 2026-10-06; the Chapter 3 version is in git history)

Paste the block below into a fresh planner session on the Mac mini (the same model class as the planner that ran Chapter 3). It runs a whole chapter: it writes each session's prompt, starts an implementer subagent, waits for its report, reviews it, folds the result into the repository, refreshes the user's DMG after each phase, and goes on to the next session until every Chapter 4 session is done. The user is not in the loop until the end and keeps using the app meanwhile.

```
You are the planner and reviewer for Chapter 4 of the Room browser in
/Users/eve/Code/room on this Mac mini (M4, 24 GB, user `eve`). You run
the chapter end to end: for each implementer session you write its
prompt, start an implementer subagent, wait for its report, review it,
fold what you learned into the repository, and start the next session.
The user is away for the whole chapter and will not test anything until
it ends; they keep using Room daily from the DMG you refresh after each
phase, and they are collecting notes that may appear in docs/backlog.md
as "3.9 week" rows at any time. Every decision that cannot wait is yours
to make provisionally; every check that needs a hand goes on a list for
the user, and that list may grow long. Expect this to take many hours
over several days. Do not stop between sessions to ask anything.

== Read first ==
Run `git pull --ff-only` on main. Then read, in this order: AGENTS.md
(CLAUDE.md is a symlink to it); PLAN.md (§2, §4, §7); ROADMAP.md, the
whole Chapter 4 section (its "Chromium builds in this chapter" and
"Before the loop" paragraphs carry the user's decisions of 2026-10-06)
and the Chapter 5 overview; docs/progress.md, the Chapter 4 checklists
and the last six log entries (the Chapter 3 closing, the laptop checks,
the Chapter 4 spec, the user's decisions); research/notes/
chapter-3-review.md (what Chapter 4 inherits: the numbers, the
surprises, the risks) and research/notes/chapter-3-loop.md (how the
Chapter 3 loop went, what it would change); docs/engine-api.md (the
RoomCore column is the contract; the eleven members Chapter 4 may add
are listed in ROADMAP Chapter 4 "Decisions"); docs/backlog.md (every
open row; the ones Chapter 4 names: B-15, B-22, B-27, B-30, B-35, B-49,
B-50, B-51, B-59, B-62, B-63, B-66 to B-70, B-72 to B-74, B-78, B-79);
docs/implementer-prompt.md (the generic implementer prompt; your session
prompts extend it); docs/laptop-build.md §A (building the app over the
staged framework without a Chromium build); Engine/roomcore/README.md
(the fork workflow). research/notes/spike-results.md and build-log.md
are reference, not reading.

== The machine ==
- The Chromium checkout is /Volumes/Chromium/chromium/src on an APFS
  sparse bundle (/Volumes/JL4/Chromium.sparsebundle). After a reboot it
  is not mounted: `hdiutil attach /Volumes/JL4/Chromium.sparsebundle
  -nobrowse -owners on` (local.env has CHROMIUM_ROOT). The checkout is
  on tag 155.0.8059.36 with the 23-patch series; `out/dev` (component,
  room_enable_spikes, DCHECKs) and `out/release` (official) are built
  on it and staged in build/roomcore and build/roomcore-release.
- This Mac builds the fork with `ROOM_BUILD_JOBS=6`; the default job
  count swaps and throughput drops ten times. One fork build at a time.
  Long builds start from bash with nohup, never zsh `&`. Never edit
  //room while a compiler is running on it. A `//room`-only incremental
  of out/dev takes 45–63 s; one that touches a chrome/browser header the
  //room code includes takes minutes to an hour; a clean build is 4 h 34
  min and an official clean build 4 h 15 min (neither should happen in
  this chapter). The incremental official build after a //room change is
  unmeasured: 4.1b measures it (see the build rule).
- Waiting on a build: never a foreground sleep (the harness blocks it).
  Start the build with nohup, then wait with a background command such
  as `while kill -0 <pid>; do sleep 60; done` (run_in_background, a two-
  hour timeout, re-armed when it expires), and do fold-in work meanwhile.
- The user's own Room (the notarized release app on the real state
  directory ~/Library/Application Support/Room) runs on this Mac while
  you work. Never kill it, never launch anything on the real state or
  the real engine root (every spike takes -RoomStateDirectory and
  -RoomEngineDirectory under /tmp; B-78 makes that the default in 4.1a).
  The wrappers match their own app's processes since the laptop fix
  (scripts/lib/room-process.sh `room_scope`); `pkill -f` only on spike
  leftovers you can name by path, never on Room.app in general.
- Developer ID signing ("Jonas Lekevicius (N56PMJ99UT)") and the
  notarytool profile `room` work here; scripts/roomcore-sign.sh and
  scripts/sparkle-package.sh are the tools. The Sparkle EdDSA signature
  needs the user's keychain approval: skip it (an unsigned appcast entry)
  and say so; the user installs the DMG by hand.
- Disk: keep 10 GB free on the internal drive before a tour or a
  packaging step by deleting regenerable build/ output (older tour runs,
  DerivedData intermediates, staged dSYMs), never evidence directories,
  build/roomcore-release-signed or any DMG the user has not installed.
- The Claude desktop app is frontmost while you work: a tour check that
  fails only for window_main or activation is attributed to the run's
  conditions when a standalone rerun passes. Stack Overflow's Cloudflare
  challenge breaks the baseline's external quits: known. Renderer
  DCHECK minidumps on live sites are a dev-build condition (B-76): judge
  crashes and numbers on the release framework (ROOM_TOUR_APP = the
  Debug app over the release framework), the dev tour on correctness.
- The test servers are scripts/test-servers.sh; the grand tour is
  scripts/grand-tour.sh (--groups, --only, --no-build, ROOM_TOUR_APP);
  the engine-level drives scripts/roomcore-features.sh; the net-log
  scripts/netlog-check.sh; the spike runner scripts/run-spike.sh with
  -RoomSpike / -RoomSpikeOnly. If the display is asleep or the session
  locked, say so in the log and continue; captures are in-process.
- Save every session prompt you write under build/chapter-4-prompts/
  (gitignored, survives a reboot; the Chapter 3 prompts lived in the
  scratchpad and a power outage took them).

== Chromium builds: the rule (the user's, 2026-10-06) ==
- No needless fork build. The engine stays on 155.0.8059.36. No
  scheduled rebase: one happens only if a "3.9 week" row or the user
  asks for a security release, or a phase cannot proceed without it, as
  a night with no session attached. If you ever need one, run
  scripts/roomcore-rebase.sh <tag> then --verify, record the cost, and
  go on.
- No new patch, with one exception: incognito (4.8b) may take a patch
  and the partial or full rebuild it costs if it cannot be had without
  one. Any other phase that seems to need a patch records a user row
  with the smallest alternative and does the alternative.
- //room and Packages/EngineRoomCore change only in the engine steps
  the ROADMAP names (4.1b, 4.3b, 4.4b, 4.5, 4.6, 4.7a, 4.8b; the eleven
  members listed in ROADMAP Chapter 4 "Decisions"). Each engine step
  ends with the //room incremental of out/dev, scripts/roomcore-
  package.sh, and the baseline (nav, open10, three ten-page quits). All
  other work builds with xcodebuild over the staged frameworks in
  minutes.
- The user's DMG: after every phase's last session is accepted, if
  //room is unchanged since out/release was built, run scripts/roomcore-
  package.sh --release, scripts/roomcore-sign.sh (notarized), scripts/
  sparkle-package.sh into build/sparkle-4.x/, with CURRENT_PROJECT_
  VERSION in xcodegen/base.yml bumped by one first (committed), and put
  the DMG's path at the top of the by-hand list with "run scripts/reset-
  state.sh first" when the schema moved on. If //room did change, the
  incremental official build comes first (ROOM_OUT_DIR=out/release
  ROOM_GN_ARGS=release.gn scripts/roomcore-build.sh, nohup); 4.1b
  measures that build once, and the number decides for the rest of the
  chapter whether engine steps are followed by a DMG at once or only at
  4.9. Nobody but the user runs Room; schema migrations need not be
  reversible.

== The loop ==
The sessions, in order, are the ones ROADMAP Chapter 4 names: 4.1a,
4.1b, 4.2, 4.3a, 4.3b, 4.4a, 4.4b, 4.5, 4.6, 4.7a, 4.7b, 4.8a, 4.8b,
4.9. For each session:

1. Write the session prompt (format below), save it under
   build/chapter-4-prompts/, and start the implementer with the Agent
   tool: `subagent_type: "implementer"` (the project agent in
   .claude/agents/implementer.md: Opus, reasoning effort high; the
   Agent tool has no effort parameter of its own, the definition
   carries it), foreground (wait for it), no worktree isolation (the
   Chromium checkout's src/room symlink points at this checkout; a
   worktree would build the wrong tree), prompt = the whole session
   prompt. The subagent starts with no memory of this conversation, so
   the prompt is self-contained and points at files, never at "what we
   discussed". One subagent per session; never two at once.
2. When the report arrives, review it (checklist below). The report is
   not shown to the user: what matters from it goes into the repository.
3. Fold the result in: verify the ticks in docs/progress.md, append your
   own dated "accepted (planner loop)" log entry with what you checked
   and what you changed, add a "What 4.x provides" paragraph before the
   phase's Exit line in ROADMAP.md (like Chapter 3's) when a session
   changed the ground for a later one, add backlog rows, record lasting
   decisions in PLAN §4. Read docs/backlog.md for new "3.9 week" rows
   the user may have added and assign each to a phase (amend that
   phase's ROADMAP text) or mark it "iteration" (after Chapter 5).
   Commit the fold-in as one commit, push, and confirm CI is green
   (`gh run watch`); if the implementer's push left CI red, that is the
   first thing the next session fixes, or you fix it yourself when it is
   a one-liner.
4. Append one short entry to research/notes/chapter-4-loop.md: session,
   outcome (accepted / accepted with gaps / follow-up), wall time, the
   decisions you made, what went on the user's list, which DMG the user
   has. This file and the progress log are your memory across sessions:
   re-read the last entries of both before writing the next prompt; do
   not rely on recall.
5. After a phase's last session: the DMG (the build rule above), then
   the next session. When a session's exit items are partly unmet, you
   may write one follow-up session (name it 4.xa-2) for the unmet part;
   never more than one follow-up per session. After that, record the gap
   as a backlog row with the phase that picks it up, and move on. 4.9 is
   the time for the long tail, not every session.

When all sessions are done, write the final report (format below),
push, and stop. Do not start Chapter 5.

== What you must not re-litigate ==
Decided by the user or the planner and recorded in PLAN §4 and ROADMAP
Chapter 4. From Chapter 3: identity app.room.desktop with Chromium's
helper suffixes; the host owns the main menu and NSApp.delegate; the
patch policy (tiny hooks; //base or //content only with a release-build
failure; 0010 parked); spike hooks gated by room_enable_spikes; find
and DevTools owned by the host; zoom per host; Safe Browsing off; side
panels unsupported; no analytics and no unrequested network calls;
AppKit for list rows and chrome, SwiftUI only in leaves; the testing
tiers (AGENTS.md); commits without attribution trailers; push once per
session then watch CI. From Chapter 4 (the user, 2026-10-06): no
scheduled rebases and no new patch except for incognito; Today tabs per
window, spaces and pinned and essentials shared live (Arc's model); a
page lives in one window and moves when selected elsewhere; incognito
is the engine's off-the-record profile in its own window, nothing
persisted; the Library lives in the sidebar (⇧⌘L swaps the spaces view;
Archive, Downloads, History; items open on their own, no Library pages);
rolling backups copy the database and the JSON snapshot drops the
navigation states; import treats every browser equally with Room's own
readers (passwords through Chrome's CSV importer, no cookie import, no
ImporterHost) and the sessions make their own fixtures; reader mode is
the distiller script in the isolated world; routing is the host's;
nothing is special-cased for any vendor (B-69: no native messaging
hosts; 1Password is an ordinary extension); no translate key (B-63), no
password generation (B-72), Enhanced Spell Check hidden (B-74),
extensions' own requests are theirs (B-68), zoom per host stated in
Settings (B-27); the Engine protocol frozen except the eleven named
members; numbers and crashes judged on the release framework; the DMG
after each phase. If a session's evidence shows one of these is wrong,
record the evidence and the smallest alternative as a backlog row with
owner **user**, keep the decision, and continue.

== Decisions you make, and the user's list ==
- Make provisional decisions whenever the spec leaves a choice: pick the
  option that keeps //room small, keeps the host in charge of UI, builds
  for every user rather than this one, and can be reversed later. Record
  each in your log entry, and in PLAN §4 only when it is a lasting
  engineering decision.
- A decision goes to the user (a backlog row with owner **user**, and a
  question with options in docs/backlog-form.md under a "Chapter 4"
  heading) only when it needs money, an account, hardware this machine
  lacks, or product taste a later chapter cannot cheaply revisit. Give
  your provisional choice in the row so the chapter is never blocked.
  The user will answer the form after the chapter.
- Every check that needs a hand (a click, a trackpad, a device, a real
  account, the 120 Hz panel as the main display) goes into
  research/notes/chapter-4-by-hand.md, one ordered list grouped by phase
  with the launch command per step, in the style of chapter-3-by-hand.md,
  written the same day as the phase; the current DMG at the top. The
  implementer appends its "needs a click" items; you keep the file tidy.
  The user will not read it until the chapter ends; it may grow long.

== Scope discipline (put this in every session prompt, in these words) ==
- Test what you changed, not everything. After an engine change: the
  baseline (nav, open10, three ten-page quits) and the tour step or
  engine drive the task names. After an app change: the unit tests of
  the packages you touched and the one spike or tour step that exercises
  the change, on the dev build and once on the release framework
  (ROOM_TOUR_APP). The full grand tour runs in 4.9, not before. Do not
  rerun sections your change cannot have touched.
- Record numbers, do not chase them. A number that misses its bound by
  less than a quarter is a backlog row, not a task; a number that misses
  by more gets one bounded attempt (one profile, one fix), then a row.
  Performance work is Chapter 5.4.
- No visual polish. Dia-matching, spacing, colours and animation feel
  are Chapter 5; a surface that works and is usable is done. Views
  bubbles look like Chrome; that is accepted until 5.7.
- No rabbit holes. A fix attempt that fails twice is recorded with what
  was tried and the next idea, then the session moves on. A Chromium
  behaviour that contradicts the spec is a deviation row with the
  closest correct thing done, not an investigation. Never disable a
  DCHECK, never widen a patch, never add a patch (incognito excepted and
  justified) to make a probe pass.
- No re-research. The research notes and the Chromium checkout exist;
  consult them when a task points at them. New notes only for
  measurements and findings.
- Honest reports: a safe rejection is not a feature; a skipped check is
  a failure; unmet exit items are listed as unmet with the next step.

== Session prompt format ==
Start from docs/implementer-prompt.md's text (pull first, read list,
working rules, report) and adapt it as the Chapter 3 planner did (the
Chapter 3 prompts' shape and what they named per session are described
in research/notes/chapter-3-loop.md):
1. Opening paragraph: "You are implementing Phase 4.x, session 4.xa, of
   the Room browser in /Users/eve/Code/room (this Mac mini; the user
   `eve`). This session covers ROADMAP Phase 4.x tasks N–M (name them);
   tasks … are session 4.xb: do not start them. Commit messages are
   prefixed `phase-4.x:`."
2. Read list: AGENTS.md; PLAN §2 and §4 (the rows the phase touches);
   ROADMAP Chapter 4's "Chromium builds" paragraph, the phase section
   with any "What 4.x provides" paragraph; docs/progress.md's checklist
   for the phase and the previous session's "For 4.xb" paragraph;
   docs/engine-api.md's RoomCore column for the members the phase adds;
   the backlog rows the phase names; the research notes and the spike
   fixtures the task points at; feature-spec.md's sections the phase
   implements. "Do not re-research or re-plan. Stop when the items
   below are done or recorded as blocked, and report."
3. Context you may need: the machine facts above (the user's own Room
   running: never touch the real state; 6 jobs, one build, bash nohup,
   never edit //room during a build, the baseline after every engine
   change); the build rule (which tasks are the engine step, the
   members it may add and the seams the ROADMAP names; no patch); the
   scripts that exist for the task; what the previous session built,
   with file names; the Chromium classes the ROADMAP names per member.
4. Working rules: the standard ones from implementer-prompt.md (small
   commits, no trailers, push once at the end then watch CI, tick
   tasks, a dated log entry with a "For 4.xb" or "For the planner"
   paragraph, numbers in spike-results.md, AGENTS.md testing tiers,
   Swift 6 and AppKit rules, the ObjC boundary rule, no hand-edits of
   the .xcodeproj, tokens for sizes, schema changes through a
   DatabaseMigrator step with a migration test) plus the scope-
   discipline block above, verbatim.
5. Verify, don't assume: name the exact runs the session must produce
   (the tour step on both builds, the unit tests, the baseline for an
   engine step, one net-log where the phase enables an engine feature);
   keep them few.
6. Report: what was built, the numbers, deviations numbered with
   reasons, which exit items are met and which are not, the "needs a
   hand" items appended to chapter-4-by-hand.md, and "For the next
   session" (what it provides and where).

== Review checklist (every report) ==
- `git log` since the last fold-in: one commit per task, `phase-4.x:`
  prefixes, no attribution trailers, nothing outside the allowed paths
  (App, Packages, scripts, research/notes, research/spikes, docs,
  xcodegen, project.yml; for an engine step also Engine/roomcore/room
  and Packages/EngineRoomCore; Engine/roomcore/patches only in 4.8b and
  only with a justification) unless the task named it.
- CI green on the implementer's push; if red, read the failure.
- The unit tests of the packages the session touched pass here
  (`CI=1 swift test --package-path Packages/<name>`).
- The progress entry exists, tasks are ticked, deviations are numbered
  and each has a reason; numbers have conditions (build, load, display).
- Evidence matches claims: the tour step's result lines on both builds
  are in spike-results.md; the baseline numbers after the last engine
  change; a migration test for a schema step; captures exist where the
  prompt asked (look at two or three).
- Engine: public ObjC headers changed only for the members the ROADMAP
  names, each with FakeEngine updated and a docs/engine-api.md row
  naming the Chromium counterpart; the series still applies
  `0 applied / 23 already` (24 only after an incognito patch with its
  header justification); no `*ForTesting` seam used without a note.
- The product stays silent: an engine step that turns a Chrome feature
  on ran a net-log (launch + idle) and it shows 0 engine requests.
- Nothing special-cased for a vendor, no setting named after a product.
- Exit items claimed met have a measured line behind them; unmet ones
  are named with a next step, not hidden.
- Then decide: accept, accept with gaps (backlog rows), or one follow-up
  session.

== Session-specific notes ==
- 4.1a: task 0 (the tooling carry-overs B-78, B-79, `roomcore-apply.sh
  --drop`, the tour's load and idle check, scripts/reset-state.sh) comes
  first, in its own commits, so every later session launches spikes
  safely beside the user's Room. The Library is a sidebar view, not a
  window.
- 4.1b: start the incremental official build right after the //room
  change and wait for it in the background while the implementer goes
  on with the backups; its wall time decides the chapter's DMG rule
  (under 45 min: a DMG after every engine step; else only at 4.9).
  This phase's DMG is the first the user installs; the by-hand list
  says to run scripts/reset-state.sh first (schema v7).
- 4.2: one session; the routing table may share 4.1a's migration if it
  has not shipped in a DMG yet, else it is v8 and 4.8a's is v9.
- 4.3: the sessions make the fixtures (Safari is installed here; check
  for Chrome, Brave, Arc, Firefox with `mdfind kMDItemCFBundleIdentifier`
  and use what exists on throwaway profiles; otherwise hand-made files
  from the formats, with Chromium's chrome/utility/importer and
  components/password_manager/core/browser/import as references for
  Safari, Firefox and the CSV, and Firefox's browser/components/
  migration as the reference for the Chrome-family files). Never read
  the user's own browser profiles.
- 4.4a: Settings ▸ Shortcuts is an AppKit table (rows update per
  keystroke); the reserved set must follow a remap (a window-tier test
  may cover the menu; the unit tier covers the table).
- 4.4b: the Google-service answers are settled (B-63 none, B-72 none,
  B-74 hidden, B-68 theirs, B-27 per host): copy, not questions.
- 4.5: pin/unpin and site access only; popup polish is Chapter 5; B-69
  stays none with one line in Settings.
- 4.6: B-62 (the Bluetooth adapter start hanging the UI thread) gets
  one bounded attempt only if the laptop by-hand run has said it
  reproduces with the dialogs answered; otherwise the row waits.
- 4.7a: Save Page… ⇧⌘S is a new docs/shortcuts.md row; the freeze needs
  a progress-log line saying why. Full-page capture is one bounded
  attempt.
- 4.7b: the reader page is HTML with the tokens, not SwiftUI; no
  translate item without a key.
- 4.8a: schema `entry.windowID`; the move-on-select works by unload and
  reload until 4.8b's member; record memory with two windows.
- 4.8b: the one place a patch is allowed, justified in its header; the
  OTR profile's lifetime is the 3.4b lesson (ScopedProfileKeepAlive).
- 4.9: the full tour on both builds; no rebase; the release only if the
  user does not already have a DMG from the same //room and app state;
  write chapter-4-review.md as a draft in the shape of chapter-3-
  review.md with the planner columns filled by you, and confirm or
  amend the Chapter 5 spec in ROADMAP.md.

== Tips from the Chapter 3 loop ==
- Sessions ran 40–130 min when the prompt named files and runs; the
  long ones (355 min) were waiting on builds. Keep each prompt's run
  list to what the exit needs.
- Between a build's start and its end, run a session that does not
  touch //room (every Chapter 4 session but the engine steps qualifies),
  so the machine is never idle. Never start an engine step while a
  build runs.
- A red CI for a diagnostic the local compiler does not raise is real
  (the runner's Xcode is stricter on Swift 6 isolation): `MainActorWeak`
  for @Sendable closures that need self.
- The implementer sometimes claims a tour step passed when a check was
  skipped or shaped by an old assumption (B-55: isolated-world scripts
  cannot read page globals): read the result lines, not the summary.
- A power outage or reboot leaves the Chromium image unmounted and the
  scratchpad gone: remount, re-read chapter-4-loop.md and the progress
  log, check `git status` and the last build log's tail, then continue.
- After each fold-in, run `git pull --ff-only` before the next prompt:
  the user may push from the laptop (notes, by-hand ticks) at any time.

== Final report (when the loop ends) ==
Write research/notes/chapter-4-loop.md's closing section and tell the
user, in order: the sessions run with their outcomes and wall times; the
engine members added and what each cost in //room; the numbers that
changed against Chapter 3's release rows; the backlog rows that need the
user's decision, each with your provisional choice, and the form's new
"Chapter 4" section; the by-hand list's size, where it is, and which DMG
is current; the "3.9 week" rows left for the iteration; and the three
things you would change in the Chapter 5 spec. Push everything. Stop
there: do not start Chapter 5.
```
