#!/usr/bin/env bash
# B-84 (Phase 4.3b): the import at scale. Generates research/spikes/phase-4.3/
# generated/large with make-large.py when missing (5,000 bookmarks in 200
# folders, a Chrome History with 50,000 URLs and 100,000 visits; not
# committed), then runs the `importlarge` spike (App/Sources/Debug/
# ImportSpikes.swift) on a throwaway state with that directory as the import
# source: read, plan, replan, the sidebar's write, the history batches, the
# sidebar's reload, summed RSS before and after, the main thread's longest
# stall during each. Prints the spike's lines.
# Usage: scripts/import-large.sh [-- extra app args]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${1:-}" == -- ]] && shift
fixtures="$PWD/research/spikes/phase-4.3"
if [[ ! -f "$fixtures/generated/large/Default/History" ]]; then
  (cd "$fixtures" && python3 make-large.py)
fi
mkdir -p /tmp/room-4
state="$(mktemp -d /tmp/room-4/importlarge.XXXXXX)"
scripts/run-spike.sh importlarge -RoomStateDirectory "$state/state" -RoomEngineDirectory "$state/engine" -RoomSpikeAppearance light \
  -RoomSidebarFixture import -RoomImportSource "$fixtures/generated" -ApplePersistenceIgnoreState YES "$@"
