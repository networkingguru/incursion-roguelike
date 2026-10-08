#!/bin/bash
# gate: live
# Does character creation arrange the starting kit by the design? (bd inc-zzwm)
#
# THE DEFECT. Creation equips by accident. Character::GainItem (src/Annot.cpp)
# drops each item into the first slot that will take it, and the arranging step
# at the end of Player::Create wields Creature::getPrimaryMelee, whose "tier 2"
# test checks bow names. So a kit's first weapon wins, a proficient shield rides
# on a shoulder, and belt pouches fill with gold, tools, scrolls and spares.
#
# THE DESIGN (five rules, derived per build from the probe's facts -- see
# tools/check_kit_arrangement.py for the exact reading):
#   R1 worn gear is worn when proficient; non-proficient armour/shield is packed
#   R2 the weapon in hand has the top WepSkill, tie -> higher average damage
#   R3 no Two-Weapon Style: a proficient shield in the ready slot (blocked by a
#      two-handed weapon or two-handed shield); with it: the second-best melee
#      weapon in the ready slot
#   R4 bow on a shoulder; thrown weapons in a pouch; every other weapon packed
#   R5 pouches hold only potions, ammunition, thrown weapons, wands, herbs,
#      dusts, mushrooms; quick-use beyond five pouches goes to the pack
#
# THE ORACLE is INCURSION_KIT_PROBE (src/Create.cpp KitProbe): at the end of
# creation it logs one KIT_ITEM line per stack to logs/errors.log with its slot,
# type, group, WepSkill, damage dice and grip. It is read-only and silent with
# the variable unset. The expected arrangement is computed from those facts, so
# no class's kit is hard-coded; each build also names what it must exercise, and
# a build whose kit did not hold it is reported as NOT EXERCISED (exit 2), never
# as a pass.
#
# BUILDS (key scripts tools/keys/kit-*.keys; race and class by name):
#   warrior   Human Warrior   shield + several melee weapons in kit
#   warrior2h Human Warrior   a two-handed focus weapon: it blocks the shield
#   paladin   Human Paladin   armour and shield, a paladin's weapon choice
#   twf       Human Rogue     Two-Weapon Style feat, three one-handed blades
#   halfling  Halfling Warrior   a Small race
#   mage      Orc Mage        seed 37: rolls field plate armour it cannot use
#   rogue     Orc Rogue       seed 25: non-proficient armour worn, proficient packed
#   ranger    Human Ranger    a bow, arrows, a melee weapon
#
# Usage: tools/check_kit_arrangement.sh [build ...]   (default: all builds)
#        tools/check_kit_arrangement.sh --selftest    (rule engine only)
#   0 every rule holds on every build   1 a rule failed   2 could not measure
# Quiet: one result block per build; the run directory is under logs/runs/.
. "$(dirname "$0")/check_lib.sh"

# --selftest: the rule engine alone, on hand-written arrangements. No build.
[ "${1:-}" = "--selftest" ] && exec python3 tools/check_kit_arrangement.py --selftest

OPTIONS=tools/fixtures/options-2026-08-22.dat
# name:seed:what the kit must exercise
BUILDS="warrior:1:R1-worn,R2,R3-worn
warrior2h:1:R3-blocked
paladin:1:R2,R3-worn|R3-blocked
twf:1:R3-twf
halfling:1:R2,R3-worn
mage:37:R1-nonprof
rogue:25:R1-nonprof,R1-worn,R2-choice
ranger:1:R2,R4-bow,R5"

[ -x ./incursion-headless ] || _check_die 2 "incursion-headless is not built." \
    "Run: BACKEND=posix ./build_macos.sh"

WANT=" $* "
FAIL=0; UNMEAS=0; N=0
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
while IFS=: read -r name seed tags; do
    [ "$WANT" = "  " ] || case "$WANT" in *" $name "*) ;; *) continue ;; esac
    N=$((N + 1))
    RUN="$PWD/logs/runs/$STAMP-kit-$name"
    INCURSION_OPTIONS="$OPTIONS" INCURSION_KIT_PROBE=1 INCURSION_RUN_DIR="$RUN" \
        tools/headless.sh "tools/keys/kit-$name.keys" "$seed" > "$RUN.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "$name: UNMEASURED headless.sh exited $rc (see $RUN.out)"
        UNMEAS=1
        continue
    fi
    python3 tools/check_kit_arrangement.py "$RUN/logs/errors.log" "$name" "$tags"
    case $? in 0) ;; 1) FAIL=1 ;; *) UNMEAS=1 ;; esac
done <<< "$BUILDS"

echo
[ "$N" -gt 0 ] || _check_die 2 "no build matched: $*"
if [ "$FAIL" -ne 0 ]; then
    echo "FAIL: at least one rule failed on at least one build ($N builds run)."
    exit 1
fi
if [ "$UNMEAS" -ne 0 ]; then
    echo "INCONCLUSIVE: a build could not be measured or did not exercise its kit."
    exit 2
fi
echo "PASS: all five kit rules hold on all $N builds."
exit 0
