#!/usr/bin/env bash
# Builds RoomCore: prepares the checkout (scripts/roomcore-apply.sh, a no-op
# when nothing changed), then `autoninja -C out/dev chrome`, which builds the
# Room.app bundle with RoomCore.framework, helpers and resources. Prints the
# wall time for research/notes/build-log.md.
# Long (clean) builds: start from bash, never zsh `&` (BG_NICE renices it):
#   bash -c 'nohup scripts/roomcore-build.sh > build/roomcore-build.log 2>&1 &'
# ROOM_OUT_DIR (default out/dev) and ROOM_GN_ARGS (default dev.gn, a file in
# Engine/roomcore/args) pick the build; the official release build is
#   bash -c 'ROOM_BUILD_JOBS=6 ROOM_OUT_DIR=out/release ROOM_GN_ARGS=release.gn \
#     nohup scripts/roomcore-build.sh > build/roomcore-release-build.log 2>&1 &'
# ROOM_BUILD_JOBS=N limits parallel local jobs (default: one per core). On a
# 24 GB machine 10 Blink compiles (1–2 GB each) swap; 6 keeps them in memory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/lib/chromium-env.sh"
SRC="$CHROMIUM_SRC"
OUT="${ROOM_OUT_DIR:-${OUT:-out/dev}}"
export ROOM_OUT_DIR="$OUT"

"$ROOT/scripts/roomcore-apply.sh"
cd "$SRC"
echo "build start $(date '+%F %T') out=$OUT args=${ROOM_GN_ARGS:-dev.gn} nice=$(ps -o nice= -p $$ | tr -d ' ') load: $(sysctl -n vm.loadavg)"
t0=$(date +%s)
autoninja -C "$OUT" chrome ${ROOM_BUILD_JOBS:+-j "$ROOM_BUILD_JOBS"}
echo "build done in $(( $(date +%s) - t0 )) s, load: $(sysctl -n vm.loadavg)"
