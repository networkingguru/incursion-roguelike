#!/bin/bash
# gate: live
# gate-serial: writes fixed scratch paths logs/aid-casting-bonus-* and rm -rf's them
# A positive A_AID bonus (Bless, Divine Favor, a luck or sacred bonus) MUST
# reach all five casting attributes, as a negative one always does (bd inc-9uuj).
#
# THE DEFECT. src/Values.cpp's Creature::StackBonus, case A_AID, adds the bonus
# to A_ARC, A_DIV, A_SOR, A_PRI and A_BAR. Creature::AddBonus, case A_AID,
# listed only A_ARC and A_DIV, so a positive bonus never reached a druid
# (A_PRI), sorcerer (A_SOR) or bard (A_BAR). A negative bonus is sent to
# StackBonus first, so a penalty did reach them. Each point of a casting
# attribute is worth 5 points of spell chance (Character::SpellRating).
#
# THE ORACLE is the spell description's own "Chance:" line, which prints the
# casting-attribute term as "+N% primal" / "+N% arcane" (src/Help.cpp). No probe.
#
# A test god (tools/fixtures/aid-casting-bonus-god.irh, spliced onto a scratch
# copy of lib/main.irc under logs/ only) grants a +5 morale A_AID bonus when
# joined. Each subject is run twice -- without the god (base) and with it (aid)
# -- and the term must rise by exactly 5 * 5 = 25 points:
#
#   orc mage   arcane term   the control: A_ARC was never missing
#   druid      primal term   the rule under test: A_PRI was missing
#
# A run that prints no Chance line is a FAIL. A casting term the engine omits
# because it is zero reads as +0; the aid run must then show the kind and +25.
#
# PROVED RED by --prove-red: the mutation deletes the three added WESMAX lines
# and rebuilds. The druid then reads +0 and this check exits 1.
#
# Usage: tools/check_aid_casting_bonus.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"
[ -f tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav ] || _check_die 2 \
    "the frozen subject druid-shoulder-metal-seed7-opt0822.sav is missing."
[ -f tools/fixtures/chars/orc-mage-seed4-opt0822.sav ] || _check_die 2 \
    "the frozen subject orc-mage-seed4-opt0822.sav is missing."

# Scratch module: a copy of lib/ under logs/, with the test god appended to the
# END of main.irc (the append-only position). The tracked lib/ is never touched.
SCRATCH="$CHECK_ROOT/logs/aid-casting-bonus/module"
build_scratch() {
    rm -rf "$SCRATCH"
    mkdir -p "$SCRATCH/mod" "$SCRATCH/save" "$SCRATCH/logs"
    cp -Rf "$CHECK_ROOT/lib" "$SCRATCH/lib" || _check_die 2 "could not copy lib/"
    ln -sfn "$CHECK_ROOT/inc" "$SCRATCH/inc"
    cat "$CHECK_ROOT/tools/fixtures/aid-casting-bonus-god.irh" \
        >> "$SCRATCH/lib/main.irc"
    INCURSIONPATH="$SCRATCH/" ./incursion-headless -compile main.irc \
        < /dev/null > "$SCRATCH/compile.log" 2>&1
    if [ ! -f "$SCRATCH/mod/Incursion.Mod" ]; then
        echo "--- compile output ---"
        tail -30 "$SCRATCH/compile.log"
        _check_die 2 "the scratch module did not compile"
    fi
}

# term_of <char fixture> <keys> -> prints "<signed number> <kind>" for the
# casting term, "+0 none" when the Chance line has no such term (the engine
# omits a zero term), or nothing when no Chance line was read at all.
term_of() {
    local sav="$1" keys="$2" dir
    dir="$(mktemp -d "$CHECK_ROOT/logs/runs/aid-casting.XXXXXX")"
    mkdir -p "$dir/mod"
    cp -f "$SCRATCH/mod/Incursion.Mod" "$dir/mod/Incursion.Mod"
    export INCURSION_LOAD="$sav"
    export INCURSION_RUN_DIR="$dir"
    check_run "$keys" 4 >&2
    unset INCURSION_RUN_DIR INCURSION_LOAD
    grep -qh "Chance:" "$CHECK_RUN"/logs/screens/*spell*.txt 2>/dev/null || return 0
    local t
    t="$(grep -hoE "[+-][0-9]+% (primal|arcane|divine|sorcery|bardic)" \
        "$CHECK_RUN"/logs/screens/*spell*.txt | head -1 | sed -E 's/% / /')"
    echo "${t:-+0 none}"
}

# One subject: base and aid terms must be the same kind and differ by 25.
judge() { # <label> <fixture> <aid keys>
    local label="$1" sav="$2" base aid bn bk an ak
    base="$(term_of "$sav" tools/keys/aid-casting-bonus-base.keys)"
    aid="$(term_of "$sav" "$3")"
    echo "  $label: base [${base:-<none>}]  with +5 A_AID [${aid:-<none>}]"
    if [ -z "$base" ] || [ -z "$aid" ]; then
        echo "FAIL: $label printed no casting term, so nothing was measured."
        failures=$((failures+1)); return
    fi
    read -r bn bk <<< "$base"
    read -r an ak <<< "$aid"
    if [ "$bk" != "none" ] && [ "$bk" != "$ak" ]; then
        echo "FAIL: $label base reads '$bk' but the aid run reads '$ak'."
        failures=$((failures+1)); return
    fi
    if [ $((an - bn)) -ne 25 ]; then
        echo "FAIL: $label casting term rose by $((an - bn)) (aid run: '$ak'); a +5 A_AID bonus is worth 25."
        failures=$((failures+1))
    fi
    CHECK_EXPECTS=$((CHECK_EXPECTS+1))
}

do_check() {
    echo "Positive A_AID bonus reaches every casting attribute (inc-9uuj)"
    echo "options:      $CHECK_OPTIONS"
    echo "scratch module: $SCRATCH"
    echo
    build_scratch
    mkdir -p "$CHECK_ROOT/logs/runs"
    failures=0
    judge "orc mage (arcane, control)" tools/fixtures/chars/orc-mage-seed4-opt0822.sav tools/keys/aid-casting-bonus-aid.keys
    judge "druid (primal)" tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav tools/keys/aid-casting-bonus-aid-wizard.keys
    [ "$failures" -eq 0 ] || CHECK_FAIL=1
}

do_check
check_done "a +5 A_AID bonus raises the arcane and the primal casting term by 25 each (inc-9uuj)"
