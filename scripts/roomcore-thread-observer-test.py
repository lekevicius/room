#!/usr/bin/env python3
"""Local lifecycle/ABI check for the opt-in read-only thread observer."""
import ctypes
import io
import json
import os
import threading
import time

from roomcore_process_observer import ProcessObserver
from roomcore_thread_observer import ThreadInfo, ThreadObserver


def main():
    assert ctypes.sizeof(ThreadInfo) == 112
    lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
    lib.pthread_self.restype = ctypes.c_void_p
    lib.pthread_mach_thread_np.argtypes = [ctypes.c_void_p]
    lib.pthread_mach_thread_np.restype = ctypes.c_uint32
    lib.thread_info.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_void_p,
                                ctypes.POINTER(ctypes.c_uint32)]
    lib.thread_info.restype = ctypes.c_int
    lib.pthread_setname_np.argtypes = [ctypes.c_char_p]
    lib.pthread_setname_np.restype = ctypes.c_int
    process = ProcessObserver(os.getpid())
    output = io.StringIO()
    observer = ThreadObserver(process, output)
    handles = []
    started = time.monotonic()

    def snapshot():
        observer.next_snapshot = 0
        # The fixture targets this process through the network-helper filter.
        observer.snapshot({os.getpid(): 'network.mojom.NetworkService'}, False)
        row = json.loads(output.getvalue().splitlines()[-1])
        assert row['process_start'] == list(process.identities[os.getpid()])
        assert row['identity_kind'] == 'reusable_thread_handle'
        assert all(t['thread_handle'] for t in row['threads'])
        return row['threads']

    for index in range(16):
        ready, release = threading.Event(), threading.Event()
        name = f'RoomObserverFixture{index}'
        identity = {}

        def worker():
            info = (ctypes.c_uint64 * 3)()
            count = ctypes.c_uint32(6)
            identity['info_result'] = lib.thread_info(
                lib.pthread_mach_thread_np(lib.pthread_self()), 4,
                info, ctypes.byref(count))
            identity['handle'] = info[1]
            identity['named'] = lib.pthread_setname_np(name.encode()) == 0
            ready.set()
            release.wait(timeout=10)

        thread = threading.Thread(target=worker)
        thread.start()
        try:
            assert ready.wait(timeout=5), 'fixture thread did not start'
            assert identity['info_result'] == 0
            assert identity['named'], 'fixture thread naming failed'
            rows = snapshot()
            match = [t for t in rows if t['thread_handle'] == identity['handle']]
            assert len(match) == 1 and match[0]['name'] == name, (identity, rows)
            handles.append(identity['handle'])
        finally:
            release.set()
            thread.join(timeout=5)
        assert not thread.is_alive()
        # Python releases its join lock before the OS finishes thread teardown.
        deadline = time.monotonic() + 5
        while any(t['name'] == name for t in snapshot()):
            assert time.monotonic() < deadline, 'joined fixture thread retained'
            time.sleep(0.001)
    print(json.dumps({'threads_created_and_exited': len(handles),
                      'distinct_thread_handles': len(set(handles)),
                      'snapshots': observer.snapshots,
                      'query_seconds': observer.query_seconds,
                      'fixture_seconds': time.monotonic() - started}))


if __name__ == '__main__':
    main()
