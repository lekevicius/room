#!/usr/bin/env bash
# Encodes a recorded clip for the website: build/showcase/clips/<name>.mov + .cursor.json →
# Website/assets/clips/<name>.mp4 (H.264, 1920 px wide, faststart: plays everywhere),
# <name>.webp (the poster: the first frame), <name>.cursor.json (the pointer track),
# and lists it in Website/assets/clips/clips.json, which the site reads to swap a still
# for its clip.
#   Website/capture/clip.sh palette-light [trim-start-seconds]
set -euo pipefail
cd "$(dirname "$0")/../.."
NAME="$1"; TRIM="${2:-0}"
RAW="build/showcase/clips"
OUT="Website/assets/clips"
mkdir -p "$OUT"
ffmpeg -loglevel error -y -ss "$TRIM" -i "$RAW/$NAME.mov" -an \
  -vf "scale=1920:-2:flags=lanczos,format=yuv420p" -c:v libx264 -profile:v high -preset slow -crf 20 \
  -movflags +faststart "$OUT/$NAME.mp4"
POSTER="$(mktemp -d)/poster.png"
ffmpeg -loglevel error -y -i "$OUT/$NAME.mp4" -frames:v 1 "$POSTER"
cwebp -quiet -q 86 "$POSTER" -o "$OUT/$NAME.webp"
python3 - "$RAW/$NAME.cursor.json" "$OUT/$NAME.cursor.json" "$TRIM" <<'PY'
import json, sys
src, dst, trim = sys.argv[1], sys.argv[2], float(sys.argv[3])
data = json.load(open(src))
events = [[round(t - trim, 3), x, y, k] for t, x, y, k in data["events"] if t >= trim]
# Moves closer than 1/60 s to the previous kept move add bytes, not smoothness.
kept, last = [], -1
for e in events:
    if e[3] == "m" and kept and e[0] - last < 1 / 60:
        continue
    kept.append(e); last = e[0]
json.dump({"width": data["width"], "height": data["height"], "events": kept}, open(dst, "w"), separators=(",", ":"))
PY
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
names = sorted(f[:-4] for f in os.listdir(out) if f.endswith(".mp4"))
json.dump(names, open(os.path.join(out, "clips.json"), "w"))
PY
echo "$OUT/$NAME.mp4 ($(du -k "$OUT/$NAME.mp4" | cut -f1) KB), poster, cursor track"
