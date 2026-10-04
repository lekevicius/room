#!/usr/bin/env python3
"""Local lifecycle checks for the diagnostic macOS libproc observer."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from roomcore_process_observer import ProcessObserver


def until(test, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if test():
            return
        time.sleep(0.02)
    raise AssertionError('lifecycle condition timed out')


with tempfile.TemporaryDirectory(prefix='room-observer-') as directory:
    root = Path(directory)
    child_pid_file = root / 'child'
    release = root / 'release'
    exec_release = root / 'exec'
    script = '''import os,time,sys
from pathlib import Path
pid=os.fork()
if pid==0:
 Path(sys.argv[1]).write_text(str(os.getpid()))
 while not Path(sys.argv[3]).exists():time.sleep(.01)
 os.execl('/bin/sleep','sleep','15')
while not Path(sys.argv[2]).exists():time.sleep(.01)
'''
    parent = subprocess.Popen(['python3', '-c', script, str(child_pid_file), str(release), str(exec_release)])
    child = None
    try:
        observer = ProcessObserver(parent.pid, helper_name='/bin/sleep')
        until(child_pid_file.exists)
        child = int(child_pid_file.read_text())
        until(lambda: (observer.snapshot(), child in observer.identities)[1])
        assert child not in observer.commands, 'pre-exec child is not a sleep helper'
        exec_release.touch()
        until(lambda: child in observer.snapshot())
        actual = observer.identities[child]
        observer.identities[child] = (actual[0], actual[1] + 1)
        assert child not in observer.remaining(), 'different start time must reject the same PID'
        observer.identities[child] = actual
        assert child in observer.remaining()
        # The parent exits while its already-observed child remains alive.
        release.touch()
        parent.wait(timeout=5)
        until(lambda: observer.info(child).ppid != parent.pid)
        assert child in observer.snapshot(), 'reparenting must not erase a helper'
        start = time.monotonic()
        for _ in range(100):
            assert child in observer.snapshot()
        elapsed = time.monotonic() - start
        os.kill(child, signal.SIGTERM)
        until(lambda: child not in observer.remaining())
        print(json.dumps({'creation_exec_reparent_exit': 'passed', 'start_identity_guard': 'passed',
                          'snapshots': 100, 'snapshot_seconds': round(elapsed, 6),
                          'command_queries': observer.command_queries}))
    finally:
        if parent.poll() is None:
            parent.terminate()
            parent.wait(timeout=5)
        if child:
            try:
                os.kill(child, signal.SIGTERM)
            except ProcessLookupError:
                pass

# Exercise the real runner's failure gate after the fixture browser exits.
# Compile an ordinary helper: relocated Apple platform binaries may be killed
# by signature policy, which would test a crash instead of a lingering child.
with tempfile.TemporaryDirectory(prefix='room-observer-runner-') as folder:
    directory = Path(folder)
    executable = directory / 'Fixture.app/Contents/MacOS/Room'
    executable.parent.mkdir(parents=True)
    helper = directory / 'Room Helper fixture'
    subprocess.run(['xcrun', 'clang', '-x', 'c', '-', '-o', str(helper)],
                   input='#include <unistd.h>\nint main(void){sleep(20);return 0;}\n',
                   text=True, check=True)
    executable.write_text('''#!/usr/bin/env python3
import sys,subprocess,time
from pathlib import Path
out=Path(sys.argv[sys.argv.index('-RoomSpikeOutput')+1])
p=subprocess.Popen([HELPER],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
(out.parent/'helper-pid').write_text(str(p.pid))
time.sleep(.5)
out.write_text('pages: 10\\nloading-at-ready: 0\\nterminate-request-time: '+str(time.time())+'\\n')
'''.replace('HELPER', repr(str(helper))))
    executable.chmod(0o755)
    output = directory / 'evidence'
    helper_pid = None
    try:
        result = subprocess.run(['python3', str(Path(__file__).with_name('roomcore-quit-timing.py')),
                                 '--app', str(directory / 'Fixture.app'), '--output', str(output),
                                 '--runs', '1', '--process-observer', 'libproc'],
                                capture_output=True, text=True, timeout=20)
        helper_pid = int((output / 'run-1/helper-pid').read_text())
        failure = json.loads((output / 'run-1/failure.json').read_text())
        receipt = json.loads((output / 'run-1/receipt.json').read_text())
        assert result.returncode != 0 and str(helper_pid) in failure['remaining_helpers'], result.stderr
        assert receipt['helpers_left'] == 1 and receipt['helper_grace_seconds'] == 5, receipt
        assert receipt['exit_status'] == 0 and failure['observer_error'] is None, failure
        print(json.dumps({'runner_rejects_lingering_helper': 'passed', 'helpers_left': 1,
                          'helper_grace_seconds': 5}))
    finally:
        if helper_pid:
            try:
                os.kill(helper_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
