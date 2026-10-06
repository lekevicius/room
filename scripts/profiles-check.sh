#!/usr/bin/env bash
# Phase 4.4b: the `profiles` spike (App/Sources/Debug/ProfileSpikes.swift),
# two launches on one state. `-RoomSpikeOnly set` makes a second profile
# (Work) with a space (Office) and the 2.5 fixture's cookie in it, reorders
# the spaces as Settings ▸ Spaces does, renames Work through Settings' path
# (its engine directory is keyed by the profile's id: nothing moves) and opens
# a space's routing rules. Between the launches this script puts Work's
# directory back under its pre-4.4b name (`Room Profile <name>`) and Chromium's
# Local State with it, as a state from before 4.4b would be. `verify` then
# checks the one-time move at launch, the cookie, Clear browsing data for the
# last hour (this hour's visit and the cookie go, a visit 3 h old stays), a
# permission stored through Settings' path and read by permissions.html, a
# profile deleted (its directory gone, its tabs in the Archive) and the
# palette's Settings ▸ Privacy, and opens Chromium's site-data page.
# Standalone it runs on a throwaway state under /tmp with the test servers;
# in the grand tour (ROOM_TOUR_SERVERS=1) on the tour's state and servers.
# Usage: scripts/profiles-check.sh [capture-dir]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"
mkdir -p /tmp/room-4
server=""
args=()
engine=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  if ! lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
    scripts/test-servers.sh "$(mktemp /tmp/room-4/profiles-endpoints.XXXXXX)" >/dev/null 2>&1 &
    server=$!
    trap '[[ -n "$server" ]] && { pkill -P "$server" 2>/dev/null; kill "$server" 2>/dev/null; } || true' EXIT
    for _ in $(seq 1 100); do
      [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8765/cookies.html') == 200 &&
         $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8766/permissions.html') == 200 ]] && break
      sleep 0.1
    done
  fi
  state="$(mktemp -d /tmp/room-4/profiles.XXXXXX)"
  engine="$state/engine"
  args=(-RoomStateDirectory "$state/state" -RoomEngineDirectory "$engine" -RoomSpikeAppearance light)
  echo "state: $state"
fi
# The tour's own directories come last in ROOM_TOUR_ARGS and win (run-spike.sh).
if [[ -n "${ROOM_TOUR_ARGS:-}" ]]; then
  read -r -a tour <<<"$ROOM_TOUR_ARGS"
  for ((i = 0; i < ${#tour[@]} - 1; i++)); do
    [[ "${tour[$i]}" == -RoomEngineDirectory ]] && engine="${tour[$((i + 1))]}"
    [[ "${tour[$i]}" == -RoomStateDirectory && -z "$engine" ]] && engine="${tour[$((i + 1))]}/engine"
  done
fi
[[ -n "$CAPS" ]] && args+=(-RoomSpikeCaptureDirectory "$CAPS")
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg)"
out="$(mktemp /tmp/room-4/profiles-set.XXXXXX)"
ROOM_SPIKE_OUT="$out" scripts/run-spike.sh profiles -RoomSpikeOnly set -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"}
# A state from before 4.4b: Work's directory under its name, Local State naming it so.
id="$(sed -n 's/^work_profile: id=\([0-9A-F-]*\) .*/\1/p' "$out" | head -1)"
if [[ -n "$id" && -n "$engine" && -d "$engine/Room Profile $id" ]]; then
  mv "$engine/Room Profile $id" "$engine/Room Profile Office Profile"
  python3 - "$engine/Local State" "Room Profile $id" "Room Profile Office Profile" <<'PY'
import json, sys
path, new, old = sys.argv[1:4]
state = json.load(open(path))
profile = state.get("profile", {})
if profile.get("last_used") == new: profile["last_used"] = old
profile["last_active_profiles"] = [old if p == new else p for p in profile.get("last_active_profiles", [])]
cache = profile.get("info_cache", {})
if new in cache: cache[old] = cache.pop(new)
json.dump(state, open(path, "w"))
print(f"legacy layout: Work's directory as \"{old}\", Local State last_used={profile.get('last_used')}")
PY
else
  echo "legacy layout: not made (id=${id:-none} engine=${engine:-none})"
fi
scripts/run-spike.sh profiles -RoomSpikeOnly verify -ApplePersistenceIgnoreState YES ${args[@]+"${args[@]}"}
