#!/usr/bin/env bash
# Phase 4.7a: the `documents` spike (App/Sources/Debug/DocumentsSpikes.swift)
# on its own state and engine directories under /tmp/room-4: Save Page as
# HTML, complete HTML and MHTML through the engine's member (the files, the
# MHTML reopened with its image), a full-page capture through the DevTools
# protocol (DevTools closed and open), Chrome's PDF viewer on a Room page
# (its DOM, find, zoom, print preview, save), View Source from the menu and
# the context menu, File ▸ Save Page…'s host path and ⇧⌘2's screenshot
# overlay with Copy, Save and Open as tab. Serves research/spikes on
# 127.0.0.1:8777 (research/spikes/phase-4.7) unless something listens there
# already. The run's files go to <work>/files; the engine's minidumps of the
# run are counted here (`crashpad_dumps:`).
# Usage: scripts/documents-check.sh [capture-dir] [extra spike args...]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
[[ $# -gt 0 ]] && shift
mkdir -p /tmp/room-4
work="$(mktemp -d /tmp/room-4/documents.XXXXXX)"
server=""
if ! lsof -nP -iTCP:8777 -sTCP:LISTEN >/dev/null 2>&1; then
  python3 -m http.server 8777 --bind 127.0.0.1 -d research/spikes >/dev/null 2>&1 &
  server=$!
  trap '[[ -n "$server" ]] && kill "$server" 2>/dev/null || true' EXIT
  for _ in $(seq 1 100); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8777/phase-4.7/page.html') == 200 ]] && break
    sleep 0.1
  done
fi
args=(-RoomStateDirectory "$work/state" -RoomEngineDirectory "$work/engine" -RoomDocumentsWorkDirectory "$work/files")
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
ROOM_SPIKE_OUT="$out" scripts/run-spike.sh documents -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"} "$@" >/dev/null || true
sleep 1
echo "== spike"
cat "$out"
echo
# Settings ▸ Downloads ▸ PDFs ▸ Download takes a launch: one run stores it,
# the next (on the same state, the feature passed at launch) opens the PDF.
if [[ -z "${ROOM_DOCUMENTS_NO_SETTING:-}" ]]; then
  for phase in pdfsetting pdfdownload; do
    out="$work/spike-$phase.txt"
    ROOM_SPIKE_OUT="$out" scripts/run-spike.sh documents -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"} -RoomSpikeOnly "$phase" >/dev/null || true
    sleep 1
    echo "== spike ($phase)"
    grep -v '^date:\|^loadavg:\|^launch_to_spike_s:' "$out" || true
    echo
  done
fi
echo "== files"
(cd "$work/files" 2>/dev/null && find . -type f -print0 | xargs -0 stat -f '%z %N' | sort -k2) || true
dumps=$(ls "$work"/engine/Crashpad/pending/*.dmp "$work"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
for dump in $dumps; do
  echo "crashpad_dump: $(basename "$dump") $(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || echo 'no FATAL line')"
done
echo "raw files: $work"
