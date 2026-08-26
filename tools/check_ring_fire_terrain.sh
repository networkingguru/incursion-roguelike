#!/bin/bash
# Regression check for PA-08-F24, inc-tek.8.8: the Ring of Fire Resistance
# promises that its wearer can cross fiery terrain, but magma refused her.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: build with BACKEND=posix ./build_macos.sh"
    exit 2
}

run_one() {
    local keys=$1 out
    out="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh "$keys" 1 2>&1)"
    echo "$out" | awk '/^run:/ {print $2}'
    if echo "$out" | grep -qE 'NO GAMEPLAY|the key script looked for something'; then
        echo "INCONCLUSIVE: the run did not complete its measurement" >&2
        echo "$out" >&2
        return 2
    fi
}

RRUN="$(run_one tools/keys/ring-fire-terrain.keys)" || exit $?
CRUN="$(run_one tools/keys/ring-fire-terrain-control.keys)" || exit $?
RWORN="$RRUN/logs/screens/0001-ring-worn.txt"
RBEFORE="$RRUN/logs/screens/0002-ring-before.txt"
RAFTER="$RRUN/logs/screens/0004-ring-after.txt"
CBEFORE="$CRUN/logs/screens/0001-control-before.txt"
CAFTER="$CRUN/logs/screens/0003-control-after.txt"
for f in "$RWORN" "$RBEFORE" "$RAFTER" "$CBEFORE" "$CAFTER"; do
    [ -f "$f" ] || { echo "INCONCLUSIVE: missing measurement screen $f"; exit 2; }
done

grep -Fq 'Ring +5 of Fire Resistance' "$RWORN" || {
    echo "INCONCLUSIVE: the ring run did not wear a Ring +5 of Fire Resistance"
    exit 2
}

at_col() { awk 'index($0,"@") { print index($0,"@"); exit }' "$1"; }
rb="$(at_col "$RBEFORE")"; ra="$(at_col "$RAFTER")"
cb="$(at_col "$CBEFORE")"; ca="$(at_col "$CAFTER")"
rprompt=0; grep -Fq 'Confirm enter the magma?' "$RAFTER" && rprompt=1
cprompt=0; grep -Fq 'Confirm enter the magma?' "$CAFTER" && cprompt=1

echo "Ring of Fire Resistance: column $rb -> $ra; refused: $rprompt"
echo "No-ring control:          column $cb -> $ca; refused: $cprompt"
if [ "$ra" -ne $((rb + 1)) ] || [ "$rprompt" -ne 0 ]; then
    echo "FAIL: the ring wearer did not cross the magma"
    exit 1
fi
if [ "$ca" -ne "$cb" ] || [ "$cprompt" -ne 1 ]; then
    echo "FAIL: the no-ring control was not refused by the magma"
    exit 1
fi
echo "PASS: the ring wearer crosses magma and the no-ring control is refused"
