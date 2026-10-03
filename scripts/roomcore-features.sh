#!/usr/bin/env bash
# Drive one feature in the packaged RoomCoreHost. No public API additions.
# Usage: scripts/roomcore-features.sh <feature> [new-evidence-directory]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEATURE="${1:?feature required}"
case "$FEATURE" in
  popups|dialogs|keys|audio|scroll|transparent|corners|band|form|extension|downloads|permissions|auth|certificate|find|zoom|print|fullscreen|widevine|fedcm|renderer-crash|autofill-save|autofill-update|ui-usb|ui-hid|ui-serial|ui-bluetooth) ;;
  *) echo "unknown feature: $FEATURE" >&2; exit 2 ;;
esac
APP="${ROOM_APP:-$ROOT/build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
DEST="${2:-$ROOT/research/notes/feature-$FEATURE-$(date +%Y%m%d-%H%M%S)}"
[[ -x "$APP/Contents/MacOS/Room" ]] || { echo "missing packaged host: $APP" >&2; exit 1; }
mkdir "$DEST"
DEST="$(cd "$DEST" && pwd)"
mkdir "$DEST/profile"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DEST/key.pem" -out "$DEST/cert.pem" \
  -days 1 -subj '/CN=localhost' > "$DEST/cert-generation.log" 2>&1
python3 "$ROOT/scripts/roomcore-fixtures.py" --root "$ROOT/research/spikes" \
  --cert "$DEST/cert.pem" --key "$DEST/key.pem" --receipt "$DEST/fixtures.json" > "$DEST/server.log" 2>&1 &
server=$!
pid='' watchdog=''
cleanup() {
  kill "$server" 2>/dev/null || true
  [[ -z "$watchdog" ]] || kill "$watchdog" 2>/dev/null || true
  [[ -z "$pid" ]] || kill -TERM "$pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
for _ in $(seq 1 50); do [[ -f "$DEST/fixtures.json" ]] && break; sleep 0.1; done
read -r http https < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["http"], d["https"])' "$DEST/fixtures.json")
# Chromium selects a port; DevToolsActivePort is written into our isolated profile.
# HostSpike needs the port before its drive. Reserve a currently free loopback
# port; a collision fails visibly instead of attaching to another profile.
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
extra=()
if [[ "$FEATURE" == extension ]]; then
  extra+=("--load-extension=$ROOT/research/spikes/phase-1.4/extension")
fi
if [[ "$FEATURE" == widevine ]]; then
  extra+=("--log-net-log=$DEST/netlog.json" "--net-log-capture-mode=Default")
  [[ -z "${ROOM_SPIKE_KEY_SYSTEM:-}" ]] || extra+=("-RoomSpikeKeySystem" "$ROOM_SPIKE_KEY_SYSTEM")
fi
start=$(date +%s)
"$APP/Contents/MacOS/Room" -RoomSpike "$FEATURE" -RoomSpikeOutput "$DEST/spike.txt" \
  -RoomSpikeBaseURL "$http" -RoomSpikeSecureURL "$https" -RoomSpikeCDPPort "$port" \
  -RoomUserDataDir "$DEST/profile" --use-mock-keychain \
  --remote-debugging-port="$port" --remote-debugging-address=127.0.0.1 \
  ${extra[@]+"${extra[@]}"} > "$DEST/host.log" 2>&1 &
pid=$!
watchdog_seconds=90
[[ "$FEATURE" != widevine ]] || watchdog_seconds=120
python3 -c 'import os,signal,sys,time; from pathlib import Path; time.sleep(int(sys.argv[3])); Path(sys.argv[2]).write_text("watchdog fired\n"); os.kill(int(sys.argv[1]),signal.SIGTERM)' "$pid" "$DEST/timeout.txt" "$watchdog_seconds" &
watchdog=$!
status=0
wait "$pid" || status=$?
pid=''
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
watchdog=''
printf 'feature=%s\nexit_status=%s\nelapsed_seconds=%s\nsource_commit=%s\n' "$FEATURE" "$status" "$(( $(date +%s) - start ))" "$(git -C "$ROOT" rev-parse HEAD)" > "$DEST/receipt.txt"
cat "$DEST/receipt.txt" "$DEST/spike.txt"
[[ "$status" -eq 0 && ! -e "$DEST/timeout.txt" ]] && ! grep -q '^error:' "$DEST/spike.txt" && grep -q "^end: $FEATURE$" "$DEST/spike.txt"
