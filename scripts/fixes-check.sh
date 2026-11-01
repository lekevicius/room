#!/usr/bin/env bash
# 5.11: the `fixes` spike (App/Sources/Debug/Fixes511Spikes.swift): the
# user's notes on build 25 (a row drag through the event queue, the folder
# preview's clicks, the docked sidebar's slide, the site panel's anchor, the
# extensions menu, review captures) on a fresh throwaway state and engine
# directory under /tmp/room-5/fixes/, search suggestions off.
# Prints the spike's lines.
# ROOM_FIXES_SPIKE=fixes512 runs 5.12's spike (App/Sources/Debug/Fixes512Spikes.swift) instead.
# Usage: scripts/fixes-check.sh <out-file> [capture-dir] [extra app args, e.g. -RoomSpikeOnly devtools -RoomSpikeAppearance dark]
# ROOM_APP picks the app (default the dev build's Debug app; the release
# framework's: build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
# Needs scripts/test-servers.sh running (:8766).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
CAPS="${1:-}"; [[ $# -gt 0 ]] && shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
WORK="/tmp/room-5/fixes/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
args=(-RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES)
# An absolute capture directory: the app's working directory is / (3.6a's finding).
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg) state=$WORK"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh "${ROOM_FIXES_SPIKE:-fixes}" "${args[@]}" "$@" >/dev/null || true
cat "$OUT"
dumps=$(ls "$WORK"/engine/Crashpad/pending/*.dmp "$WORK"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
