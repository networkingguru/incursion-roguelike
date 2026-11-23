#!/bin/bash
# gate: live
# inc-jw0hw (Phase 2): each single-effect clip of the effect reel draws the shape and color the owner ruled. The probe
# (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp) casts each effect in a lit room and writes REEL_STEP lines (every projectile,
# pillar, dart, thrown-item and burst glyph, with the number of light flashes alive when it showed), REEL_RING, REEL_GLOBEGLYPH,
# REEL_DECIDE, REEL_HOOKS and REEL_GEOM lines. This check runs those clips in the posix build (no recorder) and asserts:
#   H1 Force Missiles: one flight, and the burst opens on the square where the missile struck; the burst shows and is lit
#   H2 Flame Strike: no projectile from the caster; a pillar falls down one column from the top of the view onto the target
#      square, with light on its last square; then the lit burst of blast glyphs
#   H3 flame strike trap: the same pillar onto the victim, then a lit burst of blast glyphs
#   H4 fireball trap and Pyrotechnics explosion: rings of blast glyphs over the area, lit
#   H5 tanglefoot bag: the tool glyph flies from the thrower to the target square
#   H6 each dart trap (bloodroot, arsenic, terinav root, wyvern venom): a straight dart flight of 1 to 3 squares ending next to
#      the victim, the arrow glyph, no light; and the flight plan for a victim 2 squares and 1 square from a wall starts at that wall
#   H7 Unholy Blight: lit in the necromantic color, and its glyphs are that color (not shadow)
#   H8 Cloudkill: lit in the poison color; its burst is fog glyphs in the poison colors, not blast glyphs
#   H9 Mud Spray: the struck kobold flashes (the target flash runs)
#   W1 each held-weapon clip: the holder sees by the weapon (sight range above 0, a held radius above 0) and the light map lights squares
#   W2 each weapon-hit clip: exactly one target flash runs, and the hit deals extra damage (the disruption kill deals none and kills)
#   W3 each weapon-flight clip: the weapon flies 3 or more squares and hits; exactly one impact flash runs (fire seeds, a thrown produced flame, flaming dagger and arrow)
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the flask's attack roll and a spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: hit points and damage of the placed creatures -- not read: the check reads what is drawn, never who dies
# fact: the squares of the caster, the kobolds and the room -- fixed offsets in the probe (PX, PY, AIMX, RX0..RY1), no roll
# fact: the colors a burst or globe takes -- BlastColourSets rows read in the same run (REEL_COLSET), not constants of the check
# fact: the random pick among a ball's three glyph colors -- the check accepts any of the set's three (cosmetic_random only)
# fact: which wall a dart trap's dart comes from -- DartFlightPlan is a pure function of the map and the victim's square; the check asserts the plan for fixed squares of the fixed room
# fact: the weapon clips' hit and flight rolls -- the probe forces them (LOFSetForcedRoll 20, LOFSetForcedSaveThrowRoll 1 for the disruption kill); no roll decides them
# fact: the weapon clips' items, holder and victims -- made by the probe (Item::Create, qualities set directly; the first generated monster of the kind that lights no square); no roll decides them
# RED (W1-W3): make LightHeldRadius return 0 (W1 fails), or drop the FlashStruck call in WeaponHitFlash (W2 fails), or drop the produced-flame FlashSquare in Creature::RAttack (W3 fails).
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY="Force Missiles,Flame Strike,flame strike trap,fireball trap,Pyrotechnics,tanglefoot bag,bloodroot dart trap,arsenic dart trap,terinav root dart trap,wyvern venom dart trap,Unholy Blight,Cloudkill,Mud Spray,Weapons"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE" | tail -n 1)" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
[ -f "$LOAD" ] || LOAD="$FIXTURE"
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-reel-shapes"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/k.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"
env INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20 \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="$ONLY" INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR/run.out" 2>&1
log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
grep -aq ' REEL_DONE ' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no REEL_DONE in $log (the probe did not finish)."; exit 2; }
python3 -I - "$log" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
GLYPH_BLAST, GLYPH_FOG, GLYPH_TOOL = 263, 259, 307
ARROWS = {347, 348, 349, 350, 351, 47, 92}   # the arrow glyphs and the two diagonal strokes
res = []
def add(i, ok, text): res.append((i, ok, text))

def steps(clip, kind):
    out = []
    for m in re.finditer(r"REEL_STEP (.+?) %s (-?\d+),(-?\d+) glyph (\d+) fore (\d+) flashes (\d+) lit (\d)" % kind, log):
        if m.group(1) == clip:
            out.append(tuple(int(v) for v in m.groups()[1:]))   # x, y, glyph, fore, flashes, lit
    return out
def travels(clip):
    return len([1 for m in re.finditer(r"REEL_STEP (.+?) travel ", log) if m.group(1) == clip])
def geom(clip):
    m = re.search(r"REEL_GEOM %s player (\d+),(\d+) victim (\d+),(\d+) aim (\d+),(\d+) top (\d+)" % re.escape(clip), log)
    return tuple(int(v) for v in m.groups()) if m else None
def rings(clip):
    return [tuple(int(v) for v in m.groups()[1:]) for m in re.finditer(r"REEL_RING (.+?) ring (-?\d+) taken (\d+) drawn (\d+) flashes (\d+) at (-?\d+),(-?\d+)", log) if m.group(1) == clip]
def hooks(clip):
    m = re.search(r"REEL_HOOKS %s light-steps (\d+) with-flash (\d+) target-flashes (\d+)" % re.escape(clip), log)
    return tuple(int(v) for v in m.groups()) if m else (0, 0, 0)
def decide(clip):
    return [tuple(int(v) for v in m.groups()) for m in re.finditer(r"REEL_DECIDE %s part (\d+) dtype (\d+) lit (\d) colour (\d+)" % re.escape(clip), log)]
def colset(clip):
    m = re.search(r"REEL_COLSET %s poison (\d+),(\d+),(\d+),(\d+) necro (\d+),(\d+),(\d+),(\d+)" % re.escape(clip), log)
    return tuple(int(v) for v in m.groups()) if m else None

# H1 Force Missiles: the missile stops on the struck creature's square; the burst opens on that square
c = "Force Missiles"
g = geom(c)
st, bu, ri = steps(c, "step"), steps(c, "burst"), [r for r in rings(c) if r[0] == -2]
last = (st[-1][0], st[-1][1]) if st else None
opened = (ri[0][4], ri[0][5]) if ri else None
aim = (g[4], g[5]) if g else None
near = bool(last and aim) and max(abs(last[0] - aim[0]), abs(last[1] - aim[1])) <= 1
add("H1 Force Missiles", travels(c) == 1 and len(st) >= 2 and near and len(bu) > 0 and opened == aim and bu[0][4] > 0,
    "flights %d (need 1), missile squares %d, last missile square %s (need next to the target %s), burst glyphs %d (need 1+), burst opens at %s (need the target square), flashes at the first burst glyph %s (need 1+)"
    % (travels(c), len(st), last, aim, len(bu), opened, bu[0][4] if bu else "none"))

# H2 Flame Strike and H3 flame strike trap
def pillar(i, c, target_of):
    g = geom(c); pl = steps(c, "pillar"); bu = steps(c, "burst")
    ok = False
    if g and pl:
        tx, ty = target_of(g)
        col = len(set(p[0] for p in pl)) == 1 and pl[0][0] == tx
        ys = [p[1] for p in pl]
        down = all(ys[k + 1] == ys[k] + 1 for k in range(len(ys) - 1))
        ok = col and down and ys[0] == g[6] and ys[-1] == ty and len(pl) >= 3 and pl[-1][5] == 1 and pl[-1][4] > 0
        txt = "pillar squares %d (need 3+), column %s, falls one square each step %s, top %d (view top %d), last y %d (target y %d), last square lit %s" % (
            len(pl), col, down, ys[0], g[6], ys[-1], ty, pl[-1][5])
    else:
        txt = "pillar squares %d (need 3+), geometry %s" % (len(pl), g)
    bl = [b for b in bu if b[2] == GLYPH_BLAST]
    add(i, ok and travels(c) == 0 and len(bl) >= 5 and bu[0][4] > 0,
        "%s; projectile flights %d (need 0); burst blast glyphs %d (need 5+), flashes at the first %s (need 1+)" % (txt, travels(c), len(bl), bu[0][4] if bu else "none"))
pillar("H2 Flame Strike", "Flame Strike", lambda g: (g[4], g[5]))
pillar("H3 flame strike trap", "flame strike trap", lambda g: (g[2], g[3]))

# H4 fireball trap, Pyrotechnics explosion
for i, c, need in (("H4 fireball trap", "fireball trap", 30), ("H4 Pyrotechnics explosion", "Pyrotechnics (explosion)", 10)):
    bu = [b for b in steps(c, "burst") if b[2] == GLYPH_BLAST]
    drawn = [r for r in rings(c) if r[0] >= 0 and r[3] > 0]
    add(i, len(bu) >= need and len(drawn) >= 2 and bu[0][4] > 0,
        "blast glyphs %d (need %d+), rings with glyphs %d (need 2+), flashes at the first glyph %s (need 1+)" % (len(bu), need, len(drawn), bu[0][4] if bu else "none"))

# H4 fireball trap color: Fireball's COL_FIRE set (RED 4, PINK 12, YELLOW 14 for rings; BlastColourSets rows 16, src/Magic.cpp)
bu = [b for b in steps("fireball trap", "burst") if b[2] == GLYPH_BLAST]
fs = set(b[3] for b in bu)
add("H4 fireball trap color", bool(fs) and fs <= {4, 12, 14} and 4 in fs and 14 in fs,
    "blast glyph colors %s (need only the fire set 4,12,14, with red 4 and yellow 14 present, as Fireball draws)" % sorted(fs))

# H5 tanglefoot bag
c = "tanglefoot bag"
g = geom(c); th = steps(c, "thrown")
ok = bool(g and th) and len(th) >= 3 and max(abs(th[0][0] - g[0]), abs(th[0][1] - g[1])) == 1 and (th[-1][0], th[-1][1]) == (g[4], g[5]) and all(t[2] == GLYPH_TOOL for t in th)
add("H5 tanglefoot bag", ok, "thrown squares %d (need 3+), first %s (need next to the player %s), last %s (need the target %s), all the tool glyph %s" % (
    len(th), (th[0][0], th[0][1]) if th else None, (g[0], g[1]) if g else None, (th[-1][0], th[-1][1]) if th else None, (g[4], g[5]) if g else None,
    bool(th) and all(t[2] == GLYPH_TOOL for t in th)))

# H6 dart traps
for c in ("bloodroot dart trap", "arsenic dart trap", "terinav root dart trap", "wyvern venom dart trap"):
    g = geom(c); dt = steps(c, "dart")
    ok = False; txt = "dart squares %d, geometry %s" % (len(dt), g)
    if g and dt:
        vx, vy = g[2], g[3]
        dxs = set((dt[k + 1][0] - dt[k][0], dt[k + 1][1] - dt[k][1]) for k in range(len(dt) - 1))
        straight = len(dxs) <= 1
        lastnear = max(abs(dt[-1][0] - vx), abs(dt[-1][1] - vy)) == 1
        firstd = max(abs(dt[0][0] - vx), abs(dt[0][1] - vy))
        glyphs = all(d[2] in ARROWS for d in dt)
        dark = all(d[4] == 0 for d in dt)
        ok = 1 <= len(dt) <= 3 and straight and lastnear and 1 <= firstd <= 3 and glyphs and dark and travels(c) == 0
        txt = "dart squares %d (need 1-3), straight %s, last next to the victim %s, first %d from the victim (need 1-3), arrow glyphs %s, no light %s, projectile flights %d (need 0)" % (
            len(dt), straight, lastnear, firstd, glyphs, dark, travels(c))
    add("H6 " + c, ok, txt)
plans = {}
for m in re.finditer(r"REEL_DARTPLAN (.+?) victim (\d+),(\d+) squares (\d+) first (-?\d+),(-?\d+)", log):
    plans[(m.group(1), int(m.group(2)), int(m.group(3)))] = (int(m.group(4)), int(m.group(5)), int(m.group(6)))
c = "bloodroot dart trap"
p2, p1 = plans.get((c, 5, 17)), plans.get((c, 4, 17))
add("H6 dart from the nearest wall", p2 == (2, 3, 17) and p1 == (1, 3, 17),
    "victim 2 squares from the west wall (5,17): squares/first %s (need 2 squares, first = the wall square 3,17); victim next to it (4,17): %s (need 1 square, first 3,17)" % (p2, p1))

# H7 Unholy Blight: the glyph color is the palette purple (5), the necromantic hue; shadow (8) shows nothing
c = "Unholy Blight"
d = decide(c); gg = [int(m.group(1)) for m in re.finditer(r"REEL_GLOBEGLYPH %s \d+,\d+ fore (\d+)" % c, log)]
h = hooks(c)
add("H7 Unholy Blight", bool(d) and d[0][2] == 1 and d[0][3] == 19 and bool(gg) and all(f == 5 for f in gg) and h[1] > 0,
    "decision lit %s colour %s (need 1, COL_NECRO 19), globe glyph colors %s (need all purple 5, never shadow 8), light steps with a flash %d (need 1+)" % (
        d[0][2] if d else None, d[0][3] if d else None, sorted(set(gg)) if gg else "none", h[1]))

# H8 Cloudkill
c = "Cloudkill"
d = decide(c); cs = colset(c); bu = steps(c, "burst"); h = hooks(c)
poison = set(cs[0:4]) if cs else set()
add("H8 Cloudkill", bool(d) and d[0][2] == 1 and d[0][3] == 23 and len(bu) >= 5 and all(b[2] == GLYPH_FOG and b[3] in poison for b in bu) and h[1] > 0,
    "decision lit %s colour %s (need 1, COL_POISON 23), burst glyphs %d (need 5+), glyph ids %s (need only fog %d), colors %s (need the poison set %s), light steps with a flash %d (need 1+)" % (
        d[0][2] if d else None, d[0][3] if d else None, len(bu), sorted(set(b[2] for b in bu)), GLYPH_FOG, sorted(set(b[3] for b in bu)), sorted(poison), h[1]))

# H9 Mud Spray
c = "Mud Spray"
h = hooks(c)
add("H9 Mud Spray flash", h[2] >= 1, "target flashes %d (need 1+)" % h[2])

# W1-W3 the weapon clips (inc-as123)
def wlines(tag, pat):
    out = {}
    for m in re.finditer(r"REEL_WEAPON_%s (Weapon .*?) %s" % (tag, pat), log):
        out[m.group(1)] = tuple(int(v) for v in m.groups()[1:])
    return out
held = wlines("HELD", r"lightrange (\d+) radius (\d+) lit (\d+)")
hits = wlines("HIT", r"flashes (\d+) xdmg (-?\d+) died (\d)")
flights = wlines("FLIGHT", r"steps (\d+) flashes (\d+) hit (\d)")
bad_held = ["%s: lightrange %d radius %d lit %d" % ((k,) + v) for k, v in held.items() if v[0] <= 0 or v[1] <= 0 or v[2] <= 0]
add("W1 held weapons", len(held) == 10 and not bad_held, "%d held clips (need 10); those without sight, radius or lit squares: %s" % (len(held), bad_held or "none"))
bad_hit = []
for k, v in hits.items():
    kill = k.endswith("disruption kill")
    if v[0] != 1 or (v[1] > 0) == kill or (v[2] == 1) != kill:
        bad_hit.append("%s: flashes %d xdmg %d died %d" % ((k,) + v))
add("W2 weapon hits", len(hits) == 11 and not bad_hit, "%d hit clips (need 11); wrong ones: %s" % (len(hits), bad_hit or "none"))
bad_fl = ["%s: steps %d flashes %d hit %d" % ((k,) + v) for k, v in flights.items() if v[0] < 3 or v[1] != 1 or v[2] != 1]
add("W3 weapon flights", len(flights) == 4 and not bad_fl, "%d flight clips (need 4); wrong ones: %s" % (len(flights), bad_fl or "none"))

bad = 0
for i, ok, text in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, text))
    bad += 0 if ok else 1
if bad:
    print("FAIL: %d shape assertion(s) failed." % bad); sys.exit(1)
print("PASS: each single-effect clip draws the shape and color ruled for it.")
PY
exit $?
