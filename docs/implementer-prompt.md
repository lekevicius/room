# Implementer prompt

Replace `<PHASE>` with the phase id (e.g. `1.3`) and paste the rest unchanged.

```
You are implementing Phase <PHASE> of the Room browser in /Users/j/Code/room.

Before anything else, run `git pull --ff-only` on main (work moves between
two Macs through GitHub; never start from a stale checkout). Then read
CLAUDE.md, then PLAN.md (§1, §2, §4), then
ROADMAP.md (the overview of the chapter this phase belongs to and the
section for this phase), then docs/progress.md. Those files are the spec: the
phase's goal, tasks, and exit criteria are in ROADMAP.md, and the checklist
for it is in docs/progress.md. The frozen references the spec points at are
docs/shortcuts.md, docs/design-tokens.md, docs/engine-api.md and
research/notes/feature-spec.md; docs/backlog.md lists open items a phase may
pull in when its spec names them.
Do not re-research or re-plan. Work only on this phase; stop when its exit
criteria are met and do not start the next phase.

Context you may need:
- research/notes/ holds the research the spec is based on (cef.md for CEF
  embedding and bundle layout, macos-ui-stack.md for window/material/clipping
  and entitlements, chromium-fork.md for the fork and BrowserWindow boundary,
  feature-spec.md for product behavior, visual-reference.md and
  research/screenshots/ for the look). Consult them when a task references
  them; do not redo their work.
- research/repos/ has cloned sources for reference (cef/, zen-desktop/) and
  research/repos/arccore-headers/, which is proprietary: study only, never
  copy code or comments from it.
- The Chromium checkout lives outside the repo (location per machine in
  local.env, see docs/setup.md). Long builds run in the background from bash,
  never zsh &; keep working while they run and log timings to
  research/notes/build-log.md. Chapter 2 phases need no fork build.

Working rules:
- Commit in small chunks, one per completed task, messages prefixed
  `phase-<PHASE>:`. Never add a Co-Authored-By or any attribution trailer.
  Do not push.
- Tick each task in docs/progress.md as you complete it; append a dated log
  entry at the end of the session; when the exit criteria are met, mark the
  phase done there with a two-to-five-line review.
- Measurements and spike outcomes go in research/notes/ (build-log.md,
  spike-results.md) as numbers, not adjectives. Every red spike result needs
  a recorded fallback.
- Swift 6; AppKit for window, sidebar, card, address field, menus, key
  routing; SwiftUI only in leaf views via NSHostingView. Engine reached only
  through the Engine protocol package. Only Foundation/AppKit types and C
  structs cross the ObjC bridge, never std:: or base:: types. Never
  reposition traffic lights. Never hand-edit the generated .xcodeproj; change
  project.yml and run xcodegen.
- If something in the spec is impossible as written (a version, flag, or API
  that no longer exists), do the closest correct thing and record the
  deviation and reason in the docs/progress.md log. If a decision in PLAN.md
  §4 proves wrong, update PLAN.md and say so in the log.
- Verify, don't assume: build and launch the app, run the tests, take the
  screenshots the exit criteria ask for and save them under
  research/screenshots/ with the phase id in the filename.

Finish with a short report: what was built, the measured numbers, anything
that deviated from the spec, and whether each exit criterion is met.
```
