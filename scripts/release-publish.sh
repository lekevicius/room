#!/usr/bin/env bash
# Publishes one signed, notarized DMG to the room-updates R2 bucket behind
# https://updates.room.app: the versioned DMG, the same bytes as Room.dmg (the
# website's Download button), and appcast.xml (Sparkle's feed). An outward
# action: run it only for a DMG the user chose to release.
# Usage: scripts/release-publish.sh <release-dir> <build>
#   <release-dir> holds every published DMG and the appcast that
#   scripts/sparkle-package.sh wrote over all of them (build/release).
# CLOUDFLARE_ACCOUNT_ID: the account with R2 (default Jonas@mainline.inc's).
# ROOM_PUBLISH_DRY_RUN=1 prints the uploads instead of running them.
set -euo pipefail

DIR="$1"; BUILD="$2"
BUCKET="${ROOM_R2_BUCKET:-room-updates}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-79c846994671f62ac0fab9c05cc73249}"
DMG=$(ls "$DIR"/Room-*-"$BUILD".dmg 2>/dev/null | head -1)
[[ -f "$DMG" ]] || { echo "no Room-*-$BUILD.dmg in $DIR" >&2; exit 1; }
[[ -f "$DIR/appcast.xml" ]] || { echo "no appcast.xml in $DIR" >&2; exit 1; }
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$DIR/appcast.xml" || { echo "appcast.xml has no entry for build $BUILD" >&2; exit 1; }

# The DMG must be notarized and its app must say the real feed.
mnt=$(mktemp -d); hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mnt" "$DMG"
check=$(spctl -a -t exec -vv "$mnt/Room.app" 2>&1 || true)
feed=$(plutil -extract SUFeedURL raw "$mnt/Room.app/Contents/Info.plist" 2>/dev/null || true)
hdiutil detach -quiet "$mnt"
grep -q "Notarized Developer ID" <<<"$check" || { echo "$DMG: app not notarized: $check" >&2; exit 1; }
[[ "$feed" == https://updates.room.app/appcast.xml ]] || { echo "$DMG: feed is '$feed'" >&2; exit 1; }

put() { # <file> <key> <content-type> <cache-control>
  if [[ "${ROOM_PUBLISH_DRY_RUN:-0}" == 1 ]]; then echo "would put $1 -> r2://$BUCKET/$2 ($3; $4)"; return; fi
  wrangler r2 object put "$BUCKET/$2" --remote --file "$1" --content-type "$3" --cache-control "$4"
}
name=$(basename "$DMG")
put "$DMG" "$name" application/x-apple-diskimage "public, max-age=31536000, immutable"
put "$DMG" Room.dmg application/x-apple-diskimage "public, max-age=300"
put "$DIR/appcast.xml" appcast.xml "application/xml; charset=utf-8" "public, max-age=60"
echo "published build $BUILD: https://updates.room.app/$name, https://updates.room.app/Room.dmg, https://updates.room.app/appcast.xml"
