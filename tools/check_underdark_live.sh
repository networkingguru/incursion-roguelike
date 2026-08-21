#!/bin/bash
# Regression check for the two Underdark Warrior fixes of bd inc-tek.8.3:
# PA-03-F12 (the race requirement was never checked) and PA-03-F13 (the class
# advertised a good Reflex save and its flags gave the poor track).
#
# TWO CHARACTERS, built the same way apart from their race, because one
# character can only prove half of PA-03-F12. Before the fix the gate had no
# race test at all, so an admitted deep gnome looks identical on both
# modules. It is the REFUSAL that changed.
#
#   tools/keys/underdark-deepgnome.keys   admitted, and levels to 5
#   tools/keys/underdark-greyelf.keys     meets everything except race
#
# Both are Rogue 6 with Endurance, Roll With It, Toughness and Blind
# Fighting, Move Silently, Hide and Climb filled to their caps, and a bought
# Wisdom that each race's own bonus lifts past 17. The only difference is the
# race, so the only thing the two outcomes can differ by is the race clause.
#
# THE ORACLES
#   PA-03-F12  the refusal message on screen, and the absence of an Underdark
#              Warrior line on the sheet behind it. On the pre-fix module the
#              grey elf is admitted and reads "Underdark Warrior 0".
#   PA-03-F13  the sheet's Reflex line, which names each class's own share.
#              src/Values.cpp:395 picks the track from CF_GOOD_REF, and the
#              engine's tables (src/Tables.cpp:100-116) give GoodSave[5] = +4
#              and PoorSave[5] = +1. The pre-fix module prints +1 where the
#              class's own level table prints +4.
#
# Usage: tools/check_underdark_live.sh      (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=3

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

fail=0

# ---- PA-03-F13, and the admitting half of PA-03-F12 --------------------
OUT="$(tools/headless.sh tools/keys/underdark-deepgnome.keys "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
DUMP="$RUN/logs/udwar.txt"

if [ ! -f "$DUMP" ]; then
    echo "FAIL: the deep gnome's dump was never written to $DUMP"
    echo "$OUT" | tail -8
    fail=1
elif ! grep -q "Underdark Warrior 5" "$DUMP"; then
    echo "INCONCLUSIVE: the deep gnome is not a 5th-level Underdark Warrior,"
    echo "              so the key script has rotted. Nothing was measured."
    fail=1
else
    echo "  ok: a deep gnome is admitted, and reaches Underdark Warrior 5"
    # The Reflex line is abbreviated when it grows too long, so it reads
    # "Reflex +22(+5/+4 +5Dx +6Co +2Na)" -- Rogue +5 / Underdark Warrior +4.
    # Fortitude keeps its long form and is the control: that track was
    # already good and must not have moved.
    if grep -q "^Reflex .*(+5/+4 " "$DUMP"; then
        echo "  ok: his Underdark Warrior levels give Reflex +4, the good track"
    else
        echo "FAIL: the Underdark Warrior's share of Reflex is not the good +4"
        grep -m1 "^Reflex" "$DUMP"
        fail=1
    fi
    if grep -q "Fortitude .*Underdark Warrior +4," "$DUMP"; then
        echo "  ok: Fortitude is untouched at +4, as the control"
    else
        echo "FAIL: Fortitude moved, so something other than CF_GOOD_REF changed"
        grep -m1 "Fortitude" "$DUMP"
        fail=1
    fi
fi

# ---- the refusing half of PA-03-F12 ------------------------------------
OUT="$(tools/headless.sh tools/keys/underdark-greyelf.keys "$SEED" 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
SCR="$RUN/logs/screens/0001-refused.txt"

if [ ! -f "$SCR" ]; then
    echo "FAIL: the grey elf's refusal screen was never dumped"
    echo "$OUT" | tail -8
    fail=1
else
    # Guard: he must have got as far as being a Rogue 6, or he was refused
    # for some reason that has nothing to do with race.
    if ! grep -q "Class  Rogue 6" "$SCR"; then
        echo "INCONCLUSIVE: the grey elf is not a Rogue 6, so the key script"
        echo "              has rotted. Nothing was measured."
        fail=1
    else
        if grep -q "native to the Underdark" "$SCR"; then
            echo "  ok: a grey elf is refused, by the race clause and no other"
        else
            echo "FAIL: the grey elf was not refused on race"
            fail=1
        fi
        if grep -q "Underdark" "$SCR" && grep -q "Warrior 0" "$SCR"; then
            echo "FAIL: the grey elf took the class anyway"
            fail=1
        else
            echo "  ok: and the class was not added to him"
        fi
    fi
fi

if [ "$fail" = 0 ]; then
    echo "PASS: the Underdark Warrior admits a deep gnome, refuses a grey elf,"
    echo "      and gives the good Reflex save his own table prints"
    exit 0
fi
exit 1
