#!/bin/bash
# Regression check for Creature::Dig's divide-by-zero guard, bd inc-4ht.
#
# THE DEFECT. src/Skills.cpp computed
#
#     percent = 100 / SkillLevel(SK_MINING);
#
# with nothing floored at 1. Creature::SkillLevel (src/Create.cpp) starts its
# accumulator at 0 and only adds, and the two gates in front of the division do
# not stop a zero: the first wants a wielded WT_DIGGER, and the second aborts
# only "if (hard > pow)" -- while MaterialHardness (src/Item.cpp) answers an
# immune material with -1, not with a large number, so -1 > 0 is false and an
# untrained digger goes straight through.
#
# THE CHARACTER is a frozen fixture (bd inc-inr80), a gnome warrior with Wisdom 3
# and a plain pickaxe in the weapon hand. Every term of his Mining rating is
# known and they sum to exactly zero -- training +2, skill kit +2, attribute
# modifier -4, racial bonus 0. tools/keys/gnome-warrior-pickaxe-save.keys
# builds him and explains each term.
#
# THE ORACLE is the message Creature::Dig prints when the dig finishes:
# "Done. (<Num>~ structural integrity remaining.)", which is
# max(0, 100 - m->PercentSI), and PercentSI has just had `percent` added to it.
#
#     before the guard   100%   AArch64 SDIV answers a zero divisor with 0, so
#                                `percent` was 0 and nothing was spent
#     after  the guard     0%    100 / max(1, 0) == 100, spent in one swing
#
# so the same seed and the same script report different numbers either side of
# the one-line change. Both numbers are read off the screen; neither is a
# statistic over dice.
#
# On x86 -- upstream's platform -- there is no "before" number, because IDIV
# raises #DE on a zero divisor and the process dies. That is why this is filed
# as a base-code bug rather than a port curiosity.
#
# TWO INDEPENDENT CONFIRMATIONS, neither of which this script runs, because both
# need their own build (about ninety seconds each):
#
#   EXTRA_CXXFLAGS=-DDIG_PROBE OUT=incursion-digprobe BACKEND=posix ./build_macos.sh
#   INCURSION_BIN=./incursion-digprobe INCURSION_OPTIONS=tools/gates/Options.Dat \
#       tools/headless.sh tools/keys/dig-zero-skill.keys 1
#   ... then read <run>/logs/dig-probe.log, which prints every term:
#   dig (0,0) ter=Indestructable Rock mat=23 hard=-1 pow=0 plus=0 skill=0
#             [racial=0 train=2 kit=2 circ=0 item=0 ... attrmod=-4]
#
#   EXTRA_CXXFLAGS="-fsanitize=integer-divide-by-zero -fno-sanitize-recover=integer-divide-by-zero" \
#   EXTRA_LDFLAGS=-fsanitize=integer-divide-by-zero OUT=incursion-ubsandiv \
#   BACKEND=posix ./build_macos.sh
#   ... which on the unguarded source aborts the run with
#   "src/Skills.cpp:NNNN: runtime error: division by zero".
#
# fact: character, kit, pickaxe in the weapon hand -- fixture gnome-warrior-wis3-pickaxe-seed1-opt0822
# fact: Mining rating 0 (the divisor) -- fixture; its sheet reads "Mining +0 (0 ranks, -4 WIS, +2 train, +2 kit)"
# fact: dig target is square (0,0), Indestructable Rock -- Player::YuseMenu leaves e.EXVal/e.EYVal at 0; the fixture pins the dungeon
# fact: the result message -- deterministic arithmetic, max(0, 100 - PercentSI), no roll
# fact: settings -- INCURSION_OPTIONS tools/fixtures/options-2026-08-22.dat
#
# Usage: tools/check_dig_zero_skill.sh      (exits 0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KEYS=tools/keys/dig-zero-skill.keys
SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=tools/fixtures/chars/gnome-warrior-wis3-pickaxe-seed1-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

# FIXTURE may be overridden only to prove the INCONCLUSIVE path.
FIXTURE="${DIG_ZERO_FIXTURE:-$FIXTURE}"

OUT="$(INCURSION_OPTIONS=$OPTIONS INCURSION_LOAD=$FIXTURE tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass -- inc-loa.3.
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the run never entered a map, so it measured nothing"
    echo "$OUT" | sed 's/^/      /'
    exit 2
fi

WIELDED="$RUN/logs/screens/0001-wielded.txt"
RESULT="$RUN/logs/screens/0002-digresult.txt"

for f in "$WIELDED" "$RESULT"; do
    if [ ! -f "$f" ]; then
        echo "INCONCLUSIVE: expected screen dump missing: $f"
        exit 2
    fi
done

# The character must really be holding the pickaxe, or Dig aborts at its first
# gate and the run proves nothing.
if ! grep -q "Weapon Hand *:pickaxe" "$WIELDED"; then
    echo "INCONCLUSIVE: the pickaxe is not in the weapon hand, so Dig never got past"
    echo "      its 'You need to wield a digging implement first' gate."
    echo "      dump: $WIELDED"
    exit 2
fi

# The message wraps across two screen rows, so match only as far as the word
# the number is attached to. The engine writes '~' and the terminal draws '%'.
LINE="$(tr -s ' ' < "$RESULT" | grep -o "([0-9]*% structural" | head -1)"
if [ -z "$LINE" ]; then
    echo "INCONCLUSIVE: the dig never completed -- no 'structural integrity remaining'"
    echo "      message on the last screen. Either an earlier gate aborted it or"
    echo "      the key script no longer reaches the verb menu."
    echo "      dump: $RESULT"
    exit 2
fi

SI="$(echo "$LINE" | grep -o "[0-9]*" | head -1)"

if [ "$SI" = "100" ]; then
    echo "FAIL: one swing cost 0 structural integrity, so percent was 0, so the"
    echo "      division still ran with SkillLevel(SK_MINING) == 0. The guard is"
    echo "      gone. On x86 this same run is a SIGFPE, not a free dig."
    echo "      dump: $RESULT"
    exit 1
fi

if [ "$SI" != "0" ]; then
    echo "FAIL: expected 0% structural integrity remaining (100 / max(1,0) == 100"
    echo "      spent in one swing) but read ${SI}%. Either the character's Mining"
    echo "      rating is no longer 0 -- check lib/races.irh and the pickaxe's"
    echo "      SKILL_KIT_MOD -- or the guard was written with a different floor."
    echo "      dump: $RESULT"
    exit 1
fi

echo "PASS: a Mining rating of 0 costs 100 structural integrity in one swing"
echo "      (100 / max(1,0)), not 0. seed $SEED, $RESULT"
exit 0
