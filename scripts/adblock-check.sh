#!/usr/bin/env bash
# B-30: the `adblock` spike (App/Sources/Debug/AdblockSpikes.swift) on its
# own state and engine directories under /tmp/room-5: the bundled lists'
# engine (build, cache, decisions on real EasyList and EasyPrivacy URLs), the
# fixture research/spikes/phase-5-adblock/page.html with the spike's custom
# rules (third-party script, pixel and fetch blocked, a $redirect served,
# EasyList's own path rule, a site-specific and a generic hidden element, a
# CookieYes-style banner rejected by autoconsent, the page's blocked count),
# the per-site switch, and fixture load times with blocking off and on. Then
# the browser process's memory with the engine loaded. Serves research/spikes
# on 127.0.0.1:8777 unless something listens there already.
# Usage: scripts/adblock-check.sh [capture-dir] [extra spike args...]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
[[ $# -gt 0 ]] && shift
mkdir -p /tmp/room-5
work="$(mktemp -d /tmp/room-5/adblock.XXXXXX)"
server=""
if ! lsof -nP -iTCP:8777 -sTCP:LISTEN >/dev/null 2>&1; then
  python3 -m http.server 8777 --bind 127.0.0.1 -d research/spikes >/dev/null 2>&1 &
  server=$!
  trap '[[ -n "$server" ]] && kill "$server" 2>/dev/null || true' EXIT
  for _ in $(seq 1 100); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8777/phase-5-adblock/page.html') == 200 ]] && break
    sleep 0.1
  done
fi
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
# An absolute capture directory: the app's working directory is / (3.6a's finding).
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
out="$work/spike.txt"
ROOM_SPIKE_OUT="$out" scripts/run-spike.sh adblock -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"} "$@" >/dev/null || true
sleep 1
echo "== spike"
cat "$out"
echo
echo "== lists and engine cache"
ls -la "$work/state/ContentBlocking/Lists" "$work/state/ContentBlocking/Engine" 2>/dev/null || echo "none"
dumps=$(ls "$work"/engine/Crashpad/pending/*.dmp "$work"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
for dump in $dumps; do
  echo "crashpad_dump: $(basename "$dump") $(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || echo 'no FATAL line')"
done
echo "raw files: $work"
