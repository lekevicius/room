#!/usr/bin/env python3
"""Summarize a completed Chromium NetLog, preserving unknown attribution.

URL_REQUEST creation gives the traffic annotation hash; START_JOB gives
attempts (including redirects). TLS failures are attributed through NetLog
source dependencies, not guessed from the set of page URLs. Raw logs may
contain private URLs: only host names and Chromium source paths are printed.
"""
import argparse
from collections import Counter, defaultdict, deque
import json
import re
from pathlib import Path
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET


def annotation_hash(value):
    code = 0
    for byte in value.encode('utf-8'):
        code = (code * 31 + (byte if byte < 128 else byte - 256)) % 138003713
    return code


def annotations(src):
    result = {}
    path = src / 'tools/traffic_annotation/summary/annotations.xml'
    for item in ET.parse(path).getroot():
        name = item.get('id')
        if name:
            result[annotation_hash(name)] = {
                'id': name, 'file': item.get('file_path', 'unknown'),
            }
    return result


def host(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        return urlsplit(value if '://' in value else '//' + value).hostname
    except ValueError:
        return None


def summarize(data, annotation_map):
    constants = data['constants']
    types = {v: k for k, v in constants['logEventTypes'].items()}
    phases = {v: k for k, v in constants['logEventPhase'].items()}
    events = data['events']
    if not isinstance(events, list):
        raise ValueError('NetLog events must be an array')
    graph = defaultdict(set)
    metadata = defaultdict(dict)
    source_hosts = defaultdict(set)
    requests, tls, dns, connections = [], [], [], []
    times = []
    for event in events:
        source = event['source']['id']
        kind = types.get(event['type'], str(event['type']))
        phase = phases.get(event['phase'], str(event['phase']))
        params = event.get('params', {})
        if 'time' in event:
            times.append(float(event['time']))
        dep = params.get('source_dependency')
        if isinstance(dep, dict) and 'id' in dep:
            graph[source].add(dep['id'])
            graph[dep['id']].add(source)
        if 'traffic_annotation' in params:
            metadata[source]['annotation'] = params['traffic_annotation']
        if 'initiator' in params:
            metadata[source]['initiator'] = params['initiator']
        # A URL-bearing request source is useful for dependency attribution.
        for field in ('url', 'host', 'host_and_port', 'server_name', 'destination'):
            parsed = host(params.get(field))
            if parsed:
                source_hosts[source].add(parsed)
        # Socket pool retries/preconnects may have no request dependency.
        # GroupId::ToString serializes optional policy prefixes, destination,
        # then a space and the partition key. Only destination names the peer.
        group = params.get('group_id', '').split(' ', 1)[0]
        destination = re.search(r'(?:https?|wss?)://[^\s]+', group)
        if destination and (parsed := host(destination.group())):
            source_hosts[source].add(parsed)
        if kind == 'URL_REQUEST_START_JOB' and phase == 'PHASE_BEGIN':
            url = params.get('url', '')
            if urlsplit(url).scheme in ('http', 'https', 'ws', 'wss', 'ftp'):
                requests.append((source, host(url) or 'unknown'))
        if kind == 'SSL_CONNECT' and phase == 'PHASE_END' and params.get('net_error', 0) < 0:
            tls.append((source, params['net_error']))
        if kind == 'HOST_RESOLVER_MANAGER_REQUEST' and phase == 'PHASE_BEGIN':
            dns.append((source, host(params.get('host')) or 'unknown'))
        if kind in ('TCP_CONNECT', 'UDP_CONNECT', 'QUIC_SESSION') and phase == 'PHASE_BEGIN':
            connections.append((source, kind))

    def nearest_hosts(source):
        # Breadth first: don't assign every pooled connection's peers to a
        # request. Prefer the closest source with endpoint evidence. Ambiguous
        # results remain a set, and absent evidence remains unknown.
        queue, seen = deque([(source, 0)]), {source}
        found, depth = set(), None
        while queue:
            node, distance = queue.popleft()
            if depth is not None and distance > depth:
                break
            if source_hosts[node]:
                found.update(source_hosts[node])
                depth = distance
                continue
            for neighbor in graph[node]:
                if neighbor not in seen:
                    seen.add(neighbor)
                    queue.append((neighbor, distance + 1))
        return sorted(found) or ['unknown']

    counts = Counter()
    for source, hostname in requests:
        tag = metadata[source].get('annotation')
        annotation = annotation_map.get(tag, {})
        counts[(hostname, annotation.get('id', f'unknown:{tag}'),
                annotation.get('file', 'unknown'),
                metadata[source].get('initiator', 'unknown'))] += 1
    tls_counts = Counter((tuple(nearest_hosts(source)), error) for source, error in tls)
    return {
        'events': len(events),
        'event_span_seconds': (max(times) - min(times)) / 1000 if times else 0,
        'request_attempts': len(requests),
        'unique_request_sources': len({source for source, _ in requests}),
        'requests': [dict(host=h, component=c, source_file=f, initiator=i, attempts=n)
                     for (h, c, f, i), n in sorted(counts.items())],
        'tls_failures': [dict(hosts=list(h), net_error=e, count=n)
                         for (h, e), n in sorted(tls_counts.items())],
        'dns_requests': [dict(host=h, count=n) for h, n in sorted(Counter(h for _, h in dns).items())],
        'connection_attempts': len(connections),
        'connections': [dict(hosts=nearest_hosts(s), kind=k) for s, k in connections],
        # This describes observed traffic, not proof of a valid 600-second run.
        'observed_zero_network': not requests and not dns and not connections,
    }


def markdown(summary):
    lines = ['# RoomCore NetLog summary', '',
             f"Events: {summary['events']}; event span: {summary['event_span_seconds']:.3f} s.",
             f"Network request attempts: {summary['request_attempts']}; unique request sources: {summary['unique_request_sources']}; connection attempts: {summary['connection_attempts']}.",
             '', '| Host | Attempts | Traffic annotation / component | Chromium file | Initiator |',
             '|---|---:|---|---|---|']
    for row in summary['requests']:
        values = [row['host'], str(row['attempts']), row['component'], row['source_file'], row['initiator']]
        lines.append('| ' + ' | '.join(v.replace('|', '\\|').replace('\n', ' ') for v in values) + ' |')
    lines += ['', 'TLS failures (SSL_CONNECT end, negative net_error):', '']
    lines += [f"- {', '.join(r['hosts'])}: error {r['net_error']}, {r['count']} failures" for r in summary['tls_failures']] or ['- None.']
    lines += ['', 'DNS resolver requests:', '']
    lines += [f"- {r['host']}: {r['count']}" for r in summary['dns_requests']] or ['- None.']
    lines += ['', f"Observed zero network: {summary['observed_zero_network']}. Validate duration and clean shutdown against the runner receipt; an empty or short log alone is not a pass.", '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlog', type=Path)
    parser.add_argument('--chromium-src', type=Path, default=Path.home() / 'chromium/src')
    parser.add_argument('--json-output', type=Path)
    args = parser.parse_args()
    # json.load intentionally rejects truncated/incomplete logs.
    result = summarize(json.loads(args.netlog.read_text()), annotations(args.chromium_src))
    if args.json_output:
        args.json_output.write_text(json.dumps(result, indent=2) + '\n')
    print(markdown(result))


if __name__ == '__main__':
    main()
