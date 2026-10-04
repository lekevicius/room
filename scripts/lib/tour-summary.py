#!/usr/bin/env python3
"""The grand tour's summary (scripts/grand-tour.sh, Phase 2.9).

Given one appearance's run directory (steps.tsv, steps/, captures/) it
prints every step with its checks and results, every capture's path and the
numbers; given the tour directory it prints each appearance's summary in
turn, with the tour's wall time.
"""
import argparse, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tour_checks  # noqa: E402


def read_tsv(path):
    with open(path) as f:
        rows = [line.rstrip("\n").split("\t") for line in f if line.strip()]
    head, body = rows[0], rows[1:]
    return [dict(zip(head, r)) for r in body]


def read_kv(path):
    try:
        with open(path) as f:
            return dict(line.rstrip("\n").split("\t", 1) for line in f if "\t" in line)
    except FileNotFoundError:
        return {}


def run_summary(run, out):
    steps = read_tsv(os.path.join(run, "steps.tsv"))
    appearance = os.path.basename(run.rstrip("/"))
    seconds = read_kv(os.path.join(run, "run.tsv")).get("run_seconds")
    results = [tour_checks.evaluate(run, s) for s in steps]
    passed = sum(1 for r in results for c in r["checks"] if c[1])
    failed = sum(1 for r in results for c in r["checks"] if not c[1])
    out.append(f"## {appearance}\n")
    if seconds:
        out.append(f"Wall time {float(seconds) / 60:.1f} min. Checks: **{passed} passed, {failed} failed**.\n")
    out.append("| Step | Group | Exit | Time | Checks passed | Failed |")
    out.append("|---|---|---|---|---|---|")
    for s, r in zip(steps, results):
        bad = [c for c in r["checks"] if not c[1]]
        out.append(f"| {s['name']} | {s['group']} | {s['status']} | {float(s['seconds']):.0f} s | "
                   f"{sum(1 for c in r['checks'] if c[1])}/{len(r['checks'])} | "
                   f"{'; '.join(c[0] for c in bad) if bad else '—'} |")
    out.append("")
    out.append("### Checks\n")
    for s, r in zip(steps, results):
        out.append(f"**{s['name']}**")
        for name, ok, detail in r["checks"]:
            out.append(f"- {'pass' if ok else 'FAIL'} — {name}" + (f": {detail}" if detail else ""))
        if r["notes"]:
            for note in r["notes"]:
                out.append(f"- note — {note}")
        out.append("")
    out.append("### Numbers\n")
    for s, r in zip(steps, results):
        if r["numbers"]:
            out.append(f"**{s['name']}**")
            for key, value in r["numbers"]:
                out.append(f"- {key}: {value}")
            out.append("")
    out.append("### Captures\n")
    caps = os.path.join(run, "captures")
    for root, _, files in sorted(os.walk(caps)):
        pngs = sorted(f for f in files if f.endswith((".png", ".jpg")))
        if pngs:
            rel = os.path.relpath(root, run)
            out.append(f"- `{rel}/` ({len(pngs)}): " + ", ".join(pngs))
    out.append("")
    return passed, failed


def main():
    p = argparse.ArgumentParser()
    p.add_argument("directory")
    p.add_argument("--commit", default="")
    p.add_argument("--binary", default="")
    a = p.parse_args()
    out = []
    if os.path.exists(os.path.join(a.directory, "steps.tsv")):
        out.append(f"# Grand tour — {os.path.basename(a.directory)}\n")
        out.append(f"Build {a.commit} (Room binary sha256 {a.binary}).\n")
        run_summary(a.directory, out)
    else:
        tour = read_kv(os.path.join(a.directory, "tour.tsv")).get("tour_seconds")
        build = read_kv(os.path.join(a.directory, "build.tsv")).get("build_seconds")
        out.append(f"# Grand tour {os.path.basename(a.directory)}\n")
        out.append(f"Build {a.commit} (Room binary sha256 {a.binary})"
                   + (f", built in {float(build):.0f} s" if build else "")
                   + (f"; tour wall time {float(tour) / 60:.1f} min" if tour else "") + ".\n")
        totals = []
        for appearance in ("light", "dark"):
            run = os.path.join(a.directory, appearance)
            if os.path.exists(os.path.join(run, "steps.tsv")):
                totals.append((appearance, *run_summary(run, out)))
        out.insert(2, "Totals: " + "; ".join(f"{ap} {p} passed, {f} failed" for ap, p, f in totals) + ".\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
