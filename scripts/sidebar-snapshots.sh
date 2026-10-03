#!/usr/bin/env bash
# Captures the sidebar (Phase 2.2) with a fixture loaded into a throwaway
# state directory, through the app's DEBUG sidebar snapshot runner, and
# prints the runner's report (states and, for the 500 fixture, timings).
# The app may not be allowed to activate itself, so this script activates
# it from outside until the runner finishes.
# Usage: scripts/sidebar-snapshots.sh [demo|500] [output-dir] [path/to/Room.app]
set -euo pipefail

FIXTURE="${1:-demo}"
OUT_ARG="${2:-research/screenshots/phase-2.2b}"
mkdir -p "$(dirname "$OUT_ARG")"
OUT="$(cd "$(dirname "$OUT_ARG")" && pwd)/$(basename "$OUT_ARG")"
APP="${3:-build/DerivedData/Build/Products/Debug/Room.app}"
BUNDLE_ID="com.lekevicius.room"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
mkdir -p "$OUT"
# Room instances without arguments that were already running (the user's own).
before=$(pgrep -f "Room.app/Contents/MacOS/Room$" || true)
rm -f "$OUT/states.txt"
open -n "$APP" --args -RoomSnapshotDirectory "$OUT" -RoomSidebarFixture "$FIXTURE"
sleep 2
# Our instance, by its arguments: `osascript … activate` can relaunch Room
# without arguments if it lands just after a quit (Phase 1.4 note).
pid=$(pgrep -nf "RoomSnapshotDirectory $OUT" || true)
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  [[ -f "$OUT/states.txt" ]] && break
  osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
  sleep 1
done
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
# An activate that lands just after the quit relaunches Room without
# arguments (on the real state directory); stop any such stray.
sleep 2
for stray in $(pgrep -f "Room.app/Contents/MacOS/Room$" || true); do
  grep -qx "$stray" <<<"$before" || { echo "stopping stray relaunch $stray" >&2; kill -TERM "$stray"; }
done
cat "$OUT/states.txt"
