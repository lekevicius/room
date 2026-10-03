#!/usr/bin/env python3
"""Measure RoomCoreHost's NSApp.terminate path without AppleEvent permission.

Each run uses a fresh profile and launches an exact executable as a child.
The timing begins at the host's terminate-request-time marker, not at spawn.
Only helper PIDs observed beneath that child are checked after termination.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def processes():
    rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,command='], text=True)
    result = {}
    for line in rows.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3:
            result[int(parts[0])] = (int(parts[1]), parts[2])
    return result


def helpers_under(pid, rows):
    descendants = {pid}
    changed = True
    while changed:
        new = {child for child, (parent, _) in rows.items() if parent in descendants}
        changed = not new <= descendants
        descendants.update(new)
    return {child: rows[child][1] for child in descendants - {pid}
            if child in rows and 'Room Helper' in rows[child][1]}


def markers(path):
    if not path.exists():
        return {}
    return dict(line.split(': ', 1) for line in path.read_text().splitlines() if ': ' in line)


def crash_reports():
    directory = Path.home() / 'Library/Logs/DiagnosticReports'
    return {p.name for p in directory.glob('Room*')} if directory.exists() else set()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--diagnose-shutdown', action='store_true',
                        help='sample network teardown; timings include diagnostic overhead')
    parser.add_argument('--urls-json', type=Path, help='ten loopback fixture URLs; diagnostic only')
    parser.add_argument('--process-snapshot-ms', type=int, default=0,
                        help='diagnostic census interval; 0 preserves a full census every poll')
    args = parser.parse_args()
    if not 0 <= args.process_snapshot_ms <= 1000:
        parser.error('process snapshot interval must be between 0 and 1000 ms')
    executable = args.app.resolve() / 'Contents/MacOS/Room'
    if not executable.is_file() or args.runs < 1:
        parser.error('a packaged RoomCore host and positive run count are required')
    directory = args.output or Path(tempfile.mkdtemp(prefix='roomcore-quit-'))
    directory.mkdir(parents=True, exist_ok=True)
    print(f'evidence_directory={directory}', flush=True)
    for number in range(1, args.runs + 1):
        run_dir = directory / f'run-{number}'
        run_dir.mkdir()  # Never overwrite a previous run.
        spike = run_dir / 'spike.txt'
        before = crash_reports()
        observed = {}
        samplers = []
        sampled = False
        next_snapshot = 0.0
        snapshot_count = 0
        snapshot_seconds = 0.0
        current_helpers = {}
        load = os.getloadavg()[0]
        fixture_args = (['-RoomSpikeURLsJSON', str(args.urls_json.resolve())]
                        if args.urls_json else [])
        diagnostic_args = (['--enable-logging=stderr',
                            '--vmodule=browser_process_io_thread=1']
                           if args.diagnose_shutdown else [])
        with (run_dir / 'host.log').open('w') as log:
            process = subprocess.Popen([str(executable), '-RoomSpike', 'open10',
                '-RoomSpikeOutput', str(spike), '-RoomUserDataDir', str(run_dir / 'profile'),
                '--use-mock-keychain', *fixture_args, *diagnostic_args], stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 120
            try:
                while process.poll() is None:
                    if time.monotonic() >= next_snapshot:
                        census_start = time.monotonic()
                        rows = processes()
                        current_helpers = helpers_under(process.pid, rows)
                        observed.update(current_helpers)
                        snapshot_count += 1
                        snapshot_seconds += time.monotonic() - census_start
                        next_snapshot = time.monotonic() + args.process_snapshot_ms / 1000
                    if args.diagnose_shutdown and not sampled:
                        state = markers(spike)
                        if 'terminate-request-time' in state:
                            sampled = True
                            # Sampling the browser can retain task resources
                            # around exit and confound helper cleanup. Its
                            # watchdog already supplies a minidump if it hangs.
                            targets = {pid: 'network' for pid, command in current_helpers.items()
                                       if 'network.mojom.NetworkService' in command}
                            capture = {'started': time.time(), 'markers': state,
                                       'load': os.getloadavg(), 'helpers': current_helpers,
                                       'targets': targets}
                            (run_dir / 'shutdown-capture.json').write_text(
                                json.dumps(capture, indent=2) + '\n')
                            for pid, name in targets.items():
                                samplers.append(subprocess.Popen(
                                    ['sample', str(pid), '12', '10', '-file',
                                     str(run_dir / f'{name}-{pid}-sample.txt')],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
                    if time.monotonic() > deadline:
                        raise TimeoutError('host did not load ten pages and quit within 120 s')
                    time.sleep(0.02)
                exited = time.time()
                samplers_at_exit = sum(sampler.poll() is None for sampler in samplers)
                result = markers(spike)
                if process.returncode != 0 or 'terminate-request-time' not in result:
                    raise RuntimeError(f'host failed: exit={process.returncode}, markers={result}')
                if result.get('pages') != '10' or result.get('loading-at-ready') != '0' or 'error' in result:
                    raise RuntimeError(f'ten-page fixture incomplete: {result}')
                # Chrome code-sign-clone-cleanup can outlive the browser by 1.4 s.
                grace = time.monotonic() + 5
                while True:
                    rows = processes()
                    left = {pid: cmd for pid, cmd in observed.items() if pid in rows and rows[pid][1] == cmd}
                    if not left or time.monotonic() >= grace:
                        break
                    time.sleep(0.1)
                crashes = sorted(crash_reports() - before)
                receipt = {'corpus': result.get('corpus', 'external-typical-sites'), 'run': number, 'pages': 10, 'helpers_observed': len(observed),
                    'load1': load, 'quit_seconds': round(exited - float(result['terminate-request-time']), 3),
                    'helpers_left': len(left), 'leftover_helpers': left, 'new_crash_reports': crashes,
                    'exit_status': process.returncode, 'helper_grace_seconds': 5}
                receipt['process_snapshot_ms'] = args.process_snapshot_ms
                receipt['live_process_snapshots'] = snapshot_count
                receipt['live_process_snapshot_seconds'] = round(snapshot_seconds, 3)
                receipt['diagnostic_sampling'] = args.diagnose_shutdown
                receipt['samplers_running_at_browser_exit'] = samplers_at_exit
                (run_dir / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
                print(json.dumps(receipt), flush=True)
                if left or crashes:
                    if args.diagnose_shutdown and left:
                        pid = next(iter(left))
                        samplers.append(subprocess.Popen(
                            ['sample', str(pid), '2', '10', '-file',
                             str(run_dir / f'leftover-{pid}-sample.txt')],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
                    raise RuntimeError('shutdown left helpers or produced a crash report')
            except Exception as error:
                # A watchdog exit is the sample we most need to diagnose. Keep
                # its helpers and markers even when it cannot produce a valid
                # timing receipt; never turn the failure into a passing sample.
                rows = processes()
                failure = {
                    'error': str(error), 'exit_status': process.poll(),
                    'diagnostic_sampling': args.diagnose_shutdown,
                    'browser_pid': process.pid, 'load1': load,
                    'process_snapshot_ms': args.process_snapshot_ms,
                    'live_process_snapshots': snapshot_count,
                    'live_process_snapshot_seconds': round(snapshot_seconds, 3),
                    'markers': markers(spike), 'observed_helpers': observed,
                    'remaining_helpers': {
                        pid: cmd for pid, cmd in observed.items()
                        if pid in rows and rows[pid][1] == cmd},
                    'new_crash_reports': sorted(crash_reports() - before),
                    'minidumps': [str(path.relative_to(run_dir)) for path in
                                 sorted((run_dir / 'profile/Crashpad').rglob('*.dmp'))],
                }
                (run_dir / 'failure.json').write_text(
                    json.dumps(failure, indent=2) + '\n')
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                for sampler in samplers:
                    try:
                        sampler.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        sampler.terminate()
                        sampler.wait(timeout=5)
        time.sleep(3)


if __name__ == '__main__':
    main()
