#!/usr/bin/env bash
# Packages one signed Room.app as a Sparkle update, locally (PLAN §7 risk 12:
# the update size is the number). Nothing is uploaded.
#   1. a DMG of the app (hdiutil, HFS+, UDZO compressed);
#   2. the EdDSA signature of the DMG (Sparkle's sign_update; the private key
#      is ROOM_SPARKLE_ED_KEY from the environment or local.env when set, else
#      this Mac's login keychain, account ed25519; docs/setup.md §5);
#   3. an appcast entry (generate_appcast over the output directory, which
#      signs the entry from the same key) and sign_update --verify of the DMG
#      against the signature in the appcast.
# Usage: scripts/sparkle-package.sh <Room.app> <output-directory>
# ROOM_FEED_PREFIX: the download URL prefix written into the entry (default a
# .invalid placeholder; the feed URL is B-6's/the user's).
# ROOM_SPARKLE_UNSIGNED=1: stop after the DMG and write the appcast entry
# without sparkle:edSignature (signing reads the private key from the login
# keychain, which prompts until the user approves it; 3.1b-2).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?Room.app required}"
OUT="${2:?output directory required}"
BIN="$ROOT/Packages/Integration/.build/artifacts/sparkle/Sparkle/bin"
PREFIX="${ROOM_FEED_PREFIX:-https://updates.room.app/}"
[[ -x "$BIN/sign_update" ]] || { echo "no Sparkle tools in $BIN (resolve Packages/Integration first)" >&2; exit 1; }
# The key from local.env (gitignored) unless the environment has one; passed on
# stdin (--ed-key-file -), never as an argument.
if [[ -z "${ROOM_SPARKLE_ED_KEY:-}" && -f "$ROOT/local.env" ]]; then
  ROOM_SPARKLE_ED_KEY="$(source "$ROOT/local.env" >/dev/null 2>&1; printf '%s' "${ROOM_SPARKLE_ED_KEY:-}")"
fi
sparkle() {
  local tool="$1"; shift
  if [[ -n "${ROOM_SPARKLE_ED_KEY:-}" ]]; then
    printf '%s' "$ROOM_SPARKLE_ED_KEY" | "$BIN/$tool" --ed-key-file - "$@"
  else
    "$BIN/$tool" "$@"
  fi
}
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
if [[ "${ROOM_SPARKLE_UNSIGNED:-0}" == 1 ]]; then
  cat > "$OUT/appcast-unsigned.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Room</title>
    <item>
      <title>$version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist" 2>/dev/null || echo 26.0)</sparkle:minimumSystemVersion>
      <enclosure url="$PREFIX$(basename "$DMG")" length="$(stat -f %z "$DMG")" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
  echo "== appcast entry, unsigned (no sparkle:edSignature)"
  cat "$OUT/appcast-unsigned.xml"
  exit 0
fi
if [[ -n "${ROOM_SPARKLE_ED_KEY:-}" ]]; then keysrc="ROOM_SPARKLE_ED_KEY"; else keysrc="login keychain"; fi
echo "== sign_update (key: $keysrc)"
sparkle sign_update "$DMG" | tee "$OUT/signature.txt"
echo "== generate_appcast"
sparkle generate_appcast --download-url-prefix "$PREFIX" "$OUT"
echo "== appcast.xml"
cat "$OUT/appcast.xml"
sig=$(grep -o 'sparkle:edSignature="[^"]*"' "$OUT/appcast.xml" | head -1 | cut -d'"' -f2)
echo "== sign_update --verify (appcast's signature)"
sparkle sign_update --verify "$DMG" "$sig" && echo "verified"
