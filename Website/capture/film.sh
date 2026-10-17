#!/usr/bin/env bash
# A clip for the website without Screen Recording: the showcase spike plays the clip's
# choreography with Room's animations slowed (-RoomShowcaseSlowdown, default 5) and composes
# frames in process meanwhile (the same composition as the stills), each stamped with its time
# in the clip. This script turns the stamped frames into a steady 30 fps MP4 for the site.
#
#   Website/capture/film.sh spaces            light
#   Website/capture/film.sh spaces dark
#
# Leave the Mac alone while it runs. Output: Website/assets/clips/<clip>-<appearance>.mp4,
# a poster, and clips.json (the site swaps the still for the clip). No pointer track: the
# clips are keyboard-led, and the site draws no cursor without one.
set -euo pipefail
cd "$(dirname "$0")/../.."
CLIP="$1"; APPEARANCE="${2:-light}"
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
STATE="build/showcase/state"
FRAMES="build/showcase/film"
OUT="$(mktemp -d)/spike-showcase.txt"
mkdir -p "$STATE" "$FRAMES"

ROOM_APP="$APP" ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh showcase \
  -RoomSidebarFixture showcase -RoomFixtureReplaces YES \
  -RoomStateDirectory "$PWD/$STATE" -RoomEngineDirectory "$PWD/$STATE/engine" \
  -RoomShowcaseSize "${ROOM_SHOWCASE_SIZE:-1440x900}" -RoomShowcaseBackdrop "$PWD/Website/assets/art/pigment-1536.avif" \
  -RoomShowcaseRecord "$CLIP" -RoomShowcaseAppearances "$APPEARANCE" -RoomShowcaseDirectory "$PWD/$FRAMES" \
  -RoomShowcaseSlowdown "${ROOM_SHOWCASE_SLOWDOWN:-5}" -ApplePersistenceIgnoreState YES >/dev/null
grep -E '^(recorded|error|capture_failed):' "$OUT" || true
DIR="$FRAMES/$CLIP"
[[ -f "$DIR/times.txt" ]] || { echo "no frames" >&2; exit 1; }

# Each frame lasts until the next one's stamp; ffmpeg's concat demuxer takes the durations.
python3 - "$DIR" <<'PY'
import os, sys
d = sys.argv[1]
times = [float(t) for t in open(os.path.join(d, "times.txt")).read().split()]
with open(os.path.join(d, "list.txt"), "w") as f:
    for i, t in enumerate(times):
        nxt = times[i + 1] if i + 1 < len(times) else t + 1 / 30
        f.write(f"file '{i:05d}.jpg'\nduration {max(nxt - t, 0.001):.4f}\n")
    f.write(f"file '{len(times) - 1:05d}.jpg'\n")
print(f"{len(times)} frames over {times[-1]:.2f} s, {len(times) / max(times[-1], 0.01):.1f} fps captured")
PY
NAME="$CLIP-$APPEARANCE"
mkdir -p Website/assets/clips
ffmpeg -loglevel error -y -f concat -safe 0 -i "$DIR/list.txt" \
  -vf "fps=30,scale=1920:-2:flags=lanczos,format=yuv420p" -c:v libx264 -profile:v high -preset slow -crf 20 \
  -movflags +faststart "Website/assets/clips/$NAME.mp4"
cwebp -quiet -q 86 "$DIR/00000.jpg" -o "Website/assets/clips/$NAME.webp"
python3 - <<'PY'
import json, os
out = "Website/assets/clips"
json.dump(sorted(f[:-4] for f in os.listdir(out) if f.endswith(".mp4")), open(os.path.join(out, "clips.json"), "w"))
PY
echo "Website/assets/clips/$NAME.mp4 ($(du -k "Website/assets/clips/$NAME.mp4" | cut -f1) KB)"
