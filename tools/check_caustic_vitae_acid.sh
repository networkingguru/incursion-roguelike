#!/bin/bash
# gate: live
# inc-aiw5: Caustic Vitae must deal acid damage, so an acid-immune victim
# takes only the half its own description says cannot be resisted.
#
# The effect (lib/pspells.irh:1371) declares no xval, so src/Magic.cpp:560
# reads its damage type as 0 = AD_NORM, and the EF_HALF_UNTYPED split at
# src/Effects.cpp:251 sends BOTH halves as AD_NORM. An acid-immune victim
# therefore takes the full damage; with `xval: AD_ACID;` it takes only the
# unresistible half. The control run is the same cast at the same level on a
# bugbear with no acid resistance, which must still take the full damage.
#
# WHAT THE NUMBERS ARE. Caustic Vitae at effective caster level 2 rolls
# 2d8 + Wis mod (3), and the EF_HALF_UNTYPED split damages the victim twice,
# each time for the same halved value D that the game's own combat-numbers
# line prints ("Damage: 2d8+3 = D ..."). So a victim with no resistance loses
# 2*D (both halves), and an acid-immune victim must lose only D (the AD_NORM
# half; the AD_ACID half is negated). The oracle is the victim's own HP line
# in "Examine Nearby Things", before and after the cast.
#
# D is at least 3 at this level (min roll 2+3 = 5, halved to 3), which is what
# separates D from 2*D by a margin no rounding can bridge.
#
# A run that cannot produce the victim's HP before and after, or the game's
# damage line, or a hit at all, is a FAIL and never a pass: a green result from
# a session that never reached the state under test is the mistake this
# directory guards against (inc-loa.3).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=3
OPTIONS=tools/fixtures/options-2026-08-22.dat

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# The victim's current HP: the FIRST 'HP: cur/max' line that carries 'Subdual:'
# is the examined creature's; the status-bar line below it carries 'GP:'
# instead. Prints nothing if no such line exists -- the caller turns that
# silence into a FAIL.
_hp_of() { # <dump file>
    sed -n -e 's/^HP: *\([0-9][0-9]*\)\/.*Subdual:.*/\1/p' -e 't done' -e 'b' -e ':done' -e 'q' "$1" 2>/dev/null
}

# The game's own damage figure D for the victim, printed once per combat window.
# Every "Damage: NdM+B = N ..." line names the victim and carries the same N;
# take the unique value, and fail loudly if two different values appear (the
# run then measured something other than this one cast).
_half_dmg_of() { # <messages dump>
    local vals
    vals="$(sed -n 's/.*Damage: *[0-9]*d[0-9]*\(+[0-9]*\)\{0,1\} *= *\([0-9][0-9]*\).*/\2/p' "$1" 2>/dev/null | sort -u)"
    case "$vals" in
        "") return 1 ;;
        *$'\n'*) return 2 ;;
        *) printf '%s\n' "$vals" ;;
    esac
}

# Run one key script in its own sandbox directory and echo the run directory on
# success; the harness report goes to the caller's stdout untouched.
_run_one() { # <keyscript> <tag>
    local keys="$1" tag="$2" out status
    local run="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-$tag"
    out="$(INCURSION_OPTIONS="$OPTIONS" INCURSION_RUN_DIR="$run" \
        tools/headless.sh "$keys" "$SEED" 2>&1)"
    status=$?
    printf '%s\n' "$out"
    if [ "$status" -ne 0 ]; then
        echo "FAIL: tools/headless.sh exit $status running $keys"
        printf '%s\n' "$out" | sed -n '/^--- after the session ---/,$p' | sed 's/^/      /'
        return 1
    fi
    printf '%s\n' "$run"
}

# Read one run: echo "<before> <after> <loss> <D>" or nothing when any part is
# missing, which the caller turns into a FAIL.
_measure() { # <run dir>
    local run="$1" before after d
    before="$(_hp_of "$run"/logs/screens/*-target-before.txt)"
    after="$(_hp_of "$run"/logs/screens/*-target-after.txt)"
    d="$(_half_dmg_of "$run"/logs/screens/*-messages.txt)"
    if [ -z "$before" ] || [ -z "$after" ] || [ -z "$d" ]; then
        return 1
    fi
    printf '%s %s %s %s\n' "$before" "$after" "$((before - after))" "$d"
}

fail=0
echo "=== acid run: tools/keys/caustic-vitae-acid.keys (stunjelly, acid-immune) ==="
acid="$(_run_one tools/keys/caustic-vitae-acid.keys caustic-vitae-acid)" || exit 1
acid_run="$(printf '%s\n' "$acid" | tail -1)"
printf '%s\n' "$acid" | sed '$d'

echo
echo "=== control run: tools/keys/caustic-vitae-control.keys (bugbear, no acid resistance) ==="
ctl="$(_run_one tools/keys/caustic-vitae-control.keys caustic-vitae-control)" || exit 1
ctl_run="$(printf '%s\n' "$ctl" | tail -1)"
printf '%s\n' "$ctl" | sed '$d'

acid_m="$(_measure "$acid_run")"
ctl_m="$(_measure "$ctl_run")"

echo
if [ -z "$acid_m" ]; then
    echo "FAIL: the acid run produced no victim HP line or no game damage line."
    echo "      Looked under $acid_run/logs/screens."
    fail=1
fi
if [ -z "$ctl_m" ]; then
    echo "FAIL: the control run produced no victim HP line or no game damage line."
    echo "      Looked under $ctl_run/logs/screens."
    fail=1
fi
[ "$fail" -eq 0 ] || exit 1

set -- $acid_m
acid_before=$1 acid_after=$2 acid_loss=$3 acid_d=$4
set -- $ctl_m
ctl_before=$1 ctl_after=$2 ctl_loss=$3 ctl_d=$4

echo "acid:    HP $acid_before -> $acid_after  (lost $acid_loss; game damage D=$acid_d, want half = D)"
echo "control: HP $ctl_before -> $ctl_after  (lost $ctl_loss; game damage D=$ctl_d, want full = 2D)"
echo "specimens: $acid_run/logs/screens, $ctl_run/logs/screens"

# The damage figure must be large enough that "D" and "2*D" cannot be confused.
if [ "$acid_d" -lt 3 ] || [ "$ctl_d" -lt 3 ]; then
    echo "FAIL: a game damage figure below 3 (acid $acid_d, control $ctl_d) cannot tell"
    echo "      the unresistible half from the full amount."
    fail=1
fi

# The control must take both halves: this is what proves the run measured the
# spell's full damage at all.
if [ "$ctl_loss" -lt "$((2 * ctl_d - 1))" ]; then
    echo "FAIL: the unresisting control lost $ctl_loss, less than the full $((2 * ctl_d))"
    echo "      the spell deals; the run did not measure the spell's damage."
    fail=1
fi

# The acid-immune victim must NOT take both halves. Taking 2*D is exactly the
# defect: no xval, so the acid half lands as a second untyped half.
if [ "$acid_loss" -ge "$((2 * acid_d - 1))" ]; then
    echo "FAIL: the acid-immune stunjelly lost $acid_loss, the full $((2 * acid_d)) ="
    echo "      2*D, not the unresistible half D=$acid_d; Caustic Vitae's damage is"
    echo "      not acid, so its immunity never applies."
    fail=1
elif [ "$acid_loss" -gt "$((acid_d + 1))" ]; then
    echo "FAIL: the acid-immune stunjelly lost $acid_loss, more than the half D=$acid_d"
    echo "      plus rounding; part of the acid half leaked through."
    fail=1
elif [ "$acid_loss" -lt 1 ]; then
    echo "FAIL: the acid-immune stunjelly lost nothing; the unresistible half must"
    echo "      still land even when the acid half is negated."
    fail=1
fi

# And the acid half must actually be negated on the immune victim, the game's
# own words, not merely a small number.
if ! grep -qiE '(unaffected|resists)' "$acid_run"/logs/screens/*-messages.txt 2>/dev/null; then
    echo "FAIL: the acid run's messages never name an immunity ('unaffected'/'resists')"
    echo "      for the acid-immune stunjelly, so the acid half was not negated."
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: Caustic Vitae deals acid damage (immune stunjelly takes D=$acid_d,"
    echo "      unresisting bugbear takes 2D=$((2 * ctl_d)))."
    exit 0
fi
exit 1
