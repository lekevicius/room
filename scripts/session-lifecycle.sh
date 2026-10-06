#!/usr/bin/env bash
# Phase 3.7b: session history and the discard policy on Room.app over RoomCore
# (App/Sources/Debug/SessionSpikes.swift). Serves research/spikes on
# http://127.0.0.1:8774 (-RoomFixtureBase), then runs, each on its own
# throwaway state and engine directory under the output directory:
#   1. `session` build, then a clean relaunch with `session` check;
#   2. `session` crash (killed with SIGKILL as soon as it writes `kill_now:`,
#      right after its last navigation committed), then `session` check;
#   3. `discardpolicy` (Chromium's fake camera and microphone);
#   4. `discardspaces` (4.1b: memory pressure across two spaces);
#   5. `spelling`.
# Usage: scripts/session-lifecycle.sh [output directory] [-- extra app args]
# ROOM_SL_ONLY=session|crash|discard|discardspaces|spelling runs one part.
# ROOM_SL_KILL_DELAY_MS=<ms> waits that long after `kill_now:` before the kill
# (the loss window's other side: a step older than the store's debounce survives).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
OUTDIR="${1:-$(mktemp -d)}"; shift || true
[[ "${1:-}" == -- ]] && shift
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
EXTRA_ARGS=("$@")
PORT=8774
if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then echo "port $PORT is taken (a stale test server?)" >&2; exit 1; fi
python3 -m http.server $PORT --bind 127.0.0.1 -d research/spikes 2>"$OUTDIR/server.log" &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  [[ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$PORT/phase-3.7/step.html) == 200 ]] && break
  sleep 0.1
done

# One launch: `run <name> <state-dir> <spike> [app args]`.
run() {
  local name="$1" dir="$2"; shift 2
  local out="$OUTDIR/spike-$name.txt"
  ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh "$@" -ApplePersistenceIgnoreState YES \
    -RoomStateDirectory "$dir/state" -RoomEngineDirectory "$dir/engine" -RoomSpikeAppearance light \
    -RoomFixtureBase "http://127.0.0.1:$PORT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >/dev/null 2>"$OUTDIR/run-$name.err" || true
  echo "== $name"
  cat "$out"
  echo
}

only="${ROOM_SL_ONLY:-}"
if [[ -z "$only" || "$only" == session ]]; then
  run session-build "$OUTDIR/session" session -RoomSessionPhase build
  run session-check "$OUTDIR/session" session -RoomSessionPhase check
fi
if [[ -z "$only" || "$only" == crash ]]; then
  out="$OUTDIR/spike-session-crash.txt"
  ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh session -RoomSessionPhase crash -ApplePersistenceIgnoreState YES \
    -RoomStateDirectory "$OUTDIR/crash/state" -RoomEngineDirectory "$OUTDIR/crash/engine" -RoomSpikeAppearance light \
    -RoomFixtureBase "http://127.0.0.1:$PORT" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >/dev/null 2>"$OUTDIR/run-session-crash.err" &
  runner=$!
  while kill -0 "$runner" 2>/dev/null; do
    if pid=$(grep -m1 '^kill_now: ' "$out" 2>/dev/null | awk '{print $2}') && [[ -n "$pid" ]]; then
      [[ -n "${ROOM_SL_KILL_DELAY_MS:-}" ]] && sleep "$(python3 -c "print(${ROOM_SL_KILL_DELAY_MS}/1000)")"
      kill -9 "$pid" && echo "killed: $pid at $(python3 -c 'import time; print("%.3f" % time.time())')" >> "$out"
      break
    fi
    sleep 0.02
  done
  wait "$runner" || true
  echo "== session-crash"; cat "$out"; echo
  run session-crashcheck "$OUTDIR/crash" session -RoomSessionPhase check
fi
if [[ -z "$only" || "$only" == discard ]]; then
  run discardpolicy "$OUTDIR/discard" discardpolicy --use-fake-device-for-media-stream
fi
if [[ -z "$only" || "$only" == discardspaces ]]; then
  run discardspaces "$OUTDIR/discardspaces" discardspaces
fi
if [[ -z "$only" || "$only" == spelling ]]; then
  run spelling "$OUTDIR/spelling" spelling
fi
echo "raw files: $OUTDIR"
