#!/usr/bin/env bash
# Phase 2.8a: serves research/spikes/phase-2.7/ (HTTP :8770), runs
# `-RoomSpike appintegration` (App/Sources/Debug/AppIntegrationSpikes.swift:
# every menu item with its key, validation and target, the menu bar's
# validation time, Settings on each section, the sidebar on the right,
# fullscreen on a real Space) once per appearance (light, dark), and answers
# its `capture: <name>` requests with a window-server capture of Room's
# window, or of the window numbered in `capture: <name>@<number>` (an open
# menu, the Settings window). Captures go to research/screenshots/phase-2.8a/.
#
# `--session 2.8b` runs `appintegration2` (AppIntegration2Spikes.swift)
# instead: Room is launched by a link (the cold-launch ingestion), the
# first-run card shows (-RoomFirstRun), research/spikes/phase-2.8/server.py
# serves the dev update feed and a stand-in crash endpoint on :8771 and logs
# every request, and `open_url: <name> <method> <url>` requests are answered
# by handing Room the link with `open -a`, AppleScript's `open location`, or
# another process's NSWorkspace.open(_:withApplicationAt:) (the ack file
# holds the time of the hand-over). Captures go to research/screenshots/phase-2.8b/.
# Needs the screen unlocked and Screen Recording for the shell that runs it.
# Usage: scripts/app-integration.sh [--session 2.8a|2.8b] [--no-captures] [light|dark ...] [-- extra app args, e.g. -RoomSpikeOnly menus]
set -euo pipefail
session=2.8a
[[ "${1:-}" == --session ]] && { session="$2"; shift 2; }
DIR="${ROOM_CAPTURE_DIR:-research/screenshots/phase-$session}"
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
source scripts/lib/room-process.sh
# The app's own defaults domain and AppleEvent address: app.room.desktop.dev for a
# Debug build (5.0a), never the user's app.room.desktop.
BUNDLE_ID="$(room_bundle_id "$APP_ABS")"
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
work="$(mktemp -d)"
log="$work/server.log"
# ROOM_TOUR_SERVERS=1 (scripts/grand-tour.sh): the tour started both servers once (the
# endpoints' log is ROOM_ENDPOINTS_LOG); use them.
server=""
pids=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  python3 research/spikes/phase-2.7/server.py 2>"$log" &
  server=$!
  pids=$server
  trap 'kill $pids 2>/dev/null || true' EXIT
fi
for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 ]] && break; sleep 0.1; done
if { [[ -n "$server" ]] && ! kill -0 $server 2>/dev/null; } || [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') != 200 ]]; then
  echo "test server did not start (port 8770 taken?): $(tail -1 "$log")" >&2
  exit 1
fi
spike=appintegration
spike_args=(-RoomSpikeCaptures28 "$captures")
if [[ $session == 2.8b ]]; then
  spike=appintegration2
  endpoints="${ROOM_ENDPOINTS_LOG:-$work/endpoints.log}"
  if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
    python3 research/spikes/phase-2.8/server.py "$endpoints" 2>>"$log" &
    pids="$pids $!"
  fi
  for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8771/appcast.xml') == 200 ]] && break; sleep 0.1; done
  : > "$endpoints"   # the readiness probe is not Room's
  swiftc -O scripts/lib/open-with-workspace.swift -o "$work/open-with-workspace" 2>>"$log"
  spike_args=(-RoomSpikeCaptures28b "$captures" -RoomFirstRun YES -RoomUpdateFeedURL http://127.0.0.1:8771/appcast.xml
              -RoomSentryDSN http://public@127.0.0.1:8771/1)
fi
now() { perl -MTime::HiRes=time -e 'printf "%.6f\n", time'; }

for appearance in "${appearances[@]}"; do
  if [[ $session == 2.8b ]]; then
    # Sparkle keeps its schedule in the app's defaults (SULastCheckTime …): each run starts from none.
    for key in SUHasLaunchedBefore SULastCheckTime SUEnableAutomaticChecks SUUpdateGroupIdentifier SUSkippedVersion; do
      defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
    done
  fi
  OUT="$work/spike-$spike-$appearance.txt"
  engine_dir="$(mktemp -d)/engine"
  open_url=""
  [[ $session == 2.8b ]] && open_url="http://127.0.0.1:8770/site.html?cold-$appearance"
  ROOM_SPIKE_OPEN_URL="$open_url" ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh "$spike" -ApplePersistenceIgnoreState YES \
    -RoomEngineDirectory "$engine_dir" -RoomSpikeAppearance "$appearance" "${spike_args[@]}" "$@" >/dev/null &
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
      while IFS= read -r line; do
        read -r name method url <<<"${line#open_url: }"
        [[ " $done_names " == *" $name "* ]] && continue
        case "$method" in
          open) sent=$(now); open -a "$APP_ABS" "$url" ;;
          applescript) sent=$(now); osascript -e "tell application id \"$BUNDLE_ID\" to open location \"$url\"" ;;
          workspace) sent=$("$work/open-with-workspace" "$APP_ABS" "$url") ;;
        esac
        echo "$sent" > "$OUT.ack-$name"
        done_names="$done_names $name"
        echo "handed $url to Room by $method" >&2
      done < <(grep -E '^open_url: ' "$OUT" || true)
    fi
    sleep 0.2
  done
  echo "== $appearance"
  cat "$OUT"
  if [[ $session == 2.8b ]]; then
    echo "== local endpoints ($appearance): every request Room made to the dev feed and crash endpoint"
    cat "$endpoints"
    : > "$endpoints"
  fi
done
