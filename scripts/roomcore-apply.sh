#!/usr/bin/env bash
# Prepares the Chromium checkout for a RoomCore build:
#   1. links //room (Engine/roomcore/room) into the checkout as src/room;
#   2. creates the `room` branch at the pinned tag and applies
#      Engine/roomcore/patches/series, one commit per patch;
#   3. creates the branding placeholders (theme dirs named "room" that point at
#      Chromium's own icons) and writes <out>/args.gn from args/<args file>
#      (out/dev from args/dev.gn by default; the release build is
#      ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn).
# Idempotent: a patch already committed on `room` is skipped, so re-running
# never touches file mtimes (which would cost a rebuild).
#
# Env: CHROMIUM_TAG, ROOM_OUT_DIR (or OUT; default out/dev), ROOM_GN_ARGS (a
# file name in Engine/roomcore/args, default dev.gn); checkout location from
# scripts/lib/chromium-env.sh (local.env).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/lib/chromium-env.sh"
SRC="$CHROMIUM_SRC"
TAG="${CHROMIUM_TAG:-154.0.8037.58}"
OUT="${ROOM_OUT_DIR:-${OUT:-out/dev}}"
ROOMCORE="$REPO/Engine/roomcore"
ARGS_FILE="$ROOMCORE/args/${ROOM_GN_ARGS:-dev.gn}"
[[ -f "$ARGS_FILE" ]] || { echo "no GN args file $ARGS_FILE" >&2; exit 1; }

cd "$SRC"

# 1. //room
if [[ -L room ]]; then
  [[ "$(readlink room)" == "$ROOMCORE/room" ]] || { echo "src/room points elsewhere: $(readlink room)" >&2; exit 1; }
elif [[ -e room ]]; then
  echo "src/room exists and is not a symlink" >&2; exit 1
else
  ln -s "$ROOMCORE/room" room
fi

# Keep our symlinks out of Chromium's `git status`.
exclude=.git/info/exclude
for path in /room /chrome/app/theme/room /chrome/app/theme/default_100_percent/room \
            /chrome/app/theme/default_200_percent/room /components/vector_icons/room; do
  grep -qxF "$path" "$exclude" || echo "$path" >> "$exclude"
done

# 2. Branch and patches.
if git rev-parse -q --verify refs/heads/room >/dev/null; then
  [[ "$(git branch --show-current)" == room ]] || git checkout -q room
else
  git checkout -q -b room "tags/$TAG"
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Chromium checkout has uncommitted changes; commit or stash them first" >&2
  exit 1
fi

applied=0 skipped=0
while read -r patch; do
  [[ -z "$patch" || "$patch" == \#* ]] && continue
  subject="room: ${patch%.patch}"
  if git log --format=%s "tags/$TAG..HEAD" | grep -xF "$subject" >/dev/null; then
    skipped=$((skipped + 1))
    continue
  fi
  git apply --index --whitespace=nowarn "$ROOMCORE/patches/$patch"
  git -c user.name="${GIT_AUTHOR_NAME:-Room}" -c user.email="${GIT_AUTHOR_EMAIL:-room@localhost}" \
    commit -q -m "$subject"
  applied=$((applied + 1))
done < "$ROOMCORE/patches/series"
echo "patches: $applied applied, $skipped already on the room branch"

# 3. Branding placeholders: Chromium's icons under the "room" component name.
for dir in chrome/app/theme chrome/app/theme/default_100_percent \
           chrome/app/theme/default_200_percent components/vector_icons; do
  [[ -e "$dir/room" ]] || ln -s chromium "$dir/room"
done

mkdir -p "$OUT"
if ! cmp -s "$ARGS_FILE" "$OUT/args.gn"; then
  cp "$ARGS_FILE" "$OUT/args.gn"
  gn gen "$OUT"
fi
echo "ready: $SRC on branch $(git branch --show-current) ($(git rev-parse --short HEAD)), $OUT"
