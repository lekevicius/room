#!/usr/bin/env python3
"""Fixtures for evidence-sensitive NetLog attribution and zero-traffic checks."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('summary', Path(__file__).resolve().parents[1] / 'roomcore-netlog-summary.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)

TYPES = {'REQUEST_ALIVE': 1, 'URL_REQUEST_START_JOB': 2, 'SSL_CONNECT': 3,
         'HTTP_STREAM_JOB_BOUND_TO_REQUEST': 4, 'SOCKET_POOL_BOUND_TO_CONNECT_JOB': 5,
         'TCP_CONNECT': 6, 'HOST_RESOLVER_MANAGER_REQUEST': 7}


def event(kind, source, params=None, phase=1):
    return {'type': TYPES[kind], 'source': {'id': source}, 'params': params or {}, 'phase': phase, 'time': '1000'}


def run(events):
    return summary.summarize({'constants': {'logEventTypes': TYPES,
        'logEventPhase': {'PHASE_BEGIN': 1, 'PHASE_END': 2}}, 'events': events},
        {42: {'id': 'fixture_component', 'file': 'components/fixture.cc'}})


class NetLogTests(unittest.TestCase):
    def test_chromium_annotation_hash(self):
        self.assertEqual(summary.annotation_hash('123_id'), 70581310)

    def test_redirect_attempts_keep_component(self):
        report = run([event('REQUEST_ALIVE', 1, {'traffic_annotation': 42}),
            event('URL_REQUEST_START_JOB', 1, {'url': 'https://a.test/private?secret=1', 'initiator': 'https://page.test'}),
            event('URL_REQUEST_START_JOB', 1, {'url': 'https://b.test/redirect'})])
        self.assertEqual(report['request_attempts'], 2)
        self.assertEqual(report['unique_request_sources'], 1)
        self.assertEqual({r['host'] for r in report['requests']}, {'a.test', 'b.test'})
        self.assertTrue(all(r['component'] == 'fixture_component' for r in report['requests']))
        self.assertNotIn('secret', summary.markdown(report))

    def test_tls_dependency_walk_and_unknown(self):
        report = run([event('URL_REQUEST_START_JOB', 1, {'url': 'https://failure.test/'}),
            event('HTTP_STREAM_JOB_BOUND_TO_REQUEST', 2, {'source_dependency': {'id': 1}}),
            event('SOCKET_POOL_BOUND_TO_CONNECT_JOB', 3, {'source_dependency': {'id': 2}}),
            event('SSL_CONNECT', 3, {'net_error': -107}, phase=2),
            event('SSL_CONNECT', 8, {'net_error': -107}, phase=2),
            event('SSL_CONNECT', 9, {}, phase=2)])
        self.assertEqual(report['tls_failures'], [
            {'hosts': ['failure.test'], 'net_error': -107, 'count': 1},
            {'hosts': ['unknown'], 'net_error': -107, 'count': 1}])

    def test_preconnect_without_url_request_is_not_silent(self):
        report = run([event('TCP_CONNECT', 1), event('HOST_RESOLVER_MANAGER_REQUEST', 2, {'host': 'dns.test:443'})])
        self.assertEqual(report['request_attempts'], 0)
        self.assertFalse(report['observed_zero_network'])
        self.assertEqual(report['dns_requests'], [{'host': 'dns.test', 'count': 1}])

    def test_non_network_url_not_counted(self):
        report = run([event('URL_REQUEST_START_JOB', 1, {'url': 'data:text/html,hello'})])
        self.assertEqual(report['request_attempts'], 0)

    def test_unknown_component_stays_unknown(self):
        report = run([event('URL_REQUEST_START_JOB', 1, {'url': 'https://google.com/'})])
        self.assertEqual(report['requests'][0]['component'], 'unknown:None')

    def test_missing_constants_is_invalid(self):
        with self.assertRaises(KeyError):
            summary.summarize({'events': []}, {})


if __name__ == '__main__':
    unittest.main()
