#!/usr/bin/env bash
# 5.4a task 5: energy without privileges (`powermetrics` needs root). Runs
# `-RoomSpike energy` (App/Sources/Debug/EnergySpikes.swift) on the 50-entry
# fixture's ten typical sites: ten minutes idle with them loaded, then ten
# with the nine background pages discarded; per phase the app's processes'
# `proc_pid_rusage` differences (CPU, the kernel's energy estimate, wakeups)
# by process kind. The window is brought forward only until the pages are
# loaded: the wrappers' activation every second would wake the host.
# Usage: scripts/energy-check.sh <out-file> [extra app args, e.g. -RoomEnergySeconds 60]
# ROOM_APP picks the app (default the dev build's Debug app). The ten sites are
# real (the switching measurement's): run it only when that is wanted.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"; OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
source scripts/lib/room-process.sh
STATE="/tmp/room-5/energy/state-$(date +%s)"
mkdir -p "$STATE"
echo "load at start: $(sysctl -n vm.loadavg)" > "$OUT.conditions"
ROOM_SPIKE_NO_ACTIVATE=1 ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh energy -RoomSidebarFixture 50 \
  -RoomStateDirectory "$STATE" -RoomSuggestionsOff YES -ApplePersistenceIgnoreState YES "$@" > /dev/null &
runner=$!
until pid=$(pgrep -nf "RoomSpikeOutput $OUT"); do sleep 0.5; done
until grep -q '^phase_loaded' "$OUT" 2>/dev/null || ! kill -0 "$pid" 2>/dev/null; do room_activate "$pid"; sleep 1; done
echo "load at the loaded phase: $(sysctl -n vm.loadavg)" >> "$OUT.conditions"
until grep -q '^phase_discarded' "$OUT" 2>/dev/null || ! kill -0 "$pid" 2>/dev/null; do sleep 5; done
echo "load at the discarded phase: $(sysctl -n vm.loadavg)" >> "$OUT.conditions"
wait "$runner" || true
echo "load at the end: $(sysctl -n vm.loadavg)" >> "$OUT.conditions"
rm -rf "$STATE"
