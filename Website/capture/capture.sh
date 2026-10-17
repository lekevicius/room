#!/usr/bin/env bash
# The website's screenshots, replicable: runs `-RoomSpike showcase` on the `showcase`
# fixture (App/Sources/Debug/ShowcaseSpikes.swift) in a Debug Room.app, answers each
# `capture: <scene>-<appearance>` line with a window-server capture of Room's window
# alone (no shadow, transparent corners: the site draws the shadow), then encodes
# the frames for the site.
#
#   Website/capture/capture.sh                 every scene, light and dark
#   Website/capture/capture.sh hero,palette    some scenes
#
# Raw PNGs: build/showcase/raw/ (2× the window's points). Encoded: Website/assets/shots/.
# The state directory build/showcase/state persists between runs, so favicons and
# caches are warm on the second run; ROOM_SHOWCASE_FRESH=1 starts it over.
# Needs: a Debug app over RoomCore (scripts/roomcore-package.sh --app-only), the screen
# unlocked and awake, Screen Recording for the shell, cwebp. Leave the Mac alone while
# it runs: the spike keeps Room frontmost and changes its appearance.
set -euo pipefail
cd "$(dirname "$0")/../.."

APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
BASE="build/showcase"
STATE="$BASE/state"
RAW="$BASE/raw"
SHOTS="Website/assets/shots"
OUT="$(mktemp -d)/spike-showcase.txt"
SIZE="${ROOM_SHOWCASE_SIZE:-1440x900}"

[[ "${ROOM_SHOWCASE_FRESH:-0}" == 1 ]] && rm -rf "$STATE"
mkdir -p "$STATE" "$RAW" "$SHOTS"

args=(-RoomSidebarFixture showcase -RoomFixtureReplaces YES
      -RoomStateDirectory "$PWD/$STATE" -RoomEngineDirectory "$PWD/$STATE/engine"
      -RoomShowcaseSize "$SIZE" -ApplePersistenceIgnoreState YES)
[[ $# -gt 0 ]] && args+=(-RoomShowcaseOnly "$1")

ROOM_APP="$APP" ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh showcase "${args[@]}" >/dev/null &
runner=$!
captured=()
while kill -0 "$runner" 2>/dev/null; do
  if [[ -f "$OUT" ]]; then
    wid=$(awk -F': ' '/^window_id:/ {print $2}' "$OUT" | tail -1)
    for name in $(awk -F': ' '/^capture:/ {print $2}' "$OUT"); do
      [[ " ${captured[*]-} " == *" $name "* ]] && continue
      screencapture -x -o -l "$wid" "$RAW/$name.png"
      touch "$OUT.ack-$name"
      captured+=("$name")
      echo "captured $name"
    done
  fi
  sleep 0.2
done
grep -E '^(error|showcase_missing|capture_timeout):' "$OUT" || true

# 2880 px wide frames are kept at 2400 for the site: sharp at the largest size it shows them
# (1180 pt), a third of the bytes.
for name in "${captured[@]-}"; do
  [[ -n "$name" ]] || continue
  cwebp -quiet -q 86 -alpha_q 100 -m 6 -resize 2400 0 "$RAW/$name.png" -o "$SHOTS/$name.webp"
  echo "encoded $SHOTS/$name.webp ($(du -k "$SHOTS/$name.webp" | cut -f1) KB)"
done
