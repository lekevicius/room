#!/usr/bin/env bash
# Phase 4.4a: the `settings` spike (App/Sources/Debug/SettingsSpikes.swift),
# two launches on one state: `-RoomSpikeOnly set` remaps Pin (⌘D → ⌥⌘P) by a
# key press in Settings ▸ Shortcuts and checks the menu, the palette's hint,
# the sidebar's menu and the keys page (1.4's fixture: the old ⌘D reaches the
# page, ⌥⌘P pins), a conflict and its confirmation, refusals, Reopen Closed
# Tab remapped (⇧⌘T → ⌥⌘T) and still reserved, every General / Search /
# Downloads / Appearance setting set through the store, and the save panel per
# download (the 2.6 server on :8766); `verify` relaunches and reads every
# setting and key back, then Reset All and the settings put back. Prints both
# launches' lines. Standalone it runs on a throwaway state under /tmp with the
# test servers; in the grand tour (ROOM_TOUR_SERVERS=1) on the tour's state.
# Usage: scripts/settings-check.sh [capture-dir]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
mkdir -p /tmp/room-4
server=""
args=()
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  if ! lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
    scripts/test-servers.sh "$(mktemp /tmp/room-4/settings-endpoints.XXXXXX)" >/dev/null 2>&1 &
    server=$!
    trap '[[ -n "$server" ]] && kill "$server" 2>/dev/null || true' EXIT
    for _ in $(seq 1 100); do
      [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/download?size=1') == 200 ]] && break
      sleep 0.1
    done
  fi
  state="$(mktemp -d /tmp/room-4/settings.XXXXXX)"
  args=(-RoomStateDirectory "$state/state" -RoomEngineDirectory "$state/engine" -RoomSpikeAppearance light)
  echo "state: $state"
fi
[[ -n "$CAPS" ]] && args+=(-RoomSpikeCaptureDirectory "$CAPS")
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
scripts/run-spike.sh settings -RoomSpikeOnly set -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"}
scripts/run-spike.sh settings -RoomSpikeOnly verify -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"}
