#!/usr/bin/env bash
# 5.2b, B-103: Chrome's own pages in Room read back for "Chromium" (`-RoomSpike branding`,
# App/Sources/Debug/BrandingSpikes.swift) on a throwaway state, and the notification icon (the
# alerts helper's bundle icon). Print preview opens with no document and nothing is printed.
# Usage: scripts/branding-check.sh <out-file> [extra app args, e.g. -RoomSpikeSheetDirectory <dir> -RoomSpikeAppearance dark]
# ROOM_APP picks the app (default the dev build's Debug app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="/tmp/room-5/branding/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh branding -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" > /dev/null
grep -h "branded strings" "$WORK"/engine/RoomCore.log 2>/dev/null | sed "s/^/engine_log: /" >> "$OUT" || true
rm -rf "$WORK"
grep -E '^branding_|^error|^engine_log' "$OUT"
