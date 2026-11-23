#!/bin/bash
# gate: live
# inc-9r189: a spell-effect glyph MUST NOT be drawn on a square the player cannot
# see into. Six hostile casters (2 amnizu: fireball; 2 eye of the storm:
# lightning bolt; ice mephit: magic missile; bloodshot eye: scorcher) fight in a
# closed room (walls all round, no door) the player has never seen. The probe
# (INCURSION_UNSEEN_GLYPH_PROBE, src/UnseenGlyphProbe.cpp) reads every overlay
# glyph the engine draws (Map::Update) and every direct effect-highlight
# PutGlyph through GlyphDrawHook, and the check counts those on squares of the
# closed room (area A) that are not VI_VISIBLE, and on those that are not
# VI_DEFINED. Positive control (AC3, a spell effect in the player's view still
# draws): a second area B, open to the player's view (no wall between) but
# unlit, holds six more mutually hostile casters; the check counts the bolt and
# beam glyph draws there (kind 5) and exits 1 if spells reached B and none drew.
# Missiles: each area also holds five missile users (four slingers, a javelin
# thrower) hostile to all. The probe counts every square a missile flew over
# (kind 7, MISSILE-AT) and every missile glyph drawn (kind 6, LOFDrawFlight).
# Exit 1 on any missile glyph in A, or on missiles flying in B with none drawn.
# Red while the defect is present, green after a fix.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: terrain -- the probe rewrites every square: player room, closed room, walls; the closed room's Visibility and Memory are zeroed
# fact: area B's light and view -- the probe leaves B unlit with Visibility and Memory zeroed, and counts B squares visible (must be 0) and in line of sight (must be all) before it grades
# fact: casters, their squares, their number -- placed by the probe at fixed squares (six in A, six in B); their spells come from the monster definitions
# fact: missile users, their squares, their number -- placed by the probe at fixed squares (five in A, five in B: halflings and a bugbear); their slings and javelins come from the monster definitions
# fact: hostility -- the probe makes every caster hostile to every other (TurnHostileTo) and counts 132 of 132 hostile pairs before it grades
# fact: the player's view -- the probe counts room squares seen or in line of sight before it grades; both must be 0
# fact: whether a caster casts -- the probe forces one Magic Missile (EV_EFFECT, as a monster's cast runs it) per area from a placed caster at a fixed target, and the check exits 2 unless each FORCED kind=spell line reports ok=1 (its own effect squares reached)
# fact: whether a missile user fires -- the probe forces one missile (Throw EV_RATTACK, as ACT_RATTACK/ACT_THROW run it) per area from a placed missile user at a fixed target, and the check exits 2 unless each FORCED kind=missile line reports ok=1 (its own squares flown over)
# fact: the seed -- decides rolls and the casters' choices, not the setup; the check uses the invariant "no draw on an unseen square" and reports its own seed
# Exit 0 NOT REPRODUCED (no draw on an unseen square, and spells reached the room),
#      1 REPRODUCED (a draw on an unseen closed-room square) or the positive
#        control failed (spells reached area B and no bolt or beam glyph drew there),
#      2 INCONCLUSIVE (no setup line, setup refused, or no spell or missile
#        reached A or B).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-1}"
KEYS=tools/keys/unseen-spell-glyphs.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-unseen-glyphs"
mkdir -p "$ROOT/logs/runs"
INCURSION_UNSEEN_GLYPH_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR.out" 2>&1
rc=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log (headless exit $rc). See $RUN_DIR.out"
    exit 2
fi
grep 'UNSEEN_GLYPH:' "$log" > "$RUN_DIR/unseen-glyph.lines"
setup="$(grep 'UNSEEN_GLYPH: SETUP' "$RUN_DIR/unseen-glyph.lines" | head -n 1)"
if [ -z "$setup" ] || grep -q 'UNSEEN_GLYPH: INCONCLUSIVE' "$RUN_DIR/unseen-glyph.lines"; then
    echo "INCONCLUSIVE: the probe did not set the scenario up."
    grep 'UNSEEN_GLYPH: \(SETUP\|INCONCLUSIVE\)' "$RUN_DIR/unseen-glyph.lines"
    exit 2
fi
echo "$setup"
for fk in "missile area=A" "missile area=B" "spell area=A" "spell area=B"; do
    if ! grep -q "UNSEEN_GLYPH: FORCED kind=$fk ok=1" "$RUN_DIR/unseen-glyph.lines"; then
        echo "INCONCLUSIVE: the forced control ($fk) did not run or reached no square."
        grep 'UNSEEN_GLYPH: FORCED' "$RUN_DIR/unseen-glyph.lines"
        exit 2
    fi
done

L="$RUN_DIR/unseen-glyph.lines"
effects="$(grep -c 'UNSEEN_GLYPH: EFFECT-AT.*area=A' "$L")"
effectsB="$(grep -c 'UNSEEN_GLYPH: EFFECT-AT.*area=B' "$L")"
# A real draw is kind 2 (overlay draw in Map::Update) or kind 3 (direct PutGlyph).
draws="$(grep 'UNSEEN_GLYPH: EVENT kind=[23].*area=A' "$L" | wc -l | tr -d ' ')"
drawsB="$(grep 'UNSEEN_GLYPH: EVENT kind=5.*area=B' "$L" | wc -l | tr -d ' ')"
missA="$(grep 'UNSEEN_GLYPH: EVENT kind=6.*area=A' "$L" | wc -l | tr -d ' ')"
missB="$(grep 'UNSEEN_GLYPH: EVENT kind=6.*area=B' "$L" | wc -l | tr -d ' ')"
flyA="$(grep -c 'UNSEEN_GLYPH: MISSILE-AT.*area=A' "$L")"
flyB="$(grep -c 'UNSEEN_GLYPH: MISSILE-AT.*area=B' "$L")"
boltA="$(grep 'UNSEEN_GLYPH: EVENT kind=5.*area=A' "$L" | wc -l | tr -d ' ')"
undrawn_vis="$(grep 'UNSEEN_GLYPH: EVENT kind=[23].*area=A' "$L" | grep -c 'vi_visible=0')"
undrawn_def="$(grep 'UNSEEN_GLYPH: EVENT kind=[23].*area=A' "$L" | grep -c 'vi_defined=0')"
queued="$(grep 'UNSEEN_GLYPH: EVENT kind=1.*area=A' "$L" | wc -l | tr -d ' ')"
grep 'UNSEEN_GLYPH: SETUP-B' "$L" | head -n 1
echo "seed=$SEED effect squares reached inside the closed room (A): $effects"
echo "glyphs queued (AddGlyph) inside the closed room: $queued"
echo "glyph draws inside the closed room: $draws"
echo "  on squares not VI_VISIBLE: $undrawn_vis"
echo "  on squares never seen (not VI_DEFINED): $undrawn_def"
echo "bolt/beam glyphs drawn inside the closed room: $boltA"
echo "positive control, dark area in view (B): effect squares reached $effectsB, bolt/beam glyphs drawn $drawsB"
echo "missiles: squares flown over in A $flyA, glyphs drawn in A $missA; squares flown over in B $flyB, glyphs drawn in B $missB"
echo "Specimen: $RUN_DIR/unseen-glyph.lines"

if [ "$effects" -eq 0 ]; then
    echo "INCONCLUSIVE: no spell reached the closed room, so a draw could not be tested."
    exit 2
fi
if [ "$effectsB" -eq 0 ]; then
    echo "INCONCLUSIVE: no spell reached the dark area in view (B), so the positive control could not be tested."
    exit 2
fi
if [ "$flyA" -eq 0 ]; then
    echo "INCONCLUSIVE: no missile flew in the closed room (A), so a missile draw could not be tested."
    exit 2
fi
if [ "$flyB" -eq 0 ]; then
    echo "INCONCLUSIVE: no missile flew in the dark area in view (B), so the missile positive control could not be tested."
    exit 2
fi
if [ "$drawsB" -eq 0 ]; then
    echo "REPRODUCED (positive control failed): spells reached the dark area in the player's view ($effectsB effect squares) but no bolt or beam glyph drew there."
    exit 1
fi
if [ "$missB" -eq 0 ]; then
    echo "REPRODUCED (positive control failed): missiles flew in the dark area in the player's view ($flyB squares) but no missile glyph drew there."
    exit 1
fi
if [ "$missA" -gt 0 ]; then
    echo "REPRODUCED: $missA missile glyph draws on closed-room squares the player cannot see."
    exit 1
fi
if [ "$undrawn_vis" -gt 0 ]; then
    echo "REPRODUCED: $undrawn_vis glyph draws on closed-room squares the player cannot see ($undrawn_def on never-seen squares)."
    exit 1
fi
echo "NOT REPRODUCED: no glyph drawn on an unseen closed-room square ($effects effect squares reached); $drawsB bolt draws and $missB missile draws in the dark area in view; no missile glyph in the closed room."
exit 0
