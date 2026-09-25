#!/bin/bash
# gate: live
# Does the player's Rest ('z', KY_CMD_SLEEP -> EV_REST) work while POISONED,
# and do the poison's Fort saves roll during the rest? (bd inc-gmrj)
#
# THE PROBLEM. `Player::Rest` refused any non-plot rest while POISONED
# ("You're too busy dying at the moment to think about rest.") -- so did the
# inn, through the same event. A poison's saves only ever rolled one at a
# time, per real turn, in `Creature::DoTurn`; Rest does not call DoTurn, it
# advances the clock in one step. Deleting the refusal alone would have let
# the player wake still poisoned with no saves rolled at all.
#
# THE FIX. `Creature::DoTurn`'s own POISONED block moved out into
# `Creature::PoisonPulse(bool force, bool rest)` (src/Creature.cpp), shaped
# like the existing `DiseasePulse`; DoTurn's own call, `PoisonPulse(false,
# false)`, leaves DoTurn itself byte-for-byte unchanged. `Player::Rest`
# dropped the POISONED refusal, and its per-creature rest loop now rolls up
# to (the rest's turn span / the poison's own cval) saves per POISONED stati,
# using the same save logic PoisonPulse uses, ahead of that creature's
# healing so a night's poison resolves before that night's healing does.
#
# THE ROUTE. tools/fixtures/rest-poison-god.irh, spliced onto a scratch copy
# of lib/main.irc (never the tracked file), declares one test god.
# "Become Divine Champion" (wizard mode) joins it and grants 30000 favour
# outright (src/Debug.cpp), which fires its EV_BLESSING once; the handler
# calls GainPermStati(POISONED,...) with $"arsenic" (lib/threats.irh:389,
# cval 4 / sval 13 / lval 3). tools/keys/rest-poison.keys moves the character
# to depth 2 (Rest refuses depth 1 by design) and genocides the level (Rest
# also refuses while a hostile is in plain sight, and the entry chamber has
# both), then:
#
#   CONTROL  wizard "Examine Player Data" dumps the Stati list; it must name
#            POISONED, or the affliction never landed and the check is
#            UNMEASURED.
#   REFUSAL  'z' throws EV_REST (lowercase -- see the key script's own header
#            for why uppercase 'Z' matches nothing at all). The unfixed
#            engine refuses here and prints "too busy dying", with no further
#            prompt; the fixed engine asks "Confirm rest in dungeon? [yn]"
#            instead (OPT_SAFEREST is off in the pinned settings file).
#   WOKE     'y' answers the prompt and the rest runs; "You awaken feeling
#            well rested and recovered." is the rest-happened marker.
#   AFTER    the same dump again; POISONED must be gone. Seed 1 (tried 1-4,
#            all four resolve the poison with no encounter) reliably clears
#            arsenic's three-success threshold well inside one night's 360
#            possible checks at cval 4, against a barbarian's Fortitude.
#
# --PROVE-RED declares TWO mutations, because the fix has two halves and
# either one going red proves nothing about the other (docs/VERIFICATION.md
# step 2). check_mutation only ever drives the FIRST one it is given, so
# which is first is chosen by an extra argument: bare `--prove-red` proves
# the REFUSAL half (the default, unchanged); `--prove-red loop` proves the
# ROLL half. Only one runs per invocation; run both to cover the fix.
#
#   REFUSAL  reinserts `HasStati(POISONED) ||` ahead of the STONING guard --
#            the exact line the fix deleted. With the refusal back, Rest
#            aborts before the roll code ever runs, so the mutated build
#            cannot complete tools/keys/rest-poison.keys (the confirm prompt
#            it depends on never appears, so 'y' and the drain-pagination
#            SPACEs land as ordinary unbound keys and the session drifts
#            somewhere this check cannot read); --prove-red uses the shorter
#            tools/keys/rest-poison-red.keys instead, which stops right
#            after the refusal -- see that script's own header.
#   LOOP     neutralises just the roll loop's bound (`r < turns` -> `r <
#            0`), leaving the refusal fixed. Rest then runs to completion --
#            the full key script is used -- but PoisonPulse is never called,
#            so the player wakes still POISONED: the "overcome the arsenic"
#            and "the poison resolved" assertions must go red on their own.
#
# check_mutation (tools/check_lib.sh) owns the apply/rebuild/restore dance
# for whichever one runs, and its restore is a trap, so an interrupted
# --prove-red cannot leave the tracked source mutated.
#
# Usage: tools/check_rest_poison.sh [--prove-red [loop]]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat
SEED=1

# Which of the two --prove-red mutations runs first (see the header). "loop"
# survives check_lib.sh's own arg parsing (it strips only "--prove-red") and
# is forwarded to every recursive re-invocation via CHECK_ARGS, so this stays
# consistent across the "before mutation" and "with the fix broken" runs.
PROVE_LOOP=0
for _rp_arg in "$@"; do
    [ "$_rp_arg" = "loop" ] && PROVE_LOOP=1
done

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

# The affliction route: a scratch copy of lib/, with the test god spliced
# onto the end of main.irc -- present for every run of this check, mutated or
# not, because it is how the player gets poisoned, not part of what
# --prove-red is proving. Never touches the tracked lib/.
SCRATCH="$CHECK_ROOT/logs/rest-poison-scratch"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/mod" "$SCRATCH/save" "$SCRATCH/logs"
cp -Rf "$CHECK_ROOT/lib" "$SCRATCH/lib" || _check_die 2 "could not copy lib/"
ln -sfn "$CHECK_ROOT/inc" "$SCRATCH/inc"
cat "$CHECK_ROOT/tools/fixtures/rest-poison-god.irh" >> "$SCRATCH/lib/main.irc"
INCURSIONPATH="$SCRATCH/" ./incursion-headless -compile main.irc \
    < /dev/null > "$SCRATCH/compile.log" 2>&1
if [ ! -f "$SCRATCH/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$SCRATCH/compile.log"
    _check_die 2 "the scratch module did not compile"
fi

_RP_REFUSAL_FROM='if (HasStati(STONING)/* || HasStati(DISEASED) */) {'
_RP_REFUSAL_TO='if (HasStati(POISONED) || HasStati(STONING)/* || HasStati(DISEASED) */) {'
_RP_LOOP_FROM='for (int32 r = 0; r < turns && t->HasStati(POISONED) &&'
_RP_LOOP_TO='for (int32 r = 0; r < 0 && t->HasStati(POISONED) &&'

if [ "$PROVE_LOOP" = 1 ]; then
    check_mutation src/Player.cpp "$_RP_LOOP_FROM" "$_RP_LOOP_TO"
    check_mutation src/Player.cpp "$_RP_REFUSAL_FROM" "$_RP_REFUSAL_TO"
else
    check_mutation src/Player.cpp "$_RP_REFUSAL_FROM" "$_RP_REFUSAL_TO"
    check_mutation src/Player.cpp "$_RP_LOOP_FROM" "$_RP_LOOP_TO"
fi

# The refusal mutation breaks tools/keys/rest-poison.keys (see the header),
# so it alone switches to the short script; the loop mutation leaves the
# refusal fixed and the rest completes normally.
if [ "${CHECK_MUTATED:-0}" = 1 ] && [ "$PROVE_LOOP" != 1 ]; then
    KEYS=tools/keys/rest-poison-red.keys
else
    KEYS=tools/keys/rest-poison.keys
fi

INCURSION_RUN_DIR="$SCRATCH" check_run "$KEYS" "$SEED"

check_screens '*control*'
check_expect "POISONED from" "the control shows the player poisoned"

check_screens '*refusal*'
check_reject "too busy dying" "rest is not refused while poisoned"
check_expect "Confirm rest in dungeon" "the dungeon-rest confirm prompt fires instead"

# Skipped only for the refusal mutation, whose short key script never dumps
# these screens at all. The loop mutation runs the full script and needs
# these to go red on their own -- that is the whole point of --prove-red loop.
if [ "${CHECK_MUTATED:-0}" != 1 ] || [ "$PROVE_LOOP" = 1 ]; then
    check_screens '*woke*'
    check_expect "awaken" \
        "the rest ran to completion (short, because the wake line's own word-wrap point shifts with whatever text precedes it)"
    check_expect "overcome the arsenic" \
        "a poison save rolled during the rest, per PoisonPulse's own message"

    check_screens '*after*'
    check_reject "POISONED from" "the poison resolved during the rest"
fi

check_done "rest works while poisoned, and the poison's saves roll during it"
