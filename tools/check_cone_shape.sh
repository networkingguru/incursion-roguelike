#!/bin/bash
# gate: live
# inc-epzc0: a cone (AR_CONE) strikes the quarter circle of its length (lval) in
# front of the caster, allies and a hallway overflow included, stops at a wall,
# aims at a target square, draws one band per frame at 70 ms then holds 300 ms,
# agrees with the monster prediction, and the breath of a gold dragon is a cone
# while a black dragon's breath and a frog's spit stay beams. Casts Cone of Cold,
# Ice;wand and the Dragon tattoo; the probe also casts Fear, Shout, Blasting.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: terrain of each case -- the probe builds the map (open room, one-wide hallway, walled room) after it removes every thing but the player
# fact: monsters of each case -- placed by the probe at fixed offsets from the caster; one is made the player's ally by the probe
# fact: the length of each cone -- read from the data by the probe (TEFF lval; 5 when the data has none), which grades against an independent cone of that length
# fact: the length-3 hallway case -- the probe sets the effect's lval to 3 for that one cast and restores it
# fact: struck squares -- no roll decides them; the fill is a fixed walk from the caster, and damage and saving throws do not change which squares it strikes
# fact: a creature takes damage -- INCURSION_FORCE_SAVE_ROLL=1, so no save halves or negates it; Cone of Cold damage is 1 or more
# fact: the caster's cone aim -- a direction (east) or a square the probe names
# fact: the breath of each monster -- the probe starts the monster's own natural attack (EV_SATTACK) at a fixed range, and grades only the shape: cone fill or beam, squares struck above 1
# fact: the frames and waits of the wave -- EffectLightHook and EffectWaitHook record every band frame and wait; the game takes no real time with no display
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE or no CONE_PROBE line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/cone-shape.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-cone-shape"
INCURSION_CONE_PROBE=1 INCURSION_FORCE_SAVE_ROLL=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log. The probe never wrote anything -- is"
    echo "      ConeShapeProbe still called from Game::Play()?"
    exit 2
fi

lines="$(grep 'CONE_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "INCONCLUSIVE: $log has no CONE_PROBE lines."
    exit 2
fi

echo "$lines" | grep -E 'CONE_PROBE: ([A-Z]+ (PASS|FAIL) |CASE |DONE|.*INCONCLUSIVE)'
echo "Specimen: $log"

if grep -q 'CONE_PROBE: .*INCONCLUSIVE' <<< "$lines"; then
    echo "INCONCLUSIVE: the probe could not set a case up."
    exit 2
fi
if ! grep -q 'CONE_PROBE: DONE' <<< "$lines"; then
    echo "INCONCLUSIVE: the probe never reached DONE."
    exit 2
fi

missing=0
for c in OPEN OFFAXIS WALL HALL WAVE PREDICT BREATH ITEMS; do
    if ! grep -qE "CONE_PROBE: CASE $c PASS checks=[1-9]" <<< "$lines" &&
       ! grep -qE "CONE_PROBE: CASE $c FAIL" <<< "$lines"; then
        echo "MISSING: no CASE $c line."
        missing=1
    fi
done
[ "$missing" -eq 1 ] && exit 2

if grep -qE 'CONE_PROBE: [A-Z]+ FAIL ' <<< "$lines" ||
   grep -qE 'CONE_PROBE: CASE [A-Z]+ FAIL' <<< "$lines"; then
    echo "FAIL: at least one cone rule failed (the FAIL lines above)."
    exit 1
fi
echo "PASS: a cone strikes its quarter circle in open floor, hallway and behind a wall, aims at a target, waves band by band, matches the prediction, and only the gold dragon's breath is a cone."
exit 0
