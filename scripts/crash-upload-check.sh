#!/usr/bin/env bash
# 6.3: crash reports end to end on a Debug app (the `crashupload` spike,
# App/Sources/Debug/CrashUploadSpikes.swift). Starts tools/crash-collector/collector.py
# on 127.0.0.1:8787 (key `public`, project 1) over a throwaway data directory,
# then runs the spike twice on one throwaway engine directory: crash reports
# off (the renderer's minidump stays in Crashpad/, nothing reaches the
# collector), then on (the next one is posted). Crashpad allows one upload an
# hour, so the run with consent comes last. Prints the spike's lines, the
# collector's reports and the engine's dumps after each run.
# ROOM_APP picks the app (default the dev build's Debug app).
# Needs scripts/test-servers.sh running (:8766).
# Usage: scripts/crash-upload-check.sh <out-dir>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output directory required}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8766 (scripts/test-servers.sh)" >&2; exit 1; }
WORK="/tmp/room-6/crash/run-$(date +%s)"
mkdir -p "$WORK/engine" "$WORK/collector"
ROOM_CRASH_KEYS=1:public ROOM_CRASH_DATA="$WORK/collector" python3 tools/crash-collector/collector.py --port 8787 > "$OUT/collector.log" 2>&1 &
collector=$!
trap 'kill $collector 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do [[ $(curl -s http://127.0.0.1:8787/health) == ok* ]] && break; sleep 0.1; done
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg) work=$WORK"
reports() { find "$WORK/collector" -name '*.dmp' | wc -l | tr -d ' '; }
dumps() { find "$WORK/engine/Crashpad" -name '*.dmp' 2>/dev/null | wc -l | tr -d ' '; }
for phase in off on; do
  mkdir -p "$WORK/state-$phase"
  ROOM_SPIKE_OUT="$OUT/spike-$phase.txt" scripts/run-spike.sh crashupload -RoomStateDirectory "$WORK/state-$phase" \
    -RoomEngineDirectory "$WORK/engine" -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES \
    -RoomCrashDSN http://public@127.0.0.1:8787/1 -RoomCrashPhase "$phase" >/dev/null || true
  echo "== $phase"
  grep -vE '^(date|loadavg):' "$OUT/spike-$phase.txt"
  echo "collector_reports: $(reports)"
  echo "engine_dumps: $(dumps)"
done
echo "== collector"
find "$WORK/collector" -name '*.json' -exec python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); a=d["annotations"]; print(d["bytes"], "bytes;", {k: a[k] for k in ("prod","ver","ptype","channel","plat") if k in a}, "fields:", len(a))' {} \;
grep -vE '^$' "$OUT/collector.log" || true
