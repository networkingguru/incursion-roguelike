#!/bin/bash
# gate: live
# inc-jw0hw: an aura (a modifier or blocker field) gives no light; the SDL build
# shows it as a solid, semi-transparent tint of its color over its whole circular
# area (alpha AURA_TINT_ALPHA 0.30, no outline), drawn only on cells the player sees
# now. The probe (INCURSION_AURA_SCENE) builds a room whose squares the MAP lights
# (an aura lights nothing, so something else must show the floor), records frames
# without fields (clip "before"), creates two overlapping purple FI_MODIFIER fields
# A and B (B five squares west of A), and records again (clip "after"). A wall hides
# the south-east of A's circle. DrawAuras logs where it drew A (AURA_DRAWN: center and
# radius R in pixels). The tint T of a pixel is its purpleness (red+blue)/2 - green
# in the after frame minus the same in the before frame; the before frame cancels the
# floor and glyphs.
# Named assertions, each its own line of output:
#   (a) INTERIOR: the center band (8-24 px from the center) and the band just inside the
#       edge (R-8..R-2) are tinted, T >= TINT_MIN, and roughly equal: between 0.6 and 1.6.
#   (b) OUTSIDE: the band R+2..R+8 is untinted, |T| <= UNTINTED_MAX.
#   (c) NO RING: the band R-1..R+1 has T no more than T(R-8..R-2) + 0.5 x T(center) + 4.
#   Bands are means over an east sector (-30..10 degrees) of the circle: tools/aura_sector.py.
#   (d) OVERLAP: the cell inside both A and B has T above the A-only cell's by at
#       least OVERLAP_MARGIN (the second tint layers on the first).
#   (e) HIDE: a second run with OPT_AURA_CIRCLES = HIDE draws nothing: no AURA_DRAWN
#       line and the center cell is untinted.
#   (f) NO TINT OUT OF SIGHT: the hidden point (behind the wall, inside the circle's
#       edge) is untinted.
#   (g) NO LIGHT: not read here. tools/check_effect_light.sh cases AU1 and AU2
#       compare LightLevelAt and LightAt over the whole room with and without two
#       overlapping auras (headless, posix build).
# RED: restoring the 2 px ring in DrawAuras (a pixel with |dn - R| <= 1 blended at
# alpha 0.9) makes (c) fail; removing the VI_VISIBLE clip makes (f) fail; ignoring
# OPT_AURA_CIRCLES makes (e) fail.
# Needs the SDL build (./incursion), run windowless. The main session runs it;
# it launches SDL.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal, and OPT_AURA_CIRCLES to HIDE in the hide run only
# fact: terrain and light -- the probe builds the room, writes the wall, and sets every room square lit (legacy .Lit); no aura light is needed to see
# fact: monsters -- none; the probe removes every thing but the player
# fact: pixel coordinates -- DrawAuras logs each circle's center, radius and map cell (AURA_DRAWN); the check takes aura A's line by the map cell the probe reports (auracell); the probe reads cell size from the SDL Term at run time, no fixed font size
# fact: player's sight of each point -- the probe reports VI_VISIBLE for the seen, overlap, top, right and hidden points; the check is INCONCLUSIVE when the scene does not hold
# fact: aura color -- the probe makes both fields PURPLE (GLYPH_VALUE(GLYPH_FLOOR2, PURPLE)); the tint test reads purpleness (red+blue)/2 - green, before and after
# fact: circle radius -- DrawAuras logs it; every point is an offset from A's logged center and radius
# fact: the tint's size -- 0.30 x (the aura color x its shimmer noise 0.5..1, a hash of the field's square, no random draw - the pixel); TINT_MIN sits below the least that gives on a gray floor
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no frames, no AURA_SCENE lines, scene did not hold).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=1
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
TINT_MIN=8          # (a) the least purpleness gain of an interior pixel
UNTINTED_MAX=3      # (b), (e), (f) the most purpleness change of an untinted pixel
OVERLAP_MARGIN=2    # (d) the overlap cell's T must exceed the A-only cell's T by this much

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

# tval <x> <y> <w> <h>: purpleness (red+blue)/2 - green of the box in the after frame
# minus the same box in the before frame ($before, $after).
tval() {
    local b a
    b="$(python3 -I tools/bmp_pixel.py --mean "$before" "$1" "$2" "$3" "$4")" || return 1
    a="$(python3 -I tools/bmp_pixel.py --mean "$after" "$1" "$2" "$3" "$4")" || return 1
    python3 -I -c "import sys; v=list(map(float,sys.argv[1:7])); p=lambda r,g,b:(r+b)/2-g; print(round(p(*v[3:6])-p(*v[0:3]),1))" $b $a
}
pyok() { python3 -I -c "import sys; sys.exit(0 if eval(sys.argv[1]) else 1)" "$1"; }   # pyok '<expression of numbers>'

# ---- the normal run ----
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
read -r cw ch _ <<< "$(point cell)"
if [ -z "${sx:-}" ] || [ -z "${vx:-}" ] || [ -z "${tx:-}" ] || [ -z "${rx:-}" ] || [ -z "${hx:-}" ] || [ -z "${cw:-}" ]; then
    echo "INCONCLUSIVE: could not read the points and the cell size."
    exit 2
fi
if [ "$svis" != 1 ] || [ "$vvis" != 1 ] || [ "$tvis" != 1 ] || [ "$rvis" != 1 ] || [ "$hvis" != 0 ]; then
    echo "INCONCLUSIVE: the scene does not hold (vis seen=$svis overlap=$vvis top=$tvis right=$rvis hidden=$hvis; want 1 1 1 1 0)."
    exit 2
fi

# The probe's points are offsets from aura A's center; the center and radius are what
# DrawAuras really drew for A ("AURA_DRAWN: <cx> <cy> <R> <map x> <map y>"), chosen
# by A's map cell, which the probe reports ("AURA_SCENE: auracell <x> <y>").
read -r aax aay _ <<< "$(point auracell)"
if [ -z "${aax:-}" ]; then
    echo "INCONCLUSIVE: the probe did not report aura A's map cell."
    exit 2
fi
read -r ccx ccy RR _ <<< "$(grep -a 'AURA_DRAWN:' "$log" | sed 's/.*AURA_DRAWN: //' | awk -v x="$aax" -v y="$aay" '$4 == x && $5 == y' | tail -n 1)"
if [ -z "${ccx:-}" ] || [ -z "${RR:-}" ]; then
    echo "INCONCLUSIVE: DrawAuras logged no AURA_DRAWN line for aura A at $aax,$aay (no circle drawn)."
    exit 2
fi
echo "circle drawn at $ccx $ccy radius $RR px"
# absolute pixels. Top ring point (tx,ty) is R above the center; right (rx,ry) is R east.
TXA=$((ccx + tx)); TYA=$((ccy + ty)); RXA=$((ccx + rx)); RYA=$((ccy + ry))
SXA=$((ccx + sx)); SYA=$((ccy + sy)); VXA=$((ccx + vx)); VYA=$((ccy + vy))
HXA=$((ccx + hx)); HYA=$((ccy + hy))
CCX=$ccx; CCY=$ccy

# Sector means, not single pixels: a pixel can sit on a glyph stroke or a wall row whose
# color differs between the frames. tools/aura_sector.py averages T over an annular
# sector east of A (away from B and the wall) in bands of the radius RR.
sect() { python3 -I tools/aura_sector.py "$before" "$after" "$CCX" "$CCY" "$@"; }
Tc=$(sect 8 24) && Ted=$(sect $((RR - 8)) $((RR - 2))) && Tout=$(sect $((RR + 2)) $((RR + 8))) &&
Tband=$(sect $((RR - 1)) $((RR + 1))) &&
T1=$(tval $((SXA - cw / 2)) $((SYA - ch / 2)) "$cw" "$ch") && T2=$(tval $((VXA - cw / 2)) $((VYA - ch / 2)) "$cw" "$ch") &&
Th=$(tval "$HXA" "$HYA" 1 1) || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py or tools/aura_sector.py could not read the frames."
    exit 2
}
echo "T (purpleness after - before): center band $Tc; just inside the edge (R-8..R-2) $Ted; edge band (R-1..R+1) $Tband; outside (R+2..R+8) $Tout; A-only cell $T1; A+B cell $T2; hidden $Th"
fails=0
# (a) interior tinted, and equally at the center and just inside the edge
if pyok "$Tc >= $TINT_MIN and $Ted >= $TINT_MIN and 0.6*$Tc <= $Ted <= 1.6*$Tc"; then
    echo "PASS (a) INTERIOR: the center ($Tc) and just inside the edge ($Ted) are tinted about equally."
else
    echo "FAIL (a) INTERIOR: center $Tc, just inside the edge $Ted (each >= $TINT_MIN, edge within 0.6..1.6 of center)."; fails=1
fi
# (b) just outside is untinted
if pyok "abs($Tout) <= $UNTINTED_MAX"; then
    echo "PASS (b) OUTSIDE: just outside the circle is untinted ($Tout)."
else
    echo "FAIL (b) OUTSIDE: just outside the circle is tinted ($Tout; need |T| <= $UNTINTED_MAX)."; fails=1
fi
# (c) no ring
if pyok "$Tband <= $Ted + 0.5*$Tc + 4"; then
    echo "PASS (c) NO RING: the band within 1 px of R ($Tband) is no more tinted than just inside it ($Ted)."
else
    echo "FAIL (c) NO RING: the band within 1 px of R ($Tband) is more tinted than just inside it ($Ted)."; fails=1
fi
# (d) overlap layers
if pyok "$T2 - $T1 >= $OVERLAP_MARGIN"; then
    echo "PASS (d) OVERLAP: the cell inside A and B has T $T2, the A-only cell $T1 (need a lead of $OVERLAP_MARGIN)."
else
    echo "FAIL (d) OVERLAP: the cell inside A and B has T $T2, the A-only cell $T1 (need a lead of $OVERLAP_MARGIN)."; fails=1
fi
# (f) out of sight
if pyok "abs($Th) <= $UNTINTED_MAX"; then
    echo "PASS (f) NO TINT OUT OF SIGHT: the hidden point is untinted ($Th)."
else
    echo "FAIL (f) NO TINT OUT OF SIGHT: the hidden point is tinted ($Th)."; fails=1
fi
echo "NOTE (g) NO LIGHT: checked headless by tools/check_effect_light.sh cases AU1 and AU2."

# ---- the hide run: (e) ----
run_scene hide hide
echo "$lines"
before="$(lastof before)"
after="$(lastof after)"
if [ -z "$before" ] || [ -z "$after" ]; then
    echo "INCONCLUSIVE: no frames in the hide run under $FRAMES."
    exit 2
fi
Thc=$(tval $((CCX - cw / 2)) $((CCY - ch / 2)) "$cw" "$ch") || {
    echo "INCONCLUSIVE: tools/bmp_pixel.py could not read the hide-run frames."
    exit 2
}
echo "hide run: center T $Thc"
if grep -aq 'AURA_DRAWN:' "$log" || ! pyok "abs($Thc) <= $UNTINTED_MAX"; then
    echo "FAIL (e) HIDE: with OPT_AURA_CIRCLES = HIDE the aura is still drawn."; fails=1
else
    echo "PASS (e) HIDE: with OPT_AURA_CIRCLES = HIDE nothing is drawn."
fi

[ "$fails" = 0 ] || exit 1
echo "PASS: the aura shows as an even tint with no ring, layers where auras overlap, hides on request, and not out of sight."
exit 0
