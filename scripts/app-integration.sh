#!/usr/bin/env bash
# Phase 2.8a: serves research/spikes/phase-2.7/ (HTTP :8770), runs
# `-RoomSpike appintegration` (App/Sources/Debug/AppIntegrationSpikes.swift:
# every menu item with its key, validation and target, the menu bar's
# validation time, Settings on each section, the sidebar on the right,
# fullscreen on a real Space) once per appearance (light, dark), and answers
# its `capture: <name>` requests with a window-server capture of Room's
# window, or of the window numbered in `capture: <name>@<number>` (an open
# menu, the Settings window). Captures go to research/screenshots/phase-2.8a/.
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/app-integration.sh [--no-captures] [light|dark ...] [-- extra app args, e.g. -RoomSpikeOnly menus]
set -euo pipefail
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-2.8a}"
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
python3 research/spikes/phase-2.7/server.py 2>"$log" &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 ]] && break; sleep 0.1; done
if ! kill -0 $server 2>/dev/null; then
  echo "test server did not start (port 8770 taken?): $(tail -1 "$log")" >&2
  exit 1
fi

for appearance in "${appearances[@]}"; do
  OUT="$(mktemp -d)/spike-appintegration-$appearance.txt"
  engine_dir="$(mktemp -d)/engine"
  ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh appintegration -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" -RoomSpikeCaptures28 "$captures" "$@" >/dev/null &
  runner=$!
  done_names=""
  while kill -0 "$runner" 2>/dev/null; do
    if [[ -f "$OUT" ]]; then
      main=$(awk -F': ' '/^window_id:/ {print $2}' "$OUT" | tail -1)
      while IFS= read -r line; do
        request=${line#capture: }
        name=${request%@*}
        wid=$main
        [[ "$request" == *@* ]] && wid=${request##*@}
        [[ " $done_names " == *" $name "* ]] && continue
        screencapture -x -o -l "$wid" "$DIR/$name.png" || echo "capture of $name (window $wid) failed" >&2
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
