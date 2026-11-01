#!/usr/bin/env bash
# 6.3 (B-105): Breakpad symbols for a release, for the crash collector's triage
# (tools/crash-collector/triage.py; minidump-stackwalk --symbols-path).
# Runs Breakpad's dump_syms (built from the Chromium checkout:
# `autoninja -C $CHROMIUM_ROOT/src/out/release dump_syms`, once) over every
# dSYM the release staged (build/roomcore-release/dSYMs/) and the app's own
# (the Release app's DerivedData), and lays them out as
# <module>/<debug id>/<module>.sym under <out>.
# Usage: scripts/crash-symbols.sh <out-dir> [dSYM dir ...]
# Then: rsync -a <out-dir>/ <collector>:/var/lib/room-crash/symbols/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/chromium-env.sh"
OUT="${1:?output directory required}"; shift
DUMP_SYMS="$CHROMIUM_ROOT/src/out/release/dump_syms"
[[ -x "$DUMP_SYMS" ]] || { echo "no $DUMP_SYMS: autoninja -C $CHROMIUM_ROOT/src/out/release dump_syms" >&2; exit 1; }
dirs=("$@")
(( ${#dirs[@]} )) || dirs=("$ROOT/build/roomcore-release/dSYMs" "$ROOT/build/roomcore-release/DerivedData/Build/Products/Release")
mkdir -p "$OUT"
count=0
while IFS= read -r -d '' dsym; do
  tmp="$(mktemp)"
  if "$DUMP_SYMS" -g "$dsym" "$(find "$dsym/Contents/Resources/DWARF" -type f | head -1)" > "$tmp" 2>/dev/null; then
    # MODULE mac arm64 <debug id> <name>
    read -r _ _ _ id name < <(head -1 "$tmp")
    mkdir -p "$OUT/$name/$id"
    mv "$tmp" "$OUT/$name/$id/$name.sym"
    count=$((count + 1))
  else
    echo "skipped: $dsym" >&2
    rm -f "$tmp"
  fi
done < <(find "${dirs[@]}" -maxdepth 1 -name "*.dSYM" -print0 2>/dev/null)
echo "symbols: $count modules under $OUT ($(du -sh "$OUT" | cut -f1))"
