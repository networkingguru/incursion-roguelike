#!/bin/bash
# gate: live
# Reproduction for bd inc-vhkei: does a creature move toward its target through
# ground the PLAYER has never seen?
#
# THE DEFECT. Monster::SmartDirTo (src/Monster.cpp) asks Map::ShortestPath for a
# route, and Map::ShortestPath floods with RunOver(...,memonly=true,...)
# (src/Djikstra.cpp, "if (memonly && !At(x,y).Memory) return 0;"). So every
# square the player has not seen is impassable to the route search: a creature
# in a room the player never saw finds no route, SmartDirTo returns CENTER, and
# the creature waits every turn. The search runs only when the option
# OPT_MON_DJIKSTRA is YES (1) for any creature, or PETS (2) for a companion
# (is_pet true); on NO (0), or PETS for a non-companion, SmartDirTo steps
# straight (DirTo) and never reads map memory.
#
# WHAT THIS RUNS. Ten cases: mode in {hostile, companion, neutral} x opt in
# {0, 1, 2}, plus one mode=player case. Each runs the RouteUnseen probe
# (src/RouteUnseenProbe.cpp) once, in its own INCURSION_RUN_DIR, on a fixed
# sealed L-shaped corridor built when the overview map first opens (src/Term.cpp)
# when INCURSION_ROUTE_UNSEEN is set: player at one end, watched creature at the
# far end, every arena square except the player's own left Memory 0 (and cleared
# again each turn). The creature's OWN AI (Monster::Movement ->
# Monster::SmartDirTo) moves it, so the route search runs under the option under
# test:
#   hostile    hostile to the player, TRACKING it (perceives through walls)
#   companion  MakeCompanion to the player (PHD_PARTY), follows via getLeader()
#   neutral    TurnNeutralTo and an inc-9622 investigate TargetArea at the
#              player's square (type 7)
#
# THE PLAYER CASE. mode=player stages the same corridor with no watched
# creature, and the PLAYER asks to travel to the far end with Player::RunTo
# (src/Creature.cpp) -- the function the overview map's [R] Run to Point calls.
# RunTo routes with Map::ShortestPath's DEFAULT memonly=true (this fix's own
# declaration, inc/Map.h), so with the corridor's memory cleared it finds no
# route and refuses ("runto refused", RunToProbe). The case carries its own
# CONTROL, observed in the same run: the SAME request with the corridor's memory
# intact must be accepted ("runto accepted"). A refusal is proof only when the
# same route succeeds with memory intact.
#
# A creature makes two KINDS of SmartDirTo request: toward its REAL target --
# the player for hostile and companion, the investigate area (the player's
# square) for neutral -- and toward a random wander point (TargetWander,
# type 8). At opt=2 a companion's follow request (pet=1) is blocked, but its
# wander request takes the straight branch and moves it, so distance alone
# falsely reads as success: this check judges the REAL-target requests only.
#
# FIXED, per case, is judged on BOTH:
#   1. every SmartDirTo request whose target is the case's REAL target (tgt
#      equal to the player's square, read from the stage line) took a branch
#      that yields a step -- straight, lof, or spok (a route found) -- and NONE
#      took spblocked or failedrecent; at least one such request exists, else
#      the case cannot be judged;
#   2. the distance to the real target falls between the first and last turn.
#
# The mode=player case is FIXED when its control (memory intact) is accepted AND
# its candidate (memory cleared) is refused. Both RunToProbe lines must be
# present, so the outcomes came from Player::RunTo and not from a staging
# shortcut.
#
# Exit 0 all FIXED, 1 any FAULT PRESENT, 2 a case could not be judged (no
# build, log missing, staging failed, no real-target request, or a player case
# whose control was not accepted). 2 wins over 1: a case that did not run says
# nothing.
#
# Usage: tools/check_route_unseen.sh [--prove-red] [seed]   (needs BACKEND=posix build)
#
# --prove-red: two mutations, each applied to its OWN scratch copy of the tree
# (never the worktree's own src/), each rebuilt and run against this same check:
#   mutation 1  restore memonly=true at the SmartDirTo call (the exact base-code
#               state the fix removes): the four creature cases the fix repaired
#               go red, the player case stays green;
#   mutation 2  set the DEFAULT of memonly in inc/Map.h's ShortestPath
#               declaration to false, so player travel routes over the real map
#               rather than the player's memory: the player case goes red.
# PROVED RED is reported for each mutation separately.
#
# This check reads only facts it fixes. Where the seed could otherwise decide a
# fact, the control below pins it. The branch a REAL-target request takes is the
# property under test -- an invariant that MUST hold on every seed, like the
# encounter-building checks in docs/VERIFICATION.md -- and the wander requests,
# whose target the seed does decide, are excluded from the measurement.
# fact: character race/class/stats/kit/name -- fixture tools/fixtures/chars/kobold-rogue-seed1.sav via INCURSION_LOAD
# fact: the scene (sealed L corridor, player at one end, creature at the far end, route squares memory-cleared) -- probe src/RouteUnseenProbe.cpp, gated by INCURSION_ROUTE_UNSEEN; builds the map, independent of the generated level
# fact: the watched creature's mode/role (hostile/companion/neutral) -- INCURSION_ROUTE_UNSEEN
# fact: the option under test OPT_MON_DJIKSTRA (0/1/2) -- INCURSION_ROUTE_OPT (probe sets p->Options[OPT_MON_DJIKSTRA])
# fact: how many turns are watched -- INCURSION_ROUTE_TURNS
# fact: settings file -- tools/fixtures/options-2026-08-22.dat
# fact: the branch a real-target SmartDirTo request takes -- invariant, not seed-read: fixed by the option and the probe's corridor; the seed-decided wander requests are excluded
# fact: the player case's terrain (same sealed L corridor, player at one end) -- probe src/RouteUnseenProbe.cpp, gated by INCURSION_ROUTE_UNSEEN
# fact: the player case's corridor memory (intact for the control, cleared for the candidate) -- probe sets m->At(x,y).Memory directly, not the seed
# fact: the player's RunTo answer (accepted with memory intact, refused with memory cleared) -- invariant, not seed-read: fixed by Map::ShortestPath's memonly default; the probe reads Player::RunTo's return and the RunToProbe lines

set -uo pipefail
# ---------------------------------------------------------------------------
# --prove-red (docs/VERIFICATION.md step 2), two mutations. Mutation 1 restores
# memonly=true at the SmartDirTo call -- the exact base-code state the fix
# removes -- and the four cases the fix repaired (hostile/1, companion/1,
# neutral/1, companion/2) must go red while the player case stays green.
# Mutation 2 sets the DEFAULT of memonly in inc/Map.h's ShortestPath declaration
# to false, so the player's own travel (RunTo, which takes the default) floods
# the real map rather than the player's memory: the player case must go red
# while the nine creature cases stay green. Each mutation is applied to its OWN
# SCRATCH copy of the tree, never the worktree's own src/: the copy is rebuilt
# with its own build_macos.sh, and THIS check is run inside the copy (via
# INCURSION_ROUTE_ROOT) so it uses the copy's binary and fixtures. The
# worktree's src/ and binary are never touched.
#
# Usage: tools/check_route_unseen.sh [--prove-red] [seed]
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--prove-red" ]; then
    WT="$(cd "$(dirname "$0")/.." && pwd)"
    proof="$WT/logs/route-unseen-prove-red.$$"
    rm -rf "$proof"; mkdir -p "$proof" || { echo "INCONCLUSIVE: no scratch dir"; exit 2; }
    seed="${2:-3}"

    # Each mutation is applied to its OWN scratch copy of the tree (never the
    # worktree's own src/): the copy is rebuilt and this check is run inside it
    # (via INCURSION_ROUTE_ROOT) so it uses the copy's binary and fixtures.
    red=0
    for mut in smartdirto maph; do
        scratch="$proof/tree-$mut"
        rm -rf "$scratch"; mkdir -p "$scratch"
        echo
        if [ "$mut" = smartdirto ]; then
            echo "--- mutation 1: restore memonly=true at Monster::SmartDirTo ---"
        else
            echo "--- mutation 2: default memonly=false in inc/Map.h's ShortestPath ---"
        fi
        echo "  copying the tree to $scratch (excluding logs/, mod/, objects, .git)"
        rsync -a \
            --exclude='logs/' --exclude='mod/' --exclude='.git/' \
            --exclude='*.o' --exclude='incursion' --exclude='incursion-headless' \
            --exclude='build/' \
            "$WT/" "$scratch/" || { echo "INCONCLUSIVE: rsync of the tree failed"; exit 2; }
        mkdir -p "$scratch/logs"   # headless writes run dirs under logs/

        echo "  mutating the scratch copy"
        scratch="$scratch" mut="$mut" python3 - <<'PY' || { echo "INCONCLUSIVE: mutation did not apply cleanly"; exit 2; }
import os
root, mut = os.environ["scratch"], os.environ["mut"]
if mut == "smartdirto":
    p = os.path.join(root, "src", "Monster.cpp")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    old = "m->ShortestPath((uint8)x,(uint8)y,(uint8)tx,(uint8)ty,this,0,thePath,NULL,false)"
    new = "m->ShortestPath((uint8)x,(uint8)y,(uint8)tx,(uint8)ty,this,0,thePath,NULL,true) /* MUTATED by --prove-red */"
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"mutation text appears {n} times, expected 1")
    open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new))
    print("  mutated: SmartDirTo now passes memonly=true (the base-code flood)")
else:
    p = os.path.join(root, "inc", "Map.h")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    old = "                        bool memonly = true);"
    new = "                        bool memonly = false); /* MUTATED by --prove-red */"
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"mutation text appears {n} times, expected 1")
    open(p, "w", encoding="utf-8", errors="surrogateescape").write(s.replace(old, new))
    print("  mutated: ShortestPath's default memonly is now false (player travel")
    print("           would route over the real map, not the player's memory)")
PY

        echo "  building the scratch copy"
        # The scratch build is PRIVATE: a non-default OUT= with a non-empty
        # EXTRA_CXXFLAGS= is the pair that makes build_macos.sh skip its rewrite
        # of the shared mod/Incursion.Mod (build_macos.sh:375), so this build
        # never touches the shared module even though it runs from the scratch
        # tree. The binary keeps the default name incursion-headless, which is
        # what the inner check below looks for.
        ( cd "$scratch" && OUT=incursion-headless EXTRA_CXXFLAGS=-DROUTE_UNSEEN_PROVE_RED \
            BACKEND=posix ./build_macos.sh ) > "$proof/build-$mut.log" 2>&1 \
            || { tail -20 "$proof/build-$mut.log" | sed 's/^/      /'
                 echo "INCONCLUSIVE: the mutated scratch build failed; log in $proof/build-$mut.log"; exit 2; }

        echo "  running this check inside the scratch copy (seed $seed)"
        INCURSION_ROUTE_ROOT="$scratch" "$scratch/tools/check_route_unseen.sh" "$seed" \
            > "$proof/red-$mut.log" 2>&1
        inner=$?
        grep -E '^(mode=|INCONCLUSIVE)' "$proof/red-$mut.log" | sed 's/^/  | /'

        redcases="$(grep ' FAIL ' "$proof/red-$mut.log" | grep -oE 'mode=[a-z]+ opt=[0-9]+' | paste -sd' ' -)"
        echo "  scratch check exit=$inner, FAIL cases: ${redcases:-none}"
        # Keep the specimen run dirs, drop the heavy scratch build tree.
        mv "$scratch/logs/runs" "$proof/runs-$mut" 2>/dev/null
        rm -rf "$scratch"
        if [ "$inner" -ne 1 ]; then
            echo "FAIL: mutation $mut: the scratch check exited $inner, not 1."
            echo "      It is measuring nothing. proof in $proof"
            exit 2
        fi
        if [ "$mut" = smartdirto ]; then
            want="mode=hostile opt=1 mode=companion opt=1 mode=companion opt=2 mode=neutral opt=1"
            if [ "$redcases" != "$want" ]; then
                echo "FAIL: mutation 1: the FAIL cases are not exactly the ones the fix repaired."
                echo "      want: $want"
                echo "      got:  ${redcases:-none}"
                echo "      proof in $proof"
                exit 2
            fi
            if grep -q 'mode=player' <<< "$redcases"; then
                echo "FAIL: mutation 1: the player case failed, but that mutation only"
                echo "      touches Monster::SmartDirTo; the player case must stay green."
                exit 2
            fi
            echo "PROVED RED (mutation 1): with memonly restored to true at the"
            echo "            SmartDirTo call, the scratch copy exits 1 and the same"
            echo "            four creature cases fail (hostile/1, companion/1,"
            echo "            neutral/1, companion/2); the player case stays green."
            echo "            The worktree's src/ was never touched. Proof in $proof"
        else
            if ! grep -q 'mode=player' <<< "$redcases"; then
                echo "FAIL: mutation 2: with the ShortestPath default memonly=false,"
                echo "      the player case did NOT fail, so the check does not measure"
                echo "      the fix it claims to. FAIL cases: ${redcases:-none}"
                echo "      proof in $proof"
                exit 2
            fi
            if [ "$redcases" != "mode=player opt=1" ]; then
                echo "FAIL: mutation 2: the only FAIL case must be the player case;"
                echo "      got: ${redcases:-none}. proof in $proof"
                exit 2
            fi
            echo "PROVED RED (mutation 2): with ShortestPath's default memonly set to"
            echo "            false, player travel routes over unseen squares, and the"
            echo "            scratch player case FAILs while the nine creature cases"
            echo "            stay green. The worktree's src/ was never touched."
            echo "            Proof in $proof"
        fi
        red=$((red + 1))
    done
    echo
    echo "PROVED RED for both mutations ($red of 2): each scratch copy exits 1 with"
    echo "            its own FAIL cases, and the worktree's src/ was never touched."
    exit 0
fi

# INCURSION_ROUTE_ROOT lets --prove-red run this same check against a SCRATCH
# copy of the tree (its own src/ and its own rebuilt binary), never the
# worktree's own src/. The scratch copy carries its own tools/ and fixtures.
ROOT="${INCURSION_ROUTE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT"
SEED="${1:-3}"
[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
CHAR=tools/fixtures/chars/kobold-rogue-seed1.sav
OPTS=tools/fixtures/options-2026-08-22.dat
[ -f "$CHAR" ] && [ -f "$OPTS" ] || { echo "INCONCLUSIVE: fixture missing"; exit 2; }

stamp="$$"
mkdir -p logs/runs   # the .out redirect needs it on a fresh tree (e.g. --prove-red scratch)
worst=0
for mode in hostile companion neutral; do
    for opt in 0 1 2; do
        dir="logs/runs/route-unseen-$stamp-$mode-$opt"
        rm -rf "$dir"
        INCURSION_ROUTE_UNSEEN="$mode" INCURSION_ROUTE_OPT="$opt" INCURSION_ROUTE_TURNS=30 \
        INCURSION_RUN_DIR="$dir" INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CHAR" \
            tools/headless.sh tools/keys/route-unseen.keys "$SEED" >"$dir.out" 2>&1
        python3 - "$mode" "$opt" "$dir" <<'PY'
import os, re, sys
mode, opt, run = sys.argv[1], sys.argv[2], sys.argv[3]
log = os.path.join(run, "logs", "routeunseen.log")
def bail(why):
    print("mode=%s opt=%s INCONCLUSIVE (%s) run=%s" % (mode, opt, why, run)); sys.exit(2)
if not os.path.isfile(log):
    bail("no probe log: the overview map never opened or the session never ran")
lines = [l.rstrip("\n") for l in open(log, errors="replace")]
st = [l for l in lines if l.startswith("stage mode=")]
if not st:
    bail("staging failed: no stage line")
m = re.match(r"stage mode=(\w+) mon=\d+,\d+ player=(\d+),(\d+) tgt=(\d+),(\d+) "
             r"opt=(\d+) hostile=(\d+) leader=(\d+) lof=(\d+) turns=(\d+)", st[0])
if not m or m.group(1) != mode:
    bail("scene is not the one designed: " + st[0])
px, py = int(m.group(2)), int(m.group(3))
if int(m.group(6)) != int(opt):
    bail("option read as %s, not %s: %s" % (m.group(6), opt, st[0]))
real = "%d,%d" % (px, py)
routes = [l for l in lines if l.startswith("route ")]
if not routes:
    bail("no per-turn distance lines")
def dist(line):
    return int(re.search(r"\bdist=(\d+)", line).group(1))
first_d, last_d = dist(routes[0]), dist(routes[-1])
GOOD, BAD = {"straight", "lof", "spok"}, {"spblocked", "failedrecent"}
counts = {}
n_real = 0
bad = []
for l in lines:
    if not l.startswith("smartdir "):
        continue
    mm = re.match(r"smartdir turn=\d+ at=\d+,\d+ tgt=(\d+,\d+) opt=\d+ pet=\d+ "
                  r"branch=(\w+) ret=-?\d+", l)
    if not mm or mm.group(1) != real:
        continue
    b = mm.group(2)
    counts[b] = counts.get(b, 0) + 1
    n_real += 1
    if b in BAD:
        bad.append(b)
if n_real == 0:
    bail("no SmartDirTo request to the real target %s" % real)
nonzero = {b: c for b, c in counts.items() if c}
bc = " ".join("%s=%d" % (b, nonzero[b]) for b in sorted(nonzero)) or "none"
crit1 = not bad
crit2 = last_d < first_d
fixed = crit1 and crit2
offend = ",".join("%s=%d" % (b, bad.count(b)) for b in sorted(set(bad))) or "none"
print("mode=%s opt=%s %s branch real-target: %s first-dist=%d last-dist=%d "
      "requests=%d offending=%s run=%s" % (
      mode, opt, "PASS" if fixed else "FAIL", bc, first_d, last_d, n_real,
      offend, run))
sys.exit(0 if fixed else 1)
PY
        rc=$?
        if [ "$rc" -eq 2 ]; then worst=2; elif [ "$rc" -eq 1 ] && [ "$worst" -ne 2 ]; then worst=1; fi
        rm -f "$dir.out"
    done
done

# Tenth case: mode=player. Same staged sealed L corridor, no watched creature;
# the PLAYER asks to travel to the far end with Player::RunTo (src/Creature.cpp)
# -- the function the overview map's [R] Run to Point calls -- over squares the
# player has never seen. RunTo routes with Map::ShortestPath's default
# memonly=true, so with the corridor's memory cleared it must refuse; the case's
# own control -- the same request with the corridor's memory intact -- must be
# accepted (the run reaches/starts moving). Both halves are observed in one run.
# A control that is not accepted, or a missing half, exits 2: a refusal that
# cannot be told apart from another failure says nothing.
dir="logs/runs/route-unseen-$stamp-player"
rm -rf "$dir"
INCURSION_ROUTE_UNSEEN=player INCURSION_ROUTE_OPT=1 INCURSION_ROUTE_TURNS=30 \
INCURSION_RUNTO_PROBE=1 \
INCURSION_RUN_DIR="$dir" INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CHAR" \
    tools/headless.sh tools/keys/route-unseen.keys "$SEED" >"$dir.out" 2>&1
python3 - "$dir" <<'PY'
import os, re, sys
run = sys.argv[1]
log = os.path.join(run, "logs", "routeunseen.log")
def bail(why):
    print("mode=player opt=1 INCONCLUSIVE (%s) run=%s" % (why, run)); sys.exit(2)
if not os.path.isfile(log):
    bail("no probe log: the overview map never opened or the session never ran")
lines = [l.rstrip("\n") for l in open(log, errors="replace")]
st = [l for l in lines if l.startswith("stage mode=player ")]
if not st:
    bail("staging failed: no player stage line")
m = re.match(r"stage mode=player player=(\d+),(\d+) dest=(\d+),(\d+) opt=(\d+) turns=(\d+)", st[0])
if not m:
    bail("scene is not the one designed: " + st[0])
px, py, dx, dy = map(int, m.groups()[:4])
seen = [l for l in lines if l.startswith("player runto phase=seen ")]
unseen = [l for l in lines if l.startswith("player runto phase=unseen ")]
if not seen or not unseen:
    bail("the probe did not make both RunTo requests")
def accepted(line):
    return re.search(r"\baccepted=(\d)", line).group(1) == "1"
ctl = accepted(seen[0])
cand = accepted(unseen[0])
# Corroborate with Player::RunTo's own logs (RunToProbe): both outcomes must
# have come from the real function, not from a staging shortcut. The control's
# 'runto accepted' is required always; a 'runto refused' is required only when
# the candidate is expected to be refused (it is the fault's absence that the
# candidate being accepted reports).
rlog = os.path.join(run, "logs", "runtoprobe.log")
if not os.path.isfile(rlog):
    bail("no RunToProbe log: Player::RunTo did not log")
rl = [l.rstrip("\n") for l in open(rlog, errors="replace")]
n_from = len([l for l in rl if l.startswith("runto from=")])
if "runto accepted" not in rl:
    bail("the control's RunToProbe 'runto accepted' line is absent")
if n_from < 2:
    bail("only %d 'runto from' line(s): the probe did not make two RunTo calls" % n_from)
if not cand and "runto refused" not in rl:
    bail("the candidate's RunToProbe 'runto refused' line is absent")
if not ctl:
    bail("control (memory intact) was not accepted, so a refusal cannot be told apart from another failure")
fixed = not cand
print("mode=player opt=1 %s RunTo control(memory intact)=accepted unseen(memory cleared)=%s "
      "from=%d,%d to=%d,%d run=%s" % (
      "PASS" if fixed else "FAIL", "accepted" if cand else "refused",
      px, py, dx, dy, run))
sys.exit(0 if fixed else 1)
PY
rc=$?
if [ "$rc" -eq 2 ]; then worst=2; elif [ "$rc" -eq 1 ] && [ "$worst" -ne 2 ]; then worst=1; fi
rm -f "$dir.out"

exit "$worst"
