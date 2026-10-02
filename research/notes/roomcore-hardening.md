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
