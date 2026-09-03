#!/bin/bash
# Does light PASS THROUGH a cloud of fog, dimmed, rather than stopping at it?
#
# Fog has two ways to be wrong and they look alike on a map, so this check
# separates them. Until inc-qh0w's Reaches() fix, fog BLOCKED light: the light
# map asked the eye's question, LineOfVisualSight, which refuses any ray that
# crosses an obscured cell, so the transmittance walk never ran and every cell
# behind a cloud read dark. A cell that is merely dimmed also reads lower. The
# check therefore demands BOTH that the measured cell falls AND that it stays
# lit. A dark reading fails, exactly as an unchanged one does.
#
#   tools/keys/light-fog.keys   one wall torch, then a cloud rolled across the
#                               cells between that torch and the measured cell
#   tools/keys/light-fogterrain.keys
#                               the same geometry with placed fog terrain
#
# It finds a clear block and the final fogged block in ONE session, not two
# sessions as tools/check_light_filter.sh must for ice. Both blocks then share
# a map, a player position and a source list, so no monster can move between
# them and explain the difference away. The source lines are compared as the
# control, ignoring each source's footprint size, which fog can shrink.
#
# On seed 1 chargen-mage.keys lands the mage at (82,13):
#   (79,13) the wall torch   (80,13) the crossed cell   (81,13) measured
#
# Usage: tools/check_light_fog.sh   exit 0 pass, 1 fail, 2 inconclusive
#
# Needs the headless build: BACKEND=posix ./build_macos.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FOG_X=80; MEASURE_X=81; ROW=13

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

check_subject() {
    subject="$1"
    label="$2"

out="$(INCURSION_LIGHT_PROBE=1 tools/headless.sh "$subject" 1 2>&1)"
run="$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
if printf '%s\n' "$out" | grep -q "NO GAMEPLAY"; then
    echo "INCONCLUSIVE: the subject never entered a map. Run: $run"
    exit 2
fi
log="$run/logs/light.log"
[ -f "$log" ] || {
    echo "INCONCLUSIVE: no light.log in $run -- the probe switch did not take"
    exit 2
}

python3 - "$log" "$ROW" "$FOG_X" "$MEASURE_X" "$run" "$label" <<'PY'
import sys

log, row, fog_x, measure_x, run, label = (
    sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5],
    sys.argv[6])

def parse(block):
    """A dump block as (sources, light grid, filter grid)."""
    lines = block.split("\n")
    h = int(lines[0].split("map=")[1].split()[1])
    i = 1
    srcs = []
    while lines[i].startswith("S "):
        srcs.append(lines[i])
        i += 1
    if lines[i + h] != "FILTER":
        return None
    return srcs, lines[i:i + h], lines[i + h + 1:i + h + 1 + h]

blocks = open(log).read().split("LIGHT ")[1:]
if len(blocks) < 2:
    sys.stderr.write("INCONCLUSIVE: %s holds %d dump block(s), not two. The probe\n"
                     "  writes a block only when something it watches changes.\n"
                     % (log, len(blocks)))
    sys.exit(2)
parsed = [parse(block) for block in blocks]
after = parsed[-1]
if after is None:
    sys.stderr.write("INCONCLUSIVE: a dump block in %s has no FILTER grid\n" % log)
    sys.exit(2)

def level(ch):
    """Brightness as a number: -1 dark, 0 lit but faint, 1-9 brighter."""
    return int(ch) if ch.isdigit() else -1

def geometry(srcs):
    """A source line without its footprint size, which fog legitimately shrinks."""
    return [" ".join(s.split()[:8]) for s in srcs]

before = next((block for block in reversed(parsed[:-1])
               if block is not None
               and block[2][row][fog_x] == "-"
               and geometry(block[0]) == geometry(after[0])), None)
if before is None:
    sys.stderr.write("INCONCLUSIVE: %s has no clear block with the final source "
                     "geometry\n" % log)
    sys.exit(2)

fail = []
if geometry(before[0]) != geometry(after[0]):
    fail.append("the two blocks do not share a source list, so the fog is not the\n"
                "      only difference between them and nothing here can be concluded")
if before[2][row][fog_x] != "-":
    fail.append("the before block already marks (%d,%d) as '%s'; it must be clear"
                % (fog_x, row, before[2][row][fog_x]))
if after[2][row][fog_x] != "f":
    fail.append("the after block marks (%d,%d) as '%s', not 'f' -- the fog never\n"
                "      landed on the cell the subject aimed it at"
                % (fog_x, row, after[2][row][fog_x]))

lit_before = level(before[1][row][measure_x])
lit_after = level(after[1][row][measure_x])
if lit_before < 1:
    fail.append("(%d,%d) reads '%s' before the fog; it must be lit for the\n"
                "      comparison to mean anything"
                % (measure_x, row, before[1][row][measure_x]))
elif lit_after < 0:
    fail.append("(%d,%d) goes DARK behind the fog, from '%s' to '%s'. The fog is\n"
                "      stopping the light, not dimming it: the light map is asking\n"
                "      whether an EYE could see through, not whether light passes."
                % (measure_x, row, before[1][row][measure_x], after[1][row][measure_x]))
elif lit_after >= lit_before:
    fail.append("(%d,%d) reads '%s' behind the fog and '%s' in the clear. Light\n"
                "      crosses the cloud undimmed."
                % (measure_x, row, after[1][row][measure_x], before[1][row][measure_x]))

if fail:
    for f in fail:
        print("FAIL: %s" % f)
    print("run: %s" % run)
    sys.exit(1)
print("light through %s: (%d,%d) reads '%s' in the clear and '%s' behind one "
      "cell of fog" % (label, measure_x, row,
                       before[1][row][measure_x], after[1][row][measure_x]))
PY
}

check_subject tools/keys/light-fog.keys "cast fog" || exit $?
check_subject tools/keys/light-fogterrain.keys "fog terrain" || exit $?
