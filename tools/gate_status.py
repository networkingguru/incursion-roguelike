#!/usr/bin/env python3
"""One status-line segment for the running gate(s), for ccstatusline (inc-b0ziu.6).

Prints nothing when no live gate runs. Never raises, always exits 0.
  tools/gate_status.py [--plain]     --plain: no ANSI, a green/red circle instead.
Reads logs/gate-status/<pid>.json (same directory rule as tools/nightly_verify.sh
gate_status_dir) and logs/check-timing.tsv (INCURSION_CHECK_TIMING_LOG overrides).
"""
import json
import math
import os
import subprocess
import sys
import time

# CPU letter: raw 1-minute load. Below LOAD_M is L, below LOAD_H is M, below LOAD_X is H.
LOAD_M, LOAD_H, LOAD_X = 5.0, 8.0, 10.0
BARS = "▁▂▃▄▅▆▇█"
TREND_N = 10
HALF = 5
ARROW_PCT = 5.0
GREEN, RED, RESET = "\033[32m", "\033[31m", "\033[0m"


def common_parent():
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        out = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=here,
                             capture_output=True, text=True, timeout=1).stdout.strip()
        if out:
            if not os.path.isabs(out):
                out = os.path.join(here, out)
            return os.path.dirname(os.path.normpath(out))
    except Exception:
        pass
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def timing_log_path():
    p = os.environ.get("INCURSION_CHECK_TIMING_LOG")
    return p if p else os.path.join(common_parent(), "logs", "check-timing.tsv")


def status_dir():
    d = os.environ.get("INCURSION_GATE_STATUS_DIR")
    if d:
        return d
    if os.environ.get("INCURSION_CHECK_TIMING_LOG"):
        return os.path.join(os.path.dirname(os.environ["INCURSION_CHECK_TIMING_LOG"]), "gate-status")
    return os.path.join(common_parent(), "logs", "gate-status")


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def mmss(s):
    s = int(s)
    return "%02d:%02d" % (s // 60, s % 60)


def rnd(x):
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


def read_rows():
    rows = []
    try:
        with open(timing_log_path()) as f:
            for line in f:
                c = line.rstrip("\n").split("\t")
                if len(c) >= 5 and c[1] in ("predict", "total"):
                    rows.append(c)
    except Exception:
        pass
    return rows


def trend(rows, gtype):
    """Bars and arrow from the last TREND_N exit-0 total rows of this type."""
    vals = []
    for c in rows:
        if c[1] == "total" and c[2].split("#")[0] == gtype and c[3] == "0":
            try:
                vals.append(float(c[4]))
            except ValueError:
                pass
    vals = vals[-TREND_N:]
    if not vals:
        return ""
    lo, hi = min(vals), max(vals)
    if hi == lo:
        bars = BARS[3] * len(vals)
    else:
        bars = "".join(BARS[min(7, int((v - lo) / (hi - lo) * 8))] for v in vals)
    arrow = "·"
    if len(vals) >= TREND_N:
        new = sum(vals[-HALF:]) / HALF
        old = sum(vals[-2 * HALF:-HALF]) / HALF
        if new > old * (1 + ARROW_PCT / 100):
            arrow = "↑"
        elif new < old * (1 - ARROW_PCT / 100):
            arrow = "↓"
        else:
            arrow = "→"
    return bars + arrow


def miss(rows, gtype):
    predicted = {}
    for c in rows:
        if c[1] == "predict" and c[2].split("#")[0] == gtype:
            try:
                predicted[c[2]] = float(c[4])
            except ValueError:
                pass
    for c in reversed(rows):
        if c[1] == "total" and c[3] == "0" and c[2] in predicted and predicted[c[2]] > 0:
            try:
                return "miss %+d%%" % rnd((float(c[4]) - predicted[c[2]]) / predicted[c[2]] * 100)
            except ValueError:
                pass
    return ""


def gate_text(st, rows, now, plain):
    elapsed = max(0, now - st["started"])
    pred = st.get("predicted_s")
    pair = "%s | %s" % (mmss(elapsed), "--:--" if pred is None else mmss(pred))
    if pred is not None:
        over = elapsed >= pred
        if plain:
            pair = ("\U0001f534 " if over else "\U0001f7e2 ") + pair
        else:
            pair = (RED if over else GREEN) + pair + RESET
    gtype = st["type"]
    parts = [gtype, st.get("branch", ""), st.get("stage", ""),
             "%s/%s" % (st.get("stage_index", 0), st.get("stage_count", 0)),
             pair, trend(rows, gtype), miss(rows, gtype)]
    return " ".join(p for p in parts if p)


def cpu_letter():
    try:
        raw = os.environ.get("INCURSION_LOAD_GUARD_FAKE_LOAD")
        if raw is None:
            raw = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                                 text=True, timeout=1).stdout.split()[1]
        load = float(raw)
    except Exception:
        return "?"
    if load < LOAD_M:
        return "L"
    if load < LOAD_H:
        return "M"
    if load < LOAD_X:
        return "H"
    return "X"


def mem_letter():
    try:
        raw = os.environ.get("INCURSION_LOAD_GUARD_FAKE_PRESSURE")
        if raw is None:
            raw = subprocess.run(["sysctl", "-n", "kern.memorystatus_vm_pressure_level"],
                                 capture_output=True, text=True, timeout=1).stdout
        return {1: "L", 2: "H", 4: "X"}.get(int(raw.strip()), "?")
    except Exception:
        return "?"


def main():
    plain = "--plain" in sys.argv[1:]
    d = status_dir()
    live = []
    for name in sorted(os.listdir(d)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, name)) as f:
                st = json.load(f)
            if alive(int(st["pid"])):
                live.append(st)
        except Exception:
            continue
    if not live:
        return
    live.sort(key=lambda s: s["started"])
    rows = read_rows()
    now = int(time.time())
    segs = [gate_text(st, rows, now, plain) for st in live]
    segs.append("CPU %s MEM %s" % (cpu_letter(), mem_letter()))
    print(" · ".join(segs))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
