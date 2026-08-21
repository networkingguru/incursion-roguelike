#!/bin/bash
# Regression check for the monk's Ki Strike grant.
#
# The rule: lib/classes.irh gives the Monk Ability[CA_KI_STRIKE] at every 4th
# level starting at 4th. The grant sat commented out, so nothing in the compiled
# module granted the ability, and src/Fight.cpp:4112 -- the only thing that lets
# an unarmed attacker damage an incorporeal creature -- could never fire.
#
# The character sheet is the oracle. src/Sheet.cpp:546 renders the ability as a
# signed plus and src/Tables.cpp:3476 supplies the name "Ki Strike", so a Monk 4
# who has the grant reads "Ki Strike +1" in the Special Abilities block and one
# who does not reads nothing at all. Numbers on both sides, one variable: the
# same session photographs the block at 1st level and again at 4th.
#
# This check reads a COMPILED MODULE, not the binary. A source edit to lib/ does
# nothing until ./incursion -compile main.irc has been run, so a red result here
# after editing lib/classes.irh usually means the module was not rebuilt.
#
# Usage: tools/check_ki_strike_live.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/monk-ki-strike.keys
WANT="Ki Strike +1"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: that mistake is
# inc-loa.3. The character sheet is only reachable from inside a map.
if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected. The character"
    echo "      probably never reached 4th level; read $run/logs/screens."
    exit 1
fi

lvl1="$run/logs/screens/0001-specials1.txt"
lvl4="$run/logs/screens/0003-specials4.txt"
mark="$run/logs/screens/0002-level4.txt"

for f in "$lvl1" "$mark" "$lvl4"; do
    [ -f "$f" ] || { echo "FAIL: no screen dump at $f"; exit 1; }
done

# The dumps are scrolled past the class line, so the level is proved by its own
# screen rather than by the block being read.
grep -q "Monk 4" "$mark" || {
    echo "FAIL: $mark does not show Monk 4; the level-ups did not happen."
    exit 1
}
# And both blocks must actually be on screen, or "no Ki Strike" proves nothing.
for f in "$lvl1" "$lvl4"; do
    grep -q "Special Abilities" "$f" || {
        echo "FAIL: $f does not show the Special Abilities block, so its"
        echo "      absence of '$WANT' means nothing. The sheet layout moved."
        exit 1
    }
done

got1="$(grep -c "$WANT" "$lvl1")"
got4="$(grep -c "$WANT" "$lvl4")"

echo
echo "Monk 1 Special Abilities, lines matching '$WANT': $got1"
echo "Monk 4 Special Abilities, lines matching '$WANT': $got4"

fail=0
if [ "$got1" -ne 0 ]; then
    echo "FAIL: a 1st-level monk shows '$WANT'. The grant starts at 4th."
    fail=1
fi
if [ "$got4" -lt 1 ]; then
    echo "FAIL: a 4th-level monk shows no '$WANT'."
    echo "      Either lib/classes.irh no longer grants Ability[CA_KI_STRIKE],"
    echo "      or mod/Incursion.Mod was not rebuilt: ./incursion -compile main.irc"
    fail=1
fi

[ "$fail" -eq 0 ] && echo && echo "PASS: Ki Strike is absent at Monk 1 and reads '$WANT' at Monk 4."
exit "$fail"
