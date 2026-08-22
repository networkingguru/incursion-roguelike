#!/bin/bash
# Regression check for bd inc-9mhh: your own Spook caster demoralized you.
#
# TWO DEFECTS, one run.
#
# 1. Spook did not carry EF_ALLIES_IMMUNE (lib/wspells.irh). It is a permanent
#    mobile aura centred on its caster, and Magic::isTarget spares the caster's
#    own side only when that flag is set (src/Magic.cpp:340). A night hunter
#    taken as a companion therefore held its own master at -2 on every roll for
#    as long as it lived. Paralyzing Aura, the closest thing in the game
#    (lib/mon4.irh:519), already sets the flag.
#
# 2. Fixing 1 exposed a second, older defect. Magic::MagicHit tested immunity
#    before running a field LEAVE, and a leave only undoes what the entry
#    applied. A creature that became immune while inside a field was refused
#    the removal and kept the stati for ever, with "You are unaffected." on the
#    way out. Now a leave or an unwield skips the immunity test
#    (src/Magic.cpp).
#
# THE ORACLE is the character sheet's Hit line, which prints the morale term.
# Four states, in order, and the first two are the controls:
#
#                                        before        after
#   no bat                               Hit 6         Hit 6
#   a HOSTILE night hunter beside you     Hit 4         Hit 4   <- still works
#   tamed, and you walked out of range    Hit 6         Hit 6   <- leave works
#   walked back in, still tamed           Hit 4         Hit 6   <- the fix
#
# The hostile state is what stops a "fix" that merely switches the spell off
# from passing. The walked-out state is what stops defect 2 coming back: with
# the flag added and the leave still gated, that cell reads 4.
#
# Usage: tools/check_spook_ally.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=5
KEYS=tools/keys/spook-ally.keys
fail=0

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens"

hit() {  # $1 = screen basename; prints the Hit number, or nothing
    [ -f "$SCR/$1" ] || return
    grep -m1 "Hit:" "$SCR/$1" | sed 's/.*Hit:\([-0-9]*\).*/\1/'
}

h0=$(hit 0001-no-bat.txt)
h1=$(hit 0002-hostile-bat.txt)
h2=$(hit 0003-walked-away.txt)
h3=$(hit 0004-walked-back.txt)

if [ -z "$h0" ] || [ -z "$h1" ] || [ -z "$h2" ] || [ -z "$h3" ]; then
    echo "FAIL: one of the four screens was never taken, so nothing was measured."
    echo "$OUT" | tail -12
    exit 1
fi

# Guard first. If the character stopped being built the same way, every
# assertion below would be measuring a different creature.
if [ "$h0" != 6 ]; then
    echo "INCONCLUSIVE: the bare warrior reads Hit $h0, not 6. The key script"
    echo "              has rotted -- nothing was measured."
    exit 1
fi
echo "  ok: the bare warrior is at Hit 6"

if [ "$h1" = 4 ]; then
    echo "  ok: a hostile night hunter still demoralizes him (Hit 4)"
else
    echo "FAIL: a hostile night hunter reads Hit $h1, expected 4. Spook has been"
    echo "      switched off rather than aimed."
    fail=1
fi

if [ "$h2" = 6 ]; then
    echo "  ok: walking out of the field sheds the penalty (Hit 6)"
else
    echo "FAIL: walking out of the field reads Hit $h2, expected 6. The leave is"
    echo "      being refused on immunity again -- see defect 2 above."
    fail=1
fi

if [ "$h3" = 6 ]; then
    echo "  ok: his own tamed night hunter does not demoralize him (Hit 6)"
else
    echo "FAIL: his own tamed night hunter reads Hit $h3, expected 6."
    echo "      EF_ALLIES_IMMUNE is not reaching Spook -- check the module rebuilt."
    fail=1
fi

if [ "$fail" = 0 ]; then
    echo "PASS: an enemy's Spook still bites, your own companion's does not,"
    echo "      and either one lets go when you walk away"
    exit 0
fi
exit 1
