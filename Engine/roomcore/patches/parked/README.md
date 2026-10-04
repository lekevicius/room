# Parked patches

Patches kept for reference but not in `series`: `scripts/roomcore-apply.sh`
does not apply them.

| Patch | Parked | Why | Re-apply when |
|---|---|---|---|
| `0010-shutdown-worker-start-priority.patch` | 3.1a merge of PR #1 (2026-10-04) | A `//base` scheduling change (`base/task/thread_pool/worker_thread.cc`: a worker created after shutdown starts enters at least default priority). It fixes a startup invariant an isolated probe demonstrates, but the shutdown watchdog it was written for (B-38) is not shown to depend on it, and PLAN §4's patch policy allows `//base` patches only for a reproducible failure on the release build. Backlog B-40 | 3.1b reproduces the watchdog on the release build (`scripts/roomcore-shutdown-local.py`, 20 runs) and the same harness with this patch applied removes it. Then it returns to `series` under its next free number |

The branch's evidence: `research/notes/roomcore-shutdown-investigation.md`
(the probe, the stacks, the rejected samples) and
`Engine/roomcore/room/diagnostics/worker_shutdown_probe.cc`.
