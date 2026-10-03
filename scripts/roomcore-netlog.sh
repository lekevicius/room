#!/usr/bin/env bash
# Launch the packaged Swift RoomCoreHost on about:blank, idle for 600 seconds,
# quit via NSApp.terminate, then summarize the flushed NetLog. No suppression
# switches are added here: before and after runs measure the engine defaults.
# Usage: scripts/roomcore-netlog.sh [new-evidence-directory] [extra Chromium args...]
# ROOM_NETLOG_SECONDS is for tooling smoke checks; only >=600 qualifies as audit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/chromium-env.sh"
APP="${ROOM_APP:-$ROOT/build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
DEST="${1:-$ROOT/research/notes/netlog-$(date +%Y%m%d-%H%M%S)}"
[[ $# -eq 0 ]] || shift
SECONDS_IDLE="${ROOM_NETLOG_SECONDS:-600}"
[[ "$SECONDS_IDLE" =~ ^[0-9]+$ ]] && (( SECONDS_IDLE > 0 )) || { echo 'invalid idle duration' >&2; exit 2; }
[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "missing packaged host: $APP" >&2; exit 1; }
# Never overwrite an earlier evidence run or reuse the normal browsing profile.
mkdir "$DEST"
DEST="$(cd "$DEST" && pwd)"
mkdir "$DEST/profile"
start=$(date +%s)
"$APP/Contents/MacOS/Room" -RoomSpike idle -RoomSpikeIdleSeconds "$SECONDS_IDLE" \
  -RoomSpikeOutput "$DEST/spike.txt" -RoomUserDataDir "$DEST/profile" \
  --use-mock-keychain --log-net-log="$DEST/netlog.json" --net-log-capture-mode=Default \
  "$@" > "$DEST/host.log" 2>&1 &
pid=$!
# Bound a hung startup/quit. Watchdog targets only the child we launched.
python3 -c 'import os,signal,sys,time; from pathlib import Path; time.sleep(int(sys.argv[2])); Path(sys.argv[3]).write_text("watchdog fired\n"); os.kill(int(sys.argv[1]),signal.SIGTERM)' "$pid" "$((SECONDS_IDLE + 120))" "$DEST/timeout.txt" &
watchdog=$!
trap 'kill "$watchdog" 2>/dev/null || true; kill -TERM "$pid" 2>/dev/null || true' INT TERM EXIT
status=0
wait "$pid" || status=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
trap - INT TERM EXIT
elapsed=$(( $(date +%s) - start ))
printf 'pid=%s\nexit_status=%s\nelapsed_seconds=%s\nrequested_idle_seconds=%s\n' \
  "$pid" "$status" "$elapsed" "$SECONDS_IDLE" > "$DEST/receipt.txt"
[[ "$status" -eq 0 && ! -e "$DEST/timeout.txt" ]] && grep -q '^idle-complete:' "$DEST/spike.txt" || {
  echo "incomplete run; see $DEST/receipt.txt and host.log" >&2; exit 1;
}
python3 "$ROOT/scripts/roomcore-netlog-summary.py" "$DEST/netlog.json" \
  --chromium-src "$CHROMIUM_SRC" --json-output "$DEST/summary.json" > "$DEST/summary.md"
cat "$DEST/receipt.txt" "$DEST/summary.md"
if (( SECONDS_IDLE < 600 )); then echo 'TOOLING SMOKE ONLY: shorter than ten minutes'; fi
