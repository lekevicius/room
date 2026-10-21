#!/usr/bin/env bash
# 5.4a task 4: leaks and the host's footprint. Runs one spike section on a
# fresh throwaway state with -RoomSpikeKeepRunning YES (and MallocStackLogging,
# so a leak comes with its allocation stack), then, on that process only:
# `footprint`, `vmmap --summary` and `leaks`; then quits it by pid.
# Sections: `motion` (the motion harness's two groups: the sidebar's
# animations, the palette, Peek, the switcher, toasts, downloads, split, the
# reveal; needs scripts/test-servers.sh on :8766) and `openclose` (50 Today
# tabs opened, loaded from :8766 and closed).
# Usage: scripts/leaks-check.sh <out-dir> <motion|openclose> [extra app args]
# ROOM_APP picks the app (default the dev build's Debug app). ROOM_LEAKS_MSL=0
# runs without MallocStackLogging: its records count in the footprint
# ("Performance Tool Data", ~240 MB after the motion section), so footprint
# numbers come from a run without it, leak stacks from a run with it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output directory required}"; SECTION="${2:?section required}"; shift 2
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
source scripts/lib/room-process.sh
STATE="/tmp/room-5/leaks/state-$SECTION-$(date +%s)"
mkdir -p "$STATE"
spike="$SECTION"
echo "load before: $(sysctl -n vm.loadavg)" > "$OUT/conditions.txt"
msl="MallocStackLogging=1"; [[ "${ROOM_LEAKS_MSL:-1}" == 0 ]] && msl=""
ROOM_SPIKE_ENV="$msl" ROOM_SPIKE_OUT="$OUT/spike.txt" scripts/run-spike.sh "$spike" \
  -RoomStateDirectory "$STATE" -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES -RoomSpikeKeepRunning YES "$@" > /dev/null
pid=$(pgrep -nf "RoomSpikeOutput $OUT/spike.txt")
echo "pid $pid; load after the section: $(sysctl -n vm.loadavg)" >> "$OUT/conditions.txt"
sleep 3
footprint "$pid" > "$OUT/footprint.txt" 2>&1 || echo "footprint exit $?" >> "$OUT/footprint.txt"
vmmap --summary "$pid" > "$OUT/vmmap-summary.txt" 2>&1 || echo "vmmap exit $?" >> "$OUT/vmmap-summary.txt"
set +e
leaks "$pid" > "$OUT/leaks.txt" 2>&1
echo "leaks exit $?" >> "$OUT/leaks.txt"
set -e
room_quit "$pid" || kill -TERM "$pid"
while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
rm -rf "$STATE"
grep -E "^Process .*leaks for|leaks exit" "$OUT/leaks.txt" || true
grep -E "Physical footprint" "$OUT/vmmap-summary.txt" || true
