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
    args = parser.parse_args()
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
        load = os.getloadavg()[0]
        with (run_dir / 'host.log').open('w') as log:
            process = subprocess.Popen([str(executable), '-RoomSpike', 'open10',
                '-RoomSpikeOutput', str(spike), '-RoomUserDataDir', str(run_dir / 'profile'),
                '--use-mock-keychain'], stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 120
            try:
                while process.poll() is None:
                    observed.update(helpers_under(process.pid, processes()))
                    if time.monotonic() > deadline:
                        raise TimeoutError('host did not load ten pages and quit within 120 s')
                    time.sleep(0.02)
                exited = time.time()
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
                receipt = {'run': number, 'pages': 10, 'helpers_observed': len(observed),
                    'load1': load, 'quit_seconds': round(exited - float(result['terminate-request-time']), 3),
                    'helpers_left': len(left), 'leftover_helpers': left, 'new_crash_reports': crashes,
                    'exit_status': process.returncode, 'helper_grace_seconds': 5}
                (run_dir / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
                print(json.dumps(receipt), flush=True)
                if left or crashes:
                    raise RuntimeError('shutdown left helpers or produced a crash report')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
        time.sleep(3)


if __name__ == '__main__':
    main()
