#!/usr/bin/env bash
# Captures the Room window in every Phase 1.3 state (Debug build) into a
# directory, through the app's DEBUG snapshot runner. The app may not be
# allowed to activate itself, so this script activates it from outside.
# Usage: scripts/window-snapshots.sh [output-dir] [path/to/Room.app]
# ROOM_TOUR_ARGS (scripts/grand-tour.sh) is passed to the app.
set -euo pipefail

OUT="$(cd "$(dirname "${1:-research/screenshots/phase-1.3}")" && pwd)/$(basename "${1:-research/screenshots/phase-1.3}")"
APP="${2:-build/DerivedData/Build/Products/Debug/Room.app}"
BUNDLE_ID="app.room.desktop"

[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "no app at $APP" >&2; exit 1; }
rm -rf "$OUT"
# shellcheck disable=SC2086
open -n "$APP" --args -RoomSnapshotDirectory "$OUT" ${ROOM_SNAPSHOT_PAGE_URL:+-RoomSnapshotPageURL "$ROOM_SNAPSHOT_PAGE_URL"} ${ROOM_TOUR_ARGS:-}
# The last capture that needs the app frontmost (inactive states follow).
last_active="phase-1.3-dark-dia-compare.png"
[[ -n "${ROOM_SNAPSHOT_PAGE_URL:-}" ]] && last_active="phase-1.4-light-page-closed.png"
sleep 2
pid=$(pgrep -nf "$APP/Contents/MacOS/Room" || true)
# Keep handing focus to the app until the runner reaches its inactive states.
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do
  if [[ -f "$OUT/states.txt" ]]; then break; fi
  if ! ls "$OUT/$last_active" >/dev/null 2>&1; then
    osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
  fi
  sleep 1
done
while [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
cat "$OUT/states.txt"

# Comparison images against Dia's reference capture (needs ImageMagick).
DIA="research/screenshots/dia-window.jpg"
if command -v magick >/dev/null && [[ -f "$DIA" ]]; then
  tmp=$(mktemp -d)
  magick "$OUT/phase-1.3-light-dia-compare.png" -resize 50% "$tmp/l.png" 2>/dev/null
  magick "$OUT/phase-1.3-dark-dia-compare.png" -resize 50% "$tmp/d.png" 2>/dev/null
  magick "$DIA" "$tmp/l.png" +append -strip "$OUT/phase-1.3-dia-side-by-side-light.png"
  magick "$DIA" "$tmp/d.png" +append -strip "$OUT/phase-1.3-dia-side-by-side-dark.png"
  for f in "$DIA" "$tmp/l.png" "$tmp/d.png"; do magick "$f" -crop 320x70+0+0 +repage "$tmp/h-$(basename "$f").png" 2>/dev/null; done
  magick "$tmp/h-$(basename "$DIA").png" "$tmp/h-l.png.png" "$tmp/h-d.png.png" -append -filter point -resize 300% -strip "$OUT/phase-1.3-dia-header-zoom.png"
  for c in 262+0 1204+778; do
    magick "$DIA" -crop "40x40+$c" +repage "$tmp/a-$c.png" 2>/dev/null
    magick "$tmp/l.png" -crop "40x40+$c" +repage "$tmp/b-$c.png" 2>/dev/null
    magick "$tmp/a-$c.png" "$tmp/b-$c.png" +append "$tmp/c-$c.png" 2>/dev/null
  done
  magick "$tmp/c-262+0.png" "$tmp/c-1204+778.png" -append -filter point -resize 800% -strip "$OUT/phase-1.3-dia-corner-zoom.png" 2>/dev/null
  rm -rf "$tmp"
fi
