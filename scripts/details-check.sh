#!/usr/bin/env bash
# 5.6a: the `details` spike (App/Sources/Debug/DetailsSpikes.swift): empty
# states, titles and the unread dot, Change Icon…, Clear on hover (B-118),
# "Prevent additional dialogs" (B-116), nested folders (B-117), on a fresh
# throwaway state and engine directory under /tmp/room-5/details/, search
# suggestions off. Prints the spike's lines.
# Usage: scripts/details-check.sh <out-file> [capture-dir] [extra app args, e.g. -RoomSpikeOnly dialogs -RoomSpikeAppearance dark]
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
WORK="/tmp/room-5/details/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
args=(-RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES)
# An absolute capture directory: the app's working directory is / (3.6a's finding).
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg) state=$WORK"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh details "${args[@]}" "$@" >/dev/null || true
cat "$OUT"
dumps=$(ls "$WORK"/engine/Crashpad/pending/*.dmp "$WORK"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
