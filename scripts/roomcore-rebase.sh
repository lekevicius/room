#!/usr/bin/env bash
# Moves RoomCore to a new Chromium tag (Phase 3.8).
#
# The patch files are the source of truth and the `room` branch is derived
# from them, as in scripts/roomcore-apply.sh: the series is replayed onto the
# new tag in a scratch index (the worktree is not touched until the whole
# series is through), and the branch moves only at the end.
#
#   1. fetch    git fetch origin refs/tags/<tag> (skipped when the tag is here)
#   2. predict  the patched files that changed upstream between the pinned tag
#               (Engine/roomcore/CHROMIUM_TAG) and <tag>, with line counts
#   3. replay   each patch onto <tag> in the scratch index. A patch that applies
#               as written is committed as is; one that does not is merged per
#               file, three ways, against its commit on the current `room`
#               branch (base: that commit's parent; ours: <tag> plus the earlier
#               patches). A clean merge is committed and the patch file
#               refreshed; a conflict stops the run with the patch and file
#               named, the merged file (conflict markers, diff3 style) under
#               build/roomcore-rebase/<tag>/conflict/<path>, the three inputs
#               beside it (.ours .base .theirs), exit 2
#   4. switch   refreshed patch files written (header kept), CHROMIUM_TAG set,
#               the `room` branch moved with `git reset --keep` (only files
#               whose content changes are rewritten, so the build stays
#               incremental)
#   5. sync     gclient sync -D --nohooks --revision src@<tag commit>, then
#               gclient runhooks (src is on a branch without an upstream, so
#               gclient rebases it onto the revision given: a no-op here; with
#               no revision it would rebase onto origin's default branch)
#   6. stubs    tools/gen_browser_window_stubs.py --write, and the stub diff
#   7. apply    scripts/roomcore-apply.sh (must say "0 applied, N already") and
#               gn gen
#   8. build    scripts/roomcore-build.sh with nohup in the background (pid and
#               log printed; ROOM_BUILD_JOBS, default 6)
#
# Usage:
#   scripts/roomcore-rebase.sh [--dry-run] [--no-sync] [--no-build] <tag>
#   scripts/roomcore-rebase.sh --continue [--no-sync] [--no-build]
#       after a conflict: edit the files under build/roomcore-rebase/<tag>/conflict/
#       (no markers left; a file that moved upstream goes under its new path),
#       then --continue makes them the patch (header kept) and runs again from 3
#   scripts/roomcore-rebase.sh --verify
#       after the build: roomcore-package.sh (app and host), roomcore-baseline.sh,
#       the tour's layout, sidebar, tabs and chrome sections on RoomCore, and the
#       run's record appended to research/notes/build-log.md
#
# --dry-run prints the plan and replays the series in a scratch index (no
# branch, worktree, patch file or pin changes; unreachable objects only).
# Every step prints "STEP <name> <seconds>" and goes to the run's record,
# build/roomcore-rebase/<tag>/record.md. Re-running after a finished step is
# safe: a present tag is not fetched, a matching branch is not moved, apply is
# a no-op. Env: ROOM_OUT_DIR (default out/dev), ROOM_BUILD_JOBS (default 6),
# ROOM_REBASE_TOUR_GROUPS (default layout,sidebar,tabs,chrome),
# ROOM_REBASE_TOUR_APPEARANCES (default light; "light dark" for both).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/chromium-env.sh
source "$(dirname "$0")/lib/chromium-env.sh"
SRC="$CHROMIUM_SRC"
ROOMCORE="$REPO/Engine/roomcore"
PATCHES="$ROOMCORE/patches"
PIN_FILE="$ROOMCORE/CHROMIUM_TAG"
OUT="${ROOM_OUT_DIR:-out/dev}"
JOBS="${ROOM_BUILD_JOBS:-6}"
STATE_ROOT="$REPO/build/roomcore-rebase"

mode=run dry=0 sync=1 build=1 TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --no-sync) sync=0 ;;
    --no-build) build=0 ;;
    --continue) mode="continue" ;;
    --verify) mode="verify" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) TAG="$1" ;;
  esac
  shift
done
if [[ $mode != run ]]; then
  [[ -f "$STATE_ROOT/current" ]] || { echo "no rebase in progress ($STATE_ROOT/current missing)" >&2; exit 1; }
  TAG="$(cat "$STATE_ROOT/current")"
fi
[[ -n "$TAG" ]] || { echo "usage: $0 [--dry-run] [--no-sync] [--no-build] <tag> | --continue | --verify" >&2; exit 2; }
OLD="$(tr -d '[:space:]' < "$PIN_FILE")"
STATE="$STATE_ROOT/$TAG"
RECORD="$STATE/record.md"

say() { echo "rebase: $*"; }
record() { (( dry )) || { mkdir -p "$STATE"; echo "$*" >> "$RECORD"; }; }
now() { date +%s; }
step_done() { echo "STEP $1 $(( $(now) - $2 ))"; record "- $1: $(( $(now) - $2 )) s${3:+ ($3)}"; }
series() { grep -v '^[[:space:]]*\(#\|$\)' "$PATCHES/series"; }
patch_files() { grep '^+++ b/' "$PATCHES/$1" | sed 's|^+++ b/||'; }
build_running() { pgrep -f "roomcore-build.sh|autoninja|siso(_[a-z]+)? ninja" >/dev/null 2>&1; }
header_of() { awk '/^diff --git /{exit} {print}' "$1"; }

cd "$SRC"
tag_commit() { git rev-parse -q --verify "refs/tags/$1^{commit}"; }

# The patch commits on the current branch: <old tag>..room, one per series entry.
old_commits=()
load_old_commits() {
  old_commits=()
  local base; base="$(tag_commit "$OLD")" || { echo "pinned tag $OLD is not in the checkout" >&2; exit 1; }
  while read -r c; do old_commits+=("$c"); done < <(git rev-list --reverse "$base..refs/heads/room")
  local i=0 p
  while read -r p; do
    local c="${old_commits[$i]:-}"
    [[ -n "$c" && "$(git log -1 --format=%s "$c")" == "room: ${p%.patch}" ]] \
      || { echo "refs/heads/room is not $OLD plus the series (entry $((i+1)), $p); run scripts/roomcore-apply.sh first" >&2; exit 1; }
    i=$((i + 1))
  done < <(series)
  (( ${#old_commits[@]} == i )) || { echo "refs/heads/room has commits beyond the series; drop them first" >&2; exit 1; }
}
old_commit_of() {  # <index>: the patch's commit on the old branch (-1: the old tag)
  if (( $1 < 0 )); then tag_commit "$OLD"; else echo "${old_commits[$1]}"; fi
}

commit_tree() {  # <tree> <parent> <subject>
  GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Room}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-room@localhost}" \
  GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Room}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-room@localhost}" \
    git commit-tree "$1" -p "$2" -m "$3"
}

stage_blob() {  # <index file> <path> <file on disk>: stage a file's content with the mode it had
  local idx="$1" path="$2" file="$3" mode
  mode="$(GIT_INDEX_FILE="$idx" git ls-files -s -- "$path" | awk '{print $1; exit}')"
  GIT_INDEX_FILE="$idx" git update-index --add --cacheinfo "${mode:-100644}" "$(git hash-object -w "$file")" "$path"
}

refresh_patch() {  # <patch> <parent commit> <commit>: the patch file becomes header + the commit's diff
  local p="$1" tmp
  tmp="$(mktemp)"
  header_of "$PATCHES/$p" > "$tmp"
  git -c core.abbrev=13 diff --no-color --no-renames --no-ext-diff "$2" "$3" >> "$tmp"
  mv "$tmp" "$PATCHES/$p"
}

# --- 3. Replay ------------------------------------------------------------------
# Sets: replay_head (the last commit), replay_status ("ok" or "conflict"),
# refreshed (patches whose file must be rewritten), counts.
replay() {
  local new_base; new_base="$(tag_commit "$TAG")"
  local idx; idx="$(mktemp -t roomcore-rebase-index)"
  GIT_INDEX_FILE="$idx" git read-tree "$new_base"
  local parent="$new_base" i=0 p
  refreshed=() dry_conflicts=() replay_status=ok n_exact=0 n_offset=0 n_merged=0 conflict_patch="" conflict_files=()
  local list; list="$(series)"
  for p in $list; do
    local subject="room: ${p%.patch}" how out
    if out="$(GIT_INDEX_FILE="$idx" git apply --cached -v --whitespace=nowarn "$PATCHES/$p" 2>&1)"; then
      if grep -q "offset [0-9-]* line" <<< "$out"; then how=offset; n_offset=$((n_offset + 1)); refreshed+=("$p")
      else how=exact; n_exact=$((n_exact + 1)); fi
    else
      # Three-way per file against the patch's old commit.
      local base_c theirs_c f clean=1 work files
      if (( dry )); then work="$(mktemp -d -t roomcore-rebase-merge)"; else work="$STATE/merge/$p"; fi
      base_c="$(old_commit_of $((i - 1)))"; theirs_c="$(old_commit_of "$i")"
      rm -rf "$work"; mkdir -p "$work"
      files="$(patch_files "$p")"
      bad=()
      for f in $files; do
        mkdir -p "$work/$(dirname "$f")"
        git show "$base_c:$f" > "$work/$f.base" 2>/dev/null || : > "$work/$f.base"
        git show "$theirs_c:$f" > "$work/$f.theirs"
        if ! GIT_INDEX_FILE="$idx" git show ":$f" > "$work/$f.ours" 2>/dev/null; then
          bad+=("$f (removed or moved upstream)"); clean=0; rm -f "$work/$f.ours"; continue
        fi
        if git merge-file -p --diff3 -L "$TAG + earlier patches" -L "$OLD + earlier patches" -L "$OLD + $p" \
             "$work/$f.ours" "$work/$f.base" "$work/$f.theirs" > "$work/$f"; then
          :
        else
          local hunks; hunks="$(grep -c '^<<<<<<< ' "$work/$f" || true)"
          bad+=("$f ($hunks conflicting hunk(s))"); clean=0
        fi
      done
      if (( clean )); then
        for f in $files; do stage_blob "$idx" "$f" "$work/$f"; done
        how=merged; n_merged=$((n_merged + 1)); refreshed+=("$p")
        rm -rf "$work"
      else
        if (( dry )); then
          # A dry run lists every conflict: the patch is left out and the
          # replay goes on (a later patch on the same file may then conflict
          # only because this one is missing: "after" marks it).
          dry_conflicts+=("$p: ${bad[*]}${dry_conflicts[*]:+ (after an earlier conflict)}")
          rm -rf "$work"
          how="CONFLICT, left out: ${bad[*]}"
        else
          replay_status=conflict conflict_patch="$p" conflict_files=("${bad[@]}")
          rm -rf "$STATE/conflict"; mv "$work" "$STATE/conflict"
          echo "$p" > "$STATE/conflict-patch"
          rm -f "$idx"
          return 0
        fi
      fi
    fi
    local tree; tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
    parent="$(commit_tree "$tree" "$parent" "$subject")"
    printf '  %-48s %s\n' "$p" "$how"
    [[ $how == exact ]] || record "  - $p: $how"
    i=$((i + 1))
  done
  replay_head="$parent"
  rm -f "$idx"
}

# The tree after the first <n> patches of the series, replayed onto TAG
# (used by --continue; the earlier patches apply cleanly by then).
tree_after() {
  local n="$1" idx; idx="$(mktemp -t roomcore-rebase-index)"
  GIT_INDEX_FILE="$idx" git read-tree "$(tag_commit "$TAG")"
  local k=0 p
  while read -r p && (( k < n )); do
    GIT_INDEX_FILE="$idx" git apply --cached --whitespace=nowarn "$PATCHES/$p" \
      || { echo "patch $p no longer applies onto $TAG: run $0 $TAG again" >&2; rm -f "$idx"; exit 1; }
    k=$((k + 1))
  done < <(series)
  echo "$idx"
}

predict() {
  local p f
  say "patched files changed upstream between $OLD and $TAG (lines +/-):"
  local any=0
  while read -r p; do
    while read -r f; do
      local ns; ns="$(git diff --numstat "$(tag_commit "$OLD")" "$(tag_commit "$TAG")" -- "$f")"
      if [[ -n "$ns" ]]; then
        any=1; printf '  %-46s %-80s +%s -%s\n' "$p" "$f" "$(cut -f1 <<< "$ns")" "$(cut -f2 <<< "$ns")"
        record "  - predict: $p $f +$(cut -f1 <<< "$ns") -$(cut -f2 <<< "$ns")"
      elif ! git cat-file -e "$(tag_commit "$TAG"):$f" 2>/dev/null; then
        any=1; printf '  %-46s %-80s removed or moved\n' "$p" "$f"; record "  - predict: $p $f removed or moved"
      fi
    done < <(patch_files "$p")
  done < <(series)
  (( any )) || say "  none"
  local h="chrome/browser/ui/browser_window.h"
  local hs; hs="$(git diff --shortstat "$(tag_commit "$OLD")" "$(tag_commit "$TAG")" -- "$h" "ui/base/base_window.h" | sed 's/^ *//')"
  say "BrowserWindow headers ($h, ui/base/base_window.h): ${hs:-unchanged}"
  say "upstream: $(git rev-list --count "$(tag_commit "$OLD")".."$(tag_commit "$TAG")") commits not in $OLD;$(git diff --no-renames --shortstat "$(tag_commit "$OLD")" "$(tag_commit "$TAG")")"
}

# --- --verify --------------------------------------------------------------------
if [[ $mode == verify ]]; then
  OLD_RECORDED="$(cat "$STATE/old-tag")"
  log="$(cat "$STATE/build-log-path" 2>/dev/null || true)"
  pid="$(cat "$STATE/build-pid" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "the build (pid $pid) is still running: $log" >&2; exit 1
  fi
  if [[ -n "$log" ]] && ! grep -q '^build done in' "$log"; then
    echo "the build did not finish: $log" >&2; tail -20 "$log" >&2; exit 1
  fi
  build_s="$( [[ -n "$log" ]] && sed -n 's/^build done in \([0-9]*\) s.*/\1/p' "$log" | tail -1)"
  verify_from=$(( $(wc -l < "$RECORD") + 1 ))
  record "- build: ${build_s:-?} s ($log)"
  cd "$REPO"
  t=$(now); "$REPO/scripts/roomcore-package.sh" > "$STATE/package.log" 2>&1; step_done package "$t"
  dir="$REPO/build/baseline/rebase-$TAG-$(date +%H%M%S)"
  t=$(now); "$REPO/scripts/roomcore-baseline.sh" "$dir" | tee "$STATE/baseline.log"; step_done baseline "$t" "$dir"
  record "  - nav: $(head -1 "$dir/nav-receipt.json" 2>/dev/null)"
  record "  - quits: $(grep -Eo '[0-9.]+ s' "$dir/quit.txt" | tr '\n' ' ' || true)"
  t=$(now)
  # shellcheck disable=SC2086  # appearances: words
  ROOM_TOUR_ENGINE=roomcore "$REPO/scripts/grand-tour.sh" --groups "${ROOM_REBASE_TOUR_GROUPS:-layout,sidebar,tabs,chrome}" \
    ${ROOM_REBASE_TOUR_APPEARANCES:-light} > "$STATE/tour.log" 2>&1 || true
  # shellcheck disable=SC2012  # stamped directory names, newest first
  tour="$(ls -dt "$REPO"/build/grand-tour/*-roomcore | head -1)"
  step_done tour "$t" "$tour"
  record "  - $(grep -m1 '^Totals:' "$tour/summary.md" 2>/dev/null || echo 'no tour summary')"
  machine="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
  if grep -qF "## Rebase $OLD_RECORDED → $TAG" "$REPO/research/notes/build-log.md"; then
    # The rebase itself is written up already: add the verification only.
    { echo; echo "### Rebase $OLD_RECORDED → $TAG: verify ($machine, $(date +%F))"; echo
      tail -n "+$verify_from" "$RECORD"; } >> "$REPO/research/notes/build-log.md"
  else
    { echo; echo "## Rebase $OLD_RECORDED → $TAG ($machine, $(date +%F))"; echo
      cat "$RECORD"; } >> "$REPO/research/notes/build-log.md"
  fi
  say "appended to research/notes/build-log.md"
  exit 0
fi

# --- run / --continue ------------------------------------------------------------
# A dry run reads the object store only, so it may run beside a build.
if (( ! dry )); then
  if build_running; then echo "a build is running: no rebase while it compiles" >&2; exit 1; fi
  if [[ "$(git branch --show-current)" != room ]]; then echo "the checkout is not on the room branch" >&2; exit 1; fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then echo "the checkout has uncommitted changes" >&2; exit 1; fi
fi

if [[ $mode == continue ]]; then
  p="$(cat "$STATE/conflict-patch")"
  [[ -d "$STATE/conflict" ]] || { echo "no conflict to continue ($STATE/conflict missing)" >&2; exit 1; }
  if grep -rlE '^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|) ' "$STATE/conflict" --exclude='*.ours' --exclude='*.base' --exclude='*.theirs' >/dev/null; then
    echo "conflict markers remain:" >&2
    grep -rlE '^(<<<<<<<|>>>>>>>) ' "$STATE/conflict" --exclude='*.ours' --exclude='*.base' --exclude='*.theirs' >&2
    exit 1
  fi
  OLD_RECORDED="$OLD"
  n="$(series | grep -nxF "$p" | cut -d: -f1)"
  idx="$(tree_after $((n - 1)))"
  before="$(GIT_INDEX_FILE="$idx" git write-tree)"
  while IFS= read -r -d '' file; do
    rel="${file#"$STATE/conflict/"}"
    stage_blob "$idx" "$rel" "$file"
  done < <(find "$STATE/conflict" -type f ! -name '*.ours' ! -name '*.base' ! -name '*.theirs' -print0)
  after="$(GIT_INDEX_FILE="$idx" git write-tree)"
  rm -f "$idx"
  tmp="$(mktemp)"; header_of "$PATCHES/$p" > "$tmp"
  git -c core.abbrev=13 diff --no-color --no-renames "$before" "$after" >> "$tmp"
  mv "$tmp" "$PATCHES/$p"
  record "  - $p: resolved by hand (conflict files kept in $STATE/resolved-$p)"
  rm -rf "$STATE/resolved-$p"; mv "$STATE/conflict" "$STATE/resolved-$p"; rm -f "$STATE/conflict-patch"
  say "$p rewritten from the resolved files; add a line to its header if the fix is more than context. Continuing."
fi

[[ "$TAG" != "$OLD" || $mode == continue ]] || { say "already pinned to $TAG; nothing to rebase (scripts/roomcore-apply.sh keeps the branch)"; exit 0; }

if (( dry )); then
  say "dry run: $OLD -> $TAG in $SRC (out $OUT, $JOBS jobs)"
  if tag_commit "$TAG" >/dev/null; then say "1. fetch: $TAG is here ($(tag_commit "$TAG" | cut -c1-12))"
  else say "1. fetch: would run git fetch origin refs/tags/$TAG:refs/tags/$TAG"; say "   (the rest needs the tag)"; exit 0; fi
  predict
  load_old_commits
  say "3. replay of $(series | wc -l | tr -d ' ') patches onto $TAG in a scratch index:"
  replay
  say "   $n_exact as written, $n_offset with offsets, $n_merged merged cleanly (to refresh: ${refreshed[*]:-none})"
  if (( ${#dry_conflicts[@]} )); then
    say "   ${#dry_conflicts[@]} would stop for a hand fix (the run stops at the first):"
    printf '     %s\n' "${dry_conflicts[@]}"
  fi
  say "4. would write $TAG to Engine/roomcore/CHROMIUM_TAG and move refs/heads/room (git reset --keep)"
  (( sync )) && say "5. would run gclient sync -D --nohooks --revision src@$(tag_commit "$TAG" | cut -c1-12) and gclient runhooks in $CHROMIUM_ROOT"
  say "6. would run tools/gen_browser_window_stubs.py --write and show the stub diff"
  say "7. would run scripts/roomcore-apply.sh (expect 0 applied) and gn gen $OUT"
  (( build )) && say "8. would start ROOM_BUILD_JOBS=$JOBS nohup scripts/roomcore-build.sh > build/roomcore-rebase-$TAG-build.log"
  exit 0
fi

mkdir -p "$STATE"
echo "$TAG" > "$STATE_ROOT/current"
if [[ $mode == run ]]; then
  OLD_RECORDED="$OLD"
  echo "$OLD" > "$STATE/old-tag"
  { echo "Started $(date '+%F %T'), $OLD → $TAG, checkout $SRC, out $OUT."; echo; } >> "$RECORD"
fi
OLD_RECORDED="$(cat "$STATE/old-tag")"

# 1. fetch
t=$(now)
if ! tag_commit "$TAG" >/dev/null; then
  git fetch origin "refs/tags/$TAG:refs/tags/$TAG" 2>&1 | tail -3
fi
step_done fetch "$t" "$(tag_commit "$TAG" | cut -c1-12)"

# 2. predict
t=$(now); predict; step_done predict "$t"

# 3. replay
t=$(now)
load_old_commits
say "replaying $(series | wc -l | tr -d ' ') patches onto $TAG"
replay
if [[ $replay_status == conflict ]]; then
  step_done replay "$t" "stopped at $conflict_patch"
  record "  - CONFLICT $conflict_patch: ${conflict_files[*]}"
  echo
  say "CONFLICT in patch $conflict_patch:"
  for f in "${conflict_files[@]}"; do echo "    $f"; done
  say "the merged files (markers, diff3: $TAG / $OLD / the patch) are under $STATE/conflict/;"
  say "the inputs beside each as .ours ($TAG + earlier patches), .base, .theirs."
  say "fix them (keep the hook where its call site went; a vanished call site is a new seam: tell the planner),"
  say "then: scripts/roomcore-rebase.sh --continue"
  exit 2
fi
step_done replay "$t" "$n_exact as written, $n_offset offsets, $n_merged merged"

# 4. switch
t=$(now)
for p in ${refreshed[@]+"${refreshed[@]}"}; do
  c="$(git log --format='%H %s' "$(tag_commit "$TAG")..$replay_head" | awk -v s="room: ${p%.patch}" '$2" "$3==s{print $1}')"
  refresh_patch "$p" "$c^" "$c"
  say "refreshed $p"
done
echo "$TAG" > "$PIN_FILE"
if [[ "$(git rev-parse HEAD)" != "$replay_head" ]]; then
  git reset -q --keep "$replay_head"
fi
step_done switch "$t" "room at $(git rev-parse --short HEAD); refreshed: ${refreshed[*]:-none}"

# 5. sync
if (( sync )); then
  t=$(now)
  if ! (cd "$CHROMIUM_ROOT" && gclient sync -D --nohooks --revision "src@$(tag_commit "$TAG")") > "$STATE/sync.log" 2>&1; then
    tail -20 "$STATE/sync.log" >&2; echo "gclient sync failed: $STATE/sync.log" >&2; exit 1
  fi
  tail -5 "$STATE/sync.log"
  [[ "$(git rev-parse HEAD)" == "$replay_head" ]] || { echo "gclient moved the room branch ($(git rev-parse --short HEAD))" >&2; exit 1; }
  step_done sync "$t"
  t=$(now)
  (cd "$CHROMIUM_ROOT" && gclient runhooks) > "$STATE/runhooks.log" 2>&1 || { echo "gclient runhooks failed: $STATE/runhooks.log" >&2; exit 1; }
  step_done runhooks "$t"
fi

# 6. stubs
t=$(now)
(cd "$ROOMCORE" && python3 tools/gen_browser_window_stubs.py "$SRC" tools/browser_window_real_members.txt --write room \
  | python3 -c 'import json,sys; print("stubs:", json.load(sys.stdin)["count"])')
stubdiff="$(git -C "$REPO" diff --stat -- Engine/roomcore/room/browser/room_browser_window_stubs.cc Engine/roomcore/room/browser/room_browser_window.h)"
git -C "$REPO" diff -- Engine/roomcore/room/browser/room_browser_window_stubs.cc Engine/roomcore/room/browser/room_browser_window.h > "$STATE/stubs.diff"
step_done stubs "$t" "${stubdiff:-no change}"
[[ -n "$stubdiff" ]] && { echo "$stubdiff"; say "stub diff: $STATE/stubs.diff"; }

# 7. apply + gn gen
t=$(now)
applied="$(CHROMIUM_TAG="$TAG" ROOM_OUT_DIR="$OUT" "$REPO/scripts/roomcore-apply.sh" | tee /dev/stderr | grep '^patches:')"
gn gen "$OUT" | tail -1
step_done apply "$t" "$applied"

# 8. build
if (( build )); then
  log="$REPO/build/roomcore-rebase-$TAG-build.log"
  bash -c "cd '$REPO' && ROOM_BUILD_JOBS=$JOBS ROOM_OUT_DIR=$OUT nohup scripts/roomcore-build.sh > '$log' 2>&1 & echo \$! > '$STATE/build-pid'"
  echo "$log" > "$STATE/build-log-path"
  record "- build started $(date '+%F %T'), pid $(cat "$STATE/build-pid"), $JOBS jobs, log $log"
  say "build started: pid $(cat "$STATE/build-pid"), log $log; afterwards: $0 --verify"
else
  say "done up to the build; start it with: bash -c 'ROOM_BUILD_JOBS=$JOBS nohup scripts/roomcore-build.sh > build/roomcore-rebase-$TAG-build.log 2>&1 &'"
fi
