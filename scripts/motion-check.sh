#!/usr/bin/env bash
# 5.1a: the motion harness (`-RoomSpike motion`, App/Sources/Debug/MotionSpikes.swift)
# on a fresh throwaway state under /tmp/room-5/motion/, search suggestions off.
# Prints the spike's lines; the `motion_table:` lines are the run's table.
# Usage: scripts/motion-check.sh <out-file> [extra app args, e.g. -RoomReduceMotion YES]
# 5.1b: `-RoomSpikeOnly overlays` (or `sidebar`) runs one group; ROOM_MOTION_SPIKE=motionsheet
# writes the review sheet's contact sheets instead (research/screenshots/phase-5.1/).
# ROOM_APP picks the app (default the dev build's Debug app; the release
# framework's: build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
# Needs scripts/test-servers.sh running (:8766).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
STATE="/tmp/room-5/motion/state-$(date +%s)"
mkdir -p "$STATE"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh "${ROOM_MOTION_SPIKE:-motion}" -RoomSpikeSheetDirectory "$ROOT/research/screenshots/phase-5.1" -RoomStateDirectory "$STATE" -ApplePersistenceIgnoreState YES \
  -RoomSuggestionsOff YES "$@"
rm -rf "$STATE"
