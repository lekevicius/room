#!/usr/bin/env bash
# Phase 4.8b: the `incognito` spike (App/Sources/Debug/IncognitoSpikes.swift)
# on its own state and engine directories under /tmp/room-4, two launches:
# `main` (⇧⌘N opens the incognito window: its title, the dark appearance and
# the tint token, the sidebar's note, Today list and no essentials or pinned;
# a cookie set at cookies.html there is absent from the regular profile; the
# regular profile's history and Room's store have nothing of it; a sign-in on
# login.html offers to save in the regular window and not in incognito;
# "Open Link in Incognito Window" from a regular page lands in the incognito
# window; the fixture extension's action in the incognito header only while
# allowed in incognito; captures in both appearances; closing the window ends
# its pages and the off-the-record profile, the renderers go; reopened, the
# cookie is gone), then `idle` with the engine's net-log (an incognito window
# open over the launch and 20 s idle: the engine's hosts other than the page
# hosts must be none). Serves research/spikes on 127.0.0.1:8777, the 2.5
# cookie page on :8765 and the 3.7 login page on :8772 unless something
# listens there already. The engine's minidumps are counted (`crashpad_dumps:`).
# Usage: scripts/incognito-check.sh [capture-dir] [extra spike args...]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
[[ $# -gt 0 ]] && shift
mkdir -p /tmp/room-4
work="$(mktemp -d /tmp/room-4/incognito.XXXXXX)"
pids=""
trap '[[ -n "$pids" ]] && kill $pids 2>/dev/null || true' EXIT
serve() { # port directory
  if ! lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; then
    python3 -m http.server "$1" --bind 127.0.0.1 -d "$2" >/dev/null 2>&1 &
    pids="$pids $!"
  fi
}
serve 8777 research/spikes
serve 8765 research/spikes/phase-2.5
spki_args=()
if ! lsof -nP -iTCP:8772 -sTCP:LISTEN >/dev/null 2>&1; then
  python3 research/spikes/phase-3.7/server.py "$work/spki.txt" 2>"$work/server37.log" &
  pids="$pids $!"
fi
for _ in $(seq 1 100); do
  [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8777/phase-4.8/a.html') == 200 &&
     $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8765/cookies.html') == 200 &&
     $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8772/login.html') == 200 ]] && break
  sleep 0.1
done
[[ -s "$work/spki.txt" ]] && spki_args=("--ignore-certificate-errors-spki-list=$(cat "$work/spki.txt")")
args=(-RoomStateDirectory "$work/state" -RoomEngineDirectory "$work/engine")
echo "state: $work"
# The tour's appearance and switches stay; its state and engine directories give way to the run's own.
if [[ -n "${ROOM_TOUR_ARGS:-}" ]]; then
  read -r -a tour <<<"$ROOM_TOUR_ARGS"
  kept=()
  for ((i = 0; i < ${#tour[@]}; i++)); do
    if [[ "${tour[$i]}" == -RoomStateDirectory || "${tour[$i]}" == -RoomEngineDirectory ]]; then i=$((i + 1)); continue; fi
    kept+=("${tour[$i]}")
  done
  export ROOM_TOUR_ARGS="${kept[*]}"
else
  args+=(-RoomSpikeAppearance light)
fi
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
out="$work/spike.txt"
: >"$out"
ROOM_SPIKE_OUT="$work/spike-main.txt" scripts/run-spike.sh incognito -RoomSpikeOnly main -ApplePersistenceIgnoreState YES \
  ${args[@]+"${args[@]}"} ${spki_args[@]+"${spki_args[@]}"} "$@" >/dev/null || true
sleep 1
cat "$work/spike-main.txt" >>"$out" 2>/dev/null || echo "error: no output from main" >>"$out"
# The net-log launch: a fresh state, an incognito window over launch and idle.
idle=(-RoomStateDirectory "$work/idle-state" -RoomEngineDirectory "$work/idle-engine" "--log-net-log=$work/netlog.json"
      -RoomIncognitoIdle "${ROOM_INCOGNITO_IDLE:-20}")
[[ -z "${ROOM_TOUR_ARGS:-}" ]] && idle+=(-RoomSpikeAppearance light)
ROOM_SPIKE_OUT="$work/spike-idle.txt" scripts/run-spike.sh incognito -RoomSpikeOnly idle -ApplePersistenceIgnoreState YES "${idle[@]}" "$@" >/dev/null || true
sleep 1
cat "$work/spike-idle.txt" >>"$out" 2>/dev/null || echo "error: no output from idle" >>"$out"
echo "== spike"
cat "$out"
echo
echo "== engine net-log by host (incognito window open over launch and idle)"
if [[ -s "$work/netlog.json" ]]; then
  python3 scripts/lib/netlog-summary.py "$work/netlog.json" "$work/spike-idle.txt" | tee "$work/netlog-summary.md" | tail -1 | sed 's/^/netlog: /'
else
  echo "netlog: missing"
fi
dumps=$(ls "$work"/engine/Crashpad/pending/*.dmp "$work"/engine/Crashpad/completed/*.dmp "$work"/idle-engine/Crashpad/pending/*.dmp "$work"/idle-engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
for dump in $dumps; do
  echo "crashpad_dump: $(basename "$dump") $(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || echo 'no FATAL line')"
done
