#!/usr/bin/env bash
# Phase 4.3a: makes the Chrome-family `History` fixture (chrome/Default/History) with the
# real schema: Chrome headless on a throwaway profile (/tmp/room-4.3/chrome, never the
# user's), one run per page (headless takes one target), each held 12 s so the history
# backend commits, then six rows added with sqlite3 for what a headless run cannot make
# (typed visits on several days, visits older than the engine's 89 days, an internal
# page, a hidden subframe, a form submit and its reload). Serves pages/ on :8780.
set -euo pipefail
cd "$(dirname "$0")"
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$C" --version
rm -rf /tmp/room-4.3/chrome; mkdir -p /tmp/room-4.3
python3 -m http.server 8780 --bind 127.0.0.1 --directory pages >/tmp/room-4.3/server.log 2>&1 &
server=$!; trap 'kill $server 2>/dev/null || true' EXIT
sleep 1
FLAGS=(--headless=new --user-data-dir=/tmp/room-4.3/chrome --no-first-run --no-default-browser-check --disable-sync
       --use-mock-keychain --password-store=basic --disable-component-update --disable-background-networking)
i=0
for u in http://127.0.0.1:8780/alpha.html http://127.0.0.1:8780/beta.html http://127.0.0.1:8780/redirect.html \
         "http://127.0.0.1:8780/gamma.html?q=1" about:blank http://127.0.0.1:8780/alpha.html http://127.0.0.1:8780/beta.html; do
  i=$((i+1))
  "$C" "${FLAGS[@]}" "$u" >"/tmp/room-4.3/chrome-run-$i.log" 2>&1 &
  pid=$!; sleep "${ROOM_HISTORY_WAIT:-12}"; kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  echo "run $i $u"
done
cp /tmp/room-4.3/chrome/Default/History chrome/Default/History
python3 - <<'PY'
import sqlite3, time
db = sqlite3.connect("chrome/Default/History")
now = int((time.time() + 11644473600) * 1_000_000)  # WebKit microseconds (since 1601)
day = 86_400_000_000
def add(url, title, visits, typed, hidden=0):
    cur = db.execute("insert into urls(url,title,visit_count,typed_count,last_visit_time,hidden) values(?,?,?,?,?,?)",
                     (url, title, len(visits), typed, max(t for t, _ in visits), hidden))
    for t, tr in visits:
        db.execute("insert into visits(url,visit_time,from_visit,transition,segment_id) values(?,?,0,?,0)", (cur.lastrowid, t, tr))
add("https://example.org/typed", "Typed three times", [(now - 3*day, 0x30000001), (now - 2*day, 0x30000001), (now - day, 0x30000001)], 3)
add("https://www.example.com/old", "Old and new", [(now - 120*day, 0x30000000), (now - 10*day, 0x30000000)], 0)
add("https://example.net/ancient", "Ancient", [(now - 200*day, 0x30000000)], 0)
add("chrome://settings/", "Settings", [(now - day, 0x30000001)], 1)
add("https://ads.example.com/frame", "", [(now - day, 0x30000003)], 0, hidden=1)
add("https://example.org/search?q=room", "Search results", [(now - 5*day, 0x30000007), (now - 5*day + 1_000_000, 0x30000008)], 0)
db.commit()
print("urls", db.execute("select count(*) from urls").fetchone()[0], "visits", db.execute("select count(*) from visits").fetchone()[0])
PY
