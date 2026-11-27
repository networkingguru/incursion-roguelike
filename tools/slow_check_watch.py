#!/usr/bin/env python3
"""Sidecar for a gate check: alert once when it runs 5x past its expected time.

Usage: slow_check_watch.py <check id> <check pid>   (nightly_verify.sh run_check starts it)
Expected time comes from tools/gate_predict.py (expected(), load_history(),
log_path()). No history for the id: exit 0, write nothing.
Threshold = max(5 * expected, floor); floor 60 s, INCURSION_SLOW_WATCH_FLOOR
overrides it (tests only). On a live pid past the threshold: sample the pid and
its descendants into logs/slow-sample-<id>-<utc>.txt beside the alert file and
append ONE `ALERT slow-check` line to INCURSION_FAST_ALERT_FILE (else
<root>/logs/fast-alert.log). It NEVER signals the check and swallows every
error: a diagnostic, never a verdict (inc-omhv1).
SLOW_WATCH_MUTATE=invert-threshold inverts the comparison; only
tools/check_slow_check_watch.sh sets it, to prove the check can fail.
"""
import os, re, signal, subprocess, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except OSError:
        return True


def out(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()


def tree(pid):
    pids = [pid]
    for c in out("pgrep", "-P", str(pid)).split():
        pids += tree(int(c))
    return pids


def run(name, pid):
    import gate_predict
    hist = gate_predict.load_history(gate_predict.log_path())
    if name not in hist:
        return
    exp = gate_predict.expected(hist[name])
    floor = float(os.environ.get("INCURSION_SLOW_WATCH_FLOOR", "60"))
    limit = max(5 * exp, floor)
    t0 = time.time()
    mutate = os.environ.get("SLOW_WATCH_MUTATE") == "invert-threshold"
    while alive(pid):
        elapsed = time.time() - t0
        if (elapsed >= limit) != mutate:  # mutation: alert only before the limit
            break
        time.sleep(0.25)
    else:
        return
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    alert = os.environ.get("INCURSION_FAST_ALERT_FILE") or os.path.join(root, "logs", "fast-alert.log")
    d = os.path.dirname(alert)
    os.makedirs(d, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", name)[:80]
    path = os.path.join(d, "slow-sample-%s-%s.txt" % (safe, time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())))
    signal.signal(signal.SIGTERM, signal.SIG_IGN)  # finish the alert even if the check just ended
    jobs = []
    for p in tree(pid)[:8]:
        tmp = "%s.%d.part" % (path, p)
        jobs.append((tmp, subprocess.Popen(["sample", str(p), "1", "-file", tmp],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))
    with open(path, "w") as f:
        for tmp, j in jobs:
            try:
                j.wait(timeout=60)
            except subprocess.TimeoutExpired:
                j.kill()
            if os.path.exists(tmp):
                with open(tmp) as g:
                    f.write(g.read())
                os.remove(tmp)
    load = os.environ.get("INCURSION_LOAD_GUARD_FAKE_LOAD") or (out("sysctl", "-n", "vm.loadavg").split() or ["", ""])[1]
    gates = len(out("pgrep", "-f", "[n]ightly_verify.sh").split())
    branch = out("git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD")
    with open(alert, "a") as f:
        f.write("ALERT slow-check %s: elapsed %ds expected %ds (5x) branch %s load %s gates %d sample %s\n"
                % (name, time.time() - t0, exp, branch, load, gates, path))


if __name__ == "__main__":
    try:
        if len(sys.argv) == 3:
            run(sys.argv[1], int(sys.argv[2]))
    except BaseException:
        pass
    sys.exit(0)
