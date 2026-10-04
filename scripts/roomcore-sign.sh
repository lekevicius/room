#!/usr/bin/env bash
# Developer ID signing (and, unless --no-notarize, notarization) of Room.app on
# RoomCore: a thin wrapper over scripts/sign-and-notarize.sh, which already
# signs both engines inside-out (framework dylibs and tools, helpers with
# their entitlements, the framework, Sparkle and Sentry, the app) with the
# hardened runtime and notarizes through the stored profile `room`.
# What this adds: the RoomCore default app path, and an optional signed copy
# so the ad-hoc Debug product the spikes use stays as it is.
# Usage: scripts/roomcore-sign.sh [Room.app] [--no-notarize]
#   default app: build/roomcore-release/DerivedData/Build/Products/Release/Room.app
#   (scripts/roomcore-package.sh --release), else the component Debug app.
# ROOM_SIGN_COPY=<dir>: clone the app to <dir>/Room.app (APFS clone) and sign
# that instead (3.1b signs build/roomcore-signed/Room.app this way).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="" PASS=()
for arg in "$@"; do
  case "$arg" in
    --no-notarize) PASS+=(--no-notarize) ;;
    *) APP="$arg" ;;
  esac
done
if [[ -z "$APP" ]]; then
  APP="$ROOT/build/roomcore-release/DerivedData/Build/Products/Release/Room.app"
  [[ -d "$APP" ]] || APP="$ROOT/build/roomcore/DerivedData/Build/Products/Debug/Room.app"
fi
[[ -d "$APP/Contents/Frameworks/RoomCore.framework" ]] || { echo "not Room.app on RoomCore: $APP" >&2; exit 1; }
if [[ -n "${ROOM_SIGN_COPY:-}" ]]; then
  mkdir -p "$ROOM_SIGN_COPY"
  rm -rf "$ROOM_SIGN_COPY/Room.app"
  cp -Rc "$APP" "$ROOM_SIGN_COPY/Room.app"
  APP="$ROOM_SIGN_COPY/Room.app"
fi
echo "signing $APP"
exec "$ROOT/scripts/sign-and-notarize.sh" "$APP" ${PASS[@]+"${PASS[@]}"}
