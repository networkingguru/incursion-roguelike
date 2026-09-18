#!/bin/bash
# gate: live
# When the PLAYER casts the priest spell Heal on himself, does it cure all
# nine non-PARALYSIS maladies its "and EA_HEALING" clauses name? (bd inc-xr8i)
#
# THE NINE: BLIND, CONFUSED, DISEASED, STUNNED, POISONED, HALLU, BLEEDING,
# CHOKING, WOUNDED. PARALYSIS is a separate, later design decision and is
# deliberately never afflicted or checked here -- it stays in lib/pspells.irh
# and stays out of this check.
#
# THE ROUTE. tools/keys/heal-maladies.keys affects the player with all nine
# at once via a test god (tools/fixtures/heal-maladies-god.irh, spliced onto
# a SCRATCH copy of lib/main.irc, never the tracked file), dumps a debug
# "Stati" listing as a CONTROL (all nine must be named), teaches Heal via
# wizard "Learn Any Spell" and casts it on himself from the Use menu ([u]
# Innate Heal), then dumps the same listing again. See the key script's own
# header for why this route, and for the file:line evidence behind it.
#
# THE FIX UNDER TEST. lib/pspells.irh's Priest / Scroll Spell "Heal;spell"
# declares xval: HEAL_HP|HEAL_XP|HEAL_ATTR|HEAL_ALL_MALADIES|HEAL_FATIGUE.
# HEAL_ALL_MALADIES unconditionally calls RemoveStati on each of the ten
# maladies it names, nine of which this check watches (src/Effects.cpp:2362-
# 2378).
#
# THREE VERDICTS, per malady and overall. UNMEASURED means the control never
# showed one or more of the nine -- the affliction never landed, so nothing
# below was tested for that malady. FAIL means at least one malady's control
# landed but still shows in the after-dump. PASS means all nine landed and
# all nine are gone after the cast.
#
# PROVING IT RED costs no tracked file: _build_scratch copies lib/ under
# logs/ and, in mode "break", deletes the nine "and EA_HEALING { xval:
# HEAL_MALADY; yval: <MALADY>; }" clauses from that COPY of lib/pspells.irh
# only, leaving Heal's four working flags (HEAL_HP|HEAL_XP|HEAL_ATTR|
# HEAL_FATIGUE) untouched. That is the spell as it stood before this fix. The
# mutation counts what it removed and dies with exit 2 if the count is not
# nine, so a mutation that silently matches nothing cannot pass as red. The
# test god is spliced onto every scratch build, mutated or not -- it is the
# affliction route, not part of what --prove-red is proving. --prove-red only
# runs when the ordinary measurement is green: it wants a red-to-green pair
# to prove anything, and it says so instead of running when there is no
# green to start from.
#
# Usage: tools/check_heal_maladies.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

MALADIES=(BLIND CONFUSED DISEASED STUNNED POISONED HALLU BLEEDING CHOKING WOUNDED)

PROVE_RED=0
[ "${1:-}" = "--prove-red" ] && PROVE_RED=1

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

# Build a scratch copy of lib/ under logs/, with tools/fixtures/heal-
# maladies-god.irh appended (the affliction route -- present in every
# scratch build, mutated or not). $1 is the directory name; $2, when
# "break", also deletes the nine "and EA_HEALING { xval: HEAL_MALADY;
# yval: <MALADY>; }" clauses from that COPY of lib/pspells.irh only -- the
# tracked file is never touched. The count of deleted lines must be exactly
# nine or the mutation dies with exit 2, so a pattern that stops matching
# (because the declaration changed again) cannot pass as a silent no-op.
_build_scratch() {
    local name="$1" mode="${2:-keep}" dir
    dir="$CHECK_ROOT/logs/$name"
    rm -rf "$dir"
    mkdir -p "$dir/mod" "$dir/save" "$dir/logs"
    cp -Rf "$CHECK_ROOT/lib" "$dir/lib" || _check_die 2 "could not copy lib/"
    ln -sfn "$CHECK_ROOT/inc" "$dir/inc"
    cat "$CHECK_ROOT/tools/fixtures/heal-maladies-god.irh" >> "$dir/lib/main.irc"

    if [ "$mode" = break ]; then
        local removed
        removed=$(perl -ni -e '
            if (/^\s*and EA_HEALING \{ xval: HEAL_MALADY; yval: \w+; \}\s*$/) {
                $c++;
            } else {
                print;
            }
            END { print STDERR (defined $c ? $c : 0); }
        ' "$dir/lib/pspells.irh" 2>&1)
        [ "$removed" = 9 ] || _check_die 2 \
            "--prove-red removed $removed 'and EA_HEALING' malady lines from lib/pspells.irh, expected 9"
    fi

    INCURSIONPATH="$dir/" ./incursion-headless -compile main.irc \
        < /dev/null > "$dir/compile.log" 2>&1
    if [ ! -f "$dir/mod/Incursion.Mod" ]; then
        echo "--- compile output ---"
        tail -30 "$dir/compile.log"
        _check_die 2 "the scratch module ($name) did not compile"
    fi
    printf '%s' "$dir"
}

# Run the key script against a scratch module and read every malady's name
# out of the debug "Stati" dump, control and after. Sets CONTROL_MISSING and
# AFTER_STILL (space-separated malady lists) rather than printing a result to
# capture: this calls check_run, which sets CHECK_RUN in this same shell, and
# a $(...) capture would run it in a subshell and lose that.
_read_run() {
    local dir="$1" mal
    INCURSION_RUN_DIR="$dir" check_run tools/keys/heal-maladies.keys 1

    CONTROL_MISSING=()
    check_screens '*control*'
    for mal in "${MALADIES[@]}"; do
        grep -qF "$mal from " "${CHECK_SCREENS[@]}" || CONTROL_MISSING+=("$mal")
    done

    AFTER_STILL=()
    check_screens '*after*'
    for mal in "${MALADIES[@]}"; do
        grep -qF "$mal from " "${CHECK_SCREENS[@]}" && AFTER_STILL+=("$mal")
    done
}

_report_run() {
    echo "    control missing: ${CONTROL_MISSING[*]:-none}"
    echo "    after still present: ${AFTER_STILL[*]:-none}"
}

echo "--- measuring: does the player's own Heal cure all nine maladies? ---"
DIR=$(_build_scratch heal-maladies-fixed keep)
_read_run "$DIR"
_report_run

rc=0
if [ "${#CONTROL_MISSING[@]}" -gt 0 ]; then
    echo "  UNMEASURED  control never showed: ${CONTROL_MISSING[*]}"
    rc=2
elif [ "${#AFTER_STILL[@]}" -gt 0 ]; then
    echo "  FAIL  Heal, cast by the player, left standing: ${AFTER_STILL[*]}"
    rc=1
else
    echo "  ok    Heal, cast by the player, cured all nine maladies"
fi

if [ "$PROVE_RED" = 1 ]; then
    echo
    if [ "$rc" != 0 ]; then
        echo "--- prove-red skipped: the ordinary run is not green (exit $rc);" \
             "nothing to prove a red-to-green pair against ---"
    else
        echo "--- prove-red: the same run against the upstream HEAL_MALADY declaration ---"
        RDIR=$(_build_scratch heal-maladies-red break)
        _read_run "$RDIR"
        _report_run
        if [ "${#CONTROL_MISSING[@]}" -eq 0 ] && \
           [ "${#AFTER_STILL[@]}" -eq "${#MALADIES[@]}" ]; then
            echo "  ok    the unfixed declaration leaves all nine maladies standing"
        else
            echo "  FAIL  the mutation did not go fully red, so this check measures nothing"
            rc=1
        fi
    fi
fi

echo
case "$rc" in
    0) echo "PASS: Heal, cast by the player himself, cures all nine maladies."
       exit 0 ;;
    2) echo "UNMEASURED: not every malady's affliction landed."
       echo "      screens: ${CHECK_RUN:-<no run>}/logs/screens"
       exit 2 ;;
    *) echo "FAIL: Heal, cast by the player himself, does not cure every malady."
       echo "      screens: ${CHECK_RUN:-<no run>}/logs/screens"
       exit 1 ;;
esac
