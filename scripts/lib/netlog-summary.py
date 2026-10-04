#!/usr/bin/env python3
"""Phase 2.8b: summarises a Chromium net-log (CEF's --log-net-log) by host.

Every URL request is listed with its method, path, initiator, traffic
annotation (named from the Chromium checkout's annotations.xml when given)
and the phase of the run it fell in (from the spike's `phase: <name> <epoch>`
lines); DNS lookups, preconnects, QUIC sessions and sockets that carry no URL
request are listed by host too. Hosts in --page-hosts are page traffic; any
other host in the net-log is the engine's own (Room's own code never goes
through the engine's network stack).

Usage: netlog-summary.py <netlog.json> <spike-output.txt> [--annotations annotations.xml] [--page-hosts 127.0.0.1,localhost]
"""
import argparse, json, re, sys, urllib.parse
from collections import defaultdict


def load(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # A net-log cut short (no orderly shutdown): keep the events written so far.
        cut = text.rstrip().rstrip(",")
        end = cut.rfind("}")
        return json.loads(cut[: end + 1] + "]}")


def annotation_names(path):
    names = {}
    if not path:
        return names
    for unique_id in re.findall(r'<item id="([^"]+)"', open(path, encoding="utf-8").read()):
        h = 0
        for ch in unique_id:
            h = (h * 31 + ord(ch)) % 138003713
        names[h] = unique_id
    return names


def phases(path):
    marks = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"phase: (\S+) ([0-9.]+)", line)
        if m:
            marks.append((float(m.group(2)) * 1000, m.group(1)))
    return sorted(marks)


def phase_at(marks, ms):
    name = "before launch"
    for start, phase in marks:
        if ms >= start:
            name = phase
    return name


def host_of(value):
    if not value:
        return None
    value = str(value)
    if "://" in value:
        return urllib.parse.urlsplit(value).hostname
    # group ids ("ssl/www.google.com:443", "pm/…"), "host:port"
    value = value.split("/")[-1] if "/" in value else value
    return value.rsplit(":", 1)[0].strip("[]") or None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("netlog")
    parser.add_argument("spike")
    parser.add_argument("--annotations")
    parser.add_argument("--page-hosts", default="127.0.0.1,localhost")
    args = parser.parse_args()
    log = load(args.netlog)
    constants = log["constants"]
    event_names = {v: k for k, v in constants["logEventTypes"].items()}
    offset = int(constants.get("timeTickOffset", 0))
    names = annotation_names(args.annotations)
    marks = phases(args.spike)
    page_hosts = set(args.page_hosts.split(","))

    requests = {}          # source id -> dict
    other = defaultdict(lambda: defaultdict(set))  # host -> kind -> phases
    for event in log["events"]:
        name = event_names.get(event["type"], str(event["type"]))
        params = event.get("params") or {}
        source = event["source"]["id"]
        ms = int(event["time"]) + offset
        if name == "URL_REQUEST_START_JOB":
            url = params.get("url", "")
            parts = urllib.parse.urlsplit(url)
            request = requests.setdefault(source, {})
            if "url" not in request:
                request.update({"url": url, "host": parts.hostname, "path": parts.path or "/", "scheme": parts.scheme,
                                "method": params.get("method"), "initiator": params.get("initiator", "—"),
                                "phase": phase_at(marks, ms), "annotation": params.get("traffic_annotation")})
        elif name in ("REQUEST_ALIVE", "URL_REQUEST_DELEGATE_CONNECTED") and params.get("traffic_annotation") is not None:
            requests.setdefault(source, {}).setdefault("annotation_alive", params["traffic_annotation"])
        elif name == "HOST_RESOLVER_MANAGER_REQUEST" and event.get("phase") == 1:
            host = host_of(params.get("host"))
            if host:
                other[host]["dns lookup"].add(phase_at(marks, ms))
        elif name == "HTTP_STREAM_JOB_CONTROLLER" and event.get("phase") == 1:
            host = host_of(params.get("url"))
            if host:
                other[host]["preconnect" if params.get("is_preconnect") else "stream"].add(phase_at(marks, ms))
        elif name == "QUIC_SESSION" and event.get("phase") == 1:
            host = host_of(params.get("host"))
            if host:
                other[host]["QUIC session"].add(phase_at(marks, ms))
        elif name == "TRANSPORT_CONNECT_JOB_CONNECT" or (name.endswith("CONNECT_JOB") and event.get("phase") == 1):
            host = host_of(params.get("group_id") or params.get("group_name"))
            if host:
                other[host]["socket connect"].add(phase_at(marks, ms))

    rows = [r for r in requests.values() if r.get("url")]
    for r in requests.values():
        if r.get("url") and r.get("annotation") is None:
            r["annotation"] = r.get("annotation_alive")
    by_host = defaultdict(list)
    for r in rows:
        by_host[r["host"] or "(none)"].append(r)
    hosts = sorted(set(by_host) | set(other))
    print("| Host | Attributed to | URL requests (method path · initiator · traffic annotation · phase) | Other network events (phase) |")
    print("|---|---|---|---|")
    for host in hosts:
        owner = "page traffic (excluded)" if host in page_hosts else "engine (CEF/Chromium, B-19)"
        listed = []
        seen = set()
        for r in sorted(by_host.get(host, []), key=lambda r: (r["phase"], r["path"])):
            ann = r.get("annotation")
            ann_name = names.get(ann, str(ann) if ann is not None else "—")
            key = (r["method"], r["scheme"], r["path"], r["initiator"], ann_name, r["phase"])
            if key in seen:
                continue
            seen.add(key)
            listed.append(f"{r['method']} {r['scheme']}://…{r['path']} · {r['initiator']} · {ann_name} · {r['phase']}")
        count = len(by_host.get(host, []))
        if host in page_hosts and listed:
            listed = [f"{count} requests (page loads, favicons)"]
        events = "; ".join(f"{kind} ({', '.join(sorted(p))})" for kind, p in sorted(other.get(host, {}).items()))
        print(f"| {host} | {owner} | {'<br>'.join(listed) or '—'} | {events or '—'} |")
    engine = [h for h in hosts if h not in page_hosts]
    print()
    print(f"hosts: {len(hosts)} ({len(engine)} not page traffic: {', '.join(engine) or 'none'}); URL requests: {len(rows)}")


if __name__ == "__main__":
    sys.exit(main())
