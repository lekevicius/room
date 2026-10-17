#!/usr/bin/env bash
# Prepares the Chromium checkout for a RoomCore build:
#   1. links //room (Engine/roomcore/room) into the checkout as src/room;
#   2. creates the `room` branch at the pinned tag and applies
#      Engine/roomcore/patches/series, one commit per patch;
#   3. creates the branding placeholders (theme dirs named "room" that point at
#      Chromium's own icons) and writes <out>/args.gn from args/<args file>
#      (out/dev from args/dev.gn by default; the release build is
#      ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn).
# Idempotent: a patch whose commit on `room` matches the patch file is
# skipped, so re-running never touches file mtimes (which would cost a
# rebuild); a changed patch file rebuilds the branch from that patch on.
#
# --drop <patch-name> (4.1a): drops one patch from the series and its commit
# from the `room` branch in the same pass: the series is replayed without it
# (the guard below is told that this one commit may go), the branch moves
# with `git reset --keep` (only the patch's files change, so only they
# rebuild), and then the line leaves `patches/series` and the patch file is
# removed (commit both in the repo). Refuses while a Chromium build runs.
# --dry-run: prints what would happen (with --drop: the commit, its files, the
# commits replayed) and changes nothing: no checkout, no branch move, no
# series edit, no gn gen.
#
# Env: CHROMIUM_TAG (default: the pin in Engine/roomcore/CHROMIUM_TAG, which
# scripts/roomcore-rebase.sh moves), ROOM_OUT_DIR (or OUT; default out/dev), ROOM_GN_ARGS (a
# file name in Engine/roomcore/args, default dev.gn); checkout location from
# scripts/lib/chromium-env.sh (local.env).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/lib/chromium-env.sh"
SRC="$CHROMIUM_SRC"
TAG="${CHROMIUM_TAG:-$(tr -d '[:space:]' < "$(dirname "$0")/../Engine/roomcore/CHROMIUM_TAG")}"
OUT="${ROOM_OUT_DIR:-${OUT:-out/dev}}"
ROOMCORE="$REPO/Engine/roomcore"
ARGS_FILE="$ROOMCORE/args/${ROOM_GN_ARGS:-dev.gn}"
[[ -f "$ARGS_FILE" ]] || { echo "no GN args file $ARGS_FILE" >&2; exit 1; }
DROP="" DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --drop) DROP="${2:?--drop needs a patch name}"; DROP="${DROP%.patch}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "usage: $0 [--drop <patch-name>] [--dry-run]" >&2; exit 2 ;;
  esac
done
if [[ -n "$DROP" ]]; then
  # The series is never touched while a build reads the checkout.
  if pgrep -f "autoninja|/siso |siso_|siso ninja|ninja -C" >/dev/null; then
    echo "a Chromium build is running (autoninja/siso); drop the patch after it ends" >&2; exit 1
  fi
  [[ -f "$ROOMCORE/patches/$DROP.patch" ]] || grep -qxF "$DROP.patch" "$ROOMCORE/patches/series" \
    || echo "note: $DROP.patch is neither in the series nor in patches/ (dropping the branch commit only)" >&2
fi

cd "$SRC"

# 1. //room
if [[ -L room ]]; then
  [[ "$(readlink room)" == "$ROOMCORE/room" ]] || { echo "src/room points elsewhere: $(readlink room)" >&2; exit 1; }
elif [[ -e room ]]; then
  echo "src/room exists and is not a symlink" >&2; exit 1
else
  ln -s "$ROOMCORE/room" room
fi

# Room's Rust crates (the blocker, B-30): vendored once per Cargo.lock
# (gitignored; tools/vendor_rust_crates.sh, a crates.io download when the
# crates are not in ~/.cargo already).
if ! "$ROOMCORE/tools/vendor_rust_crates.sh" --check 2>/dev/null; then
  if (( DRY_RUN )); then
    echo "would vendor room/third_party/rust (tools/vendor_rust_crates.sh)"
  else
    "$ROOMCORE/tools/vendor_rust_crates.sh"
  fi
fi

# Keep our symlinks out of Chromium's `git status`.
exclude=.git/info/exclude
for path in /room /chrome/app/theme/room /chrome/app/theme/default_100_percent/room \
            /chrome/app/theme/default_200_percent/room /components/vector_icons/room; do
  grep -qxF "$path" "$exclude" || echo "$path" >> "$exclude"
done

# 2. Branch and patches. The room branch must be the tag plus one commit per
# series patch, in order, each commit's tree equal to its parent's tree with
# the patch file applied. The check replays the series in a scratch index
# (no worktree access). From the first commit that differs (a changed patch
# file, a new patch) the rest are rebuilt there and the branch moves with
# `git reset --keep`, which rewrites only files whose content changes, so
# unchanged sources keep their mtimes and do not rebuild. Commits beyond the
# series (a temporary experiment) are kept while the series matches; a
# rebuild refuses to drop them.
if git rev-parse -q --verify refs/heads/room >/dev/null; then
  if [[ "$(git branch --show-current)" != room ]]; then
    if (( DRY_RUN )); then echo "dry run: would check out room (now on $(git branch --show-current))"
    else git checkout -q room; fi
  fi
else
  (( DRY_RUN )) && { echo "dry run: no room branch; would create it at tags/$TAG and apply the series" >&2; exit 0; }
  git checkout -q -b room "tags/$TAG"
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Chromium checkout has uncommitted changes; commit or stash them first" >&2
  exit 1
fi

scratch_index="$(mktemp -t roomcore-apply-index)"
trap 'rm -f "$scratch_index"' EXIT
GIT_INDEX_FILE="$scratch_index" git read-tree "tags/$TAG"
commits=()
while read -r commit; do commits+=("$commit"); done < <(git rev-list --reverse "tags/$TAG..refs/heads/room")
drop_subject=""
if [[ -n "$DROP" ]]; then
  drop_subject="room: $DROP"
  drop_commit=""
  for commit in ${commits[@]+"${commits[@]}"}; do
    [[ "$(git log -1 --format=%s "$commit")" == "$drop_subject" ]] && drop_commit="$commit"
  done
  [[ -n "$drop_commit" ]] || { echo "no commit \"$drop_subject\" on the room branch" >&2; exit 1; }
  echo "drop: $drop_subject (${drop_commit:0:12}); its files go back to the series without it:"
  git diff --name-only "$drop_commit^" "$drop_commit" | sed 's/^/  /'
fi
parent="$(git rev-parse "tags/$TAG^{commit}")"
series_subjects=()
applied=0 skipped=0 index=0 diverged=0
while read -r patch; do
  [[ -z "$patch" || "$patch" == \#* ]] && continue
  [[ -n "$DROP" && "$patch" == "$DROP.patch" ]] && continue
  subject="room: ${patch%.patch}"
  series_subjects+=("$subject")
  GIT_INDEX_FILE="$scratch_index" git apply --cached --whitespace=nowarn "$ROOMCORE/patches/$patch" \
    || { echo "patch does not apply: $patch" >&2; exit 1; }
  tree="$(GIT_INDEX_FILE="$scratch_index" git write-tree)"
  commit="${commits[$index]:-}"
  if (( ! diverged )) && [[ -n "$commit" ]] \
      && [[ "$(git log -1 --format=%s "$commit")" == "$subject" ]] \
      && [[ "$(git rev-parse "$commit^{tree}")" == "$tree" ]]; then
    parent="$commit"
    skipped=$((skipped + 1))
  else
    diverged=1
    parent="$(GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Room}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-room@localhost}" \
      GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Room}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-room@localhost}" \
      git commit-tree "$tree" -p "$parent" -m "$subject")"
    applied=$((applied + 1))
  fi
  index=$((index + 1))
done < "$ROOMCORE/patches/series"
# A dropped patch that was last in the series leaves the rest matching: the
# branch still moves to the last series commit.
if (( diverged )) || [[ -n "$DROP" ]]; then
  for commit in ${commits[@]+"${commits[@]}"}; do
    subject="$(git log -1 --format=%s "$commit")"
    [[ -n "$drop_subject" && "$subject" == "$drop_subject" ]] && continue
    if ! printf '%s\n' "${series_subjects[@]}" | grep -qxF "$subject"; then
      echo "the room branch has a commit outside the series ($subject, ${commit:0:12});" \
           "drop it before the series can be rebuilt" >&2
      exit 1
    fi
  done
  if (( DRY_RUN )); then
    echo "dry run: would move room from $(git rev-parse --short refs/heads/room) to ${parent:0:12}" \
         "($applied commits replayed, $skipped kept) with git reset --keep"
  else
    git reset -q --keep "$parent"
  fi
fi
echo "patches: $applied applied, $skipped already on the room branch$( (( DRY_RUN )) && echo " (dry run)")"
if [[ -n "$DROP" ]]; then
  if (( DRY_RUN )); then
    echo "dry run: would remove $DROP.patch from patches/series and delete the patch file"
  else
    grep -vxF "$DROP.patch" "$ROOMCORE/patches/series" > "$ROOMCORE/patches/series.new" || true
    mv "$ROOMCORE/patches/series.new" "$ROOMCORE/patches/series"
    rm -f "$ROOMCORE/patches/$DROP.patch"
    echo "dropped $DROP: removed from patches/series and patches/; commit the series change in the repo, then rebuild"
  fi
fi
(( DRY_RUN )) && exit 0

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
