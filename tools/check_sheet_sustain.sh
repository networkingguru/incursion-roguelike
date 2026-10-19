#!/bin/bash
# gate: live
# Does the character sheet show a stat sustain? (bd inc-j2wy)
#
#   tools/check_sheet_sustain.sh [seed]     default seed: 1
#   exit 0 the sheet shows both sustains, 1 it misses one, 2 could not measure
#
# THE DEFECT. src/Sheet.cpp's Special Abilities list had no entry for SUSTAIN.
# The status works in play: the drain code in src/Fight.cpp subtracts it.
#
# THE SESSION is tools/keys/sheet-sustain.keys: wizard mode puts the Ring of
# Elemental Command (Earth) on a finger (SUSTAIN STR +10 and SUSTAIN CON +10),
# reads the player's stati, and dumps the sheet's Special Abilities list.
#
# THE ORACLE, read from the screen dump of the sheet:
#   - "Sustain STR: +10" and "Sustain CON: +10" appear in Special Abilities.
# IT CANNOT PASS BY DEFAULT. Exit 1 only when all controls hold: the session
# ended cleanly, the ring is worn, wizard mode lists a SUSTAIN stati of
# Mag 10 from the ring, and the Special Abilities heading reached the screen.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"; exit 2; }
OPTIONS="${INCURSION_OPTIONS:-tools/fixtures/options-2026-08-22.dat}"
[ -f "$OPTIONS" ] || { echo "INCONCLUSIVE: settings file $OPTIONS is not there"; exit 2; }
KEYS=tools/keys/sheet-sustain.keys
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: $KEYS is not there"; exit 2; }
SEED="${1:-1}"

RUN="$ROOT/logs/runs/check-sheet-sustain-$$-$(date +%s)"
rm -rf "$RUN"
out="$(INCURSION_RUN_DIR="$RUN" INCURSION_OPTIONS="$OPTIONS" \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
S="$RUN/logs/screens"
if grep -qE 'NO GAMEPLAY|the key script looked for something|WATCHDOG|FATAL|ASSERT' <<< "$out" \
   || ! grep -q 'ended: *cleanly' <<< "$out"; then
    echo "INCONCLUSIVE: the session did not play to the end; see $RUN"; exit 2
fi
RING="$S/0001-ring-on.txt"; STATI="$S/0002-stati.txt"; SPEC="$S/0003-specials.txt"
for f in "$RING" "$STATI" "$SPEC"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: no screen dumped at $f"; exit 2; }
done
grep -q 'Left Ring    :Ring of Elemental Command (Earth)' "$RING" || {
    echo "INCONCLUSIVE: the earth ring is not on a finger; see $RUN"; exit 2; }
grep -q 'SUSTAIN from SS ITEM (Val:A CON Mag:10)' "$STATI" || {
    echo "INCONCLUSIVE: the player holds no SUSTAIN CON Mag 10 stati; see $RUN"; exit 2; }
grep -q 'Special Abilities' "$SPEC" || {
    echo "INCONCLUSIVE: the Special Abilities heading never reached the screen; see $RUN"; exit 2; }
echo "control: ring worn, SUSTAIN stati held (Mag 10), Special Abilities on screen"

missing=""
grep -q 'Sustain STR: +10' "$SPEC" || missing="$missing 'Sustain STR: +10'"
grep -q 'Sustain CON: +10' "$SPEC" || missing="$missing 'Sustain CON: +10'"
if [ -n "$missing" ]; then
    echo "FAIL: the sheet does not show:$missing; see $RUN"; exit 1
fi
echo "PASS: the sheet shows the sustains"
grep -h 'Sustain ' "$SPEC"
exit 0
