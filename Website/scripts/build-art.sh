#!/usr/bin/env bash
# Derives the site's art from the local originals in research/art/ (gitignored):
# the risograph prints become AVIF + WebP at two widths, the Icon Composer
# documents become rendered PNG/WebP icons (light and dark). The derivatives are
# committed; the originals are not. Re-run after adding or changing art.
#
# Needs: magick (ImageMagick 7), avifenc, cwebp, Icon Composer.app (ictool).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/research/art"
OUT="$ROOT/Website/assets"
ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ICTOOL" ] || ICTOOL="$(xcrun --find ictool)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Print name in research/art/risograph → slug on the site.
prints=(
  "Grainy Abstract Pigment Field:pigment"
  "Grainy Monochrome Halftone Abstraction:newsprint"
  "Retro Halftone Color Fields:fields"
  "Retro Risograph Abstract Color Fields:quilt"
  "Retro Risograph Amoeba Composition:amoeba"
  "Retro Risograph Color Flow:flow"
  "Retro Risograph Waves in Teal and Magenta:waves"
  "Vintage Risograph Color Blobs:blobs"
)

mkdir -p "$OUT/art" "$OUT/icons"
for entry in "${prints[@]}"; do
  name="${entry%%:*}"; slug="${entry##*:}"
  src="$SRC/risograph/$name.png"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  for w in 1536 800; do
    magick "$src" -resize "${w}x>" -strip "$TMP/$slug-$w.png"
    # Grain is the point of these prints: q 50 keeps the halftone dots (checked
    # against the original at 1:1); every browser Room's visitors use reads AVIF.
    avifenc -q 50 -s 4 -j all "$TMP/$slug-$w.png" "$OUT/art/$slug-$w.avif" >/dev/null
  done
  echo "art  $slug"
done

# Icon Composer document → slug (matches the app's AppIconChoice raw values).
icons=(
  "Room:room"
  "Room-Alt1:sunrise"
  "Room-Alt2:lagoon"
  "Room-Alt3:ember"
  "Room-Alt4:dusk"
  "Room-Alt5:harbor"
  "Room-Alt6:newsprint"
  "Room-v0:watercolor"
)
for entry in "${icons[@]}"; do
  name="${entry%%:*}"; slug="${entry##*:}"
  doc="$SRC/$name.icon"
  for rendition in Default Dark; do
    suffix=""; [ "$rendition" = Dark ] && suffix="-dark"
    "$ICTOOL" "$doc" --export-image --output-file "$TMP/$slug$suffix.png" \
      --platform macOS --rendition "$rendition" --width 512 --height 512 --scale 1 >/dev/null
    cwebp -quiet -q 88 -alpha_q 100 -m 6 "$TMP/$slug$suffix.png" -o "$OUT/icons/$slug$suffix.webp"
  done
  # The bare glyph art (no squircle), used by the site where the mark is a window onto the print.
  magick "$doc/Assets/"*.png -trim +repage -resize 768x768 -strip "$TMP/$slug-glyph.png"
  cwebp -quiet -q 86 -alpha_q 100 -m 6 "$TMP/$slug-glyph.png" -o "$OUT/icons/$slug-glyph.webp"
  echo "icon $slug"
done

# Social card and favicon from the default icon.
"$ICTOOL" "$SRC/Room.icon" --export-image --output-file "$TMP/fav.png" \
  --platform macOS --rendition Default --width 256 --height 256 --scale 1 >/dev/null
magick "$TMP/fav.png" -resize 180x180 "$OUT/icons/apple-touch-icon.png"
magick "$TMP/fav.png" -resize 64x64 "$OUT/icons/favicon-64.png"
echo "done"
