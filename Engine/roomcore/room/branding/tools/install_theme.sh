#!/usr/bin/env bash
# Room's theme directories in the Chromium checkout (B-103, 5.2b), run by scripts/roomcore-apply.sh.
# branding_path_component = "room" makes Chromium read chrome/app/theme/room,
# chrome/app/theme/default_{100,200}_percent/room and components/vector_icons/room. Each of the
# three theme directories becomes a real directory of file copies (APFS clones; never symlinks:
# bundle_data copies a link as a link, which would leave the helpers' icons pointing out of the
# bundle): Chromium's own file of the same path (chrome/app/theme/.../chromium), or Room's where
# theme/ has one (the logos from
# render_theme.swift) or theme/gen/ does (mac/app.icns and mac/Assets.car, compiled by actool
# from App/Resources/AppIcon.icon: the alerts helpers' icon, which macOS shows on notifications).
# components/vector_icons/room stays a link to Chromium's (no Room vector icon yet).
# Idempotent: a file already equal to its source is left alone (its mtime kept: no rebuild), and
# files no longer wanted are removed. Usage: install_theme.sh <chromium src>
set -euo pipefail
SRC="${1:?chromium src required}"
BRANDING="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$BRANDING/../../../.." && pwd)"
GEN="$BRANDING/theme/gen"

# The mac icons, compiled again only when the icon document changes.
ICON="$REPO/App/Resources/AppIcon.icon"
stamp="$(find "$ICON" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -c1-16)"
if [[ ! -f "$GEN/mac/Assets.car" || "$(cat "$GEN/stamp" 2>/dev/null)" != "$stamp" ]]; then
  rm -rf "$GEN/mac.tmp"
  mkdir -p "$GEN/mac.tmp"
  xcrun actool "$ICON" --compile "$GEN/mac.tmp" --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$GEN/mac.tmp/partial.plist" > /dev/null
  mv "$GEN/mac.tmp/AppIcon.icns" "$GEN/mac.tmp/app.icns"
  rm -f "$GEN/mac.tmp/partial.plist"
  rm -rf "$GEN/mac"
  mv "$GEN/mac.tmp" "$GEN/mac"
  echo "$stamp" > "$GEN/stamp"
  echo "branding: compiled mac/app.icns and mac/Assets.car from $ICON"
fi

place() {   # <source> <destination>: a clone of the source unless an equal regular file is there
  [[ -f "$2" && ! -L "$2" ]] && cmp -s "$1" "$2" && return
  rm -f "$2"
  cp -c "$1" "$2" 2>/dev/null || cp "$1" "$2"
  touch "$2"   # a clone keeps the source's mtime; the build must see it as new
}

overlay() {   # <checkout dir holding chromium/ and room/> <Room's directory for it>...
  local parent="$SRC/$1"; shift
  local base="$parent/chromium" dest="$parent/room"
  [[ -L "$dest" ]] && rm "$dest"     # the placeholder link of Chapters 3–5.2a
  mkdir -p "$dest"
  local wanted=()
  while IFS= read -r -d '' file; do
    local rel="${file#"$base"/}" target="$file"
    for room in "$@"; do
      [[ -f "$room/$rel" ]] && { target="$room/$rel"; break; }
    done
    wanted+=("$rel")
    mkdir -p "$dest/$(dirname "$rel")"
    place "$target" "$dest/$rel"
  done < <(find "$base" -type f -print0)
  # Room's files Chromium does not have under that name.
  for room in "$@"; do
    [[ -d "$room" ]] || continue
    while IFS= read -r -d '' file; do
      local rel="${file#"$room"/}"
      [[ -e "$base/$rel" ]] && continue
      wanted+=("$rel")
      mkdir -p "$dest/$(dirname "$rel")"
      place "$file" "$dest/$rel"
    done < <(find "$room" -type f -not -name stamp -print0)
  done
  # Files no longer wanted (and the symlinks of the first 5.2b install).
  while IFS= read -r -d '' path; do
    local rel="${path#"$dest"/}" keep=0
    for w in "${wanted[@]}"; do [[ "$w" == "$rel" ]] && { keep=1; break; }; done
    (( keep )) || rm "$path"
  done < <(find "$dest" \( -type f -o -type l \) -print0)
}

overlay chrome/app/theme "$GEN" "$BRANDING/theme/room"
overlay chrome/app/theme/default_100_percent "$BRANDING/theme/default_100_percent"
overlay chrome/app/theme/default_200_percent "$BRANDING/theme/default_200_percent"
[[ -e "$SRC/components/vector_icons/room" ]] || ln -s chromium "$SRC/components/vector_icons/room"
