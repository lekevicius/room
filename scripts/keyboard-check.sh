#!/usr/bin/env bash
# 5.3a: the key path by keyboard alone (`-RoomSpike keyboard`, App/Sources/Debug/KeyboardSpikes.swift):
# key events posted to Room's own window, the focus read back; the Tab order in the default keyboard
# mode and with Full Keyboard Access (switched in-process, never the system setting); the sidebar to
# a page and back, the address field, the palette, a toast, Esc out of Peek, the Library and the
# downloads popover. A throwaway state, suggestions off; no click, no pasteboard.
# Usage: scripts/keyboard-check.sh <out-file> [extra app args]. ROOM_APP picks the app (default the dev build's).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="/tmp/room-5/keyboard/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh keyboard -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" > /dev/null
rm -rf "$WORK"
grep -E '^keyboard_|^error|^window_main' "$OUT"
