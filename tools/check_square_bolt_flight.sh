#!/bin/bash
# gate: live
# inc-s87gl: a bolt with no chosen creature (aimed at a square, or cast in a
# direction) MUST fly: a flight glyph on every square it crosses, and its effect
# run on each (Magic::MagicXY). Magic::ABallBeamBolt jumps to DoneProject from
# its "no chosen creature" branch and skips the travel loop, so neither happens.
# The probe (INCURSION_SQUARE_BOLT_PROBE, src/SquareBoltProbe.cpp) builds one
# open, lit room and casts the wand effect Fire Bolts (AR_BOLT, AD_FIRE) from
# a +5 wand along one row. It reads GlyphDrawHook kind 5 (a bolt glyph drawn)
# and AreaProbeXYHook (every MagicXY call). Cases: S1 empty square; S2 empty
# aim with a kobold on the square before it (forced hit; every glyph MUST
# draw before the kobold loses hit points); S3 two kobolds, forced roll 1
# misses both, the flight passes them; S4 a direction cast; S5 the control,
# aimed AT a kobold, MUST draw (a failure exits 2); S6 an Ice Wall on the path
# that fire melts only through MagicXY, with its own control S6c aimed AT a
# creature behind the wall (the wall MUST melt there, or the check exits 2).
# S7 (miss-then-hit) and S8 (same square) are in the probe and graded below.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS
# fact: terrain -- the probe rewrites every square: one open lit room, walls elsewhere; it counts the row in line of sight and refuses (INCONCLUSIVE) unless all 31 squares are
# fact: monsters, their squares, their number -- placed by the probe at fixed squares (kobolds at x=10, 13, 14, 15 on the player's row); hit points pinned to 10000
# fact: S7 and S8 defences -- the probe pins each kobold's TouchDef after placing it, from vHit read back through LOFGetLastVHit and LineOfFireCoverPenalty(1), so roll 10 misses the first and beats the second
# fact: the attack roll -- LOFSetForcedRoll (20 hits, 1 misses), set before each cast and cleared after it
# fact: the effect's damage -- MM_MAXIMIZE on every cast and a +5 wand; the Ice Wall melts when the fire damage beats 10+random(10), and the control S6c proves it does
# fact: whether a cast happened -- every case logs cast=1 when ReThrow(EV_EFFECT) did not abort; the check exits 2 otherwise
# fact: the seed -- decides nothing the cases read; the check reports its own seed
# Exit 0 NOT REPRODUCED (every case flies and its effect runs),
#      1 REPRODUCED (S1-S4 draw no flight glyph or run no effect on a crossed
#        square, S2 draws a glyph after the kobold is hit, or S6's wall stays),
#      2 INCONCLUSIVE (setup fails, a cast did not happen, or a control fails).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-1}"
KEYS=tools/keys/square-bolt-flight.keys
OPTIONS=tools/fixtures/options-2026-08-22.dat
LOAD=xsummon-priest-seed5-opt0822

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-square-bolt"
mkdir -p "$ROOT/logs/runs"
INCURSION_SQUARE_BOLT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR.out" 2>&1
rc=$?

log="$RUN_DIR/logs/errors.log"
if [ ! -s "$log" ]; then
    echo "INCONCLUSIVE: no $log (headless exit $rc). See $RUN_DIR.out"
    exit 2
fi
L="$RUN_DIR/square-bolt.lines"
grep 'SQUARE_BOLT:' "$log" | sed 's/^.*SQUARE_BOLT: /SQUARE_BOLT: /' > "$L"
if ! grep -q 'SQUARE_BOLT: SETUP' "$L" || grep -q 'SQUARE_BOLT: INCONCLUSIVE' "$L" \
        || ! grep -q 'SQUARE_BOLT: DONE' "$L"; then
    echo "INCONCLUSIVE: the probe did not set up or did not finish."
    cat "$L"
    exit 2
fi

field() { # field <case-prefix> <key>
    grep "SQUARE_BOLT: CASE name=$1" "$L" | head -n 1 | sed -n "s/.* $2=\([^ ]*\).*/\1/p"
}
ice() { grep "SQUARE_BOLT: ICE name=$1 " "$L" | sed -n 's/.*still_ice=\([0-9]*\).*/\1/p'; }

grep 'SQUARE_BOLT: CASE' "$L" | sed 's/ drawn=.*//'
echo "ICE wall still standing: S6c(control)=$(ice S6c) S6=$(ice S6)"

for c in S5 S1 S2 S3 S4 S7 S8 S6c S6; do
    if [ "$(field "$c-" cast)" != "1" ]; then
        echo "INCONCLUSIVE: case $c did not run or its cast did not happen."
        exit 2
    fi
done
if [ "$(field S5- glyphs_total)" -eq 0 ] || [ "$(field S5- glyph_missing)" -ne 0 ]; then
    echo "INCONCLUSIVE: control S5 (aimed at a creature) drew no flight, or not on every square; the glyph reader is not proved."
    exit 2
fi
if [ "$(ice S6c)" != "0" ]; then
    echo "INCONCLUSIVE: control S6c (aimed at a creature behind the Ice Wall) did not melt it; the effect reader is not proved."
    exit 2
fi
if [ "$(field S2- kobolds_struck)" -ne 1 ] || [ "$(field S3- kobolds_struck)" -ne 0 ]; then
    echo "INCONCLUSIVE: the forced roll did not give the expected strikes (S2 want 1, S3 want 0)."
    exit 2
fi

red=0
for c in S1 S2 S3 S4; do
    gm="$(field "$c-" glyph_missing)"; xm="$(field "$c-" xy_missing)"
    if [ "$gm" -ne 0 ] || [ "$xm" -ne 0 ]; then
        echo "REPRODUCED: case $c left $gm crossed squares with no flight glyph and $xm with no effect run."
        red=1
    fi
done
for c in S7 S8; do
    gm="$(field "$c-" glyph_missing)"; xm="$(field "$c-" xy_missing)"
    if [ "$gm" -ne 0 ] || [ "$xm" -ne 0 ]; then
        echo "REPRODUCED: case $c left $gm crossed squares with no flight glyph and $xm with no effect run."
        red=1
    fi
    role="$(grep "SQUARE_BOLT: ROLE case=$c-" "$L")"
    sf="$(echo "$role" | sed -n 's/.*struck_first=\([0-9]*\).*/\1/p')"
    ss="$(echo "$role" | sed -n 's/.*struck_second=\([0-9]*\).*/\1/p')"
    want2=1; [ "$c" = S8 ] && want2=0   # S8: only a square's head is a candidate
    if [ "$sf" != "0" ] || [ "$ss" != "$want2" ]; then
        echo "REPRODUCED: case $c struck first=$sf second=$ss; want first=0 second=$want2."
        red=1
    fi
    if [ "$(field "$c-" glyphs_after_hit)" -ne 0 ]; then
        echo "REPRODUCED: case $c drew a flight glyph after the struck creature lost hit points."
        red=1
    fi
done
if [ "$(field S2- glyphs_after_hit)" -ne 0 ]; then
    echo "REPRODUCED: S2 drew $(field S2- glyphs_after_hit) flight glyphs after the kobold lost hit points."
    red=1
fi
if [ "$(ice S6)" != "0" ]; then
    echo "REPRODUCED: S6 crossed an Ice Wall with fire and the wall stood; the bolt's effect never ran there."
    red=1
fi
echo "Specimen: $L"
if [ "$red" -ne 0 ]; then
    exit 1
fi
echo "NOT REPRODUCED: every bolt with no chosen creature flew and ran its effect on each crossed square."
exit 0
