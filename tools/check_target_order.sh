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
# inc-3ybbz replaced that with this order. The map round the player is cut into
# eight 45-degree slices, one centred on each arrow (N NE E SE S SW W NW; screen
# y grows down, so north is dy < 0). A run that starts with arrow A visits A's
# slice first, then the next slice clockwise, and so on round all eight. Inside
# a slice the nearest thing comes first, and equal distances go clockwise. The
# first press of a run (cursor on the player, or an arrow other than the run's)
# takes the first place in that order; the same arrow again takes the next one;
# the last wraps to the first. WHICH things are candidates did not change; that
# is the calling prompt's business and the filters are untouched.
#
# fact: character -- fixture orc-barbarian-seed1-opt0818 -- orc-barbarian-seed1-opt0818 is frozen old save kept as a specimen until inc-9s4u0 gives its scene a map builder (tools/fixtures/specimens/orc-barbarian-seed1-opt0818.sav)
# fact: map, player square (111,110), nine corpses in view -- same fixture (a save pins the dungeon)
# fact: no monster acts, no roll is made -- Look and the target cursor take no game turn
#
# The assertions, all read from the probe log, with the slices worked out here
# from the logged coordinates by atan2, not by the game's integer test:
#   1. a run's first press chose the nearest candidate in its arrow's slice, or
#      in the next non-empty slice clockwise;
#   2. a run's choices equal the computed order, every place once per lap, and
#      then the lap again;
#   3. a run started by another arrow restarts at its own slice;
#   4. a hand-worked second oracle: the first five squares of the RIGHT run.
#
# THE RUN CAN FAIL TO MEASURE ANYTHING, and that is reported as INCONCLUSIVE
# rather than FAIL: a session that failed to load the fixture, or whose [t]
# never opened the target cursor, says nothing about the bug. Sending somebody
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

out="$(INCURSION_TARGET_PROBE=1 INCURSION_OPTIONS=tools/fixtures/options-2026-08-18.dat INCURSION_LOAD=tools/fixtures/specimens/orc-barbarian-seed1-opt0818.sav tools/headless.sh tools/keys/target-ring.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/targetprobe.log"

[ -f "$log" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log, so the target cursor"
    echo "              was never opened. Run dir: $run"
    exit 2
}

python3 - "$log" "$run" <<'PY'
import math, re, sys

log, run = sys.argv[1], sys.argv[2]
# The probe prints creature names, which carry the game's colour bytes.
# Only the coordinates are read here, so the bytes are decoded permissively.
text = open(log, 'rb').read().decode('latin-1')

NAMES = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']   # clockwise from north

presses = []
for block in text.split('arrow ')[1:]:
    head = block.split('\n', 1)[0]
    m = re.match(r'(\w+) newrun=(\d) cursor=\((\d+),(\d+)\) player=\((\d+),(\d+)\)', head)
    if not m:
        continue
    chosen = re.search(r'CHOSE \(\s*(\d+),\s*(\d+)\)', block)
    presses.append({
        'arrow': m.group(1),
        'newrun': m.group(2) == '1',
        'player': (int(m.group(5)), int(m.group(6))),
        'cands': sorted({(int(x), int(y), int(d)) for x, y, d in
                         re.findall(r'cand\s+\(\s*(\d+),\s*(\d+)\) dist=(\d+)', block)}),
        'chosen': (int(chosen.group(1)), int(chosen.group(2))) if chosen else None,
    })

fails, dead = [], []

# Runs: consecutive presses of one arrow.
runs = []
for q in presses:
    if runs and runs[-1][0]['arrow'] == q['arrow']:
        runs[-1].append(q)
    else:
        runs.append([q])

def bearing(dx, dy):
    """Degrees clockwise from north; screen y grows down."""
    return math.degrees(math.atan2(dx, -dy)) % 360

def slice_of(dx, dy):
    return int(((bearing(dx, dy) + 22.5) % 360) // 45)

def key(c, px, py, start):
    """(slice from the start arrow, distance, bearing from the slice's start edge)"""
    dx, dy = c[0] - px, c[1] - py
    s = slice_of(dx, dy)
    edge = (45 * s - 22.5) % 360
    return ((s - start) % 8, c[2], (bearing(dx, dy) - edge) % 360)

def order(cands, player, arrow):
    start = NAMES.index(arrow)
    return [(c[0], c[1]) for c in
            sorted(cands, key=lambda c: key(c, player[0], player[1], start))]

# Four runs, RIGHT (E) twelve, UP (N) twelve, DOWN (S) three, PGUP (NE) three,
# measure nothing if the arrows never reached the target cursor.
if [r[0]['arrow'] for r in runs] != ['E', 'N', 'S', 'NE']:
    dead.append("the probe saw the runs %s, not E, N, S, NE, so the arrows\n"
                "              never reached the target cursor as scripted."
                % [r[0]['arrow'] for r in runs])
elif not presses[0]['cands']:
    dead.append("the first press saw no candidates; nothing was in view.")

if not dead:
    for r in runs:
        arrow, player = r[0]['arrow'], r[0]['player']
        cands = r[0]['cands']
        want = order(cands, player, arrow)
        start = NAMES.index(arrow)

        # The game's own claim about which presses start a run.
        flags = [q['newrun'] for q in r]
        if flags != [True] + [False] * (len(r) - 1):
            fails.append("run %s: the newrun flags are %s; only the first press of a\n"
                         "      run starts a new run." % (arrow, flags))

        # 1. The first press: nearest in the arrow's slice, or the next
        #    non-empty slice clockwise.
        for rel in range(8):
            inside = [c for c in cands
                      if (slice_of(c[0] - player[0], c[1] - player[1]) - start) % 8 == rel]
            if inside:
                near = min(inside, key=lambda c: key(c, player[0], player[1], start))
                if r[0]['chosen'] != (near[0], near[1]):
                    fails.append("run %s: the first press chose %s, but the nearest in the\n"
                                 "      first non-empty slice (%s) is %s, distance %d."
                                 % (arrow, r[0]['chosen'], NAMES[(start + rel) % 8],
                                    (near[0], near[1]), near[2]))
                break

        # 2. The whole run is the computed order, lap after lap.
        got = [q['chosen'] for q in r]
        expect = [want[i % len(want)] for i in range(len(r))]
        if got != expect:
            k = next(i for i in range(len(r)) if got[i] != expect[i])
            fails.append("run %s: press %d chose %s, but the order has %s there.\n"
                         "      order: %s" % (arrow, k + 1, got[k], expect[k], want))
        if len(r) > len(want) and got[len(want)] != got[0]:
            fails.append("run %s: the lap of %d did not come back to %s."
                         % (arrow, len(want), got[0]))

    # A run too short to show a lap on the two long runs measures nothing.
    if len(runs[0]) <= len(order(runs[0][0]['cands'], runs[0][0]['player'], 'E')):
        dead.append("the RIGHT run is no longer than one lap, so the wrap was not reached.")

    # 3. The UP run restarts at its own slice; it does not go on from where
    #    the RIGHT run stopped.
    right, up = runs[0], runs[1]
    cont = order(right[0]['cands'], right[0]['player'], 'E')
    after = cont[len(right) % len(cont)]
    first_up = order(up[0]['cands'], up[0]['player'], 'N')[0]
    if up[0]['chosen'] != first_up:
        fails.append("the UP run began at %s, not at its own first place %s."
                     % (up[0]['chosen'], first_up))
    if first_up == after:
        dead.append("the UP run's first place equals where RIGHT would have gone\n"
                    "              next, so this run cannot tell a restart from a continuation.")

    # 4. Second oracle, worked by hand from the candidate list in the log.
    #    Player (111,110). Slices (dx,dy) -> slice, dist:
    #      E  (115,109) d4 (4,-1)   S (112,113) d3 (1,3)   SW (109,111) d2 (-2,1)
    #      W  (105,111) d6 (-6,1)   NW (108,108) d4 (-3,-2)
    #      N  (112,107) d3 (1,-3), (111,106) d4 (0,-4)
    #      NE (112,108) d2 (1,-2), (116,107) d6 (5,-3);  SE: none.
    #    RIGHT starts at E: E, SE (empty), S, SW, W, NW, N, NE. So the first
    #    five squares are the E one, the S one, the SW one, the W one, the NW one.
    HAND = [(115, 109), (112, 113), (109, 111), (105, 111), (108, 108)]
    got5 = [q['chosen'] for q in right[:5]]
    if got5 != HAND:
        fails.append("the first five RIGHT squares are %s; worked by hand they are %s."
                     % (got5, HAND))

# A proved failure outranks a missing measurement.
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

print("PASS: each arrow's run starts at its own slice, goes nearest first and")
print("      clockwise round all eight slices, and laps; %d places in view." % len(want))
print("Run dir: " + run)
PY
status=$?
exit $status
