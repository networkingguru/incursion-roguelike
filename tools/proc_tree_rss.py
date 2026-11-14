#!/usr/bin/env python3
"""Sum the resident memory of a process and its descendants (bead inc-ilor0).

Usage: python3 -I tools/proc_tree_rss.py <root-pid>
Prints one line: <MB> <pid> <pid> ...   (MB = int(bytes / 1048576); root first)
Exit 0 on success. Exit 1, with a reason on stderr and nothing on stdout, when
libproc cannot be loaded or the root pid cannot be read.

Why libproc and not ps: /bin/ps is setuid root, and a macOS sandbox refuses to
exec a setuid binary, so `ps` fails inside every implementer sandbox.
proc_pid_rusage on the caller's own descendants works inside one.
"""
import ctypes
import sys


class RusageV0(ctypes.Structure):
    _fields_ = [
        ("uuid", ctypes.c_uint8 * 16),
        ("user_time", ctypes.c_uint64),
        ("system_time", ctypes.c_uint64),
        ("pkg_idle_wkups", ctypes.c_uint64),
        ("interrupt_wkups", ctypes.c_uint64),
        ("pageins", ctypes.c_uint64),
        ("wired_size", ctypes.c_uint64),
        ("resident_size", ctypes.c_uint64),
        ("phys_footprint", ctypes.c_uint64),
        ("proc_start_abstime", ctypes.c_uint64),
        ("proc_exit_abstime", ctypes.c_uint64),
    ]


def main():
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print("usage: proc_tree_rss.py <root-pid>", file=sys.stderr)
        return 2
    root = int(sys.argv[1])
    try:
        lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    except OSError as e:
        print("cannot load libproc: %s" % e, file=sys.stderr)
        return 1

    def rss(pid):
        info = RusageV0()
        # RUSAGE_INFO_V0 is flavor 0.
        if lib.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
            return None
        return info.resident_size

    def children(pid):
        buf = (ctypes.c_int * 1024)()
        n = lib.proc_listchildpids(pid, buf, ctypes.sizeof(buf))
        # Verified: returns the number of pids stored; <= 0 means none.
        return [buf[i] for i in range(max(0, min(n, len(buf))))]

    total = rss(root)
    if total is None:
        print("cannot read memory of pid %d" % root, file=sys.stderr)
        return 1
    pids = [root]
    queue = [root]
    seen = {root}
    while queue:
        for c in children(queue.pop()):
            if c in seen or c <= 0:
                continue
            seen.add(c)
            r = rss(c)
            if r is None:   # exited between the list and the read
                continue
            total += r
            pids.append(c)
            queue.append(c)
    print(int(total / 1048576), *pids)
    return 0


sys.exit(main())
