#!/bin/bash
# Regression check for the three door-flag defects fixed on 2026-08-21:
# inc-8zu, inc-wj8 and inc-95d. All three are the same disagreement seen from
# different sides, so they are checked together -- fix one and leave another,
# and the symptom comes straight back in a shape nobody recognises.
#
# WHAT WAS WRONG.
#
#   inc-95d, the source. Door::SetImage brands a door DF_BROKEN when it can
#   read no doorframe beside it (src/Feature.cpp). SetImage runs during level
#   generation, before the walls next to a door exist, so ordinary doors got
#   branded -- and the brand was permanent. On one generated level, 42 redraws
#   found a door still branded whose frame was readable again, 14 of 63 brand
#   events hit a LOCKED door and so made a locked door walkable, and 6 hit a
#   SECRET one. Six doors ended that level closed and branded broken.
#
#   inc-8zu, the symptom Brian hit. Map::RunOver asked for DF_OPEN alone, so a
#   branded door was a wall to the route search while the map called the square
#   passable. A character inside a building whose exits were branded doors could
#   not travel anywhere, and the overview map's [R] answered "There's no clear,
#   safe and explored route to that area" with the way out plainly visible.
#
#   inc-wj8, the same reader defect at the monster movement site. A monster
#   meeting a branded doorway called OpenDoor on a hole, and OpenDoor's
#   fall-through sent it on to attack the empty doorway.
#
# WHAT THIS ASSERTS, in two halves that need each other.
#
#   SOURCE. One predicate, Door::isPassable, holds the engine's answer, and
#   every reader asks it rather than reconstructing the answer from flag bits.
#   A grep is enough here because the failure being guarded against is somebody
#   writing `DoorFlags & DF_OPEN` again at one of these sites.
#
#   LIVE. A generated session with INCURSION_DOOR_PROBE=1 must show the brand
#   being APPLIED at least once -- a run that never brands a door proves
#   nothing and must say so rather than pass -- and must show no door left
#   branded broken while closed, in a readable doorframe, with the doorway
#   clear. That last combination is exactly the state Brian's save was in.
#
# The live half is the one that would catch a real regression; the source half
# is the one that says which line caused it.
#
# Usage:
#   tools/check_broken_door.sh              exit 0 pass, 1 fail, 2 inconclusive
#   tools/check_broken_door.sh --selftest   prove the analyser detects the bug
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/dive12.keys
FAIL=0

# ---------------------------------------------------------------------------
# The analyser. Reads a probe log on stdin, prints a report, exits non-zero on
# a violation. Kept separate from the run so --selftest can feed it a
# hand-written log and prove it detects what it claims to detect.
analyse() {
    python3 -c '
import re, sys
pat = re.compile(r"door (-?\d+),(-?\d+) before=0x([0-9a-f]+) after=0x([0-9a-f]+) "
                 r"N=(\d) S=(\d) W=(\d) E=(\d) vert=(\d) horiz=(\d) occ=(\d)")
DF_OPEN, DF_BROKEN = 0x02, 0x40
rows = []
for line in sys.stdin:
    m = pat.match(line.strip())
    if m:
        g = m.groups()
        rows.append(dict(x=int(g[0]), y=int(g[1]), before=int(g[2],16),
                         after=int(g[3],16), vert=int(g[8]), horiz=int(g[9]),
                         occ=int(g[10])))
if not rows:
    print("INCONCLUSIVE: the probe log holds no door redraws. Either the run")
    print("              never generated a level or INCURSION_DOOR_PROBE was")
    print("              not set. Nothing was measured.")
    sys.exit(2)

brands = [r for r in rows if not (r["before"] & DF_BROKEN) and (r["after"] & DF_BROKEN)]
# A stale brand: carried in, the frame is readable, the doorway is clear, and
# it is STILL there on the way out. The occupied case is the fix deliberately
# waiting for the square to clear, so it is not a violation.
stale = [r for r in rows
         if (r["before"] & DF_BROKEN) and not (r["before"] & DF_OPEN)
         and (r["vert"] or r["horiz"]) and not r["occ"]
         and (r["after"] & DF_BROKEN)]
last = {}
for r in rows:
    last[(r["x"], r["y"])] = r
ended = [r for r in last.values()
         if (r["after"] & DF_BROKEN) and not (r["after"] & DF_OPEN)
         and (r["vert"] or r["horiz"]) and not r["occ"]]

print("    door redraws seen                       %d" % len(rows))
print("    distinct doors                          %d" % len(last))
print("    brand applied (the branch is reachable) %d" % len(brands))
print("    stale brand kept through a redraw       %d" % len(stale))
print("    doors left closed and branded broken    %d" % len(ended))

rc = 0
if not brands:
    print()
    print("INCONCLUSIVE: no door was branded DF_BROKEN in this run, so a clean")
    print("              result proves nothing about the branch that brands")
    print("              them. Pick a seed or key script that builds one.")
    sys.exit(2)
if stale:
    r = stale[0]
    print()
    print("FAIL: a door carried DF_BROKEN without DF_OPEN through a redraw that")
    print("      could read its doorframe, with nothing standing in the doorway.")
    print("      Door::SetImage must clear that brand. This is inc-95d back.")
    print("      first of %d: door %d,%d before=0x%02x after=0x%02x vert=%d horiz=%d"
          % (len(stale), r["x"], r["y"], r["before"], r["after"], r["vert"], r["horiz"]))
    rc = 1
if ended:
    r = ended[0]
    print()
    print("FAIL: a door ended the run closed, branded broken and standing in a")
    print("      readable doorframe -- the exact state that sealed Brian temple")
    print("      on 2026-08-21. The route search calls that square a wall while")
    print("      the map calls it a hole. This is inc-8zu back.")
    print("      first of %d: door %d,%d flags=0x%02x vert=%d horiz=%d"
          % (len(ended), r["x"], r["y"], r["after"], r["vert"], r["horiz"]))
    rc = 1
sys.exit(rc)
'
}

# ---------------------------------------------------------------------------
selftest() {
    local rc=0 out got

    # A log in the shape the pre-fix build produced: a door branded while its
    # frame was unbuilt, then redrawn twice with the frame readable and the
    # brand still on it. The analyser must fail on this.
    out=$(printf '%s\n' \
        "door 10,10 before=0x00 after=0x40 N=0 S=0 W=0 E=0 vert=0 horiz=0 occ=0" \
        "door 10,10 before=0x40 after=0x40 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        "door 10,10 before=0x40 after=0x40 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        | analyse 2>&1)
    got=$?
    if [ "$got" -eq 1 ] && printf '%s' "$out" | grep -q "inc-95d back"; then
        printf 'selftest ok    %-40s -> exit 1\n' "pre-fix log fails"
    else
        printf 'selftest FAIL  %-40s -> exit %s\n%s\n' "pre-fix log fails" "$got" "$out"
        rc=1
    fi

    # The same door under the fix: branded with no frame, then un-branded on
    # the first redraw that can read one. Must pass.
    out=$(printf '%s\n' \
        "door 10,10 before=0x00 after=0x40 N=0 S=0 W=0 E=0 vert=0 horiz=0 occ=0" \
        "door 10,10 before=0x40 after=0x01 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        "door 10,10 before=0x01 after=0x01 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        | analyse 2>&1)
    got=$?
    if [ "$got" -eq 0 ]; then
        printf 'selftest ok    %-40s -> exit 0\n' "post-fix log passes"
    else
        printf 'selftest FAIL  %-40s -> exit %s\n%s\n' "post-fix log passes" "$got" "$out"
        rc=1
    fi

    # A creature standing in the doorway is the one case the fix deliberately
    # leaves alone: turning the square solid under it would bury it in a wall.
    # That must NOT be reported as a regression.
    out=$(printf '%s\n' \
        "door 10,10 before=0x00 after=0x40 N=0 S=0 W=0 E=0 vert=0 horiz=0 occ=0" \
        "door 10,10 before=0x40 after=0x40 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=1" \
        | analyse 2>&1)
    got=$?
    if [ "$got" -eq 0 ]; then
        printf 'selftest ok    %-40s -> exit 0\n' "occupied doorway is exempt"
    else
        printf 'selftest FAIL  %-40s -> exit %s\n%s\n' "occupied doorway is exempt" "$got" "$out"
        rc=1
    fi

    # A genuinely smashed door keeps DF_BROKEN forever, and carries DF_OPEN
    # with it. Reporting that would make the check cry wolf on correct state.
    out=$(printf '%s\n' \
        "door 10,10 before=0x00 after=0x40 N=0 S=0 W=0 E=0 vert=0 horiz=0 occ=0" \
        "door 10,10 before=0x42 after=0x42 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        | analyse 2>&1)
    got=$?
    if [ "$got" -eq 0 ]; then
        printf 'selftest ok    %-40s -> exit 0\n' "smashed door is not a stale brand"
    else
        printf 'selftest FAIL  %-40s -> exit %s\n%s\n' "smashed door is not a stale brand" "$got" "$out"
        rc=1
    fi

    # And a run in which no door was ever branded must report INCONCLUSIVE
    # rather than pass. A green result from a run that measured nothing is the
    # failure mode this whole script is written against.
    out=$(printf '%s\n' \
        "door 10,10 before=0x01 after=0x01 N=1 S=1 W=0 E=0 vert=1 horiz=0 occ=0" \
        | analyse 2>&1)
    got=$?
    if [ "$got" -eq 2 ]; then
        printf 'selftest ok    %-40s -> exit 2\n' "no brand in the run is inconclusive"
    else
        printf 'selftest FAIL  %-40s -> exit %s\n%s\n' "no brand in the run is inconclusive" "$got" "$out"
        rc=1
    fi

    echo
    [ "$rc" -eq 0 ] && echo "selftest: pass" || echo "selftest: FAIL"
    return "$rc"
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    "") ;;
    *) echo "usage: $0 [--selftest]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Half one: the source rule.
echo "--- source ---"

want() {
    # want <file> <regex> <what it guards>
    if grep -qE "$2" "$1"; then
        printf '  ok    %s\n' "$3"
    else
        printf '  FAIL  %s\n' "$3"
        printf '        %s no longer matches: %s\n' "$1" "$2"
        FAIL=1
    fi
}

want inc/Feature.h 'bool isPassable\(\)' \
    "inc/Feature.h defines Door::isPassable, the one answer every reader asks"
want inc/Feature.h 'DoorFlags & \(DF_OPEN \| DF_BROKEN\)' \
    "isPassable calls a door open OR broken a hole"
want inc/Feature.h 'DoorFlags & DF_SECRET' \
    "isPassable keeps a secret door solid, as Door::SetImage does"
want src/Feature.cpp 'DoorFlags & \(DF_OPEN \| DF_BROKEN\)' \
    "Door::SetImage still decides At(x,y).Solid on that same pair"
want src/Feature.cpp 'DoorFlags &= ~DF_BROKEN' \
    "Door::SetImage clears a stale orientation brand (inc-95d)"
want src/Djikstra.cpp 'dr->isPassable\(\)' \
    "Map::RunOver routes through a broken doorway (inc-8zu)"
want src/Monster.cpp '\(Door\*\)f\)->isPassable\(\)' \
    "Monster movement does not try to open a hole (inc-wj8)"

# The readers must not have grown a DF_OPEN-only passability test again. Only
# these two files: Player.cpp asks "is it open, so should I close it?", which
# is a different question and correctly uses DF_OPEN alone.
for f in src/Djikstra.cpp src/Monster.cpp; do
    if grep -nE 'DoorFlags & DF_OPEN' "$f" > /dev/null; then
        printf '  FAIL  %s tests DF_OPEN alone again\n' "$f"
        grep -nE 'DoorFlags & DF_OPEN' "$f" | sed 's/^/        /'
        FAIL=1
    else
        printf '  ok    %s asks no DF_OPEN-only question\n' "$f"
    fi
done

# ---------------------------------------------------------------------------
# Half two: the live run.
echo
echo "--- live (seed $SEED, $KEYS) ---"

if [ ! -x ./incursion-headless ]; then
    echo "  INCONCLUSIVE: ./incursion-headless not built."
    echo "                Run: BACKEND=posix ./build_macos.sh"
    exit 2
fi

RUN="$ROOT/logs/runs/broken-door-$$"
mkdir -p "$RUN/logs" || exit 2
if ! INCURSION_DOOR_PROBE=1 INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "$KEYS" "$SEED" > "$RUN/harness.txt" 2>&1; then
    echo "  INCONCLUSIVE: the headless run did not finish. See $RUN/harness.txt"
    exit 2
fi

LOG="$RUN/logs/doorprobe.log"
if [ ! -f "$LOG" ]; then
    echo "  INCONCLUSIVE: no $LOG was written, so the probe never fired."
    echo "                Check DoorProbeEnabled() in src/Feature.cpp."
    exit 2
fi

analyse < "$LOG"
LIVE=$?

echo
if [ "$LIVE" -eq 2 ]; then
    echo "INCONCLUSIVE: the source rule holds, the live run measured nothing."
    exit 2
fi
if [ "$FAIL" -ne 0 ] || [ "$LIVE" -ne 0 ]; then
    echo "BROKEN DOORS: inc-8zu, inc-wj8 or inc-95d has regressed. Run"
    echo "              $0 --selftest to confirm this check still works,"
    echo "              then read $LOG."
    exit 1
fi
rm -rf "$RUN"
echo "PASS: one predicate, every reader asks it, and no door ended the run"
echo "      closed and branded broken in a readable doorframe."
exit 0
