#!/usr/bin/env bash
# Phase 4.2: the `routing` spike (App/Sources/Debug/RoutingSpikes.swift) on the
# `routing` fixture (spaces Space, Work, Play; three rules), with 2.7's site
# served on :8770 (127.0.0.1 and localhost). External links are handed to Room
# through `application(_:open:)` inside the spike (the URL inbox's entry);
# links between spaces are clicked on the fixture page. Prints the spike's lines.
# Standalone it runs on a throwaway state under /tmp; in the grand tour
# (ROOM_TOUR_SERVERS=1) on the tour's state, servers and ROOM_TOUR_ARGS.
# Usage: scripts/routing-check.sh [capture-dir] [-- extra app args]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"; shift || true
[[ "${1:-}" == -- ]] && shift
server=""
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  if lsof -nP -iTCP:8770 -sTCP:LISTEN >/dev/null 2>&1; then echo "port 8770 is taken (a stale test server?)" >&2; exit 1; fi
  python3 research/spikes/phase-2.7/server.py 2>/dev/null &
  server=$!
  trap 'kill $server 2>/dev/null || true' EXIT
  for _ in $(seq 1 50); do [[ $(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8770/site.html') == 200 ]] && break; sleep 0.1; done
  state="$(mktemp -d /tmp/room-4/routing.XXXXXX)"
  set -- -RoomStateDirectory "$state/state" -RoomEngineDirectory "$state/engine" -RoomSpikeAppearance light "$@"
fi
args=(-RoomSidebarFixture routing -ApplePersistenceIgnoreState YES)
[[ -n "$CAPS" ]] && args+=(-RoomSpikeCaptureDirectory "$CAPS")
scripts/run-spike.sh routing "${args[@]}" "$@"
