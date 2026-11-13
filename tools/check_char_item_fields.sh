#!/usr/bin/env bash
# gate: live
#
# Does a stated kit item become the item with every field the text form writes?
#
# WHAT IS BEING PROVED. Spec B2 (bead inc-10v7f, phase 7a): an answered
# CreationItem is built by CreationMakeItem through the engine's own item
# functions, and the .char parser reads every field CreationItemText writes. Two
# stated kit items carry between them: plus, flags (blessed, masterwork), a
# weapon quality, charges, a status with its effect, a bane with its bane
# quality. The built character's canonical dump MUST show each one.
#
# fact: the character -- a .char recorded now by tools/headless.sh from tools/keys/chargen-default-save.keys at seed 1 under tools/fixtures/options-2026-08-22.dat (inc-10v7f); two of its kit_item lines are then replaced by the stated items below
# fact: the stated items -- the replacement lines in this script; the check reads the dump only for those fields
#
# Usage: INCURSION_BIN=./incursion-headless tools/check_char_item_fields.sh
# Exit: 0 pass; 1 fail; 2 could not run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
BIN="${INCURSION_BIN:-./incursion-headless}"
[ -x "$BIN" ] || { echo "INCONCLUSIVE: $BIN is not built"; exit 2; }
O22=tools/fixtures/options-2026-08-22.dat

W="$(mktemp -d "$ROOT/logs/item-fields.XXXXXX")" || exit 2
trap 'rm -rf "$W"' EXIT

INCURSION_RECORD_CHAR="$W/good.char" INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" \
    INCURSION_RUN_DIR="$W/walk" tools/headless.sh tools/keys/chargen-default-save.keys 1 \
    > "$W/walk.log" 2>&1 < /dev/null
[ -f "$W/good.char" ] || { echo "INCONCLUSIVE: the recording run left no .char"; exit 2; }

sed -e 's/^kit_item \[Orc;a2\]: knife, quantity 1/kit_item [Orc;a2]: knife, plus 2, flag blessed, flag masterwork, quality WQ_KEEN, quantity 1, charges 7, stati POISONED val 0 mag 7 duration 0 effect elfshot/' \
    -e 's/^kit_item \[Barbarian;a8\]: greatsword, quantity 1/kit_item [Barbarian;a8]: greatsword, bane 3, quality WQ_BANE, quantity 1/' \
    "$W/good.char" > "$W/fields.char"
grep -q 'flag masterwork' "$W/fields.char" && grep -q 'bane 3' "$W/fields.char" || { echo "INCONCLUSIVE: the recorded kit lines moved; the edit found nothing to replace"; exit 2; }

if ! INCURSION_BIN="$BIN" tools/build_fixture.sh "$W/fields.char" "$W/out" > "$W/b.log" 2>&1; then
    echo "FAIL: the build did not finish: $(grep -m1 'BUILD FAILED' "$W/b.log" || tail -1 "$W/b.log")"; exit 1
fi
INCURSION_OPTIONS="$O22" INCURSION_BIN="$BIN" tools/char_dump.sh "$W/out/fields.sav" "$W/f.canon" > /dev/null 2>&1 || { echo "INCONCLUSIVE: the dump failed"; exit 2; }

fail=0
block() {   # <iID> -> the first 9 lines of that item's entry
    grep -m1 -A8 "^ *- Item iID=$1 eID=" "$W/f.canon"
}
need() {   # <label> <block> <pattern>
    if grep -qE -- "$3" <<< "$2"; then echo "ok   $1"; else echo "FAIL $1: no match for /$3/"; fail=1; fi
}
K="$(block knife)"
need "plus 2 and charges 7"        "$K" 'Plus=2 Charges=7'
need "flags blessed and masterwork" "$K" 'IFlags=0x[0-9a-f]*[9bdf]'
need "quality WQ_KEEN"             "$K" 'Qualities: \[0\]=WQ_KEEN'
need "status POISONED with effect" "$K" 'Stati: Nature=POISONED Val=0 Mag=7 Duration=0 Source=SS_MISC .* eID=elfshot'
G="$(block greatsword)"
need "quality WQ_BANE"             "$G" 'Qualities: \[0\]=WQ_BANE'
need "bane 3 (MA_BAT)"             "$G" 'Bane: MA_BAT'

[ $fail -eq 0 ] && { echo "PASS: every stated item field is in the built item"; exit 0; }
exit 1
