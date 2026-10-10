#!/bin/bash
# gate: live
# gate-serial: writes a fixed scratch module dir logs/inc-gatz-module and rm -rf's it
# inc-gatz: Thing::Move throws EV_FIELDON before it relinks the mover into the
# new square. If the field effect re-places the mover (enlarging it to a size
# with a FaceRadius runs Creature::CalcValues -> PlaceNear, src/Values.cpp:1798),
# Move then links it at the new square too, and the map audit reports
# "Thing linked at a square it does not claim".
#
# Scenario: tools/fixtures/inc-gatz-growth.irh appended to a scratch copy of
# lib/main.irc adds a monster owning a static field that grows the entrant +2
# size categories. tools/keys/inc-gatz-growth.keys walks an orc (Medium -> Huge)
# into it. Builds nothing; needs ./incursion-headless.
#
# Exit 1: the audit line is present (defect), or the run could not be read
# (the check MUST fail when it cannot tell). Exit 0: the field was entered and
# the line is absent. Exit 2: setup problem.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=1
MODULE="$ROOT/logs/inc-gatz-module"
RUN="$ROOT/logs/inc-gatz-run"

[ -x ./incursion-headless ] || { echo "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
[ -f "$OPTIONS" ] || { echo "missing $OPTIONS"; exit 2; }

rm -rf "$MODULE" "$RUN"
mkdir -p "$MODULE/mod" "$MODULE/save" "$MODULE/logs" "$RUN"
cp -Rf lib "$MODULE/lib" || exit 2
ln -sfn "$ROOT/inc" "$MODULE/inc"
cat tools/fixtures/inc-gatz-growth.irh >> "$MODULE/lib/main.irc"
INCURSIONPATH="$MODULE/" ./incursion-headless -compile main.irc < /dev/null > "$MODULE/compile.log" 2>&1
if [ ! -f "$MODULE/mod/Incursion.Mod" ]; then
    tail -20 "$MODULE/compile.log"
    echo "scratch module did not compile"; exit 2
fi

# The run uses the scratch module as its game folder (as check_periodic_interval.sh does).
INCURSION_RUN_DIR="$MODULE" INCURSION_OPTIONS="$OPTIONS" \
    tools/headless.sh tools/keys/inc-gatz-growth.keys "$SEED" > "$RUN/harness.txt" 2>&1 < /dev/null
status=$?
D="$MODULE"
echo "headless exit $status; run dir $D"

# Reached-the-scenario evidence: the field message must be on a dumped screen.
if ! grep -rqs "You swell enormously" "$D/logs/screens"; then
    echo "INCONCLUSIVE: no screen shows 'You swell enormously!' -- the field was never entered"
    exit 1
fi
if [ ! -f "$D/logs/mapaudit.log" ]; then
    echo "INCONCLUSIVE: no logs/mapaudit.log"; exit 1
fi
if grep -q "linked at a square it does not claim" "$D/logs/mapaudit.log"; then
    echo "RED: map audit found a Thing linked at a square it does not claim:"
    grep -A1 "does not claim" "$D/logs/mapaudit.log" | head -6
    exit 1
fi
echo "GREEN: field entered, audit clean"
exit 0
