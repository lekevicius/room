#!/usr/bin/env bash
# Phase 3.4b: a throwaway handler for the `roomtest:` scheme, so the external
# protocol path can launch a real application on this Mac without opening
# anything the user has. `install` builds an AppleScript applet in
# build/roomtest-handler/ (Launch Services ignores applets under $TMPDIR) that appends each URL it is asked to open to
# $ROOM_EXTERNAL_LOG and quits, and registers it with Launch Services;
# `remove` unregisters and deletes it.
# Usage: ROOM_EXTERNAL_LOG=<file> scripts/external-protocol-fixture.sh install | remove
set -euo pipefail
DIR="${ROOM_EXTERNAL_DIR:-$(cd "$(dirname "$0")/.." && pwd)/build/roomtest-handler}"
APP="$DIR/RoomTestHandler.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
case "${1:?install or remove}" in
  install)
    : "${ROOM_EXTERNAL_LOG:?ROOM_EXTERNAL_LOG required}"
    rm -rf "$DIR"; mkdir -p "$DIR"
    cat > "$DIR/handler.applescript" <<SCRIPT
on open location theURL
  do shell script "echo " & quoted form of theURL & " >> " & quoted form of "$ROOM_EXTERNAL_LOG"
  quit
end open location
on run
  quit
end run
SCRIPT
    osacompile -o "$APP" "$DIR/handler.applescript"
    plist="$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.room.test.roomtest-handler" "$plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string app.room.test.roomtest-handler" "$plist"
    /usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" \
      -c "Add :CFBundleURLTypes:0 dict" \
      -c "Add :CFBundleURLTypes:0:CFBundleURLName string RoomTest" \
      -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" \
      -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string roomtest" "$plist"
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -f "$APP"
    echo "roomtest: handler $APP (log $ROOM_EXTERNAL_LOG)"
    ;;
  remove)
    [[ -d "$APP" ]] && "$LSREGISTER" -u "$APP" || true
    rm -rf "$DIR"
    ;;
esac
