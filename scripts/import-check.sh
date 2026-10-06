#!/usr/bin/env bash
# Phase 4.3a: the `import` spike (App/Sources/Debug/ImportSpikes.swift) with the
# fixtures of research/spikes/phase-4.3 listed as detected installs
# (-RoomImportSource) on the `import` fixture (the seed's shape: one space, no
# entries): every reader's counts, the preview against the store's rows after
# each import (Chrome, Safari, the Netscape file, Arc), the depth clip, the
# Essentials cap, Arc's spaces and profiles, history found through the engine
# in the same launch. No server and never a real browser profile. Prints the
# spike's lines. Standalone it runs on a throwaway state under /tmp; in the
# grand tour (ROOM_TOUR_SERVERS=1) on the tour's state and ROOM_TOUR_ARGS.
# Usage: scripts/import-check.sh [capture-dir] [-- extra app args]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"; shift || true
[[ "${1:-}" == -- ]] && shift
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  mkdir -p /tmp/room-4
  state="$(mktemp -d /tmp/room-4/import.XXXXXX)"
  set -- -RoomStateDirectory "$state/state" -RoomEngineDirectory "$state/engine" -RoomSpikeAppearance light "$@"
fi
args=(-RoomSidebarFixture import -RoomImportSource "$PWD/research/spikes/phase-4.3" -ApplePersistenceIgnoreState YES)
[[ -n "$CAPS" ]] && args+=(-RoomSpikeCaptureDirectory "$CAPS")
scripts/run-spike.sh import "${args[@]}" "$@"
