#!/usr/bin/env bash
# Signs a built Room.app inside-out with Developer ID, hardened runtime and
# per-target entitlements, verifies it, and (unless --no-notarize) submits it
# to Apple's notary service and staples the ticket.
#
# Handles both engines: CEF (helpers in Contents/Frameworks) and RoomCore
# (helpers and, in the component build, ~500 dylibs inside
# RoomCore.framework/Versions/<v>; scripts/roomcore-package.sh).
#
# Notarization needs a stored credential profile, created once by the user:
#   xcrun notarytool store-credentials room --apple-id <id> --team-id N56PMJ99UT
# Usage: scripts/sign-and-notarize.sh [path/to/Room.app] [--no-notarize]
set -euo pipefail

APP="${1:-build/Release/Room.app}"
NOTARIZE=1
[[ "${2:-}" == "--no-notarize" || "${1:-}" == "--no-notarize" ]] && NOTARIZE=0
[[ "$APP" == "--no-notarize" ]] && APP="build/Release/Room.app"
IDENTITY="${ROOM_SIGN_IDENTITY:-Developer ID Application: Jonas Lekevicius (N56PMJ99UT)}"
PROFILE="${ROOM_NOTARY_PROFILE:-room}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENT_APP="$ROOT/App/Resources/Room.entitlements"
ENT_JIT="$ROOT/Helpers/Resources/Helper-JIT.entitlements"
ENT_NONE="$ROOT/Helpers/Resources/Helper.entitlements"
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

[[ -d "$APP" ]] || { echo "no app at $APP" >&2; exit 1; }
t0=$(now)

if [[ -d "$APP/Contents/Frameworks/RoomCore.framework" ]]; then
  FW="$APP/Contents/Frameworks/RoomCore.framework"
  FWV="$FW/Versions/$(readlink "$FW/Versions/Current")"
  HELPERS="$FWV/Helpers"
else
  FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
  FWV="$FW/Versions/A"
  HELPERS="$APP/Contents/Frameworks"
fi

# 1. Framework internals (dylibs: in parallel, the component build has ~500),
# then helper executables that are not app bundles.
# A static (release) RoomCore keeps only the ANGLE/SwiftShader dylibs there.
if [[ -d "$FWV/Libraries" ]]; then
  find "$FWV/Libraries" -name '*.dylib' -print0 \
    | xargs -0 -P 8 -n 16 codesign --force --options runtime --timestamp --sign "$IDENTITY"
fi
for tool in chrome_crashpad_handler app_mode_loader web_app_shortcut_copier; do
  [[ -f "$HELPERS/$tool" ]] && sign "$HELPERS/$tool"
done

# 2. Helpers: Renderer and GPU (and their Aperitif twins on RoomCore) get
# allow-jit, the rest nothing, exactly as Chrome's own signing config
# (chrome/installer/mac/signing/parts.py: helper-renderer and helper-gpu with
# allow-jit, the base, Alerts and plain Aperitif helpers with none). On M154
# the GPU process runs from the base helper unless SwiftShader is allowed;
# Chrome ships that helper without allow-jit, Phase 1.4 measured CEF's GPU
# process running without it, and 3.1b keeps it so on RoomCore
# (ROOM_BASE_HELPER_ENTITLEMENTS to experiment).
for helper in "$HELPERS"/Room\ Helper*.app; do
  case "$helper" in
    *"Renderer)"*|*"GPU)"*) ent="$ENT_JIT" ;;
    *"Room Helper.app") ent="${ROOM_BASE_HELPER_ENTITLEMENTS:-$ENT_NONE}" ;;
    *) ent="$ENT_NONE" ;;
  esac
  sign --entitlements "$ent" "$helper"
done

# 3. The framework (after its nested code).
sign "$FWV"

# 4. The other embedded frameworks, inside-out (Sparkle's XPC services,
# Autoupdate and Updater.app keep their own entitlements), then anything else
# Xcode embedded (debug dylibs in Debug builds), then the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE" ]]; then
  for xpc in "$SPARKLE"/XPCServices/*.xpc; do
    [[ -e "$xpc" ]] && sign --preserve-metadata=entitlements "$xpc"
  done
  [[ -e "$SPARKLE/Autoupdate" ]] && sign "$SPARKLE/Autoupdate"
  [[ -e "$SPARKLE/Updater.app" ]] && sign "$SPARKLE/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
fi
for framework in "$APP"/Contents/Frameworks/*.framework; do
  case "$framework" in */RoomCore.framework|*/Sparkle.framework|*"/Chromium Embedded Framework.framework") continue ;; esac
  sign "$framework"
done
find "$APP/Contents/MacOS" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do sign "$lib"; done
sign --entitlements "$ENT_APP" "$APP"
t1=$(now)
echo "signed in $(perl -e "print $t1 - $t0") s"

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
codesign -dv "$APP" 2>&1 | grep -E 'Authority=Developer ID Application|TeamIdentifier|flags'
spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true

[[ $NOTARIZE -eq 1 ]] || exit 0
ZIP="$(dirname "$APP")/Room-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "zip: $(du -h "$ZIP" | cut -f1)"
t2=$(now)
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
echo "notarized in $(perl -e "print $(now) - $t2") s"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
