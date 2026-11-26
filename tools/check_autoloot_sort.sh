#!/bin/bash
# gate: live
# inc-ibzyp: does the AutoLoot checklist list items from most to least valuable
# by what the player can know, and leak nothing about unidentified items?
# MultiSelectColorProbe mode s stages five floor items, runs the AutoLoot macro
# and logs the rows LMultiSelect draws (pass one, cursor on row 0):
#   long sword +5   known            value 3203 (true price)
#   handaxe +1      hint "good"      value 2136 (a level-4 item; its true price is 536)
#   club +1         hint "magical"   value  535 (a level-1 item)
#   plate mail      hint "mundane"   value  200 (plain base price)
#   warhammer +5    no hint          value    4 (plain base price; its true price 3204 must NOT show)
# Expected order: long sword, handaxe, club, plate mail, warhammer. A sort on the
# true price would put the warhammer second. Item::KnownValue is the sort key.
# Builds nothing; needs incursion-headless.
# fact: character and abilities -- fixture orc-rogue-seed1-opt0822.char
# fact: options -- options-2026-08-22.dat
# fact: terrain and absence of threats -- probe picks an isolated empty floor cell
# fact: items, plus, identification, hints -- probe Item::Create, SetInherentPlus, MakeKnown, Inscrip from IntuitLevels
# fact: price table values -- lib/*.irh item costs and defCost in src/Social.cpp; the order, not the gp, is asserted
# fact: row order read -- first five LMultiSelect rows drawn, read through AGetChar on the posix backend
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-autoloot-sort"
mkdir -p "$base"
run="$base/s"
INCURSION_MULTISELECT_COLOR_PROBE=s INCURSION_RUN_DIR="$run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.char \
    tools/headless.sh tools/keys/multiselect-colors.keys 1 > "$base/s-harness.log" 2>&1
log="$run/logs/multiselect-colors.log"
if [ ! -f "$log" ] || ! grep -q '^COMPLETE' "$log"; then
    echo "FAIL: probe did not complete ($base/s-harness.log)"; exit 1
fi
got=$(grep '^ROW menu=multi' "$log" | head -5 | sed -e 's/.*text=\[ *\[ \] //' \
    -e 's/ (on ground).*//' | tr '\n' '|')
want="a long sword +5|a ? handaxe {good}|a ? club {magical}|a suit of ? plate mail {mundane}|a ? warhammer|"
if [ "$got" = "$want" ]; then echo "PASS: $got"; exit 0; fi
echo "FAIL: order $got (want $want) specimen $log"; exit 1
