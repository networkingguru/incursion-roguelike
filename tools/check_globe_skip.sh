#!/bin/bash
# gate: live
# inc-jve92: a globe strikes every thing in its radius, even when a strike takes a thing off the map. Magic::AGlobe once walked
# m->Things by index; Animate Objects removes the floor item it animates, which shifted the next thing into the slot just passed, so
# every other item stayed on the floor (inc-etic is the same fault for creatures). This check casts Animate Objects through the effect
# reel probe (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp), whose scene puts six floor items in the globe (open floor, one in
# line with the caster's aim) and one far outside it. It reads the probe's REEL_MOTION_EXPECT line (globe center and radius) and
# its REEL_ITEM lines, and asserts:
#   G1 the probe placed 6 or more floor items
#   G2 no floor item inside the globe's radius is left on the floor
#   G3 the floor item outside the radius is still on the floor
# The spell removes a floor item only after it makes the animated object for it, so a removed item is an animated one. The probe's
# animated count also counts held items, so the check does not read it.
# RED: revert only the AGlobe collect-then-strike loop in src/Magic.cpp, rebuild, run: G2 fails and names the items left.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: the squares of every placed item -- fixed offsets in the probe (PX, PY, AIMX), no roll
# fact: the globe's center and radius -- read from the probe's REEL_MOTION_EXPECT line (the aimed kobold's square, the effect's lval), not hard-coded
# fact: which items the globe's MapIterate reaches first -- not read: the check asserts every in-radius item, in any order
# fact: what a kobold carries -- the probe removes whatever its generation gave it before it gives the held item; held items are not counted
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-globe-skip"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/k.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"
env INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20 \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="Animate Objects" INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR/run.out" 2>&1
log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
grep -aq ' REEL_DONE ' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no REEL_DONE in $log (the probe did not finish)."; exit 2; }
python3 -I - "$log" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
ex = re.findall(r"REEL_MOTION_EXPECT Animate Objects center (\d+),(\d+) radius (\d+)", log)
sc = re.findall(r"REEL_SCENE Animate Objects floor-items (\d+) held-items (\d+) floor-items-left (\d+) animated (\d+)", log)
if not ex or not sc:
    print("INCONCLUSIVE: no REEL_MOTION_EXPECT or REEL_SCENE line for Animate Objects."); sys.exit(2)
cx, cy, rad = map(int, ex[-1]); placed = int(sc[-1][0])
left = [(n, int(x), int(y)) for n, x, y in re.findall(r"REEL_ITEM Animate Objects left .*? (\w+) at (\d+),(\d+)", log)]
def dist(x, y):   # the engine's dist(): max(dx,dy) + min(dx,dy)/2
    dx, dy = abs(x - cx), abs(y - cy); return max(dx, dy) + min(dx, dy) // 2
inside = [l for l in left if dist(l[1], l[2]) <= rad]
outside = [l for l in left if dist(l[1], l[2]) > rad]
res = []
def add(i, ok, t): res.append((i, ok, t))
add("G1 items placed", placed >= 6, "floor items placed %d (need 6+)" % placed)
add("G2 none left in the globe", not inside,
    "globe center %d,%d radius %d: items left on the floor inside it: %s (need none)" % (cx, cy, rad, ", ".join("%s at %d,%d" % l for l in inside) or "none"))
add("G3 far item stays", len(outside) == 1, "items left outside the globe: %d (need 1)" % len(outside))
bad = 0
for i, ok, t in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, t)); bad += 0 if ok else 1
if bad:
    print("FAIL: %d assertion(s) failed." % bad); sys.exit(1)
print("PASS: the globe struck every floor item in its radius and left the far one.")
PY
exit $?
