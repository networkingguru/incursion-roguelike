#!/bin/bash
# gate: live
# inc-0t9ol: Zen Defense gives its insight bonus to Defense only for WORN armor
# and only below Moderate encumbrance. (0 GREEN, 1 RED, 2 INCONCLUSIVE)
#
# fact: character, Zen Defense feat, Wis modifier +1 -- fixture lizardfolk-monk-seed1 (INCURSION_LOAD)
# fact: no worn armor -- the probe refuses (INCONCLUSIVE) if SL_ARMOUR is filled
# fact: Mage Armour active -- probe grants the real effect's ADJUST_ARM stati
# fact: encumbrance level -- probe stacks a long sword in the ready hand until Encumbrance() equals the level
# fact: settings -- tools/fixtures/options-2026-08-22.dat (INCURSION_OPTIONS)
# fact: Wis modifier +5 for the armor cases -- probe sets BAttr[A_WIS]=20 after the encumbrance cases; the check asserts wis=5 on each
# fact: worn armor -- probe puts "cord armour" (light) or "hide armour" (medium) in SL_ARMOUR; the check asserts the armtype is not read, only insight and enc 0
# fact: no roll is read; the check turns on no dice and no map
#
# THE ORACLE is INCURSION_ZEN_DEFENSE_PROBE (src/ZenDefenseProbe.cpp), which
# prints the BONUS_INSIGHT component of A_DEF after CalcValues:
#   ZEN_DEFENSE case=<name> enc=<n> armtype=<n> insight=<n> wis=<n>
# The expected values are literal here, not computed by the probe. The Wis
# modifier is +1 on this fixture, so "full" is 1 and "none" is 0.
#   bare, bare_again, light : 1 (control, passes before the rules change)
#   mage_armour             : 1 (R1; fails before the change)
#   moderate, heavy         : 0 (R2; fails before the change)
# With Wis modifier +5 (full 5, half 3):
#   bare_wis5, spirit_armour, mage_armour_wis5 : 5 (spell armor ignored; R1)
#   worn_light              : 3 (control, passes before the change)
#   worn_medium             : 0 (control, passes before the change)
#   worn_light_plus_mage    : 3 (spell ignored over worn light; R1)
#
# Usage: tools/check_zen_defense.sh [seed]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SEED="${1:-1}"
OPTS="tools/fixtures/options-2026-08-22.dat"
FIX="tools/fixtures/chars/lizardfolk-monk-seed1.sav"
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
RUN="logs/zen-defense-$$"
rm -rf "$RUN"
INCURSION_ZEN_DEFENSE_PROBE=1 INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTS" \
    INCURSION_LOAD="$FIX" tools/headless.sh tools/keys/zen-defense.keys "$SEED" > "$RUN.out" 2>&1
LOG="$RUN/logs/errors.log"
[ -f "$LOG" ] || { echo "INCONCLUSIVE: no errors.log; see $RUN.out"; exit 2; }
grep -v '^    ' "$LOG" | grep 'ZEN_DEFENSE' > "$RUN.lines"
grep -q 'ZEN_DEFENSE INCONCLUSIVE' "$RUN.lines" && {
    echo "INCONCLUSIVE: $(grep -m1 'ZEN_DEFENSE INCONCLUSIVE' "$RUN.lines")"; exit 2; }
grep -q 'ZEN_DEFENSE COMPLETE' "$RUN.lines" || {
    echo "INCONCLUSIVE: probe did not complete ($RUN.lines)"; exit 2; }

fail=0
check() { # case expected-insight expected-enc [wis, default 1]
    local line ins enc wis
    line="$(grep "case=$1 " "$RUN.lines" | head -1)"
    [ -n "$line" ] || { echo "INCONCLUSIVE: no line for case $1"; exit 2; }
    ins="$(echo "$line" | sed -n 's/.* insight=\(-\{0,1\}[0-9]*\).*/\1/p')"
    enc="$(echo "$line" | sed -n 's/.* enc=\([0-9]*\).*/\1/p')"
    wis="$(echo "$line" | sed -n 's/.* wis=\(-\{0,1\}[0-9]*\).*/\1/p')"
    local ewis="${4:-1}"
    [ "$wis" = "$ewis" ] || { echo "INCONCLUSIVE: Wis modifier is $wis, case $1 needs $ewis"; exit 2; }
    [ "$enc" = "$3" ] || { echo "INCONCLUSIVE: case $1 encumbrance $enc, wanted $3"; exit 2; }
    if [ "$ins" = "$2" ]; then echo "  PASS $1: insight=$ins (enc=$enc)"
    else echo "  FAIL $1: insight=$ins, expected $2 (enc=$enc)"; fail=1; fi
}
# EN_NONE 0, EN_LIGHT 1, EN_MODERATE 2, EN_HEAVY 3
check bare        1 0
check mage_armour 1 0
check bare_again  1 0
check light       1 1
check moderate    0 2
check heavy       0 3
check bare_wis5            5 0 5
check spirit_armour        5 0 5
check mage_armour_wis5     5 0 5
check worn_light           3 0 5
check worn_light_plus_mage 3 0 5
check worn_medium          0 0 5
if [ "$fail" -ne 0 ]; then echo "RED: Zen Defense bonus is wrong. Run: $RUN"; exit 1; fi
echo "GREEN: Zen Defense matches R1 and R2. Run: $RUN"
exit 0
