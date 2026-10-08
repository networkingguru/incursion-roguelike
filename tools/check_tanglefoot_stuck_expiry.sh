#!/bin/bash
# gate: live
# Does STUCK from thrown tanglefoot strands let go? Bead inc-9smo.
#
# THE DEFECT. lib/alchemy.irh sends ThrowDmg(EV_DAMAGE,AD_STUK,-1,"tanglefoot
# strands",...) at the mount and the unmounted branch. The -1 becomes the STUCK
# Duration, and Thing::UpdateStati (src/Status.cpp) only counts down a Duration
# above zero. The strands vanish by themselves (Map::UpdateTerra), but the
# creature stays stuck: the only exit is the escape check in src/Move.cpp, and
# a creature that makes no move makes no check.
#
# THE PLANNED FIX has two parts. This check asserts each on its own.
#   (a) TIMEOUT: tanglefoot STUCK lasts 2d4 rounds, not -1.
#   (b) LINK: when Map::RemoveTerra removes the strands, every creature on that
#       square whose STUCK Val is the terrain's STICK_TYPE loses STUCK at once.
#
# TICKS. A stati "round" is 60 game ticks: Main.cpp throws EV_TURN at every
# creature, and runs Map::UpdateTerra, only when Turn%60 == 0, and
# Creature::DoTurn (src/Creature.cpp) is what calls UpdateStati. So 2d4 rounds
# is at most 8 stati decrements, at most 8*60 = 480 ticks after the first
# boundary that follows the grab (540 with one boundary of slack). The strands
# last Duration decrements of UpdateTerra, so they vanish at a boundary:
# R = B1 + (Duration-1)*60 (B1 = first boundary after the throw). A wait key is
# about 16 ticks, so one "." is a quarter of a round.
#
# ASSERTION (a), RUN A. Throw, step out at once (the strands catch a creature
# leaving), then wait one key at a time with a dump after each. STUCK must be
# gone within 540 ticks of the grab AND while the strands are still on the map
# (the location line still names them). Strands last at least 9 rounds, the
# worst timeout ends 60 ticks sooner, so the (a)-only fix passes and the
# (b)-only fix cannot: it frees at R, with the strands already gone.
#
# ASSERTION (b), RUN B. Same throw, but wait N keys first so the step-out
# lands in the last 44 ticks before R (N is planned from run A's own R). The
# creature is grabbed less than a round before the strands go, so the
# shortest 2d4 timeout (2 rounds, ends at R+60 at the earliest) cannot free it.
# STUCK must be gone on the first dump after the strands vanish. The (b)-only
# fix passes and the (a)-only fix cannot.
#
# MOUNTED. Seeds 1..4 ride a horse (tanglefoot-wait50-mount.keys, paladin):
# the mount takes the STUCK. It is read from the mount's stati in wizard
# "Examine Player Data" (a "STUCK from SS ATTK ... [Dur -1]" line), one dump
# after each wait. Unmounted (tanglefoot-wait50.keys, seeds 5..10) the oracle
# is the "Stuck" word on the status line; Dur is not printed there.
#
# CAN'T-TELL IS NOT PASS (exit 2 when no case could be judged). A case counts
# only if the throw printed, the first step-out left STUCK on the target with
# the strands on the map, no escape-check line ever appeared (so a roll did
# not free it), and the strands were seen to vanish. A run that cannot show
# that is skipped; if every case is skipped the exit is 2, never 0.
#
# Usage: tools/check_tanglefoot_stuck_expiry.sh [UNMOUNTED_SEEDS [MOUNTED_SEEDS]]
#        defaults "5 6 7 8 9 10" and "1 2 3 4" (quote a list, "" for none). 0 pass, 1 fail, 2 inconclusive.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

UNSEEDS="${1-5 6 7 8 9 10}"
MSEEDS="${2-1 2 3 4}"
OPTS=tools/fixtures/options-2026-08-22.dat
WAITS=48   # per-key waits after the step: 48*16 = 768 ticks > R + 100

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTS" ] || { echo "INCONCLUSIVE: options fixture missing"; exit 2; }

TMP="$ROOT/logs/tanglefoot-expiry-$$"
mkdir -p "$TMP"

# make_keys <mode> <prewaits> <out>: the prefix of the committed key script up
# to its "thrown" dump, <prewaits> waits, one step-out, then one wait and one
# dump per key. Mounted mode also dumps "Examine Player Data" after each.
make_keys() {
    local mode="$1" pre="$2" out="$3" src n
    src="$SRC"
    n="$(grep -n '^@dump:thrown$' "$src" | cut -d: -f1)"
    # @include resolves next to the key file; the generated file lives in logs/.
    head -n "$n" "$src" | sed "s#^@include #@include $ROOT/tools/keys/#" > "$out"
    local i
    for i in $(seq 1 "$pre"); do echo "." >> "$out"; done
    { echo "RIGHT"; echo '@while "Confirm" y'; echo "@dump:try1"; } >> "$out"
    if [ "$mode" = mount ]; then
        { echo w; echo '@choose "Examine Player Data"'; echo "DOWN*148"
          echo "@dump:str"; echo ESC; } >> "$out"
    fi
    for i in $(seq 1 "$WAITS"); do
        { echo "."; echo "@dump:w$(printf %02d "$i")"; } >> "$out"
        if [ "$mode" = mount ]; then
            { echo w; echo '@choose "Examine Player Data"'; echo "DOWN*148"
              echo "@dump:s$(printf %02d "$i")"; echo ESC; } >> "$out"
        fi
    done
    echo "@quit" >> "$out"
}

# run_keys <keys> <seed> <tag>: one sandboxed run, unique run directory.
run_keys() {
    local keys="$1" seed="$2" tag="$3"
    RUN_DIR="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-$tag"
    INCURSION_RUN_DIR="$RUN_DIR" INCURSION_OPTIONS="$OPTS" INCURSION_MAP_AUDIT=0 \
        tools/headless.sh "$keys" "$seed" >/dev/null 2>&1
    SCREENS="$RUN_DIR/logs/screens"
}

# The analyser. analyse <A|B|PLAN> <mode> <screens-dir> [<run-A-dir-info>]
analyse() { python3 - "$@" <<'PY'
import glob, os, re, statistics, sys
what, mode, d = sys.argv[1:4]
rows, stati = [], {}
for f in sorted(glob.glob(os.path.join(d, "*.txt"))):
    txt = open(f, errors="replace").read()
    m = re.match(r"=== screen \d+ (\S+)\s+key \d+\s+mode \d+\s+turn (\d+)", txt)
    if not m: continue
    name, turn = m.group(1), int(m.group(2))
    lines = txt.split("\n")
    if name in ("thrown", "try1") or re.fullmatch(r"w\d+", name):
        strands = any(re.match(r"^The .*\(tanglefoot strands", l) for l in lines)
        # Unmounted, the thrower's own square carries no terrain (the location
        # line is empty there), so the strands are read off the map as the '~'
        # ring around the '@'. No other '~' is on the Entry Chamber map.
        if mode == "plain":
            strands = sum(l[:64].count("~") for l in lines) >= 3
        bar = any(l.startswith("HP:") and re.search(r"\bStuck\s*\|", l) for l in lines)
        rows.append(dict(name=name, turn=turn, strands=strands, bar=bar,
                         valid=(mode == "plain"), stuck=(mode == "plain" and bar),
                         thrown=("You throw a tanglefoot bag" in txt), dur=None))
    elif name == "str" or re.fullmatch(r"s\d+", name):
        key = "try1" if name == "str" else "w" + name[1:]
        stati[key] = (("MOUNT from SS MISC" in txt),
                      ("STUCK from SS ATTK" in txt),
                      (re.search(r"STUCK from SS ATTK.*?\[Dur (-?\d+)\]", txt) or [None, None])[1])
for r in rows:
    if mode == "mount" and r["name"] in stati:
        r["valid"], r["stuck"], r["dur"] = stati[r["name"]]
thrown = [r for r in rows if r["name"] == "thrown"]
try1 = [r for r in rows if r["name"] == "try1"]
ws = [r for r in rows if re.fullmatch(r"w\d+", r["name"])]
def bail(msg):
    print("SKIP " + msg); sys.exit(3)
if not thrown or not thrown[0]["thrown"]: bail("the throw message never printed")
if not try1 or len(ws) < 10: bail("the run did not reach its dumps")
t = try1[0]
if not t["valid"]: bail("no readable stati dump at the step-out (mount section missing)")
if not t["stuck"]: bail("the step-out did not leave the target stuck (save passed)")
if not t["strands"]: bail("the step-out dump shows no strands on the map")
seq = [t] + ws
w = int(statistics.median([b["turn"] - a["turn"] for a, b in zip(ws, ws[1:])])) if len(ws) > 1 else 16
last_with = max((r["turn"] for r in seq if r["strands"]), default=None)
first_without = min((r["turn"] for r in seq if not r["strands"]), default=None)
if first_without is None: bail("the strands never vanished within the run")
R = [x for x in range(last_with + 1, first_without + 1) if x % 60 == 0]
if len(R) != 1: bail("cannot place the strand-vanish boundary (candidates %s)" % R)
R = R[0]
if what == "PLAN":
    print("PLAN R=%d w=%d t_try=%d" % (R, w, t["turn"])); sys.exit(0)
dur = t["dur"]
durtxt = " [Dur %s]" % dur if dur is not None else ""
if what == "A":
    free = next((r for r in ws if r["valid"] and not r["stuck"]), None)
    lastw = ws[-1]
    if free is None:
        print("FAIL(a) STUCK%s still present at turn %d, %d ticks after the grab at turn %d "
              "(limit 540); strands vanished at turn %d" %
              (durtxt, lastw["turn"], lastw["turn"] - t["turn"], t["turn"], R))
    elif not free["strands"]:
        print("FAIL(a) STUCK ended only at turn %d, when the strands were already gone "
              "(R=%d): the strands' removal freed it, not a timeout" % (free["turn"], R))
    elif free["turn"] - t["turn"] > 540:
        print("FAIL(a) STUCK ended %d ticks after the grab (limit 540)" % (free["turn"] - t["turn"]))
    else:
        print("PASS(a) STUCK ended %d ticks after the grab, strands still on the map (R=%d)" %
              (free["turn"] - t["turn"], R))
elif what == "B":
    if not t["turn"] > R - 44: bail("step-out at turn %d is not within 44 ticks of R=%d" % (t["turn"], R))
    if t["turn"] >= R: bail("step-out at turn %d is after R=%d" % (t["turn"], R))
    f = next(r for r in seq if not r["strands"])
    before = [r for r in seq if r["turn"] < f["turn"]]
    if any(not r["stuck"] for r in before if r["valid"]): bail("target got free before the strands vanished")
    if not f["valid"]: bail("no readable stati dump after the strands vanished")
    if f["stuck"]:
        print("FAIL(b) STUCK%s still present at turn %d, first dump after the strands vanished "
              "at turn %d; grabbed at turn %d, %d ticks before they vanished" %
              (durtxt, f["turn"], R, t["turn"], R - t["turn"]))
    else:
        print("PASS(b) STUCK gone at turn %d, first dump after the strands vanished at turn %d "
              "(grabbed at turn %d)" % (f["turn"], R, t["turn"]))
PY
}

nrun=0; npass=0; nfail=0; nskip=0; jud_a=0; jud_b=0
judge() { # judge <what> <mode> <seed> <screens>
    local out rc
    out="$(analyse "$1" "$2" "$4")"; rc=$?
    case "$out" in
        PASS*) echo "$2 seed $3: $out"; npass=$((npass + 1)); [ "$1" = A ] && jud_a=$((jud_a + 1)) || jud_b=$((jud_b + 1)) ;;
        FAIL*) echo "$2 seed $3: $out"; nfail=$((nfail + 1)); [ "$1" = A ] && jud_a=$((jud_a + 1)) || jud_b=$((jud_b + 1)) ;;
        *)     echo "$2 seed $3: INCONCLUSIVE $1: ${out#SKIP }"; nskip=$((nskip + 1)) ;;
    esac
    if grep -qhE "Escape Artist Check:|Strength Check:|tear free|break free" "$4"/*.txt 2>/dev/null; then
        echo "$2 seed $3: INCONCLUSIVE $1: an escape-check line appeared, so a roll may have freed it"
        # take back the verdict just counted
        case "$out" in PASS*) npass=$((npass - 1)) ;; FAIL*) nfail=$((nfail - 1)) ;; *) nskip=$((nskip - 1)) ;; esac
        nskip=$((nskip + 1))
    fi
}

one_case() { # one_case <mode> <seed>
    local mode="$1" seed="$2" plan R w tt N pre tries
    # The rogue-archer drops 1d2 bags; the pickup name differs, so a seed that
    # carries two needs the other committed script.
    local cands="tools/keys/tanglefoot-wait50.keys tools/keys/tanglefoot-wait50-2bags.keys"
    [ "$mode" = mount ] && cands=tools/keys/tanglefoot-wait50-mount.keys
    for SRC in $cands; do
        make_keys "$mode" 0 "$TMP/a.keys"
        run_keys "$TMP/a.keys" "$seed" "stuckexp-a-$mode-s$seed"; nrun=$((nrun + 1))
        [ -f "$SCREENS/"*-thrown.txt ] 2>/dev/null && break
    done
    judge A "$mode" "$seed" "$SCREENS"
    plan="$(analyse PLAN "$mode" "$SCREENS")"
    case "$plan" in PLAN*) ;; *)
        echo "$mode seed $seed: INCONCLUSIVE (b): run A gave no plan: ${plan#SKIP }"; nskip=$((nskip + 1)); return ;;
    esac
    R="$(echo "$plan" | sed 's/.*R=\([0-9]*\).*/\1/')"
    w="$(echo "$plan" | sed 's/.*w=\([0-9]*\).*/\1/')"
    tt="$(echo "$plan" | sed 's/.*t_try=\([0-9]*\).*/\1/')"
    N=$(( (R - 22 - tt + w / 2) / w )); pre=$N
    for tries in 1 2; do
        make_keys "$mode" "$pre" "$TMP/b.keys"
        run_keys "$TMP/b.keys" "$seed" "stuckexp-b$tries-$mode-s$seed"; nrun=$((nrun + 1))
        out="$(analyse B "$mode" "$SCREENS")"
        # a step-out outside the last 44 ticks: correct N once from what run B saw
        if [ "$tries" = 1 ] && grep -q "SKIP step-out at turn" <<< "$out"; then
            local tb
            tb="$(analyse PLAN "$mode" "$SCREENS" | sed 's/.*t_try=\([0-9]*\).*/\1/')"
            case "$tb" in ''|*[!0-9]*) break ;; esac
            pre=$(( pre + (R - 22 - tb) / w )); continue
        fi
        break
    done
    judge B "$mode" "$seed" "$SCREENS"
}

for s in $UNSEEDS; do one_case plain "$s"; done
for s in $MSEEDS;  do one_case mount "$s"; done

# The run directories are evidence; only the generated key files are scratch.
rm -f "$TMP/a.keys" "$TMP/b.keys"; rmdir "$TMP" 2>/dev/null

echo "runs $nrun, assertions passed $npass, failed $nfail, inconclusive $nskip"
if [ "$nfail" -gt 0 ]; then
    echo "FAIL: tanglefoot STUCK does not end by timeout (a) and/or when the strands vanish (b)."
    exit 1
fi
if [ "$jud_a" = 0 ] || [ "$jud_b" = 0 ]; then
    echo "INCONCLUSIVE: assertion (a) judged $jud_a times, (b) judged $jud_b times; both need one."
    exit 2
fi
echo "PASS: every judged assertion held."
exit 0
