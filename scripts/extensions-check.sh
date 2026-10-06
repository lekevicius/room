#!/usr/bin/env bash
# Phase 4.5: the `extux` spike (App/Sources/Debug/ExtensionsUXSpikes.swift)
# with the engine's net-log: the 3.6 fixture extension loaded unpacked, its
# site access (On click until Run in the site panel, On this site across a
# reload), pin/unpin and the overflow menu, a command with the sidebar
# focused (B-70), the options page in a space of the extension's profile
# with two profiles (B-67), the shortcuts page and Settings ▸ Shortcuts'
# rows. Then the extension's own request: the fixture's named command
# fetches http://127.0.0.1:8771/room-extension-fetch, which the endpoint
# server logs and the net-log attributes to the extension's origin
# (initiator chrome-extension://<id>), apart from the engine's own requests
# (hosts that are not page traffic: 0 expected).
# Standalone it runs on a throwaway state under /tmp with the test servers;
# in the grand tour (ROOM_TOUR_SERVERS=1) on the tour's state and servers.
# `--spike <name>` runs another spike the same way (the tour's `extpopup`,
# 3.6b's popups, after 4.5's pinned-order change).
# The run always has its own state and engine directories under /tmp/room-4,
# also in the tour: an unpacked extension left in the tour's profile would
# run its content script and show its button in every later step; the
# engine's minidumps of the run are counted here (`crashpad_dumps:`).
# Usage: scripts/extensions-check.sh [--spike <name>] [capture-dir] [extra spike args...]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
SPIKE=extux
if [[ "${1:-}" == --spike ]]; then SPIKE="$2"; shift 2; fi
CAPS="${1:-}"
[[ $# -gt 0 ]] && shift
mkdir -p /tmp/room-4
server=""
args=()
endpoints="${ROOM_ENDPOINTS_LOG:-}"
work="$(mktemp -d /tmp/room-4/extensions.XXXXXX)"
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  if ! lsof -nP -iTCP:8770 -sTCP:LISTEN >/dev/null 2>&1; then
    endpoints="$work/endpoints.log"
    scripts/test-servers.sh "$endpoints" >/dev/null 2>&1 &
    server=$!
    trap '[[ -n "$server" ]] && { pkill -P "$server" 2>/dev/null; kill "$server" 2>/dev/null; } || true' EXIT
    for _ in $(seq 1 100); do
      [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 &&
         $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8771/appcast.xml') == 200 ]] && break
      sleep 0.1
    done
    sleep 0.5
    : > "$endpoints"   # the readiness probes are not Room's
  fi
fi
args=(-RoomStateDirectory "$work/state" -RoomEngineDirectory "$work/engine")
echo "state: $work"
# The tour's appearance and switches stay; its state and engine directories give way to the run's own.
if [[ -n "${ROOM_TOUR_ARGS:-}" ]]; then
  read -r -a tour <<<"$ROOM_TOUR_ARGS"
  kept=()
  for ((i = 0; i < ${#tour[@]}; i++)); do
    if [[ "${tour[$i]}" == -RoomStateDirectory || "${tour[$i]}" == -RoomEngineDirectory ]]; then i=$((i + 1)); continue; fi
    kept+=("${tour[$i]}")
  done
  export ROOM_TOUR_ARGS="${kept[*]}"
else
  args+=(-RoomSpikeAppearance light)
fi
# An absolute capture directory: the app's working directory is / (3.6a's finding).
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
start_line=0
[[ -n "$endpoints" && -f "$endpoints" ]] && start_line=$(wc -l < "$endpoints" | tr -d ' ')
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
out="$work/spike.txt"
ROOM_SPIKE_OUT="$out" scripts/run-spike.sh "$SPIKE" -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"} "$@" \
  "--log-net-log=$work/netlog.json" --net-log-capture-mode=Everything >/dev/null || true
sleep 1
echo "== spike"
cat "$out"
echo
dumps=$(ls "$work"/engine/Crashpad/pending/*.dmp "$work"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
for dump in $dumps; do
  echo "crashpad_dump: $(basename "$dump") $(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || echo 'no FATAL line')"
done
[[ "$SPIKE" != extux ]] && { echo "raw files: $work"; exit 0; }
echo "== the endpoint server's log during the run (:8771)"
if [[ -n "$endpoints" && -f "$endpoints" ]]; then
  lines=$(tail -n +"$((start_line + 1))" "$endpoints")
  printf '%s\n' "${lines:-none}"
  printf 'extension_fetch_server: %s request(s) to /room-extension-fetch\n' "$(printf '%s\n' "$lines" | grep -c 'room-extension-fetch' || true)"
else
  echo "no endpoints log"
fi
echo
echo "== the net-log by initiator"
python3 - "$work/netlog.json" <<'PY'
import json, sys, urllib.parse
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
try:
    log = json.loads(text)
except json.JSONDecodeError:
    cut = text.rstrip().rstrip(","); log = json.loads(cut[: cut.rfind("}") + 1] + "]}")
names = {v: k for k, v in log["constants"]["logEventTypes"].items()}
seen, rows = set(), []
for e in log["events"]:
    if names.get(e["type"]) != "URL_REQUEST_START_JOB" or e["source"]["id"] in seen:
        continue
    seen.add(e["source"]["id"])
    p = e.get("params") or {}
    rows.append((p.get("url", ""), p.get("initiator", "—"), p.get("method", "")))
ext = [r for r in rows if str(r[1]).startswith("chrome-extension://")]
fetches = [r for r in ext if "room-extension-fetch" in r[0]]
print(f"url_requests: {len(rows)}; initiated by an extension: {len(ext)}")
for url, initiator, method in ext:
    print(f"  {method} {url} · initiator {initiator}")
print(f"extension_fetch_netlog: {len(fetches)} with initiator {fetches[0][1] if fetches else 'none'}")
PY
echo
echo "== engine net-log by host (hosts that are not page traffic are the engine's)"
python3 scripts/lib/netlog-summary.py "$work/netlog.json" "$out" | tail -1 | sed 's/^/engine_netlog: /'
echo "raw files: $work"
