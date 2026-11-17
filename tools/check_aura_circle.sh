#!/bin/bash
# gate: live
# inc-jw0hw: the SDL build draws an aura circle (a modifier or blocker field)
# only on cells the player sees now. The probe (INCURSION_AURA_SCENE) builds a
# DARK room, records frames without the field (clip "before"), creates one
# purple FI_MODIFIER field, and records again (clip "after"). A wall hides the
# south-east of the circle. DrawAuras logs where it drew the circle (AURA_DRAWN);
# the probe gives offsets from that center. A pixel "is ring" when its red and
# its blue each exceed its green by 25 (the purple ring over the gray floor).
# PASS needs, in the last "after" frame: the top and right ring points are ring;
# the hidden ring point (behind the wall) and an outside point are NOT ring; and
# the mean of the seen interior cell is redder than green by 5 more than in the
# last "before" frame (the fill tints it).
# RED: removing the VI_VISIBLE clip in DrawAuras (src/Wlibtcod.cpp) paints the
# hidden ring point, so "hidden" turns ring-colored and the check FAILs.
# Needs the SDL build (./incursion), run windowless. The main session runs it;
# it launches SDL.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal
# fact: terrain and darkness -- the probe builds a dark room and the wall; the aura alone lights it
# fact: monsters -- none; the probe removes every thing but the player
# fact: pixel coordinates -- DrawAuras logs the circle's center and radius (AURA_DRAWN); the probe reads cell size from the SDL Term at run time, no fixed font size
# fact: player's sight of each point -- the probe reports VI_VISIBLE for each point; the check is INCONCLUSIVE when the scene does not hold
# fact: aura color -- the probe makes the field PURPLE (GLYPH_VALUE(GLYPH_FLOOR2, PURPLE)); the ring test assumes red and blue exceed green by 25 over a gray floor
# fact: circle radius -- DrawAuras logs it; the probe offsets the top, right and hidden points from it
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no frames, no AURA_SCENE lines, scene did not hold).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
MARGIN=30      # a seen pixel must be brighter after than before by this much (sum of channels)
TOLERANCE=8    # a hidden or outside pixel must match before and after within this per channel

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

RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-aura-circle"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/scene.keys"
echo "@quit" > "$KEYS"
FRAMES="$RUN_DIR/frames"

INCURSION_BIN=./incursion INCURSIONFONTPATH="$ROOT/fonts" \
    INCURSION_FRAMES="$FRAMES" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" \
    INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_AURA_SCENE=1 \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN_DIR/run.out" 2>&1

log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
lines="$(grep -a 'AURA_SCENE:' "$log" 2>/dev/null)"
if [ -z "$lines" ]; then
    echo "INCONCLUSIVE: no AURA_SCENE lines in $log."
    exit 2
fi
echo "$lines"
if grep -aq 'AURA_SCENE: INCONCLUSIVE' <<< "$lines" || ! grep -aq 'AURA_SCENE: DONE' <<< "$lines"; then
    echo "INCONCLUSIVE: the scene did not finish."
    exit 2
fi

lastof() { find "$FRAMES/$1" -name 'f*.bmp' 2>/dev/null | sort | tail -n 1; }
before="$(lastof before)"
after="$(lastof after)"
if [ -z "$before" ] || [ -z "$after" ]; then
    echo "INCONCLUSIVE: no frames in clip before ($before) or after ($after) under $FRAMES."
    exit 2
fi

# Each point line: "AURA_SCENE: <name> <x> <y> vis=<0|1>".
point() { grep -a "AURA_SCENE: $1 " <<< "$lines" | head -n 1 | sed 's/.*AURA_SCENE: [a-z]* \(-*[0-9]*\) \(-*[0-9]*\) vis=\([01]\).*/\1 \2 \3/'; }
read -r sx sy svis <<< "$(point seen)"
read -r tx ty tvis <<< "$(point top)"
read -r rx ry rvis <<< "$(point right)"
read -r hx hy hvis <<< "$(point hidden)"
read -r ox oy ovis <<< "$(point outside)"
read -r cw ch _ <<< "$(point cell)"
if [ -z "${sx:-}" ] || [ -z "${tx:-}" ] || [ -z "${rx:-}" ] || [ -z "${hx:-}" ] || [ -z "${ox:-}" ] || [ -z "${cw:-}" ]; then
    echo "INCONCLUSIVE: could not read the points and the cell size."
    exit 2
fi
if [ "$svis" != 1 ] || [ "$tvis" != 1 ] || [ "$rvis" != 1 ] || [ "$hvis" != 0 ] || [ "$ovis" != 0 ]; then
    echo "INCONCLUSIVE: the scene does not hold (vis seen=$svis top=$tvis right=$rvis hidden=$hvis outside=$ovis; want 1 1 1 0 0)."
    exit 2
fi

# The probe's points are offsets from the circle's center; the center is where
# DrawAuras really drew it ("AURA_DRAWN: <cx> <cy> <R>", last line).
read -r ccx ccy _ <<< "$(grep -a 'AURA_DRAWN:' "$log" | tail -n 1 | sed 's/.*AURA_DRAWN: //')"
if [ -z "${ccx:-}" ]; then
    echo "INCONCLUSIVE: DrawAuras logged no AURA_DRAWN line (no circle drawn)."
    exit 2
fi
echo "circle drawn at $ccx $ccy"
sx=$((ccx + sx)); sy=$((ccy + sy)); tx=$((ccx + tx)); ty=$((ccy + ty))
rx=$((ccx + rx)); ry=$((ccy + ry)); hx=$((ccx + hx)); hy=$((ccy + hy))
ox=$((ccx + ox)); oy=$((ccy + oy))

pix() { python3 -I tools/bmp_pixel.py "$1" "$tx" "$ty" "$rx" "$ry" "$hx" "$hy" "$ox" "$oy"; }
pa="$(pix "$after")" || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not read $after."
    exit 2
}
mean() { python3 -I tools/bmp_pixel.py --mean "$1" $((sx - cw / 2)) $((sy - ch / 2)) "$cw" "$ch"; }
mb="$(mean "$before")" && ma="$(mean "$after")" || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not average the seen cell."
    exit 2
}
echo "after frame: $after"
echo "$pa"
echo "seen cell mean r g b: before $mb, after $ma"

# is_ring <row>: red and blue each exceed green by 25. Rows: 1 top, 2 right, 3 hidden, 4 outside.
is_ring() { local r g b; read -r _ _ r g b <<< "$(sed -n "$1p" <<< "$pa")"; [ $((r - g)) -ge 25 ] && [ $((b - g)) -ge 25 ]; }
rowname=(x top right hidden outside)
for i in 1 2; do
    is_ring $i || { echo "FAIL: the ${rowname[$i]} point is not ring-colored: $(sed -n "${i}p" <<< "$pa")."; exit 1; }
done
for i in 3 4; do
    if is_ring $i; then
        echo "FAIL: the ${rowname[$i]} point is ring-colored ($(sed -n "${i}p" <<< "$pa")); the circle drew out of sight or outside."
        exit 1
    fi
done
read -r mbr mbg _ <<< "$mb"
read -r mar mag _ <<< "$ma"
if ! python3 -I -c "import sys; ar,ag,br,bg=map(float,sys.argv[1:5]); sys.exit(0 if (ar-ag)-(br-bg) >= 5 else 1)" "$mar" "$mag" "$mbr" "$mbg" 2>/dev/null; then
    echo "FAIL: the seen interior cell is not tinted: (R-G) before $(python3 -I -c "print($mbr-$mbg)") after $(python3 -I -c "print($mar-$mag)"), need +5."
    exit 1
fi
echo "PASS: the circle shows on its top and right points and the seen interior, and not out of sight."
exit 0
