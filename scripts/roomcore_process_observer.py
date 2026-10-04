"""Opt-in macOS descendant observer for the RoomCore shutdown diagnostic.

Uses the installed SDK's libproc.h / sys/proc_info.h ABI. PID plus start time
identifies a process across reparenting; a recycled PID is never the same child.
Full command lines are fetched in one targeted ps call for newly seen helpers.
"""
import ctypes
import errno
import subprocess


class BSDInfo(ctypes.Structure):
    _fields_ = ([(name, ctypes.c_uint32) for name in (
        'flags', 'status', 'xstatus', 'pid', 'ppid', 'uid', 'gid', 'ruid',
        'rgid', 'svuid', 'svgid', 'reserved')]
        + [('comm', ctypes.c_char * 16), ('name', ctypes.c_char * 32)]
        + [(name, ctypes.c_uint32) for name in ('nfiles', 'pgid', 'jobc', 'tdev', 'tpgid')]
        + [('nice', ctypes.c_int32), ('start_seconds', ctypes.c_uint64),
           ('start_microseconds', ctypes.c_uint64)])


class ProcessObserver:
    def __init__(self, root_pid, helper_name='Room Helper'):
        self.lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
        self.lib.proc_listchildpids.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        self.lib.proc_listchildpids.restype = ctypes.c_int
        self.lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                        ctypes.c_void_p, ctypes.c_int]
        self.lib.proc_pidinfo.restype = ctypes.c_int
        self.lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        self.lib.proc_pidpath.restype = ctypes.c_int
        self.root_pid = root_pid
        self.helper_name = helper_name
        info = self.info(root_pid)
        if info is None:
            raise ProcessLookupError(root_pid)
        self.identities = {root_pid: self.identity(info)}
        self.commands = {}
        self.command_queries = 0

    @staticmethod
    def identity(info):
        return info.start_seconds, info.start_microseconds

    @staticmethod
    def _gone_or_raise(operation, pid):
        error = ctypes.get_errno()
        if error in (errno.ESRCH, errno.ENOENT):
            return None
        raise OSError(error, f'{operation} failed for PID {pid}')

    def info(self, pid):
        result = BSDInfo()
        ctypes.set_errno(0)
        size = self.lib.proc_pidinfo(pid, 3, 0, ctypes.byref(result), ctypes.sizeof(result))
        if size == 0:
            return self._gone_or_raise('proc_pidinfo', pid)
        if size != ctypes.sizeof(result) or result.pid != pid:
            raise RuntimeError(f'proc_pidinfo ABI/identity mismatch: pid={pid}, size={size}')
        return result

    def children(self, pid):
        capacity = 64
        while capacity <= 65536:
            buffer = (ctypes.c_int * capacity)()
            ctypes.set_errno(0)
            count = self.lib.proc_listchildpids(pid, buffer, ctypes.sizeof(buffer))
            if count < 0:
                self._gone_or_raise('proc_listchildpids', pid)
                return []
            # Unlike proc_listpids, this wrapper returns a PID count, not bytes.
            if count < capacity:
                return [child for child in buffer[:count] if child > 0]
            capacity *= 2
        raise RuntimeError('child PID buffer limit exceeded; observation incomplete')

    def path(self, pid):
        buffer = ctypes.create_string_buffer(4096)
        ctypes.set_errno(0)
        if self.lib.proc_pidpath(pid, buffer, len(buffer)) <= 0:
            return self._gone_or_raise('proc_pidpath', pid)
        return buffer.value.decode('utf-8', errors='surrogateescape')

    def is_same_process(self, pid):
        info = self.info(pid)
        return info is not None and self.identity(info) == self.identities.get(pid)

    def snapshot(self):
        # Continue following known children after their parent exits/reparents.
        queue = [pid for pid in self.identities if self.is_same_process(pid)]
        visited = set()
        new_helpers = {}
        while queue:
            parent = queue.pop()
            if parent in visited or not self.is_same_process(parent):
                continue
            visited.add(parent)
            # A child may be visible between fork and exec. Recheck its path
            # until it becomes a helper, including after reparenting.
            if parent != self.root_pid and parent not in self.commands:
                path = self.path(parent)
                if path and self.helper_name in path:
                    new_helpers[parent] = path
            for pid in self.children(parent):
                info = self.info(pid)
                if info is None or info.ppid != parent:
                    continue  # exited or reparented during enumeration
                identity = self.identity(info)
                if self.identities.get(pid) != identity:
                    self.identities[pid] = identity
                    self.commands.pop(pid, None)
                queue.append(pid)
        if new_helpers:
            result = subprocess.run(['ps', '-p', ','.join(map(str, new_helpers)),
                                     '-o', 'pid=,command='], capture_output=True, text=True)
            self.command_queries += 1
            if result.returncode not in (0, 1):
                raise RuntimeError(f'targeted ps failed: {result.stderr}')
            commands = {}
            for row in result.stdout.splitlines():
                fields = row.strip().split(None, 1)
                if len(fields) == 2:
                    commands[int(fields[0])] = fields[1]
            for pid, path in new_helpers.items():
                if self.is_same_process(pid):
                    if pid not in commands:
                        raise RuntimeError(f'live helper command unavailable: {pid} ({path})')
                    self.commands[pid] = commands[pid]
        return self.remaining()

    def remaining(self):
        return {pid: command for pid, command in self.commands.items()
                if self.is_same_process(pid)}
