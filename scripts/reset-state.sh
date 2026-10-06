#!/usr/bin/env bash
# Moves Room's real state aside (4.1a): ~/Library/Application Support/Room
# (Room.sqlite, the snapshot, history-archive.json and the engine root
# RoomCore/ inside it) becomes Room.<timestamp> beside it, so the next launch
# starts empty. The user runs it before installing a DMG whose schema moved on
# (migrations need not be reversible in Chapters 4 and 5). Nothing is deleted:
# moving the folder back restores everything.
# Refuses while any Room process runs (the app, the release app, a Debug app,
# their helpers), whatever its path.
# Usage: scripts/reset-state.sh [--dry-run]   (--dry-run prints only)
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

SUPPORT="$HOME/Library/Application Support"
STATE="$SUPPORT/Room"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET="$SUPPORT/Room.$STAMP"

running=$(ps -axo pid=,command= | grep -E '/Contents/MacOS/Room( |$)|/Contents/MacOS/Room Helper' | grep -v grep || true)
if [[ -n "$running" ]]; then
  echo "Room is running; quit every copy first:" >&2
  echo "$running" | sed 's/^/  /' >&2
  (( DRY_RUN )) || exit 1
  echo "(dry run: a real run would refuse here)" >&2
fi

if [[ ! -e "$STATE" ]]; then
  echo "nothing to move: $STATE does not exist"
  exit 0
fi

verb="moving"; (( DRY_RUN )) && verb="would move"
echo "$verb: $STATE"
echo "        to: $TARGET"
du -sh "$STATE" 2>/dev/null | awk '{print "      size: " $1}'
for item in Room.sqlite Room-snapshot.json history-archive.json RoomCore Backups; do
  [[ -e "$STATE/$item" ]] && printf '  contains %s (%s)\n' "$item" "$(du -sh "$STATE/$item" 2>/dev/null | cut -f1)"
done
if (( DRY_RUN )); then
  echo "dry run: nothing moved"
  exit 0
fi
mv "$STATE" "$TARGET"
echo "moved $STATE to $TARGET; the next launch starts with an empty sidebar and a new engine root"
echo "to undo: quit Room, then mv \"$TARGET\" \"$STATE\""
