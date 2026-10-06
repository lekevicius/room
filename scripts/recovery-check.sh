#!/usr/bin/env bash
# Phase 4.1b: crash recovery and Restore Sidebar on Room.app over RoomCore
# (App/Sources/Debug/RecoverySpikes.swift), two launches on one state:
# `recovery -RoomRecoveryPhase prepare` (two spaces, a backup, one space
# deleted and written, then killed with SIGKILL as soon as it writes
# `kill_now:`), then `recovery -RoomRecoveryPhase check -RoomRecoveryBackup
# <the backup>` (everything restored unloaded with the toast, a click loads
# the selection, Restore Sidebar brings the space back).
# Usage: scripts/recovery-check.sh [output directory]
# ROOM_APP picks the app. Inside the grand tour, ROOM_TOUR_ARGS' state and
# engine directories win over this script's own (run-spike.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
OUTDIR="${1:-$(mktemp -d)}"
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
server_pid=""
if ! lsof -nP -iTCP:8770 -sTCP:LISTEN >/dev/null 2>&1; then
  scripts/test-servers.sh "$OUTDIR/endpoints.log" >/dev/null 2>&1 &
  server_pid=$!
  for _ in $(seq 1 100); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8770/site.html) == 200 ]] && break
    sleep 0.1
  done
fi
trap '[[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true' EXIT
args=(-ApplePersistenceIgnoreState YES -RoomStateDirectory "$OUTDIR/state" -RoomEngineDirectory "$OUTDIR/engine")

out="$OUTDIR/spike-prepare.txt"
ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh recovery -RoomRecoveryPhase prepare "${args[@]}" \
  >/dev/null 2>"$OUTDIR/run-prepare.err" &
runner=$!
killed=""
while kill -0 "$runner" 2>/dev/null; do
  if pid=$(grep -m1 '^kill_now: ' "$out" 2>/dev/null | awk '{print $2}') && [[ -n "$pid" ]]; then
    kill -9 "$pid" && killed="$pid" && echo "killed: $pid with SIGKILL at $(python3 -c 'import time; print("%.3f" % time.time())')" >> "$out"
    break
  fi
  sleep 0.02
done
wait "$runner" || true
echo "== prepare"; cat "$out"; echo
[[ -n "$killed" ]] || { echo "error: the prepare launch was not killed"; exit 1; }
backup=$(grep -m1 '^backup_taken: ' "$out" | awk '{print $2}')

out="$OUTDIR/spike-check.txt"
ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh recovery -RoomRecoveryPhase check -RoomRecoveryBackup "$backup" \
  "${args[@]}" >/dev/null 2>"$OUTDIR/run-check.err" || true
echo "== check"; cat "$out"
