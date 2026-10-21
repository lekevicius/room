#!/usr/bin/env bash
# Phase 3.7a: Chrome's password manager and autofill on Room.app over RoomCore
# (App/Sources/Debug/PasswordSpikes.swift). Serves research/spikes/phase-3.7
# (HTTP :8772 as 127.0.0.1 and localhost, HTTPS :8773 with a self-signed
# certificate whose SPKI hash Chromium is told to accept, for the card form),
# then runs on one throwaway state and engine directory:
#   1. `-RoomSpike passwords -RoomPasswordsPhase save` (save bubbles on two
#      sites, the update bubble, the sign-up page and its generation offer),
#   2. `-RoomSpike passwords -RoomPasswordsPhase fill` (the relaunch: both
#      sites fill from the suggestion popup with real keys, the sign-in,
#      chrome://password-manager),
#   3. `-RoomSpike autofill` (address save and update bubbles, the address
#      suggestion popup: fill, Esc, window move; card save bubble and fill).
# Each launch writes a net-log; every request is summarised by host and
# traffic annotation (scripts/lib/netlog-summary.py, page hosts 127.0.0.1 and
# localhost). After the runs the profile's stores are read with sqlite3: the
# saved logins (`Login Data`), addresses and cards (`Web Data`); password and
# card number columns are encrypted and only their lengths are printed.
# Captures are the spike's own, in-process (WindowSnapshot of Room's window
# with Chrome's bubble or popup or the host's popover; since 5.8e, no shell
# screencapture), into research/screenshots/phase-3.7a/ or ROOM_CAPTURE_DIR.
# 5.8a's engine half: the save phase accepts the host's popover where Chrome's
# bubble was, and answers Not Now and Never on the HTTPS site.
# Usage: scripts/passwords-autofill.sh [output directory] [-- extra app args]
# ROOM_PA_APPEARANCE=dark captures in the dark appearance (names end -light/-dark).
# ROOM_PA_ONLY=passwords|autofill runs one spike (passwords runs both phases).
# ROOM_PA_ONLY=import (4.3b): `-RoomPasswordsPhase import` (Profile.importPasswords
# on research/spikes/phase-4.3's CSVs: the saved one, then passwords.csv kept,
# then replaced), then the relaunch's `fill` phase: the imported passwords fill.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
OUTDIR="${1:-$(mktemp -d)}"; shift || true
[[ "${1:-}" == -- ]] && shift
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
SHOTS="${ROOM_CAPTURE_DIR:-research/screenshots/phase-3.7a}"
mkdir -p "$SHOTS"
SHOTS="$(cd "$SHOTS" && pwd)"  # absolute: the app's working directory is /
source scripts/lib/chromium-env.sh 2>/dev/null || true
annotations="${CHROMIUM_SRC:-}/tools/traffic_annotation/summary/annotations.xml"

for port in 8772 8773; do
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then echo "port $port is taken (a stale test server?)" >&2; exit 1; fi
done
python3 research/spikes/phase-3.7/server.py "$OUTDIR/spki.txt" 2>"$OUTDIR/server.log" &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 1 100); do
  [[ -s "$OUTDIR/spki.txt" && $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8772/login.html) == 200 ]] && break
  sleep 0.1
done
spki=$(cat "$OUTDIR/spki.txt")
state="$OUTDIR/state"; engine="$OUTDIR/engine"

# One launch: the spike and its net-log.
run() {
  local name="$1"; shift
  local out="$OUTDIR/spike-$name.txt"
  ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh "$@" -ApplePersistenceIgnoreState YES \
    -RoomStateDirectory "$state" -RoomEngineDirectory "$engine" -RoomSpikeAppearance "${ROOM_PA_APPEARANCE:-light}" -RoomSuggestionsOff YES \
    -RoomSpikeCaptureDirectory "$SHOTS" \
    "--ignore-certificate-errors-spki-list=$spki" "--log-net-log=$OUTDIR/netlog-$name.json" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >/dev/null || true
  echo "== $name"
  cat "$out"
  echo
}

EXTRA_ARGS=("$@")
only="${ROOM_PA_ONLY:-}"
if [[ -z "$only" || "$only" == passwords ]]; then
  run passwords-save passwords -RoomPasswordsPhase save
  run passwords-fill passwords -RoomPasswordsPhase fill
fi
if [[ "$only" == import ]]; then
  run passwords-import passwords -RoomPasswordsPhase import
  run passwords-fill passwords -RoomPasswordsPhase fill
fi
if [[ -z "$only" || "$only" == autofill ]]; then
  run autofill autofill
fi

echo "== the profile's stores (sqlite3 on copies)"
profile=$(find "$engine" -maxdepth 1 -type d -name 'Room Profile *' | head -1)
[[ -z "$profile" ]] && profile="$engine/Default"
echo "profile: ${profile#"$OUTDIR/"}"
cp "$profile/Login Data" "$OUTDIR/LoginData.sqlite" 2>/dev/null && \
  sqlite3 -header "$OUTDIR/LoginData.sqlite" \
    "SELECT origin_url, username_value, length(password_value) AS password_bytes, times_used, blacklisted_by_user FROM logins ORDER BY origin_url, username_value;" \
  || echo "no Login Data"
cp "$profile/Web Data" "$OUTDIR/WebData.sqlite" 2>/dev/null || echo "no Web Data"
if [[ -f "$OUTDIR/WebData.sqlite" ]]; then
  for table in local_addresses addresses; do
    if sqlite3 "$OUTDIR/WebData.sqlite" ".tables" | tr -s ' ' '\n' | grep -qx "$table"; then
      echo "-- $table: $(sqlite3 "$OUTDIR/WebData.sqlite" "SELECT count(*) FROM $table;") row(s)"
      tokens="${table%addresses}address_type_tokens"
      sqlite3 "$OUTDIR/WebData.sqlite" ".tables" | tr -s ' ' '\n' | grep -qx "$tokens" && \
        sqlite3 -separator ' = ' "$OUTDIR/WebData.sqlite" "SELECT type, value FROM $tokens WHERE value != '' ORDER BY guid, type;"
    fi
  done
  if sqlite3 "$OUTDIR/WebData.sqlite" ".tables" | tr -s ' ' '\n' | grep -qx credit_cards; then
    echo "-- credit_cards"
    sqlite3 -header "$OUTDIR/WebData.sqlite" \
      "SELECT name_on_card, expiration_month, expiration_year, length(card_number_encrypted) AS number_bytes FROM credit_cards;"
  fi
fi
echo

echo "== engine net-log by host (every launch)"
for log in "$OUTDIR"/netlog-*.json; do
  name=$(basename "$log" .json); name=${name#netlog-}
  echo "-- $name"
  python3 scripts/lib/netlog-summary.py "$log" "$OUTDIR/spike-$name.txt" \
    $( [[ -f "$annotations" ]] && echo --annotations "$annotations" ) --page-hosts 127.0.0.1,localhost \
    | tee "$OUTDIR/netlog-summary-$name.md"
done
echo "server: $(grep -c '^POST' "$OUTDIR/server.log" || true) POSTs ($(grep '^POST' "$OUTDIR/server.log" | awk '{print $2}' | sort | uniq -c | tr -s ' ' | tr '\n' ';'))"
echo "raw files: $OUTDIR"
