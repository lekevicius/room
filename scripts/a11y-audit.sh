#!/usr/bin/env bash
# 5.3a: the accessibility self-audit over the real app (`-RoomSpike a11y`,
# App/Sources/Debug/AccessibilitySpikes.swift): the matrix's surfaces set up
# one after another on a throwaway state, every visible window walked through
# its own NSAccessibility protocol (in-process; no AX client, no prompt).
# Usage: scripts/a11y-audit.sh <out-file> [extra app args, e.g. -RoomSpikeOnly window,palette]
# ROOM_APP picks the app (default the dev build's Debug app). Needs scripts/test-servers.sh (:8766, :8767).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
WORK="/tmp/room-5/a11y/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh a11y -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" > /dev/null
rm -rf "$WORK"
grep -E '^a11y_|^error|^window_main' "$OUT"
