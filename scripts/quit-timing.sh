#!/usr/bin/env bash
# Shutdown spike: opens ten pages (one visible, nine hidden) through the DEBUG
# spike runner, waits until they loaded, then quits through the AppleEvent path
# (as ⌘Q does) and measures exit time, leftover helpers and crash reports.
# Usage: scripts/quit-timing.sh [runs]
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is passed to the app.
set -euo pipefail

# RoomCore has a native termination marker; use its exact child process and
# avoid both AppleEvent permission and another concurrently running Room app.
if [[ "${ROOM_QUIT_MODE:-appleevent}" == spike ]]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  exec python3 "$ROOT/scripts/roomcore-quit-timing.py" \
    --app "${ROOM_APP:-$ROOT/build/roomcore-host/DerivedData/Build/Products/Debug/Room.app}" \
    --runs "${1:-3}"
fi

RUNS="${1:-3}"
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
# Quit goes to our process by pid, never by bundle id (B-47).
source "$(dirname "$0")/lib/room-process.sh"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

for run in $(seq 1 "$RUNS"); do
  out=$(mktemp -d)/open10.txt
  reports_before=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)
  # shellcheck disable=SC2086
  open -n "$APP" --args -RoomSpike open10 -RoomSpikeOutput "$out" -RoomSpikeKeepRunning YES ${ROOM_TOUR_ARGS:-}
  sleep 2
  pid=$(pgrep -nf "$APP/Contents/MacOS/Room" || true)
  for _ in $(seq 1 120); do grep -q '^ready:' "$out" 2>/dev/null && break; sleep 1; done
  pages=$(grep '^pages:' "$out" | cut -d' ' -f2)
  helpers=$( (pgrep -f "Room Helper" || true) | wc -l | tr -d ' ')
  load=$(sysctl -n vm.loadavg | awk '{print $2}')
  t0=$(now)
  room_quit "$pid"
  while kill -0 "$pid" 2>/dev/null; do
    if perl -e "exit !($(now) - $t0 > 15)"; then echo "run $run: did not exit within 15 s" >&2; kill -9 "$pid"; break; fi
    sleep 0.02
  done
  t1=$(now)
  sleep 1
  # Not counting Chrome's code-sign clone cleanup helper when it exits within
  # 5 s more (B-45, RoomCore).
  read -r left clone <<<"$(room_helpers_left 5)"
  reports_after=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)
  printf 'run=%s pages=%s helpers_running=%s load1=%s quit_seconds=%.2f helpers_left=%s new_crash_reports=%s clone_cleanup_seconds=%s\n' \
    "$run" "$pages" "$helpers" "$load" "$(perl -e "print $t1 - $t0")" "$left" "$((reports_after - reports_before))" "$clone"
  sleep 3
done
