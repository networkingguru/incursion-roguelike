#!/bin/bash
# Observed regression check for F39 / inc-tek.8.8 / bd inc-cyma: the Sunblade's
# activated light field reaches the 60 feet its page promises -- six ten-foot
# squares -- and the game is watched painting that disc on the map.
#
# THE ORACLE is the map, not the source. An activated FI_LIGHT field renders as
# a disc of ',' glyphs centred on the player '@' (posixTerm::DumpScreen,
# src/Wposix.cpp). The disc's radius in tiles IS the field's lval, and one tile
# is ten feet. tools/keys/sunblade-light.keys acquires a Sunblade, wields it,
# dumps the map, activates the 3/day field, and dumps the map again. This check
# runs that script on the CURRENT build and reads the '@' row of each dump: the
# field must be absent before activation and exactly six tiles to each side
# after it.
#
# WHY THE COUNT IS UNAMBIGUOUS. The ',' glyph is distinct from floor '.'. On
# seed 1 the disc stops with plain floor tiles still visible before the wall --
# four to each side after the fix -- so the wall does not clip it, and the six
# is the field's own radius rather than the room's width.
#
# PROVED RED FIRST, across the fix commit, reproducibly. The fix is commit
# e47f209, which changed lval from 5 to 6. tools/oracle_ab.sh builds both sides
# and runs this same key script on each:
#
#   before (e47f209^, lval 5):  #.....,,,,,@,,,,,.....#   -> 5 tiles each side
#   after  (e47f209,  lval 6):  #....,,,,,,@,,,,,,....#   -> 6 tiles each side
#
# Re-run that proof any time with:
#   tools/oracle_ab.sh e47f209 tools/keys/sunblade-light.keys 1 map-after-activation
# The before build measures 5, so a check that asserts 6 is red on it. That is
# the mutation this check survives.
#
# Usage: tools/check_sunblade_light_range.sh   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/sunblade-light.keys

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if printf '%s\n' "$out" | grep -q "the key script looked for something"; then
    echo "INCONCLUSIVE: $KEYS could not find something on screen. Run: $run"
    exit 2
fi
if printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: $KEYS never entered a map. Run: $run"
    exit 2
fi

screens="$run/logs/screens"

# radius_of <dump>: echo the number of ',' field tiles that touch '@' on its own
# row, to the left and right. The two must agree; the disc is symmetric.
radius_of() {
    local dump="$1" row left right lc rc
    dump="$(ls "$screens"/*"$1"*.txt 2>/dev/null | head -1 || true)"
    [ -n "$dump" ] || { echo "INCONCLUSIVE: no '$1' dump under $screens" >&2; exit 2; }
    row="$(grep -m1 '@' "$dump" || true)"
    [ -n "$row" ] || { echo "INCONCLUSIVE: no '@' on the $1 map. Run: $run" >&2; exit 2; }
    left="${row%%@*}"; right="${row#*@}"
    lc="$(printf '%s' "$left"  | sed 's/.*[^,]//')"   # trailing comma run
    rc="$(printf '%s' "$right" | sed 's/[^,].*//')"    # leading comma run
    if [ "${#lc}" -ne "${#rc}" ]; then
        echo "INCONCLUSIVE: $1 disc is lopsided (${#lc} left, ${#rc} right). Run: $run" >&2
        exit 2
    fi
    echo "${#rc}"
}

before="$(radius_of map-before-activation)"
after="$(radius_of map-after-activation)"

fail=0
if [ "$before" -ne 0 ]; then
    echo "FAIL: the map showed a light disc BEFORE activation (radius $before). Run: $run"
    fail=1
fi
if [ "$after" -ne 6 ]; then
    echo "FAIL: the activated Sunblade light disc is radius $after, not 6 (60 feet). Run: $run"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "Sunblade light radius: 0 before activation, 6 squares = 60 feet after."
    echo "PASS: the game paints a radius-six FI_LIGHT disc when the Sunblade is activated."
fi
exit "$fail"
