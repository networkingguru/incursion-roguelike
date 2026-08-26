#!/bin/bash
# Regression check for PA-08-F26 / inc-tek.8.8: the Enchant Armour (graceful)
# scroll must advertise the graceful quality, not featherlight.
#
# WHAT WAS WRONG. Its Desc was copied verbatim from Enchant Armour
# (featherlight), although its script tests and grants AQ_GRACEFUL.
#
# THE ORACLE is the item description screen the game renders from the compiled
# module. One wizard-mode session Auto-Identifies and acquires both scrolls,
# then Inventory Mode's x opens each page. Each box must name its own scroll
# and show the unchanged provided-that clause before its words are trusted.
#
# MEASURED, seed 1:
#   BEFORE: graceful page said "bestow the featherlight quality".
#   AFTER:  graceful page says "bestow the graceful quality"; the featherlight
#           control still says "bestow the featherlight quality".
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
              if (s != "") printf "%s ", s }
    ' "$1"
}

graceful_file="$run/logs/screens/0001-graceful.txt"
feather_file="$run/logs/screens/0002-featherlight.txt"
for f in "$graceful_file" "$feather_file"; do
    [ -f "$f" ] || { echo "FAIL: no description screen at $f"; exit 1; }
done

graceful="$(box_text "$graceful_file")"
feather="$(box_text "$feather_file")"
for spec in "graceful|$graceful|$graceful_file" \
            "featherlight|$feather|$feather_file"; do
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

echo "Graceful scroll page: $(printf '%s' "$graceful" | grep -o 'bestow the [a-z]* quality' | head -1)"
echo "Featherlight control page: $(printf '%s' "$feather" | grep -o 'bestow the [a-z]* quality' | head -1)"

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

[ "$fail" -eq 0 ] && echo "PASS: both Enchant Armour scroll pages advertise their own qualities."
exit "$fail"
