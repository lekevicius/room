#!/usr/bin/env bash
# Signs a built Room.app inside-out with Developer ID, hardened runtime and
# per-target entitlements, verifies it, and (unless --no-notarize) submits it
# to Apple's notary service and staples the ticket.
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
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

[[ -d "$APP" ]] || { echo "no app at $APP" >&2; exit 1; }
t0=$(now)

# 1. Framework internals, then the framework.
find "$FW/Versions/A/Libraries" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do sign "$lib"; done
sign "$FW/Versions/A"

# 2. Helpers: Renderer and GPU get allow-jit, the rest nothing (as Chrome).
# On M154 the GPU process runs from the base helper; measured in Phase 1.4,
# it runs without allow-jit (ROOM_BASE_HELPER_ENTITLEMENTS to experiment).
for helper in "$APP"/Contents/Frameworks/Room\ Helper*.app; do
  case "$helper" in
    *"(Renderer)"*|*"(GPU)"*) ent="$ENT_JIT" ;;
    *"Room Helper.app") ent="${ROOM_BASE_HELPER_ENTITLEMENTS:-$ENT_NONE}" ;;
    *) ent="$ENT_NONE" ;;
  esac
  sign --entitlements "$ent" "$helper"
done

# 3. Anything else Xcode embedded (debug dylibs in Debug builds), then the app.
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
