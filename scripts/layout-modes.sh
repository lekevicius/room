#!/usr/bin/env bash
# Phase 2.7a: serves research/spikes/phase-2.7/ (HTTP :8770, answering as
# 127.0.0.1 and as localhost, two sites), runs `-RoomSpike layoutmodes`
# (hide/reveal timing, the floating traffic-light cluster, the optional
# toolbar, Peek's off-site rule on CEF, Peek open timing, event isolation
# under the Peek dim and the sidebar overlay) once per appearance (light,
# dark) and answers its `capture: <name>` requests with a window-server
# capture of Room's window. Captures go to research/screenshots/phase-2.7a/.
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/layout-modes.sh [--no-captures] [light|dark ...] [-- extra app args, e.g. -RoomSpikeOnly peek]
set -euo pipefail
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-2.7a}"
captures=YES
appearances=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-captures) captures=NO; shift ;;
    light|dark) appearances+=("$1"); shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[[ ${#appearances[@]} -eq 0 ]] && appearances=(light dark)
mkdir -p "$DIR"
log="$(mktemp -d)/server.log"
# ROOM_TOUR_SERVERS=1 (scripts/grand-tour.sh): the tour started the server once; use it.
server=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  python3 research/spikes/phase-2.7/server.py 2>"$log" &
  server=$!
  trap 'kill $server 2>/dev/null || true' EXIT
fi
for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 ]] && break; sleep 0.1; done
if { [[ -n "$server" ]] && ! kill -0 $server 2>/dev/null; } || [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') != 200 ]]; then
  echo "test server did not start (port 8770 taken?): $(tail -1 "$log")" >&2
  exit 1
fi

for appearance in "${appearances[@]}"; do
  OUT="$(mktemp -d)/spike-layoutmodes-$appearance.txt"
  engine_dir="$(mktemp -d)/engine"
  ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh layoutmodes -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" -RoomSpikeCaptures27 "$captures" "$@" >/dev/null &
  runner=$!
  done_names=""
  while kill -0 "$runner" 2>/dev/null; do
    if [[ -f "$OUT" ]]; then
      wid=$(awk -F': ' '/^window_id:/ {print $2}' "$OUT" | tail -1)
      while IFS= read -r line; do
        name=${line#capture: }
        [[ " $done_names " == *" $name "* ]] && continue
        screencapture -x -o -l "$wid" "$DIR/$name.png"
        touch "$OUT.ack-$name"
        done_names="$done_names $name"
        echo "captured $DIR/$name.png" >&2
      done < <(grep -E '^capture: ' "$OUT" || true)
    fi
    sleep 0.2
  done
  echo "== $appearance"
  cat "$OUT"
done
