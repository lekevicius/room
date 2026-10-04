#!/usr/bin/env bash
# Xcode build phase (RoomCoreApp and RoomCoreHost targets): copies the staged RoomCore.framework
# (scripts/roomcore-package.sh --stage) into Contents/Frameworks and signs the
# app's nested code ad hoc. The framework's own dylibs and helpers were signed
# when staged; APFS clones keep the ~1 GB copy instant.
set -euo pipefail

# ROOMCORE_STAGE (xcodegen/roomcore.yml): build/roomcore, or build/roomcore-release
# for scripts/roomcore-package.sh --release.
SRC="${ROOMCORE_STAGE:-$SRCROOT/build/roomcore}/RoomCore.framework"
DEST="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/RoomCore.framework"

if [[ ! -d "$SRC" ]]; then
  echo "error: $SRC not found; run scripts/roomcore-package.sh" >&2
  exit 1
fi

stamp="$DERIVED_FILE_DIR/roomcore-framework.stamp"
want="$(stat -f %m "$SRC/Versions/Current/RoomCore")"
if [[ -f "$stamp" && "$(cat "$stamp")" == "$want" && -f "$DEST/Versions/Current/RoomCore" ]]; then
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -Rc "$SRC" "$DEST"

mkdir -p "$DERIVED_FILE_DIR"
echo "$want" > "$stamp"
