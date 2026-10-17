#!/bin/bash
# gate: live
# Does the character sheet list a confusion immunity? (bd inc-h8lc)
#
#   tools/check_sheet_immunities.sh [seed]     default seed: 1
#   exit 0 the sheet lists Confusion, 1 it does not, 2 could not measure
#
# THE DEFECT. src/Sheet.cpp prints resistances and "Complete Immunities" only
# for damage types in its array ResistsShown. AD_CONF is not on it, although
# Creature::ResistLevel returns -1 (immune) for it.
#
# THE SESSION is tools/keys/sheet-immunities.keys: wizard mode gives the player
# the "plantform" template, whose Immune: list (PLANT_IMMUNITIES in
# lib/defines.irh) holds DF_CONF with DF_POIS, DF_SLEE, DF_STUN, DF_PLYS and
# DF_POLY. The sheet is then scrolled to its immunities section and dumped.
#
# THE ORACLE, read from the screen dump:
#   - positive control: the Complete Immunities section lists Poison, Sleep,
#     Stunning and Paralysis. Those are template-granted and on ResistsShown, so
#     they prove the template took effect and the section was captured;
#   - the section lists Confusion. DF_CONF is in the same Immune: list.
# IT CANNOT PASS BY DEFAULT. Exit 2 when the session did not play, the template
# was not added, or the control rows are missing. Exit 1 only when the control
# holds and Confusion is absent.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/sheet-immunities.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }
SEED="${1:-1}"

# The immunity must exist in the data, or a red result would mean nothing.
grep -q 'DF_CONF' <<< "$(grep -A2 'define PLANT_IMMUNITIES' lib/defines.irh)" || {
    echo "INCONCLUSIVE: PLANT_IMMUNITIES in lib/defines.irh no longer holds DF_CONF"; exit 2; }

RUN="$ROOT/logs/runs/check-sheet-immunities-$$-$(date +%s)"
rm -rf "$RUN"
out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
S="$RUN/logs/screens"
if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$out" \
   || ! grep -q 'ended: *cleanly' <<< "$out"; then
    echo "INCONCLUSIVE: the session did not play to the end; see $RUN"; exit 2
fi
TEMPLATE="$(ls "$S"/*-template.txt 2>/dev/null | head -1)"
IMMUNE="$(ls "$S"/*-immune.txt 2>/dev/null | head -1)"
[ -n "$TEMPLATE" ] && [ -n "$IMMUNE" ] || { echo "INCONCLUSIVE: a screen dump is missing; see $RUN"; exit 2; }
grep -q 'Template added' "$TEMPLATE" || { echo "INCONCLUSIVE: the template was not added; see $RUN"; exit 2; }
grep -q 'Complete Immunities' "$IMMUNE" || { echo "INCONCLUSIVE: the immunities heading never reached the screen; see $RUN"; exit 2; }

# Section rows: indented words under the heading, up to the first blank line.
ROWS="$(awk '/Complete Immunities/ {on=1; next} on && NF==0 {exit} on {print}' <<< "$(cut -c38- "$IMMUNE")")"
for need in Poison Sleep Stunning Paralysis; do
    grep -q "$need" <<< "$ROWS" || {
        echo "INCONCLUSIVE: control row '$need' is not in the immunities section; see $RUN"; exit 2; }
done
echo "control: Poison, Sleep, Stunning and Paralysis are listed under Complete Immunities"

if grep -q 'Confusion' <<< "$ROWS"; then
    echo "PASS: Complete Immunities lists Confusion"; exit 0
fi
echo "FAIL: the player is immune to confusion (plantform template) but Complete Immunities does not list Confusion; see $RUN"
exit 1
