#!/bin/bash
# gate: live
# gate-serial: writes fixed scratch paths logs/natural-one-attack-* and rm -rf's them
# A natural 1 on a melee attack roll must ALWAYS miss, whatever the total --
# the OGL rule, and the half of it the engine's own hit test omitted (bd
# inc-bp2y).
#
# THE DEFECT. src/Fight.cpp's Creature::Strike hit test read
#
#     if ((e.vHit + e.vRoll >= max(e.vDef,
#           (e.vRideCheck ? e.vRideCheck : -40))) || e.vRoll == 20)
#       e.isHit = true;
#
# while the comment above it claims "the *exact* logic of the OGL system" and
# already lists the natural-20 half of the rule. There was no natural-1 clause
# at all, so a natural 1 hit whenever the total beat the defense. The fix makes
# a natural 1 an automatic miss before the total comparison, keeps the natural
# 20 auto-hit and the e.vRideCheck term.
#
# THE ORACLE is the game's own attack roll line in the message log,
# "Attack: 1d20 (n) ... vs. Def D [hit|miss]" (src/Fight.cpp, kept by
# OPT_STORE_ROLLS). No probe: this reads what an ordinary session already tells
# the player.
#
# THE ARITHMETIC IS FORCED, THE ROLL IS PINNED. The subject is the frozen orc
# mage of tools/fixtures/chars/orc-mage-seed1-opt0822.sav (Melee +3). A test
# god (tools/fixtures/natural-one-attack-god.irh, spliced onto a scratch copy
# of lib/main.irc under logs/ only) grants +30 to hit when joined, so
# e.vHit + e.vRoll on a forced 1 is 34 -- above any summoned goblin's Defense.
# The arithmetic alone would hit on every forced roll, so only the natural-1
# clause can turn the forced 1 into a miss. INCURSION_LOF_FORCE_ROLL pins the
# d20 (src/Fight.cpp's LOFInitForcedRoll), one run per forced value:
#
#   forced 1   MUST read [miss]   the rule under test
#   forced 2   MUST read [hit]    the control: same bonus, arithmetic hits
#   forced 20  MUST read [hit]    the auto-hit is kept
#
# A run that never printed an Attack line, or whose forced value does not appear
# on it, is INCONCLUSIVE and never a pass.
#
# PROVED RED by --prove-red: the mutation `nonat1` deletes the natural-1 clause
# and rebuilds. The forced-1 case then reads [hit] and this check exits 1.
#
# Usage: tools/check_natural_one_attack.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# The mutation this check defends: the natural-1 automatic miss removed, so the
# hit test is upstream's bare comparison again. Declared before do_check runs so
# that --prove-red intercepts here, before the runs below.
check_mutation src/Fight.cpp \
'    if (e.vRoll == 1)
      e.isHit = false;
    else if ((e.vHit + e.vRoll >= max(e.vDef,' \
'    if ((e.vHit + e.vRoll >= max(e.vDef,'

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
[ -f tools/fixtures/chars/orc-mage-seed1-opt0822.sav ] || _check_die 2 \
    "the frozen subject tools/fixtures/chars/orc-mage-seed1-opt0822.sav is missing."
[ -f tools/keys/natural-one-attack.keys ] || _check_die 2 \
    "the key script tools/keys/natural-one-attack.keys is missing."

# Scratch module: a copy of lib/ under logs/, with the +30 test god appended to
# the END of main.irc (the append-only position, so every resource id keeps its
# place). The tracked lib/ is never touched.
SCRATCH="$CHECK_ROOT/logs/natural-one-attack/module"
build_scratch() {
    rm -rf "$SCRATCH"
    mkdir -p "$SCRATCH/mod" "$SCRATCH/save" "$SCRATCH/logs"
    cp -Rf "$CHECK_ROOT/lib" "$SCRATCH/lib" || _check_die 2 "could not copy lib/"
    ln -sfn "$CHECK_ROOT/inc" "$SCRATCH/inc"
    cat "$CHECK_ROOT/tools/fixtures/natural-one-attack-god.irh" \
        >> "$SCRATCH/lib/main.irc"
    INCURSIONPATH="$SCRATCH/" ./incursion-headless -compile main.irc \
        < /dev/null > "$SCRATCH/compile.log" 2>&1
    if [ ! -f "$SCRATCH/mod/Incursion.Mod" ]; then
        echo "--- compile output ---"
        tail -30 "$SCRATCH/compile.log"
        _check_die 2 "the scratch module did not compile (does A_HIT/GainPermStati exist on this branch?)"
    fi
}

# The forced roll -> expected verdict and human description. One newline-
# separated record per case, read with IFS=: so the description's spaces never
# split a case into words (the fault this phase repairs).
CASES='1:miss:forced natural 1 must miss although the total (34) beats the Defense
2:hit:forced natural 2 must hit -- same bonus, the arithmetic carries it
20:hit:forced natural 20 keeps its automatic hit'

# read_verdict <run-dir> <forced roll> -> prints the bracket word on the engine's
# own "Attack: 1d20 (<roll>) ... vs. Def ... [<word>]" line, or nothing.
read_verdict() {
    local dir="$1" roll="$2"
    grep -hoE "Attack: 1d20 \($roll\)[^]]*\[(hit|miss|threat|crit)\]" \
        "$dir"/logs/screens/*-messages.txt 2>/dev/null |
        sed -E 's/.*\[(hit|miss|threat|crit)\]$/\1/' |
        sort -u | head -1
}

do_check() {
    echo "Natural 1 on an attack roll (inc-bp2y)"
    echo "options:      $CHECK_OPTIONS"
    echo "scratch module: $SCRATCH"
    echo
    build_scratch

    mkdir -p "$CHECK_ROOT/logs/runs"

    local roll want why dir verdict failures=0
    while IFS=: read -r roll want why; do
        [ -n "$roll" ] || continue
        dir="$(mktemp -d "$CHECK_ROOT/logs/runs/natural-one-$roll.XXXXXX")"
        mkdir -p "$dir/mod"
        cp -f "$SCRATCH/mod/Incursion.Mod" "$dir/mod/Incursion.Mod"
        # tooling safety: the run dir must not exist before headless.sh links
        # the repository mod/ into it, so we pre-create mod/ with the scratch
        # module (headless's -sfn link lands beside it) exactly as
        # check_blind_fight_miss.sh and check_luck_mode.sh do.
        export INCURSION_LOAD=tools/fixtures/chars/orc-mage-seed1-opt0822.sav
        export INCURSION_RUN_DIR="$dir"
        export INCURSION_LOF_FORCE_ROLL="$roll"
        check_run tools/keys/natural-one-attack.keys 1
        unset INCURSION_RUN_DIR INCURSION_LOF_FORCE_ROLL INCURSION_LOAD

        verdict="$(read_verdict "$CHECK_RUN" "$roll")"
        echo "  forced $roll: engine says [${verdict:-<no Attack line>}] -- $why"
        if [ -z "$verdict" ]; then
            echo "FAIL: the forced-$roll session printed no 'Attack: 1d20 ($roll)' line"
            echo "      in its message log, so the rule was never measured."
            failures=$((failures+1))
            continue
        fi
        case "$want" in
            miss)
                if [ "$verdict" != "miss" ]; then
                    echo "FAIL: a forced natural 1 read [$verdict]; the OGL rule"
                    echo "      makes it an automatic miss whatever the total."
                    failures=$((failures+1))
                fi ;;
            hit)
                if [ "$verdict" = "miss" ]; then
                    echo "FAIL: a forced natural $roll read [miss] although the"
                    echo "      total beats the Defense ($why)."
                    failures=$((failures+1))
                fi ;;
        esac
        CHECK_EXPECTS=$((CHECK_EXPECTS+1))
    done <<< "$CASES"
    [ "$failures" -eq 0 ] || CHECK_FAIL=1
}

do_check
check_done "a natural 1 always misses, a natural 2 hits on the same bonus, and a natural 20 keeps its automatic hit (inc-bp2y)"
