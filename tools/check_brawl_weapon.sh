#!/bin/bash
# Regression check for bd inc-nwk: a fist is not a sword.
#
# THE RULE. Unarmed attacks take nothing from a weapon. The accuracy, the
# speed and the enchantment of a held weapon belong to the melee slot, and a
# weapon that is not even in the character's hands belongs to no attack slot
# at all.
#
# WHAT WAS WRONG. src/Values.cpp builds all five attack modes in one loop:
#
#     case S_BRAWL: it = NULL;
#     case S_MELEE: it = meleeWep; break;
#
# The brawl arm had no break, so it fell into the melee arm and the brawl slot
# was handed the melee weapon. Every weapon bonus below -- weapon Acc, weapon
# Spd, the enchantment plus, the weapon-skill bonuses -- then landed on the
# fist.
#
# THE ORACLE is the character sheet's Brawl block, which src/Sheet.cpp:175-200
# builds from KAttr[A_HIT_BRAWL] and KAttr[A_SPD_BRAWL] and prints with the
# source of every term beside it. The sheet hides that block whenever the
# weapon hand holds a T_WEAPON, so the character in tools/keys/
# brawl-shoulder-weapon.keys holds a BOW (type T_BOW) and carries his sword on
# his back, where src/Values.cpp:301-308 still makes it the melee weapon. The
# key script's header explains the arrangement in full.
#
# MEASURED, seed 1, elf ranger, elven long sword on the left shoulder:
#
#              BEFORE                              AFTER
#   Brawl  +toHit +2 (Ranger +0, +2 weapon)   +toHit +0 (Ranger +0)
#          Speed  130% ... x 125% weapon      Speed  105%
#   Melee  +toHit +3 (Ranger +1, +2 weapon)   unchanged
#          Speed  130% ... x 125% weapon      unchanged
#
# The Melee block is the control. Without it, a build that had simply stopped
# applying weapon bonuses to anything would still pass the first two lines.
#
# Usage: tools/check_brawl_weapon.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/brawl-shoulder-weapon.keys
OPT_BYTE=121          # OPT_NATURAL_SPEED, see inc/Defines.h
WANT_BRAWL_HIT="+0"
WANT_BRAWL_SPEED=105

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}
[ -f Options.Dat ] || { echo "FAIL: no Options.Dat to base the run on"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# OPT_NATURAL_SPEED floors the brawl speed at 175%, which would hide the very
# number this check reads. Turn it off in a throwaway copy of the options, so
# the check says the same thing whatever the player has set.
python3 - "$TMP" "$OPT_BYTE" <<'PY' || exit 1
import sys, io
tmp, idx = sys.argv[1], int(sys.argv[2])
b = bytearray(io.open('Options.Dat','rb').read())
if len(b) <= idx:
    raise SystemExit("Options.Dat is %d bytes, too short for option %d" % (len(b), idx))
b[idx] = 0
io.open(tmp + '/plain.Dat','wb').write(bytes(b))
PY

out="$(INCURSION_OPTIONS="$TMP/plain.Dat" tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: that mistake is
# inc-loa.3. The sheet is only reachable from inside a map.
if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map"
    exit 1
fi
sheet="$run/logs/screens/0002-sheet1.txt"
if [ ! -f "$sheet" ]; then
    echo "FAIL: no character sheet dump at $sheet"
    echo "$out"
    exit 1
fi

# Each attack block runs from its own heading to the next one. Brawl is
# followed by Melee, and Melee by Size.
brawl="$(awk '/^ Brawl /{f=1} /^ Melee /{f=0} f' "$sheet")"
melee="$(awk '/^ Melee /{f=1} /^ Size /{f=0} f' "$sheet")"

if [ -z "$brawl" ]; then
    echo "FAIL: the sheet has no Brawl block, so this run proved nothing."
    echo "      The bow must be in the weapon hand; see the key script header."
    exit 1
fi
if [ -z "$melee" ]; then
    echo "FAIL: the sheet has no Melee block, so the control is missing."
    echo "      The sword must be on the left shoulder; see the key script header."
    exit 1
fi

echo "--- Brawl (the fist) ---"
echo "$brawl"
echo "--- Melee (the control: the sword on his back) ---"
echo "$melee"
echo

got_hit="$(echo "$brawl" | awk '/\+toHit/ {print $3}')"
got_speed="$(echo "$brawl" | awk '/Speed/ {print $2}' | tr -d '%')"

fail=0
if echo "$brawl" | grep -qi "weapon"; then
    echo "FAIL: the Brawl block names a weapon. A fist is not a sword (inc-nwk)."
    fail=1
fi
if [ "${got_hit:-}" != "$WANT_BRAWL_HIT" ]; then
    echo "FAIL: brawl +toHit is ${got_hit:-<none>}, and nothing but the class"
    echo "      trickle (${WANT_BRAWL_HIT}) may reach the fist here."
    fail=1
fi
if [ "${got_speed:-}" != "$WANT_BRAWL_SPEED" ]; then
    echo "FAIL: brawl speed is ${got_speed:-<none>}%, expected ${WANT_BRAWL_SPEED}%."
    echo "      130% is the long sword's 125% multiplier reaching the fist."
    fail=1
fi
if ! echo "$melee" | grep -qi "weapon"; then
    echo "FAIL: the Melee block names no weapon either, so weapon bonuses have"
    echo "      stopped reaching the slot they belong to. This check cannot"
    echo "      pass by taking bonuses away from everybody."
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "PASS: the fist takes nothing from the sword, and the sword still"
    echo "      counts for the melee slot."
fi
exit "$fail"
