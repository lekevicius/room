#!/usr/bin/env bash
# 4.1b (B-59): a download removed through the Library and one cleared from the
# popover stay gone after a relaunch; a kept one is listed again (Chrome's
# DownloadHistory replays it). Two launches of `chromesurfaces2` on one fresh
# throwaway state: `downloadremove`, then `downloadsrestore`.
# Usage: scripts/download-remove-check.sh <new-evidence-dir>
# ROOM_APP picks the app (default: the dev build's Debug app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEST="${1:?new evidence directory required}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
STATE="$(mktemp -d /tmp/room-41b-downloads.XXXXXX)"
server_pid=""
if ! lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
  scripts/test-servers.sh "$DEST/endpoints.log" >/dev/null 2>&1 &
  server_pid=$!
  trap '[[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true' EXIT
  for _ in $(seq 1 100); do
    [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') == 200 ]] && break
    sleep 0.1
  done
fi
echo "app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} state=$STATE load=$(sysctl -n vm.loadavg)" | tee "$DEST/conditions.txt"
ROOM_SPIKE_OUT="$DEST/remove.txt" scripts/run-spike.sh chromesurfaces2 -RoomSpikeOnly downloadremove \
  -RoomStateDirectory "$STATE" >/dev/null
ROOM_SPIKE_OUT="$DEST/relaunch.txt" scripts/run-spike.sh chromesurfaces2 -RoomSpikeOnly downloadsrestore \
  -RoomStateDirectory "$STATE" >/dev/null
grep '^download_remove:' "$DEST/remove.txt" || echo "download_remove: missing"
grep '^download_restored:' "$DEST/relaunch.txt" || echo "download_restored: missing"
minidumps=$(find "$STATE/engine" -path '*Crashpad*' -name '*.dmp' 2>/dev/null | wc -l | tr -d ' ')
echo "minidumps: $minidumps"
if grep -q '^download_restored: rows=1 .*unknown' "$DEST/relaunch.txt"; then
  echo "result: passed (only the kept download is listed after the relaunch)"
else
  echo "result: FAILED"; exit 1
fi
