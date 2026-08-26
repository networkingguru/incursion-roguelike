#!/bin/bash
# Regression check for PA-08-F28 / inc-tek.8.8.
#
# Rule: the Wand of Acid's residual 1d6 burn is acid damage. Both branches of
# its EV_TURN handler incorrectly used AD_FIRE, even though the blast, messages
# and page all call it acid.
#
# Oracle: numeric HP from Creature::Dump across the two observable turns left
# after a +4 wand activation spends enough time to pay its first two turns. The
# hell hound is immune to fire and has no acid resistance
# (lib/mon4.irh:1985-1997), so the unfixed burn dealt 0 residual and the fixed
# burn must lower HP on both turns. Measured red: hell hound 46/46/46 (0, 0
# residual). Measured green: hell hound 37/31/29 (6, 2 residual).
#
# No acid-immune second side is reachable: acid immunity rejects the initial
# acid blast before POST(EV_MAGIC_HIT) attaches the residual TRAP_EVENT. This
# was checked with the caustic fungus (lib/mon3.irh:2382-2395): even when the
# residual constant was deliberately restored to AD_FIRE, it stayed at 65 HP.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }

OUT="$(INCURSION_OPTIONS=tools/gates/Options.Dat tools/headless.sh tools/keys/wand-acid-type.keys 1 2>&1)"
RUN="$(echo "$OUT" | awk '/^run:/ {print $2}')"
if echo "$OUT" | grep -q "NO GAMEPLAY"; then
    echo "FAIL: the run never entered a map, so it measured nothing."
    echo "$OUT"; exit 1
fi
if echo "$OUT" | grep -q "the key script looked for something"; then
    echo "FAIL: the key script missed an expected screen; read $RUN/logs/screens."
    echo "$OUT"; exit 1
fi

SCR="$RUN/logs/screens"
WAND="$(ls "$SCR"/*-wand.txt 2>/dev/null | head -1)"
[ -n "$WAND" ] || { echo "FAIL: missing wand acquisition screen"; exit 1; }
grep -qi "Wand +4 of Acid" "$WAND" || {
    echo "FAIL: acquisition did not produce a known Wand +4 of Acid"; exit 1;
}
FIRE_HIT="$(ls "$SCR"/*-fire-hit.txt 2>/dev/null | head -1)"
[ -n "$FIRE_HIT" ] || { echo "FAIL: missing the wand activation screen"; exit 1; }
grep -qi "glob of acid strikes a hell hound" "$FIRE_HIT" || {
    echo "FAIL: fire-hit does not prove that the first activation landed"; exit 1;
}

hp_of() { grep -m1 '^HP:.*Subdual:.*CR:' "$1" | sed 's/^HP:\([0-9]*\)\/.*/\1/'; }
read_hp_series() {
    local stem="$1" creature="$2" n f v
    SERIES=()
    for n in 0 1 2 3 4 5; do
        f="$(ls "$SCR"/*-"$stem"-hp-"$n".txt 2>/dev/null | head -1)"
        [ -n "$f" ] || { echo "FAIL: missing $stem HP reading $n"; exit 1; }
        grep -q "$creature (class" "$f" || {
            echo "FAIL: $f does not show the $creature dump"; exit 1;
        }
        v="$(hp_of "$f")"
        [ -n "$v" ] || { echo "FAIL: $f does not show the creature HP block"; exit 1; }
        SERIES+=("$v")
    done
}

read_hp_series fire "hell hound"; FIRE=("${SERIES[@]}")
FD1=$(( FIRE[0] - FIRE[1] )); FD2=$(( FIRE[1] - FIRE[2] )); FD3=$(( FIRE[2] - FIRE[3] ))
FD4=$(( FIRE[3] - FIRE[4] )); FD5=$(( FIRE[4] - FIRE[5] ))

echo "Wand of Acid +4 residual damage (two post-activation burn turns):"
echo "  fire-immune hell hound HP: ${FIRE[*]} (burn drops $FD1, $FD2; after-window $FD3, $FD4, $FD5)"

fail=0
if [ "$FD1" -le 0 ] || [ "$FD2" -le 0 ] || [ "$FD3" -ne 0 ] || [ "$FD4" -ne 0 ] || [ "$FD5" -ne 0 ]; then
    echo "FAIL: fire-immune victim must lose HP on both observable acid-burn turns, then stop."
    fail=1
fi
[ "$fail" -eq 0 ] && echo "PASS: residual burn damages the fire-immune victim as acid."
exit "$fail"
