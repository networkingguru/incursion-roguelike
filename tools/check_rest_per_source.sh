#!/bin/bash
# gate: live
# inc-4999: does a full rest apply each spell source's own selection, and leave
# the other sources alone?
#
# WHAT IS BEING GUARDED. Player::Spells[] keeps, per spell, a kind bit that
# means "HELD from that source" (SP_ARCANE, SP_DIVINE, SP_PRIMAL, SP_BARDIC) and
# a pending bit per source for "selected for the next rest" (SP_PENDING arcane,
# SP_PEND_DIV divine, SP_PEND_PRI primal; bardic has none).
# Player::ApplySpellSelection() (src/Create.cpp) runs at a full rest. Per
# source, a pending spell becomes held (arcane only when a carried spellbook
# holds it) and a held spell that is not pending is forgotten. Bardic never
# changes. Before this rule one shared pending bit let a rest for one source
# erase another (inc-lrxk: a Priest/Mage lost his divine spells).
#
# THE ORACLE is INCURSION_SPELLFLAG_PROBE (src/Create.cpp, Player::
# SpellFlagProbe). It writes one errors.log line per spell that carries
# SP_KNOWN or a source bit, then a "migrated=<n> rev=<n>" line, once at load and
# once more after the rest. The second block IS the proof that the rest ran;
# a case with no second block exits 2, never 0.
#
#   a. Priest/Mage (tools/fixtures/chars/human-priest-mage-seed4-gate.sav),
#      full rest, no menu change: every spell divine=1 at load is divine=1 after.
#   b. Priest (orc-priest-seed4-gate.sav, no spellbook), Learn Spells: unmark
#      Bane, Bless and Call Companions (the level holds 6 of 4 slots and a mark
#      is refused until it drops below 4), mark Detect Evil, confirm, rest.
#      Bane divine=0 after, Detect Evil divine=1 after.
#   c. Bard (orc-bard-reapply-seed1.sav), full rest: every bardic=1 spell is
#      still bardic=1.
#   d. Priest/Mage dual version: mark the ARCANE row of a spell held divine
#      where a carried spellbook holds it; after the rest arcane=1 and divine=1.
#      The Priest/Mage fixture carries no spellbook, so d prints SKIP (neither
#      PASS nor FAIL). It becomes exit 2 if a book ever appears in the
#      inventory, because then d needs a key script this check does not have.
#
# PROVED RED with --prove-red (docs/VERIFICATION.md step 2). The mutation makes
# the row loop of ApplySpellSelection skip every row whose Type is not
# SP_ARCANE. A divine row is then never applied, so case b keeps Bane divine=1
# and Detect Evil never becomes held; the check exits 1.
#
# Usage: tools/check_rest_per_source.sh [--prove-red]
#   0 every run case holds   1 one fails   2 could not measure
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

CHARS=tools/fixtures/chars
PM=$CHARS/human-priest-mage-seed4-gate
PRIEST=$CHARS/orc-priest-seed4-gate.sav
BARD=$CHARS/orc-bard-reapply-seed1.sav

check_mutation src/Create.cpp \
'    for (i = 0; ls[i].spID; i++) {
        if (ls[i].Type != SP_ARCANE && ls[i].Type != SP_DIVINE
            && ls[i].Type != SP_PRIMAL)
            continue;' \
'    for (i = 0; ls[i].spID; i++) {
        if (ls[i].Type != SP_ARCANE) continue;
        if (ls[i].Type != SP_ARCANE && ls[i].Type != SP_DIVINE
            && ls[i].Type != SP_PRIMAL)
            continue;'

for f in "$PM.sav" "$PM.sheet.txt" "$PRIEST" "$BARD"; do
    [ -f "$f" ] || _check_die 2 "no $f."
done

export INCURSION_SPELLFLAG_PROBE=1
FAIL=0
RUNS=0

# run_case <label> <fixture> <keys> <seed> -- sets LOG to the run's errors.log
run_case() {
    export INCURSION_LOAD="$2"
    check_run "$3" "$4"
    LOG="$CHECK_RUN/logs/errors.log"
    [ -f "$LOG" ] || _check_die 2 "case $1: the run logged nothing."
    RUNS=$((RUNS + 1))
}

# block <n> -- the probe lines of the n-th probe block (1 load, 2 after rest)
block() {
    grep -E '^[0-9].*SPELLFLAG_PROBE' "$LOG" | sed 's/^.*SPELLFLAG_PROBE //' |
        awk -v n="$1" 'BEGIN{b=1} b==n{print} /^migrated=/{b++}'
}

# need_rest <label> -- exit 2 unless the post-rest block exists and is complete
need_rest() {
    if ! block 2 | grep -q '^migrated='; then
        _check_die 2 "case $1: no probe block after the rest, so no rest" \
            "was proved. See $CHECK_RUN."
    fi
}

# bit <block n> <spell> <field> -- 0, 1, or "none" when the spell has no line
bit() {
    local line
    line="$(block "$1" | grep -E "^$2 known=" | head -1)"
    [ -n "$line" ] || { echo none; return; }
    printf '%s\n' "$line" | grep -oE " $3=[01]" | sed "s/ $3=//"
}

# keep_all <label> <field> -- every spell with field=1 at load keeps it
keep_all() {
    local label="$1" field="$2" n=0 name
    while read -r name; do
        [ -n "$name" ] || continue
        n=$((n + 1))
        if [ "$(bit 2 "$name" "$field")" != "1" ]; then
            echo "FAIL $label: $name had $field=1 at load, now $(bit 2 "$name" "$field")."
            FAIL=1
        fi
    done < <(block 1 | grep -E " $field=1" | awk '{print $1}')
    [ "$n" -gt 0 ] || _check_die 2 "case $label: no spell has $field=1 at load," \
        "so there is nothing to keep."
    echo "  $label: $n spell(s) with $field=1 at load, checked after the rest."
}

# a. Priest/Mage, rest only
run_case a "$PM.sav" tools/keys/rest-per-source-restonly.keys 4
need_rest a
keep_all a divine

# b. Priest, no book: swap one set of divine picks for another
run_case b "$PRIEST" tools/keys/rest-per-source-swap.keys 4
need_rest b
OLD=Bane
NEW=Detect_Evil
if [ "$(bit 1 $OLD divine)" != "1" ] || [ "$(bit 1 $NEW divine)" = "1" ]; then
    _check_die 2 "case b: at load $OLD must be divine=1 and $NEW not held." \
        "The fixture or the key script drifted."
fi
if ! cat "$CHECK_RUN"/logs/screens/*swapped.txt 2>/dev/null |
        grep -q '\[\*\] (div)Detect Evil'; then
    _check_die 2 "case b: the Learn Spells screen did not show Detect Evil" \
        "marked, so the swap was not made. See $CHECK_RUN."
fi
if [ "$(bit 2 $OLD divine)" = "1" ]; then
    echo "FAIL b: $OLD was unmarked but is still divine=1 after the rest."
    FAIL=1
fi
if [ "$(bit 2 $NEW divine)" != "1" ]; then
    echo "FAIL b: $NEW was marked but is divine=$(bit 2 $NEW divine) after the rest."
    FAIL=1
fi
echo "  b: dropped $OLD (divine $(bit 1 $OLD divine) -> $(bit 2 $OLD divine)), picked $NEW (divine $(bit 1 $NEW divine) -> $(bit 2 $NEW divine))."

# c. Bard, rest only
run_case c "$BARD" tools/keys/rest-per-source-restonly.keys 1
need_rest c
keep_all c bardic

# d. dual version needs a carried spellbook
if sed -n '/^Inventory:/,/^On The Ground/p' "$PM.sheet.txt" | grep -qi 'book'; then
    _check_die 2 "case d: the Priest/Mage now carries a spellbook, and this" \
        "check has no key script that marks the arcane row."
fi
echo "SKIP d: the Priest/Mage fixture carries no spellbook (its inventory lists none), so no spell can be held arcane and divine."

[ "$RUNS" -eq 3 ] || _check_die 2 "expected 3 runs, made $RUNS."

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "FAIL: a rest changed a spell source it was not asked to change, or did"
    echo "      not apply the source's own selection (inc-4999)."
    exit 1
fi
echo
echo "PASS: a, b, c hold; d skipped. A rest applies each source's own selection."
exit 0
