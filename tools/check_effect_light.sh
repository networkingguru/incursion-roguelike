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
# fact: CP1 cast square, radius and kobold -- the probe aims Hypnotic Pattern at (PX+8, PY) with one kobold on that square; the radius is the data's lval (2), the expected squares are those within it that the probe's own LineOfSight call says the player sees
# fact: CP1 picks per square and the gap between picks -- the effect's own clock: the 1500 ms hold runs in steps of 33 ms and a square picks again at the first step 100 ms after its last pick, so 12 picks 132 ms apart; no roll and no wall clock decide them
# fact: CP1 the glyph and color of each pick -- cosmetic_random() picks them; the check reads only invariants every pick keeps (a symbol that is not a letter, digit or @; a palette color that is not black, shadow, grey or white; the light base color equals LightEffectColour of the glyph color)
# fact: CP1 at least 4 distinct colors and 4 distinct glyphs -- 252 picks (21 squares, 12 each) draw each from 8 values, so fewer than 4 distinct of either happen with chance below 1e-90
# fact: CP1 a re-pick changes a square's color -- 231 consecutive pairs of picks each repeat the color with chance 1/8, so none changing it has chance below 1e-200
# fact: CP2 aim, kobolds and range -- the probe aims Colour Spray at (PX+10, PY), kobolds at (PX+3, PY) and (PX+6, PY), 500 hit points each, MM_EXTEND set as the effect reel sets it; the beam walks a straight row, so no roll decides its squares
# fact: CP2 both kobolds are struck -- a beam strikes every creature on its line by design (isMulti); the probe counts the data's strike message "spray of colours strikes" twice, so no saving throw or attack roll decides it
# fact: CP2 a drawn beam picks again -- the first square of a 10-square beam stays up about 315 ms of effect clock at 35 ms a square, so it picks again at least twice; no roll decides it
# fact: CP3 the orb's square list -- Chromatic Orb aimed at a kobold at (PX+6, PY) walks the straight row to it; a hit or a miss roll does not change the walk
# fact: CP3 the orb is the unprompted clear orb -- the probe casts with no caster level bonus, so the fixture's own caster level (below 3) takes the lowest branch and loses 4 mana; the probe grades the 4, so a higher level that would open the color prompt fails the check
# fact: CP4 non-pattern effects -- Nightmare smite;actual blast (a COL_RAINBOW globe without the flag) and Fireball carry no EF_COLOR_PATTERN, so no roll lets the hook fire
# fact: CP5 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that no pick fires
# fact: CP6 the gameplay random stream -- the probe re-initializes it with init_genrand just before each of two casts, so both casts start from one state; the check compares the next four draws, whatever the values are
# fact: BH1 cast squares and kobold -- the probe casts Burning Hands east from the player's fixed square with a kobold at (PX+1, PY), 500 hit points; the three squares are the spell's fixed shape for the direction (the probe writes them from the spell text), no roll decides them
# fact: BH1 a square's age -- the effect's own clock: the 500 ms hold runs in 33 ms steps and the probe takes the step nearest 100, 300 and 550 ms; never the wall clock
# fact: BH2 the diagonal squares -- the probe casts northeast (EDir set by the probe); the shape for a diagonal is fixed by the spell's own code, no roll decides it
# fact: BH3 the struck creature -- a kobold on a square of the spell's shape; the spell strikes every creature there with no attack roll or save deciding the flash, which comes before the hit resolves
# fact: BH4 the wall square -- the probe writes a wall on the middle of the three squares; the spell skips a solid square, no roll decides it
# fact: BH5 animation None -- the probe sets OPT_ANIMATION 2 for the cast; no roll decides that nothing lights
# fact: BH6 out of sight -- the probe makes the player's eight neighbors opaque (as case C) and a kobold at (PX+10, PY) casts with the player as its victim, so the script holds; no roll decides the line of sight
# fact: BH8 the terminal's glyph -- the CP437 247 glyph, read with T1->GetGlyph at the three squares of the east shape, a fixed offset from the player's fixed square, at each 33 ms step of the hold; no roll decides it
# fact: BH7 the gameplay random stream -- each cast runs in its own process (INCURSION_BH7_ANIM), from init_genrand(7770002) just before the cast, so no state carries between casts; the check compares the stream position (seed, draws taken) when the script's light ends, before the strike, which re-seeds the stream; whatever the values are
# fact: BH7 the struck kobold -- a kobold at (PX+1, PY), 500 hit points, on the first of the spell's squares; the spell strikes it with no roll deciding that
# fact: BH7 process-to-process determinism -- two runs at the same animation must give equal draws; the check runs animation Normal twice and is INCONCLUSIVE if they differ
# Cases BH1-BH8 add (BH7 in separate processes): Burning Hands lights each square it draws on the fire ramp through the hold and the cooling, flashes every creature it hit, and moves no gameplay roll.
# Cases CP1-CP6 add: Hypnotic Pattern, Colour Spray and Chromatic Orb draw random symbols in random colors that re-pick each 100 ms of the effect clock, the light follows each glyph's color, and no gameplay roll moves.
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

bh7() {   # one fresh process; prints its four draws
    local d="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-bh7-$1"
    INCURSION_BH7_ANIM="$1" INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$d" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        tools/headless.sh "$KEYS" "$SEED" > /dev/null 2>&1
    grep -a 'EFFECT_LIGHT: BH7DRAW' "$d/logs/errors.log" 2>/dev/null | sed 's/.*BH7DRAW //'
}
BH7_N1="$(bh7 0)"; BH7_N2="$(bh7 0)"; BH7_NONE="$(bh7 2)"

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
        if [ -z "$BH7_N1" ] || [ "$BH7_N1" != "$BH7_N2" ]; then
            echo "INCONCLUSIVE: BH7 two animation-Normal runs gave different draws ('$BH7_N1' / '$BH7_N2')."
            exit 2
        fi
        if [ "$BH7_N1" != "$BH7_NONE" ]; then
            echo "EFFECT_LIGHT: BH7 FAIL stream position when the script's light ends, struck kobold: animation Normal $BH7_N1, animation None $BH7_NONE (need equal)"
            exit 1
        fi
        echo "EFFECT_LIGHT: BH7 PASS stream position when the script's light ends, struck kobold: animation Normal (twice) $BH7_N1, animation None $BH7_NONE"
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
