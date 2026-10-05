#!/bin/bash
# gate: live
#
# inc-tmys: Monster::Initialize (src/Monster.cpp) asserts
# cHP == mHP + Attr[A_THP] after the EV_INITIALIZE events. A monster standing
# ELEVATED (in a tree) that then takes the "wildshaped druid" template shifts
# shape, gains POLYMORPH, and StatiOn calls ClimbFall (src/Move.cpp), which
# dealt 2d6 fall damage and broke the invariant.
#
# THE FIX. Monster::Initialize cannot simply decide the tree elevation after
# the events (the preferred order): the probe, like a monster summoned into a
# tree, stands ELEVATED before Initialize runs, so the template event still
# falls. Instead the fall is made fictitious while the monster is initialised:
# Monster::Initializing (inc/Creature.h) is a depth counter raised around the
# EV_INITIALIZE block, and Creature::ClimbFall returns after removing ELEVATED
# but before ThrowDmg when `isMonster() && Monster::Initializing`. ELEVATED is
# still consumed, so the witness line below still proves the path ran. The
# ASSERT and the template script are untouched.
#
# THE ORACLE is src/MonsterInitProbe.cpp under INCURSION_MONINIT_PROBE, called
# from Game::Play() (src/Main.cpp). It builds the "wildshaped druid" template
# on an elf, stands it ELEVATED (ELEV_TREE), and calls Monster::Initialize. Its
# "MONINIT_PROBE: DONE elevated_left=0" line proves the monster was built and
# that ClimbFall consumed ELEVATED; the Initialize ASSERT count in
# errors.log is the verdict.
# Exit 1 while the ASSERT fires or when it cannot
# tell; exit 0 only when the probe ran the path and no ASSERT was logged.
#
# PROVED RED (docs/VERIFICATION.md step 2) with --prove-red: removing the
# ClimbFall guard restores the 2d6 fall damage inside Initialize, the ASSERT
# fires, and this check exits 1.
#
# Usage: tools/check_monster_init_hp.sh [--prove-red]  (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

SEED=1
KEYS=tools/keys/monster-init-hp.keys
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

# The mutation this check defends: the guard ClimbFall gained for inc-tmys,
# read directly off Creature::ClimbFall. Declared before the run below so
# --prove-red intercepts here, before the (build-needing) measurement runs.
check_mutation src/Move.cpp \
'	if (isMonster() && Monster::Initializing)
		return;

' \
''

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

export INCURSION_MONINIT_PROBE=1
export INCURSION_LOAD="$LOAD"

RUN_DIR="$CHECK_ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-monster-init-hp"
INCURSION_MONINIT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$CHECK_OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR.harness.txt" 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "FAIL: no $log. Is MonsterInitProbe still called from Game::Play()?"
    exit 1
fi

lines="$(grep 'MONINIT_PROBE:' "$log")"
asserts="$(grep -c "ASSERT failed: 'cHP == mHP + Attr\[A_THP\]'" "$log")"
echo "$lines"
echo "Specimen: $log"
echo "Initialize ASSERT count: $asserts"

# Here-strings avoid the pipe/SIGPIPE false-negative described in inc-wbq9.
# DONE with elevated_left=0 proves the probe built the monster and that
# ClimbFall ran; anything else means the check cannot tell.
if ! grep -q 'MONINIT_PROBE: DONE elevated_left=0 ' <<< "$lines"; then
    echo "FAIL: the probe did not complete the elevated-then-polymorph path."
    exit 1
fi
if [ "$asserts" -ne 0 ]; then
    echo "FAIL: Initialize left cHP != mHP + THP (the ASSERT fired)."
    exit 1
fi
echo "PASS: Initialize keeps cHP == mHP + THP."
