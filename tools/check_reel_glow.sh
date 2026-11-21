#!/bin/bash
# gate: live
# inc-jw0hw (Phase 4h): in the reel's own cast path (INCURSION_EFFECT_REEL, MM_EXTEND, Silence on, three kobolds, the
# reel's room) Faerie Fire leaves each kobold glowing in the color stored in its ILLUMINATED status, and the clip
# holds the idle for 2000 ms so the glow shows. Reads the REEL_IDLE and REEL_GLOW lines of src/EffectReelProbe.cpp.
# RED 1: test only te->Vals(1..) for ILLUMINATED, as before; the idle is 700 ms and the check FAILs.
# RED 2: store no value (drop the POST(EV_MAGIC_HIT) handler in lib/pspells.irh); every kobold takes the cval fallback and the check FAILs.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: which color each kobold takes -- random(5) in the spell's script, seeded; the check passes for any stored value and reads the light against it, never assuming one
# fact: the kobolds' squares -- the reel places them at fixed offsets (AIMX, PY-2/PY/PY+2) from the reel's fixed player square
# fact: whether the player's view paints the kobold square through the light -- TextTerm::PutGlyph's own decision, recorded by PutGlyphProbeHook during the reel's post-cast Refresh; no roll decides it
# fact: the idle length -- the reel's own table (2000 ms when the effect inflicts ILLUMINATED); no clock decides it
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "INCONCLUSIVE: no fixture."; exit 2; }
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-reel-glow"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/k.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"
INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="Faerie Fire" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR/run.out" 2>&1
log="$RUN_DIR/logs/errors.log"
grep -aq ' REEL_DONE ' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no REEL_DONE in $log"; exit 2; }
python3 -I - "$log" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
idle = re.findall(r"REEL_IDLE Faerie Fire (\d+)", log)
glow = re.findall(r"REEL_GLOW after-idle kobold (\d) stati (\d) val (-?\d+) light (\d+),(\d+),(\d+) \((\d)\) lit (\d) seen (\d) level (\d+) painted-remembered (-?\d)", log)
# val -> the probe's own oracle color
oracle = {29: (220,225,240), 64: (170,110,255), 32: (255,215,110), 65: (60,150,255), 30: (220,40,60)}
cyan = (127,255,255)
def norm(c):
    m = max(c) or 1
    return tuple(v * 255 // m for v in c)
def d2(a, b): return sum((x - y) ** 2 for x, y in zip(norm(a), norm(b)))
bad = []
if not idle or int(idle[0]) < 2000: bad.append("idle %s ms (need 2000)" % (idle[0] if idle else "none"))
if len(glow) != 3: bad.append("%d kobold glow lines (need 3)" % len(glow))
for k, st, val, r, g, b, got, lit, seen, level, prem in glow:
    val = int(val); c = (int(r), int(g), int(b))
    if seen != "1" or prem != "0": bad.append("kobold %s: seen %s, painted as remembered %s (need seen 1, painted lit 0)" % (k, seen, prem)); continue
    if st != "1" or got != "1" or lit != "1" or not any(c): bad.append("kobold %s: status %s light %s lit %s" % (k, st, c, lit)); continue
    if val not in oracle: bad.append("kobold %s: stored value %d is no glow color" % (k, val)); continue
    if d2(c, oracle[val]) > 600 or d2(c, oracle[val]) > d2(c, cyan): bad.append("kobold %s: light %s is not the color of value %d" % (k, c, val))
print("REEL_GLOW: idle %s ms; kobolds %s" % (idle[:1], [(g[2], g[3:6]) for g in glow]))
if bad:
    print("FAIL: " + "; ".join(bad)); sys.exit(1)
print("PASS: the reel's Faerie Fire leaves each kobold glowing in the color its status stores, and idles 2000 ms.")
PY
