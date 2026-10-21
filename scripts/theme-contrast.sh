#!/usr/bin/env bash
# 5.2b task 4: the sidebar text's contrast over each space theme (`-RoomSpike contrast`,
# App/Sources/Debug/ThemeSpikes.swift): five algorithms × eight sample colours × five
# wallpaper fixtures (a window of the spike's own behind Room's; never the user's desktop
# picture), light and dark, at tint opacity 0.5 (the default) and 1.0 (the highest), on a
# throwaway state. Prints the raw lines to <out-file> and a summary table (the minimum over
# the six probe heights; primary and secondary text) to <out-file>.md.
# Usage: scripts/theme-contrast.sh <out-file> [extra app args, e.g. -RoomSpikeOnly inactive]
# ROOM_APP picks the app (default the dev build's Debug app).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:?output file required}"; shift
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
WORK="/tmp/room-5/contrast/run-$(date +%s)"
mkdir -p "$WORK/state" "$WORK/engine"
ROOM_SPIKE_OUT="$OUT" scripts/run-spike.sh contrast -RoomStateDirectory "$WORK/state" -RoomEngineDirectory "$WORK/engine" \
  -ApplePersistenceIgnoreState YES -RoomSuggestionsOff YES "$@" > /dev/null
rm -rf "$WORK"
python3 - "$OUT" <<'PY'
import collections, re, sys
path = sys.argv[1]
rows = []
for line in open(path):
    m = re.match(r'contrast: (light|dark) (\w+) (\w+|-) (#\w+|-) ([\d.]+|-) primary=([\d.]+)/([\d.]+) secondary=([\d.]+)/([\d.]+) secondary_computed=([\d.]+) bg=(#\w+)', line)
    if m: rows.append(m.groups())
if not rows:
    print(open(path).read()); sys.exit(0)
out = []
walls = ['plain', 'stripes', 'confetti', 'night', 'sky']
for opacity in sorted({r[4] for r in rows if r[4] != '-'}):
    for appearance in ['light', 'dark']:
        out.append(f'\n**{appearance}, opacity {opacity}** (primary / secondary, the minimum of six probes; below 4.5 in bold)\n')
        out.append('| algorithm | colour | ' + ' | '.join(walls) + ' |')
        out.append('|---|---|' + '---|' * len(walls))
        keys = sorted({(r[2], r[3]) for r in rows if r[0] == appearance and r[4] == opacity}, key=lambda k: (['complementary','split','analogous','triadic','floating'].index(k[0]), k[1]))
        for algorithm, colour in keys:
            cells = []
            for w in walls:
                r = [x for x in rows if x[0] == appearance and x[1] == w and x[2] == algorithm and x[3] == colour and x[4] == opacity]
                if not r: cells.append('—'); continue
                p, s = float(r[0][5]), float(r[0][7])
                f = lambda v: f'**{v:.1f}**' if v < 4.5 else f'{v:.1f}'
                cells.append(f'{f(p)} / {f(s)}')
            out.append(f'| {algorithm} | {colour} | ' + ' | '.join(cells) + ' |')
out.append('\n**No tint** (the neutral material): ' + '; '.join(f'{r[0]} {r[1]} {float(r[5]):.1f} / {float(r[7]):.1f}' for r in rows if r[2] == 'none'))
summary = collections.defaultdict(lambda: [99, 99])
for r in rows:
    k = (r[0], r[4])
    summary[k][0] = min(summary[k][0], float(r[5])); summary[k][1] = min(summary[k][1], float(r[7]))
below = [r for r in rows if r[2] != 'none' and (float(r[5]) < 4.5 or float(r[7]) < 4.5)]
out.append('\n**Worst case** ' + '; '.join(f'{k[0]} opacity {k[1]}: primary {v[0]:.2f}, secondary {v[1]:.2f}' for k, v in sorted(summary.items())))
out.append(f'\n**Samples below 4.5:1:** {len(below)} of {len([r for r in rows if r[2] != "none"])} (primary {sum(float(r[5]) < 4.5 for r in below)}, secondary {sum(float(r[7]) < 4.5 for r in below)})')
open(path + '.md', 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[-3:]))
PY
