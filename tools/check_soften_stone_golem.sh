#!/bin/bash
# gate: live
# inc-wqql: Soften Stone cast at a stone golem softens its body (lowers its
# armor) instead of slowing it, and does not slow the golem.
#
# fact: character -- fixture druid-shoulder-metal-seed7-opt0822.sav
# fact: options -- fixed options-2026-08-22.dat fixture
# fact: a stone golem beside the caster -- wizard menu "Monster Summoning",
#       "Golems", "stone golem"
# fact: the caster knows Soften Stone -- wizard menu "Learn Any Spell"
# fact: caster's position and surroundings -- fixture (wizard mode, Infinite
#       Mana, Freeze Monsters set in the fixture's options/save)
# fact: the soften effect and its armor magnitude (-5) -- the mon3.irh stone
#       golem rule, read as the dump's "ADJUST ARM ... (Val:A ARM Mag:-5)";
#       not a roll. The 2d6 duration is a roll and is read only as a duration,
#       never asserted.
# fact: the prose "stone body softens" -- the mon3.irh rule text
#
# The oracle is the wizard dump of the golem, taken while Soften Stone is aimed
# at its square (pressing W on the aimed creature opens Thing::Dump; see
# tools/keys/soften-stone-golem.keys). Before the cast the golem reads
# "A ARM   10 (base 0, +10 natural)"; after it reads
# "A ARM    5 (base 0, +10 natural, -5 armour)" and its Stati gain
# "ADJUST ARM ... (Val:A ARM Mag:-5) (eID:Soften Stone)". A slow would instead
# print "The stone golem slows down." and add ADJUST stati on A SPD.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -x "$ROOT/incursion-headless" ]; then
    echo "exit 2: no incursion-headless binary; build with BACKEND=posix ./build_macos.sh"
    exit 2
fi

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-soften-stone-golem"
mkdir -p "$RUN_DIR"

INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
    tools/headless.sh tools/keys/soften-stone-golem.keys 1 > "$RUN_DIR/session.log" 2>&1
status=$?

screens="$RUN_DIR/logs/screens"
if ! ls "$screens"/*.txt >/dev/null 2>&1; then
    echo "exit 2: no screen was written under $screens (could not see)"
    exit 2
fi

after_stati="$screens/0010-after-stati.txt"
after_golem="$screens/0009-after-golem.txt"
cast="$screens/0007-cast-enter.txt"

# Every screen, for the absence of a slow line.
all="$(cat "$screens"/*.txt 2>/dev/null)"

fail=0

# A slow line anywhere is the old behaviour: the golem slowed down instead of
# softening, which also stops the run before the after screens are written.
if grep -q "slows down" <<<"$all"; then
    echo "FAIL: the golem slowed down; Soften Stone must soften, not slow"
    fail=1
fi

if [ ! -s "$after_stati" ] || [ ! -s "$after_golem" ] || [ ! -s "$cast" ]; then
    if [ "$fail" -ne 0 ]; then
        echo "Specimen: $screens"
        echo "FAIL: Soften Stone did not soften the golem (or slowed it)."
        exit 1
    fi
    echo "exit 2: the expected aim/dump screens were not written under $screens"
    exit 2
fi

if ! grep -q "stone body softens" <<<"$all"; then
    echo "FAIL: no \"stone body softens\" prose in the run"
    fail=1
fi

if ! grep -q "ADJUST ARM from SS ENCH (Val:A ARM Mag:-5)" "$after_stati"; then
    echo "FAIL: the golem's Stati after the cast do not show"
    echo "      ADJUST ARM ... (Val:A ARM Mag:-5)"
    fail=1
fi

if ! grep -q "A ARM    5 (base 0, +10 natural, -5 armour)" "$after_golem"; then
    echo "FAIL: the golem's A ARM after the cast is not 5 with -5 armour"
    fail=1
fi

echo "Specimen: $screens"
echo "Session exit: $status"
if [ "$fail" -ne 0 ]; then
    echo "FAIL: Soften Stone did not soften the golem (or slowed it)."
    exit 1
fi
echo "PASS: Soften Stone softened the golem's body (A ARM 10 -> 5, ADJUST ARM -5) and did not slow it."
exit 0
