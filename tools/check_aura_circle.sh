#!/bin/bash
# gate: live
# inc-jw0hw: an aura (a modifier or blocker field) gives no light; the SDL build
# shows it as a thin circle in its color with a faint additive tint inside, drawn
# only on cells the player sees now. The probe (INCURSION_AURA_SCENE) builds a room
# whose squares the MAP lights (an aura lights nothing, so something else must show
# the floor), records frames without fields (clip "before"), creates two overlapping
# purple FI_MODIFIER fields A and B (B five squares west of A), and records again
# (clip "after"). A wall hides the south-east of A's circle. DrawAuras logs where it
# drew A's circle (AURA_DRAWN); the probe gives offsets from that center. A pixel
# "is ring" when its red and its blue each exceed its green by 25.
# Named assertions, each its own line of output:
#   (a) RING COLOR: A's top and right ring points are ring-colored.
#   (b) TINT: the seen cell inside A only is brighter after than before, by at least
#       TINT_MIN (sum of channels).
#   (c) NO LIGHT: not read here. tools/check_effect_light.sh cases AU1 and AU2
#       compare LightLevelAt and LightAt over the whole room with and without two
#       overlapping auras (headless, posix build).
#   (d) OVERLAP: the seen cell inside both A and B is brighter than the A-only cell
#       by at least OVERLAP_MARGIN more (sum of channels, after minus before).
#   (e) HIDE: a second run with OPT_AURA_CIRCLES = HIDE draws no circle: no AURA_DRAWN
#       line and no ring-colored pixel on A's top and right points.
#   plus: the hidden ring point (behind the wall) and an outside point are NOT ring.
# RED: removing the VI_VISIBLE clip in DrawAuras (src/Wlibtcod.cpp) paints the hidden
# ring point, so "hidden" turns ring-colored; logs/p5-mutations/*.patch break (c), (d), (e).
# Needs the SDL build (./incursion), run windowless. The main session runs it;
# it launches SDL.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal, and OPT_AURA_CIRCLES to HIDE in the hide run only
# fact: terrain and light -- the probe builds the room, writes the wall, and sets every room square lit (legacy .Lit); no aura light is needed to see
# fact: monsters -- none; the probe removes every thing but the player
# fact: pixel coordinates -- DrawAuras logs each circle's center, radius and map cell (AURA_DRAWN); the check takes aura A's line by the map cell the probe reports (auracell); the probe reads cell size from the SDL Term at run time, no fixed font size
# fact: player's sight of each point -- the probe reports VI_VISIBLE for each point; the check is INCONCLUSIVE when the scene does not hold
# fact: aura color -- the probe makes both fields PURPLE (GLYPH_VALUE(GLYPH_FLOOR2, PURPLE)); the ring test assumes red and blue exceed green by 25
# fact: circle radius -- DrawAuras logs it; the probe offsets the top, right and hidden points from it
# fact: the tint's size -- 0.05 x the circle color x its shimmer noise (0.5..1, a hash of the field's square, no random draw); TINT_MIN and OVERLAP_MARGIN sit below the least value that gives (about 14 per aura)
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no frames, no AURA_SCENE lines, scene did not hold).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
TINT_MIN=8          # (b) the A-only cell must be brighter after than before by this much (sum of channels)
OVERLAP_MARGIN=8    # (d) the overlap cell's gain must exceed the A-only cell's gain by this much (sum of channels)

[ -x ./incursion ] || {
    echo "INCONCLUSIVE: ./incursion (the SDL build) is missing. Run: ./build_macos.sh"
    exit 2
}
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || {
    echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."
    exit 2
}

run_scene() {   # $1 mode (1 or hide), $2 name; sets RUN_DIR FRAMES log
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-aura-circle-$2"
    mkdir -p "$RUN_DIR"
    echo "@quit" > "$RUN_DIR/scene.keys"
    FRAMES="$RUN_DIR/frames"
    INCURSION_BIN=./incursion INCURSIONFONTPATH="$ROOT/fonts" \
        INCURSION_FRAMES="$FRAMES" INCURSION_RUN_DIR="$RUN_DIR" \
        INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
        INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_AURA_SCENE="$1" \
        tools/headless.sh "$RUN_DIR/scene.keys" "$SEED" > "$RUN_DIR/run.out" 2>&1
    log="$RUN_DIR/logs/errors.log"
    echo "Specimen: $RUN_DIR"
    lines="$(grep -a 'AURA_SCENE:' "$log" 2>/dev/null)"
    if [ -z "$lines" ]; then
        echo "INCONCLUSIVE: no AURA_SCENE lines in $log."
        exit 2
    fi
    if grep -aq 'AURA_SCENE: INCONCLUSIVE' <<< "$lines" || ! grep -aq 'AURA_SCENE: DONE' <<< "$lines"; then
        echo "INCONCLUSIVE: the scene did not finish."
        exit 2
    fi
}
lastof() { find "$FRAMES/$1" -name 'f*.bmp' 2>/dev/null | sort | tail -n 1; }
# Each point line: "AURA_SCENE: <name> <x> <y> vis=<0|1>".
point() { grep -a "AURA_SCENE: $1 " <<< "$lines" | head -n 1 | sed 's/.*AURA_SCENE: [a-z]* \(-*[0-9]*\) \(-*[0-9]*\) vis=\([01]\).*/\1 \2 \3/'; }
# is_ring <row>: red and blue each exceed green by 25.
is_ring() { local r g b; read -r _ _ r g b <<< "$(sed -n "$1p" <<< "$2")"; [ $((r - g)) -ge 25 ] && [ $((b - g)) -ge 25 ]; }

# ---- the normal run: (a), (b), (d), and the hidden and outside points ----
run_scene 1 show
echo "$lines"
before="$(lastof before)"
after="$(lastof after)"
if [ -z "$before" ] || [ -z "$after" ]; then
    echo "INCONCLUSIVE: no frames in clip before ($before) or after ($after) under $FRAMES."
    exit 2
fi
read -r sx sy svis <<< "$(point seen)"
read -r vx vy vvis <<< "$(point overlap)"
read -r tx ty tvis <<< "$(point top)"
read -r rx ry rvis <<< "$(point right)"
read -r hx hy hvis <<< "$(point hidden)"
read -r ox oy ovis <<< "$(point outside)"
read -r cw ch _ <<< "$(point cell)"
if [ -z "${sx:-}" ] || [ -z "${vx:-}" ] || [ -z "${tx:-}" ] || [ -z "${rx:-}" ] || [ -z "${hx:-}" ] || [ -z "${ox:-}" ] || [ -z "${cw:-}" ]; then
    echo "INCONCLUSIVE: could not read the points and the cell size."
    exit 2
fi
if [ "$svis" != 1 ] || [ "$vvis" != 1 ] || [ "$tvis" != 1 ] || [ "$rvis" != 1 ] || [ "$hvis" != 0 ]; then
    echo "INCONCLUSIVE: the scene does not hold (vis seen=$svis overlap=$vvis top=$tvis right=$rvis hidden=$hvis; want 1 1 1 1 0)."
    exit 2
fi

# The probe's points are offsets from aura A's circle center; the center is where
# DrawAuras really drew A ("AURA_DRAWN: <cx> <cy> <R> <map x> <map y>", one line per
# aura per change). The line is chosen by A's map cell, which the probe reports
# ("AURA_SCENE: auracell <x> <y>"); the other aura, B, logs its own line.
read -r aax aay _ <<< "$(point auracell)"
if [ -z "${aax:-}" ]; then
    echo "INCONCLUSIVE: the probe did not report aura A's map cell."
    exit 2
fi
read -r ccx ccy _ <<< "$(grep -a 'AURA_DRAWN:' "$log" | sed 's/.*AURA_DRAWN: //' | awk -v x="$aax" -v y="$aay" '$4 == x && $5 == y' | tail -n 1)"
if [ -z "${ccx:-}" ]; then
    echo "INCONCLUSIVE: DrawAuras logged no AURA_DRAWN line for aura A at $aax,$aay (no circle drawn)."
    exit 2
fi
echo "circle drawn at $ccx $ccy"
sx=$((ccx + sx)); sy=$((ccy + sy)); vx=$((ccx + vx)); vy=$((ccy + vy))
tx=$((ccx + tx)); ty=$((ccy + ty)); rx=$((ccx + rx)); ry=$((ccy + ry))
hx=$((ccx + hx)); hy=$((ccy + hy)); ox=$((ccx + ox)); oy=$((ccy + oy))
TX=$tx; TY=$ty; RX=$rx; RY=$ry   # kept for the hide run: the circle's center is the same

pa="$(python3 -I tools/bmp_pixel.py "$after" "$tx" "$ty" "$rx" "$ry" "$hx" "$hy" "$ox" "$oy")" || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not read $after."
    exit 2
}
mean() { python3 -I tools/bmp_pixel.py --mean "$1" $(($2 - cw / 2)) $(($3 - ch / 2)) "$cw" "$ch"; }
read -r b1r b1g b1b <<< "$(mean "$before" "$sx" "$sy")" && read -r a1r a1g a1b <<< "$(mean "$after" "$sx" "$sy")" &&
read -r b2r b2g b2b <<< "$(mean "$before" "$vx" "$vy")" && read -r a2r a2g a2b <<< "$(mean "$after" "$vx" "$vy")" || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not average a seen cell."
    exit 2
}
echo "after frame: $after"
echo "$pa"
gain1=$(python3 -I -c "import sys; v=list(map(float,sys.argv[1:])); print(round((v[0]+v[1]+v[2])-(v[3]+v[4]+v[5]),1))" "$a1r" "$a1g" "$a1b" "$b1r" "$b1g" "$b1b")
gain2=$(python3 -I -c "import sys; v=list(map(float,sys.argv[1:])); print(round((v[0]+v[1]+v[2])-(v[3]+v[4]+v[5]),1))" "$a2r" "$a2g" "$a2b" "$b2r" "$b2g" "$b2b")
echo "seen cell (A only) mean r g b: before $b1r $b1g $b1b, after $a1r $a1g $a1b; gain $gain1"
echo "overlap cell (A and B) mean r g b: before $b2r $b2g $b2b, after $a2r $a2g $a2b; gain $gain2"
fails=0
rowname=(x top right hidden outside)
# (a) ring color
if is_ring 1 "$pa" && is_ring 2 "$pa"; then
    echo "PASS (a) RING COLOR: the top and right ring points are ring-colored."
else
    echo "FAIL (a) RING COLOR: top $(sed -n 1p <<< "$pa"), right $(sed -n 2p <<< "$pa") are not both ring-colored."; fails=1
fi
# hidden and outside points are not ring
for i in 3 4; do
    if is_ring $i "$pa"; then
        echo "FAIL the ${rowname[$i]} point is ring-colored ($(sed -n "${i}p" <<< "$pa")); the circle drew out of sight or outside."; fails=1
    else
        echo "PASS the ${rowname[$i]} point is not ring-colored."
    fi
done
# (b) tint
if python3 -I -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$gain1" "$TINT_MIN"; then
    echo "PASS (b) TINT: the seen cell inside A is brighter after than before by $gain1 (need $TINT_MIN)."
else
    echo "FAIL (b) TINT: the seen cell inside A gained $gain1 (need $TINT_MIN)."; fails=1
fi
# (c) no light
echo "NOTE (c) NO LIGHT: checked headless by tools/check_effect_light.sh cases AU1 and AU2."
# (d) overlap
if python3 -I -c "import sys; sys.exit(0 if float(sys.argv[1]) - float(sys.argv[2]) >= float(sys.argv[3]) else 1)" "$gain2" "$gain1" "$OVERLAP_MARGIN"; then
    echo "PASS (d) OVERLAP: the cell inside A and B gained $gain2, the A-only cell $gain1 (need a lead of $OVERLAP_MARGIN)."
else
    echo "FAIL (d) OVERLAP: the cell inside A and B gained $gain2, the A-only cell $gain1 (need a lead of $OVERLAP_MARGIN)."; fails=1
fi

# ---- the hide run: (e) ----
run_scene hide hide
echo "$lines"
hafter="$(lastof after)"
if [ -z "$hafter" ]; then
    echo "INCONCLUSIVE: no after frame in the hide run under $FRAMES."
    exit 2
fi
ph="$(python3 -I tools/bmp_pixel.py "$hafter" "$TX" "$TY" "$RX" "$RY")" || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not read $hafter."
    exit 2
}
echo "hide run, after frame: $hafter"
echo "$ph"
if grep -aq 'AURA_DRAWN:' "$log" || is_ring 1 "$ph" || is_ring 2 "$ph"; then
    echo "FAIL (e) HIDE: with OPT_AURA_CIRCLES = HIDE the circle is still drawn."; fails=1
else
    echo "PASS (e) HIDE: with OPT_AURA_CIRCLES = HIDE no circle is drawn."
fi

[ "$fails" = 0 ] || exit 1
echo "PASS: the circle shows on its ring, tints its seen interior, adds where auras overlap, hides on request, and not out of sight."
exit 0
