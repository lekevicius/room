#!/usr/bin/env bash
# Phase 4.3a: the `import` spike (App/Sources/Debug/ImportSpikes.swift) with the
# fixtures of research/spikes/phase-4.3 listed as detected installs
# (-RoomImportSource) on the `import` fixture (the seed's shape: one space, no
# entries): every reader's counts, the preview against the store's rows after
# each import (Chrome, Safari, the Netscape file, Arc), the depth clip, the
# Essentials cap, Arc's spaces and profiles, history found through the engine
# in the same launch; 4.3b: Firefox, passwords from the CSV through the sheet,
# the extensions' store pages one at a time, the browsers on a fake home, the
# permission-denied fallback, Settings' and the first-run card's Import. No
# server and never a real browser profile. Prints the
# spike's lines. Standalone it runs on a throwaway state under /tmp; in the
# grand tour (ROOM_TOUR_SERVERS=1) on the tour's state and ROOM_TOUR_ARGS.
# Usage: scripts/import-check.sh [capture-dir] [-- extra app args]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
CAPS="${1:-}"; shift || true
[[ "${1:-}" == -- ]] && shift
if [[ -z "${ROOM_TOUR_SERVERS:-}" ]]; then
  mkdir -p /tmp/room-4
  state="$(mktemp -d /tmp/room-4/import.XXXXXX)"
  set -- -RoomStateDirectory "$state/state" -RoomEngineDirectory "$state/engine" -RoomSpikeAppearance light "$@"
fi
# 4.3b: a fake home holding the fixtures at the browsers' real relative paths
# (-RoomImportHome: Safari, Arc, Firefox and Chrome are detected there as they
# would be in ~), and a local page standing for the Chrome Web Store's detail
# pages (-RoomWebStorePage), so the store-page sequence sends no request.
mkdir -p /tmp/room-4
fake_home="$(mktemp -d /tmp/room-4/importhome.XXXXXX)"
fixtures="$PWD/research/spikes/phase-4.3"
mkdir -p "$fake_home/Library/Safari" "$fake_home/Library/Application Support/Arc" \
  "$fake_home/Library/Application Support/Firefox/Profiles/x1y2z3.default-release" "$fake_home/Library/Application Support/Google"
cp "$fixtures/safari/Bookmarks.plist" "$fixtures/safari/History.db" "$fake_home/Library/Safari/"
cp -R "$fixtures/arc/" "$fake_home/Library/Application Support/Arc/"
cp "$fixtures/firefox/places.sqlite" "$fake_home/Library/Application Support/Firefox/Profiles/x1y2z3.default-release/"
cp -R "$fixtures/chrome" "$fake_home/Library/Application Support/Google/Chrome"
args=(-RoomSidebarFixture import -RoomImportSource "$fixtures" -RoomImportHome "$fake_home"
      -RoomWebStorePage "file://$fixtures/webstore/detail.html?id={id}" -ApplePersistenceIgnoreState YES)
[[ -n "$CAPS" ]] && args+=(-RoomSpikeCaptureDirectory "$CAPS")
scripts/run-spike.sh import "${args[@]}" "$@"
