#!/bin/bash
# gate: live
# Reproduction for bd inc-vmpk: the overview map's Run to Point ([R]) routes
# the character into a hazard with no warning.
#
# Player::RunTo (src/Creature.cpp) tries Map::ShortestPath with DF_ALL_SAFE,
# then DF_IGNORE_TRAPS, then DF_IGNORE_TRAPS|DF_IGNORE_TERRAIN, and takes the
# first route. It never asks. Three cases, each a sealed one-square-wide
# corridor ten squares long (src/RunToProbe.cpp builds it, on the first opening
# of the overview map, when INCURSION_RUNTO_STAGE is set), so the hazard on the
# fifth square is on the ONLY route to the far end:
#
#   T  a found, armed trap (howling trap)
#   D  deep water, which Map::RunOver rejects without DF_IGNORE_TERRAIN
#   S  a corridor region whose Size is below the character's
#      (the stage sets the Winding Corridor region's Size to SZ_MINISCULE)
#
#   M  not a Run to Point case: a Large companion (an ogre) follows the character
#      by Monster::SmartDirTo, which plans with Map::ShortestPath, with the
#      option "Monsters Use Djikstra" at YES. The short route to the character
#      crosses a Medium region ("Twisty Little Passage") that the ogre may not
#      enter (src/Move.cpp:799); a longer detour of Large-region squares exists.
#      The character stands still (tools/keys/runto-monster.keys). FAULT PRESENT
#      = the ogre never gets past the first square of the detour (it stays at the
#      region's entrance or oscillates there); FIXED = it advances along the
#      detour. A companion, not a hostile: SmartDirTo for a hostile skips a
#      target it cannot see (src/Monster.cpp, Movement, "ts.t[i].vis == 0"), and
#      the walls hide the character.
#
# The cases T, D and S load tools/fixtures/chars/kobold-rogue-seed1.sav, opens the
# overview map, moves the cursor to the far end and presses [R]; the next key
# is [n], the answer to the fixed build's prompt.
#
# FIXED, per case, is read from the probe log (logs/runtoprobe.log):
#   T, D  a yes/no prompt "No safe path found: look for dangerous paths?"
#         opens, and the run never takes a step
#   S     the run never takes a step
# Anything else is FAULT PRESENT. A "step from" line is one Player step of the
# run (src/Creature.cpp, EV_MOVE with Mag >= 50).
#
# Exit 0 all cases FIXED, 1 any FAULT PRESENT, 2 a case could not be
# established (no build, stage failed, [R] never reached the far end, no
# gameplay). 2 wins over 1: a case that did not run says nothing.
#
# Case M uses the same settings file: its byte 114 (OPT_MON_DJIKSTRA) is already 1
# in options-2026-08-22.dat, and the stage logs the value the game read.
#
# Usage: tools/check_runto_hazards.sh [seed]     (needs BACKEND=posix build)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
worst=0
for c in T D S M; do
    dir="logs/runs/runto-hazards-$stamp-$c"
    keys=tools/keys/runto-hazard.keys
    [ "$c" = M ] && keys=tools/keys/runto-monster.keys
    rm -rf "$dir"
    INCURSION_RUNTO_PROBE=1 INCURSION_RUNTO_STAGE=$c INCURSION_RUN_DIR="$dir" \
    INCURSION_OPTIONS="$OPTS" INCURSION_LOAD="$CHAR" \
        tools/headless.sh "$keys" "$SEED" >"$dir.out" 2>&1
    python3 - "$c" "$dir" <<'PY'
import glob, os, re, sys
case, run = sys.argv[1], sys.argv[2]
log = os.path.join(run, "logs", "runtoprobe.log")
def bail(why):
    print("CASE %s: INCONCLUSIVE (%s) run=%s" % (case, why, run)); sys.exit(2)
if not os.path.isfile(log):
    bail("no probe log: the overview map never opened or the session never ran")
lines = [l.rstrip("\n") for l in open(log, errors="replace")]
stage = [l for l in lines if l.startswith("stage ")]
st = [l for l in stage if l.startswith("stage mode=")]
if not st:
    bail("staging failed: " + "; ".join(l for l in stage if "failed" in l) if stage else "no stage line")
if case == "M":
    mm = re.match(r"stage mode=M player=(\d+),(\d+) entrance=(\d+),(\d+) mon=(\d+),(\d+) "
                  r"monsize=(\d+) medsize=(\d+) lof=(\d+) opt=(\d+) leader=(\d+)", st[0])
    if not mm:
        bail("scene is not the one designed: " + st[0])
    px, py, ex, ey, mx, my, msz, rsz, lof, opt, ldr = map(int, mm.groups())
    if (mx, my) != (ex, ey): bail("monster is not at the entrance: " + st[0])
    if msz <= rsz: bail("monster size %d is not above region size %d" % (msz, rsz))
    if lof: bail("monster has a line of fire to the character at the start")
    if opt != 1: bail("OPT_MON_DJIKSTRA read as %d, not 1" % opt)
    if not ldr: bail("monster does not follow the character")
    pos = []
    for l in lines:
        q = re.match(r"mon at=(\d+),(\d+) tgt=(\d+),(\d+) turn=(\d+) opt=(\d+) pet=1", l)
        if q:
            if int(q.group(6)) != 1: bail("option changed during the run")
            pos.append((int(q.group(1)), int(q.group(2))))
    if len(pos) < 20:
        bail("the monster planned only %d times; it never followed" % len(pos))
    plans = [l for l in lines if l.startswith("plan ")]
    visited = sorted(set(pos))
    # The detour's first square is (ex, ey+1); FIXED needs the monster past it.
    far = max(p[1] for p in pos if p[0] >= ex - 1) - ey
    back = [l for l in plans if ("at=%d,%d " % (ex, ey)) in l and ("next=%d,%d" % (ex, ey - 1)) in l]
    fixed = far >= 2
    print("CASE M: %s" % ("FIXED" if fixed else "FAULT PRESENT"))
    print("  evidence: option-read=%d, monster-size=%d region-size=%d, line-of-fire-at-start=no, "
          "decisions=%d, squares-visited=%s, farthest-detour-step=%d (FIXED needs 2+), "
          "plans-from-entrance-into-region=%d, run=%s" % (
          opt, msz, rsz, len(pos), " ".join("%d,%d" % p for p in visited), far, len(back), run))
    sys.exit(0 if fixed else 1)
m = re.match(r"stage mode=(\w) player=(\d+),(\d+) hazard=(\d+),(\d+) dest=(\d+),(\d+)", st[0])
if not m or m.group(1) != case:
    bail("scene is not the one designed: " + st[0])
start = (int(m.group(2)), int(m.group(3)))
dest = "%s,%s" % (m.group(6), m.group(7))
rs = [l for l in lines if l.startswith("R target=")]
if not rs or rs[0] != "R target=" + dest:
    bail("[R] did not reach the far end %s: %s" % (dest, rs[:1]))
steps = [l for l in lines if l.startswith("step from=")]
nows = [l for l in lines if l.startswith("step now=")]
prompts = [l.split("msg=", 1)[1] for l in lines if l.startswith("yn ")]
route = "found" if "runto accepted" in lines else "refused"
entered = []
for l in nows:
    mm = re.match(r"step now=(\d+),(\d+)", l)
    pos = (int(mm.group(1)), int(mm.group(2)))
    if pos != start and (not entered or entered[-1] != pos):
        entered.append(pos)
last = nows[-1].split()[-1] if nows else "r=?"
shots = sorted(glob.glob(os.path.join(run, "logs", "screens", "*after-run*")))
text = open(shots[0], errors="replace").read() if shots else ""
msg = "too large to enter" if "too large to enter" in text else "none"
if not shots:
    bail("no after-run screen: no gameplay")
nosafe = any(p.startswith("No safe path found") for p in prompts)
ran = len(steps) > 0
if case in "TD":
    fixed = nosafe and not ran
else:
    fixed = not ran
ev = ("evidence: route-search=%s, run-started=%s, squares-entered=%s, "
      "prompts=%s, no-safe-path-prompt=%s, screen-message=%s, run=%s" % (
      route, "yes" if ran else "no",
      " ".join("%d,%d" % p for p in entered) or "none",
      "; ".join(prompts) or "none", "yes" if nosafe else "no", msg, run))
print("CASE %s: %s" % (case, "FIXED" if fixed else "FAULT PRESENT"))
print("  " + ev)
sys.exit(0 if fixed else 1)
PY
    rc=$?
    if [ "$rc" -eq 2 ]; then worst=2; elif [ "$rc" -eq 1 ] && [ "$worst" -ne 2 ]; then worst=1; fi
    rm -f "$dir.out"
done

# Case E: after the character says yes to "No safe path found" and yes to the
# movement's own confirm, a hazard that then HAS AN EFFECT on him must stop the
# run at once, with no question. A hazard that has no effect must not stop it.
# Same corridor, hazard on square 5, target at the far end, every prompt
# answered y (tools/keys/runto-effect.keys). Outcomes are forced, not hoped for:
#   E1  howling trap (1d6 sonic damage); INCURSION_FORCE_SAVE_ROLL=1 makes the
#       avoid save roll a natural 1, which always fails (Creature::SavingThrow)
#   E2  slow trap (a SLOW stati, no hit-point damage); same forced save
#   E3  bed of spikes (1d8 piercing on a passed Escape Artist check);
#       INCURSION_RUNTO_SKILL_ROLL=20 forces the d20 of every skill check
#   E0  control: the howling trap with the save forced to a natural 20, so the
#       trap is avoided and the run MUST reach the far end
# FIXED (E1-E3): after the first effect the run takes no further step and no
# "Do you want to stop" prompt opens. The effect is the earliest of: the message
# "You fall victim to", a "Do you want to stop" prompt, "You stop running", or a
# drop in hit points seen after a step. E0 prints CONTROL ok or CONTROL broken;
# broken counts as FAULT.
for e in E1 E2 E3 E0; do
    dir="logs/runs/runto-hazards-$stamp-$e"
    rm -rf "$dir"
    case "$e" in
        E1) xenv=(INCURSION_RUNTO_STAGE=T INCURSION_FORCE_SAVE_ROLL=1) ;;
        E2) xenv=(INCURSION_RUNTO_STAGE=T "INCURSION_RUNTO_TRAP=slow trap" INCURSION_FORCE_SAVE_ROLL=1) ;;
        E3) xenv=(INCURSION_RUNTO_STAGE=D "INCURSION_RUNTO_TERRAIN=bed of spikes" INCURSION_RUNTO_SKILL_ROLL=20) ;;
        E0) xenv=(INCURSION_RUNTO_STAGE=T INCURSION_FORCE_SAVE_ROLL=20) ;;
    esac
    env INCURSION_RUNTO_PROBE=1 INCURSION_RUN_DIR="$dir" INCURSION_OPTIONS="$OPTS" \
        INCURSION_LOAD="$CHAR" "${xenv[@]}" \
        tools/headless.sh tools/keys/runto-effect.keys "$SEED" >"$dir.out" 2>&1
    python3 -I - "$e" "$dir" <<'PY'
import os, re, sys
case, run = sys.argv[1], sys.argv[2]
log = os.path.join(run, "logs", "runtoprobe.log")
def bail(why):
    print("CASE %s: INCONCLUSIVE (%s) run=%s" % (case, why, run)); sys.exit(2)
if not os.path.isfile(log):
    bail("no probe log")
lines = [l.rstrip("\n") for l in open(log, errors="replace")]
st = [l for l in lines if l.startswith("stage mode=")]
if not st:
    bail("staging failed")
dest = re.search(r"dest=(\d+,\d+)", st[0]).group(1)
hz = re.search(r"hazard=(\d+,\d+)", st[0]).group(1)
rs = [l for l in lines if l.startswith("R target=")]
if not rs or rs[0] != "R target=" + dest:
    bail("[R] did not reach the far end")
r0 = lines.index(rs[0])
body = lines[r0:]
if not any(l.startswith("yn ") and "No safe path found" in l for l in body):
    bail("the No safe path prompt never opened")
# events after [R], in order
hp = None; ev = None; evtxt = None
for k, l in enumerate(body):
    q = re.match(r"step now=(\d+),(\d+) r=(\d+) hp=(\d+) acting=(\d)", l)
    if q:
        h = int(q.group(4))
        if hp is not None and h < hp and ev is None:
            ev, evtxt = k, "hit points %d -> %d" % (hp, h)
        hp = h
    if ev is None and (l.startswith("msg You fall victim to") or "Do you want to stop" in l
                       or l.startswith("msg You stop running")):
        ev, evtxt = k, l.split(" ", 1)[1] if l.startswith("msg ") else l
reached = [l for l in body if l.startswith("step now=%s," % dest.split(",")[0])
           and l.startswith("step now=%s r=" % dest)]
if case == "E0":
    avoided = any(l.startswith("msg You avoid the effects") for l in body)
    if not avoided:
        bail("the trap was not avoided, so the control did not run as designed")
    ok = bool(reached) and not any("Do you want to stop" in l for l in body)
    print("CASE E0: CONTROL %s" % ("ok" if ok else "broken"))
    print("  evidence: avoid-message=yes, reached-far-end=%s, stop-prompt=%s, run=%s" % (
          "yes" if reached else "no",
          "yes" if any("Do you want to stop" in l for l in body) else "no", run))
    sys.exit(0 if ok else 1)
if ev is None:
    bail("no effect on the character was seen: the run never reached the hazard's effect")
hurt = [l for l in body if re.match(r"step now=.* hp=", l)]
hps = [int(re.search(r"hp=(\d+)", l).group(1)) for l in hurt]
if case in ("E1", "E3") and not (hps and min(hps) < hps[0]):
    bail("hit points never dropped, so no damage effect happened")
if case == "E2" and hps and min(hps) < hps[0]:
    bail("hit points dropped; the effect was meant to be a non-damage one")
after = body[ev + 1:]
more_steps = [l for l in after if l.startswith("step from=")]
prompts = [l.split("msg=", 1)[1] for l in after if l.startswith("yn ")]
stop_prompt = any("Do you want to stop" in p for p in prompts) or \
              (body[ev].startswith("yn ") and "Do you want to stop" in body[ev])
msgs = [l[4:] for l in body if l.startswith("msg ") and l[4:].strip()
        and "Hit:" not in l and not l.startswith("msg AutoHide")]
effmsgs = [m for m in msgs if re.search(r"victim|exposed|stop running|pierc|damage|slow", m, re.I)]
fixed = not more_steps and not stop_prompt
print("CASE %s: %s" % (case, "FIXED" if fixed else "FAULT PRESENT"))
print("  evidence: effect=%s, effect-messages=%s, further-steps-after-effect=%d, "
      "prompts-after-effect=%s, stop-prompt=%s, run=%s" % (
      evtxt, " | ".join(effmsgs) or "none", len(more_steps),
      "; ".join(prompts) or "none", "yes" if stop_prompt else "no", run))
sys.exit(0 if fixed else 1)
PY
    rc=$?
    if [ "$rc" -eq 2 ]; then worst=2; elif [ "$rc" -eq 1 ] && [ "$worst" -ne 2 ]; then worst=1; fi
    rm -f "$dir.out"
done
exit "$worst"
