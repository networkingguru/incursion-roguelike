#!/bin/bash
# gate: live
# inc-jw0hw (Phase 4a): an environment effect forms in the order the owner ruled. The reel probe (INCURSION_EFFECT_REEL,
# src/EffectReelProbe.cpp) writes one REEL_FORMATION line per batch of squares (the order, the glyph, the squares), REEL_FORMATION_END
# lines when the whole formation is on show (phase -1) and when its overlay is gone (phase -2), and REEL_FORMATION_FINAL with the squares
# the game really changed to the effect's terrain, read after the cast. This check runs those clips in the posix build (no recorder):
#   F1 floods (Create Water, Whirlpool, water trap, chill water trap, caustic water trap): rings from the center, distances non-decreasing
#   F2 Web: the web glyph is drawn during the formation, ring by ring, and is the glyph the terrain ends with (no late draw)
#   F3 Spike Growth: one square per batch, every square once, a random order (not by distance), and many batches
#   F4 pit trap, small and large trapdoor trap: the center first, one square per batch, every square once, and no blast glyphs (no recolor)
#   F5 caltrop trap: each caltrop flies from the center square to its landing square (a flight line per landing square, several in the
#      air at once), lands in a scattered order, every square once
#   F9 growth in clumps (Forestation, Forest Wall) and growth (Wall of Thorns, thornwall trap): the first batches are 2 to 6 isolated
#      seeds, every later batch is adjacent to a square already grown
#   F10 walls that rise end to end (Wall of Stone, Wall of Fire, Wall of Doors): one square per batch, the position along the line
#      strictly monotonic, no gap
#   F11 walls that form from the middle (Wall of Ice, Wind Wall, Wall of Fog): distance from the line center non-decreasing, the center
#      first, the two squares of a batch on opposite sides of the center
#   F12 a script-made fog (a thunderbeast's own cloud, lib/mon1.irh EV_INITIALIZE) billows through Map::NewField
#   F6 fog banks (Pyrotechnics smoke, Solid Fog, thunderbeast fumes (an AR_MFIELD fog)): rings from the source, the drawn area grows batch by batch
#   F7 vapor traps that leave no fog field (ungol dust cloud, burnt othur vapor, insanity mist): fog glyphs billow out, then the overlay clears
#   F8 the squares the game changed: every formation square set equals the final changed set, pit and trapdoor traps included
#      (the game stops writing once the victim has fallen; the formation shows the squares it wrote and no others)
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the flask's attack roll and a spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: hit points and damage of the placed creatures -- not read: the check reads what is drawn, never who dies
# fact: the squares of the caster, the kobolds, the stub and the room -- fixed offsets in the probe (PX, PY, AIMX, STUBX, RX0..RY1), no roll
# fact: the random order of a pop, a fall or a scatter -- cosmetic_random only; the check asserts properties no order can break (one square per batch, every square once, the center first), and "not sorted by distance" for a 100-square pop, which a random order breaks with probability below 1e-30
# fact: whether a trap's victim falls and stops the game's terrain loop -- F8 requires equality either way: the formation is drawn after the game's writes, over the squares it changed
# fact: the squares of a wall's line -- the room's rows RY0..RY1 at the column in front of the caster; no roll
# fact: the random order of a growth -- cosmetic_random only; the check asserts the seed count (2 to 6) and that every later square borders a grown one, which no order can break
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY="Create Water,Whirlpool,water trap,chill water trap,caustic water trap,Spike Growth,pit trap,small trapdoor trap,large trapdoor trap,caltrop trap,Pyrotechnics,Solid Fog,Web,thunderbeast fumes,ungol dust cloud trap,burnt othur vapor trap,insanity mist vapor trap,Forestation,Forest Wall,Wall of Thorns,thornwall trap,Wall of Stone,Wall of Fire,Wall of Ice,Wall of Doors,Wind Wall,Wall of Fog"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE" | tail -n 1)" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
[ -f "$LOAD" ] || LOAD="$FIXTURE"
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-reel-formation"
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
GLYPH_FOG = 259
res = []
def add(i, ok, text): res.append((i, ok, text))
def dist(a, b):   # the engine's dist() (inc/Inline.h)
    dx, dy = abs(a[0] - b[0]), abs(a[1] - b[1])
    return dx + dy // 2 if dx > dy else dy + dx // 2
def squares(t): return [tuple(int(v) for v in s.split(",")) for s in t.split(";") if s]

def batches(clip):
    out = []
    for m in re.finditer(r"REEL_FORMATION (.+?) order (\d+) batch (\d+) n (\d+) drawn (\d+) glyph (\d+) fore (\d+) at (\d+),(\d+) radius (\d+) sq (\S*)", log):
        if m.group(1) == clip:
            out.append(dict(order=int(m.group(2)), n=int(m.group(4)), drawn=int(m.group(5)), glyph=int(m.group(6)),
                            c=(int(m.group(8)), int(m.group(9))), r=int(m.group(10)), sq=squares(m.group(11))))
    return out
def ends(clip):
    return [(int(m.group(3)), int(m.group(4)), int(m.group(5))) for m in
            re.finditer(r"REEL_FORMATION_END (.+?) order (\d+) phase (-\d) total (\d+) shown (\d)", log) if m.group(1) == clip]
def final(clip):
    m = re.search(r"REEL_FORMATION_FINAL %s n (\d+) glyph (\d+) sq (\S*)" % re.escape(clip), log)
    return (int(m.group(1)), int(m.group(2)), squares(m.group(3))) if m else None
def grows_after_first(cum):
    """the drawn area, cumulative by batch, grows at every batch from the first one that drew (the source square can hold a creature, which keeps its own glyph)"""
    k = next((i for i, v in enumerate(cum) if v > 0), None)
    return k is not None and k <= 1 and all(cum[i] < cum[i + 1] for i in range(k, len(cum) - 1))
def allsq(bs): return [s for b in bs for s in b["sq"]]

# F1 floods
for c in ("Create Water", "Whirlpool", "water trap", "chill water trap", "caustic water trap"):
    bs = batches(c)
    d = [[dist(bs[0]["c"], s) for s in b["sq"]] for b in bs] if bs else []
    ring_each = all(len(set(x)) == 1 for x in d)
    flat = [x[0] for x in d if x]
    mono = all(flat[k] <= flat[k + 1] for k in range(len(flat) - 1))
    add("F1 " + c, len(bs) >= 3 and bs[0]["order"] == 1 and ring_each and mono and flat[:1] == [0],
        "batches %d (need 3+), order %s (need 1 rings), each batch one ring %s, ring distances %s (need non-decreasing from 0)"
        % (len(bs), bs[0]["order"] if bs else None, ring_each, flat[:8]))

# F2 Web
c = "Web"
bs, fi = batches(c), final(c)
drawn_batches = [b for b in bs if b["drawn"] > 0]
add("F2 Web", bool(bs) and bool(fi) and bs[0]["order"] == 1 and len(drawn_batches) >= 2 and all(b["glyph"] == fi[1] for b in drawn_batches),
    "batches %d, batches that drew %d (need 2+), their glyphs %s (need the terrain's final glyph %s), order %s"
    % (len(bs), len(drawn_batches), sorted(set(b["glyph"] for b in drawn_batches)), fi[1] if fi else None, bs[0]["order"] if bs else None))

# F3 Spike Growth
c = "Spike Growth"
bs = batches(c)
sq = allsq(bs)
dd = [dist(bs[0]["c"], s) for s in sq] if bs else []
add("F3 Spike Growth", len(bs) >= 50 and bs[0]["order"] == 2 and all(b["n"] == 1 for b in bs) and len(sq) == len(set(sq)) and dd != sorted(dd),
    "batches %d (need 50+), order %s (need 2 pop), batch sizes all 1 %s, squares %d distinct %d, sorted by distance %s (need False)"
    % (len(bs), bs[0]["order"] if bs else None, all(b["n"] == 1 for b in bs), len(sq), len(set(sq)), dd == sorted(dd)))

# F4 falls
for c in ("pit trap", "small trapdoor trap", "large trapdoor trap"):
    bs = batches(c)
    sq = allsq(bs)
    blast = len(re.findall(r"REEL_GLOBEGLYPH %s " % re.escape(c), log)) + len(re.findall(r"REEL_STEP %s burst " % re.escape(c), log))
    add("F4 " + c, len(bs) >= 5 and bs[0]["order"] == 3 and all(b["n"] == 1 for b in bs) and bs[0]["sq"] == [bs[0]["c"]]
        and len(sq) == len(set(sq)) and blast == 0,
        "batches %d (need 5+), order %s (need 3 fall), sizes all 1 %s, first square %s (need the center %s), squares %d distinct %d, blast or recolor lines %d (need 0)"
        % (len(bs), bs[0]["order"] if bs else None, all(b["n"] == 1 for b in bs), bs[0]["sq"] if bs else None, bs[0]["c"] if bs else None,
           len(sq), len(set(sq)), blast))

# F5 caltrops: a flight per landing square
c = "caltrop trap"
bs = batches(c)
sq = allsq(bs)
fly = {}
order_log = []
for m in re.finditer(r"REEL_FORMATION_FLY %s order (\d+) id (\d+) step (\d+) at (\d+),(\d+) glyph (\d+)" % re.escape(c), log):
    fly.setdefault(int(m.group(2)), []).append((int(m.group(3)), (int(m.group(4)), int(m.group(5))), int(m.group(6))))
    order_log.append(int(m.group(2)))
cen = bs[0]["c"] if bs else (0, 0)
cheb = lambda a, b: max(abs(a[0] - b[0]), abs(a[1] - b[1]))
lines_ok = bool(fly)
for i, st in fly.items():
    pos = [p for _, p, _ in st]
    steps = [k for k, _, _ in st]
    if not (steps == list(range(len(st))) and cheb(cen, pos[0]) <= 1 and all(cheb(pos[k], pos[k + 1]) <= 1 for k in range(len(pos) - 1))
            and len(st) == max(1, cheb(cen, pos[-1])) and st[0][2] != (bs[0]["glyph"] if bs and bs[0]["glyph"] else -1)):
        lines_ok = False
lands = sorted(p[-1][1] for p in fly.values()) if fly else []
overlap = any(order_log.index(i) < k and k < len(order_log) - 1 - order_log[::-1].index(j)
              for i in fly for j in fly if j > i for k in [order_log.index(j)]
              if order_log.index(j) < len(order_log) - 1 - order_log[::-1].index(i)) if len(fly) > 1 else False
in_air = max((sum(1 for i in fly if order_log.index(i) <= k <= len(order_log) - 1 - order_log[::-1].index(i)) for k in range(len(order_log))), default=0)
add("F5 caltrop trap", len(bs) >= 10 and bs[0]["order"] == 4 and len(sq) == len(set(sq)) and lines_ok and lands == sorted(sq) and in_air >= 3,
    "landing batches %d (need 10+), order %s (need 4 scatter), squares %d distinct %d, flights %d each a line from the center %s to its own landing square %s, landing squares equal the formation squares %s, most caltrops in the air at once %d (need 3+)"
    % (len(bs), bs[0]["order"] if bs else None, len(sq), len(set(sq)), len(fly), cen, lines_ok, lands == sorted(sq), in_air))

# F6 fog banks
for c in ("Pyrotechnics (smoke)", "Solid Fog", "thunderbeast fumes"):
    bs = batches(c)
    flat = [dist(bs[0]["c"], b["sq"][0]) for b in bs if b["sq"]]
    mono = all(flat[k] <= flat[k + 1] for k in range(len(flat) - 1))
    cum, acc = [], 0
    for b in bs:
        acc += b["drawn"]; cum.append(acc)
    grows = grows_after_first(cum)
    glyph_ok = all(b["glyph"] == GLYPH_FOG for b in bs if b["drawn"]) if c != "Solid Fog" else all(b["glyph"] > 0 for b in bs if b["drawn"])
    add("F6 " + c, len(bs) >= 3 and bs[0]["order"] == 5 and mono and grows and glyph_ok,
        "batches %d (need 3+), order %s (need 5 billow), ring distances %s non-decreasing %s, drawn area by batch %s strictly grows %s, glyphs fog %s"
        % (len(bs), bs[0]["order"] if bs else None, flat[:8], mono, cum[:8], grows, glyph_ok))

# F7 vapor traps
for c in ("ungol dust cloud trap", "burnt othur vapor trap", "insanity mist vapor trap"):
    bs, en = batches(c), ends(c)
    cum, acc = [], 0
    for b in bs:
        acc += b["drawn"]; cum.append(acc)
    grows = grows_after_first(cum)
    shown = (-1, ) == tuple(e[0] for e in en if e[0] == -1) and any(e[0] == -1 and e[2] == 1 for e in en)
    cleared = any(e[0] == -2 for e in en)
    add("F7 " + c, len(bs) >= 3 and bs[0]["order"] == 5 and grows and shown and cleared and final(c) is None
        and all(b["glyph"] == GLYPH_FOG for b in bs if b["drawn"]),
        "batches %d (need 3+), order %s (need 5 billow), drawn area by batch %s strictly grows %s, whole cloud shown %s, overlay cleared %s, fog field left behind %s (need False), glyphs fog %s"
        % (len(bs), bs[0]["order"] if bs else None, cum[:8], grows, shown, cleared, final(c) is not None,
           all(b["glyph"] == GLYPH_FOG for b in bs if b["drawn"])))

# F8 the squares the game changed
for c, subset in (("Web", False), ("Create Water", False), ("Whirlpool", False), ("water trap", False), ("chill water trap", False),
                  ("caustic water trap", False), ("Spike Growth", False), ("caltrop trap", False), ("Solid Fog", False),
                  ("pit trap", False), ("small trapdoor trap", False), ("large trapdoor trap", False),
                  ("Forestation", False), ("Forest Wall", False), ("Wall of Thorns", False), ("Wall of Stone", False),
                  ("Wall of Fire", False), ("Wall of Ice", False), ("Wind Wall", False), ("Wall of Fog", False)):
    fi, form = final(c), set(allsq(batches(c)))
    got = set(fi[2]) if fi else set()
    ok = bool(fi) and bool(form) and (got <= form if subset else got == form)
    add("F8 " + c, ok, "formation squares %d, squares the game changed %d, %s, formation minus changed %d, changed minus formation %d"
        % (len(form), len(got), "changed within formation required" if subset else "equal required", len(form - got), len(got - form)))

# F9 growth
adj = lambda a, b: max(abs(a[0] - b[0]), abs(a[1] - b[1])) <= 1
for c, order in (("Forestation", 7), ("Forest Wall", 7), ("Wall of Thorns", 8), ("thornwall trap", 8)):
    bs = batches(c)
    sq = allsq(bs)
    k = 0
    while k < len(sq) and not any(adj(sq[k], sq[j]) for j in range(k)):
        k += 1
    rest_ok = all(any(adj(sq[i], sq[j]) for j in range(i)) for i in range(k, len(sq)))
    add("F9 " + c, len(bs) >= 8 and bs[0]["order"] == order and all(b["n"] == 1 for b in bs) and len(sq) == len(set(sq))
        and 2 <= k <= 6 and k < len(sq) and rest_ok,
        "batches %d (need 8+), order %s (need %d), batch sizes all 1 %s, squares %d distinct %d, isolated seeds first %d (need 2 to 6), every later square borders a grown one %s"
        % (len(bs), bs[0]["order"] if bs else None, order, all(b["n"] == 1 for b in bs), len(sq), len(set(sq)), k, rest_ok))

# F10 walls that rise end to end
for c in ("Wall of Stone", "Wall of Fire", "Wall of Doors"):
    bs = batches(c)
    sq = allsq(bs)
    axis = 1 if sq and len({s_[0] for s_ in sq}) == 1 else 0
    pos = [s_[axis] for s_ in sq]
    step = [pos[i + 1] - pos[i] for i in range(len(pos) - 1)]
    mono = bool(step) and (all(v == 1 for v in step) or all(v == -1 for v in step))
    add("F10 " + c, len(bs) >= 10 and bs[0]["order"] == 6 and all(b["n"] == 1 for b in bs) and len({s_[1 - axis] for s_ in sq}) == 1 and mono,
        "batches %d (need 10+), order %s (need 6 sweep), batch sizes all 1 %s, one line %s, position along the line %s strictly monotonic with no gap %s"
        % (len(bs), bs[0]["order"] if bs else None, all(b["n"] == 1 for b in bs), len({s_[1 - axis] for s_ in sq}) == 1, pos[:4] + ["..."] + pos[-2:], mono))

# F11 walls that form from the middle
for c, order in (("Wall of Ice", 1), ("Wind Wall", 1), ("Wall of Fog", 5)):
    bs = batches(c)
    cen = bs[0]["c"] if bs else (0, 0)
    d = [[dist(cen, s_) for s_ in b["sq"]] for b in bs]
    flat = [x[0] for x in d if x]
    mono = all(flat[k] <= flat[k + 1] for k in range(len(flat) - 1)) and all(len(set(x)) == 1 for x in d)
    axis = 1 if bs and bs[-1]["sq"] and len({s_[0] for s_ in allsq(bs)}) == 1 else 0
    opposite = all(len(b["sq"]) == 1 or ((b["sq"][0][axis] - cen[axis]) * (b["sq"][1][axis] - cen[axis]) < 0) for b in bs if len(b["sq"]) <= 2)
    add("F11 " + c, len(bs) >= 5 and bs[0]["order"] == order and bs[0]["sq"] == [cen] and mono and opposite and all(b["n"] <= 2 for b in bs),
        "batches %d (need 5+), order %s (need %d), first square %s (need the line center %s), distances from the center %s non-decreasing %s, a batch holds one square or one on each side %s"
        % (len(bs), bs[0]["order"] if bs else None, order, bs[0]["sq"] if bs else None, cen, flat[:8], mono, opposite))

# F12 script-made fog
c = "thunderbeast script fog"
bs, en = batches(c), ends(c)
flat = [dist(bs[0]["c"], b["sq"][0]) for b in bs if b["sq"]]
mono = all(flat[k] <= flat[k + 1] for k in range(len(flat) - 1))
cum, acc = [], 0
for b in bs:
    acc += b["drawn"]; cum.append(acc)
add("F12 " + c, len(bs) >= 3 and bs[0]["order"] == 5 and mono and grows_after_first(cum) and all(b["glyph"] == GLYPH_FOG for b in bs if b["drawn"])
    and any(e[0] == -2 for e in en),
    "batches %d (need 3+), order %s (need 5 billow), ring distances %s non-decreasing %s, drawn area by batch %s strictly grows %s, overlay cleared %s"
    % (len(bs), bs[0]["order"] if bs else None, flat[:8], mono, cum[:8], grows_after_first(cum), any(e[0] == -2 for e in en)))

bad = 0
for i, ok, text in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, text))
    bad += 0 if ok else 1
print("%d ok, %d failed" % (len(res) - bad, bad))
sys.exit(1 if bad else 0)
PY
exit $?
