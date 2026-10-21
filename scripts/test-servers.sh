#!/usr/bin/env bash
# Every Chapter 2 test server at once, for a by-hand pass
# (research/notes/chapter-2-by-hand.md): 127.0.0.1:8765 phase-2.5 (cookies,
# colour pages), :8766 and its self-signed HTTPS twin :8767 phase-2.6
# (dialogs, auth, certificate, permissions, menus, files, popups, downloads,
# find, status, fullscreen), :8770 phase-2.7 (answering as 127.0.0.1 and as
# localhost: Peek, split, the menus), :8771 phase-2.8 (the dev update feed,
# a stand-in crash endpoint and a refusing proxy, each request logged to the
# file given, default /tmp/room-endpoints.log), and :8776 research/spikes
# itself (Chapter 3–4 fixtures: phase-3.7/pip.html, phase-4.6/media.html …;
# added 5.0a, B-107: by-hand step 53's link had no server). Ctrl-C stops them all.
# Usage: scripts/test-servers.sh [endpoints-log]
set -euo pipefail
cd "$(dirname "$0")/.."
endpoints="${1:-/tmp/room-endpoints.log}"
for port in 8765 8766 8767 8770 8771 8776; do
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then echo "port $port is taken (a stale test server?)" >&2; exit 1; fi
done
pids=""
python3 -m http.server 8765 --bind 127.0.0.1 -d research/spikes/phase-2.5 >/dev/null 2>&1 & pids="$pids $!"
python3 research/spikes/phase-2.6/server.py & pids="$pids $!"
python3 research/spikes/phase-2.7/server.py & pids="$pids $!"
python3 research/spikes/phase-2.8/server.py "$endpoints" & pids="$pids $!"
python3 -m http.server 8776 --bind 127.0.0.1 -d research/spikes >/dev/null 2>&1 & pids="$pids $!"
# shellcheck disable=SC2086
trap 'kill $pids 2>/dev/null || true' EXIT INT TERM
ready() { [[ $(curl -sk -o /dev/null -w '%{http_code}' "$1") == 200 ]]; }
for _ in $(seq 1 100); do
  ready http://127.0.0.1:8765/cookies.html && ready 'http://127.0.0.1:8766/download?size=1' && ready https://127.0.0.1:8767/secure.html \
    && ready http://127.0.0.1:8770/site.html && ready http://127.0.0.1:8771/appcast.xml \
    && ready http://127.0.0.1:8776/phase-3.7/pip.html && break
  sleep 0.1
done
: > "$endpoints"   # the readiness probes are not Room's
echo "serving :8765 :8766 :8767 :8770 :8771 :8776 (endpoints log: $endpoints); Ctrl-C stops" >&2
wait
