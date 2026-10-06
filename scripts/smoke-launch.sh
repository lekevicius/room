#!/usr/bin/env bash
# Launches Room.app, waits, quits it through the normal AppleEvent path and
# checks for a clean exit: status 0, no helper processes left, no crash report.
# The quit AppleEvent goes to the launched pid. On RoomCore Chrome's
# code-sign-clone-cleanup helper is allowed 5 s past the check (B-45) and
# reported as clone_cleanup_seconds.
# Usage: scripts/smoke-launch.sh [path/to/Room.app] [seconds-before-quit]
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is passed to the app.
set -euo pipefail

APP="${1:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
WAIT="${2:-5}"
# Quit goes to our process by pid, never by bundle id (B-47).
source "$(dirname "$0")/lib/room-process.sh"
room_scope "$APP"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
if pgrep -f "$ROOM_MAIN_PATTERN" >/dev/null; then
  echo "Room is already running" >&2; exit 1
fi
reports_before=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)

t_launch=$(now)
# shellcheck disable=SC2086
"$APP/Contents/MacOS/Room" ${ROOM_TOUR_ARGS:-} >/dev/null 2>&1 &
pid=$!
sleep "$WAIT"
kill -0 "$pid" 2>/dev/null || { echo "FAIL: Room exited during launch" >&2; exit 1; }
helpers=$( (pgrep -f "$ROOM_HELPER_PATTERN" || true) | wc -l | tr -d ' ')

t0=$(now)
room_quit "$pid"
while kill -0 "$pid" 2>/dev/null; do
  if perl -e "exit !($(now) - $t0 > 10)"; then
    echo "FAIL: Room did not exit within 10 s" >&2; kill -9 "$pid"; exit 1
  fi
  sleep 0.02
done
wait "$pid" && status=0 || status=$?
t1=$(now)
sleep 0.5
# Helpers left 0.5 s after the exit, not counting Chrome's code-sign clone
# cleanup helper when it exits within 5 s more (B-45, RoomCore).
read -r left clone <<<"$(room_helpers_left 5)"
reports_after=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)

printf 'helpers_running=%s exit_status=%s quit_seconds=%.2f helpers_left=%s new_crash_reports=%s clone_cleanup_seconds=%s\n' \
  "$helpers" "$status" "$(perl -e "print $t1 - $t0")" "$left" "$((reports_after - reports_before))" "$clone"
[[ $status -eq 0 && $left -eq 0 && $reports_after -eq $reports_before ]]
