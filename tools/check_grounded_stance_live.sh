#!/bin/bash
# Regression check for bd inc-brp: the Earthsinger's Grounded Stance added no
# damage even when every condition it names was met.
#
# THE DEFECT. The ability rides a TRAP_EVENT stati whose Mag is PRE(EV_HIT)
# (lib/prestige.irh:1598). src/Event.cpp:325-336 walks those stati, rewrites
# e.Event to META(e.Event) and only then calls the effect, so the handler the
# engine asks for is named META(PRE(EV_HIT)). Grounded Stance declared its
# handler as plain PRE(EV_HIT), a name no trap dispatch ever asks for, so the
# body never ran. Every other trap in lib/ pairs the two the other way round
# -- Divine Sacrifice (lib/pspells.irh:1117,1132) and Death Attack
# (lib/prestige.irh:600,652) both declare META(PRE(EV_HIT)).
#
# THE ORACLE is the damage roll. The handler appends its own term to the
# damage string, " %+d GS" (lib/prestige.irh:1610), and src/Fight.cpp prints
# that string in the "Damage:" line. So a landed blow either says GS or the
# ability did not fire. Nothing else in the game writes " GS" into a damage
# roll.
#
# WHAT THE SESSION SETS UP. tools/keys/prestige-earthsinger.keys builds a rock
# gnome Bard 7 / Earthsinger 2, turns on the wizard switch "Show All Combat
# Rolls", summons a stone jelly one square east, hits it three times and then
# opens the message log. The character is Afoot, on the material plane, on
# ordinary cave floor, and his boot slot is empty, so all four guards in the
# handler pass and the ability owes him +2 on every blow.
#
# WHY THE MESSAGE LOG and not the map screen: the roll panel under the map
# keeps only the newest roll, and the jelly answers every blow, so a screen
# dumped after a blow shows the jelly's attack. The log keeps them all.
#
# BEFORE THE FIX every landed blow read "Bofi's Damage: 1d6 = 6 vs. Arm 10 =
# 0" -- three damage rolls, not one GS term in the run.
#
# Usage: tools/check_grounded_stance_live.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=3
KEYS=tools/keys/prestige-earthsinger.keys
# The character is an Earthsinger 2, so the term the effect writes is this one.
TERM_WANTED="+2 GS"

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

# A session that measured nothing must never read as a pass: inc-loa.3.
if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected; read"
    echo "      $run/logs/screens for the one it was looking at."
    exit 1
fi

summon="$run/logs/screens/0001-gs-summoned.txt"
log="$run/logs/screens/0005-gs-log.txt"
for f in "$summon" "$log"; do
    [ -f "$f" ] || { echo "FAIL: no screen dump at $f"; exit 1; }
done

# The log is drawn as a box floating over the map, so every one of its lines
# has the map to the left of a '|' and the sidebar to the right of another.
# Keep what is between them, and flatten it: the box wraps a long roll onto a
# second line, and it wraps at a different column once a roll grows an extra
# term -- which is exactly the difference this check is looking for.
logtext() {
    awk -F'|' 'NF>=3 { s=""; for (i=2;i<NF;i++) s = s $i; print s }' "$1" \
        | tr '\n' ' ' | tr -s ' '
}

flat="$(logtext "$log")"

# Guard 1: the character is the one the ability belongs to. A Bard 7 with no
# prestige level would print no GS term for an honest reason.
grep -q "Earthsinger 2" "$summon" || {
    echo "INCONCLUSIVE: the character is not an Earthsinger 2, so the key"
    echo "              script has rotted. Nothing was measured."
    grep -m2 "Bard\|Earthsinger" "$summon"
    exit 1
}

# Guard 2: the jelly was standing beside him, drawn as the glyph pair &j.
grep -q "&j" "$summon" || {
    echo "FAIL: $summon does not show the summoned stone jelly beside the"
    echo "      player. Wizard-mode summoning did not place it; nothing was hit."
    exit 1
}

# Guard 3: blows landed and printed damage rolls. Three misses prove nothing.
# A damage roll reads "Bofi's Damage: <dice and terms> = <total> vs. ...", and
# the dice part holds no '=' , so everything up to the first one is the part
# Grounded Stance writes into.
rolls="$(echo "$flat" | grep -o "Bofi's Damage: [^=]*=")"
n_rolls="$(echo "$rolls" | grep -c "Damage:")"
if [ "$n_rolls" = 0 ]; then
    echo "INCONCLUSIVE: no blow landed, so no damage roll was printed and"
    echo "              nothing was measured. The log is $log."
    exit 1
fi

n_gs="$(echo "$rolls" | grep -c -- "$TERM_WANTED")"

echo
echo "the gnome's damage rolls in this session:"
echo "$rolls" | sed 's/^/  /'
echo
echo "rolls: $n_rolls   carrying '$TERM_WANTED': $n_gs"
echo

if [ "$n_gs" = 0 ]; then
    echo "FAIL: not one landed blow carried the '$TERM_WANTED' term. Grounded"
    echo "      Stance did not fire, though the gnome is Afoot, on the material"
    echo "      plane, on cave floor and barefoot. That is bd inc-brp: the"
    echo "      handler is declared PRE(EV_HIT) where the trap dispatch calls"
    echo "      META(PRE(EV_HIT)) (src/Event.cpp:325-336)."
    exit 1
fi

if [ "$n_gs" != "$n_rolls" ]; then
    echo "FAIL: $n_gs of $n_rolls landed blows carried '$TERM_WANTED'. The"
    echo "      ability is firing intermittently, which no guard in the handler"
    echo "      explains: nothing about the character changed between blows."
    exit 1
fi

echo "PASS: all $n_rolls of the gnome's damage rolls added his Earthsinger"
echo "      level, as '$TERM_WANTED'"
exit 0
