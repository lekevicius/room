"""Read-only macOS network-thread snapshots; never suspend the target.

The public PROC_PIDLISTTHREADS API returns thread handles, not unique kernel
thread IDs. Handles may be reused even within a process. These are raw samples,
not a lifetime CPU-accounting ledger; do not join samples by handle alone.
"""
import ctypes
import errno
import json
import time


class ThreadInfo(ctypes.Structure):
    _fields_ = [('user_time', ctypes.c_uint64), ('system_time', ctypes.c_uint64)] + [
        (name, ctypes.c_int32) for name in ('cpu_usage', 'policy', 'run_state', 'flags',
                                          'sleep_time', 'current_priority', 'priority', 'max_priority')
    ] + [('name', ctypes.c_char * 64)]


class ThreadObserver:
    def __init__(self, process_observer, output):
        self.processes = process_observer
        self.output = output
        self.next_snapshot = 0.0
        self.snapshots = 0
        self.query_seconds = 0.0

    def snapshot(self, helpers, terminating):
        now = time.monotonic()
        if now < self.next_snapshot:
            return
        self.next_snapshot = now + 0.25
        started = time.monotonic()
        # proc_pidinfo returns bytes; PROC_PIDLISTTHREADS yields thread handles.
        for pid, command in helpers.items():
            if 'network.mojom.NetworkService' not in command or not self.processes.is_same_process(pid):
                continue
            capacity = 64
            while True:
                ids = (ctypes.c_uint64 * capacity)()
                ctypes.set_errno(0)
                size = self.processes.lib.proc_pidinfo(pid, 6, 0, ids, ctypes.sizeof(ids))
                if size <= 0:
                    self.processes._gone_or_raise('PROC_PIDLISTTHREADS', pid)
                    break
                if size % ctypes.sizeof(ctypes.c_uint64):
                    raise RuntimeError('invalid thread-list ABI size')
                if size < ctypes.sizeof(ids):
                    break
                capacity *= 2
                if capacity > 65536:
                    raise RuntimeError('thread list exceeded diagnostic limit')
            if size <= 0:
                continue
            threads = []
            zero_handles = 0
            for handle in ids[:size // ctypes.sizeof(ctypes.c_uint64)]:
                # Threads before userspace registration can have a zero handle.
                # Querying zero cannot identify one of multiple such threads.
                if handle == 0:
                    zero_handles += 1
                    continue
                info = ThreadInfo()
                ctypes.set_errno(0)
                received = self.processes.lib.proc_pidinfo(pid, 5, handle, ctypes.byref(info), ctypes.sizeof(info))
                if received == 0 and ctypes.get_errno() in (errno.ESRCH, errno.ENOENT):
                    continue
                if received != ctypes.sizeof(info):
                    raise RuntimeError(f'thread info unavailable: pid={pid}, thread_handle={handle}, size={received}, errno={ctypes.get_errno()}')
                row = {name: getattr(info, name) for name, _ in info._fields_ if name != 'name'}
                row.update(thread_handle=handle, name=bytes(info.name).decode('utf-8', errors='replace'))
                threads.append(row)
            if not self.processes.is_same_process(pid):
                continue
            self.output.write(json.dumps({'time': time.time(), 'pid': pid,
                                          'process_start': self.processes.identities[pid],
                                          'identity_kind': 'reusable_thread_handle',
                                          'zero_handles_omitted': zero_handles,
                                          'terminating': terminating, 'threads': threads}) + '\n')
            self.snapshots += 1
        self.query_seconds += time.monotonic() - started
