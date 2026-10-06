#!/usr/bin/env bash
# Captures the sidebar (Phase 2.2) with a fixture loaded into a throwaway
# state directory, through the app's DEBUG sidebar snapshot runner, and
# prints the runner's report (states and, for the 500 fixture, timings).
# The app may not be allowed to activate itself, so this script activates
# it from outside until the runner finishes.
# Usage: scripts/sidebar-snapshots.sh [demo|500] [output-dir] [path/to/Room.app]
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is passed to the app.
set -euo pipefail

FIXTURE="${1:-demo}"
OUT_ARG="${2:-research/screenshots/phase-2.2b}"
mkdir -p "$(dirname "$OUT_ARG")"
OUT="$(cd "$(dirname "$OUT_ARG")" && pwd)/$(basename "$OUT_ARG")"
APP="${3:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
# Activate goes to our process by pid, never by bundle id (B-47).
source "$(dirname "$0")/lib/room-process.sh"
room_scope "$APP"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
mkdir -p "$OUT"
# Room instances without arguments that were already running (the user's own).
before=$(pgrep -f "$ROOM_MAIN_PATTERN$" || true)
rm -f "$OUT/states.txt"
# shellcheck disable=SC2086
open -n "$APP" --args -RoomSnapshotDirectory "$OUT" -RoomSidebarFixture "$FIXTURE" ${ROOM_TOUR_ARGS:-}
sleep 2
# Our instance, by its arguments: `osascript … activate` can relaunch Room
# without arguments if it lands just after a quit (Phase 1.4 note).
pid=$(pgrep -nf "RoomSnapshotDirectory $OUT" || true)
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  [[ -f "$OUT/states.txt" ]] && break
  room_activate "$pid"
  sleep 1
done
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
# An activate that lands just after the quit relaunches Room without
# arguments (on the real state directory); stop any such stray.
sleep 2
for stray in $(pgrep -f "$ROOM_MAIN_PATTERN$" || true); do
  grep -qx "$stray" <<<"$before" || { echo "stopping stray relaunch $stray" >&2; kill -TERM "$stray"; }
done
cat "$OUT/states.txt"
