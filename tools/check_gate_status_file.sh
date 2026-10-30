#!/bin/bash
# gate: cheap
# Does the gate keep an honest status file while it runs, and clean up after it?
#
# It runs a copy of tools/nightly_verify.sh against a fake check directory (one
# cheap check that sleeps) and asserts, for a pass, a fail and a SIGINT:
#   - logs/gate-status/<pid>.json exists while the gate runs, with every key;
#   - the file is gone after the gate exits;
#   - a `total` row for the run is in the timing log, with the gate's exit code.
# `--selftest` re-runs the check with the gate's EXIT trap cut out of the copy
# (GATE_STATUS_MUTATE=no-cleanup, read only by this script) and requires red.
#
# fact: timing log and status dir -- private temp dir via INCURSION_CHECK_TIMING_LOG
# fact: the checks the gate runs -- one fake cheap check written by this script
# fact: gate order and slot count -- INCURSION_GATE_JOBS=2, --checks-only
# fact: wall-clock -- polls with a 15 s limit; the fake check sleeps 2 s or 30 s
# (no seed, no game, no build, no real check or real log is touched)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--selftest" ]; then
    if GATE_STATUS_MUTATE=no-cleanup "$0" > /dev/null 2>&1; then
        echo "FAIL: selftest -- the check stayed green with the cleanup trap removed"; exit 1
    fi
    "$0" > /dev/null 2>&1 || { echo "FAIL: selftest -- the check is red unmutated"; exit 1; }
    echo "ok: the check goes red when the gate's cleanup trap is removed"; exit 0
fi

D="$(mktemp -d "${TMPDIR:-/tmp}/gatestatus.XXXXXX")" || exit 2
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/root/tools" "$D/checks"
cp "$ROOT/tools/nightly_verify.sh" "$D/root/tools/nightly_verify.sh"
cp "$ROOT/tools/timing_log.sh" "$ROOT/tools/gate_predict.py" "$D/root/tools/"
if [ "${GATE_STATUS_MUTATE:-}" = "no-cleanup" ]; then
    sed -i.bak '/^    trap gate_on_exit EXIT$/d' "$D/root/tools/nightly_verify.sh"
    cmp -s "$D/root/tools/nightly_verify.sh.bak" "$D/root/tools/nightly_verify.sh" \
        && { echo "FAIL: the mutation matched nothing"; exit 1; }
fi

D="$D" python3 -I - <<'PYEOF'
import json, os, signal, subprocess, sys, time

D = os.environ["D"]
KEYS = {"pid", "type", "branch", "checks", "stage", "stage_index", "stage_count",
        "started", "stage_started", "predicted_s", "predicted_end"}
fails = 0


def fail(msg):
    global fails
    fails += 1
    print("FAIL: " + msg)


def run_case(name, check_body, sig):
    global fails
    cdir = os.path.join(D, "checks-" + name)
    os.makedirs(cdir)
    with open(os.path.join(cdir, "check_fake.sh"), "w") as f:
        f.write("#!/bin/sh\n# gate: cheap\n" + check_body)
    os.chmod(os.path.join(cdir, "check_fake.sh"), 0o755)
    sdir = os.path.join(D, "status-" + name)
    log = os.path.join(D, "timing-" + name + ".tsv")
    env = dict(os.environ, INCURSION_GATE_STATUS_DIR=sdir, INCURSION_CHECK_TIMING_LOG=log,
               NIGHTLY_CHECK_DIR=cdir, NIGHTLY_VERIFY_STATE=os.path.join(D, name + "-base.txt"),
               INCURSION_GATE_JOBS="2")
    p = subprocess.Popen([os.path.join(D, "root/tools/nightly_verify.sh"), "--checks-only"],
                         env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         # A gate run in the background inherits SIGINT ignored; restore it.
                         preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
    path = os.path.join(sdir, "%d.json" % p.pid)
    end = time.time() + 15
    while time.time() < end and not os.path.exists(path):
        time.sleep(0.1)
    if not os.path.exists(path):
        fail(name + ": no status file while the gate runs")
    else:
        try:
            st = json.load(open(path))
            if set(st) != KEYS:
                fail(name + ": status keys differ: " + ",".join(sorted(set(st) ^ KEYS)))
            elif st["pid"] != p.pid or st["stage_count"] < 1 or st["type"] != "compare-checks-only":
                fail(name + ": status values wrong: %r" % st)
        except ValueError as e:
            fail(name + ": status file is not JSON: %s" % e)
    if sig:
        time.sleep(1.0)  # let the gate arm its job trap and start the check
        p.send_signal(sig)
    try:
        rc = p.wait(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
        fail(name + ": the gate did not end")
        return
    want = {"pass": 0, "fail": 1, "sigint": 130}[name]
    if rc != want:
        fail("%s: exit %s, wanted %s" % (name, rc, want))
    if os.path.exists(path):
        fail(name + ": status file still there after the gate ended")
    rows = [l.split("\t") for l in open(log)] if os.path.exists(log) else []
    tot = [r for r in rows if len(r) > 3 and r[1] == "total"]
    if len(tot) != 1 or tot[0][3] != str(want):
        fail(name + ": total row missing or wrong exit: %r" % tot)
    if fails == 0:
        print("ok: " + name)


run_case("pass", "sleep 2\nexit 0\n", None)
run_case("fail", "sleep 2\nexit 1\n", None)
run_case("sigint", "sleep 30\nexit 0\n", signal.SIGINT)
sys.exit(1 if fails else 0)
PYEOF
