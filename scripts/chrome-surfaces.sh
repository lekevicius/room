#!/usr/bin/env bash
# Phase 2.6: serves research/spikes/phase-2.6/ (HTTP :8766 with Basic auth at
# /auth and slow downloads at /download, self-signed HTTPS :8767), runs
# `-RoomSpike chromesurfaces` (2.6a) or, with `--session 2.6b`,
# `chromesurfaces2` (every delegate member, downloads, find, zoom, print, the
# status pill, the site panel, dismissals, a crash, fullscreen, DevTools)
# once per appearance (light, dark) and answers its capture requests:
# `capture: <name>` with a window-server capture of Room's window (its child
# windows included: popovers), `capture_screen: <name> x,y,w,h` with that
# screen rect (the context menu, a window of its own, inside Room's frame).
# Captures go to research/screenshots/phase-2.6a/ (or phase-2.6b/).
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/chrome-surfaces.sh [--session 2.6a|2.6b] [--no-captures] [light|dark ...] [-- extra app args]
set -euo pipefail
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
session=2.6a
captures=YES
appearances=()
[[ "${1:-}" == --session ]] && { session="$2"; shift 2; }
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-$session}"
spike=chromesurfaces
capture_flag=-RoomSpikeCaptures
if [[ $session == 2.6b ]]; then spike=chromesurfaces2; capture_flag=-RoomSpikeCaptures2b; fi
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
python3 research/spikes/phase-2.6/server.py 2>/tmp/room-2.6a-server.log &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
# This session's server (a stale one without /download would serve the pages but no downloads).
for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') == 200 ]] && break; sleep 0.1; done
if ! kill -0 $server 2>/dev/null || [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') != 200 ]]; then
  echo "test server did not start (port 8766 or 8767 taken?): $(tail -1 /tmp/room-2.6a-server.log)" >&2
  exit 1
fi

for appearance in "${appearances[@]}"; do
  OUT="$(mktemp -d)/spike-$spike-$appearance.txt"
  # A throwaway engine directory: permissions, the certificate exception and auth stay out of the real profile.
  engine_dir="$(mktemp -d)/engine"
  ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh "$spike" -RoomSidebarFixture demo -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" "$capture_flag" "$captures" "$@" >/dev/null &
  runner=$!
  done_names=""
  while kill -0 "$runner" 2>/dev/null; do
    if [[ -f "$OUT" ]]; then
      wid=$(awk -F': ' '/^window_id:/ {print $2}' "$OUT" | tail -1)
      while IFS= read -r line; do
        kind=${line%%: *}; rest=${line#*: }
        name=${rest%% *}
        [[ " $done_names " == *" $name "* ]] && continue
        if [[ $kind == capture ]]; then
          screencapture -x -o -l "$wid" "$DIR/$name.png"
        else
          screencapture -x -R "${rest#* }" "$DIR/$name.png"
        fi
        touch "$OUT.ack-$name"
        done_names="$done_names $name"
        echo "captured $DIR/$name.png" >&2
      done < <(grep -E '^capture(_screen)?: ' "$OUT" || true)
    fi
    sleep 0.2
  done
  echo "== $appearance"
  cat "$OUT"
done
