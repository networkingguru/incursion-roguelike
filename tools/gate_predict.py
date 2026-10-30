#!/usr/bin/env python3
"""Predict the landing gate's wall time from per-check history (inc-b0ziu.6).

Reads logs/check-timing.tsv (path resolved as tools/timing_log.sh does:
INCURSION_CHECK_TIMING_LOG, else <git common dir's parent>/logs/check-timing.tsv).
Columns: utc_time runner check exit elapsed_s load1 ncpu mem_pressure
gates_running branch. Only runner "gate" rows count.

ROW NAMES. A check row is named by the check id exactly as nightly_verify.sh
logs it (run_one: "tools/<name>.sh [args]"). Overhead stages are rows of runner
"gate" named:
    stage:build:<n>     the n-th build, counting from 1, in BUILDS order
    stage:<step>        a background step, <step> = its command (STEPS first field)

WEIGHTING. Expected time of a name = weighted mean of its last 20 rows (any
exit code; rows whose elapsed_s is not an integer are skipped). The newest row
has weight 1, each older row 0.87x the next newer (about 0.5 at 5 runs back).

FALLBACK. A check without history gets the median expected time of the checks
in this request that share its tier and have history; else the median over all
tiers in the request; else 0. The prediction is partial only when a check has no
median to fall back on (no check in the request has history), or when a build or
step has no history (it counts as 0).

INPUT (stdin, TSV): kind<TAB>name<TAB>tier<TAB>serial
    kind = check|build|step, tier = cheap|smoke|live (blank for build/step),
    serial = 0|1. List order matters: it is the gate's start order.

PHASES (mirror nightly_verify.sh):
  compare: cheap par, cheap serial, builds (sum), then max(longest step,
           smoke par + live par), smoke serial, live serial.
  record:  builds (sum), cheap par, cheap serial, smoke par, smoke serial,
           live par, live serial, steps one after another (sum).
  A parallel phase is greedy list scheduling onto --jobs slots, in input order
  (the gate starts checks in list order as slots free); time = busiest slot.
  A serial phase is the sum.
--no-builds drops builds and steps; --no-live drops smoke and live checks.

OUTPUT: "predicted_s=<int> checks=<n> partial=<0|1>", or JSON with --json.
GATE_PREDICT_MUTATE=sum-parallel makes a parallel phase a sum; only
tools/check_gate_predict.sh sets it, to prove the check can fail.
"""
import argparse, heapq, json, os, subprocess, sys

DECAY, KEEP = 0.87, 20


def log_path():
    p = os.environ.get("INCURSION_CHECK_TIMING_LOG")
    if p:
        return p
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True,
                                text=True, check=True).stdout.strip()
        base = os.path.dirname(os.path.abspath(common))
    except (subprocess.CalledProcessError, OSError):
        base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, "logs", "check-timing.tsv")


def load_history(path):
    hist = {}
    try:
        with open(path) as f:
            for line in f:
                c = line.rstrip("\n").split("\t")
                if len(c) < 5 or c[1] != "gate" or not c[4].isdigit():
                    continue
                hist.setdefault(c[2], []).append(int(c[4]))
    except OSError:
        pass
    return hist


def expected(rows):
    rows = rows[-KEEP:][::-1]  # newest first
    w = [DECAY ** i for i in range(len(rows))]
    return sum(r * x for r, x in zip(rows, w)) / sum(w)


def median(v):
    v = sorted(v)
    n = len(v)
    return 0.0 if n == 0 else (v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2)


def par(times, jobs):
    if os.environ.get("GATE_PREDICT_MUTATE") == "sum-parallel":
        return float(sum(times))
    slots = [0.0] * max(jobs, 1)
    heapq.heapify(slots)
    for t in times:
        heapq.heappush(slots, heapq.heappop(slots) + t)
    return max(slots)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["compare", "record"], required=True)
    ap.add_argument("--jobs", type=int, required=True)
    ap.add_argument("--no-builds", action="store_true")
    ap.add_argument("--no-live", action="store_true")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    items = []
    for line in sys.stdin:
        c = line.rstrip("\n").split("\t")
        if len(c) < 2 or not c[0]:
            continue
        c += [""] * (4 - len(c))
        items.append((c[0], c[1], c[2], c[3] == "1"))
    if a.no_builds:
        items = [i for i in items if i[0] == "check"]
    if a.no_live:
        items = [i for i in items if not (i[0] == "check" and i[2] in ("smoke", "live"))]

    hist = load_history(log_path())
    t = {n: expected(hist[n]) for k, n, _, _ in items if n in hist}
    by_tier, allv = {}, []
    for k, n, tier, _ in items:
        if k == "check" and n in t:
            by_tier.setdefault(tier, []).append(t[n])
            allv.append(t[n])
    fallback = []
    for k, n, tier, _ in items:
        if n in t:
            continue
        fallback.append(n)
        t[n] = median(by_tier.get(tier) or allv) if k == "check" else 0.0

    def tier_items(tier, serial):
        return [t[n] for k, n, ti, s in items if k == "check" and ti == tier and s == serial]

    builds = sum(t[n] for k, n, _, _ in items if k == "build")
    steps = [t[n] for k, n, _, _ in items if k == "step"]
    ph = {}
    ph["cheap_par"] = par(tier_items("cheap", False), a.jobs)
    ph["cheap_serial"] = sum(tier_items("cheap", True))
    ph["builds"] = builds
    sp = par(tier_items("smoke", False), a.jobs)
    lp = par(tier_items("live", False), a.jobs)
    if a.mode == "compare":
        ph["steps_beside_smoke_live"] = max(max(steps, default=0.0), sp + lp)
        ph["smoke_serial"] = sum(tier_items("smoke", True))
        ph["live_serial"] = sum(tier_items("live", True))
    else:
        ph["smoke_par"], ph["smoke_serial"] = sp, sum(tier_items("smoke", True))
        ph["live_par"], ph["live_serial"] = lp, sum(tier_items("live", True))
        ph["steps"] = sum(steps)
    total = int(sum(ph.values()) + 0.5)
    nchk = sum(1 for i in items if i[0] == "check")
    partial = 1 if fallback and any(
        k != "check" or not (by_tier.get(tier) or allv) for k, n, tier, _ in items if n in fallback) else 0
    if a.json:
        print(json.dumps({"predicted_s": total, "checks": nchk, "partial": partial,
                          "phases": {k: int(v + 0.5) for k, v in ph.items()},
                          "fallback": fallback}))
    else:
        print("predicted_s=%d checks=%d partial=%d" % (total, nchk, partial))


if __name__ == "__main__":
    main()
