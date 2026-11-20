#!/bin/bash
# gate: live
# inc-9r189: a spell-effect glyph MUST NOT be drawn on a square the player cannot
# see into. Six hostile casters (2 amnizu: fireball; 2 eye of the storm:
# lightning bolt; ice mephit: magic missile; bloodshot eye: scorcher) fight in a
# closed room (walls all round, no door) the player has never seen. The probe
# (INCURSION_UNSEEN_GLYPH_PROBE, src/UnseenGlyphProbe.cpp) reads every overlay
# glyph the engine draws (Map::Update) and every direct effect-highlight
# PutGlyph through GlyphDrawHook, and the check counts those on squares of the
# closed room that are not VI_VISIBLE, and on those that are not VI_DEFINED.
# Red while the defect is present, green after a fix.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: terrain -- the probe rewrites every square: player room, closed room, walls; the closed room's Visibility and Memory are zeroed
# fact: casters, their squares, their number -- placed by the probe at fixed squares; their spells come from the monster definitions
# fact: hostility -- the probe makes every caster hostile to every other (TurnHostileTo) and counts 30 of 30 hostile pairs before it grades
# fact: the player's view -- the probe counts room squares seen or in line of sight before it grades; both must be 0
# fact: whether a caster casts -- the check reports the effect squares reached; it exits 2 when no spell reached the room
# fact: the seed -- decides rolls and the casters' choices, not the setup; the check uses the invariant "no draw on an unseen square" and reports its own seed
# Exit 0 NOT REPRODUCED (no draw on an unseen square, and spells reached the room),
#      1 REPRODUCED, 2 INCONCLUSIVE (no setup line, setup refused, or no spell reached the room).
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

effects="$(grep -c 'UNSEEN_GLYPH: EFFECT-AT' "$RUN_DIR/unseen-glyph.lines")"
# A real draw is kind 2 (overlay draw in Map::Update) or kind 3 (direct PutGlyph).
draws="$(grep 'UNSEEN_GLYPH: EVENT kind=[23]' "$RUN_DIR/unseen-glyph.lines" | wc -l | tr -d ' ')"
undrawn_vis="$(grep 'UNSEEN_GLYPH: EVENT kind=[23]' "$RUN_DIR/unseen-glyph.lines" | grep -c 'vi_visible=0')"
undrawn_def="$(grep 'UNSEEN_GLYPH: EVENT kind=[23]' "$RUN_DIR/unseen-glyph.lines" | grep -c 'vi_defined=0')"
queued="$(grep -c 'UNSEEN_GLYPH: EVENT kind=1' "$RUN_DIR/unseen-glyph.lines")"
echo "seed=$SEED effect squares reached inside the closed room: $effects"
echo "glyphs queued (AddGlyph) inside the closed room: $queued"
echo "glyph draws inside the closed room: $draws"
echo "  on squares not VI_VISIBLE: $undrawn_vis"
echo "  on squares never seen (not VI_DEFINED): $undrawn_def"
echo "Specimen: $RUN_DIR/unseen-glyph.lines"

if [ "$effects" -eq 0 ]; then
    echo "INCONCLUSIVE: no spell reached the closed room, so a draw could not be tested."
    exit 2
fi
if [ "$undrawn_vis" -gt 0 ]; then
    echo "REPRODUCED: $undrawn_vis glyph draws on closed-room squares the player cannot see ($undrawn_def on never-seen squares)."
    exit 1
fi
echo "NOT REPRODUCED: no glyph drawn on an unseen closed-room square ($effects effect squares reached)."
exit 0
