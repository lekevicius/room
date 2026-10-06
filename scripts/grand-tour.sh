#!/usr/bin/env bash
# Phase 2.9 grand tour: every spike of Chapters 1 and 2, in sequence, on one
# Debug build of Room.app on RoomCore (the only engine since 3.9: scheme
# "Room (RoomCore)", build/roomcore/DerivedData, the framework staged by
# scripts/roomcore-package.sh) and one state directory (plus one engine
# directory), so each
# spike starts from what the ones before it left: the sidebar, history,
# favicons, settings, profiles, cookies, windows.
#
# Order: layout (Chapter 1: smoke launch, the 1.3/1.4 window captures, the
# 1.4 engine spikes, quit timing), sidebar (the 2.1 kill test, the 2.2
# captures and scroll), spaces (2.5), palette (2.4), tabs (2.3), chrome
# surfaces (2.6a, 2.6b), layout modes (2.7), app integration (2.8a, 2.8b),
# and last the net-log check (2.8b's no-request check) on the same build.
#
# The test servers start once (127.0.0.1:8765 phase-2.5, :8766/:8767
# phase-2.6, :8770 phase-2.7, :8771 phase-2.8) and stop at the end; the
# wrappers see ROOM_TOUR_SERVERS and use them. ROOM_TOUR_ARGS carries the
# state and engine directories, the appearance and -RoomFixtureReplaces YES
# (a fixture replaces the sidebar it finds) to every launch.
#
# Each appearance is one tour with its own state directory. Output goes to
# build/grand-tour/<stamp>/<appearance>/ (steps/ the raw output of every
# step, captures/ every capture, state/ and engine/ the one state); the
# summary (every check, capture and number) is summary.md there and in
# build/grand-tour/<stamp>/summary.md for both appearances.
# Needs the screen unlocked, Room frontmost-able, Screen Recording for the
# shell (window captures) and Automation for Room (activate/quit).
# Groups (`--groups layout,tabs`, Chapter 3 ran the tour section by section):
# layout, sidebar, spaces, palette, tabs, chrome, layoutmodes, appintegration,
# netlog. `--only` takes step names, `--from` a step to start at.
# Crash reports: Room's own and its helpers' in ~/Library/Logs/DiagnosticReports,
# and the engine's minidumps in <engine>/Crashpad (RoomCore's Crashpad writes
# there, never to DiagnosticReports: B-76); each step's new minidumps are named
# with their FATAL line (a DCHECK) in steps/<step>.crashpad.
# Usage: scripts/grand-tour.sh [--no-build] [--groups <group,...>] [--from <step>] [--only <step,...>] [light] [dark]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ENGINE_NAME=roomcore
SCHEME="Room (RoomCore)"
DERIVED="build/roomcore/DerivedData"
# ROOM_TOUR_APP=<Room.app> runs the steps on another Debug-configured app with --no-build
# (3.9-2: the Debug app over the release framework, for its crash count).
APP="${ROOM_TOUR_APP:-$DERIVED/Build/Products/Debug/Room.app}"
export ROOM_APP="$APP"

build=YES
from=""
only=""
groups=""
appearances=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) build=NO; shift ;;
    --from) from="$2"; shift 2 ;;
    --only) only=",$2,"; shift 2 ;;
    --groups) groups=",$2,"; shift 2 ;;
    light|dark) appearances+=("$1"); shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ ${#appearances[@]} -eq 0 ]] && appearances=(light dark)

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# Room's own crash reports and its helpers' (a renderer `chrome://crash` kills is expected in 2.6b).
crash_count() { ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room-' || true; }
helper_crash_count() { ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room Helper' || true; }
# The engine's minidumps (pending and completed) under the run's engine directory.
crashpad_dumps() { ls "$ENGINE"/Crashpad/pending/*.dmp "$ENGINE"/Crashpad/completed/*.dmp 2>/dev/null | sort || true; }
# This tour's app only: a Room run from elsewhere is not the tour's to stop.
room_pids() { pgrep -f "${APP#./}/Contents/MacOS/Room" || true; }

STAMP="$(date +%Y%m%d-%H%M%S)"
TOUR="$ROOT/build/grand-tour/$STAMP-$ENGINE_NAME"
mkdir -p "$TOUR"
tour_start=$(now)

# --- Preflight ---------------------------------------------------------------
if [[ -n "$(room_pids)" ]]; then echo "Room is already running; quit it first" >&2; exit 1; fi
if ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked | grep -q '<true/>'; then
  echo "the screen is locked: window captures and activation need it unlocked" >&2; exit 1
fi
for port in 8765 8766 8767 8770 8771; do
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then echo "port $port is taken (a stale test server?)" >&2; exit 1; fi
done

# --- Conditions (4.1a) ------------------------------------------------------
# Numbers are comparable run to run only with the load beside them: the
# 1-minute load, the Room processes that are not this tour's (the user's own
# Room, another wrapper's) and whether a Chromium build runs. Recorded, never
# refused; printed in summary.md's header.
other_rooms=$(ps -axo pid=,command= | grep -E '/Contents/MacOS/Room( |$)' | grep -v 'Room Helper' \
  | grep -vF "${APP#./}/Contents/MacOS/Room" | grep -cv grep || true)
chromium_builds=$(pgrep -f 'autoninja|/siso |siso_|siso ninja' | wc -l | tr -d ' ')
{
  printf 'load1\t%s\n' "$(sysctl -n vm.loadavg | awk '{print $2}')"
  printf 'other_room_processes\t%s\n' "$other_rooms"
  printf 'chromium_build\t%s\n' "$([[ $chromium_builds -gt 0 ]] && echo "yes ($chromium_builds autoninja/siso processes)" || echo no)"
  printf 'app\t%s\n' "$APP"
} > "$TOUR/conditions.tsv"

# --- One build ----------------------------------------------------------------
commit="$(git rev-parse --short HEAD)"
[[ -n "$(git status --porcelain -- App Packages Engine project.yml xcodegen)" ]] && commit="$commit+dirty"
if [[ $build == YES ]]; then
  echo "building Debug ($ENGINE_NAME) at $commit" >&2
  b0=$(now)
  xcodegen -q
  xcodebuild -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" build -quiet 2>&1 | grep -v "Using the first of multiple\|platform:macOS" >&2 || true
  [[ -x "$APP/Contents/MacOS/Room" ]] || { echo "build failed" >&2; exit 1; }
  printf 'build_seconds\t%.1f\n' "$(perl -e "print $(now) - $b0")" > "$TOUR/build.tsv"
fi
binary_sha=$(shasum -a 256 "$APP/Contents/MacOS/Room" | cut -c1-12)

# --- Servers, once -----------------------------------------------------------
endpoints="$TOUR/endpoints.log"
: > "$endpoints"
server_log="$TOUR/servers.log"
servers=""
python3 -m http.server 8765 --bind 127.0.0.1 -d research/spikes/phase-2.5 >>"$server_log" 2>&1 & servers="$servers $!"
python3 research/spikes/phase-2.6/server.py >>"$server_log" 2>&1 & servers="$servers $!"
python3 research/spikes/phase-2.7/server.py >>"$server_log" 2>&1 & servers="$servers $!"
python3 research/spikes/phase-2.8/server.py "$endpoints" >>"$server_log" 2>&1 & servers="$servers $!"
cleanup() {
  # shellcheck disable=SC2086
  kill $servers 2>/dev/null || true
  for pid in $(room_pids); do kill -TERM "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
ready() { [[ $(curl -sk -o /dev/null -w '%{http_code}' "$1") == 200 ]]; }
for _ in $(seq 1 100); do
  ready http://127.0.0.1:8765/cookies.html && ready 'http://127.0.0.1:8766/download?size=1' && ready https://127.0.0.1:8767/secure.html \
    && ready http://127.0.0.1:8770/site.html && ready http://127.0.0.1:8771/appcast.xml && break
  sleep 0.1
done
ready http://127.0.0.1:8771/appcast.xml && ready http://127.0.0.1:8770/site.html && ready 'http://127.0.0.1:8766/download?size=1' \
  && ready http://127.0.0.1:8765/cookies.html || { echo "a test server did not start: $(tail -3 "$server_log")" >&2; exit 1; }
: > "$endpoints"   # the readiness probes are not Room's
export ROOM_TOUR_SERVERS=1 ROOM_ENDPOINTS_LOG="$endpoints"
# An idle display sleep locks the session, and a locked session has no window captures and no
# activation (found in 2.9): keep the display awake for the tour's length.
caffeinate -dimsu -w $$ &

# --- Steps -------------------------------------------------------------------
# step <name> <group> <command...>: runs one spike (or wrapper), keeps its
# stdout and stderr, its wall time, its exit status, new crash reports and any
# Room process left behind (stopped, and counted against the step).
started=NO
[[ -z "$from" ]] && started=YES
step() {
  local name=$1 group=$2; shift 2
  [[ $started == NO && "$name" == "$from" ]] && started=YES
  [[ $started == NO ]] && return 0
  [[ -n "$only" && "$only" != *",$name,"* ]] && return 0
  [[ -n "$groups" && "$groups" != *",$group,"* ]] && return 0
  local log="$STEPS/$name.out" err="$STEPS/$name.err"
  local crashes_before helpers_before dumps_before t0 t1 status=0 left dumps dump fatal
  crashes_before=$(crash_count)
  helpers_before=$(helper_crash_count)
  dumps_before=$(crashpad_dumps)
  if ioreg -n Root -d1 -a | grep -A1 IOConsoleLocked | grep -q '<true/>'; then
    echo "the screen locked before $name; stopping (unlock and rerun with --from $name)" >&2; exit 1
  fi
  echo "[$appearance] $(date +%H:%M:%S) $group / $name" >&2
  t0=$(now)
  "$@" >"$log" 2>"$err" || status=$?
  t1=$(now)
  # A step ends with no Room left; give a quitting instance 20 s.
  for _ in $(seq 1 40); do [[ -z "$(room_pids)" ]] && break; sleep 0.5; done
  left=$(room_pids | wc -l | tr -d ' ')
  for pid in $(room_pids); do kill -TERM "$pid" 2>/dev/null || true; done
  while pgrep -f "${APP#./}/Contents/.*Room Helper" >/dev/null; do sleep 0.5; done
  # New engine minidumps: one line each, with the check that failed (a dev-build DCHECK) or none (a kill).
  dumps=0
  : > "$STEPS/$name.crashpad"
  for dump in $(comm -13 <(printf '%s\n' "$dumps_before") <(crashpad_dumps)); do
    dumps=$((dumps + 1))
    # (`|| true`: grep -m1 closes the pipe early, and pipefail would count that as a failure.)
    fatal=$(strings -n 8 "$dump" | grep -m1 -oE 'FATAL:[^]]*\] .{0,160}' || true)
    printf '%s\t%s\n' "$(basename "$dump")" "${fatal:-no FATAL line (killed, or a crash without a check)}" >> "$STEPS/$name.crashpad"
  done
  printf '%s\t%s\t%s\t%.1f\t%s\t%s\t%s\n' "$name" "$group" "$status" "$(perl -e "print $t1 - $t0")" \
    "$(( $(crash_count) - crashes_before ))" "$left" "$(( $(helper_crash_count) - helpers_before + dumps ))" >> "$RUN/steps.tsv"
}

spike() { # spike <name> [app args...]: one SpikeRunner spike, output in steps/<step>.spike
  local out="$STEPS/$current.spike"
  rm -f "$out"
  ROOM_SPIKE_OUT="$out" scripts/run-spike.sh "$@"
}
run() { current=$1; shift; step "$current" "$group" "$@"; }

for appearance in "${appearances[@]}"; do
  RUN="$TOUR/$appearance"
  STEPS="$RUN/steps"; CAPS="$RUN/captures"; STATE="$RUN/state"; ENGINE="$RUN/engine"
  mkdir -p "$STEPS" "$CAPS"
  printf 'name\tgroup\tstatus\tseconds\tcrash_reports\tleft_running\thelper_crash_reports\n' > "$RUN/steps.tsv"
  export ROOM_TOUR_ARGS="-RoomStateDirectory $STATE -RoomEngineDirectory $ENGINE -RoomSpikeAppearance $appearance -RoomFixtureReplaces YES -ApplePersistenceIgnoreState YES"
  run_start=$(now)
  # The main display's mode: window-size checks (Dia's 1244 × 818 framing) need a screen taller than 818 pt.
  cp "$TOUR/conditions.tsv" "$RUN/conditions.tsv"
  printf 'display\t%s\n' "$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/UI Looks like/ {print $2; exit}')" > "$RUN/display.tsv"

  group=layout
  run smoke scripts/smoke-launch.sh "$APP" 5
  ROOM_SNAPSHOT_PAGE_URL=http://127.0.0.1:8770/site.html run window scripts/window-snapshots.sh "$CAPS/window" "$APP"
  run cdp spike cdp -RoomSpikeCaptureDirectory "$CAPS/cdp"
  for name in scroll resize memory audio popups hidden open10 diaframe keys devtools; do
    run "$name" spike "$name"
  done
  run quittiming scripts/quit-timing.sh 3

  group=sidebar
  run killtest scripts/persistence-kill-test.sh 100 300 2101
  run sidebardemo scripts/sidebar-snapshots.sh demo "$CAPS/sidebar-demo" "$APP"
  run sidebar500 scripts/sidebar-snapshots.sh 500 "$CAPS/sidebar-500" "$APP"

  group=spaces
  run spaces spike spaces -RoomSidebarFixture spaces500
  ROOM_CAPTURE_DIR="$CAPS/spaces" run spacecaptures scripts/spaces-capture.sh
  run cookies scripts/spaces-cookies.sh

  group=palette
  run palette spike palette -RoomSidebarFixture demo -RoomSpikeCaptureDirectory "$CAPS/palette"
  run palette2 spike palette2 -RoomSidebarFixture demo -RoomSpikeCaptureDirectory "$CAPS/palette2"
  # The suggestion checks go through the logging proxy on :8771 (it refuses every tunnel): no query leaves the Mac.
  : > "$endpoints"
  run suggeston spike suggestcheck -RoomSidebarFixture demo -RoomSuggestProxy 127.0.0.1:8771
  cp "$endpoints" "$STEPS/suggeston.proxy"; : > "$endpoints"
  run suggestoff spike suggestcheck -RoomSidebarFixture demo -RoomSuggestProxy 127.0.0.1:8771 -RoomSuggestionsOff YES
  cp "$endpoints" "$STEPS/suggestoff.proxy"; : > "$endpoints"
  run palettemeasure spike palettemeasure -RoomSidebarFixture 500 -RoomHistoryRows 50000

  group=tabs
  run tabs spike tabs
  run tabsmeasure scripts/tabs-measure.sh "$STEPS/tabsmeasure"
  run tabcapture spike capture -RoomSidebarFixture demo -RoomSpikeCaptureDirectory "$CAPS/tabs"

  group=chrome
  ROOM_CAPTURE_DIR="$CAPS/chrome-2.6a" run chrome26a scripts/chrome-surfaces.sh --session 2.6a "$appearance"
  ROOM_CAPTURE_DIR="$CAPS/chrome-2.6b" run chrome26b scripts/chrome-surfaces.sh --session 2.6b "$appearance"

  group=layoutmodes
  ROOM_CAPTURE_DIR="$CAPS/layoutmodes" run layoutmodes scripts/layout-modes.sh "$appearance"

  group=appintegration
  ROOM_CAPTURE_DIR="$CAPS/app-2.8a" run app28a scripts/app-integration.sh --session 2.8a "$appearance"
  ROOM_CAPTURE_DIR="$CAPS/app-2.8b" run app28b scripts/app-integration.sh --session 2.8b "$appearance"

  group=netlog
  run netlog scripts/netlog-check.sh "$STEPS/netlog"

  printf 'run_seconds\t%.1f\n' "$(perl -e "print $(now) - $run_start")" > "$RUN/run.tsv"
  python3 scripts/lib/tour-summary.py "$RUN" --commit "$commit ($ENGINE_NAME)" --binary "$binary_sha" > "$RUN/summary.md" || true
done

printf 'tour_seconds\t%.1f\n' "$(perl -e "print $(now) - $tour_start")" > "$TOUR/tour.tsv"
python3 scripts/lib/tour-summary.py "$TOUR" --commit "$commit ($ENGINE_NAME)" --binary "$binary_sha" > "$TOUR/summary.md" || true
cat "$TOUR/summary.md"
echo "tour output: $TOUR" >&2
