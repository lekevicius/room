#!/usr/bin/env bash
# Fetches Chromium into $CHROMIUM_ROOT (default ~/chromium; local.env), checks out the pinned
# stable tag matching CEF, and syncs DEPS. Idempotent: skips steps already done.
# Timings are printed as "STEP <name> <seconds>" for research/notes/build-log.md.
set -euo pipefail

TAG="${CHROMIUM_TAG:-154.0.8037.58}"
source "$(dirname "$0")/lib/chromium-env.sh"
ROOT="$CHROMIUM_ROOT"

step() {
  local name="$1"; shift
  local t0; t0=$(date +%s)
  echo "== $(date '+%F %T') begin $name"
  "$@"
  echo "STEP $name $(( $(date +%s) - t0 ))"
}

if [[ ! -d "$DEPOT_TOOLS" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
fi

mkdir -p "$ROOT"
cd "$ROOT"

if [[ ! -d src/.git ]]; then
  # Full history: rebases of the `room` branch onto new tags need the merge base.
  step fetch fetch --nohooks chromium
fi

cd src
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  step fetch-tag git fetch origin "refs/tags/$TAG:refs/tags/$TAG"
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "refs/tags/$TAG^{commit}")" ]]; then
  step checkout git -c advice.detachedHead=false checkout "tags/$TAG"
fi

step sync gclient sync -D --nohooks
step runhooks gclient runhooks

echo "== $(date '+%F %T') done; checkout size:"
du -sh "$ROOT"
