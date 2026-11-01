#!/usr/bin/env python3
"""Groups the collector's reports by where they crashed (6.3, the triage routine).

For every <id>.dmp under DATA_DIR not yet walked, runs rust-minidump's
`minidump-stackwalk --json --symbols-path SYMBOLS` (Breakpad symbols, laid out
as <module>/<debug id>/<module>.sym; the release pipeline writes them) and
keeps the crashing thread's top frames next to the dump (<id>.walk.json). Then
prints one line per signature (the top three frames with a function name),
most reports first, with the versions and process types seen and the newest
report's path.

    python3 triage.py --data /var/lib/room-crash --symbols /var/lib/room-crash/symbols [--days 14]
"""
import argparse
import collections
import datetime
import glob
import json
import os
import subprocess


def walk(dump, symbols):
    out = dump[:-4] + ".walk.json"
    if os.path.exists(out):
        return json.load(open(out))
    result = subprocess.run(["minidump-stackwalk", "--json", "--symbols-path", symbols, dump],
                            capture_output=True, text=True, timeout=300)
    try:
        walked = json.loads(result.stdout)
    except json.JSONDecodeError:
        walked = {"error": result.stderr[-2000:]}
    crash = walked.get("crash_info") or {}
    index = crash.get("crashing_thread")
    threads = walked.get("threads") or []
    frames = threads[index]["frames"] if index is not None and index < len(threads) else []
    summary = {
        "reason": crash.get("type"),
        "frames": [{"module": f.get("module"), "function": f.get("function"), "offset": f.get("module_offset")} for f in frames[:12]],
        "error": walked.get("error"),
    }
    json.dump(summary, open(out, "w"), indent=1)
    return summary


def signature(summary):
    named = [f"{f['module']}!{f['function']}" for f in summary.get("frames", []) if f.get("function")]
    if named:
        return " < ".join(named[:3])
    raw = [f"{f.get('module')}+{f.get('offset')}" for f in summary.get("frames", [])[:3]]
    return " < ".join(raw) or (summary.get("reason") or "unknown")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--data", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--days", type=int, default=14)
    args = parser.parse_args()
    since = (datetime.date.today() - datetime.timedelta(days=args.days)).isoformat()
    groups = collections.defaultdict(list)
    for dump in sorted(glob.glob(os.path.join(args.data, "*", "*", "*.dmp"))):
        if os.path.basename(os.path.dirname(dump)) < since:
            continue
        meta = json.load(open(dump[:-4] + ".json"))
        summary = walk(dump, args.symbols)
        groups[signature(summary)].append((meta, dump, summary.get("reason")))
    for sig, reports in sorted(groups.items(), key=lambda item: -len(item[1])):
        versions = sorted({m["annotations"].get("ver", "?") for m, _, _ in reports})
        kinds = sorted({m["annotations"].get("ptype", "browser") for m, _, _ in reports})
        newest = max(reports, key=lambda r: r[0]["received"])
        print(f"{len(reports):4}  {sig}\n      {reports[0][2]}; versions {', '.join(versions)}; processes {', '.join(kinds)}; newest {newest[1]}")
    if not groups:
        print(f"no reports since {since}")


if __name__ == "__main__":
    main()
