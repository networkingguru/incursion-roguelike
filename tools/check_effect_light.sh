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
# fact: a square's age -- the flash's own clock, set by the probe (LightFlashSetClock) or the sum of the ball's ring waits; never the wall clock
# fact: the ruled fire ramp -- the probe's own table (FireRampAt), from logs/ramp-mock/mock.py
# fact: messages a cast prints -- the same seeded run twice, flash on and flash off; the probe records MsgHistory
# fact: T1 kobold squares -- fixed offsets (0,-2) and (0,+2) from the aim square (PX+5, inside the fireball's own range); the probe verifies both are struck
# fact: T2 the touch lands or misses -- the probe forces the attack roll (LOFSetForcedRoll 20 for a hit, 1 for a miss)
# fact: T2 the touch spell and its hand charge -- the probe gives the player the TOUCH_ATTACK status for Chill Touch
# fact: T3 target square -- a kobold at (PX+6, PY), a fixed offset from the player's fixed square
# fact: T cases' light -- no light but the flash: the probe zeroes the player's light, infravision and shadow ranges
# fact: FW1 the fireworks cast square and radius -- the probe aims Pyrotechnics;flash at (PX+8, PY); the radius is the data's lval, read back from the hook's rings
# fact: FW1 which squares the player sees -- an open dark room, no wall inside the radius; the probe computes the expected set from its own LineOfSight call
# fact: FW1 a ring's start and stage clock -- the effect's own clock, the sum of the animation's waits (stage length from the radius); never the wall clock
# fact: FW1 each square's shape and glyph -- computed from the square's offset from the center and its stage; no roll decides them
# fact: FW1 each square's light -- born when its ring starts; the probe reads LightLevelAt and LightLitAt after the frame's refresh
# fact: LM lightning range -- the probe grants +30 caster levels to every school (BONUS_SCHOOL_CASTING_LEVEL), so the range is 5 + level/2 squares whatever the fixture's level
# fact: LM1 kobold squares and hit points -- kobolds placed at (PX+2, PY), (PX+3, PY), (PX+8, PY), fresh each cast, hit points set to 500 so none dies; the probe aims at (PX+10, PY)
# fact: LM1 which squares the stroke leaves the line -- cosmetic_random() picks them; the check reads only invariants every path keeps (distance, on-line at creatures and ends, adjacency, no solid, stroke glyph)
# fact: LM1 the stroke leaves the line in the gap (PX+4..PX+7) in at least 1 of 20 casts -- each of 4 gap squares stays on the line with chance at most 1/2 given any history (3 or 5 open candidates, at least 2), so a cast stays on the line with chance at most 1/16 and 20 casts all do with chance at most 1e-24
# fact: LM1 two casts draw different paths -- a cast repeats a given path with chance at most 1/16 (the 4 gap squares alone), so all 19 later casts repeat the first with chance at most 1e-22
# fact: LM2 corridor -- the probe walls every square of the room off the cast row; the path is the line by rule, no roll decides it
# fact: LM3 chain target -- one kobold at (PX+6, PY) as the chosen victim; the arc ends within 1 square of it, no roll decides that
# fact: LM4 non-meandering casts -- fire breath, Acid Arrow and Magic Missile are not lit electricity, so no hook fires whatever the roll
# fact: LM5 the spell's own squares -- no roll decides them: the spell walks a straight row from the player
# Cases LM1-LM5 add: a lit lightning stroke is drawn as a jagged path that keeps its rules and never changes the squares the spell walks.
# Case FW1 adds: the fireworks globe (Pyrotechnics;flash) plays dot, star, flower, gone, ring by ring, pointing away from the center.
# Cases T1-T3 add: the target flash (Fireball with two kobolds, a landed and a missed Chill Touch, Call Lightning).
# Cases R1-R3 add: a square's light cools by its own age (fire, then no white stage for dark energy), and a Fireball
# under OPT_ANIMATION None ends with no flash left.
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
