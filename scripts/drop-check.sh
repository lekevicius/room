#!/usr/bin/env bash
# 5.5b: the drop matrix and the haptics audit (`-RoomSpike drops`, App/Sources/Debug/DropSpikes.swift):
# six sources (a link, two links, text, two URLs as text, image data, a file) onto the sidebar's list,
# the card's page and a space icon, a link onto Essentials, text into a page's textarea; the insertion
# line and haptic ticks read back; no tick on hover; the split divider's snap. Pasteboards are made
# in-process and handed to Room's own drop code. Needs scripts/test-servers.sh (:8770, :8771, :8776).
# A throwaway state; searches go to a local engine (no request to a real site).
# Usage: scripts/drop-check.sh <out-file> [extra app args, e.g. -RoomSpikeOnly matrix]. ROOM_APP picks the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="/tmp/room-5/drops/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh drops -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES -RoomSpikeCaptureDirectory "$(dirname "$OUT")" "$@" > /dev/null
rm -rf "$WORK"
grep -vE '^(date|spike|end):' "$OUT"
