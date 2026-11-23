#!/bin/bash
# gate: live
# inc-jw0hw (Phase 1): each effect reel scene holds what its effect acts on, and the effect acts on it. The probe
# (INCURSION_EFFECT_REEL, src/EffectReelProbe.cpp) places undead for Undeath to Death and the holy water flask, corpses for the
# reanimation trap, items for Animate Objects, six kobolds for Chain Lightning, and a thunderbeast that exudes the fumes; the Skull
# Trap's globe is centered on the skull, not the caster. It logs REEL_SCENE, REEL_FIELD, REEL_STATI and REEL_HP lines. This check
# runs those clips in the posix build (no recorder) and asserts on the lines:
#   S1 Undeath to Death: 5 undead placed, at least 3 dead
#   S2 holy water: 4 undead placed, at least 3 struck
#   S3 reanimation trap: 5 corpses placed, at least 2 raised
#   S4 Animate Objects: 6 floor items and 3 held items placed, at least 5 animated
#   S5 Chain Lightning: 6 targets placed, at least 4 struck
#   S6 thunderbeast fumes: one cloud, made by the thunderbeast, centered on it, the player outside its radius
#   S7 Skull Trap: the player is not afraid (he stands outside the globe) and a kobold in the globe took damage
#   S8 no clip places a wall torch for an effect that is not Pyrotechnics' smoke or Fire Charm (source has no isLitFive)
# Not asserted: the Web (inc-jw0hw Phase 1 task 8) -- its terrain is written after the globe's whole animation (Magic.cpp AGlobe), so no
# reel scene change shows it earlier.
# RED: --red runs the same clips with INCURSION_REEL_SCENE_OFF=1 (the probe places nothing and the Skull Trap's globe is centered on
# the caster again); S1-S7 must all FAIL. S8 goes red when isLitFive is put back in the probe.
# fact: character -- fixture xsummon-priest-seed5-opt0822
# fact: settings -- options-2026-08-22.dat
# fact: a placed creature's saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (a natural 1 fails every save)
# fact: the flask's attack roll and a spell's ranged touch roll -- INCURSION_LOF_FORCE_ROLL=20
# fact: hit points and damage of the placed creatures -- not read: the check counts creatures changed (dead or hurt), and the smallest roll of each effect (3d6, a pool of at least 11 Hit Dice, 10d6) still changes a creature
# fact: Chain Lightning's choice among equally near targets -- not read: the check counts the creatures struck, which is the first target plus one for each arc, whatever order they take
# fact: the squares of every placed creature, corpse and item -- fixed offsets in the probe (PX, PY, AIMX), no roll
# fact: which corpses and items the globe's MapIterate reaches -- the Things array order, which the probe's fixed placement order sets; the check asserts a floor (at least 2 raised, at least 5 animated), not an exact count
# fact: what a kobold carries -- the probe removes whatever its generation gave it before it gives the held item
# Exit 0 PASS, 1 FAIL, 2 INCONCLUSIVE (no build, no fixture, no REEL_DONE).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RED=0
case "${1:-}" in
    "") ;;
    --red) RED=1 ;;
    *) echo "usage: tools/check_effect_reel_scenes.sh [--red]" >&2; exit 2 ;;
esac
OPTIONS=tools/fixtures/options-2026-08-22.dat
FIXTURE=xsummon-priest-seed5-opt0822
ONLY="Undeath to Death,water,reanimation trap,Animate Objects,Chain Lightning,thunderbeast fumes,skull trap"
[ -x ./incursion-headless ] || { echo "INCONCLUSIVE: ./incursion-headless is missing. Run: BACKEND=posix ./build_macos.sh"; exit 2; }
LOAD="$(tools/fixture_cache.sh "$FIXTURE")" || { echo "INCONCLUSIVE: tools/fixture_cache.sh could not build $FIXTURE."; exit 2; }
RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-reel-scenes"
mkdir -p "$RUN_DIR"
KEYS="$RUN_DIR/k.keys"
for _ in $(seq 1 80); do echo "ESC"; done > "$KEYS"
echo "@quit" >> "$KEYS"
SCENE_OFF=""
[ "$RED" -eq 1 ] && SCENE_OFF=1
env ${SCENE_OFF:+INCURSION_REEL_SCENE_OFF=1} INCURSION_FORCE_SAVE_ROLL=1 INCURSION_LOF_FORCE_ROLL=20 \
    INCURSION_OPTIONS="$OPTIONS" INCURSION_LOAD="$LOAD" INCURSION_RUN_DIR="$RUN_DIR" \
    INCURSION_EFFECT_REEL=1 INCURSION_EFFECT_REEL_ONLY="$ONLY" INCURSION_LIGHT_TABLE="$ROOT/tools/fixtures/effect-light-table.tsv" \
    tools/headless.sh "$KEYS" 1 > "$RUN_DIR/run.out" 2>&1
log="$RUN_DIR/logs/errors.log"
echo "Specimen: $RUN_DIR"
grep -aq ' REEL_DONE ' "$log" 2>/dev/null || { echo "INCONCLUSIVE: no REEL_DONE in $log (the probe did not finish)."; exit 2; }
python3 -I - "$log" "$ROOT/src/EffectReelProbe.cpp" "$RED" <<'PY'
import re, sys
log = open(sys.argv[1], errors="replace").read()
src = open(sys.argv[2], errors="replace").read()
red = sys.argv[3] == "1"
def one(pat):
    m = re.findall(pat, log)
    return m[-1] if m else None
res = []   # (id, ok, text)
def add(i, ok, text): res.append((i, ok, text))

m = one(r"REEL_SCENE Undeath to Death targets (\d+) struck (\d+) dead (\d+)")
add("S1 Undeath to Death", bool(m) and int(m[0]) >= 5 and int(m[2]) >= 3, "undead placed %s, dead %s (need 5+, 3+)" % ((m[0], m[2]) if m else ("none", "none")))
m = one(r"REEL_SCENE water targets (\d+) struck (\d+) dead (\d+)")
add("S2 holy water", bool(m) and int(m[0]) >= 4 and int(m[1]) >= 3, "undead placed %s, struck %s (need 4+, 3+)" % ((m[0], m[1]) if m else ("none", "none")))
m = one(r"REEL_SCENE reanimation trap corpses (\d+) left (\d+) raised (\d+)")
add("S3 reanimation trap", bool(m) and int(m[0]) >= 5 and int(m[2]) >= 2, "corpses placed %s, raised %s (need 5+, 2+)" % ((m[0], m[2]) if m else ("none", "none")))
m = one(r"REEL_SCENE Animate Objects floor-items (\d+) held-items (\d+) floor-items-left (\d+) animated (\d+)")
add("S4 Animate Objects", bool(m) and int(m[0]) >= 6 and int(m[1]) >= 3 and int(m[3]) >= 5,
    "floor items placed %s, held items %s, animated %s (need 6+, 3+, 5+)" % ((m[0], m[1], m[3]) if m else ("none",) * 3))
m = one(r"REEL_SCENE Chain Lightning targets (\d+) struck (\d+) dead (\d+)")
add("S5 Chain Lightning", bool(m) and int(m[0]) >= 6 and int(m[1]) >= 4, "targets placed %s, struck %s (need 6+, 4+)" % ((m[0], m[1]) if m else ("none", "none")))

fields = re.findall(r"REEL_FIELD thunderbeast fumes thunderbeast fumes center (\d+),(\d+) radius (\d+) creator (\S.*)", log)
sc = one(r"REEL_SCENE thunderbeast fumes fields (\d+) thunderbeast (\d) at (-?\d+),(-?\d+) player (\d+),(\d+)")
ok = False; txt = "no cloud or no scene line"
if sc and len(fields) == 1:
    cx, cy, rad, who = int(fields[0][0]), int(fields[0][1]), int(fields[0][2]), fields[0][3].strip()
    tbx, tby, px, py = int(sc[2]), int(sc[3]), int(sc[4]), int(sc[5])
    d = max(abs(cx - px), abs(cy - py))
    ok = sc[1] == "1" and who == "thunderbeast" and (cx, cy) == (tbx, tby) and d > rad
    txt = "clouds %d, creator %s, center (%d,%d), thunderbeast at (%d,%d), player (%d,%d) is %d away of radius %d (need 1, thunderbeast, same square, away > radius)" % (
        len(fields), who, cx, cy, tbx, tby, px, py, d, rad)
add("S6 thunderbeast fumes", ok, txt)

st = re.findall(r"REEL_STATI skull trap player (\S+)", log)
hp = one(r"REEL_HP skull trap kobold hp (\d+)/(\d+) (\d+)/(\d+) (\d+)/(\d+)")
hurt = bool(hp) and any(int(hp[i]) < int(hp[i + 1]) for i in (0, 2, 4))
afraid = bool(st) and "AFRAID" in st[-1]
add("S7 Skull Trap", bool(st) and not afraid and hurt, "player afraid %s (need False), a kobold hurt %s (need True)" % (afraid, hurt))

add("S8 no effect torch", "isLitFive" not in src, "isLitFive %s in src/EffectReelProbe.cpp" % ("present" if "isLitFive" in src else "absent"))

bad = 0
for i, ok, text in res:
    print("%s %s: %s" % ("ok  " if ok else "FAIL", i, text))
    bad += 0 if ok else 1
if red:
    scene = [r for r in res if not r[0].startswith("S8")]
    still = [i for i, ok, t in scene if ok]
    if still:
        print("RED FAIL: with the scene content left out these still pass: " + ", ".join(still)); sys.exit(1)
    print("RED PASS: with the scene content left out, S1-S7 all fail.")
    sys.exit(0)
if bad:
    print("FAIL: %d scene assertion(s) failed." % bad); sys.exit(1)
print("PASS: each scene holds what its effect acts on, and the effect acts on it.")
PY
exit $?
