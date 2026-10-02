#!/usr/bin/env bash
# Builds RoomCore: prepares the checkout (scripts/roomcore-apply.sh, a no-op
# when nothing changed), then `autoninja -C out/dev chrome`, which builds the
# Room.app bundle with RoomCore.framework, helpers and resources. Prints the
# wall time for research/notes/build-log.md.
# Long (clean) builds: start from bash, never zsh `&` (BG_NICE renices it):
#   bash -c 'nohup scripts/roomcore-build.sh > ~/chromium/build-room.log 2>&1 &'
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${CHROMIUM_SRC:-$HOME/chromium/src}"
OUT="${OUT:-out/dev}"
export PATH="${DEPOT_TOOLS:-$HOME/depot_tools}:$PATH"

"$ROOT/scripts/roomcore-apply.sh"
cd "$SRC"
echo "build start $(date '+%F %T') nice=$(ps -o nice= -p $$ | tr -d ' ') load: $(sysctl -n vm.loadavg)"
t0=$(date +%s)
autoninja -C "$OUT" chrome
echo "build done in $(( $(date +%s) - t0 )) s, load: $(sysctl -n vm.loadavg)"
