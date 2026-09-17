#!/bin/bash
# gate: live
# Does a cosmetic random draw leave the gameplay stream where it was?
# (bd inc-rir0)
#
# WHAT IS BEING GUARDED. Every gameplay draw comes off one shared Mersenne
# Twister, and the simulation reads it in a fixed order, so the NUMBER of draws
# a session takes is part of what a seed means. A draw made for the screen
# therefore moves every later gameplay roll even though it decides nothing.
# That is measured, not feared: Character::GodMessage drew random(4) once per
# CHARACTER of the message text to shade a god's voice, so rewording a line of
# flavour text moved the stream and two games on the same seed stopped being
# the same game. 04ffaa9 fixed that site by deleting the draw; inc-rir0 added
# cosmetic_int32 (src/Base.cpp) so the next author who wants a random shade has
# somewhere safe to put it. This check is the standing proof that the somewhere
# safe really is safe.
#
# HOW IT ASKS. INCURSION_COSMETIC_BURN and INCURSION_RNG_BURN spend draws off
# one stream before the game starts (SeedCosmeticStream, src/Main.cpp). Burning
# from the cosmetic stream MUST change nothing the session does. That is the
# claim.
#
# AND WHY IT CANNOT PASS FOR THE WRONG REASON. A check that compares two
# sessions and finds them equal proves nothing if the comparison is blind -- if
# the screens were empty, or the run died the same way twice, the claim would
# "pass". So the control runs SECOND: one single draw off the GAMEPLAY stream
# must make the same comparison come out DIFFERENT. Green here means the
# cosmetic burn changed nothing AND the comparison can tell when something
# changes. Either half alone is worthless.
#
# THE SIX LEGACY COLOUR DRAWS ARE DELIBERATELY NOT CONVERTED, and this check
# does not require them to be. src/Magic.cpp:1703,1875,2079 and
# src/MakeLev.cpp:1265,3009,3020 still draw colours from the gameplay stream.
# None of them varies with content, so none can repeat the GodMessage defect,
# and moving them costs a real shift: measured 2026-09-17, converting all six
# took tools/check_wand_acid_type.sh from PASS to FAIL and moved
# tools/check_flame_tongue_undead.sh's readings from 61/45/38 to 58/42. That is
# a one-time re-baselining nobody has asked for. New presentation code uses
# cosmetic_random(); the old six stay until somebody wants to pay for them.
#
# Usage: tools/check_rng_split.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

KEYS=tools/keys/dive.keys
SEED=1
BURN=37          # 37, not 1: a stream that ignored small burns and broke on
                 # large ones would be a nastier bug than the one being guarded

# The mutation goes on the SEEDING, not on a screen: if SeedCosmeticStream ever
# routes the cosmetic burn into the gameplay generator -- the single likeliest
# way for this to rot -- the burn starts moving the session and the comparison
# below must notice. That is the failure this check exists to see.
check_mutation src/Main.cpp \
    '(void)cosmetic_int32();' \
    '(void)genrand_int32();'

# ---------------------------------------------------------------------------
# A session's gameplay, as text. The screen headers carry a key counter that
# moves with nothing but the harness, so they are cut.
session() { # session <env assignment>... -> the screens, headerless
    local out run
    out="$(env "$@" INCURSION_OPTIONS="$CHECK_OPTIONS" \
           tools/headless.sh "$KEYS" "$SEED" 2>&1 </dev/null)"
    run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
    [ -n "$run" ] || return 1
    cat "$run"/logs/screens/*.txt 2>/dev/null | sed '/^=== screen /d'
}

# The baseline goes through check_run, so the library sees a real session and
# the assertion below is counted. Comparing two texts is not an assertion the
# library can account for, and a check whose only claim is "these two blobs
# match" must still prove that either blob came from a game that was played.
check_run "$KEYS" "$SEED"
check_screens '*-final'
check_expect "HP:" "the baseline session reached gameplay, so there is something to compare"

BASE="$(cat "$CHECK_RUN"/logs/screens/*.txt 2>/dev/null | sed '/^=== screen /d')"
COSM="$(session INCURSION_COSMETIC_BURN=$BURN)" || _check_die 2 "the cosmetic-burn session produced no run directory"
GAME="$(session INCURSION_RNG_BURN=1)"         || _check_die 2 "the gameplay-burn session produced no run directory"

[ -n "$BASE" ] || _check_die 2 \
    "the baseline session drew no screens, so the comparison would compare" \
    "nothing against nothing and call it a pass."

# ---------------------------------------------------------------------------
# The claim.
if [ "$BASE" = "$COSM" ]; then
    echo "  ok    $BURN draws off the cosmetic stream changed nothing the session did"
else
    echo "  FAIL  $BURN cosmetic draws CHANGED the session"
    echo "        A draw meant for the screen moved the gameplay stream, which is"
    echo "        the whole defect cosmetic_int32 exists to prevent. Look first at"
    echo "        SeedCosmeticStream (src/Main.cpp): if the cosmetic seed or the"
    echo "        cosmetic burn reaches NextSeed() or genrand_int32(), this is why."
    printf '%s\n' "$BASE" > "$CHECK_RUN/gameplay-base.txt" 2>/dev/null
    printf '%s\n' "$COSM" > "$CHECK_RUN/gameplay-cosmetic.txt" 2>/dev/null
    CHECK_FAIL=1
fi

# The control, and it is not optional: it is what stops the line above passing
# because the comparison is blind.
if [ "$BASE" != "$GAME" ]; then
    echo "  ok    one draw off the gameplay stream DID change the session, so the"
    echo "        comparison above can tell when something moves"
else
    echo "  FAIL  a single gameplay draw changed nothing either, so this check is"
    echo "        BLIND and its first result means nothing. The sessions are not"
    echo "        reaching gameplay, or INCURSION_RNG_BURN is not being read."
    CHECK_FAIL=1
fi

check_done "a cosmetic draw leaves the gameplay stream untouched, and a gameplay draw does not"
