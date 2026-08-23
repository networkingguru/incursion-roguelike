#!/bin/bash
# Regression check: the unfinished prestige classes must not be offered.
#
# WHAT THE DEFECT WAS. Eight prestige classes in lib/prestige.irh have never
# been implemented. Each opens its description with "*** NOT FINISHED YET ***"
# and each carries the same placeholder body -- HitDice: 4; Mana: 12; Def: 1/4;
# Skills[0]: 0; no grants and no good-save flags -- while six of the eight also
# print a stat header advertising values that body does not honour.
#
# They were still listed in the class menu. The refusal sits on EV_ISTARGET,
# which fires AFTER the player picks the class, so the sequence a player saw was
# "choose Bladesinger" then "This prestige class is still under development and
# cannot be used." Brian's ruling on 2026-08-23: do not display them, and keep
# every line of their prose as the guide for implementing them later.
#
# THE FIX. Each of the eight gained CF_PSEUDO, the flag the engine already uses
# to keep a class out of every list. Every site that builds a class list skips
# it: src/Managers.cpp:2271 (the [P]restige and [M]ulticlass menus),
# src/Create.cpp:306 (character generation), src/Help.cpp:763, :789 and :840
# (the class-description menu and the printed help pages) and src/Skills.cpp:97
# (the "which classes take this skill" line). Nothing else in the engine reads
# the flag, so no mechanic changed and no prose was deleted.
#
# WHAT THIS CHECK PROVES. It photographs the prestige menu a player actually
# sees and asserts that none of the eight names is on it, and that the eleven
# finished classes still are. The second half is the control: a menu that
# failed to open, or opened empty, would otherwise pass the first half.
#
# Ends: 0 pass, 1 fail, 2 the check could not be run.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-1}"
KEYS="tools/keys/prestige-hidden.keys"
OPTS="$ROOT/tools/gates/Options.Dat"
BIN="${INCURSION_BIN:-./incursion-headless}"

HIDDEN=("Bladesinger" "Celestial Initiate" "Crimson Adept" "Duelist" \
        "Elementalist" "Horizon Walker" "Inquisitor" "Undead Slayer")
SHOWN=("Alienist" "Assassin" "Blackguard" "Earthsinger" "Loremaster" \
       "Master Archer" "Sentinel" "Shadowdancer" "Tattoo Mystic" \
       "Twilight Huntsman" "Underdark Warrior")

[ -x "$BIN" ] || {
    echo "INCONCLUSIVE: $BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTS" ] || { echo "INCONCLUSIVE: no settings file at $OPTS"; exit 2; }
[ -f "$KEYS" ] || { echo "INCONCLUSIVE: no key script at $KEYS"; exit 2; }

RUN="$(mktemp -d "${TMPDIR:-/tmp}/incursion-preshidden.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT

INCURSION_RUN_DIR="$RUN/game" INCURSION_OPTIONS="$OPTS" INCURSION_BIN="$BIN" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN/out" 2>&1

DUMP="$(ls "$RUN/game/logs/screens/"*prestige-menu* 2>/dev/null | head -1)"
if [ -z "$DUMP" ]; then
    echo "INCONCLUSIVE: the run never reached the prestige menu, so it measured"
    echo "              nothing about which classes are offered."
    sed -n '/--- after the session ---/,$p' "$RUN/out"
    exit 2
fi

# Only the menu itself. The description pane under it prints the highlighted
# class's whole Desc:, and matching a class name in that prose would be noise.
MENU="$RUN/menu.txt"
sed -n '/Choose a class:/,/^ *$/p' "$DUMP" | grep '\[' > "$MENU"
if [ ! -s "$MENU" ]; then
    echo "INCONCLUSIVE: the 'Choose a class:' box held no lettered entries."
    exit 2
fi

fail=0

# The control first: if the finished classes are missing, the check has nothing
# to say about the unfinished ones and must not pretend otherwise.
for name in "${SHOWN[@]}"; do
    grep -q "$name" "$MENU" || {
        echo "INCONCLUSIVE: the finished class '$name' is not on the menu either,"
        echo "              so this run cannot tell you whether the fix works."
        cat "$MENU"
        exit 2
    }
done

for name in "${HIDDEN[@]}"; do
    if grep -q "$name" "$MENU"; then
        echo "FAIL: '$name' is offered to the player. It is unfinished, so its"
        echo "      Flags line in lib/prestige.irh has lost CF_PSEUDO."
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "PASS: the prestige menu offers the ${#SHOWN[@]} finished classes and none of"
    echo "      the ${#HIDDEN[@]} unfinished ones."
fi
exit "$fail"
