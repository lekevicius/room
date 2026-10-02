#!/usr/bin/env bash
# Runs one Phase 1.4 spike in a Debug Room.app (App/Sources/Debug/SpikeRunner.swift)
# and prints its results. Keeps the app frontmost from outside, because macOS
# refuses self-activation of script-launched apps while the user works elsewhere.
# Usage: scripts/run-spike.sh <cdp|scroll|resize|memory|audio|popups|hidden|open10> [extra app args...]
set -euo pipefail

SPIKE="$1"; shift
APP="${ROOM_APP:-build/DerivedData/Build/Products/Debug/Room.app}"
OUT="${ROOM_SPIKE_OUT:-$(mktemp -d)/spike-$SPIKE.txt}"
BUNDLE_ID="com.lekevicius.room"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
if pgrep -f "Room.app/Contents/MacOS/Room" >/dev/null; then echo "Room is already running" >&2; exit 1; fi
rm -f "$OUT"
open -n "$APP" --args -RoomSpike "$SPIKE" -RoomSpikeOutput "$OUT" "$@"
sleep 2
pid=$(pgrep -nf "$APP/Contents/MacOS/Room" || true)
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  if [[ "${ROOM_SPIKE_NO_ACTIVATE:-0}" != 1 ]]; then
    osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
  fi
  grep -q '^end:' "$OUT" 2>/dev/null && [[ "$*" == *KeepRunning* ]] && break
  sleep 1
done
cat "$OUT"
