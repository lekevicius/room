#!/usr/bin/env bash
# 5.2a: the visual audit's screenshot matrix (`-RoomSpike matrix`,
# App/Sources/Debug/MatrixSpikes.swift): every surface light and dark, active
# and inactive, one contact sheet per surface under
# research/screenshots/phase-5.2/ (phase-5.2-<surface><suffix>.png), on a fresh
# throwaway state and engine directory under /tmp/room-5/matrix/, search
# suggestions off. Rerunnable: later phases shoot it again for before/after.
# Usage: scripts/visual-matrix.sh <out-file> [suffix] [extra app args, e.g. -RoomSpikeOnly rows,footer]
#   suffix: appended to each sheet's name after a dash ("before" → -before; "" for the current state).
# ROOM_APP picks the app (default the dev build's Debug app; the release
# framework's: build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
# ROOM_MATRIX_DIR overrides the sheets' directory (a release-framework run into build/).
# Needs scripts/test-servers.sh running (:8766, :8767).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
SUFFIX="${1:-}"; [[ $# -gt 0 ]] && shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
WORK="/tmp/room-5/matrix/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh matrix -RoomSpikeSheetDirectory "${ROOM_MATRIX_DIR:-$ROOT/research/screenshots/phase-5.2}" \
  -RoomMatrixSuffix "$SUFFIX" -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" -ApplePersistenceIgnoreState YES \
  -RoomSuggestionsOff YES "$@"
rm -rf "$WORK"
