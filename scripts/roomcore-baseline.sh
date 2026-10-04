#!/usr/bin/env bash
# nav assertions, followed by one ten-loaded-page clean-quit measurement.
# Usage: scripts/roomcore-baseline.sh <new-evidence-directory>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:?new evidence directory required}"
mkdir "$DEST"
DEST="$(cd "$DEST" && pwd)"
APP="${ROOM_APP:-$ROOT/build/roomcore/DerivedData/Build/Products/Debug/Room.app}"
python3 - "$APP" "$DEST" <<'PY'
import json,subprocess,sys,time
from pathlib import Path
app=Path(sys.argv[1]); out=Path(sys.argv[2]); started=time.time()
with (out/'nav-host.log').open('w') as log:
    result=subprocess.run([str(app/'Contents/MacOS/Room'),'-RoomSpike','nav',
        '-RoomSpikeOutput',str(out/'nav.txt'),'-RoomUserDataDir',str(out/'nav-profile'),
        '--use-mock-keychain'],stdout=log,stderr=subprocess.STDOUT,timeout=120)
markers=dict(line.split(': ',1) for line in (out/'nav.txt').read_text().splitlines() if ': ' in line)
expected={'load1':['https://example.com/','back=false'],
          'load2':['https://en.wikipedia.org/wiki/Special:Version','back=true','forward=false'],
          'back':['https://example.com/','back=false','forward=true'],
          'forward':['https://en.wikipedia.org/wiki/Special:Version','back=true','forward=false'],
          'reload':['https://en.wikipedia.org/wiki/Special:Version','sawLoading=true'],
          'nativeView':['WebContentsViewCocoa','in window=true']}
assert result.returncode==0, f'nav exit {result.returncode}'
assert 'error' not in markers, markers
for key, values in expected.items():
    assert all(value in markers.get(key,'') for value in values), (key,markers.get(key))
receipt={'nav_exit':result.returncode,'nav_seconds':round(time.time()-started,3),'nav_assertions':'passed'}
(out/'nav-receipt.json').write_text(json.dumps(receipt)+'\n')
print(json.dumps(receipt),flush=True)
PY
ROOM_APP="$APP" ROOM_QUIT_MODE=spike "$ROOT/scripts/quit-timing.sh" 1 | tee "$DEST/quit.txt"
