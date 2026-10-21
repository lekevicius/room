#!/usr/bin/env bash
# 5.8a: the `passwordpopover` spike (App/Sources/Debug/PasswordPopoverSpikes.swift):
# the host's password popover fired through the page's UI delegate with the
# members RoomCore will call (Return saves and the confirmation toast, Esc
# Not Now, Never for This Site, the update offer, Manage Passwords as a
# tab, the sidebar hidden, a withdrawn offer, the engine's own confirmation)
# on the 3.7a sign-in fixture, on a fresh throwaway state and engine
# directory under /tmp/room-5/passwordpopover/, search suggestions off.
# Prints the spike's lines.
# Usage: scripts/password-popover-check.sh <out-file> [capture-dir] [extra app args, e.g. -RoomSpikeAppearance dark]
# ROOM_APP picks the app (default the dev build's Debug app; the release
# framework's: build/roomcore-release/DerivedData/Build/Products/Debug/Room.app).
# Needs scripts/test-servers.sh running (:8776).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
CAPS="${1:-}"; [[ $# -gt 0 ]] && shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
lsof -nP -iTCP:8776 -sTCP:LISTEN >/dev/null 2>&1 || { echo "no test server on :8776 (scripts/test-servers.sh)" >&2; exit 1; }
WORK="/tmp/room-5/passwordpopover/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
args=(-RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES)
# An absolute capture directory: the app's working directory is / (3.6a's finding).
[[ -n "$CAPS" ]] && { mkdir -p "$CAPS"; CAPS="$(cd "$CAPS" && pwd)"; args+=(-RoomSpikeCaptureDirectory "$CAPS"); }
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg) state=$WORK"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh passwordpopover "${args[@]}" "$@" >/dev/null || true
cat "$OUT"
dumps=$(ls "$WORK"/engine/Crashpad/pending/*.dmp "$WORK"/engine/Crashpad/completed/*.dmp 2>/dev/null || true)
echo "crashpad_dumps: $(printf '%s' "$dumps" | grep -c . || true)"
