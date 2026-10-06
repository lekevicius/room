#!/usr/bin/env bash
# Runs one Phase 1.4 spike in a Debug Room.app (App/Sources/Debug/SpikeRunner.swift)
# and prints its results. Keeps the app frontmost from outside, because macOS
# refuses self-activation of script-launched apps while the user works elsewhere.
# Usage: scripts/run-spike.sh <cdp|scroll|resize|memory|audio|popups|hidden|open10> [extra app args...]
# ROOM_SPIKE_OPEN_URL=<url> launches Room with that link (open -a App URL).
# ROOM_SPIKE_ENV="NAME=value ..." passes environment variables to the app
# (`open --env`; 3.4b's translate check sets a placeholder GOOGLE_API_KEY).
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is appended to the app's arguments;
# the last occurrence of a `-Key value` pair wins, so the tour's state and
# engine directories and appearance override a wrapper's own.
set -euo pipefail

SPIKE="$1"; shift
# shellcheck disable=SC2206
tour_args=(${ROOM_TOUR_ARGS:-})
set -- "$@" ${tour_args[@]+"${tour_args[@]}"}
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
OUT="${ROOM_SPIKE_OUT:-$(mktemp -d)/spike-$SPIKE.txt}"
# Activate and quit go to our process by pid, never by bundle id (B-47).
source "$(dirname "$0")/lib/room-process.sh"
room_scope "$APP"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
if pgrep -f "$ROOM_MAIN_PATTERN" >/dev/null; then echo "Room is already running" >&2; exit 1; fi
rm -f "$OUT"
if [[ -n "${ROOM_SPIKE_OPEN_URL:-}" ]]; then
  # Launched by a link (Phase 2.8b): the URL reaches the app before it finishes launching.
  open -n -a "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")" "$ROOM_SPIKE_OPEN_URL" --args -RoomSpike "$SPIKE" -RoomSpikeOutput "$OUT" "$@"
else
  env_args=()
  for pair in ${ROOM_SPIKE_ENV:-}; do env_args+=(--env "$pair"); done
  open -n ${env_args[@]+"${env_args[@]}"} "$APP" --args -RoomSpike "$SPIKE" -RoomSpikeOutput "$OUT" "$@"
fi
sleep 2
# Our instance, by its arguments (an `activate` that lands just after a quit
# relaunches Room without arguments, on the real state directory).
pid=$(pgrep -nf "RoomSpikeOutput $OUT" || true)
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  # Stop activating once the spike has ended: the quit follows.
  if [[ "${ROOM_SPIKE_NO_ACTIVATE:-0}" != 1 ]] && ! grep -q '^end:' "$OUT" 2>/dev/null; then
    room_activate "$pid"
  fi
  grep -q '^end:' "$OUT" 2>/dev/null && [[ "$*" == *KeepRunning* ]] && break
  sleep 1
done
# A relaunch without arguments (what an activate by bundle id used to cause,
# B-47) should not happen any more; stop one if it does, by its pid.
if [[ "$*" != *KeepRunning* ]]; then
  sleep 2
  for stray in $(pgrep -f "$ROOM_MAIN_PATTERN$" || true); do
    echo "stopping stray relaunch $stray" >&2
    room_quit "$stray" || kill -TERM "$stray"
  done
  while pgrep -f "$ROOM_MAIN_PATTERN" >/dev/null; do sleep 0.5; done
fi
cat "$OUT"
