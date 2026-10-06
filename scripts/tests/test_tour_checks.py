#!/usr/bin/env python3
"""The kill test's tour check (B-79): a reopen ahead of the last ack is
informational; only a reopen behind it fails."""
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import tour_checks  # noqa: E402

SUMMARY = """summary: 100 kills in 61.2 seconds, {failures} failures
  kills with a transaction in flight: 40 (rolled back to the previous generation: 38)
  reopened ahead of the last ack (committed, ack not yet read; informational): {ahead}
  reopened behind the last ack (an acknowledged write lost): {behind}
  commit time median 0.9 ms, p95 1.4 ms, max 3.1 ms
"""


def evaluate(text):
    with tempfile.TemporaryDirectory() as run:
        os.makedirs(os.path.join(run, 'steps'))
        with open(os.path.join(run, 'steps', 'killtest.out'), 'w') as f:
            f.write(text)
        step = {'name': 'killtest', 'status': '0', 'crash_reports': '0', 'left_running': '0'}
        result = tour_checks.evaluate(run, step)
    return {name: ok for name, ok, _ in result['checks']}, dict(result['numbers'])


class KillTestCheck(unittest.TestCase):
    BEHIND = 'no reopen behind the last ack (no acknowledged write lost)'

    def test_ahead_of_the_ack_is_informational(self):
        checks, numbers = evaluate(SUMMARY.format(failures=0, ahead=2, behind=0))
        self.assertTrue(checks[self.BEHIND])
        self.assertTrue(all(checks.values()))
        self.assertEqual(numbers['reopened ahead of the last ack (informational)'], '2')

    def test_behind_the_ack_fails(self):
        checks, _ = evaluate(SUMMARY.format(failures=1, ahead=0, behind=1))
        self.assertFalse(checks[self.BEHIND])

    def test_missing_line_fails(self):
        checks, _ = evaluate("summary: 100 kills in 1 s, 0 failures\n")
        self.assertFalse(checks[self.BEHIND])


if __name__ == '__main__':
    unittest.main()
