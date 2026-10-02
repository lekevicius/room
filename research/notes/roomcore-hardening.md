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
