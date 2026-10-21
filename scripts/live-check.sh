#!/usr/bin/env bash
# 5.0a: live-site checks, on demand only (never CI; these are requests the
# session makes for a check, never ones the product makes). Runs
# `-RoomSpike live` (App/Sources/Debug/LiveSpikes.swift) on a fresh state and
# engine directory under /tmp/room-5 with the blocker's defaults, over the
# sites and expectations in scripts/live-sites.json (or the file given), and
# prints one table: per site and pass (off = the site panel's switch off, on =
# the defaults) the blocked requests, the elements with display:none and in
# all, the elements the bundled lists' hiding rules match and how many of
# them are hidden (the cosmetic filters' work, read from the list files), the
# ad containers by common names and how many are hidden (the two passes load
# different ads, so these are compared as shares), the visible consent containers, the cookie banner
# autoconsent answered and the selectors asked for; then PASS/FAIL per
# expectation. Needs the network.
# Usage: scripts/live-check.sh [sites.json] [extra app args, e.g. -RoomSpikeOnly delfi]
# ROOM_APP=<Room.app> picks the app (the release framework's Debug app for numbers).
set -euo pipefail
cd "$(dirname "$0")/.."
SITES="scripts/live-sites.json"
[[ $# -gt 0 && "$1" == *.json ]] && { SITES="$1"; shift; }
SITES="$(cd "$(dirname "$SITES")" && pwd)/$(basename "$SITES")"
mkdir -p /tmp/room-5
work="$(mktemp -d /tmp/room-5/live.XXXXXX)"
out="$work/spike.txt"
echo "state: $work"
echo "conditions: app=${ROOM_APP:-build/roomcore/DerivedData/Build/Products/Debug/Room.app} load=$(sysctl -n vm.loadavg) date=$(date -u +%FT%TZ)"
ROOM_SPIKE_OUT="$out" scripts/run-spike.sh live -RoomLiveSites "$SITES" -RoomStateDirectory "$work/state" \
  -RoomEngineDirectory "$work/engine" -RoomSpikeAppearance light -ApplePersistenceIgnoreState YES "$@" >/dev/null || true
python3 - "$SITES" "$out" <<'PY'
import json, re, sys
sites = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).read().splitlines()
values = {}
for line in lines:
    key, _, rest = line.partition(": ")
    values[key] = rest
print(f"lists: {values.get('live_lists', '?')}")
print(f"{'site':10} {'pass':4} {'load_s':>6} {'blocked':>7} {'hidden':>6} {'total':>6} {'ads hid':>9} {'lists hid':>11} {'iframes':>7}  banners / autoconsent / present")
failures = 0
def parse(rest):
    m = re.match(r"load_s=(\S+) blocked=(\d+) probe=(.*) cookie_banner=(.*)$", rest)
    if not m: return None
    try: probe = json.loads(m.group(3))
    except Exception: probe = {}
    return {"load": m.group(1), "blocked": int(m.group(2)), "probe": probe, "cookie": m.group(4)}
for site in sites:
    name = site["name"]
    passes = {p: parse(values.get(f"live_{name}_{p}", "")) for p in ("off", "on")}
    if not any(passes.values()):
        print(f"{name:10} not run ({values.get(f'live_{name}_off') or values.get(f'live_{name}') or 'no line'})")
        if not values.get("error") and f"live_{name}_off" not in values: continue
    for p, r in passes.items():
        if not r: continue
        pr = r["probe"]
        ads = f"{pr.get('adHidden', '?')}/{pr.get('adLike', '?')}"
        lists = f"{pr.get('listHidden', '?')}/{pr.get('listMatched', '?')}"
        print(f"{name:10} {p:4} {r['load']:>6} {r['blocked']:>7} {pr.get('hidden', '?'):>6} {pr.get('total', '?'):>6} {ads:>9} {lists:>11} {pr.get('iframes', '?'):>7}  "
              f"{pr.get('banners')} / {r['cookie']} / {pr.get('present')} ({pr.get('host')})")
    off, on = passes["off"], passes["on"]
    if not (off and on):
        print(f"  FAIL {name}: a pass did not run"); failures += 1; continue
    exp = site.get("expect", {})
    checks = []
    if "blocked_on_min" in exp: checks.append((f"blocked on ≥ {exp['blocked_on_min']}", on["blocked"] >= exp["blocked_on_min"]))
    if "blocked_off_max" in exp: checks.append((f"blocked off ≤ {exp['blocked_off_max']}", off["blocked"] <= exp["blocked_off_max"]))
    share = lambda r: (r["probe"].get("adHidden") or 0) / max(1, r["probe"].get("adLike") or 0)
    if "list_hidden_on_min" in exp:
        n = on["probe"].get("listHidden") or 0
        checks.append((f"elements the lists hide, hidden on {n} ≥ {exp['list_hidden_on_min']} (off {off['probe'].get('listHidden')} of {off['probe'].get('listMatched')})",
                       n >= exp["list_hidden_on_min"]))
    if "ad_hidden_on_min" in exp:
        n = on["probe"].get("adHidden") or 0
        checks.append((f"ad containers hidden on {n} ≥ {exp['ad_hidden_on_min']}", n >= exp["ad_hidden_on_min"]))
    if exp.get("ad_share_higher_on"):
        checks.append((f"share of ad containers hidden on {share(on):.2f} > off {share(off):.2f}", share(on) > share(off)))
    if exp.get("banner_gone_on"):
        shown = bool(off["probe"].get("banners")) or "consent." in str(off["probe"].get("host", ""))
        gone = not on["probe"].get("banners") and "consent." not in str(on["probe"].get("host", ""))
        answered = on["cookie"] != "none" or off["cookie"] != "none"
        checks.append((f"cookie banner: shown off={shown}, gone on={gone}, autoconsent={on['cookie']}", gone and (shown or answered)))
    for sel in exp.get("present_on", []): checks.append((f"{sel} present", sel in (on["probe"].get("present") or [])))
    for label, ok in checks:
        print(f"  {'PASS' if ok else 'FAIL'} {name}: {label}")
        failures += 0 if ok else 1
print(f"live-check: {failures} failure(s)")
PY
echo "raw: $out"
