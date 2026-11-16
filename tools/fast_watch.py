#!/usr/bin/env python3
"""Run a fast check and report a stall or heavy CPU use, with no wall limit (inc-rst61).

Usage: tools/fast_watch.py --name NAME --alert-file FILE (--watched|--unwatched)
                           [--debug] -- CMD [ARG...]
Why: a wall-clock limit made machine load decide failures. This tool watches
PROGRESS instead: some process of the check gained CPU, or one started or ended.
Every 0.25 s it reads the CPU of the process tree (libproc, as tools/proc_tree_rss.py).
Limits, in seconds: INCURSION_FAST_STALL (no progress, default 5) and
INCURSION_FAST_CPU (cumulative CPU of every process ever seen, default 50).
--watched: append `ALERT NAME pgid P: ...` once per kind; the check keeps running.
--unwatched: limits are 5x; at a limit append `HANG NAME pgid P: ...`, stop the group.
When the root exits, the rest of its process group is stopped (tools/run_capped.py).
Exit: the child's status (signal N -> 128+N); 125 HANG; 128+N on SIGTERM/SIGINT to
this tool; 2 on bad usage, a bad limit, or when libproc cannot measure.
"""
import argparse
import ctypes
import os
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_capped  # noqa: E402

INTERVAL = 0.25


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


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


class Meter:
    def __init__(self):
        self.lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        sysl = ctypes.CDLL("/usr/lib/libSystem.dylib")
        tb = Timebase()
        if sysl.mach_timebase_info(ctypes.byref(tb)) != 0 or tb.denom == 0:
            raise OSError("mach_timebase_info failed")
        # rusage times are mach absolute time units; convert to seconds.
        self.scale = tb.numer / tb.denom / 1e9

    def cpu(self, pid):
        info = RusageV0()
        if self.lib.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
            return None
        return (info.user_time + info.system_time) * self.scale

    def children(self, pid):
        buf = (ctypes.c_int * 1024)()
        n = self.lib.proc_listchildpids(pid, buf, ctypes.sizeof(buf))
        return [buf[i] for i in range(max(0, min(n, len(buf))))]

    def tree(self, root):
        """{pid: cpu seconds} for root and its live descendants."""
        out = {}
        c = self.cpu(root)
        if c is None:
            return out
        out[root] = c
        queue = [root]
        while queue:
            for ch in self.children(queue.pop()):
                if ch <= 0 or ch in out:
                    continue
                v = self.cpu(ch)
                if v is None:
                    continue
                out[ch] = v
                queue.append(ch)
        return out


def read_limit(name, default):
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        v = float(raw)
        if not v > 0 or v == float("inf"):
            raise ValueError
    except ValueError:
        raise SystemExit("fast_watch: bad %s=%r (need a number > 0)" % (name, raw))
    return v


def main(argv):
    ap = argparse.ArgumentParser(prog="fast_watch.py", add_help=False)
    ap.add_argument("--name", required=True)
    ap.add_argument("--alert-file", required=True)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--watched", action="store_true")
    mode.add_argument("--unwatched", action="store_true")
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    try:
        a = ap.parse_args(argv[1:])
    except SystemExit:
        return 2
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    if not cmd:
        print("usage: fast_watch.py --name N --alert-file F (--watched|--unwatched) -- CMD...",
              file=sys.stderr)
        return 2
    try:
        stall = read_limit("INCURSION_FAST_STALL", 5.0)
        cpu_lim = read_limit("INCURSION_FAST_CPU", 50.0)
    except SystemExit as e:
        print(e, file=sys.stderr)
        return 2
    if a.unwatched:
        stall *= 5
        cpu_lim *= 5
    try:
        meter = Meter()
    except OSError as e:
        print("fast_watch: cannot load libproc: %s" % e, file=sys.stderr)
        return 2

    child = subprocess.Popen(cmd, start_new_session=True)
    pgid = child.pid

    def on_signal(signum, _frame):
        run_capped.stop_group(child)
        sys.exit(128 + signum)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    warned = [False]

    def emit(line):
        try:
            with open(a.alert_file, "a") as f:
                f.write(line + "\n")
        except OSError as e:
            if not warned[0]:
                warned[0] = True
                print("fast_watch: cannot append to %s: %s" % (a.alert_file, e), file=sys.stderr)

    last = meter.tree(child.pid)
    if child.pid not in last and child.poll() is None:
        run_capped.stop_group(child)
        print("fast_watch: cannot read pid %d" % child.pid, file=sys.stderr)
        return 2
    total = dict(last)          # last CPU value of every pid ever seen
    prev_live = set(last)
    prev_cpu = dict(last)
    progress_at = time.monotonic()
    stall_sent = cpu_sent = False

    def cum():
        return sum(total.values())

    while child.poll() is None:
        time.sleep(INTERVAL)
        now = time.monotonic()
        cur = meter.tree(child.pid)
        moved = set(cur) != prev_live
        for pid, v in cur.items():
            total[pid] = max(total.get(pid, 0.0), v)
            if v > prev_cpu.get(pid, -1.0):
                moved = True
        prev_live = set(cur)
        prev_cpu = cur
        if moved:
            progress_at = now
        idle = now - progress_at
        used = cum()
        reason = None
        if idle >= stall:
            reason = "no progress for %.1f s" % idle
            if a.watched and not stall_sent:
                stall_sent = True
                emit("ALERT %s pgid %d: %s" % (a.name, pgid, reason))
        if used >= cpu_lim:
            reason = reason if idle >= stall else "%.1f s of CPU" % used
            if a.watched and not cpu_sent:
                cpu_sent = True
                emit("ALERT %s pgid %d: %.1f s of CPU" % (a.name, pgid, used))
        if a.unwatched and reason is not None and child.poll() is None:
            emit("HANG %s pgid %d: %s" % (a.name, pgid, reason))
            run_capped.stop_group(child)
            return 125

    rc = child.returncode
    run_capped.stop_group(child)      # an orphaned member of the group
    if a.debug:
        print("fast_watch: cumulative CPU %.3f s" % cum(), file=sys.stderr)
    return 128 - rc if rc < 0 else rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
