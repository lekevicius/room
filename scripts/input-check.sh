#!/usr/bin/env bash
# 5.5a: keyboards, mice and the history swipe (`-RoomSpike input`, App/Sources/Debug/InputSpikes.swift):
# marked text into the palette, the rename field and a page; dead keys; the mouse's back and forward
# buttons, middle-/⌘-/⇧-clicks on links, horizontal wheel over the sidebar; scroll-phase swipes over the
# card and the sidebar; B-102's field. Events are made in-process and sent to Room's own window.
# Needs scripts/test-servers.sh (:8770, :8776). A throwaway state, suggestions off.
# Usage: scripts/input-check.sh <out-file> [extra app args, e.g. -RoomSpikeOnly mouse,swipe]. ROOM_APP picks the app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="/tmp/room-5/input/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh input -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" > /dev/null
rm -rf "$WORK"
grep -vE '^(date|spike|end):' "$OUT"
