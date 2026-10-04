#!/usr/bin/env python3
"""B-38: classifies the teardown-watchdog minidumps under an evidence directory.

For every Crashpad dump (profile/Crashpad/pending/*.dmp) LLDB prints all
threads (against the host app the run used, `--app`), and this reports where
the main thread waits (ThreadPoolImpl::Shutdown/CompleteShutdown, the network
service wait in ProcessHostCleanUp, the IO thread join, other) and how many
threads sit in ThreadFunc → _pthread_set_properties_self (a thread created
during shutdown that has not started yet: the worker-start/QoS lead behind
parked patch 0010, B-40). The full backtraces are written beside each dump.
Usage: roomcore-watchdog-stacks.py <evidence-dir> --app <Room.app>
"""
import argparse, re, subprocess
from pathlib import Path

def classify(text):
    threads = re.split(r'\n\s*thread #', text)
    main = threads[1] if len(threads) > 1 else ''
    if 'CompleteShutdown' in main or 'ThreadPoolImpl::Shutdown' in main:
        where = 'ThreadPoolImpl::Shutdown (CompleteShutdown)'
    elif 'ProcessHostCleanUp' in main or 'WaitForExit' in main:
        where = 'ProcessHostCleanUp (network service wait)'
    elif 'PlatformThreadBase::Join' in main or 'Thread::Stop' in main:
        where = 'IO thread join'
    else:
        where = 'other'
    starting = sum(1 for t in threads[1:] if '_pthread_set_properties_self' in t.split('frame #2')[0])
    blocking = sum(1 for t in threads[1:] if 'WaitForChildToDie' in t or 'ImportantFileWriter' in t)
    return where, starting, blocking

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('evidence', type=Path)
    p.add_argument('--app', type=Path, required=True)
    a = p.parse_args()
    exe = a.app / 'Contents/MacOS/Room'
    print('| Dump | Main thread waits in | Threads not yet started (pthread_set_properties_self) | Blocking-shutdown tasks seen |')
    print('|---|---|---:|---:|')
    for dump in sorted(a.evidence.rglob('Crashpad/pending/*.dmp')):
        out = dump.with_suffix('.lldb.txt')
        if not out.exists():
            r = subprocess.run(['perl', '-e', 'alarm shift; exec @ARGV', '300', 'lldb', '--batch',
                                '-o', f'target create "{exe}" --core "{dump}"', '-o', 'thread backtrace all'],
                               capture_output=True, text=True)
            out.write_text(r.stdout + r.stderr)
        where, starting, blocking = classify(out.read_text())
        print(f'| {dump.relative_to(a.evidence).as_posix()} | {where} | {starting} | {blocking} |')

if __name__ == '__main__':
    main()
