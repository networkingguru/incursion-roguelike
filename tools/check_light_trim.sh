#!/bin/bash
# inc-4mxm: the two display-only lighting trims, OPT_LIGHT_EXPLORED and
# OPT_LIGHT_BRIGHT.
#
# Links tools/light_trim_probe.cpp against the REAL src/Light.o from a
# completed headless build and asserts on the numbers it prints, so this
# measures the shipped arithmetic rather than a copy of it. No seeded session
# and no options fixture: both functions under test are pure, and a fixture
# would only add a way for the check to pass without measuring anything.
#
# The assertion that matters most is NORMAL IS THE OLD PICTURE: at the middle
# step both trims MUST reproduce, byte for byte, what the game drew before
# either option existed. The ten memory goldens below were taken from
# HEAD:src/Light.cpp built and run on 2026-09-10, BEFORE the options existed --
# they are not a snapshot of the new code agreeing with itself.
#
# Getting an old file TO the middle step is the other half, and it belongs to
# MigrateOptions rather than to this arithmetic; tools/check_options_migrate.sh
# checks that half.
#
# Exit 0 pass, 1 behavioural failure, 2 missing or incomplete measurement.
#
# Mutations confirmed RED here on 2026-09-10:
#   MemoryStep[Normal]  1.00f -> 1.01f  (Normal stops being the old picture)
#   GainStep[Normal]    1.00f -> 1.02f  (the same, for the gain)
#   StepIndex clamps, not falls back    (a corrupt option byte reads garbage)
#   the g<1 branch -> the g>1 curve     (dimming leaves a white cell pinned)
#   k -> g unconditionally              (brightening clips a maxed channel)
#   MemoryStep[Darkest] 0.20f -> 1.00f  (the explored option does nothing)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OBJ="${INCURSION_LIGHT_OBJ:-build/obj-incursion-headless/Light.o}"
[ -f "$OBJ" ] || {
    echo "INCONCLUSIVE: $OBJ is missing; run BACKEND=posix ./build_macos.sh"
    exit 2
}
[ "$OBJ" -nt src/Light.cpp ] || {
    echo "INCONCLUSIVE: $OBJ is older than src/Light.cpp; rebuild first"
    exit 2
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CXX="${CXX:-clang++}"
$CXX -std=c++17 -O2 -fpermissive -Wno-narrowing -w -DPOSIX_TERM \
     -Iinc -Ilib -Icompat -c tools/light_trim_probe.cpp -o "$WORK/probe.o" || {
    echo "INCONCLUSIVE: the probe did not compile"
    exit 2
}
# Light.o names a dozen engine symbols from LightRebuild and the Map helpers.
# None is reachable from the two pure functions under test, so they are left to
# resolve at load time rather than stubbed; entering one would abort.
$CXX -std=c++17 -Wl,-undefined,dynamic_lookup \
     -o "$WORK/probe" "$WORK/probe.o" "$OBJ" || {
    echo "INCONCLUSIVE: the probe did not link against $OBJ"
    exit 2
}

"$WORK/probe" > "$WORK/out.txt" || {
    echo "INCONCLUSIVE: the probe did not run to completion"
    exit 2
}

python3 - "$WORK/out.txt" <<'PYCODE'
import sys, collections

rows = [l.split() for l in open(sys.argv[1]).read().splitlines() if l.strip()]
if not rows:
    print("INCONCLUSIVE: the probe printed nothing")
    sys.exit(2)

gain, memory = {}, {}
for r in rows:
    if r[0] == "gain":
        gain[(r[1], int(r[2]))] = tuple(int(x) for x in r[3:6])
    elif r[0] == "memory":
        memory[(r[1], int(r[2]), int(r[3]))] = tuple(int(x) for x in r[4:7])

INPUT = {"black": (0,0,0), "white": (255,255,255), "orange": (255,160,60),
         "grey": (128,128,128), "dim": (20,12,6)}
# The scale runs darkest to brightest, as the menu reads it, so Normal is the
# middle step and NOT the zero byte. A file written before these options
# existed reads 0 -- Dimmest -- and MigrateOptions is what lifts it to Normal;
# tools/check_options_migrate.sh is the check for that half.
DIMMEST, DIMMER, NORMAL, BRIGHTER, BRIGHTEST = 0, 1, 2, 3, 4
OUT_OF_RANGE = [-1, -128, 5, 127]
COLOURS = sorted(INPUT)

# Guard against a probe that silently stopped measuring: every combination the
# assertions below index MUST be present, or this exits 2 rather than passing.
want_gain = len(COLOURS) * (5 + len(OUT_OF_RANGE))
want_mem  = len(COLOURS) * 2 * (5 + len(OUT_OF_RANGE))
if len(gain) != want_gain or len(memory) != want_mem:
    print("INCONCLUSIVE: probe emitted %d gain and %d memory rows, "
          "wanted %d and %d" % (len(gain), len(memory), want_gain, want_mem))
    sys.exit(2)

fails = []
def check(cond, msg):
    if not cond:
        fails.append(msg)

# --- 1. step 0 is the identity for the gain, exactly ------------------------
for name in COLOURS:
    check(gain[(name, NORMAL)] == INPUT[name],
          "gain %s at Normal returned %s, wanted the colour unchanged %s"
          % (name, gain[(name, NORMAL)], INPUT[name]))

# --- 2. a corrupt or foreign option byte falls back to Normal ---------------
for name in COLOURS:
    for s in OUT_OF_RANGE:
        check(gain[(name, s)] == INPUT[name],
              "gain %s at out-of-range step %d returned %s, wanted %s"
              % (name, s, gain[(name, s)], INPUT[name]))
    for f in (0, 1):
        for s in OUT_OF_RANGE:
            check(memory[(name, f, s)] == memory[(name, f, NORMAL)],
                  "memory %s floor %d at out-of-range step %d returned %s, "
                  "wanted the Normal value %s"
                  % (name, f, s, memory[(name, f, s)],
                     memory[(name, f, NORMAL)]))

# --- 3. the ten memory goldens, taken from HEAD before the option existed ---
GOLDEN = {
    ("black",  0): (20, 20, 20),  ("black",  1): (30, 30, 30),
    ("white",  0): (64, 64, 64),  ("white",  1): (94, 94, 94),
    ("orange", 0): (64, 63, 62),  ("orange", 1): (94, 93, 91),
    ("grey",   0): (43, 43, 43),  ("grey",   1): (63, 63, 63),
    ("dim",    0): (25, 24, 24),  ("dim",    1): (36, 36, 35),
}
for (name, f), want in GOLDEN.items():
    check(memory[(name, f, NORMAL)] == want,
          "memory %s floor %d at Normal returned %s, but the pre-option code "
          "returned %s; the frozen options fixtures all read step 0"
          % (name, f, memory[(name, f, NORMAL)], want))

# --- 4. black stays black, and a maxed channel never wraps ------------------
for s in [NORMAL, DIMMER, DIMMEST, BRIGHTER, BRIGHTEST]:
    check(gain[("black", s)] == (0, 0, 0),
          "gain black at step %d returned %s, wanted black" % (s, gain[("black", s)]))
    check(max(gain[("white", s)]) <= 255,
          "gain white at step %d returned %s, which left the byte range"
          % (s, gain[("white", s)]))
for s in (BRIGHTER, BRIGHTEST):
    check(gain[("white", s)] == (255, 255, 255),
          "gain white at step %d returned %s; brightening a fully bright cell "
          "must leave it alone, not clip or wrap it" % (s, gain[("white", s)]))

# --- 5. brightness is ordered: dimmest < dimmer < normal < brighter < ... ---
ORDER = [DIMMEST, DIMMER, NORMAL, BRIGHTER, BRIGHTEST]
for name in COLOURS:
    for a, b in zip(ORDER, ORDER[1:]):
        for i, ch in enumerate("rgb"):
            check(gain[(name, a)][i] <= gain[(name, b)][i],
                  "gain %s channel %s fell from %d at step %d to %d at step %d"
                  % (name, ch, gain[(name, a)][i], a, gain[(name, b)][i], b))
    for f in (0, 1):
        for a, b in zip(ORDER, ORDER[1:]):
            for i, ch in enumerate("rgb"):
                check(memory[(name, f, a)][i] <= memory[(name, f, b)][i],
                      "memory %s floor %d channel %s fell from %d at step %d "
                      "to %d at step %d" % (name, f, ch, memory[(name, f, a)][i],
                                            a, memory[(name, f, b)][i], b))

# --- 6. every step scales all three channels by ONE factor, so no step can
#        shift a cell's hue. This is the assertion that catches a gain written
#        as a plain multiply: at a bright step that clips the maxed channel and
#        drags a saturated colour toward white, which is exactly the washing
#        out the curve exists to prevent. It must hold in BOTH directions, so
#        it runs over every step, not just the dim ones.
for name in COLOURS:
    src = INPUT[name]
    if max(src) == 0:
        continue                      # black cannot show a hue shift
    for s in (DIMMER, DIMMEST, BRIGHTER, BRIGHTEST):
        out = gain[(name, s)]
        top = max(range(3), key=lambda i: src[i])   # least rounding error
        k = out[top] / float(src[top])
        for i, ch in enumerate("rgb"):
            want = round(src[i] * k)
            check(abs(out[i] - want) <= 1,
                  "gain %s at step %d returned %s; channel %s is %d but "
                  "scaling every channel by %.4f gives %d, so this step "
                  "shifted the hue" % (name, s, out, ch, out[i], k, want))

# --- 7. both options must actually move the picture -------------------------
# Without this the whole check passes on a build where the steps do nothing.
check(gain[("grey", DIMMEST)][0] < gain[("grey", NORMAL)][0],
      "gain grey at Dimmest is not darker than Normal; the option does nothing")
check(gain[("grey", BRIGHTEST)][0] > gain[("grey", NORMAL)][0],
      "gain grey at Brightest is not brighter than Normal; the option does nothing")
check(gain[("white", DIMMEST)][0] < gain[("white", NORMAL)][0],
      "gain white at Dimmest is not darker than Normal; dimming must reach a "
      "fully bright cell, which an up-only curve would leave pinned at 255")
for name in COLOURS:
    if name == "black":
        continue          # black has no brightness for either option to move
    for f in (0, 1):
        check(memory[(name, f, DIMMEST)][0] < memory[(name, f, NORMAL)][0],
              "memory %s floor %d at Dimmest is not darker than Normal; the "
              "explored option does nothing" % (name, f))
        check(memory[(name, f, BRIGHTEST)][0] > memory[(name, f, NORMAL)][0],
              "memory %s floor %d at Brightest is not brighter than Normal; "
              "the explored option does nothing" % (name, f))

if fails:
    for m in fails:
        print("FAIL: " + m)
    sys.exit(1)
print("PASS: %d gain rows and %d memory rows; Normal matches the pre-option "
      "code and both trims move the picture." % (len(gain), len(memory)))
PYCODE
exit $?
