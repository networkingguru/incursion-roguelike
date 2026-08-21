#!/bin/bash
# Regression check for bd inc-tek.8.3 finding PA-03-F20: the Master Archer's
# Ranged Sneak Attack fired with every launcher in the game, not only with
# the bows its own description names.
#
# The description is explicit -- "can only be performed with a long bow or
# short bow", lib/prestige.irh:2276-2278 -- and the only test was
#     if (e.AType != A_FIRE) return NOTHING;
# A_FIRE is the generic launcher attack type; inc/Defines.h:1185 even names
# the constant "Fire [Cross]bow". So every launcher qualified.
#
# The obvious repair, an isType(T_BOW) check like the one the neighbouring
# Opportune Shot performs, would NOT have worked: T_BOW is the item type for
# every launcher, not for bows. lib/weapons.irh declares the long bow, short
# bow, arbalest, cranquin, hand crossbow, blowpipe AND sling all as T_BOW.
# The fix names the bows instead.
#
# THE ORACLE is the damage line. A sneak attack appends its own term to it,
# " +Nd6 SA" (src/Fight.cpp:5135), and the Show All Combat Rolls wizard
# switch makes the line print.
#
# THE MEASUREMENT. tools/keys/prestige-masterarcher.keys builds an
# Elf Ranger 5 / Bard 3 / Master Archer 1 and shoots three freshly summoned
# ogres, one per weapon, from one square away. Measured on this machine:
#
#   weapon     module at f5444e9^              module with the fix
#   long bow   1d4+4 +1 PBS = 7 +1d6 SA = 8    1d4+4 +1 PBS = 7 +1d6 SA = 8
#   sling      1d2+1 +1 PBS = 3 +1d6 SA = 5    1d2+1 +1 PBS = 3
#   arbalest   1d4   +1 PBS = 3 +1d6 SA = 4    1d4   +1 PBS = 3
#
# The base damage is identical on both sides; only the SA term moves.
#
# WHY A FRESH OGRE PER SHOT. Sneak attack damage needs the victim off-guard,
# flanked or surprised, and the attacker within three squares
# (src/Fight.cpp:5113-5115). Monster::Initialize sets FFCount to 20 on every
# new monster (src/Monster.cpp:1446) and isFlatFooted() is FFCount > 5, so a
# monster is off-guard on the turn it appears -- and a strike resets both
# fighters' FFCount to zero (src/Fight.cpp:3039-3040), so the same monster
# cannot serve twice. An ogre rather than a kobold because a kobold dies to
# the first hit and the sneak attack block is skipped for a dead victim.
#
# Usage: tools/check_masterarcher_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=7
KEYS=tools/keys/prestige-masterarcher.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

OUT="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens"

for want in archer bowlog slinglog crossbowlog; do
    if ! ls "$SCR"/*-"$want".txt >/dev/null 2>&1; then
        echo "FAIL: the run never reached the $want dump."
        echo "$OUT" | tail -10
        exit 1
    fi
done

# Guard first. If the build stops producing a Master Archer -- an entry
# requirement changed, the prestige menu moved -- the assertions below would
# fail for the wrong reason.
if ! grep -q "Master Archer 1" "$SCR"/*-archer.txt; then
    echo "INCONCLUSIVE: the character is not a Master Archer, so the key"
    echo "              script has rotted. Nothing was measured."
    grep -m2 "Class\|Archer" "$SCR"/*-archer.txt | head -2
    exit 1
fi
echo "  ok: a Ranger 5 / Bard 3 / Master Archer 1 exists"

# The last damage line in each log is the shot that log was taken for. The
# earlier ones are the shots before it, still in the message history.
shot() { grep -h "Damage:" "$SCR"/*-"$1".txt | grep -v "Aust's\|Ogre's" | tail -1; }

fail=0

BOW="$(shot bowlog)"
SLING="$(shot slinglog)"
BOLT="$(shot crossbowlog)"

for pair in "long bow:$BOW" "sling:$SLING" "arbalest:$BOLT"; do
    name="${pair%%:*}"
    line="${pair#*:}"
    if [ -z "$line" ]; then
        echo "FAIL: the $name shot produced no damage line at all -- it missed,"
        echo "      or it never happened. Nothing was measured."
        exit 1
    fi
done

# The control: a long bow is what the description allows, so it MUST still
# sneak attack. Without this the test would pass on a build that had simply
# broken the ability outright.
if echo "$BOW" | grep -q "d6 SA"; then
    echo "  ok: the long bow still sneak attacks -- ${BOW#*Damage: }"
else
    echo "FAIL: the long bow does not sneak attack either, so the ability is"
    echo "      broken rather than narrowed."
    echo "      $BOW"
    fail=1
fi

for pair in "sling:$SLING" "arbalest:$BOLT"; do
    name="${pair%%:*}"
    line="${pair#*:}"
    if echo "$line" | grep -q "d6 SA"; then
        echo "FAIL: the $name still sneak attacks, which the class description"
        echo "      forbids."
        echo "      $line"
        fail=1
    else
        echo "  ok: the $name does not sneak attack -- ${line#*Damage: }"
    fi
done

if [ "$fail" = 0 ]; then
    echo "PASS: the Master Archer's Ranged Sneak Attack fires with a bow and"
    echo "      with nothing else, which is what her own description says"
    exit 0
fi
exit 1
