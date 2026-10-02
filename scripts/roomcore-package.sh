#!/usr/bin/env bash
# Assembles Room.app on RoomCore from the fork's out/dev and the Swift host:
#   1. stage build/roomcore/RoomCore.framework: the framework GN built (binary,
#      helpers, resources), our public headers + module map, and, for the
#      component build, every component dylib in Versions/<v>/Libraries (the
#      helpers already search there; the framework binary gets an rpath);
#      ad-hoc signed;
#   2. xcodegen + xcodebuild the RoomCoreHost target (its own DerivedData,
#      because the CEF target also produces a Room.app), which embeds the
#      staged framework (scripts/embed-roomcore-framework.sh);
#   3. verify the signature and print where the app is.
# Usage: scripts/roomcore-package.sh [--stage-only] [--launch]
# Env: OUT (out/dev), CONFIGURATION (Debug); checkout location from
# scripts/lib/chromium-env.sh (local.env).
# Developer ID signing of the result: scripts/sign-and-notarize.sh <app>.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/lib/chromium-env.sh"
SRC="$CHROMIUM_SRC"
OUT_DIR="$SRC/${OUT:-out/dev}"
CONFIGURATION="${CONFIGURATION:-Debug}"
STAGE="$ROOT/build/roomcore"
FW="$STAGE/RoomCore.framework"
DERIVED="$STAGE/DerivedData"
APP="$DERIVED/Build/Products/$CONFIGURATION/Room.app"
STAGE_ONLY=0 LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    --stage-only) STAGE_ONLY=1 ;;
    --launch) LAUNCH=1 ;;
    *) echo "unknown argument $arg" >&2; exit 2 ;;
  esac
done
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
t0=$(now)

GN_FW="$OUT_DIR/Room.app/Contents/Frameworks/RoomCore.framework"
[[ -d "$GN_FW" ]] || { echo "no $GN_FW; build with scripts/roomcore-build.sh" >&2; exit 1; }
VERSION="$(readlink "$GN_FW/Versions/Current")"

# 1. Stage the framework (APFS clones: no copy cost).
rm -rf "$FW"
mkdir -p "$STAGE"
cp -Rc "$GN_FW" "$FW"
V="$FW/Versions/$VERSION"
mkdir -p "$V/Headers" "$V/Modules"
cp "$ROOT"/Engine/roomcore/room/core/public/*.h "$V/Headers/"
cp "$ROOT/Engine/roomcore/room/core/public/module.modulemap" "$V/Modules/"
ln -sfn Versions/Current/Headers "$FW/Headers"
ln -sfn Versions/Current/Modules "$FW/Modules"

component=0
if otool -L "$V/RoomCore" | grep -q '@rpath/libchrome_dll.dylib'; then
  component=1
  # The component build loads ~500 dylibs from the out directory; bring them
  # into the bundle so it runs (and signs) anywhere.
  find "$OUT_DIR" -maxdepth 1 -name '*.dylib' -exec cp -c {} "$V/Libraries/" \;
  install_name_tool -add_rpath @loader_path/Libraries "$V/RoomCore" 2>/dev/null
fi

# Ad-hoc signatures, inside-out. Linker signatures of untouched dylibs stay
# valid; the framework binary changed (rpath) and the bundle gained headers.
codesign --force --sign - "$V/RoomCore"
codesign --force --sign - "$V"
t1=$(now)
dylibs=$(find "$V/Libraries" -name '*.dylib' | wc -l | tr -d ' ')
echo "staged $FW (component=$component, $dylibs dylibs, $(du -sh "$FW" | cut -f1)) in $(perl -e "print $t1 - $t0") s"
[[ $STAGE_ONLY -eq 1 ]] && exit 0

# 2. The Swift host.
cd "$ROOT"
xcodegen --quiet
log="$STAGE/xcodebuild.log"
if ! xcodebuild -project Room.xcodeproj -scheme "Room (RoomCore)" -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED" build > "$log" 2>&1; then
  grep -E 'error:|BUILD FAILED' "$log" | head -40 >&2
  echo "xcodebuild failed; full log: $log" >&2
  exit 1
fi
t2=$(now)

# 3. Verify.
codesign --verify --deep --strict "$APP" && echo "signature: valid (ad hoc)"
echo "app: $APP ($(du -sh "$APP" | cut -f1), host built in $(perl -e "print $t2 - $t1") s)"
echo "framework binary: $(du -h "$V/RoomCore" | cut -f1); libchrome_dll: $( [[ -f "$V/Libraries/libchrome_dll.dylib" ]] && du -h "$V/Libraries/libchrome_dll.dylib" | cut -f1 || echo n/a)"

if [[ $LAUNCH -eq 1 ]]; then
  open -n "$APP"
fi
