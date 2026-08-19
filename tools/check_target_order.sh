#!/bin/bash
# Regression check for the target cursor that jumped by stride, inc-upw.26.
#
# TextTerm::EffectPrompt (src/Term.cpp) scored every candidate on ONE axis.
# RIGHT added the column gap and never looked at the row; UP added the row gap
# and never looked at the column. So "right" meant "the nearest column to my
# right", every row in that column scored the same, and the winner among them
# was whichever sat first in Map::Things. Brian described it from play as
# "almost like when you configure tab stops incorrectly".
#
# The arrows now step round a ring: the candidates are ordered by their
# bearing from the player, UP and RIGHT go clockwise, DOWN and LEFT go
# counter-clockwise, and the cursor enters the ring at the nearest candidate
# in the direction of the first press. WHICH things are candidates did not
# change; that is the calling prompt's business and the filters are untouched.
#
# Measured 2026-08-19, seed 1, same key script, src/Term.cpp the only file
# different between the two builds. The player stands at (111,110) with nine
# corpses in view:
#
#   RIGHT from the player   before: (112,107), three columns off and the
#                                   furthest of the three tied candidates
#                           after:  (112,108), the nearest thing to the right
#   UP from (116,107)       before: (111,106) -- up one row, sideways five
#                           after:  (115,109), the next place round the ring
#   twelve UP presses       before: four squares, revisited out of order
#                           after:  nine distinct squares, then the lap again
#
# The three assertions below are all red on the old build.
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is reported as INCONCLUSIVE
# rather than FAIL: a session that never reached the caves, or whose [t] never
# opened the target cursor, says nothing about the bug. Sending somebody
# hunting a regression that a dead session invented is the mistake of
# inc-loa.3.
#
# Usage: tools/check_target_order.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_TARGET_PROBE=1 tools/headless.sh tools/keys/target-ring.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/targetprobe.log"

[ -f "$log" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log, so the target cursor"
    echo "              was never opened. Run dir: $run"
    exit 2
}

python3 - "$log" "$run" <<'PY'
import re, sys

log, run = sys.argv[1], sys.argv[2]
# The probe prints creature names, which carry the game's colour bytes.
# Only the coordinates are read here, so the bytes are decoded permissively.
text = open(log, 'rb').read().decode('latin-1')

presses = []          # one per arrow press: way, cursor, aim candidates, chosen
for block in text.split('arrow ')[1:]:
    head = block.split('\n', 1)[0]
    cur = re.search(r'cursor=\((\d+),(\d+)\)', head)
    chosen = re.search(r'CHOSE \(\s*(\d+),\s*(\d+)\)', block)
    presses.append({
        'way': head.split()[0],
        'cursor': (int(cur.group(1)), int(cur.group(2))) if cur else None,
        'aims': [(int(x), int(y), int(d)) for x, y, d in
                 re.findall(r'aim\s+\(\s*(\d+),\s*(\d+)\) dist=(\d+)', block)],
        'chosen': (int(chosen.group(1)), int(chosen.group(2))) if chosen else None,
    })

fails, dead = [], []

def way(name):
    return [q for q in presses if q['way'].startswith(name)]

cw_all, ccw_all = way('clock'), way('widder')

# A run that never opened the target cursor, or never pressed enough keys at
# it, measures nothing and must not be reported as either a pass or a fail.
# A cursor that HAD presses and refused to move is a different thing, and is
# a failure -- that is the whole complaint.
if len(cw_all) < 4 or len(ccw_all) < 4:
    dead.append("the target cursor took only %d clockwise and %d counter-clockwise\n"
                "              presses, so the arrows never reached it."
                % (len(cw_all), len(ccw_all)))
if presses and not presses[0]['aims']:
    dead.append("the first press did not enter the ring, so the cursor was not\n"
                "              on the player when the arrows started.")

if not dead:
    # 1. Entering the ring takes the NEAREST candidate in the direction pressed.
    #    The old code took the nearest COLUMN, then whichever of that column's
    #    ties came first in Map::Things.
    first = presses[0]
    nearest = min(first['aims'], key=lambda c: c[2])
    if first['chosen'] != (nearest[0], nearest[1]):
        fails.append("the first press entered the ring at %s, but the nearest\n"
                     "      candidate in that direction is %s (distance %d)."
                     % (first['chosen'], (nearest[0], nearest[1]), nearest[2]))

    # 2. Every press moves. A press with nowhere to go is the stride bug's
    #    signature: the cursor walks itself into a corner and stops.
    for name, seq in (("clockwise", cw_all), ("counter-clockwise", ccw_all)):
        stuck = [i + 1 for i, q in enumerate(seq) if q['chosen'] is None]
        if stuck:
            fails.append("%d of the %d %s presses moved the cursor nowhere\n"
                         "      (presses %s). The ring has no dead ends."
                         % (len(stuck), len(seq), name,
                            ', '.join(str(i) for i in stuck[:6]) + (', ...' if len(stuck) > 6 else '')))

    # 3. One direction, pressed repeatedly, walks a closed lap: every place on
    #    the ring once, in the same order, for ever.
    laps = {}
    for name, seq in (("clockwise", [q['chosen'] for q in cw_all if q['chosen']]),
                      ("counter-clockwise", [q['chosen'] for q in ccw_all if q['chosen']])):
        if seq[0] not in seq[1:]:
            if len(set(seq)) == len(seq):
                dead.append("%s never came back round to %s in %d presses, so the\n"
                            "              ring is bigger than this run walks."
                            % (name, seq[0], len(seq)))
            else:
                fails.append("%s revisited a place without completing a lap:\n      %s"
                             % (name, seq))
            continue
        n = seq.index(seq[0], 1)
        if len(set(seq[:n])) != n:
            fails.append("%s came back round after %d presses, but only %d of those\n"
                         "      places are distinct -- it does not walk a lap:\n      %s"
                         % (name, n, len(set(seq[:n])), seq[:n]))
            continue
        broke = next((i for i, place in enumerate(seq) if place != seq[i % n]), None)
        if broke is not None:
            fails.append("%s broke its order at press %d: expected %s, got %s."
                         % (name, broke + 1, seq[broke % n], seq[broke]))
            continue
        laps[name] = seq[:n]

    # 4. Counter-clockwise is clockwise backwards. Same ring, same places, the
    #    reverse order -- a cursor that cannot retrace its steps is useless.
    if len(laps) == 2:
        cw_lap, ccw_lap = laps["clockwise"], laps["counter-clockwise"]
        if sorted(cw_lap) != sorted(ccw_lap):
            fails.append("the two directions walk different sets of places:\n"
                         "      clockwise %s\n      counter   %s"
                         % (sorted(cw_lap), sorted(ccw_lap)))
        else:
            n = len(cw_lap)
            at = cw_lap.index(ccw_lap[0])
            backwards = [cw_lap[(at - k) % n] for k in range(n)]
            if ccw_lap != backwards:
                fails.append("counter-clockwise is not clockwise reversed:\n"
                             "      forwards  %s\n      backwards %s\n      measured  %s"
                             % (cw_lap, backwards, ccw_lap))

# A proved failure outranks a missing measurement: something already went
# wrong, and calling that inconclusive would hide it.
if fails:
    for f in fails:
        print("FAIL: " + f)
    print("Run dir: " + run)
    sys.exit(1)

if dead:
    for d in dead:
        print("INCONCLUSIVE: " + d)
    print("              Run dir: " + run)
    sys.exit(2)

lap = laps["clockwise"]
print("PASS: the cursor enters the ring at the nearest thing in the direction")
print("      pressed, walks %d places clockwise and the same %d backwards."
      % (len(lap), len(lap)))
print("Run dir: " + run)
PY
status=$?
exit $status
