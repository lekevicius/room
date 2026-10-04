#!/usr/bin/env bash
# Packages one signed Room.app as a Sparkle update, locally (PLAN §7 risk 12:
# the update size is the number). Nothing is uploaded.
#   1. a DMG of the app (hdiutil, HFS+, UDZO compressed);
#   2. the EdDSA signature of the DMG (Sparkle's sign_update; the private key
#      comes from this Mac's login keychain, account ed25519, docs/setup.md §5);
#   3. an appcast entry (generate_appcast over the output directory, which
#      signs the entry from the same key) and sign_update --verify of the DMG
#      against the signature in the appcast.
# Usage: scripts/sparkle-package.sh <Room.app> <output-directory>
# ROOM_FEED_PREFIX: the download URL prefix written into the entry (default a
# .invalid placeholder; the feed URL is B-6's/the user's).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?Room.app required}"
OUT="${2:?output directory required}"
BIN="$ROOT/Packages/Integration/.build/artifacts/sparkle/Sparkle/bin"
PREFIX="${ROOM_FEED_PREFIX:-https://updates.room.invalid/}"
[[ -x "$BIN/sign_update" ]] || { echo "no Sparkle tools in $BIN (resolve Packages/Integration first)" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
version=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
build=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")
mkdir -p "$OUT"
DMG="$OUT/Room-$version-$build.dmg"
rm -f "$DMG"
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
t0=$(now)
hdiutil create -quiet -volname Room -fs HFS+ -format UDZO -srcfolder "$APP" "$DMG"
t1=$(now)
echo "app: $(du -sh "$APP" | cut -f1) ($(du -sk "$APP" | cut -f1) KB)"
echo "dmg: $DMG $(stat -f %z "$DMG") bytes ($(du -h "$DMG" | cut -f1)) in $(perl -e "print $t1 - $t0") s"
echo "== sign_update"
"$BIN/sign_update" "$DMG" | tee "$OUT/signature.txt"
echo "== generate_appcast"
"$BIN/generate_appcast" --download-url-prefix "$PREFIX" "$OUT"
echo "== appcast.xml"
cat "$OUT/appcast.xml"
sig=$(grep -o 'sparkle:edSignature="[^"]*"' "$OUT/appcast.xml" | head -1 | cut -d'"' -f2)
echo "== sign_update --verify (appcast's signature)"
"$BIN/sign_update" --verify "$DMG" "$sig" && echo "verified"
