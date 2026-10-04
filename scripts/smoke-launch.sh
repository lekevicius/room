#!/usr/bin/env bash
# Launches Room.app, waits, quits it through the normal AppleEvent path and
# checks for a clean exit: status 0, no helper processes left, no crash report.
# Usage: scripts/smoke-launch.sh [path/to/Room.app] [seconds-before-quit]
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is passed to the app.
set -euo pipefail

APP="${1:-build/DerivedData/Build/Products/Debug/Room.app}"
WAIT="${2:-5}"
BUNDLE_ID="com.lekevicius.room"
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
if pgrep -f "Room.app/Contents/MacOS/Room" >/dev/null; then
  echo "Room is already running" >&2; exit 1
fi
reports_before=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)

t_launch=$(now)
# shellcheck disable=SC2086
"$APP/Contents/MacOS/Room" ${ROOM_TOUR_ARGS:-} >/dev/null 2>&1 &
pid=$!
sleep "$WAIT"
kill -0 "$pid" 2>/dev/null || { echo "FAIL: Room exited during launch" >&2; exit 1; }
helpers=$( (pgrep -f "Room Helper" || true) | wc -l | tr -d ' ')

t0=$(now)
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null
while kill -0 "$pid" 2>/dev/null; do
  if perl -e "exit !($(now) - $t0 > 10)"; then
    echo "FAIL: Room did not exit within 10 s" >&2; kill -9 "$pid"; exit 1
  fi
  sleep 0.02
done
wait "$pid" && status=0 || status=$?
t1=$(now)
sleep 0.5
left=$( (pgrep -f "Room Helper" || true) | wc -l | tr -d ' ')
reports_after=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^Room' || true)

printf 'helpers_running=%s exit_status=%s quit_seconds=%.2f helpers_left=%s new_crash_reports=%s\n' \
  "$helpers" "$status" "$(perl -e "print $t1 - $t0")" "$left" "$((reports_after - reports_before))"
[[ $status -eq 0 && $left -eq 0 && $reports_after -eq $reports_before ]]
