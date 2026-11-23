#!/bin/bash
# gate: live
# inc-jw0hw Phase 3: a stronger grade of a lit effect releases more light than its basic grade, and the basic grade's
# light does not change. The probe (INCURSION_GRADE_PROBE) lights each graded effect's real EffectLight on one square
# of a dark room and prints the peak light on that square and on the 1..4 squares east of it, then again after the
# light ends. Checks: (a) a basic grade (Minor Drain, Inflict Light Wounds, minor lightning bolt trap, Minor Light Ray)
# keeps today's shape: own square full, 1 out 0.75, 2 out 0.45, 3 and 4 out dark. (b) at each higher grade, squares
# 1 and 2 out are no dimmer than at the grade below, and the first square past the lower grade's reach is lit only
# at the higher grade, out to base reach + grade squares. Basic grades are pinned to [220,164,99,0..] by (a).
# (c) the effect's own square is the same at every grade. (e) no square around the effect is brighter than the effect's own
# square, and none has a channel above the own square's channel (the ring keeps the effect's hue). (d) after the light ends, no square is lit.
# RED: in src/Light.cpp ScanFlashes, skip the extra-light loop (set its bound to 0); (b) must FAIL. GREEN: restore.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat, named in INCURSION_OPTIONS; the probe forces OPT_ANIMATION Normal
# fact: terrain and darkness -- the probe builds the map, clears legacy Lit/Bright and zeroes the player's light, infravision and shadow ranges
# fact: the lit square -- (PX+10, PY), a fixed offset from the player's fixed square; the probe calls EffectLight::Light on it, open floor, so the player sees it; no roll decides it
# fact: a square's age -- a fresh flash at clock 0, the same for every grade; never the wall clock
# fact: effect grades and colors -- read from the loaded module's flags (EF_GRADE_n) and the data's cval and damage type; no dice
# Exit 0 on PASS, 1 on FAIL, 2 on INCONCLUSIVE.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless not built."; exit 2; }
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-effect-light-grade"
INCURSION_GRADE_PROBE=1 INCURSION_EFFECT_LIGHT_PROBE=1 INCURSION_LIGHT_PROBE=1 INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat INCURSION_LOAD=xsummon-priest-seed5-opt0822 \
    tools/headless.sh tools/keys/effect-light.keys 1 > /dev/null 2>&1
log="$RUN_DIR/logs/errors.log"
[ -s "$log" ] || { echo "INCONCLUSIVE: no $log"; exit 2; }
python3 - "$log" <<'PY'
import re, sys
rows, ends = {}, {}
for l in open(sys.argv[1], errors='replace'):
    m = re.search(r'EFFECT_LIGHT: GRADE (.+?) grade=(\d) p0=(\d+) p1=(\d+) p2=(\d+) p3=(\d+) p4=(\d+) p5=(\d+) p6=(\d+)', l)
    if m: rows[m.group(1)] = (int(m.group(2)), [int(m.group(i)) for i in range(3, 10)])
    m = re.search(r'EFFECT_LIGHT: GRADEEND (.+?) p0=(\d+) p1=(\d+) p2=(\d+) p3=(\d+) p4=(\d+) p5=(\d+) p6=(\d+) flashes=(\d+)', l)
    if m: ends[m.group(1)] = [int(m.group(i)) for i in range(2, 10)]
cols = {}
for l in open(sys.argv[1], errors='replace'):
    m = re.search(r'EFFECT_LIGHT: GRADEC (.+?) ((?:\d+,\d+,\d+ ?){7})', l)
    if m: cols[m.group(1)] = [tuple(int(v) for v in t.split(',')) for t in m.group(2).split()]
for n, (g, p) in sorted(rows.items()): print("GRADE %-30s g=%d %s" % (n, g, p))
bad = []
def need(c, msg):
    if not c: bad.append(msg)
ladders = [("drain", ["Minor Drain", "Major Drain"]),
           ("lightning trap", ["minor lightning bolt trap", "major lightning bolt trap"]),
           ("light ray", ["Minor Light Ray", "Major Light Ray"]),
           ("inflict", ["Inflict Light Wounds", "Inflict Moderate Wounds", "Inflict Serious Wounds", "Inflict Critical Wounds"]),
           ("inflict traps", ["inflict light wounds trap", "inflict serious wounds trap", "inflict critical wounds trap"])]
expect = {"Minor Drain": 0, "Major Drain": 1, "Minor Light Ray": 0, "Major Light Ray": 1, "minor lightning bolt trap": 0,
          "major lightning bolt trap": 1, "Inflict Light Wounds": 0, "Inflict Moderate Wounds": 1, "Inflict Serious Wounds": 2,
          "Inflict Critical Wounds": 3, "inflict light wounds trap": 0, "inflict serious wounds trap": 2, "inflict critical wounds trap": 3}
for n, g in expect.items():
    need(n in rows, "%s: no probe line" % n)
    if n in rows: need(rows[n][0] == g, "%s: grade %d, want %d" % (n, rows[n][0], g))
for name, ladder in ladders:
    if not all(n in rows for n in ladder): continue
    base = rows[ladder[0]][1]
    # (a) basic grade keeps today's shape
    need(base[0] > 0 and abs(base[1] - 0.75 * base[0]) <= 0.06 * base[0] and abs(base[2] - 0.45 * base[0]) <= 0.06 * base[0]
         and not any(base[3:]), "%s basic %s: not today's shape (full, .75, .45, dark beyond)" % (name, base))
    for i in range(1, len(ladder)):
        lo, hi = rows[ladder[i-1]][1], rows[ladder[i]][1]
        need(hi[0] == lo[0], "%s: own square differs (%d vs %d)" % (ladder[i], hi[0], lo[0]))   # (c)
        need(hi[1] >= lo[1] and hi[2] >= lo[2], "%s: ring 1/2 dimmer than %s (%s vs %s)" % (ladder[i], ladder[i-1], hi, lo))  # (b)
        gh = rows[ladder[i]][0]
        # grade n lights distance base reach + n; the grade below does not
        need(lo[2 + gh] == 0 and hi[2 + gh] > 0, "%s: square %d out must be lit only at the higher grade (%d vs %d)" % (ladder[i], 2 + gh, hi[2+gh], lo[2+gh]))
for n, (g, p) in rows.items():   # (e) no square passes the effect's own square; the ring keeps the effect's hue
    need(n in cols, "%s: no color line" % n)
    if n not in cols: continue
    own = cols[n][0]
    for d in range(1, 7):
        need(p[d] <= p[0], "%s: square %d out (%d) is brighter than the own square (%d)" % (n, d, p[d], p[0]))
        need(all(cols[n][d][c] <= own[c] for c in range(3)), "%s: square %d out %s has a channel above the own square %s" % (n, d, cols[n][d], own))
for n in rows:   # (d)
    need(n in ends and all(v == 0 for v in ends[n][:7]) and ends[n][7] == 0, "%s: light remains after the effect ends: %s" % (n, ends.get(n)))
if bad:
    print("FAIL"); [print("  " + b) for b in bad]; sys.exit(1)
print("PASS"); sys.exit(0)
PY
