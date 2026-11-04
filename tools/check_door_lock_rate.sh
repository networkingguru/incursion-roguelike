#!/bin/bash
# gate: live
# Does a random closed door lock exactly when the roll is below the depth's
# lock chance? (bd inc-h22n, rewritten as an exact test in bd inc-0re7)
#
# THE RULE (src/Feature.cpp, Door::Door). lockChance = 25 + (depth-1)*50/9,
# integer math: depth 2 -> 30, depth 10 -> 75. A closed door locks when
# random(100) < lockChance. Designed-room locks and the forced secret-and-locked
# door are not random doors and are not counted.
#
# THE TEST. INCURSION_DOOR_LOCK_ROLL=<0..99> replaces the lock roll, so a door
# locks exactly when the value is below its depth's chance. Four sessions:
#   roll 29: every closed depth-2 door locks   (29 < 30)
#   roll 30: no closed depth-2 door locks      (30 is not < 30)
#            every closed depth-10 door locks  (30 < 75)
#   roll 74: every closed depth-10 door locks  (74 < 75)
#   roll 75: no closed depth-10 door locks     (75 is not < 75)
# A flat 50% rule fails roll 30 at depth 2 and roll 29 is the same for both,
# so the check is red on the old code. A closed door is one with neither
# DF_OPEN (0x02) nor DF_SECRET (0x20) set; DF_BROKEN is ignored (inc-95d).
# Locked is DF_LOCKED (0x08). Log lines come from INCURSION_DOORGEN_PROBE=1
# (src/DoorPickProbe.cpp, logs/doorgen.log):  DOORGEN depth=D flags=0xFF
#
# WHY DEPTH 2, NOT DEPTH 1. A loaded save brings its own depth-1 level, which
# is not regenerated, so no depth-1 door is built in the session. Depth 1 uses
# the same formula as every other depth.
#
# THE GUARD. A needed depth with zero closed doors in a session is
# INCONCLUSIVE (exit 2), never a pass.
#
# fact: character -- fixture orc-mage-seed1-opt0822 (INCURSION_LOAD)
# fact: settings -- CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
# fact: levels 2..10 built -- wizard 'p' jump to depth 10 (tools/keys/door-rate.keys)
# fact: the lock roll -- INCURSION_DOOR_LOCK_ROLL
# fact: number of closed doors per depth (open roll 1-in-10, no control) -- not asserted on, zero is exit 2
#
# Usage: tools/check_door_lock_rate.sh [--prove-red]   exit 0 pass, 1 fail, 2 inconclusive
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The old flat rule: roll 30 locks depth-2 doors.
check_mutation src/Feature.cpp \
    '    int lockChance = 25 + (depth - 1) * 50 / 9;' \
    '    int lockChance = 50;'

export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
export INCURSION_DOORGEN_PROBE=1

# tally <log> <depth>: prints "<closed> <locked>".
tally() {
    python3 - "$1" "$2" <<'PY'
import re, sys
c = l = 0
for line in open(sys.argv[1]):
    m = re.match(r"DOORGEN depth=(\d+) flags=0x([0-9a-f]+)", line)
    if not m or int(m.group(1)) != int(sys.argv[2]):
        continue
    f = int(m.group(2), 16)
    if f & 0x02 or f & 0x20:
        continue
    c += 1
    l += bool(f & 0x08)
print(c, l)
PY
}

FAIL=0
# run_roll <roll>: runs a session; leaves its log path in LOG.
run_roll() {
    INCURSION_DOOR_LOCK_ROLL="$1" check_run tools/keys/door-rate.keys 1 > /dev/null
    LOG="$CHECK_RUN/logs/doorgen.log"
    [ -f "$LOG" ] || _check_die 2 \
        "roll $1 wrote no $LOG, so the probe never ran. Is DoorGenProbe" \
        "still the last statement of Map::MakeDoor (src/MakeLev.cpp)?"
}
# expect <roll> <depth> all|none
expect() {
    local c l want ok=ok
    read -r c l < <(tally "$LOG" "$2")
    [ "$c" -gt 0 ] || _check_die 2 \
        "roll $1 built no closed random door at depth $2."
    if [ "$3" = all ]; then [ "$l" -eq "$c" ] || ok=FAIL
    else [ "$l" -eq 0 ] || ok=FAIL; fi
    [ "$ok" = ok ] || FAIL=1
    printf '  roll %-2s depth %-2s  %4d closed  %4d locked  want %-4s  %s\n' "$1" "$2" "$c" "$l" "$3" "$ok"
}

run_roll 29; expect 29 2 all
run_roll 30; expect 30 2 none; expect 30 10 all
run_roll 74; expect 74 10 all
run_roll 75; expect 75 10 none

echo
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: a door locked or stayed open on the wrong side of its depth's lock chance (inc-h22n point 1)"
    exit 1
fi
echo "PASS: closed doors lock exactly below 25 + (depth-1)*50/9 (depth 2: 30, depth 10: 75)"
exit 0
