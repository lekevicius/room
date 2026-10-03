#!/usr/bin/env bash
# Phase 2.5 cookie check: serves research/spikes/phase-2.5 on 127.0.0.1:8765
# and runs `-RoomSpike cookies` on the `spaces` fixture with a throwaway
# engine root, so no cookie lands in the real profiles.
set -euo pipefail
ROOT="$(mktemp -d)/Engine"
python3 -m http.server 8765 --bind 127.0.0.1 -d research/spikes/phase-2.5 >/dev/null 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
sleep 1
scripts/run-spike.sh cookies -RoomSidebarFixture spaces -RoomEngineDirectory "$ROOT" "$@"
