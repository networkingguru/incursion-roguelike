#!/bin/bash
# gate: live
# Does Monster::SeneschalPromote still promote a follower through its kill
# tally exactly as src/Social.cpp intends? (bd inc-e46n)
#
# The promotion is driven by SENESCHAL_TALLY (Mag, capped 32767): a rung is
# applied once the tally reaches 400 * max(1,newCR), the new CR is not over the
# leader's SK_SENESCHAL, the rung is addable, and the leader's command pool can
# afford XCR(newCR). Monster::SeneschalKill credits the tally when the
# follower lands a killing blow, which reaches the tally through Creature::Death.
#
# The build has no way to reach a tally of 400 in a scripted session, so the
# oracle is the opt-in probe (INCURSION_SENESCHAL_PROBE=1), which writes one
# line per case to logs/seneschal.log. This check reads that log and pins every
# case: threshold, remainder under the threshold, a multi-rung jump, the tally
# ceiling, a budget refusal that sets the one-time flag, a free (XCR 0/rival)
# rung, an animal, a dominated charme, a sapient undead, a random undead
# refused without a script error, and a follower kill crediting the tally
# through Creature::Death. run.log must end with DONE and carry no
# INCONCLUSIVE line.
#
# Needs a built headless binary:  BACKEND=posix ./build_macos.sh
# Usage: tools/check_seneschal.sh [--prove-red]
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

# Break the one line every promotion passes through: AddTemplate appends the
# new rung, so removing it stops all promotion and the probe's case=promote,
# case=multi, case=undead and case=ceiling lines move.
check_mutation src/Social.cpp \
    '        AddTemplate(rung[next]);' \
    '        /* mutated */;'

export INCURSION_SENESCHAL_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav
check_run tools/keys/template-alignment.keys 1

SENESCHAL_LOG="$CHECK_RUN/logs/seneschal.log"

if [ ! -f "$SENESCHAL_LOG" ]; then
    printf '  FAIL  no probe log at %s\n' "$SENESCHAL_LOG"
    CHECK_FAIL=1
else
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    printf '  ok    probe log exists: %s\n' "$SENESCHAL_LOG"

    if grep -q '^DONE$' "$SENESCHAL_LOG" && [ "$(tail -1 "$SENESCHAL_LOG")" = DONE ]; then
        printf '  ok    log ends with DONE\n'
    else
        printf '  FAIL  log does not end with DONE\n'
        CHECK_FAIL=1
    fi

    if grep -qF 'INCONCLUSIVE' "$SENESCHAL_LOG"; then
        printf '  FAIL  log carries an INCONCLUSIVE line:\n'
        grep -nF 'INCONCLUSIVE' "$SENESCHAL_LOG" | sed 's/^/        /'
        CHECK_FAIL=1
    else
        printf '  ok    log has no INCONCLUSIVE line\n'
    fi

    # cr values carry inc-dp5u's unfloored template CR (a negative sum is no longer clamped to 0).
    want='case=promote rung=skilled cr=-1 tally=0 flag=0 rating=20 base=-2 need=400
case=remainder rung=skilled cr=-1 tally=123 flag=0 rating=20
case=multi rung=veteran cr=2 tally=31167 flag=1 rating=20
case=ceiling rung=none cr=-2 tally=32767 flag=2 rating=-2
case=budget rung=none cr=-2 tally=32767 flag=1 rating=30 over=1 pool=4968 max=125
case=freebie rung=legendary cr=10 tally=21167 flag=0 rating=30
case=animal rung=none cr=0 tally=32767 flag=0 rating=30
case=dominated rung=none cr=-2 tally=32767 flag=0 rating=30
case=undead rung=skilled cr=3 tally=31567 flag=1 rating=30 int=14
case=wild-undead rung=none cr=2 tally=0 flag=0 rating=30 accepted=0
case=kill rung=none cr=-2 tally=16 flag=0 rating=0 vcr=-4 fcr=-2 dead=1'

    got="$(grep '^case=' "$SENESCHAL_LOG" || true)"
    if [ "$got" = "$want" ]; then
        CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
        printf '  ok    every case line matches the pinned evidence\n'
    else
        printf '  FAIL  case lines differ from the pinned evidence\n'
        first="$(diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | awk 'NR==1{next} {print; exit}')"
        wn="$(printf '%s\n' "$want" | grep -n '^case=' | sed -n "s/^\([0-9]*\):.*/\1/p")"
        gn="$(printf '%s\n' "$got"  | grep -n '^case=' | sed -n "s/^\([0-9]*\):.*/\1/p")"
        i=1
        while IFS= read -r wl; do
            gl="$(printf '%s\n' "$got" | sed -n "${i}p")"
            if [ "$wl" != "$gl" ]; then
                printf '        first differing case %s\n' "$i"
                printf '        want: %s\n' "$wl"
                printf '        got:  %s\n' "$gl"
                break
            fi
            i=$((i + 1))
        done < <(printf '%s\n' "$want")
        CHECK_FAIL=1
    fi
fi

ERRLOG="$CHECK_RUN/logs/errors.log"
if [ -f "$ERRLOG" ] && grep -qF 'Invalid object reference' "$ERRLOG"; then
    printf '  FAIL  errors.log contains Invalid object reference:\n'
    grep -nF 'Invalid object reference' "$ERRLOG" | sed 's/^/        /'
    CHECK_FAIL=1
else
    CHECK_EXPECTS=$((CHECK_EXPECTS + 1))
    printf '  ok    no Invalid object reference in errors.log\n'
fi

check_done "the Seneschal kill-tally promotes exactly as src/Social.cpp intends"
