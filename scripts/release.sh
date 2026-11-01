#!/usr/bin/env bash
# 6.1: one release, from the official engine to a signed appcast entry, in
# the order the log has always run it by hand. Nothing is published:
# scripts/release-publish.sh build/release <build> is the user's go.
#   1. the official engine (out/release, incremental) unless --no-engine;
#   2. the framework staged and the Release app built (roomcore-package.sh --release);
#   3. Developer ID signing and notarization of a copy (roomcore-sign.sh);
#   4. build/release made ready: the published DMGs Sparkle needs for deltas,
#      the newest fetched from https://updates.room.app when it is missing;
#   5. the DMG, its signature, the release notes (docs/releases/<version>.html)
#      and the appcast with deltas (sparkle-package.sh into build/release).
# The version and build come from xcodegen/base.yml (bump them first).
# Usage: scripts/release.sh [--no-engine]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENGINE=1
[[ "${1:-}" == "--no-engine" ]] && ENGINE=0
version=$(awk '/MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' xcodegen/base.yml)
build=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' xcodegen/base.yml)
notes="docs/releases/$version.html"
[[ -n "$version" && -n "$build" ]] || { echo "no version or build in xcodegen/base.yml" >&2; exit 1; }
[[ -f "$notes" ]] || { echo "no release notes: $notes" >&2; exit 1; }
LOG="build/release-$build"
mkdir -p "$LOG"
echo "release $version ($build); logs in $LOG"
step() { echo "== $1 ($(date '+%H:%M:%S'))"; }

if (( ENGINE )); then
  step "official engine"
  ROOM_BUILD_JOBS="${ROOM_BUILD_JOBS:-6}" ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn scripts/roomcore-build.sh > "$LOG/engine.log" 2>&1
  tail -2 "$LOG/engine.log"
fi
step "package"
scripts/roomcore-package.sh --release > "$LOG/package.log" 2>&1
tail -1 "$LOG/package.log"
step "sign and notarize"
ROOM_SIGN_COPY=build/roomcore-release-signed scripts/roomcore-sign.sh > "$LOG/sign.log" 2>&1
grep -iE "accepted|stapled|notarized" "$LOG/sign.log" | tail -3
app=build/roomcore-release-signed/Room.app
[[ "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" == "$build" ]] || { echo "$app is not build $build" >&2; exit 1; }

step "build/release"
mkdir -p build/release
# Deltas are made from the DMGs beside the new one: the one users have now must be here.
live=$(curl -s --max-time 30 https://updates.room.app/appcast.xml | grep -o 'https://updates.room.app/Room-[^"]*\.dmg' | head -1 || true)
if [[ -n "$live" && ! -f "build/release/$(basename "$live")" ]]; then
  echo "fetching the published $(basename "$live")"
  curl -s --fail --max-time 900 -o "build/release/$(basename "$live")" "$live"
fi
# The live appcast's entries stay in the new one (generate_appcast keeps the items of DMGs it finds).
curl -s --max-time 30 -o build/release/appcast.xml https://updates.room.app/appcast.xml || true

step "sparkle"
ROOM_FEED_PREFIX=https://updates.room.app/ ROOM_RELEASE_NOTES="$notes" scripts/sparkle-package.sh "$app" build/release > "$LOG/sparkle.log" 2>&1
grep -E "^dmg:|^delta:|verified|release notes" "$LOG/sparkle.log"
echo "ready: build/release (publish with scripts/release-publish.sh build/release $build, the user's go)"
