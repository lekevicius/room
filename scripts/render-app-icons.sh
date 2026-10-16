#!/usr/bin/env bash
# Renders every Settings ▸ Appearance ▸ App Icon choice (Model's AppIconChoice)
# from its Icon Composer document to the PNGs the app bundles:
#
#   App/Resources/AppIcons/Rendered/<raw>.png       the Default rendition
#   App/Resources/AppIcons/Rendered/<raw>-dark.png  the Dark rendition
#
# 1024 x 1024 (512 pt @2x), 8 bits per channel, Display P3 kept. `room` is
# rendered from App/Resources/AppIcon.icon (the bundle's own icon, which actool
# compiles); the alternates from App/Resources/AppIcons/<Name>.icon, sources
# only (never compiled or copied into the bundle). Run it after changing a
# document and commit the PNGs.
#
# Needs Icon Composer (/Applications) for ictool and ImageMagick (`magick`,
# Homebrew) to bring ictool's 16-bit output down to 8 bits (~3 MB → ~1 MB).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICTOOL="${ICTOOL:-/Applications/Icon Composer.app/Contents/Executables/ictool}"
OUT="$ROOT/App/Resources/AppIcons/Rendered"

[[ -x "$ICTOOL" ]] || { echo "error: ictool not found at $ICTOOL (install Icon Composer)" >&2; exit 1; }
command -v magick >/dev/null || { echo "error: ImageMagick's magick not found (brew install imagemagick)" >&2; exit 1; }

# raw value (AppIconChoice) → document
CHOICES=(
  "room:App/Resources/AppIcon.icon"
  "sunrise:App/Resources/AppIcons/Sunrise.icon"
  "lagoon:App/Resources/AppIcons/Lagoon.icon"
  "ember:App/Resources/AppIcons/Ember.icon"
  "dusk:App/Resources/AppIcons/Dusk.icon"
  "harbor:App/Resources/AppIcons/Harbor.icon"
  "newsprint:App/Resources/AppIcons/Newsprint.icon"
  "watercolor:App/Resources/AppIcons/Watercolor.icon"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

for choice in "${CHOICES[@]}"; do
  raw="${choice%%:*}"
  doc="$ROOT/${choice#*:}"
  [[ -d "$doc" ]] || { echo "error: $doc missing" >&2; exit 1; }
  for rendition in Default Dark; do
    suffix=""
    [[ "$rendition" == Dark ]] && suffix="-dark"
    raw16="$TMP/$raw$suffix.png"
    "$ICTOOL" "$doc" --export-image --output-file "$raw16" \
      --platform macOS --rendition "$rendition" --width 512 --height 512 --scale 2 >/dev/null
    magick "$raw16" -depth 8 -define png:compression-level=9 -define png:compression-filter=5 "$OUT/$raw$suffix.png"
    printf '%-24s %s\n' "$raw$suffix.png" "$(du -h "$OUT/$raw$suffix.png" | cut -f1)"
  done
done
