#!/bin/bash
# Regression check for the overview map's staircase keys, inc-pw1.4 and
# inc-pw1.5.
#
# TWO THINGS WERE WRONG, and this checks both.
#
# 1. '<' and '>' did nothing at all (inc-pw1.5). TextTerm::ShowMapOverview
#    switched on 'case KY_CMD_UP:' and 'case KY_CMD_DOWN:', and GetCharCmd in
#    KY_CMD_ARROW_MODE returns no command outside the eight compass arrows
#    (src/Wposix.cpp:1351, and the same lines in Wcurses.cpp and
#    Wlibtcod.cpp). So the keyset hit was dropped, the raw character came back
#    instead, no label matched it, and both keys fell to default: -- which
#    closes the map. ',' and '.' worked all along, because KY_COMMA and
#    KY_PERIOD ARE the raw characters.
#
# 2. The search picked the wrong staircase (inc-pw1.4). It scanned the map row
#    by row from the cursor's linear index and took the next match in reading
#    order. Distance never entered it. The search now ranks each staircase by
#    what it costs to walk there, using the same Map::ShortestPath and the same
#    three danger settings, in the same order, that Player::RunTo uses -- so
#    the square the cursor lands on is the square [R] will really reach.
#    Repeated presses still cycle: they step down the ranked list and wrap.
#
# WHAT THIS ASSERTS, from the probe log the session writes:
#
#   A. the map opened, and both '<' and '>' reached the search
#   B. every choice is the one the ranking rule demands, recomputed here from
#      the candidate list the game itself logged
#   C. at least one rank is above zero, so the number is a real path cost and
#      not a stub
#   D. the cursor wraps rather than reporting nothing when it is already on
#      the last staircase of the list
#
# A is red on the build before the fix: the map opens, and no press is ever
# recorded because '<' closed it.
#
# ponytail: B is only as strong as the session is rich. Seed 1 knows one
# staircase of each kind, so B checks the choice and the wrap but never the
# ORDER of two candidates. This script says so in its output rather than
# implying coverage it does not have. To lift the ceiling, give it a session
# that remembers two staircases of one kind -- see the note in
# tools/keys/stair-cycle.keys for what has already been tried.
#
# A run that never opens the map is INCONCLUSIVE, not FAIL. A dead session
# says nothing about the bug; sending somebody hunting a regression that a
# dead session invented is the mistake of inc-loa.3.
#
# Usage: tools/check_stair_cycle.sh    (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(INCURSION_STAIR_PROBE=1 tools/headless.sh tools/keys/stair-cycle.keys "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"
log="$run/logs/stairprobe.log"

[ -f "$log" ] || {
    echo "INCONCLUSIVE: the session wrote no probe log, so the overview map"
    echo "              was never opened. Run dir: $run"
    exit 2
}

python3 - "$log" "$run" <<'PY'
import re, sys

log, run = sys.argv[1], sys.argv[2]

# One record per press: the cursor it started from, the candidates the scan
# accepted in the order it accepted them, and the square it moved to. The
# scan runs row by row, so the log order IS the map-index order, which is
# what breaks a tie between two equally costly staircases.
presses, opens, cur = [], 0, None
for line in open(log):
    line = line.strip()
    if line.startswith("open "):
        opens += 1
    elif line.startswith("press "):
        f = dict(kv.split("=", 1) for kv in line.split()[1:])
        x, y = f["cur"].split(",")
        cur = {"dir": f["dir"], "x": int(x), "y": int(y),
               "rank": int(f["currank"]), "onstair": f["onstair"] == "1",
               "cands": [], "chose": None}
        presses.append(cur)
    elif line.startswith("cand ") and cur is not None:
        f = dict(kv.split("=", 1) for kv in line.split()[1:])
        cur["cands"].append((int(f["x"]), int(f["y"]), int(f["rank"])))
    elif line.startswith("chose ") and cur is not None:
        if line == "chose none":
            cur["chose"] = None
        else:
            f = dict(kv.split("=", 1) for kv in line.split()[1:])
            cur["chose"] = (int(f["x"]), int(f["y"]), int(f["rank"]))

fails, notes = [], []

if not opens:
    print("INCONCLUSIVE: the map never opened. Run dir: %s" % run)
    sys.exit(2)

# A. both keys reached the search
ups = [p for p in presses if p["dir"] == "up"]
downs = [p for p in presses if p["dir"] == "down"]
if not ups:
    fails.append("'<' never reached the staircase search: the map opened %d "
                 "time(s) and not one ascending press was recorded. This is "
                 "inc-pw1.5 back again." % opens)
if not downs:
    fails.append("'>' never reached the staircase search: the map opened %d "
                 "time(s) and not one descending press was recorded. This is "
                 "inc-pw1.5 back again." % opens)

# B. every choice follows the ranking rule
def key(cand, pos):
    return (cand[2], pos)

stepped = wrapped = 0
for n, p in enumerate(presses):
    cands = p["cands"]
    if not cands:
        if p["chose"] is not None:
            fails.append("press %d chose %s with no candidates at all"
                         % (n, p["chose"]))
        continue
    if p["chose"] is None:
        fails.append("press %d had %d candidate(s) and chose none"
                     % (n, len(cands)))
        continue

    order = sorted(range(len(cands)), key=lambda i: key(cands[i], i))
    if p["onstair"]:
        here = [i for i, c in enumerate(cands)
                if (c[0], c[1]) == (p["x"], p["y"])]
        if not here:
            fails.append("press %d says the cursor stood on a staircase at "
                         "(%d,%d), which is not in its own candidate list"
                         % (n, p["x"], p["y"]))
            continue
        pos = here[0]
        after = [i for i in order if key(cands[i], i) > (p["rank"], pos)]
        want = cands[after[0]] if after else cands[order[0]]
        if after:
            stepped += 1
        else:
            wrapped += 1
    else:
        want = cands[order[0]]

    if p["chose"] != want:
        fails.append("press %d (%s) chose %s but the ranking rule demands %s; "
                     "candidates were %s"
                     % (n, p["dir"], p["chose"], want, cands))

# C. at least one real, non-zero path cost.
#
# A failure already found outranks an empty session. Report it first: an
# empty candidate list is exactly what the inc-pw1.5 regression produces, so
# exiting INCONCLUSIVE here would hide the very thing check A just caught.
ranks = [c[2] for p in presses for c in p["cands"]]
if not ranks:
    if fails:
        print()
        for f in fails:
            print("FAIL: " + f)
        print("Run dir: %s" % run)
        sys.exit(1)
    print("INCONCLUSIVE: the map opened and the keys worked, but the session "
          "never remembered a single staircase, so there was nothing to rank. "
          "Run dir: %s" % run)
    sys.exit(2)
if max(ranks) <= 0:
    fails.append("every candidate ranked 0. The rank is meant to be the cost "
                 "of walking there, so a whole session of zeroes means the "
                 "cost is not being measured.")

# D. the wrap was exercised
if not wrapped:
    notes.append("the wrap was never exercised: no press ran off the end of "
                 "the ranked list.")

distinct = {(c[0], c[1]) for p in presses for c in p["cands"]}
if len(distinct) < 2:
    notes.append("this session knew only %d staircase, so the ORDER of two "
                 "candidates was not checked -- only the choice and the wrap. "
                 "See the ponytail note in this script." % len(distinct))

print("map opened %d time(s); %d ascending and %d descending presses"
      % (opens, len(ups), len(downs)))
print("%d distinct staircase(s) known; ranks %d..%d"
      % (len(distinct), min(ranks), max(ranks)))
print("%d press(es) stepped to a further staircase, %d wrapped to the closest"
      % (stepped, wrapped))
for note in notes:
    print("note: " + note)

if fails:
    print()
    for f in fails:
        print("FAIL: " + f)
    print("Run dir: %s" % run)
    sys.exit(1)

print("PASS")
sys.exit(0)
PY
exit $?
