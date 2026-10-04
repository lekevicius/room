#!/usr/bin/env bash
# B-38 shutdown watchdog, both harnesses, on the packaged embryo host:
#   (a) serial: N ten-real-page quits through NSApp.terminate, one
#       roomcore-quit-timing.py run each (what roomcore-baseline.sh's quit part
#       runs; rejected fixtures are retried, up to 2N attempts);
#   (b) concurrent: N rounds of scripts/roomcore-shutdown-local.py --mode room
#       --corpus real (three hosts load ten real pages each, then quit), the
#       branch's reproduction (roomcore-shutdown-investigation.md).
# Then a summary of every quit: seconds, exit (2 = Chrome's 10 s teardown
# watchdog), helpers left after the 5 s grace, new crash reports, load1.
# Usage: scripts/roomcore-watchdog.sh <new-evidence-directory> [N=20] [serial|concurrent|both]
# ROOM_APP: the host (default build/roomcore-host/.../Debug/Room.app).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?new evidence directory required}"
N="${2:-20}"
WHICH="${3:-both}"
mkdir "$DEST" || exit 1
DEST="$(cd "$DEST" && pwd)"
APP="${ROOM_APP:-$ROOT/build/roomcore-host/DerivedData/Build/Products/Debug/Room.app}"
export ROOM_APP="$APP"
echo "host $APP; N=$N; $(date '+%F %T'); load $(sysctl -n vm.loadavg)" | tee "$DEST/run.txt"
if [[ $WHICH != concurrent ]]; then
  # One ten-page quit per invocation: a page still loading at "ready" rejects
  # that fixture (not a quit sample) and would end a multi-run invocation, so
  # attempts repeat until N quits were measured (at most 2N attempts).
  mkdir -p "$DEST/serial"
  measured=0 attempt=0
  while (( measured < N && attempt < 2 * N )); do
    attempt=$((attempt + 1))
    python3 "$ROOT/scripts/roomcore-quit-timing.py" --app "$APP" --runs 1 \
      --output "$DEST/serial/attempt-$attempt" > "$DEST/serial/attempt-$attempt.log" 2>&1
    status=$?
    if grep -q 'ten-page fixture incomplete' "$DEST/serial/attempt-$attempt.log"; then
      echo "serial attempt $attempt: fixture rejected (a page still loading) $(date +%T)" | tee -a "$DEST/run.txt"
    else
      measured=$((measured + 1))
      echo "serial attempt $attempt: quit $measured, runner exit $status $(date +%T) load $(sysctl -n vm.loadavg)" | tee -a "$DEST/run.txt"
    fi
    sleep 3
  done
fi
if [[ $WHICH != serial ]]; then
  mkdir -p "$DEST/concurrent"
  for i in $(seq 1 "$N"); do
    python3 "$ROOT/scripts/roomcore-shutdown-local.py" --mode room --corpus real --app "$APP" \
      --output "$DEST/concurrent/round-$i" > "$DEST/concurrent/round-$i.log" 2>&1
    echo "concurrent round $i exit $? $(date +%T) load $(sysctl -n vm.loadavg)" | tee -a "$DEST/run.txt"
    # Leftovers of a failed round must not leak into the next.
    for _ in $(seq 1 20); do pgrep -f 'roomcore-host/DerivedData/Build/Products/.*/Room.app/Contents/' >/dev/null || break; sleep 1; done
    sleep 3
  done
fi
python3 - "$DEST" <<'PY' | tee "$DEST/summary.md"
import json, sys, statistics
from pathlib import Path
dest = Path(sys.argv[1])
def rows(kind, files):
    out = []
    for f in sorted(files, key=lambda p: [int(x) if x.isdigit() else x for x in p.as_posix().replace('-', '/').split('/')]):
        d = json.loads(f.read_text())
        ok = f.name == 'receipt.json'
        log = f.parent / 'host.log'
        watchdog = log.exists() and 'Teardown watchdog expired' in log.read_text(errors='replace')
        left = d.get('helpers_left', len(d.get('remaining_helpers', d.get('leftover_helpers', {})) or {}))
        note = '' if ok else ('teardown watchdog' if watchdog else d.get('error', 'failure')[:120])
        out.append((kind, f.parent.relative_to(dest).as_posix(), d.get('quit_seconds'), d.get('exit_status'),
                    left, len(d.get('new_crash_reports', []) or []),
                    round(d['load1'], 1) if isinstance(d.get('load1'), float) else d.get('load1'), note))
    return out
serial = rows('serial', list((dest / 'serial').rglob('receipt.json')) + list((dest / 'serial').rglob('failure.json'))) if (dest / 'serial').exists() else []
conc = rows('concurrent', list((dest / 'concurrent').rglob('receipt.json')) + list((dest / 'concurrent').rglob('failure.json'))) if (dest / 'concurrent').exists() else []
print('| Harness | Run | Quit s | Exit | Helpers left | Crash reports | load1 | Failure |')  # exit 2 = teardown watchdog
print('|---|---|---:|---:|---:|---:|---:|---|')
for r in serial + conc:
    print('| ' + ' | '.join('' if v is None else str(v) for v in r) + ' |')
for name, rs in (('serial', serial), ('concurrent', conc)):
    q = [r[2] for r in rs if isinstance(r[2], (int, float))]
    clean = [r for r in rs if r[3] == 0 and r[4] == 0 and r[5] == 0 and not r[7]]
    wd = [r for r in rs if r[3] == 2]
    if rs:
        print(f'\n{name}: {len(rs)} quits, clean {len(clean)}, watchdog exits {len(wd)}, '
              + (f'median {statistics.median(q):.3f} s, max {max(q):.3f} s' if q else 'no timings'))
PY
