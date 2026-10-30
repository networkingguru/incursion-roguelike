#!/bin/bash
# gate: cheap
# gate-fast: static, python only, no build, under 1 s
# Does tools/gate_status.py print the right status-line segment?
#
# It writes fake status files and a fake timing log, runs the script, and asserts
# the exact text: nothing with no live gate or only a dead pid; the green/red
# time pair (ANSI bytes, and the --plain circles); --:-- for a null prediction;
# the bars and each arrow (up, down, flat, too few rows); the miss sign and value;
# the CPU letter at each cut point; the MEM letter; two live gates on one line.
# `--selftest` runs the check against a copy of the script with the color rule
# inverted (sed, in this check only) and requires red.
#
# fact: gate status files -- fixed JSON in a temp dir, INCURSION_GATE_STATUS_DIR
# fact: timing history -- fixed fake log, INCURSION_CHECK_TIMING_LOG
# fact: machine load and memory pressure -- INCURSION_LOAD_GUARD_FAKE_LOAD / _FAKE_PRESSURE
# fact: wall-clock -- elapsed is now minus started, so the check accepts 1 s of drift
# fact: live and dead pids -- the check's python process, and a child it spawns and reaps
# (no seed, no game, no build, no real log is read)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/tools/gate_status.py"

if [ "${1:-}" = "--selftest" ]; then
    if GATE_STATUS_SEGMENT_MUTATE=invert-color "$0" > /dev/null 2>&1; then
        echo "FAIL: selftest -- the check stayed green with the color rule inverted"; exit 1
    fi
    "$0" > /dev/null 2>&1 || { echo "FAIL: selftest -- the check is red unmutated"; exit 1; }
    echo "ok: the check goes red when the color rule is inverted"; exit 0
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/gatestatseg.XXXXXX")" || exit 2
trap 'rm -rf "$D"' EXIT
cp "$SRC" "$D/gate_status.py"
if [ "${GATE_STATUS_SEGMENT_MUTATE:-}" = "invert-color" ]; then
    sed -i.bak 's/over = elapsed >= pred/over = elapsed < pred/' "$D/gate_status.py"
    cmp -s "$D/gate_status.py.bak" "$D/gate_status.py" \
        && { echo "FAIL: the mutation matched nothing"; exit 1; }
fi

D="$D" python3 -I - <<'PYEOF'
import json, os, subprocess, sys, time

D = os.environ["D"]
SCRIPT = os.path.join(D, "gate_status.py")
G, R, Z = "\033[32m", "\033[31m", "\033[0m"
fails = 0


def fail(msg):
    global fails
    fails += 1
    print("FAIL: " + msg)


dead = subprocess.Popen(["true"])
dead.wait()
DEAD, LIVE = dead.pid, os.getpid()
LOG = os.path.join(D, "timing.tsv")


def rows(kind, gtype, vals, exit_code=0):
    return ["2026-01-01T00:00:00Z\t%s\t%s#%d\t%s\t%s\t1\t8\t1\t1\tb" % (kind, gtype, i + 100, exit_code, v)
            for i, v in enumerate(vals)]


lines = ["utc_time\trunner\tcheck\texit\telapsed_s\tload1\tncpu\tmem_pressure\tgates_running\tbranch"]
lines += rows("total", "up", [100] * 5 + [200] * 5)
lines += rows("total", "down", [200] * 5 + [100] * 5)
lines += rows("total", "flat", [100] * 10)
lines += rows("total", "few", [10, 20, 30])
lines += rows("total", "bad", [999], exit_code=1) + rows("total", "few", [999], exit_code=1)
# miss: newest total with a predict row is m#2 (108 vs 100); m#3 has none; m#1 is older.
lines += ["t\tpredict\tm#1\t0\t100\t1\t8\t1\t1\tb", "t\ttotal\tm#1\t0\t97\t1\t8\t1\t1\tb",
          "t\tpredict\tm#2\t0\t100\t1\t8\t1\t1\tb", "t\ttotal\tm#2\t0\t108\t1\t8\t1\t1\tb",
          "t\ttotal\tm#3\t0\t50\t1\t8\t1\t1\tb",
          "t\tpredict\tn#1\t0\t200\t1\t8\t1\t1\tb", "t\ttotal\tn#1\t0\t194\t1\t8\t1\t1\tb"]
open(LOG, "w").write("\n".join(lines) + "\n")


def status(pid, gtype, elapsed, pred, stage="build", i=2, n=5, branch="br"):
    return {"pid": pid, "type": gtype, "branch": branch, "checks": 7, "stage": stage,
            "stage_index": i, "stage_count": n, "started": int(time.time()) - elapsed,
            "stage_started": int(time.time()), "predicted_s": pred, "predicted_end": None}


case_no = [0]


def run(files, plain=False, load="1", pressure="1"):
    case_no[0] += 1
    sd = os.path.join(D, "s%d" % case_no[0])
    os.makedirs(sd)
    for st in files:
        json.dump(st, open(os.path.join(sd, "%d.json" % st["pid"]), "w"))
    env = dict(os.environ, INCURSION_GATE_STATUS_DIR=sd, INCURSION_CHECK_TIMING_LOG=LOG,
               INCURSION_LOAD_GUARD_FAKE_LOAD=load, INCURSION_LOAD_GUARD_FAKE_PRESSURE=pressure)
    p = subprocess.run([sys.executable, "-I", SCRIPT] + (["--plain"] if plain else []),
                       env=env, capture_output=True, text=True, timeout=10)
    if p.returncode != 0:
        fail("exit %d" % p.returncode)
    return p.stdout.rstrip("\n"), sd


def expect(name, got, *wants):
    if got not in wants:
        fail("%s: got %r, wanted %r" % (name, got, wants[0]))


def with_elapsed(template, elapsed_options):
    """The elapsed text may tick over by 1 s while the script runs."""
    return [template % e for e in elapsed_options]


out, _ = run([])
expect("no files", out, "")
out, sd = run([status(DEAD, "up", 10, 100)])
expect("dead pid only", out, "")
if not os.path.exists(os.path.join(sd, "%d.json" % DEAD)):
    fail("a dead pid's status file was deleted")

# Under and over, colored and plain; trend of "up" is bars + up arrow; no miss for "up".
UPB = "▁" * 5 + "█" * 5 + "↑"
out, _ = run([status(LIVE, "up", 125, 300)])
expect("under", out, *with_elapsed("up br build 2/5 " + G + "%s | 05:00" + Z + " " + UPB + " · CPU L MEM L",
                                   ["02:05", "02:06"]))
out, _ = run([status(LIVE, "up", 125, 60)])
expect("over", out, *with_elapsed("up br build 2/5 " + R + "%s | 01:00" + Z + " " + UPB + " · CPU L MEM L",
                                  ["02:05", "02:06"]))
out, _ = run([status(LIVE, "up", 125, 300)], plain=True)
expect("plain under", out, *with_elapsed("up br build 2/5 \U0001f7e2 %s | 05:00 " + UPB + " · CPU L MEM L",
                                         ["02:05", "02:06"]))
out, _ = run([status(LIVE, "up", 125, 60)], plain=True)
expect("plain over", out, *with_elapsed("up br build 2/5 \U0001f534 %s | 01:00 " + UPB + " · CPU L MEM L",
                                        ["02:05", "02:06"]))
if "\033" in out:
    fail("--plain printed an ANSI escape")
out, _ = run([status(LIVE, "up", 125, None)])
expect("null prediction", out, *with_elapsed("up br build 2/5 %s | --:-- " + UPB + " · CPU L MEM L",
                                             ["02:05", "02:06"]))
out, _ = run([status(LIVE, "up", 6000 + 65, 9000)])
if "101:" not in out:
    fail("minutes above 99 not shown: %r" % out)

# Arrows, bars, and no-trend.
def tail(gtype):
    out, _ = run([status(LIVE, gtype, 10, None)])
    return out.split("--:--", 1)[1].rsplit("CPU", 1)[0].strip().rstrip("\u00b7").strip()


expect("down", tail("down"), "█" * 5 + "▁" * 5 + "↓")
expect("flat", tail("flat"), "▄" * 10 + "→")
expect("few", tail("few"), "▁▅█·")
expect("no rows", tail("zzz"), "")  # nothing between the pair and CPU

# Miss: +8% from the newest total that has a predict row; -3% for another type.
expect("miss +8%", tail("m").split(" ", 1)[-1][-8:], "miss +8%")
expect("miss -3%", tail("n").split(" ", 1)[-1][-8:], "miss -3%")
if "miss" in tail("up"):
    fail("miss printed for a type with no predict row")

# CPU letter cut points.
for load, want in (("4.9", "L"), ("5", "M"), ("7.9", "M"), ("8", "H"), ("9.9", "H"), ("10", "X")):
    out, _ = run([status(LIVE, "zzz", 10, None)], load=load)
    expect("cpu " + load, out.split("CPU ")[1].split(" ")[0], want)
for pr, want in (("1", "L"), ("2", "H"), ("4", "X"), ("3", "?")):
    out, _ = run([status(LIVE, "zzz", 10, None)], pressure=pr)
    expect("mem " + pr, out.rsplit(" ", 1)[-1], want)

# Two live gates, one line, oldest first; the dead one is left out.
other = subprocess.Popen(["sleep", "30"])
try:
    out, _ = run([status(LIVE, "up", 200, 300, branch="one"), status(other.pid, "flat", 100, 50, branch="two"),
                  status(DEAD, "down", 50, 50)])
finally:
    other.kill(); other.wait()
if out.count(" · CPU") != 1 or out.count("\n") or out.index("up one") > out.index("flat two") \
        or "down" in out.replace("↓", ""):
    fail("two gates: %r" % out)
if out.count(G) != 1 or out.count(R) != 1:
    fail("two gates: want one green and one red pair: %r" % out)

print("gate_status segment: %s" % ("FAIL" if fails else "ok"))
sys.exit(1 if fails else 0)
PYEOF
