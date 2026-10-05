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
# Answers `capture_screen: <name> x,y,w,h` lines with `screencapture -R` into
# research/screenshots/phase-3.7a/ (needs the screen unlocked and Screen
# Recording for the shell that runs it).
# Usage: scripts/passwords-autofill.sh [output directory] [-- extra app args]
# ROOM_PA_ONLY=passwords|autofill runs one spike (passwords runs both phases).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
OUTDIR="${1:-$(mktemp -d)}"; shift || true
[[ "${1:-}" == -- ]] && shift
mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
SHOTS="${ROOM_CAPTURE_DIR:-research/screenshots/phase-3.7a}"
mkdir -p "$SHOTS"
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

# One launch: the spike, its captures, its net-log.
run() {
  local name="$1"; shift
  local out="$OUTDIR/spike-$name.txt"
  ROOM_APP="$APP" ROOM_SPIKE_OUT="$out" scripts/run-spike.sh "$@" -ApplePersistenceIgnoreState YES \
    -RoomStateDirectory "$state" -RoomEngineDirectory "$engine" -RoomSpikeAppearance light \
    "--ignore-certificate-errors-spki-list=$spki" "--log-net-log=$OUTDIR/netlog-$name.json" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} >/dev/null &
  local runner=$! done_names=""
  while kill -0 "$runner" 2>/dev/null; do
    if [[ -f "$out" ]]; then
      while IFS= read -r line; do
        local rest=${line#*: }
        local shot=${rest%% *}
        [[ " $done_names " == *" $shot "* ]] && continue
        screencapture -x -R "${rest#* }" "$SHOTS/$shot.png" || echo "capture of $shot failed" >&2
        touch "$out.ack-$shot"
        done_names="$done_names $shot"
        echo "captured $SHOTS/$shot.png" >&2
      done < <(grep -E '^capture_screen: ' "$out" || true)
    fi
    sleep 0.2
  done
  wait "$runner" || true
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
if [[ -z "$only" || "$only" == autofill ]]; then
  run autofill autofill
fi

echo "== the profile's stores (sqlite3 on copies)"
profile=$(find "$engine" -maxdepth 1 -type d -name 'Room Profile *' | head -1)
[[ -z "$profile" ]] && profile="$engine/Default"
echo "profile: ${profile#"$OUTDIR/"}"
cp "$profile/Login Data" "$OUTDIR/LoginData.sqlite" 2>/dev/null && \
  sqlite3 -header "$OUTDIR/LoginData.sqlite" \
    "SELECT origin_url, username_value, length(password_value) AS password_bytes, times_used FROM logins ORDER BY origin_url;" \
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
