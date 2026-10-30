#!/usr/bin/env python3
# Run CMD with a wall limit, and stop the WHOLE process group at the limit.
# (inc-xthfj)
#
# `perl -e 'alarm 60; exec @ARGV' tools/headless.sh ...` ended only the bash
# process of headless.sh; the game binary under it was reparented to PID 1 and
# kept running. This tool starts CMD in its own session and, at the limit,
# sends SIGTERM to the group, waits 2 s, then sends SIGKILL (the method of
# tools/measure_route_cost.sh).
#
# Usage: tools/run_capped.py SECONDS CMD [ARG...]
# Exit: the child's exit code (killed by signal N -> 128+N); 124 at the limit;
# 128+N when this tool itself gets SIGTERM/SIGINT (N), after it stops the group;
# 2 on bad usage.
import os
import signal
import subprocess
import sys


def stop_group(child):
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    # The leader may have left while a member ignored SIGTERM, so always send KILL.
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        # inc-xthfj: Darwin gives EPERM when only zombies remain; SIGTERM just worked, so nothing live is left.
        pass
    child.wait()


def main(argv):
    try:
        limit = float(argv[1])
        if not limit > 0 or len(argv) < 3:
            raise ValueError
    except (IndexError, ValueError):
        print("usage: run_capped.py SECONDS CMD [ARG...]  (SECONDS > 0)", file=sys.stderr)
        return 2
    child = subprocess.Popen(argv[2:], start_new_session=True)

    def on_signal(signum, _frame):
        stop_group(child)
        sys.exit(128 + signum)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    try:
        rc = child.wait(timeout=limit)
    except subprocess.TimeoutExpired:
        stop_group(child)
        return 124
    return 128 - rc if rc < 0 else rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
