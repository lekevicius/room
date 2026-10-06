#!/usr/bin/env bash
# Phase 2.3 exit measurement (on CEF then; RoomCore since 3.9): 50 entries with 10 loaded (the Phase 1.4
# typical sites), summed RSS, 100 selection switches (main-thread time and
# the page's own visible/first-frame times), then a quit and a relaunch on
# the same state directory (pages loaded at launch, time to the selected
# page). Prints both spike reports.
# Usage: scripts/tabs-measure.sh [output-dir]
# The engine directory is the state's own (a throwaway one; without it the
# Debug app opens the real engine root, which a running Room holds: laptop, 2026-10-06).
set -euo pipefail

OUT="${1:-$(mktemp -d)}"
STATE="$OUT/state"
mkdir -p "$OUT"
rm -rf "$STATE"
echo "load average: $(sysctl -n vm.loadavg)"
ROOM_SPIKE_OUT="$OUT/switch.txt" scripts/run-spike.sh switch -RoomSidebarFixture 50 -RoomStateDirectory "$STATE" -RoomEngineDirectory "$STATE/engine" >/dev/null
# Wait for the helpers of the first run to be gone before relaunching.
source "$(dirname "$0")/lib/room-process.sh"
while pgrep -f "$ROOM_HELPER_PATTERN" >/dev/null; do sleep 0.5; done
ROOM_SPIKE_OUT="$OUT/relaunch.txt" scripts/run-spike.sh relaunch -RoomStateDirectory "$STATE" -RoomEngineDirectory "$STATE/engine" >/dev/null
cat "$OUT/switch.txt" "$OUT/relaunch.txt"
