#!/bin/bash
# gate: live
# inc-ibzyp: does the AutoLoot checklist keep the color of an item's name?
# Opt-in MultiSelectColorProbe (src/MultiSelectColorProbe.cpp) stages a known
# cursed dagger (RED "c "/"cursed " span in Item::Name) and a long sword, a) on the floor
# or b) inside a chest, runs the AutoLoot macro, and logs each row that
# TextTerm::LMultiSelect draws. PASS needs the cursed row to keep RED cells
# both as the cursor row and as a plain row, the cursor row to carry background
# 1, and the row text "(on ground)"/"(in chest)" to stay readable.
# Case p stages the same two items and opens the real "Pick up what?" menu with
# the g key; its plain cursed row must hold as many RED cells as the AutoLoot
# row (AC1). A structural grep proves AutoLoot builds each row from Item::Name
# and sets no color of its own (AC2). Cases a and b prove AC3 and AC4.
# Builds nothing; needs incursion-headless.
# fact: character and abilities -- fixture orc-rogue-seed1-opt0822.char
# fact: options -- options-2026-08-22.dat (AutoLoot macro does not read AUTOPICKUP)
# fact: terrain and absence of threats -- probe picks an isolated empty floor cell
# fact: items, curse and identification -- probe Item::Create, IFlags IF_CURSED, MakeKnown, aborts if the name has no RED span
# fact: lib/alchemy.irh row construction -- grep of the AutoLoot macro body; AC2 is structural
# fact: row colors read -- cell foreground of the drawn row via AGetChar on the posix backend, exact
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-multiselect-colors"
mkdir -p "$base"
failed=0
for c in a b; do
    run="$base/$c"
    INCURSION_MULTISELECT_COLOR_PROBE="$c" INCURSION_RUN_DIR="$run" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.char \
        tools/headless.sh tools/keys/multiselect-colors.keys 1 > "$base/$c-harness.log" 2>&1
    rc=$?
    log="$run/logs/multiselect-colors.log"
    if [ ! -f "$log" ] || ! grep -q '^COMPLETE' "$log"; then
        echo "FAIL case=$c: probe did not complete (harness exit $rc, $base/$c-harness.log)"
        failed=1; continue
    fi
    suffix=ground; [ "$c" = b ] && suffix=chest
    cur=$(grep -c "cursor=1 cursed=1 red=[1-9]" "$log")
    plain=$(grep -c "cursor=0 cursed=1 red=[1-9]" "$log")
    uncolored=$(grep -c "cursed=1 red=0" "$log")
    bg=$(grep -c "cursor=1 .* back1=[1-9]" "$log")
    sfx=$(grep -c "cursed=1 .*$suffix=1" "$log")
    if [ "$cur" -ge 1 ] && [ "$plain" -ge 1 ] && [ "$uncolored" -eq 0 ] && [ "$bg" -ge 1 ] && [ "$sfx" -ge 1 ]; then
        echo "PASS case=$c: cursor-red=$cur plain-red=$plain cursor-bg=$bg suffix=$sfx"
    else
        echo "FAIL case=$c: cursor-red=$cur plain-red=$plain uncolored=$uncolored cursor-bg=$bg suffix=$sfx specimen $log"
        failed=1
    fi
done
# case p: the "Pick up what?" menu (AC1)
run="$base/p"
INCURSION_MULTISELECT_COLOR_PROBE=p INCURSION_RUN_DIR="$run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.char \
    tools/headless.sh tools/keys/multiselect-pickup.keys 1 > "$base/p-harness.log" 2>&1
plog="$run/logs/multiselect-colors.log"
alog="$base/a/logs/multiselect-colors.log"
pr=$(grep "menu=menu i=[0-9]* cursor=0 cursed=1 red=" "$plog" 2>/dev/null | head -1 | sed 's/.* red=\([0-9]*\) .*/\1/')
ar=$(grep "menu=multi i=[0-9]* cursor=0 cursed=1 red=" "$alog" 2>/dev/null | head -1 | sed 's/.* red=\([0-9]*\) .*/\1/')
if [ -n "$pr" ] && [ "$pr" = "$ar" ] && [ "$pr" -ge 1 ]; then
    echo "PASS case=p (AC1): pickup-menu red=$pr equals AutoLoot red=$ar"
else
    echo "FAIL case=p (AC1): pickup-menu red=[$pr] AutoLoot red=[$ar] specimen $plog"; failed=1
fi
# AC2: every AutoLoot row is Item::Name text, and the menu sets no color of its own.
al=$(sed -n '/^AI_MACRO Effect "AutoLoot"/,/^AI_MACRO Effect/p' lib/alchemy.irh)
nm=$(printf '%s\n' "$al" | grep -c 's = h2*->Name(NA_A|NA_LONG|NA_MECH)')
col=$(printf '%s\n' "$al" | grep -c 'LOptionFlags\|LOptionColor')
if [ "$nm" -eq 2 ] && [ "$col" -eq 0 ]; then
    echo "PASS (AC2): both AutoLoot rows come from ->Name(NA_A|NA_LONG|NA_MECH), no LOptionFlags"
else
    echo "FAIL (AC2): Name rows=$nm (want 2), color calls=$col (want 0)"; failed=1
fi
exit "$failed"
