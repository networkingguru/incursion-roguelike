#!/bin/bash
# gate: live
# inc-az4d2: a ball (AR_BALL) strikes the disc of its radius (lval), stretches
# along a corridor to the same volume, stops at a closed door, scales with
# Enlarge and Focus, strikes the same squares out of sight, holds the largest
# ball without truncation, and the monster prediction names the same victims.
# Fires Fireball (lval 2) and the Hellstorm (lval 8).
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: terrain of each case -- the probe builds the map (floor, wall, door, boxed-in player) after clearing every thing but the player
# fact: monsters in cases E and E2 -- placed by the probe, four kobolds at fixed offsets from the center
# fact: the radius of Fireball and the Hellstorm -- read from the data by the probe (TEFF lval), which grades against the disc of that radius
# fact: struck squares -- no roll decides them; the fill is a fixed walk from the center, and damage and saving throws do not change which squares it strikes
# fact: the ball's center -- the probe aims at a square 5 from the player and checks the center the fill used before it grades
# fact: the player's view in case C -- the probe makes the player's eight neighbors opaque and checks no area square is in line of sight
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE or no BALL_PROBE line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/ball-shape.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-ball-shape"
INCURSION_BALL_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log. The probe never wrote anything -- is"
    echo "      BallShapeProbe still called from Game::Play()?"
    exit 2
fi

lines="$(grep 'BALL_PROBE:' "$log")"
if [ -z "$lines" ]; then
    echo "INCONCLUSIVE: $log has no BALL_PROBE lines."
    exit 2
fi

echo "$lines"
echo "Specimen: $log"

last="$(tail -n 1 <<< "$lines")"
case "$last" in
    *"BALL_PROBE: PASS")
        echo "PASS: a ball strikes its disc or the same volume along a corridor, scaled by Enlarge and Focus, in or out of sight."
        exit 0 ;;
    *"BALL_PROBE: FAIL")
        echo "FAIL: at least one ball-shape rule failed."
        exit 1 ;;
    *)
        echo "INCONCLUSIVE: no verdict, or a case could not be established."
        exit 2 ;;
esac
