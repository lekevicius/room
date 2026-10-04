#!/usr/bin/env bash
# Runs one Phase 1.4 spike in a Debug Room.app (App/Sources/Debug/SpikeRunner.swift)
# and prints its results. Keeps the app frontmost from outside, because macOS
# refuses self-activation of script-launched apps while the user works elsewhere.
# Usage: scripts/run-spike.sh <cdp|scroll|resize|memory|audio|popups|hidden|open10> [extra app args...]
# ROOM_SPIKE_OPEN_URL=<url> launches Room with that link (open -a App URL).
set -euo pipefail

SPIKE="$1"; shift
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
OUT="${ROOM_SPIKE_OUT:-$(mktemp -d)/spike-$SPIKE.txt}"
BUNDLE_ID="com.lekevicius.room"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
if pgrep -f "Room.app/Contents/MacOS/Room" >/dev/null; then echo "Room is already running" >&2; exit 1; fi
rm -f "$OUT"
if [[ -n "${ROOM_SPIKE_OPEN_URL:-}" ]]; then
  # Launched by a link (Phase 2.8b): the URL reaches the app before it finishes launching.
  open -n -a "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")" "$ROOM_SPIKE_OPEN_URL" --args -RoomSpike "$SPIKE" -RoomSpikeOutput "$OUT" "$@"
else
  open -n "$APP" --args -RoomSpike "$SPIKE" -RoomSpikeOutput "$OUT" "$@"
fi
sleep 2
# Our instance, by its arguments (an `activate` that lands just after a quit
# relaunches Room without arguments, on the real state directory).
pid=$(pgrep -nf "RoomSpikeOutput $OUT" || true)
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  # Stop activating once the spike has ended: the quit follows.
  if [[ "${ROOM_SPIKE_NO_ACTIVATE:-0}" != 1 ]] && ! grep -q '^end:' "$OUT" 2>/dev/null; then
    osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
  fi
  grep -q '^end:' "$OUT" 2>/dev/null && [[ "$*" == *KeepRunning* ]] && break
  sleep 1
done
# Stop a relaunch without arguments that an activate caused anyway.
if [[ "$*" != *KeepRunning* ]]; then
  sleep 2
  for stray in $(pgrep -f "Room.app/Contents/MacOS/Room$" || true); do
    echo "stopping stray relaunch $stray" >&2
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || kill -TERM "$stray"
  done
  while pgrep -f "Room.app/Contents/MacOS/Room" >/dev/null; do sleep 0.5; done
fi
cat "$OUT"
