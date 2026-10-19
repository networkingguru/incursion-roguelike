#!/bin/bash
# gate: live
# Does the character sheet show water breathing and true sight? (bd inc-frhx)
#
#   tools/check_sheet_water_true_sight.sh [seed]     default seed: 1
#   exit 0 the sheet shows both, 1 it misses one, 2 could not measure
#
# THE DEFECT. src/Sheet.cpp's Special Abilities switch has no case for
# WATER_BREATHING, and its Perception and Vision section prints nothing for
# TRUE_SIGHT. Both statuses work in play.
#
# THE SESSION is tools/keys/sheet-water-breathing-true-sight.keys: wizard mode
# puts the Ring of Elemental Command (Water) on a finger (WATER_BREATHING), the
# mage learns and casts True Seeing (TRUE_SIGHT), and the sheet is scrolled to
# the Special Abilities and Perception and Vision sections and dumped.
#
# THE ORACLE, read from the screen dumps:
#   - "Water Breathing" appears in the Special Abilities dump;
#   - "True Sight Range" appears in the Perception and Vision dump.
# IT CANNOT PASS BY DEFAULT. Exit 1 only when all four controls hold: the
# session ended cleanly, the ring is worn, the Conditions screen lists the
# True Seeing spell effect, and both section headings reached the screen.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/sheet-water-breathing-true-sight.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }
SEED="${1:-1}"

RUN="$ROOT/logs/runs/check-sheet-water-true-sight-$$-$(date +%s)"
rm -rf "$RUN"
out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
S="$RUN/logs/screens"
if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$out" \
   || ! grep -q 'ended: *cleanly' <<< "$out"; then
    echo "INCONCLUSIVE: the session did not play to the end; see $RUN"; exit 2
fi
RING="$S/0001-ring-on.txt"; COND="$S/0003-cond.txt"
SPEC="$S/0004-specials.txt"; PERC="$S/0005-perception.txt"
for f in "$RING" "$COND" "$SPEC" "$PERC"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done
grep -q 'Left Ring    :Ring of Elemental Command (Water)' "$RING" || {
    echo "INCONCLUSIVE: the water ring is not on a finger; see $RUN"; exit 2; }
grep -q 'Spell Effect: True Seeing' "$COND" || {
    echo "INCONCLUSIVE: the True Seeing effect is not on the player; see $RUN"; exit 2; }
grep -q 'Special Abilities' "$SPEC" || {
    echo "INCONCLUSIVE: the Special Abilities heading never reached the screen; see $RUN"; exit 2; }
grep -q 'Perception and Vision' "$PERC" || {
    echo "INCONCLUSIVE: the Perception and Vision heading never reached the screen; see $RUN"; exit 2; }
echo "control: ring worn, True Seeing active, both section headings on screen"

missing=""
grep -q 'Water Breathing' "$SPEC" || missing="$missing 'Water Breathing'"
grep -q 'True Sight Range' "$PERC" || missing="$missing 'True Sight Range'"
if [ -n "$missing" ]; then
    echo "FAIL: the sheet does not show:$missing; see $RUN"; exit 1
fi
echo "PASS: the sheet shows Water Breathing and True Sight Range"
grep -h 'Water Breathing' "$SPEC"; grep -h 'True Sight Range' "$PERC"
exit 0
