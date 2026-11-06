#!/bin/bash
# gate: live
# A creature that cannot fly, pushed onto a chasm square by a swap with a
# levitating ally, must leave the level without crashing the game. (bd inc-06ndv)
#
# THE DEFECT. Creature::Walk (src/Move.cpp) called TerrainEffects(), which drops
# a non-flying walker down the chasm: it leaves the level, m becomes NULL and
# F_DELETE is set. The next lines called m->RegionAt(...) and crashed.
#
# THE STAGING. INCURSION_CHASM_SWAP_PROBE=1 (src/ChasmSwapProbe.cpp) builds the
# scene before the first key: floor, one chasm square, a levitating player on it
# and a horse ally beside him (a large ally blocks, so the walk is a swap, not a pass-through). The key script walks into the ally, which runs the
# real swap path. No seed decides the scene.
# THE ORACLE. The probe's errors.log line must say ready=1, and the message log
# must say the ally fell into the chasm. A session that shows neither is
# inconclusive (exit 2). A crash is exit 1 from check_run.
#
# fact: character -- fixture human-paladin-seed4-gate, loaded by INCURSION_LOAD
# fact: map, terrain, positions -- built by INCURSION_CHASM_SWAP_PROBE, no generator involved
# fact: monsters on the level -- probe removes every monster but the player and the ally
# fact: the ally and its allegiance -- probe adds a horse and sets it as ally with addCreatureTarget
# fact: levitation of the player -- probe grants LEVITATION as a permanent stati
# fact: region sizes -- probe assigns the tight and roomy regions and prints ready=1 only when their sizes differ as the crash needs
# fact: the swap -- no roll; Creature::Walk displaces a friendly creature unconditionally
# fact: text matched -- game strings only; no seed-decided text is asserted
#
# PROVED RED (bd inc-06ndv): `tools/check_chasm_swap.sh --prove-red` removes the
# guard after TerrainEffects() (check_mutation below), rebuilds, and the session
# dies with exit 139 (ASSERT failed: 'InBounds(x,y)', inc/Map.h:285); the check
# exits 1. GREEN with the guard: PASS, both messages found, no crash.
#
# Usage: tools/check_chasm_swap.sh [--prove-red]   (0 pass, 1 fail, 2 inconclusive)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/gates/Options.Dat
FIXTURE=tools/fixtures/chars/human-paladin-seed4-gate.sav
SEED=4

check_mutation src/Move.cpp \
'	if (isDead() || !m)
		return DONE;

	if (szChange < 0)' \
'	if (szChange < 0)'

INCURSION_LOAD="$FIXTURE" INCURSION_CHASM_SWAP_PROBE=1 check_run tools/keys/chasm-swap.keys "$SEED"

ERRLOG="$CHECK_RUN/logs/errors.log"
grep -q "CHASM_SWAP stage ready=1" "$ERRLOG" 2>/dev/null || \
    _check_die 2 "the probe did not stage the scene (no 'CHASM_SWAP stage ready=1' in $ERRLOG)."

check_screens '*messages*'
check_expect "falls into the chasm" "the ally fell into the chasm"
check_expect "You displace" "the swap happened"
check_done "the ally was pushed onto the chasm, fell, and the game kept running"
