#!/bin/bash
# gate: live
# inc-nrxo8: Chain Lightning follows the d20 spell: the bolt strikes the primary target, then EVERY secondary arc starts at the
# primary's square. Magic::ABallBeamBolt once started each arc where the last one ended (1 to 2 to 3 to 4). An arc still strikes
# every creature in its path, so a creature MAY be struck more than once; but the spell arcs to a creature only once. This check casts Chain Lightning
# through the effect reel probe (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp), whose scene puts the primary kobold 9 squares east of
# the caster and five more kobolds 5 to 7 squares around it in different directions, none behind another as seen from it. With
# INCURSION_CHAIN_BRANCH_PROBE the engine logs CHAIN_BRANCH_PROBE lines: each arc's start and end square and its chosen target, and each creature struck.
#   B1 the cast logged a primary arc and 3 secondary arcs, and 4 or more strikes (a run that logs no arc FAILS, never passes)
#   B2 every secondary arc starts at the square where the primary arc ended
#   B5 the secondary arcs are drawn together: every secondary arc starts before any secondary arc ends, step k of every arc comes before
#      step k+1 of any arc, and the light fades once, after the last arc ends (never between the primary's end and the last arc's end)
#   B4 no creature is the target of two arcs (the engine logs each arc's chosen target square)
# RED: B2: revert the chain block of Magic::ABallBeamBolt (src/Magic.cpp) to start each arc at the last arc's end. B4: drop the ArcList exclusion there. B5: draw each arc to its end before the next starts, and fade after each arc. Rebuild, run.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: the squares of the primary and every secondary kobold -- fixed offsets in the probe (PX, PY, AIMX), no roll
# fact: the number of arcs -- the probe gives the caster a fixed caster level (BONUS_SCHOOL_CASTING_LEVEL 9), so the spell arcs 3 times (level / 3)
# fact: which of two equally near kobolds an arc picks -- not read: the check asserts where each arc starts and that arcs end on distinct squares, whatever order they take
# fact: creatures an arc strikes in passing -- not read: the check reads each arc's chosen target (its end square), never the strike lines for B4
# fact: the order of the engine's draw steps -- the engine logs each drawn square (step, arc, square) and each fade in the order they happen; no roll or clock enters the order
# fact: damage and hit points of the kobolds -- not read: the check reads the engine's strike lines, not hit points
# fact: what a kobold carries -- not read
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-chain-branch"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/k.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"
env INCURSION_CHAIN_BRANCH_PROBE=1 INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20 \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="Chain Lightning" INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR/run.out" 2>&1
log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
grep -aq ' REEL_DONE ' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no REEL_DONE in $log (the probe did not finish)."; exit 2; }
python3 -I - "$log" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
starts, ends, aims, strikes = {}, {}, {}, []
events = []   # in log order: ("start", n), ("step", n, k), ("end", n), ("fade",)
for m in re.finditer(r"CHAIN_BRANCH_PROBE: (?:arc (\d+) (start|end)|step (\d+) arc (\d+) |fade)", log):
    if m.group(1) is not None: events.append((m.group(2), int(m.group(1))))
    elif m.group(3) is not None: events.append(("step", int(m.group(4)), int(m.group(3))))
    else: events.append(("fade",))
for m in re.finditer(r"CHAIN_BRANCH_PROBE: (?:arc (\d+) (start|end) (\d+),(\d+)(?: target (\d+),(\d+))?|strike (\d+),(\d+))", log):
    if m.group(1) is not None:
        n, kind, x, y = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4))
        (starts if kind == "start" else ends)[n] = (x, y)
        if m.group(5) is not None: aims[n] = (int(m.group(5)), int(m.group(6)))
    else:
        strikes.append((int(m.group(7)), int(m.group(8))))
res = []
def add(i, ok, t): res.append((i, ok, t))
arcs = sorted(starts)
add("B1 arcs and strikes read", len(arcs) >= 4 and 0 in ends and len(strikes) >= 4,
    "arcs logged %d (need 4+), primary arc end %s, strikes logged %d (need 4+)" % (len(arcs), "yes" if 0 in ends else "no", len(strikes)))
if 0 in ends:
    P = ends[0]
    bad = ["arc %d starts at %d,%d" % (n, *starts[n]) for n in arcs if n >= 1 and starts[n] != P]
    add("B2 secondary arcs start at the primary", len(arcs) >= 2 and not bad,
        "primary %d,%d; secondary arcs not starting there: %s (need none)" % (P[0], P[1], ", ".join(bad) or "none"))
targets = [aims[n] for n in arcs if n in aims]
dup = sorted(set(t for t in targets if targets.count(t) > 1))
add("B4 no creature is the target of two arcs", bool(targets) and not dup,
    "arc target squares %s; on two arcs: %s (need none)" % (targets, dup or "none"))
ev_end = [i for i, v in enumerate(events) if v[0] == "end"]
sec_start = [i for i, v in enumerate(events) if v[0] == "start" and v[1] >= 1]
sec_end = [i for i, v in enumerate(events) if v[0] == "end" and v[1] >= 1]
sec_steps = [v[2] for v in events if v[0] == "step" and v[1] >= 1]
fades = [i for i, v in enumerate(events) if v[0] == "fade"]
together = bool(sec_start) and bool(sec_end) and max(sec_start) < min(sec_end) and bool(sec_steps) and all(a <= b for a, b in zip(sec_steps, sec_steps[1:]))
once = bool(ev_end) and len(fades) == 1 and fades[0] > max(ev_end)
add("B5 secondary arcs drawn together, one fade after the last arc ends", together and once,
    "last secondary start at event %s, first secondary end at %s, secondary step numbers %s (need starts first, steps never going back); fades at events %s, last arc end at %s (need exactly one fade, after it)" % (max(sec_start) if sec_start else None, min(sec_end) if sec_end else None, sec_steps, fades, max(ev_end) if ev_end else None))
bad = 0
for i, ok, t in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, t)); bad += 0 if ok else 1
if bad:
    print("FAIL: %d assertion(s) failed." % bad); sys.exit(1)
print("PASS: every secondary arc started at the primary's square and no creature was the target of two arcs.")
PY
exit $?
