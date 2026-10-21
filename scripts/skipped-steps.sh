#!/usr/bin/env bash
# 5.0b: the `skipped` spike (App/Sources/Debug/SkippedStepsSpikes.swift), the
# Chapter 4 by-hand steps the user skipped that no earlier spike drove, one
# launch per group on its own throwaway state under /tmp/room-5/skipped/:
#   41     archive (steps 2–6), on an empty sidebar
#   42     routing (steps 11–14, 16, 18, 19) on the routing fixture, links from
#          another process by `open -a <app> <url>` as Terminal sends them;
#          then routingverify (step 13's relaunch) on the same state
#   43     importsheet (steps 20–24, 29) on the 4.3 fixtures
#   44     search (step 33)
#   45     extensions (steps 46, 47) with the 3.6 fixture; then extensionsverify
#   46     autoplay (step 54)
#   47     print (step 64; Return only on a Mac with no printer set up)
#   48     windows (steps 65, 66, 74, 68's setup); then windowsrelaunch (68, 67)
# Search suggestions are off (-RoomSuggestionsOff): the palette checks send no
# query to a search engine; step 33's keyword check loads YouTube's results page
# once (the check's own request). Needs scripts/test-servers.sh running (:8766, :8770, :8776).
# Usage: scripts/skipped-steps.sh <evidence-dir> [group ...]   (default: all)
# ROOM_APP picks the app (default the dev build's Debug app; the release
# framework's: build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DEST="${1:?evidence directory required}"; shift
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
groups=("$@")
[[ ${#groups[@]} -eq 0 ]] && groups=(41 42 43 44 45 46 47 48)
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
export ROOM_APP="$APP"
for port in 8766 8770 8776; do
  lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :$port (scripts/test-servers.sh)" >&2; exit 1; }
done
STATES=/tmp/room-5/skipped
mkdir -p "$STATES"
echo "app=$APP load=$(sysctl -n vm.loadavg) printers=$(lpstat -p 2>/dev/null | grep -c '^printer' || true)" | tee "$DEST/conditions.txt"

run() { # run <out-name> <state-name> <app args...>
  local name=$1 state=$2; shift 2
  ROOM_SPIKE_OUT="$DEST/$name.txt" scripts/run-spike.sh skipped -RoomStateDirectory "$STATES/$state" \
    -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" >/dev/null || echo "$name: the spike exited non-zero" >&2
}

# The routing group answers each `send_link: <n> <url>` line with `open -a`, as Terminal would.
links() { # links <out-file>
  local out=$1 answered=0 n url
  while :; do
    [[ -f "$out" ]] || { sleep 0.3; continue; }
    grep -q '^send_link: done' "$out" && break
    grep -q '^end:' "$out" && break
    while read -r n url; do
      if (( n > answered )); then
        open -a "$APP_ABS" "$url"
        answered=$n
      fi
    done < <(grep '^send_link: [0-9]' "$out" | sed 's/^send_link: //')
    sleep 0.3
  done
}

for group in "${groups[@]}"; do
  case "$group" in
    41) rm -rf "$STATES/41"; run 41-archive 41 -RoomSpikeOnly archive ;;
    42)
      rm -rf "$STATES/42"
      rm -f "$DEST/42-routing.txt"
      links "$DEST/42-routing.txt" &
      watcher=$!
      run 42-routing 42 -RoomSpikeOnly routing -RoomSidebarFixture routing
      kill "$watcher" 2>/dev/null || true
      run 42-routing-relaunch 42 -RoomSpikeOnly routingverify ;;
    43) rm -rf "$STATES/43"; run 43-import 43 -RoomSpikeOnly importsheet -RoomSidebarFixture import -RoomImportSource "$ROOT/research/spikes/phase-4.3" \
          -RoomImportHome "$STATES/43-home" -RoomWebStorePage "file://$ROOT/research/spikes/phase-4.3/webstore/detail.html?id={id}" ;;
    44) rm -rf "$STATES/44"; run 44-search 44 -RoomSpikeOnly search ;;
    45) rm -rf "$STATES/45"; run 45-extensions 45 -RoomSpikeOnly extensions; run 45-extensions-relaunch 45 -RoomSpikeOnly extensionsverify ;;
    46) rm -rf "$STATES/46"; run 46-autoplay 46 -RoomSpikeOnly autoplay ;;
    47) rm -rf "$STATES/47"; run 47-print 47 -RoomSpikeOnly print ;;
    48) rm -rf "$STATES/48"; run 48-windows 48 -RoomSpikeOnly windows; run 48-windows-relaunch 48 -RoomSpikeOnly windowsrelaunch ;;
    *) echo "unknown group $group" >&2; exit 2 ;;
  esac
done
cat "$DEST"/*.txt | grep -E '^(step|error|tabs|end)' || true
