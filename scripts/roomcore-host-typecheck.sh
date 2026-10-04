#!/usr/bin/env bash
# Typecheck Swift host changes without linking or loading Chromium.
# Public headers are copied into a stand-in framework. Supply compiled local
# package modules from a matching checkout via ROOM_HOST_MODULES.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULES="${ROOM_HOST_MODULES:-$ROOT/build/roomcore-host/DerivedData/Build/Products/Debug}"
[[ -d "$MODULES/UIKitCore.swiftmodule" ]] || {
  echo 'Set ROOM_HOST_MODULES to matching compiled Design/UIKitCore/Card/Infra modules.' >&2; exit 1;
}
STAGE="$ROOT/build/roomcore-typecheck"
mkdir -p "$STAGE/RoomCore.framework/Headers" "$STAGE/RoomCore.framework/Modules"
cp "$ROOT"/Engine/roomcore/room/core/public/*.h "$STAGE/RoomCore.framework/Headers/"
cp "$ROOT/Engine/roomcore/room/core/public/module.modulemap" "$STAGE/RoomCore.framework/Modules/"
xcrun swiftc -typecheck -swift-version 6 -default-isolation MainActor \
  -target arm64-apple-macos26.0 -module-cache-path "$STAGE/cache" \
  -F "$STAGE" -I "$MODULES" "$ROOT"/App/RoomCore/*.swift
