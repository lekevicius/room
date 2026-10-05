#!/usr/bin/env bash
# Phase 2.5 captures: runs `-RoomSpike spacecaptures` on the `spaces` fixture
# and answers each `capture: <name>` line with a window-server capture of
# Room's window (real pages included, unlike in-process renders), saved as
# research/screenshots/<name>.png. Needs the screen unlocked and Screen
# Recording for the shell that runs it.
set -euo pipefail
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
DIR="${ROOM_CAPTURE_DIR:-research/screenshots}"
OUT="$(mktemp -d)/spike-spacecaptures.txt"
mkdir -p "$DIR"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh spacecaptures -RoomSidebarFixture spaces "$@" >/dev/null &
runner=$!
done_names=""
while kill -0 "$runner" 2>/dev/null; do
  if [[ -f "$OUT" ]]; then
    wid=$(awk -F': ' '/^window_id:/ {print $2}' "$OUT" | tail -1)
    for name in $(awk -F': ' '/^capture:/ {print $2}' "$OUT"); do
      [[ " $done_names " == *" $name "* ]] && continue
      screencapture -x -o -l "$wid" "$DIR/$name.png"
      touch "$OUT.ack-$name"
      done_names="$done_names $name"
      echo "captured $DIR/$name.png"
    done
  fi
  sleep 0.2
done
cat "$OUT"
