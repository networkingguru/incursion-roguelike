#!/bin/bash
# gate: live
# Does a random closed door lock at the depth-scaled rate? (bd inc-h22n)
#
# THE RULE (design point 1). A closed random door is locked with chance
# 25 + (depth - 1) * 50 / 9 percent: 25% at depth 1, 75% at depth 10.
# Designed-room locks (TILE_LOCKED) and the forced secret-and-locked door are
# NOT random doors and are not counted: only Map::MakeDoor's doors are.
#
# THE ORACLE. INCURSION_DOORGEN_PROBE=1 makes Map::MakeDoor log one line per
# random door it places, after the generator has finished with it
# (src/DoorPickProbe.cpp, logs/doorgen.log):  DOORGEN depth=D flags=0xFF
# tools/keys/door-rate.keys starts a new character (a fresh depth-1 level) and
# jumps to depth 10 with the wizard 'p' command, which also builds the levels in
# between, so one session logs doors for depths 1..10. The gate settings file
# is used because chargen.keys only works on every seed with it. A door is CLOSED when neither DF_OPEN (0x02) nor DF_SECRET
# (0x20) is set; DF_BROKEN is ignored, because Door::SetImage brands doors
# broken while their frame is unbuilt (inc-95d) and un-brands them later. A
# closed door is LOCKED when DF_LOCKED (0x08) is set.
#
# THE TOLERANCE. The 10 SEEDS give about 300 closed doors per depth (measured: 513 and
# 392 over 16 seeds), so one standard deviation is under 3 points. Depth 1 must land in 25 +/- 10 and
# depth 10 in 75 +/- 10. The unmodified code locks half of all closed doors,
# which is 6 standard deviations from 25 and from 75, so the check is RED there
# and GREEN for any implementation of the design.
#
# THE GUARD. Fewer than MIN_CLOSED closed doors at either depth is INCONCLUSIVE
# (exit 2), never a pass: a run that measured nothing proves nothing.
#
# Usage: tools/check_door_lock_rate.sh [--selftest]   exit 0 pass, 1 fail, 2 inconclusive
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat
SEEDS="1 2 3 4 5 6 7 8 9 10"   # not 12: it offers no "Neutral" alignment, so chargen.keys cannot pass it
MIN_CLOSED=120
TOL=10

# analyse <log>: exit 0 pass, 1 fail, 2 inconclusive.
analyse() {
python3 - "$1" "$MIN_CLOSED" "$TOL" <<'PY'
import re, sys
path, minc, tol = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
closed, locked = {}, {}
for line in open(path):
    m = re.match(r"DOORGEN depth=(\d+) flags=0x([0-9a-f]+)", line)
    if not m:
        continue
    d, f = int(m.group(1)), int(m.group(2), 16)
    if f & 0x02 or f & 0x20:
        continue
    closed[d] = closed.get(d, 0) + 1
    if f & 0x08:
        locked[d] = locked.get(d, 0) + 1
rc = 0
for d, want in ((1, 25), (10, 75)):
    n = closed.get(d, 0)
    if n < minc:
        print("INCONCLUSIVE: only %d closed random doors at depth %d (need %d)" % (n, d, minc))
        sys.exit(2)
    pct = 100.0 * locked.get(d, 0) / n
    ok = abs(pct - want) <= tol
    print("  depth %-2d  %4d closed  %4d locked  %5.1f%%  want %d +/- %d  %s"
          % (d, n, locked.get(d, 0), pct, want, tol, "ok" if ok else "FAIL"))
    if not ok:
        rc = 1
sys.exit(rc)
PY
}

# --selftest: the analyser on hand-made logs, no game. The design's rates pass,
# the unmodified code's 50% at both depths fails, too few doors is inconclusive.
if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp)"; bad=0
    mk() { python3 -c "
import sys
d1, d10, n = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
for depth, p in ((1, d1), (10, d10)):
    for i in range(n):
        print('DOORGEN depth=%d flags=0x%02x' % (depth, 0x08 if i < p * n else 0x00))
" "$@" > "$T"; }
    mk 0.25 0.75 200; analyse "$T" > /dev/null; got=$?
    [ "$got" -eq 0 ] && echo "selftest ok    design rates pass" || { echo "selftest FAIL  design rates -> $got"; bad=1; }
    mk 0.50 0.50 200; analyse "$T" > /dev/null; got=$?
    [ "$got" -eq 1 ] && echo "selftest ok    50%/50% (unmodified code) fails" || { echo "selftest FAIL  50/50 -> $got"; bad=1; }
    mk 0.25 0.75 20; analyse "$T" > /dev/null; got=$?
    [ "$got" -eq 2 ] && echo "selftest ok    too few doors is inconclusive" || { echo "selftest FAIL  few doors -> $got"; bad=1; }
    rm -f "$T"; exit "$bad"
fi

export INCURSION_DOORGEN_PROBE=1

ALL="$(mktemp)"
OUT="$(mktemp)"
# check_run is quiet on success; on a refusal it exits, and this shows why.
# (The trap runs inside check_run's redirect, so it must write to stderr.)
trap 'rc=$?; [ "$rc" -eq 2 ] && [ -s "$OUT" ] && cat "$OUT" >&2; rm -f "$ALL" "$OUT"' EXIT
for s in $SEEDS; do
    : > "$OUT"
    check_run tools/keys/door-rate.keys "$s" > "$OUT"
    LOG="$CHECK_RUN/logs/doorgen.log"
    [ -f "$LOG" ] || _check_die 2 \
        "seed $s wrote no $LOG, so the probe never ran. Is DoorGenProbe" \
        "still the last statement of Map::MakeDoor (src/MakeLev.cpp)?"
    cat "$LOG" >> "$ALL"
done

analyse "$ALL"
RC=$?
echo
if [ "$RC" -eq 2 ]; then exit 2; fi
if [ "$RC" -ne 0 ]; then
    echo "FAIL: the lock rate is not 25% at depth 1 and 75% at depth 10 (inc-h22n point 1)"
    exit 1
fi
echo "PASS: random closed doors lock at about 25% (depth 1) and 75% (depth 10)"
exit 0
