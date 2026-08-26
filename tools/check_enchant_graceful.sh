#!/bin/bash
# Regression check for PA-08-F26, PA-08-F27, PA-08-F29, PA-08-F30,
# PA-08-F31 and PA-08-F32 / inc-tek.8.8: six corrected item pages must
# advertise their own scripted qualities, prerequisite, spells or bonus type,
# while the unchanged featherlight scroll is the control.
#
# WHAT WAS WRONG. Both Descs were copied verbatim from Enchant Armour
# (featherlight), although their scripts test and grant AQ_GRACEFUL and
# AQ_LIFEKEEPING respectively.
#
# THE ORACLE is the item description screen the game renders from the compiled
# module. One wizard-mode session Auto-Identifies and acquires all three scrolls,
# the Staff of the Goblin Queen, the Staff of Exorcism and the Staff of
# Abjuration and the Staff of Wind and Water, then Inventory Mode's x opens
# each page.
# Each box must name its own item and show its own description block before its
# words are trusted.
#
# MEASURED, seed 1:
#   BEFORE: graceful page said "bestow the featherlight quality".
#   AFTER:  graceful page says "bestow the graceful quality"; the featherlight
#           control still says "bestow the featherlight quality".
#   BEFORE: life-keeping page said "bestow the featherlight quality".
#   AFTER:  life-keeping page says "bestow the life-keeping quality"; the
#           featherlight control still says "bestow the featherlight quality".
#
# Usage: tools/check_enchant_graceful.sh    (exits 0 on pass, 1 on fail)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/enchant-graceful.keys

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 1
}

out="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$KEYS" "$SEED" 2>&1)"
run="$(echo "$out" | awk '/^run:/ {print $2}')"

if echo "$out" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$out"
    exit 1
fi
if echo "$out" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script did not find a screen it expected."
    echo "$out"
    exit 1
fi

box_text() {
    awk '
      /#-+#/ { if (!seen) { match($0,/#-+#/); L=RSTART; W=RLENGTH; seen=1; next }
               else exit }
      seen  { s = substr($0, L+1, W-2)
              sub(/ +[\^v]$/, "", s)
              gsub(/^ +| +$/, "", s)
              gsub(/[[:space:]]+/, " ", s)
              if (s != "") printf "%s ", s }
    ' "$1"
}

graceful_file="$run/logs/screens/0001-graceful.txt"
feather_file="$run/logs/screens/0002-featherlight.txt"
lifekeeping_file="$run/logs/screens/0003-life-keeping.txt"
goblin_file="$run/logs/screens/0004-goblin-queen.txt"
exorcism_file="$run/logs/screens/0005-exorcism.txt"
abjuration_file="$run/logs/screens/0006-abjuration.txt"
wind_water_file="$run/logs/screens/0007-wind-water.txt"
for f in "$graceful_file" "$feather_file" "$lifekeeping_file" "$goblin_file" "$exorcism_file" "$abjuration_file" "$wind_water_file"; do
    [ -f "$f" ] || { echo "FAIL: no description screen at $f"; exit 1; }
done

graceful="$(box_text "$graceful_file")"
feather="$(box_text "$feather_file")"
lifekeeping="$(box_text "$lifekeeping_file")"
goblin="$(box_text "$goblin_file")"
exorcism="$(box_text "$exorcism_file")"
abjuration="$(box_text "$abjuration_file")"
wind_water="$(box_text "$wind_water_file")"
for spec in "graceful|$graceful|$graceful_file" \
            "featherlight|$feather|$feather_file" \
            "life-keeping|$lifekeeping|$lifekeeping_file"; do
    kind="${spec%%|*}"; rest="${spec#*|}"; page="${rest%%|*}"; file="${rest##*|}"
    case "$page" in
        *"Enchant Armour ($kind)"*) ;;
        *) echo "FAIL: $file does not name Enchant Armour ($kind); wrong page."; exit 1 ;;
    esac
    case "$page" in
        *"provided that the armour's item level"*) ;;
        *) echo "FAIL: $file lacks the description block; absence proves nothing."; exit 1 ;;
    esac
done
case "$goblin" in
    *"Staff Of The Goblin Queen"*) ;;
    *) echo "FAIL: $goblin_file does not name the Staff of the Goblin Queen; wrong page."; exit 1 ;;
esac
case "$exorcism" in
    *"Staff Of Exorcism"*) ;;
    *) echo "FAIL: $exorcism_file does not name the Staff of Exorcism; wrong page."; exit 1 ;;
esac
case "$abjuration" in
    *"Staff Of Abjuration"*) ;;
    *) echo "FAIL: $abjuration_file does not name the Staff of Abjuration; wrong page."; exit 1 ;;
esac
case "$wind_water" in
    *"Staff Of Wind And Water"*) ;;
    *) echo "FAIL: $wind_water_file does not name the Staff of Wind and Water; wrong page."; exit 1 ;;
esac
case "$wind_water" in
    *"bonus to Luck"*) ;;
    *) echo "FAIL: $wind_water_file lacks the staff's description block; absence proves nothing."; exit 1 ;;
esac
case "$abjuration" in
    *"allows access to the spells"*) ;;
    *) echo "FAIL: $abjuration_file lacks the staff's description block; absence proves nothing."; exit 1 ;;
esac
case "$exorcism" in
    *"access to the spells"*) ;;
    *) echo "FAIL: $exorcism_file lacks the staff's description block; absence proves nothing."; exit 1 ;;
esac
case "$goblin" in
    *"thirteen potent charms"*) ;;
    *) echo "FAIL: $goblin_file lacks the staff's description block; absence proves nothing."; exit 1 ;;
esac

echo "Graceful scroll page: $(printf '%s' "$graceful" | grep -o 'bestow the [a-z]* quality' | head -1)"
echo "Featherlight control page: $(printf '%s' "$feather" | grep -o 'bestow the [a-z]* quality' | head -1)"
echo "Life-keeping scroll page: $(printf '%s' "$lifekeeping" | grep -o 'bestow the [a-z-]* quality' | head -1)"
echo "Goblin Queen staff page: $(printf '%s' "$goblin" | grep -o '[13].. level or above' | head -1)"
echo "Exorcism staff page: Staff Of Exorcism"
echo "Abjuration staff page: $(printf '%s' "$abjuration" | grep -oE 'arcane casting levels|mage or priest' | head -1)"
echo "Wind and Water staff page: $(printf '%s' "$wind_water" | grep -oE '\+2 (circumstance|enhancement) bonus to Luck' | head -1)"

fail=0
case "$graceful" in
    *"bestow the graceful quality"*) ;;
    *) echo "FAIL: the graceful scroll does not advertise graceful."; fail=1 ;;
esac
case "$graceful" in
    *"featherlight"*) echo "FAIL: the graceful scroll still advertises featherlight."; fail=1 ;;
esac
case "$feather" in
    *"bestow the featherlight quality"*) ;;
    *) echo "FAIL: the featherlight control no longer advertises featherlight."; fail=1 ;;
esac
case "$lifekeeping" in
    *"bestow the life-keeping quality"*) ;;
    *) echo "FAIL: the life-keeping scroll does not advertise life-keeping."; fail=1 ;;
esac
case "$lifekeeping" in
    *"featherlight"*) echo "FAIL: the life-keeping scroll still advertises featherlight."; fail=1 ;;
esac
case "$goblin" in
    *"3rd level or above"*) ;;
    *) echo "FAIL: the Goblin Queen staff does not advertise its 3rd-level gate."; fail=1 ;;
esac
case "$goblin" in
    *"1st level or above"*) echo "FAIL: the Goblin Queen staff still advertises a 1st-level gate."; fail=1 ;;
esac
for spell in "aura of abjuration" "bless" "detect evil" "dispel evil" \
             "dispel magic" "magic circle vs. evil" "remove curse" "spiritwrack"; do
    case "$exorcism" in
        *"$spell"*) ;;
        *) echo "FAIL: the Staff of Exorcism does not advertise $spell."; fail=1 ;;
    esac
done
case "$abjuration" in
    *"mage or priest"*) ;;
    *) echo "FAIL: the Staff of Abjuration does not advertise arcane and divine casters."; fail=1 ;;
esac
case "$abjuration" in
    *"arcane casting levels"*) echo "FAIL: the Staff of Abjuration still advertises an arcane-only gate."; fail=1 ;;
esac
case "$wind_water" in
    *"+2 circumstance bonus to Luck"*) ;;
    *) echo "FAIL: the Staff of Wind and Water does not advertise its circumstance bonus."; fail=1 ;;
esac
case "$wind_water" in
    *"enhancement"*) echo "FAIL: the Staff of Wind and Water still advertises an enhancement bonus."; fail=1 ;;
esac

[ "$fail" -eq 0 ] && echo "PASS: all seven item pages advertise their own scripted qualities, prerequisites, spells or bonus type."
exit "$fail"
