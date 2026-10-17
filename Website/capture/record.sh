#!/usr/bin/env bash
# A clip for the website, replicable: stages the clip's first state in Room (the showcase
# spike with -RoomShowcaseStage), plays Website/capture/scenes/<clip>.json with room-record
# (real pointer and key events, the window recorded alone without the system cursor, the
# pointer's path logged), quits Room, then encodes the clip (clip.sh).
#
#   Website/capture/record.sh palette            light
#   Website/capture/record.sh palette dark
#   ROOM_RECORD_MANUAL=1 Website/capture/record.sh palette    you do the moves; Return stops
#
# Needs what capture.sh needs, plus Accessibility for the terminal (posting events).
# Hands off the mouse and keyboard while it plays.
set -euo pipefail
cd "$(dirname "$0")/../.."
CLIP="$1"; APPEARANCE="${2:-light}"
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
STATE="build/showcase/state"
RAW="build/showcase/clips"
OUT="$(mktemp -d)/spike-showcase.txt"
SCENE="Website/capture/scenes/$CLIP.json"
[[ -f "$SCENE" || "${ROOM_RECORD_MANUAL:-0}" == 1 ]] || { echo "no scene $SCENE" >&2; exit 1; }
mkdir -p "$STATE" "$RAW"

swift build -c release --package-path Website/capture/RoomRecorder >/dev/null
RECORDER="Website/capture/RoomRecorder/.build/release/room-record"

source scripts/lib/room-process.sh
room_scope "$APP"
ROOM_APP="$APP" ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh showcase \
  -RoomSidebarFixture showcase -RoomFixtureReplaces YES \
  -RoomStateDirectory "$PWD/$STATE" -RoomEngineDirectory "$PWD/$STATE/engine" \
  -RoomShowcaseSize "${ROOM_SHOWCASE_SIZE:-1440x900}" -RoomShowcaseStage "$CLIP" -RoomShowcaseAppearances "$APPEARANCE" \
  -RoomSpikeKeepRunning YES -ApplePersistenceIgnoreState YES >/dev/null
grep -q "^ready: $CLIP" "$OUT" || { cat "$OUT"; echo "Room did not get ready" >&2; exit 1; }
pid=$(pgrep -nf "RoomSpikeOutput $OUT")
room_activate "$pid"
sleep 0.5

name="$CLIP-$APPEARANCE"
if [[ "${ROOM_RECORD_MANUAL:-0}" == 1 ]]; then
  "$RECORDER" --pid "$pid" --out "$RAW/$name" --duration "${ROOM_RECORD_SECONDS:-20}"
else
  "$RECORDER" --pid "$pid" --out "$RAW/$name" --script "$SCENE"
fi
room_quit "$pid" || kill -TERM "$pid"
Website/capture/clip.sh "$name"
