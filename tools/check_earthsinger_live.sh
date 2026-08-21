#!/bin/bash
# Regression check for bd inc-tek.8.3 finding PA-03-F14: the Earthsinger's
# race gate refused the gnomes its own refusal message names.
#
# The gate tested dwarves and nothing else. Its two gnome clauses were
# commented out because the disabled lines named races that do not exist --
# $"Gnome, Rock" and $"Gnome, Deep" against the real "Gnome;race" and
# "Deep Gnome;race" -- so the class told a gnome he might qualify
# (lib/prestige.irh:1429-1430) and then turned him away.
#
# THE ORACLE is whether the character holds the class. tools/keys/
# prestige-earthsinger.keys builds a rock gnome bard who meets every other
# requirement -- Bardic Music, melee BAB +5, Craft 15, Endurance, Hardiness,
# and no god -- and then takes the class. On a module compiled from the
# pre-fix lib/prestige.irh the same character is refused, with the class's
# own message on screen, and never becomes an Earthsinger at all.
#
# WHAT THIS DOES NOT CHECK, and why. PA-03-F5, the Grounded Stance fix, is
# NOT tested here, for two reasons found while trying:
#
#   1. The corrected clause is "boots suppress the ability only if they are
#      magical". Item::isMagic() is `return eID || Plus` (inc/Item.h:92), and
#      every pair of boots the game can produce carries one or the other. The
#      only mundane boots in the ruleset are Item "boots" (lib/mundane.irh:150,
#      flagged IT_NOGEN, so never generated) and Item "cured leather boots"
#      (lib/weapons.irh:1309, referenced by nothing at all). Wizard mode
#      cannot make one either: the acquisition prompt has no plain-T_BOOTS
#      category, only the magical -AI_BOOTS one (src/Tables.cpp:341). So the
#      corrected test has no reachable input.
#   2. Grounded Stance does not appear to fire even when every condition it
#      states is met. A barefoot Earthsinger 2 on ordinary cave floor, not
#      levitating and on the material plane, hit a stone jelly for
#      "Damage: 1d6 = 6 vs. Arm 10 = 0" -- no " +2 GS" term, though the
#      effect appends one at lib/prestige.irh:1610 and the trap that carries
#      it is installed and permanent on the character (wizard mode's Examine
#      Player Data shows "TRAP EVENT ... (eID:Grounded Stance) [Dur -1]").
#      That is a separate defect underneath this one and has its own bead.
#
# Usage: tools/check_earthsinger_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=3
KEYS=tools/keys/prestige-earthsinger.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
DUMP="$RUN/logs/esng.txt"

if [ ! -f "$DUMP" ]; then
    echo "FAIL: the earthsinger's dump was never written to $DUMP."
    echo "      On a pre-fix module this is what the refusal looks like:"
    echo "      the run stops at @expect and the last screen dump carries"
    echo "      \"You must be of a race that has spiritual ties to...\"."
    echo "$OUT" | tail -8
    exit 1
fi

fail=0

# Guard first: he has to be the race the finding is about.
if ! grep -q "Race   Gnome" "$DUMP"; then
    echo "INCONCLUSIVE: the character is not a rock gnome, so the key script"
    echo "              has rotted. Nothing was measured."
    grep -m1 "Race" "$DUMP"
    exit 1
fi

if grep -q "Earthsinger 2" "$DUMP"; then
    echo "  ok: a rock gnome holds two levels of Earthsinger"
else
    echo "FAIL: the gnome did not reach Earthsinger 2"
    grep -m2 "Class" "$DUMP"
    fail=1
fi

# The class's own 1st and 2nd level grants, as a second witness that the
# levels are real rather than a name on a line.
for spell in "Stone Tell" "Soften Stone" "Meld into Stone"; do
    if grep -q "$spell" "$DUMP"; then
        echo "  ok: he has the class's innate spell $spell"
    else
        echo "FAIL: the class's innate spell $spell is missing"
        fail=1
    fi
done

if [ "$fail" = 0 ]; then
    echo "PASS: the Earthsinger admits the rock gnome its own refusal message"
    echo "      has always named"
    exit 0
fi
exit 1
