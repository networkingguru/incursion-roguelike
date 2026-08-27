#!/bin/bash
# Regression check for F44 / inc-tek.8.8: only an orc wielding the Bloodspear
# receives its +4 saving-throw bonus versus spells.
#
# THE ORACLE is the character sheet's Will-save breakdown after the Bloodspear
# is wielded. The sheet appends "(... +4 vs. spells ...)" to the Will line
# (src/Sheet.cpp:146) when a SAVE_BONUS/SN_SPELLS stati is present. The
# Bloodspear grants that stati only when its EV_WIELD handler takes the orc
# branch and returns NOTHING, so the EA_GRANT wield path applies the component.
# An orc wielder must gain the line; a dwarf wielder -- not an orc, and not a
# goblinoid, troll, kobold or lizardfolk either -- must wield the same spear and
# gain nothing. tools/oracle_ab.sh proves the same dwarf gained the line before
# commit 24b7eb7; this check reads the current build.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
ORC_KEYS=tools/keys/bloodspear-orc-save.keys
DWARF_KEYS=tools/keys/bloodspear-dwarf-save.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

# Run one keys file and echo its run directory; fail hard on a run that never
# reached a map or could not find a screen it scripted.
run_keys() {
    local keys="$1" out run
    out="$(tools/headless.sh "$keys" "$SEED" 2>&1)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if echo "$out" | grep -q "NO GAMEPLAY"; then
        echo "FAIL: $keys never entered a map, so it measured nothing." >&2
        echo "$out" >&2
        return 1
    fi
    if echo "$out" | grep -q "the key script looked for something"; then
        echo "FAIL: $keys did not find a screen it expected." >&2
        echo "$out" >&2
        return 1
    fi
    echo "$run"
}

# Assert a screen exists; fail with its path otherwise.
need_screen() {
    [ -f "$1" ] || { echo "FAIL: no measurement screen at $1"; exit 1; }
}

SPELLS='+4 vs. spells'
WIELDED="longspear 'Bloodspear'"

# --- Orc: the spear must grant the +4-vs-spells line. ---
orc_run="$(run_keys "$ORC_KEYS")" || exit 1
orc_before="$orc_run/logs/screens/0001-orc-sheet-without-bloodspear.txt"
orc_wielded="$orc_run/logs/screens/0002-orc-wielded.txt"
orc_after="$orc_run/logs/screens/0003-orc-sheet-with-bloodspear.txt"
need_screen "$orc_before"; need_screen "$orc_wielded"; need_screen "$orc_after"

grep -Fq "$WIELDED" "$orc_wielded" || {
    echo "FAIL: the orc did not wield the Bloodspear; the oracle measured nothing."
    echo "Screen: $orc_wielded"
    exit 1
}
grep -Fq "$SPELLS" "$orc_before" && {
    echo "FAIL: the orc's sheet already showed '$SPELLS' before wielding the spear."
    echo "Screen: $orc_before"
    exit 1
}
grep -Fq "$SPELLS" "$orc_after" || {
    echo "FAIL: the orc wielding the Bloodspear did not gain '$SPELLS' on the sheet."
    echo "Screen: $orc_after"
    exit 1
}

# --- Dwarf: the same spear, wielded, must grant nothing. ---
dwarf_run="$(run_keys "$DWARF_KEYS")" || exit 1
dwarf_before="$dwarf_run/logs/screens/0001-dwarf-sheet-without-bloodspear.txt"
dwarf_wielded="$dwarf_run/logs/screens/0002-dwarf-wielded.txt"
dwarf_after="$dwarf_run/logs/screens/0003-dwarf-sheet-with-bloodspear.txt"
need_screen "$dwarf_before"; need_screen "$dwarf_wielded"; need_screen "$dwarf_after"

grep -Fq "$WIELDED" "$dwarf_wielded" || {
    echo "FAIL: the dwarf did not wield the Bloodspear; the gate was not exercised."
    echo "Screen: $dwarf_wielded"
    exit 1
}
grep -Fq "$SPELLS" "$dwarf_after" && {
    echo "FAIL: a non-orc wielding the Bloodspear received '$SPELLS'; the gate leaks."
    echo "Screen: $dwarf_after"
    exit 1
}

echo "Orc wielding the Bloodspear:   Will save gains '$SPELLS'"
echo "Dwarf wielding the Bloodspear: Will save gains nothing"
echo "PASS: F44 / inc-tek.8.8 gates the Bloodspear +4 spell-save bonus to orcs."
