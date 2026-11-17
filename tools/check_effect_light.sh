#!/bin/bash
# gate: live
# inc-jw0hw: a magical effect lights the squares it covers. Case A: a fire
# flash on one square of a dark room lights that square, shows it in the
# player's view in fire color, dims (without hiding it) when its level drops,
# and leaves it dark when removed. Later cases add each effect shape.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal
# fact: terrain and darkness -- the probe builds the map and clears legacy Lit/Bright
# fact: monsters -- placed by the probe at fixed offsets
# fact: effect radii and colors -- read from the data by the probe (TEFF lval, cval)
# fact: which squares are struck -- no roll decides them (as check_ball_shape.sh)
# fact: player's sight in case C -- the probe makes the player's eight neighbors opaque
# fact: aim square -- the probe aims every cast at (PX+8, PY), a fixed offset from the player's fixed square
# fact: kobold squares -- the probe places each kobold at a fixed offset from the aim square or the player
# fact: messages a cast prints -- the same seeded run twice, flash on and flash off; the probe records MsgHistory
# Cases B (Fireball) and B2 (a globe, Sleep) add: the effect lights while it shows, is gone at its
# end hook and after the cast returns, and a flash on and a flash off print the same set of messages.
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE or no EFFECT_LIGHT line.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
KEYS=tools/keys/effect-light.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light"
INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

OFF_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-off"
INCURSION_EFFECT_LIGHT_OFF=1 INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 \
    INCURSION_RUN_DIR="$OFF_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log. The probe never wrote anything -- is"
    echo "      EffectLightProbe still called from Game::Play()?"
    exit 2
fi

lines="$(grep -a 'EFFECT_LIGHT:' "$log")"
if [ -z "$lines" ]; then
    echo "INCONCLUSIVE: $log has no EFFECT_LIGHT lines."
    exit 2
fi

echo "$lines"
echo "Specimen: $log"

# The light dump must name the flash: F <id> <cells> <reach> <style> <level>.
dump="$RUN_DIR/logs/light.log"
if ! grep -Eq '^F [0-9]+ 1 2 1 ' "$dump" 2>/dev/null; then
    echo "FAIL: $dump has no F line for the one-square fire flash."
    exit 1
fi

last="$(tail -n 1 <<< "$lines")"
case "$last" in
    *"EFFECT_LIGHT: PASS")
        # Review Focus 2: the set of messages a cast prints must not depend on the flash.
        msg_on="$(grep -a 'EFFECT_LIGHT: MSG ' "$log" | sed 's/^[0-9-]* [0-9:]* *//' | sort)"
        msg_off="$(grep -a 'EFFECT_LIGHT: MSG ' "$OFF_DIR/logs/errors.log" 2>/dev/null | sed 's/^[0-9-]* [0-9:]* *//' | sort)"
        if [ -z "$msg_on" ] || [ -z "$msg_off" ]; then
            echo "INCONCLUSIVE: a run recorded no cast messages (on: $(grep -c . <<< "$msg_on"), off: $(grep -c . <<< "$msg_off"))."
            exit 2
        fi
        if [ "$msg_on" != "$msg_off" ]; then
            echo "FAIL: the Fireball's messages differ with the flash on and off."
            diff <(echo "$msg_on") <(echo "$msg_off") | head -10
            exit 1
        fi
        echo "messages: $(grep -c . <<< "$msg_on") line(s), identical with the flash on and off"
        echo "PASS: an effect's squares light, show in its color, dim without hiding, and go dark."
        exit 0 ;;
    *"EFFECT_LIGHT: FAIL")
        echo "FAIL: at least one effect-light rule failed."
        exit 1 ;;
    *)
        echo "INCONCLUSIVE: no verdict, or a case could not be established."
        exit 2 ;;
esac
