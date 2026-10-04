# Chapter loop prompt (written for Chapter 3, 2026-10-04)

Paste the block below into a fresh planner session on the build machine. It runs a whole chapter: it writes each session's prompt, starts an implementer subagent, reviews the report, folds the result into the docs, and goes on to the next session until the chapter's build phases are done. The user is not in the loop until the end.

```
You are the planner and reviewer for Chapter 3 of the Room browser in
/Users/j/Code/room on this Mac mini (M4, 24 GB). You run the chapter end
to end: for each implementer session you write its prompt, start an
implementer subagent, wait for its report, review it, fold what you learned
into the repository, and start the next session. The user is away and will
not test anything until the chapter ends; every decision that cannot wait
is yours to make provisionally, and every check that needs a hand goes on
a list for the user. Expect this to take many hours. Do not stop between
sessions to ask anything.

== Read first ==
Run `git pull --ff-only` on main. Then read, in this order: AGENTS.md
(CLAUDE.md is a symlink to it); PLAN.md (§1, §2, §4, §7); ROADMAP.md, the
whole Chapter 3 section and the Chapter 4 overview; docs/progress.md, the
Chapter 3 checklists and the last ten log entries; research/notes/
chapter-2-review.md and research/notes/roomcore-hardening-review.md (what
Chapter 3 inherits and why); docs/engine-api.md (the RoomCore column is the
contract); docs/backlog.md (B-38 to B-44 are Chapter 3's inputs);
docs/implementer-prompt.md (the generic implementer prompt; your session
prompts extend it); Engine/roomcore/README.md and docs/setup.md §4 (the
fork build on this machine). research/notes/spike-results.md and
build-log.md are reference, not reading.

== The machine ==
- The Chromium checkout and `out/dev` are here (location in local.env).
  This Mac builds the fork with `ROOM_BUILD_JOBS=6`; the default job count
  swaps and throughput drops ten times. One fork build at a time. Long
  builds start from bash with nohup, never zsh `&`. Never edit //room while
  a compiler is running on it. `//room` incrementals take 45–63 s; a clean
  build takes over four hours and is an overnight job. The official release
  build (3.1b) may not link in 24 GB: try it at 6 jobs; if it fails for
  memory, record the failure with numbers and put the release build on the
  user's list (the laptop has 64 GB); do not retry blindly.
- Developer ID signing and the notarytool profile `room` are on this
  machine. Ad-hoc builds use the mock keychain; signed builds use the real
  one (one prompt on first launch, none after).
- Implementer subagents must run in this checkout, not in a worktree: the
  Chromium checkout's `src/room` symlink points here and a worktree would
  build the wrong tree.
- The test servers are `scripts/test-servers.sh`; the grand tour is
  `scripts/grand-tour.sh` with `--groups` to run sections; the engine-level
  drives are `scripts/roomcore-features.sh` (after the 3.1a merge).
  Stray Room instances and a locked session have hung spikes before: before
  each session, `pkill -f Room.app` for leftovers from spikes only (never
  the user's own instance on the real state directory), and if the display
  is asleep say so in the log and continue; captures will be in-process.

== The loop ==
The sessions, in order, are the ones ROADMAP Chapter 3 names: 3.1a, 3.1b,
3.2a, 3.2b, 3.3a, 3.3b, 3.4a, 3.4b, 3.5, 3.6a, 3.6b, 3.7a, 3.7b, 3.8, and
3.9 without its week of use (tasks 1, 2, 3's tour, 5's draft review). For
each session:

1. Write the session prompt (format below) and start the implementer with
   the Agent tool: `subagent_type: "implementer"` (the project agent in
   .claude/agents/implementer.md: Opus, reasoning effort high; the Agent
   tool has no effort parameter of its own, the definition carries it),
   foreground (wait for it), no worktree isolation, prompt = the whole
   session prompt. The subagent starts with no memory of this conversation, so
   the prompt is self-contained and points at the files, never at "what
   we discussed". One subagent per session; never two at once.
2. When the report arrives, review it (checklist below). The report is not
   shown to the user: what matters from it goes into the repository.
3. Fold the result in: tick the tasks in docs/progress.md (the implementer
   does; you verify), append your own dated "accepted (planner loop)" log
   entry with what you checked and what you changed, amend the ROADMAP's
   later phases where the session changed the ground ("What N provides"
   paragraphs, like the Chapter 2 ones), add backlog rows, record
   decisions. Commit your fold-in as one commit, push, and confirm CI is
   green on it (`gh run watch`); if the implementer's own push left CI
   red, that is the first thing the next session fixes, or you fix it
   yourself when it is a one-liner.
4. Append one short entry to research/notes/chapter-3-loop.md: session,
   outcome (accepted / accepted with gaps / follow-up), wall time, the
   decisions you made, what went on the user's list. This file and the
   progress log are your memory across sessions: re-read the last entries
   of both before writing the next prompt, do not rely on recall.
5. Go to the next session. When a session's exit items are partly unmet,
   you may write one follow-up session (name it 3.xa-2) for the unmet
   part; never more than one follow-up per session. After that, record the
   gap as a backlog row with the phase that picks it up, and move on.
   Chapter 3's last session is the time for the long tail, not every
   session.

When all sessions are done, write the final report (format below), push,
and stop.

== What you must not re-litigate ==
These were decided by the user or the planner on 2026-10-04 and are in PLAN
§4 and ROADMAP Chapter 3: identity `app.room.desktop`; the host owns the
main menu and NSApp.delegate (RoomAppController through one hook); hybrid
Views bubbles stay for Chapter 3; patch policy (tiny hooks; //base or
//content patches only with a reproducible failure on the release build;
0010 parked); spike hooks gated by `room_enable_spikes`; engine selection
by `ROOM_ENGINE`; find and DevTools owned by the host; zoom per host; Safe
Browsing off; side panel unsupported; no analytics and no unrequested
network calls; AppKit for list rows and chrome, SwiftUI only in leaves;
testing tiers (AGENTS.md); commits without attribution trailers; push once
per session then watch CI. If a session's evidence shows one of these is
wrong, record the evidence and the smallest alternative as a backlog row
with owner **user**, keep the decision, and continue.

== Decisions you make, and the user's list ==
- Make provisional decisions whenever the spec leaves a choice: pick the
  option that keeps the patch set small, keeps the host in charge of UI,
  and can be reversed later. Record each in your log entry and in PLAN §4
  only when it is a lasting engineering decision.
- A decision goes to the user (a backlog row with owner **user**) only
  when it needs money, an account, hardware this machine lacks, or product
  taste that a later chapter cannot cheaply revisit. Give your provisional
  choice in the row so the chapter is not blocked.
- Every check that needs a hand (a click, a trackpad, a device, a real
  account, a 120 Hz panel) goes into research/notes/chapter-3-by-hand.md,
  one ordered list grouped by phase with the launch command per step, in
  the style of chapter-2-by-hand.md. The implementer appends its "needs a
  click" items; you keep the file tidy. The list may grow long; the user
  will use the app for a week after the chapter.

== Scope discipline (put this in every session prompt, in these words) ==
- Test what you changed, not everything. After an engine change: the
  baseline (nav, open10, three ten-page quits) and the tour sections or
  engine drives the task names. After an app change: the unit tests of the
  packages you touched and the one spike that exercises the change. The
  full grand tour runs in 3.9, not before.
- Record numbers, do not chase them. A number that misses its bound by
  less than a quarter is a backlog row, not a task; a number that misses
  by more gets one bounded attempt (one profile, one fix), then a row.
  Performance work is a later chapter.
- No visual polish. Dia-matching, spacing, colours and animation feel are
  Chapter 5; a surface that works and is usable is done. Views bubbles look
  like Chrome; that is accepted.
- No rabbit holes. A fix attempt that fails twice is recorded with what was
  tried and the next idea, then the session moves on. A Chromium behaviour
  that contradicts the spec is a deviation row with the closest correct
  thing done, not an investigation. Never disable a DCHECK or widen a
  patch to make a probe pass.
- No re-research. The research notes exist; consult them when a task
  points at them. New notes only for measurements and findings.
- Honest reports: a safe rejection is not a feature; a skipped section is
  a failure; unmet exit items are listed as unmet with the next step.

== Session prompt format ==
Start from docs/implementer-prompt.md's text (pull first, read list,
working rules, report) and adapt it as the Chapter 2 planner did:
1. Opening paragraph: "You are implementing Phase 3.x, session 3.xa, of
   the Room browser in /Users/j/Code/room. This session covers ROADMAP
   Phase 3.x tasks N–M (name them)…; tasks … are session 3.xb: do not
   start them. Commit messages are prefixed `phase-3.x:`."
2. Read list: AGENTS.md, PLAN §1/§2/§4, ROADMAP Chapter 3 overview and the
   phase section including its "What N provides" paragraph, docs/progress.md
   with the previous session's "For 3.xb" paragraph, docs/engine-api.md's
   RoomCore column, the research notes the phase names, docs/backlog.md
   rows the phase names. "Do not re-research or re-plan. Stop when … and
   report."
3. Context you may need: the machine facts above (6 jobs, one build, bash
   nohup, never edit //room during a build, rebuild and rerun the baseline
   after every engine fix); the scripts that exist for the task; what the
   previous session built, with file names; the Chromium call sites the
   research already found.
4. Working rules: the standard ones from implementer-prompt.md (small
   commits, no trailers, push once at the end then watch CI, tick tasks,
   dated log entry, numbers in spike-results.md, AGENTS.md testing tiers,
   Swift 6 and AppKit rules, the ObjC boundary rule, no hand-edits of the
   .xcodeproj, tokens for sizes) plus the scope-discipline block above,
   verbatim.
5. Verify, don't assume: name the exact runs and captures the session
   must produce; keep them few.
6. Report: what was built, the numbers, deviations, which exit items are
   met and which are not, the "needs a hand" list for chapter-3-by-hand.md,
   and "For the next session" (what it provides and where).

== Review checklist (every report) ==
- `git log` since the last fold-in: one commit per task, `phase-3.x:`
  prefixes, no attribution trailers, nothing outside the allowed paths for
  a fork session (Engine/roomcore, Packages/EngineRoomCore, App, scripts,
  research/notes, docs) unless the task named it.
- CI green on the implementer's push; if red, read the failure.
- The unit tests of the packages the session touched pass here
  (`swift test --package-path Packages/<name>`).
- The progress entry exists, tasks are ticked, deviations are numbered and
  each has a reason; numbers have conditions (build, load, display).
- Evidence matches claims: the baseline numbers after the last engine
  change are in spike-results.md; the stub-hit list is recorded for 3.2
  sessions; captures exist where the prompt asked (look at two or three).
- Patches: any new patch has a written no-existing-hook justification, is
  small, and the series still applies 0 applied / N already.
- Public ObjC headers changed only where the task said so, and
  docs/engine-api.md's RoomCore column was updated with the Chromium
  counterpart.
- The Engine protocol changed only with FakeEngine and (until 3.9) CEF
  updated and a row in engine-api.md.
- Exit items claimed met have a measured line behind them; the unmet ones
  are named with a next step, not hidden.
- Then decide: accept, accept with gaps (backlog rows), or one follow-up
  session.

== Session-specific notes ==
- 3.1a: the PR #1 merge comes first and alone in its commit sequence
  (rebase, three append conflicts in docs/backlog.md, docs/engine-api.md,
  research/notes/spike-results.md, 0010 parked, ids renumbered B-38–B-40);
  `scripts/roomcore-apply.sh` must report 0 applied / 11 already before any
  //room edit. The engine-neutral spike driving surface (B-44) and the
  launch quick_check (B-42) are in this session.
- 3.1b: the release build is an overnight job; start it at the end of the
  session from bash with nohup and let the next session read the result,
  rather than waiting idle. If it cannot link here, record and move on
  (user's list). Signing and notarization are real on this machine.
- 3.2 sessions: the stub-hit log over the tour sections is the deliverable
  as much as the code.
- 3.3b: RoomCore's numbers are taken under the tour's conditions (visible
  window, frontmost, 60 Hz here) and placed beside CEF's.
- 3.5: measure launch time before and after the history migration.
- 3.6a: the Web Store check needs real extensions; if the store refuses,
  the CRX path is the fallback and the risk is re-ranked in your log, not
  argued with.
- 3.8: two rebases are two overnight builds; schedule them so the machine
  is never idle during a session (start the build, then run a session
  that does not touch //room, such as 3.5 or 3.6a, if the order allows).
- 3.9: delete CEF only after the tour is green on RoomCore; the week of
  use is the user's; write chapter-3-review.md as a draft in the shape of
  chapter-2-review.md with the planner columns filled by you.

== Final report (when the loop ends) ==
Write research/notes/chapter-3-loop.md's closing section and tell the
user, in order: the sessions run with their outcomes and wall times; the
numbers table (RoomCore beside CEF); the backlog rows that need the
user's decision, each with your provisional choice; the by-hand list's
size and where it is; what the week of use should watch for; and the
three things you would change in the Chapter 4 spec. Push everything.
Stop there: do not start Chapter 4.
```
