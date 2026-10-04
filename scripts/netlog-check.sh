#!/usr/bin/env bash
# Phase 2.8 exit check: with every opt-in declined, a launch, a short browse
# and a quit make no request from Room's own code. The 2.4b method, widened:
#   - Room's own code: Sparkle's feed, Sentry's DSN and the suggestion proxy all
#     point at research/spikes/phase-2.8/server.py (:8771), which logs every
#     request it gets; `nettop` records every Room process's sockets and bytes
#     (the main process is the app and its own code; the engine's network
#     service runs in a Room Helper).
#   - The engine: CEF's net-log (--log-net-log, capture mode Everything),
#     summarised by host with scripts/lib/netlog-summary.py (traffic
#     annotations named from the Chromium checkout when it is mounted).
# Page traffic (the local test site on 127.0.0.1:8770 and localhost:8770) is
# excluded by host. Runs `-RoomSpike netcheck` (AppIntegration2Spikes.swift)
# on a fresh state and engine directory with the first-run card shown.
# Usage: scripts/netlog-check.sh [output directory]
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
OUTDIR="${1:-$(mktemp -d)}"
mkdir -p "$OUTDIR"
work="$(mktemp -d)"
source scripts/lib/chromium-env.sh 2>/dev/null || true
annotations="${CHROMIUM_ROOT:-}/src/tools/traffic_annotation/summary/annotations.xml"

# ROOM_TOUR_SERVERS=1 (scripts/grand-tour.sh): the tour started both servers once and
# its endpoints' log is ROOM_ENDPOINTS_LOG; the check reads that log instead.
endpoints="$OUTDIR/endpoints.log"
pids=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  python3 research/spikes/phase-2.7/server.py 2>"$work/pages.log" &
  pids=$!
  python3 research/spikes/phase-2.8/server.py "$endpoints" 2>>"$work/pages.log" &
  pids="$pids $!"
else
  endpoints="$ROOM_ENDPOINTS_LOG"
fi
trap 'kill $pids 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 &&
     $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8771/appcast.xml') == 200 ]] && break
  sleep 0.1
done
: > "$endpoints"   # the readiness probes are not Room's
# Sparkle has never run for this check (its defaults would only matter once it is created).
for key in SUHasLaunchedBefore SULastCheckTime SUEnableAutomaticChecks SUUpdateGroupIdentifier SUSkippedVersion; do
  defaults delete app.room.desktop "$key" 2>/dev/null || true
done

nettop -L 0 -n -x -s 1 > "$work/nettop.csv" 2>/dev/null &
nettop_pid=$!
pids="$pids $nettop_pid"
sleep 1

ROOM_SPIKE_OUT="$OUTDIR/spike.txt" scripts/run-spike.sh netcheck -RoomFirstRun YES -ApplePersistenceIgnoreState YES \
  -RoomStateDirectory "$work/state" -RoomEngineDirectory "$work/engine" \
  -RoomUpdateFeedURL http://127.0.0.1:8771/appcast.xml -RoomSentryDSN http://public@127.0.0.1:8771/1 \
  -RoomSuggestProxy 127.0.0.1:8771 \
  "--log-net-log=$OUTDIR/netlog.json" --net-log-capture-mode=Everything >/dev/null
sleep 2
kill "$nettop_pid" 2>/dev/null || true

echo "== spike"
cat "$OUTDIR/spike.txt"
echo
echo "== Room's own code: requests to the dev feed, the crash endpoint and the suggestion proxy"
[[ "$endpoints" != "$OUTDIR/endpoints.log" ]] && cp "$endpoints" "$OUTDIR/endpoints.log"
if [[ -s "$OUTDIR/endpoints.log" ]]; then cat "$OUTDIR/endpoints.log"; else echo "none"; fi
echo
echo "== nettop: every Room process (max bytes in/out over the run; remote endpoints of the connections seen)"
awk -F, '
  /^time,/ { next }
  $2 ~ /^(tcp|udp)[46] / { if (proc ~ /^Room/) { split($2, a, "<->"); ep[proc] = ep[proc] " " a[2] "(" $3 ")" } next }
  { proc = $2; if (proc ~ /^Room/) { if ($5 + 0 > inb[proc]) inb[proc] = $5 + 0; if ($6 + 0 > outb[proc]) outb[proc] = $6 + 0; seen[proc] = 1 } }
  END { for (p in seen) { n = split(ep[p], list, " "); delete uniq; s = ""; for (i = 1; i <= n; i++) if (!(list[i] in uniq)) { uniq[list[i]] = 1; s = s " " list[i] }
        printf "%s in=%d out=%d endpoints:%s\n", p, inb[p], outb[p], (s == "" ? " none" : s) } }
' "$work/nettop.csv" | sort
cp "$work/nettop.csv" "$OUTDIR/nettop.csv"
echo
echo "== engine net-log by host"
python3 scripts/lib/netlog-summary.py "$OUTDIR/netlog.json" "$OUTDIR/spike.txt" \
  $( [[ -f "$annotations" ]] && echo --annotations "$annotations" ) | tee "$OUTDIR/netlog-summary.md"
echo
echo "raw files: $OUTDIR"
