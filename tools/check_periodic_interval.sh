#!/bin/bash
# gate: live
# Does a PERIODIC status effect fire every Val rounds, not every Val-1?
# (bd inc-7mri)
#
# THE DEFECT. Creature::DoTurn's PERIODIC loop (src/Creature.cpp) used to
# reset its counter to 1 after firing, not 0:
#   if (!(++S->Mag % S->Val)) { S->Mag = 1; ... ReThrow(EV_EFFECT,e); }
# The pre-increment makes the FIRST firing land Val rounds after a grant with
# Mag 0, which is right. The reset to 1 then shorts every LATER firing by one
# round: a Val N timer repeated every N-1 rounds, not N. One round is 60 game
# turns (src/Main.cpp:800-802 throws EV_TURN when !(Turn%60)).
#
# THE FIXTURE. lib/ declares PERIODIC exactly once -- the Ring of
# Polymorphing, lib/m_items.irh:4713, Val 50 -- one interval, and 50 rounds
# is slow to prove spacing against. tools/fixtures/periodic-interval-gods.irh
# adds two test gods, Val 3 and Val 5, each granting a PERIODIC stati from
# its own EV_BLESSING the instant its follower reaches level 1 (the same
# call the Ring's worn-item code uses, src/Magic.cpp:745-751 ->
# GainPermStati). This check builds a SCRATCH module for it: lib/ copied
# under logs/, the fixture APPENDED to the END of the COPY's main.irc --
# never inserted mid-file, because a v1 save records each resource array's
# length and each entry's name in POSITION order, so a mid-file insert would
# slide every later resource one place and misread a save written before it
# -- compiled with the current ./incursion-headless via INCURSIONPATH, and
# run through INCURSION_RUN_DIR. No tracked file is ever touched by this
# half, so it needs no trap and no restore: the same shape
# tools/check_v1_append_survives.sh, and (on another branch)
# tools/check_rank_revocation.sh, already use, and for the same reason.
#
# WHY check_lib.sh's check_mutation IS USED, this time. The only remaining
# edit to a tracked file is the span-of---prove-red revert of
# src/Creature.cpp below, so there is no second always-on edit for
# check_mutation's own child-process re-invocation to collide with. That is
# exactly the case check_mutation is built for, and it is used here plainly.
#
# THE ORACLE. Each test god's effect prints "PERIODIC-<A|B> FIRED <turn>" the
# instant it fires. The measured gap between consecutive firings must equal
# Val rounds (Val*60 turns), across at least three firings for each of the
# two timers -- one gap alone cannot tell a fix from a lucky roll (Val 1
# looks identical broken or fixed, since 1%1 and 2%1 are both 0); two gaps in
# a row at the SAME wrong spacing is what a broken counter produces, and is
# what this check rejects.
#
# Usage: tools/check_periodic_interval.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# 1. The scratch module: lib/ copied, inc/ symlinked, the test gods appended
#    to the COPY's main.irc, compiled with the CURRENT ./incursion-headless.
#    The directory lives under logs/, not a mktemp one a trap would delete,
#    because check_run's evidence must survive this script's own exit.
MODULE="$CHECK_ROOT/logs/periodic-interval-module"
rm -rf "$MODULE"
mkdir -p "$MODULE/mod" "$MODULE/save" "$MODULE/logs"
cp -Rf "$CHECK_ROOT/lib" "$MODULE/lib" || _check_die 2 "could not copy lib/"
ln -sfn "$CHECK_ROOT/inc" "$MODULE/inc"
cat "$CHECK_ROOT/tools/fixtures/periodic-interval-gods.irh" >> "$MODULE/lib/main.irc"

[ -x ./incursion-headless ] || _check_die 2 \
    "./incursion-headless is not built. Run: BACKEND=posix ./build_macos.sh"

COMPILE_LOG="$MODULE/compile.log"
INCURSIONPATH="$MODULE/" ./incursion-headless -compile main.irc \
    < /dev/null > "$COMPILE_LOG" 2>&1
if [ ! -f "$MODULE/mod/Incursion.Mod" ]; then
    echo "--- compile output ---"
    tail -30 "$COMPILE_LOG"
    _check_die 2 "the scratch module with periodic-interval-gods.irh appended did not compile"
fi

export INCURSION_RUN_DIR="$MODULE"

# macOS ships bash 3.2, where "${arr[@]}" on a declared-but-EMPTY array is an
# unbound-variable error under this file's "set -u" -- not merely empty. Every
# array below is therefore only ever expanded as "${arr[@]:-}", and the
# resulting single empty-string placeholder is filtered back out here.
_drop_empty() { # prints each non-empty argument on its own line
    local x
    for x in "$@"; do [ -n "$x" ] && printf '%s\n' "$x"; done
}

# 2. Run the session once, and read the two timers' firing turns off the
#    screens it dumped.
A_TURNS=()
B_TURNS=()
_measure() {
    check_run tools/keys/periodic-interval.keys 1
    check_screens
    local f
    A_TURNS=()
    B_TURNS=()
    for f in "${CHECK_SCREENS[@]}"; do
        while read -r t; do A_TURNS+=("$t"); done \
            < <(grep -oE "PERIODIC-A FIRED [0-9]+" "$f" | grep -oE "[0-9]+$")
        while read -r t; do B_TURNS+=("$t"); done \
            < <(grep -oE "PERIODIC-B FIRED [0-9]+" "$f" | grep -oE "[0-9]+$")
    done
    A_TURNS=($(_drop_empty "${A_TURNS[@]:-}" | sort -n -u))
    B_TURNS=($(_drop_empty "${B_TURNS[@]:-}" | sort -n -u))
}

# <label> <want gap> <turns...> -- at least 3 firings, every consecutive gap
# exactly <want gap>. Prints the broken-counter reading (want - 60) when a
# gap misses, since that is exactly what an unfixed S->Mag = 1 produces.
_check_gaps() {
    local label="$1" want="$2"; shift 2
    local turns=() x n i gap bad=0
    for x in "$@"; do [ -n "$x" ] && turns+=("$x"); done
    n=${#turns[@]}
    if [ "$n" -lt 3 ]; then
        echo "  FAIL  $label: only $n firing(s) logged, need at least 3: ${turns[*]:-<none>}"
        return 1
    fi
    for ((i = 1; i < n; i++)); do
        gap=$(( turns[i] - turns[i-1] ))
        if [ "$gap" -ne "$want" ]; then
            echo "  FAIL  $label: ${turns[i-1]} -> ${turns[i]} is $gap turns, want $want" \
                 "$([ "$gap" -eq $((want - 60)) ] && echo "(the broken S->Mag=1 spacing)")"
            bad=1
        fi
    done
    [ "$bad" = 0 ] && {
        echo "  ok    $label: $n firings, every gap $want turns (${turns[*]})"
        return 0
    }
    return 1
}

do_check() {
    _measure
    local rc=0
    _check_gaps "PERIODIC-A (Val 3, want 180-turn gaps)" 180 "${A_TURNS[@]:-}" || rc=1
    _check_gaps "PERIODIC-B (Val 5, want 300-turn gaps)" 300 "${B_TURNS[@]:-}" || rc=1
    return "$rc"
}

# 3. The mutation this check defends: S->Mag = 0, broken back to the
#    upstream S->Mag = 1.
check_mutation src/Creature.cpp \
'            S->Mag = 0;
            EventInfo e;' \
'            S->Mag = 1;
            EventInfo e;'

echo "--- measuring PERIODIC firing intervals ---"
if do_check; then
    echo
    echo "PASS: PERIODIC fires every Val rounds, not Val-1."
    exit 0
else
    echo
    echo "FAIL: a PERIODIC timer's firing interval is not Val rounds."
    echo "      screens: ${CHECK_RUN:-<no run>}/logs/screens"
    exit 1
fi
