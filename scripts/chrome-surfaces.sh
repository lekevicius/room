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
# `--session 3.4b` runs `pageservices` (the hung page, external protocols
# with the throwaway roomtest: handler of scripts/external-protocol-fixture.sh,
# the translate offer, an engine infobar, capture state with fake devices,
# the media session, a device chooser) with the arguments it needs.
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/chrome-surfaces.sh [--session 2.6a|2.6b|3.4b] [--no-captures] [light|dark ...] [-- extra app args]
set -euo pipefail
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
session=2.6a
captures=YES
appearances=()
[[ "${1:-}" == --session ]] && { session="$2"; shift 2; }
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-$session}"
spike=chromesurfaces
capture_flag=-RoomSpikeCaptures
if [[ $session == 2.6b ]]; then spike=chromesurfaces2; capture_flag=-RoomSpikeCaptures2b; fi
session_args=()
if [[ $session == 3.4b ]]; then
  spike=pageservices; capture_flag=-RoomSpikeCaptures3b
  port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
  external_log="$(mktemp -d)/roomtest-handler.log"
  ROOM_EXTERNAL_LOG="$external_log" scripts/external-protocol-fixture.sh install >&2
  trap 'scripts/external-protocol-fixture.sh remove >&2 || true' EXIT
  # Chrome offers translation only with an API key configured; a placeholder
  # makes the offer appear (the translation itself then fails: no real key).
  export ROOM_SPIKE_ENV="${ROOM_SPIKE_ENV:-GOOGLE_API_KEY=room-placeholder-no-key}"
  session_args=(--enable-features=RendererHangWatcher:delay/3s --use-fake-device-for-media-stream
                "--remote-debugging-port=$port" -RoomSpikeCDPPort "$port" -RoomSpikeExternalLog "$external_log")
fi
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
# ROOM_TOUR_SERVERS=1 (scripts/grand-tour.sh): the tour started the server once; use it.
server=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  python3 research/spikes/phase-2.6/server.py 2>/tmp/room-2.6a-server.log &
  server=$!
  if [[ $session == 3.4b ]]; then
    trap 'kill $server 2>/dev/null || true; scripts/external-protocol-fixture.sh remove >&2 || true' EXIT
  else
    trap 'kill $server 2>/dev/null || true' EXIT
  fi
fi
# This session's server (a stale one without /download would serve the pages but no downloads).
for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') == 200 ]] && break; sleep 0.1; done
if { [[ -n "$server" ]] && ! kill -0 $server 2>/dev/null; } || [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') != 200 ]]; then
  echo "test server did not start (port 8766 or 8767 taken?): $(tail -1 /tmp/room-2.6a-server.log 2>/dev/null)" >&2
  exit 1
fi

for appearance in "${appearances[@]}"; do
  OUT="$(mktemp -d)/spike-$spike-$appearance.txt"
  # A throwaway engine directory: permissions, the certificate exception and auth stay out of the real profile.
  engine_dir="$(mktemp -d)/engine"
  ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh "$spike" -RoomSidebarFixture demo -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" "$capture_flag" "$captures" \
    ${session_args[@]+"${session_args[@]}"} "$@" >/dev/null &
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
