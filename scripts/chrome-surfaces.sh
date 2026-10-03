#!/usr/bin/env bash
# Phase 2.6a: serves research/spikes/phase-2.6/ (HTTP :8766 with Basic auth at
# /auth, self-signed HTTPS :8767), runs `-RoomSpike chromesurfaces` once per
# appearance (light, dark) and answers its capture requests: `capture: <name>`
# with a window-server capture of Room's window (its child windows included:
# the permission popover), `capture_screen: <name> x,y,w,h` with that screen
# rect (the context menu, a window of its own, inside Room's frame). Captures go to research/screenshots/phase-2.6a/.
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/chrome-surfaces.sh [--no-captures] [light|dark ...] [-- extra app args]
set -euo pipefail
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-2.6a}"
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
python3 research/spikes/phase-2.6/server.py 2>/tmp/room-2.6a-server.log &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do curl -s -o /dev/null http://127.0.0.1:8766/dialogs.html && break; sleep 0.1; done

for appearance in "${appearances[@]}"; do
  OUT="$(mktemp -d)/spike-chromesurfaces-$appearance.txt"
  # A throwaway engine directory: permissions, the certificate exception and auth stay out of the real profile.
  engine_dir="$(mktemp -d)/engine"
  ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh chromesurfaces -RoomSidebarFixture demo -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" -RoomSpikeCaptures "$captures" "$@" >/dev/null &
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
