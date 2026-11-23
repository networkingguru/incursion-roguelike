#!/bin/bash
# gate: live
# inc-jw0hw (Phase 5): the light and motion of five effects. The reel probe (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp) logs
# what the SDL build would draw: REEL_WALLLIGHT (the lit squares of a wall), REEL_MOTION_START / _FRAME / _END / _EXPECT (the squares
# that shake or dance, and each square's pixel pick on 12 frames), REEL_MOTION_XFORM (the pixel transform run on a synthetic cell),
# REEL_FORMATION (a rising corpse) and REEL_SPORE (a spore's glyph and flight). This check runs those clips in the posix build (no
# recorder) and asserts on the lines:
#   W1 Wall of Fire: after the cast and after the idle every wall square is lit and the standing wall light is held; with the wall
#      taken down no square is lit and no standing light is left
#   W4 Wall of Fire while the sweep extends: at every step of the sweep the probe repaints and counts; every square placed so far is lit
#   W2 Wall of Fire after a load: the map's own reset (Term::SetMap, which a load and a level entry both call) leaves no standing light,
#      and the next repaint lights every wall square again from what the map holds; with the wall down no square is lit and no light is left
#   W3 Wall of Fire through a real save and load: run 1 saves the level with the wall standing (INCURSION_WALL_SAVE), run 2 loads that
#      .sav (INCURSION_WALL_LOAD); the same squares are lit after the first repaint as before the save, a light is held, and the load greeting shows
#   M1 Tremor and Boots of Thunder (Thunder): every shake start names exactly the creatures and items in the globe (the probe's own
#      scan of the scene), the far item outside the globe is not named, and every square holds a creature or an item (no floor or wall)
#   M2 Earthmaw: every start names the one victim and nothing else
#   M3 Animate Objects: every start names the floor items only (a creature that holds an item does not shake), and no other square
#   M4 each shake pick: both offsets within 3 pixels, the larger within 1 to 3, and the picks change from frame to frame
#   M5 the pixel transform: every shift of 1 to 3 pixels in eight directions and every mirror leaves the cell's own pixels moved or
#      mirrored inside the cell, the uncovered strip takes the background, and nothing is written outside the cell
#   D1 Othello's Irresistable Dance: the dancers are exactly the humanoid living creatures in its globe, and each shows at least one
#      mirror in the 12 frames; a shake clip (Tremor) shows no mirror
#   D2 the dance lasts the status: at every repaint after the cast (REEL_DANCE_TURN, one per turn) the motion set is exactly the visible
#      creatures that hold the status (the probe's own HasEffStati scan), in dance mode, it holds the dancers for at least one turn
#      after the cast, and it is empty once the status has ended; the shake clips stay hold-only (no turn lines, their motion ends at the hold)
#   D3 the caster does not dance: Othello's dance is EF_CASTER_IMMUNE, so he holds no Dancing status and no motion is on his square
#   R1 reanimation trap: one corpse stands up per step (every batch holds one square), the squares drawn are exactly the squares of
#      the creatures the game raised, and each step shows the risen undead's glyph
#   P1 Vrock Spores: eight or more flights leave the vrock, each glyph is the one for its flight's direction ('-', '/', '|', '\')
#      (the check holds its own table), several fly at once, the first square of each is next to the vrock, one reaches the victim,
#      and the spores cast no light
# RED: break each of these in turn, rebuild, and its assertion must FAIL (see the bead's report): W1 data flag EF_GLOW off the wall;
# M1 the shake set grown to every thing; M2 the set grown by one square; M3 the held-item test removed; M4 a pick of up to 4 pixels;
# M5 the strip left unfilled; D1 no mirror; D2 the dancer scan in StandingPatternPrepare removed; W2 and W3 the rebuild in StandingWallPrepare removed; R1 two squares to a step; P1 the glyph table swapped.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the flask's attack roll and a spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: hit points and damage of the placed creatures -- not read: the check reads the squares drawn, never who dies
# fact: the loaded character and map in run 2 -- the .sav run 1 wrote in this check's own run directory (INCURSION_LOAD), settings options-2026-08-22.dat
# fact: the squares of the caster, the kobolds, the vrock, the items and the corpses -- fixed offsets in the probe (PX, PY, AIMX), no roll
# fact: the random pick of a shake, a dance, a rising order and a spore's start -- cosmetic stream only; the check asserts properties no pick can break (offset ranges, the pixel transform, one square per step, glyph for direction) and "the picks change", which a random pick breaks with probability below 1e-9 per square
# fact: whether a spell's attack roll lands -- the probe casts Earthmaw again until it lands; the check reads every start, so each cast is asserted
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY="Wall of Fire,Tremor,Thunder,Earthmaw,Animate Objects,Othello's Irresistable Dance,reanimation trap,Vrock Spores"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE" | tail -n 1)" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
[ -f "$LOAD" ] || LOAD="$FIXTURE"
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-reel-motion"
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
# W3: a REAL save and a REAL load. Run 1 casts Wall of Fire (the reel probe, INCURSION_WALL_SAVE) and saves the level with the wall up;
# run 2 loads that .sav in a fresh run directory and logs the wall squares and the lit squares after the first repaint.
W1DIR="$RUN_DIR-w3save"; W2DIR="$RUN_DIR-w3load"
mkdir -p "$W1DIR" "$W2DIR"
env INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20 \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$W1DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_WALL_SAVE=1 INCURSION_EFFECT_REEL_ONLY="Wall of Fire" INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh tools/keys/wall-save.keys 1 > "$W1DIR/run.out" 2>&1
SAV="$(ls "$W1DIR"/save/*.sav 2>/dev/null | head -1)"
[ -n "$SAV" ] || { echo "INCONCLUSIVE: the W3 save run wrote no .sav in $W1DIR/save."; exit 2; }
env INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$SAV" INCURSION_RUN_DIR="$W2DIR" INCURSION_WALL_LOAD=1 \
    tools/headless.sh tools/keys/load-char-sheet.keys 1 > "$W2DIR/run.out" 2>&1
echo "Specimen: $W1DIR $W2DIR"
export W3_LOG1="$W1DIR/logs/errors.log" W3_LOG2="$W2DIR/logs/errors.log" W3_ARRIVAL="$(ls "$W2DIR"/logs/screens/*arrival* 2>/dev/null | head -1)"
python3 -I - "$log" <<'PY'
import os, re, sys
log = open(sys.argv[1], errors="replace").read()
res = []
def add(i, ok, text): res.append((i, ok, text))
def sqs(t): return [tuple(int(v) for v in s.split(",")) for s in t.split(";") if s]

def starts(clip):
    out = []
    for m in re.finditer(r"REEL_MOTION_START %s n (\d+) sq (\S*)" % re.escape(clip), log):
        sq = []
        for part in m.group(2).split(";"):
            x, y, kind, mode = part.split(",")
            sq.append((int(x), int(y), kind, int(mode)))
        out.append(sq)
    return out
def expect(clip):
    m = re.search(r"REEL_MOTION_EXPECT %s center (\d+),(\d+) radius (\d+) sq (\S*)" % re.escape(clip), log)
    return (set(sqs(m.group(4))), int(m.group(3))) if m else (None, 0)
def frames(clip):   # list of (frame, [(i, dx, dy, fx, fy)])
    out = []
    for m in re.finditer(r"REEL_MOTION_FRAME %s f (\d+) (\S*)" % re.escape(clip), log):
        row = []
        for part in m.group(2).split(";"):
            i, rest = part.split(":")
            dx, dy, fx, fy = (int(v) for v in rest.split(","))
            row.append((int(i), dx, dy, fx, fy))
        out.append((int(m.group(1)), row))
    return out

# W1 wall light
def wall(when):
    m = re.search(r"REEL_WALLLIGHT Wall of Fire %s squares (\d+) lit (\d+) standing (\d+)" % when, log)
    return tuple(int(v) for v in m.groups()) if m else None
wc, wi, wd = wall("after-cast"), wall("after-idle"), wall("wall-down")
ok = bool(wc and wi and wd) and wc[0] >= 3 and wc[1] == wc[0] and wi[1] == wi[0] and wi[0] == wc[0] and wc[2] >= 1 and wi[2] >= 1 \
    and wd[1] == 0 and wd[2] == 0
wr = wall("after-reset"); wl = wall("after-reload")
ok2 = bool(wr and wl and wc) and wr[2] == 0 and wl[0] == wc[0] and wl[1] == wl[0] and wl[2] >= 1 and wd and wd[1] == 0 and wd[2] == 0
add("W2 Wall of Fire light after a load", ok2, "after reset %s, after reload %s, wall down %s (squares, lit, standing: need no standing light after the reset, then every square lit with a light held, then none once down)" % (wr, wl, wd))
# W3 a real save and a real load
def rd(p):
    try: return open(p, errors="replace").read()
    except OSError: return ""
l1, l2, arr = rd(os.environ.get("W3_LOG1", "")), rd(os.environ.get("W3_LOG2", "")), rd(os.environ.get("W3_ARRIVAL", ""))
m1 = re.search(r"REEL_WALLSAVE squares (\d+) lit (\d+) standing (\d+)", l1)
m2 = re.search(r"REEL_WALLLOAD before-repaint squares (\d+) standing (\d+)", l2)
m3 = re.search(r"REEL_WALLLOAD after-repaint squares (\d+) lit (\d+) standing (\d+)", l2)
greet = "Welcome back to Incursion," in arr
sv = tuple(int(v) for v in m1.groups()) if m1 else None
bf = tuple(int(v) for v in m2.groups()) if m2 else None
af = tuple(int(v) for v in m3.groups()) if m3 else None
ok3 = bool(sv and bf and af) and greet and sv[0] >= 3 and sv[1] == sv[0] and sv[2] >= 1 and bf[0] == sv[0] \
    and af[0] == sv[0] and af[1] == sv[1] and af[2] >= 1
add("W3 Wall of Fire light after a real save and load", ok3, "saved %s, loaded before repaint %s, loaded after repaint %s, load greeting %s (squares, lit, standing; squares, standing; squares, lit, standing: need the same squares and the same lit count after the load as before the save, a light held, and the greeting; the load's own first repaint may already have rebuilt it)" % (sv, bf, af, greet))
add("W1 Wall of Fire light", ok, "after cast %s, after idle %s, wall down %s (squares, lit, standing: need squares >= 3, all lit while it stands, none lit and no light left once it is down)" % (wc, wi, wd))
# W4 each square is lit from the frame it forms. The probe reads the light map the display paints from (LightLitAt) at each step of the
# formation (REEL_WALLFORM: the squares the formation has drawn, after the paint of the batch before) and of the terrain sweep (REEL_WALLSWEEP).
fm = [tuple(int(v) for v in m) for m in re.findall(r"REEL_WALLFORM \w+ step (\d+) drawn (\d+) lit (\d+)", log)]
sw = [tuple(int(v) for v in m) for m in re.findall(r"REEL_WALLSWEEP step (\d+) squares (\d+) lit (\d+) standing (\d+)", log)]
grown = [r for r in sw if r[1] > 0]
ok = len(fm) >= 3 and all(r[2] == r[1] for r in fm) and fm[-1][1] >= 3 and len(grown) >= 2 and all(r[2] == r[1] and r[3] >= 1 for r in grown)
add("W4 Wall of Fire lit while it forms and while the sweep extends", ok, "formation reads %d (step, drawn, lit) %s, sweep steps with squares %d (step, squares, lit, standing) %s (need >= 3 formation reads with every drawn square lit, and every sweep step fully lit with a light held)" % (len(fm), fm[:4], len(grown), grown[:4]))

# M1 Tremor and Thunder
for clip in ("Tremor", "Thunder"):
    st = starts(clip); want, R = expect(clip)
    got = [set((x, y) for x, y, k, md in s) for s in st]
    kinds = [k for s in st for x, y, k, md in s]
    modes = set(md for s in st for x, y, k, md in s)
    ok = bool(st) and want is not None and all(g == want for g in got) and "N" not in kinds and modes == {1} and len(want) >= 5 and \
        sum(1 for s in st[:1] for x, y, k, md in s if k == "I") >= 2
    add("M1 %s shake set" % clip, ok, "starts %d, squares shaken %s, expected %s (radius %s), non-creature non-item squares %d, modes %s (need every start == expected, no floor or wall, shake only, >= 5 squares, >= 2 items)" % (
        len(st), sorted(got[0]) if got else None, sorted(want) if want else None, R, kinds.count("N"), sorted(modes)))

# M2 Earthmaw
st = starts("Earthmaw"); want, R = expect("Earthmaw")
ok = bool(st) and want is not None and len(want) == 1 and all(set((x, y) for x, y, k, md in s) == want and len(s) == 1 and s[0][2] == "C" for s in st)
add("M2 Earthmaw victim", ok, "starts %d, squares %s, victim %s (need each start == the one victim, a creature)" % (len(st), [[(x, y) for x, y, k, md in s] for s in st], sorted(want) if want else None))

# M3 Animate Objects
st = starts("Animate Objects"); want, R = expect("Animate Objects")
got = [set((x, y) for x, y, k, md in s) for s in st]
kinds = sorted(set(k for s in st for x, y, k, md in s))
ok = bool(st) and want is not None and all(g == want for g in got) and len(want) >= 6 and kinds == ["I"]
add("M3 Animate Objects set", ok, "starts %d, squares shaken %d, expected %d (the 6 floor items; the 3 creatures that hold an item do not shake), kinds %s (need every start == expected, items only)" % (
    len(st), len(got[0]) if got else 0, len(want) if want else 0, kinds))

# M4 offsets
bad = []; same = []
for clip in ("Tremor", "Thunder", "Earthmaw", "Animate Objects", "Othello's Irresistable Dance"):
    fr = frames(clip)
    per = {}
    for f, row in fr:
        for i, dx, dy, fx, fy in row:
            if not (abs(dx) <= 3 and abs(dy) <= 3 and 1 <= max(abs(dx), abs(dy)) <= 3):
                bad.append((clip, f, i, dx, dy))
            per.setdefault((clip, i), set()).add((dx, dy))
    same += [k for k, v in per.items() if len(v) < 3]
nframes = sum(len(frames(c)) for c in ("Tremor", "Thunder", "Earthmaw", "Animate Objects", "Othello's Irresistable Dance"))
add("M4 shake offsets", nframes >= 20 and not bad and not same, "frames %d, picks outside 1..3 pixels %d %s, squares whose pick repeats (under 3 different) %d" % (nframes, len(bad), bad[:3], len(same)))

# M5 pixel transform
m = re.search(r"REEL_MOTION_XFORM cases (\d+) bad (\d+) guard-bad (\d+)", log)
add("M5 pixel transform", bool(m) and int(m.group(1)) >= 27 and int(m.group(2)) == 0 and int(m.group(3)) == 0,
    "cases %s, wrong pixels %s, pixels written outside the cell %s (need 27+ cases, 0, 0)" % ((m.group(1), m.group(2), m.group(3)) if m else ("none",) * 3))

# D1 dance
st = starts("Othello's Irresistable Dance"); want, R = expect("Othello's Irresistable Dance")
fr = frames("Othello's Irresistable Dance")
got = [set((x, y) for x, y, k, md in s) for s in st]
modes = set(md for s in st for x, y, k, md in s)
mirrors = {}
for f, row in fr:
    for i, dx, dy, fx, fy in row:
        mirrors[i] = mirrors.get(i, 0) + (1 if fx or fy else 0)
tr = frames("Tremor")
shake_flips = sum(1 for f, row in tr for i, dx, dy, fx, fy in row if fx or fy)
ok = bool(st) and want is not None and all(g == want for g in got) and len(want) >= 3 and modes == {2} and len(mirrors) == len(want) \
    and all(v >= 1 for v in mirrors.values()) and bool(tr) and shake_flips == 0
add("D1 dance", ok, "starts %d, dancers %d, expected %d (humanoid living creatures in its globe), modes %s, mirrors per dancer in 12 frames %s, mirrors in a shake clip %d (need set == expected, mode 2, every dancer >= 1 mirror, 0 in a shake)" % (
    len(st), len(got[0]) if got else 0, len(want) if want else 0, sorted(modes), sorted(mirrors.values()), shake_flips))

# D2 the dance lasts the status
dt = re.findall(r"REEL_DANCE_TURN Othello's Irresistable Dance turn (\d+) want (\d+) (\S*) got (\d+) (\S*)", log)
def dsq(t): return sorted((int(a), int(b)) for a, b, *_ in (s.split(",") for s in t.split(";") if s))
def dmode(t): return set(int(s.split(",")[2]) for s in t.split(";") if s)
rows = [(int(a), int(b), dsq(c), int(d), dsq(e), dmode(e)) for a, b, c, d, e in dt]
tr_turns = len(re.findall(r"REEL_DANCE_TURN Tremor", log))
ok = bool(rows) and all(r[3] == r[1] and r[2] == r[4] and r[5] <= {2} for r in rows) and len(rows) >= 2 and rows[0][1] >= 3 \
    and rows[1][1] >= 1 and rows[-1][1] == 0 and rows[-1][3] == 0 and tr_turns == 0
add("D2 dance lasts the status", ok, "turns %d, dancers per turn %s, motion squares per turn %s (need motion == dancers every turn, dance mode, >= 3 at the cast, >= 1 one turn later, 0 at the end), shake-clip turn lines %d (need 0)" % (
    len(rows), [r[1] for r in rows], [r[3] for r in rows], tr_turns))
# D3 the caster does not dance: he holds no Dancing status and his square is in no motion start and no turn's motion set
cm = re.search(r"REEL_DANCE_CASTER Othello's Irresistable Dance at (\d+),(\d+) status (\d+)", log)
cs = (int(cm.group(1)), int(cm.group(2))) if cm else None
dstarts = starts("Othello's Irresistable Dance")
in_start = any((x, y) == cs for s_ in dstarts for x, y, k, md in s_)
in_turn = any(cs in r[2] or cs in r[4] for r in rows)
ok = bool(cm) and cm.group(3) == "0" and bool(dstarts) and not in_start and not in_turn
add("D3 the caster does not dance", ok, "caster at %s, Dancing status %s, in a motion start %s, in a turn's motion set %s (need no status and no motion on the caster's square, while the other dancers dance)" % (cs, cm.group(3) if cm else None, in_start, in_turn))

# R1 reanimation
fm = re.findall(r"REEL_FORMATION reanimation trap order (\d+) batch (\d+) n (\d+) drawn (\d+) glyph (\d+) fore (\d+) at (\d+),(\d+) radius (\d+) sq (\S*)", log)
raised = re.search(r"REEL_RAISED reanimation trap sq (\S*)", log)
drawn_sq = [sqs(b[9]) for b in fm]
flat = [s for b in drawn_sq for s in b]
rs = set(sqs(raised.group(1))) if raised else None
ok = bool(fm) and rs is not None and len(rs) >= 2 and all(b[2] == "1" and b[3] == "1" for b in fm) and len(flat) == len(set(flat)) and set(flat) == rs \
    and all(b[0] == "9" and b[4] == "90" for b in fm)
add("R1 reanimation", ok, "steps %d, squares per step %s, drawn set %s, raised set %s, glyph ids %s (need 1 square per step, drawn == raised, glyph 90 'Z', order 9)" % (
    len(fm), sorted(set(b[2] for b in fm)), sorted(set(flat)), sorted(rs) if rs is not None else None, sorted(set(b[4] for b in fm))))

# P1 spores
def want_glyph(dx, dy):   # the check's own table: screen y grows downward
    ax, ay = abs(dx), abs(dy)
    if ay * 2 <= ax: return ord("-")
    if ax * 2 <= ay: return ord("|")
    return ord("\\") if (dx > 0) == (dy > 0) else ord("/")
sp = re.findall(r"REEL_SPORE Vrock Spores flight (\d+) step (\d+) at (\d+),(\d+) dir (-?\d+),(-?\d+) glyph (\d+)", log)
sc = re.search(r"REEL_SCENE Vrock Spores vrock (\d) at (-?\d+),(-?\d+) victim (\d+),(\d+)", log)
hk = re.search(r"REEL_HOOKS Vrock Spores light-steps (\d+) with-flash (\d+) target-flashes (\d+)", log)
flights = {}
for f, s, x, y, dx, dy, g in sp:
    flights.setdefault(int(f), []).append((int(s), int(x), int(y), int(dx), int(dy), int(g)))
wrong = [(f, s, g) for f, v in flights.items() for (s, x, y, dx, dy, g) in v if g and g != want_glyph(dx, dy)]
ok = bool(sc) and sc.group(1) == "1" and len(flights) >= 8 and not wrong and bool(hk) and hk.groups() == ("0", "0", "0")
txt_extra = ""
if ok:
    vx, vy, tx, ty = int(sc.group(2)), int(sc.group(3)), int(sc.group(4)), int(sc.group(5))
    firstNear = all(min(v)[1:3] != (vx, vy) and max(abs(min(v)[1] - vx), abs(min(v)[2] - vy)) == 1 for v in flights.values())
    reach = any((x, y) == (tx, ty) for v in flights.values() for (s, x, y, dx, dy, g) in v)
    atOnce = any(sum(1 for v in flights.values() for (s, x, y, dx, dy, g) in v if s == step) >= 2 for step in range(0, 4))
    drew = sum(1 for v in flights.values() for t in v if t[5])
    ok = firstNear and reach and atOnce and drew >= 8
    txt_extra = ", first squares next to the vrock %s, a flight reaches the victim %s, several at once %s, glyphs drawn %d" % (firstNear, reach, atOnce, drew)
add("P1 Vrock Spores", ok, "flights %d, wrong glyphs %d %s, light hooks %s%s (need 8+ flights, glyph for direction, no light)" % (
    len(flights), len(wrong), wrong[:3], hk.groups() if hk else None, txt_extra))

bad = 0
for i, ok, text in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, text))
    bad += 0 if ok else 1
if bad:
    print("FAIL: %d motion assertion(s) failed." % bad); sys.exit(1)
print("PASS: the wall light, the shake, the dance, the rising dead and the spores draw what each ruling says.")
PY
exit $?
