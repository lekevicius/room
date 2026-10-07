#!/usr/bin/env bash
# Phase 4.8a: the `windows` spike (App/Sources/Debug/WindowSpikes.swift) on its
# own state and engine directories under /tmp/room-4, three launches:
# `main` (⌘N; a pinned entry renamed in window 1 read back from window 2's
# row; a Today tab per window; a pinned page navigated in window 1, then
# selected in window 2: it moves with its history and window 1 falls back to
# its MRU; ⌘1 in window 2; Open in New Window from the context menu; the drag
# out 20 pt and 100 pt past the edge; window 2 on a second space with its own
# frame), `relaunch` on the same state (every window back with its frame,
# active space and Today tabs, only the front one loaded; closing window 2
# archives its Today tab with `windowClosed`; closing the last keeps the app;
# ⌘N and the Dock reopen it), then `memory` twice on fresh states (ten live
# pages in one window, then five in each of two windows; summed RSS and
# renderers: judge the numbers on the release framework). Serves research/spikes on 127.0.0.1:8777
# unless something listens there already. The engine's minidumps of the runs
# are counted here (`crashpad_dumps:`).
# Usage: scripts/windows-check.sh [capture-dir] [extra spike args...]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
# ROOM_WINDOWS_MEMORY=0 skips the memory launch.
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
[[ $# -gt 0 ]] && shift
mkdir -p /tmp/room-4
work="$(mktemp -d /tmp/room-4/windows.XXXXXX)"
server=""
if ! lsof -nP -iTCP:8777 -sTCP:LISTEN >/dev/null 2>&1; then
  python3 -m http.server 8777 --bind 127.0.0.1 -d research/spikes >/dev/null 2>&1 &
  server=$!
  trap '[[ -n "$server" ]] && kill "$server" 2>/dev/null || true' EXIT
  for _ in $(seq 1 100); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8777/phase-4.8/a.html') == 200 ]] && break
    sleep 0.1
  done
fi
args=(-RoomStateDirectory "$work/state" -RoomEngineDirectory "$work/engine")
memargs=()
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
  memargs+=(-RoomSpikeAppearance light)
fi
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
out="$work/spike.txt"
: >"$out"
for section in main relaunch; do
  part="$work/spike-$section.txt"
  ROOM_SPIKE_OUT="$part" scripts/run-spike.sh windows -RoomSpikeOnly "$section" -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"} "$@" >/dev/null || true
  sleep 1
  # One file for the checks: the launches' lines in order (`spike`/`end` once per launch).
  cat "$part" >>"$out" 2>/dev/null || echo "error: no output from $section" >>"$out"
done
if [[ "${ROOM_WINDOWS_MEMORY:-1}" != 0 ]]; then
  # Ten pages in one window, then over two windows: each on a fresh state and launch.
  for windows in 1 2; do
    part="$work/spike-memory-$windows.txt"
    run=(-RoomStateDirectory "$work/memory$windows-state" -RoomEngineDirectory "$work/memory$windows-engine" -RoomWindowsMemoryWindows "$windows")
    ROOM_SPIKE_OUT="$part" scripts/run-spike.sh windows -RoomSpikeOnly memory -ApplePersistenceIgnoreState YES ${memargs[@]+"${memargs[@]}"} "${run[@]}" "$@" >/dev/null || true
    sleep 1
    cat "$part" >>"$out" 2>/dev/null || echo "error: no output from memory $windows" >>"$out"
  done
fi
echo "== spike"
cat "$out"
echo
dumps=$(ls "$work"/engine/Crashpad/pending/*.dmp "$work"/engine/Crashpad/completed/*.dmp "$work"/memory*-engine/Crashpad/pending/*.dmp "$work"/memory*-engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
for dump in $dumps; do
  echo "crashpad_dump: $(basename "$dump") $(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || echo 'no FATAL line')"
done
echo "raw files: $work"
