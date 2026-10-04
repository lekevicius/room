#!/usr/bin/env bash
# Assembles Room.app on RoomCore from the fork's out/dev and the Swift host:
#   1. stage build/roomcore/RoomCore.framework: the framework GN built (binary,
#      helpers, resources), our public headers + module map, and, for the
#      component build, every component dylib in Versions/<v>/Libraries (the
#      helpers already search there; the framework binary gets an rpath);
#      ad-hoc signed;
#   2. xcodegen + xcodebuild the two RoomCore targets, each embedding the
#      staged framework (scripts/embed-roomcore-framework.sh): Room.app on
#      RoomCore (scheme "Room (RoomCore)", build/roomcore/DerivedData) and the
#      embryo host the engine-level scripts drive (scheme "RoomCore Host",
#      build/roomcore-host/DerivedData; both products are Room.app, as is the
#      CEF app's);
#   3. verify the signatures and print where the apps are.
# The framework's Info.plist gains RoomCoreCommit (the last commit touching
# //room, "-dirty" with local changes; a crash key), and the host is compiled
# with ROOM_SPIKES when the GN args set room_enable_spikes = true.
# Usage: scripts/roomcore-package.sh [--stage-only] [--launch] [--app-only|--host-only]
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
HOST_DERIVED="$ROOT/build/roomcore-host/DerivedData"
HOST_APP="$HOST_DERIVED/Build/Products/$CONFIGURATION/Room.app"
STAGE_ONLY=0 LAUNCH=0 BUILD_APP=1 BUILD_HOST=1
for arg in "$@"; do
  case "$arg" in
    --stage-only) STAGE_ONLY=1 ;;
    --launch) LAUNCH=1 ;;
    --app-only) BUILD_HOST=0 ;;
    --host-only) BUILD_APP=0 ;;
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
  # The helpers' rpaths already include Libraries/. The framework binary has
  # no header room for another LC_RPATH (install_name_tool refuses even an
  # in-place rewrite), so the host executable carries it
  # (xcodegen/roomcore.yml LD_RUNPATH_SEARCH_PATHS).
  # chrome_crashpad_handler only knows the out directory; it has header room.
  handler="$V/Helpers/chrome_crashpad_handler"
  if ! otool -l "$handler" | grep -q 'path @executable_path/../Libraries '; then
    install_name_tool -add_rpath @executable_path/../Libraries "$handler"
  fi
  codesign --force --sign - "$handler"
fi

# The //room commit for the crash keys (room_application.mm reads it).
commit="$(git -C "$ROOT" log -1 --format=%h -- Engine/roomcore/room)"
[[ -z "$(git -C "$ROOT" status --porcelain -- Engine/roomcore/room)" ]] || commit="$commit-dirty"
plutil -replace RoomCoreCommit -string "$commit" "$V/Resources/Info.plist"

# Ad-hoc signatures, inside-out. Linker signatures of untouched dylibs stay
# valid; the framework binary changed (rpath) and the bundle gained headers.
# GN leaves the helper bundles with only the linker's signature of their
# executable, which does not seal the bundle; codesign --verify rejects that.
for helper in "$V"/Helpers/*.app; do
  codesign --force --sign - "$helper"
done
codesign --force --sign - "$V/RoomCore"
codesign --force --sign - "$V"
t1=$(now)
dylibs=$(find "$V/Libraries" -name '*.dylib' | wc -l | tr -d ' ')
locales_kb=$(du -ck "$V"/Resources/*.lproj | tail -1 | cut -f1)
fw_kb=$(du -sk "$FW" | cut -f1)
echo "staged $FW (component=$component, $dylibs dylibs, $(du -sh "$FW" | cut -f1); $(ls -d "$V"/Resources/*.lproj | wc -l | tr -d ' ') locales $((locales_kb / 1024)) MB, without them $(((fw_kb - locales_kb) / 1024)) MB; RoomCoreCommit $commit) in $(perl -e "print $t1 - $t0") s"
[[ $STAGE_ONLY -eq 1 ]] && exit 0

# 2. The Swift apps.
cd "$ROOT"
spikes=""
grep -Eq '^[[:space:]]*room_enable_spikes[[:space:]]*=[[:space:]]*true' "$OUT_DIR/args.gn" && spikes=ROOM_SPIKES
xcodegen --quiet
build_scheme() {  # scheme, derived data, log name, extra settings...
  local scheme="$1" derived="$2" log="$STAGE/$3"; shift 3
  if ! xcodebuild -project Room.xcodeproj -scheme "$scheme" -configuration "$CONFIGURATION" \
      -derivedDataPath "$derived" "$@" build > "$log" 2>&1; then
    grep -E 'error:|BUILD FAILED' "$log" | head -40 >&2
    echo "xcodebuild ($scheme) failed; full log: $log" >&2
    exit 1
  fi
}
if [[ $BUILD_HOST -eq 1 ]]; then
  build_scheme "RoomCore Host" "$HOST_DERIVED" xcodebuild-host.log ROOM_SPIKES_CONDITION="$spikes"
  codesign --verify --deep --strict "$HOST_APP" && echo "host: $HOST_APP (spike hooks: ${spikes:-off})"
fi
t2=$(now)
if [[ $BUILD_APP -eq 1 ]]; then
  build_scheme "Room (RoomCore)" "$DERIVED" xcodebuild.log
  codesign --verify --deep --strict "$APP" && echo "signature: valid (ad hoc)"
  echo "app: $APP ($(du -sh "$APP" | cut -f1))"
fi
t3=$(now)
echo "swift builds: host $(perl -e "print $t2 - $t1") s, app $(perl -e "print $t3 - $t2") s"
echo "framework binary: $(du -h "$V/RoomCore" | cut -f1); libchrome_dll: $( [[ -f "$V/Libraries/libchrome_dll.dylib" ]] && du -h "$V/Libraries/libchrome_dll.dylib" | cut -f1 || echo n/a)"

if [[ $LAUNCH -eq 1 ]]; then
  open -n "$APP"
fi
