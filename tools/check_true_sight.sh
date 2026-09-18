#!/bin/bash
# gate: live
# TRUE_SIGHT must see through invisibility and through darkness, out to its
# own range, and stop doing anything beyond it. (bd inc-5bl3)
#
# THE DEFECT. `Perceives`'s invisibility test (src/Vision.cpp) and
# `Map::MarkAsSeen`'s darkness gate both asked only `HasStati(SEE_INVIS)`, so
# a TRUE_SIGHT stati (the True Seeing spell, a kuo-toa's racial sight, the
# 8th-level cleric domain power, the 7th-level prestige power) did nothing at
# all: an invisible creature stayed invisible and a dark square stayed dark to
# a caster who should see through both, out to 120 feet (12 squares at this
# codebase's 10-feet-per-square scale). Two independent fixes close it: an
# exemption in the invisibility test, and one in MarkAsSeen's darkness gate.
# `Creature::TrueSightRange()` (inc/Creature.h, src/Vision.cpp) computes the
# range: a stati's own Mag when positive, else TRUE_SIGHT_RANGE (12).
#
# THE ORACLE is INCURSION_TRUESIGHT_PROBE, which arms Creature::TrueSightProbe
# (src/Vision.cpp), run once at the top of Game::Play() on the live player. It
# grants TRUE_SIGHT, places one temporary invisible giant rat in turn at a lit
# square inside range, an unlit square inside range, a square outside range,
# and (with TRUE_SIGHT removed again) a control at the lit square -- and
# narrates each Perceives() result against expectation through Error(), one
# "TRUESIGHT_PROBE:" line per assertion, because errors.log is the channel
# under test -- the same pattern check_quiet_lookup.sh uses. It leaves the
# character exactly as it found it: every stati and every square it touches is
# restored before it returns.
#
# FIVE LINES, each "expected=<x> actual=<y>":
#   range          expected=12       -- TrueSightRange() itself
#   lit-inside     expected=visual   -- invisibility exemption, ordinary light
#   dark-inside    expected=visual   -- invisibility exemption AND the
#                                        darkness gate, both at once
#   outside-range  expected=hidden   -- true sight does nothing past its range
#   control        expected=hidden   -- with TRUE_SIGHT gone, invisibility
#                                        alone hides the same creature again
#
# A "TRUESIGHT_PROBE: INCONCLUSIVE -- <reason>" line (the probe could not
# construct a case: no open line to a test square, no room to place one
# outside range, or the light map still calls the forced-dark square lit)
# makes the whole run INCONCLUSIVE, never a pass or a fail -- it did not
# measure what it claims to.
#
# PROVED RED two ways (docs/VERIFICATION.md step 2), by hand, not by this
# script: reverting the invisibility exemption at the `t_HasStati_INVIS` test
# in `Perceives` turns "lit-inside" (and "dark-inside") red; reverting the new
# `else if (TrueRange && dist <= TrueRange)` branch in `MarkAsSeen` turns only
# "dark-inside" red, because a naturally LIT square already passes without it.
#
# Usage: tools/check_true_sight.sh [seed]   (0 pass, 1 fail, 2 inconclusive)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="${1:-3}"
KEYS="tools/keys/dive.keys"
OPTS="$ROOT/tools/fixtures/options-2026-08-22.dat"
BIN="incursion-headless"

[ -x "./$BIN" ] || {
    echo "INCONCLUSIVE: ./$BIN is not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}
[ -f "$OPTS" ] || { echo "INCONCLUSIVE: no settings file at $OPTS"; exit 2; }

RUN="$(mktemp -d "${TMPDIR:-/tmp}/incursion-truesight.XXXXXX")"
trap 'rm -rf "$RUN"' EXIT

INCURSION_TRUESIGHT_PROBE=1 INCURSION_RUN_DIR="$RUN/game" \
    INCURSION_OPTIONS="$OPTS" INCURSION_BIN="./$BIN" \
    tools/headless.sh "$KEYS" "$SEED" > "$RUN/out" 2>&1
STATUS=$?

LOG="$RUN/game/logs/errors.log"
[ -f "$LOG" ] || {
    echo "INCONCLUSIVE: the run logged nothing at all (exit $STATUS)."
    echo "The probe reports through Error(), so an empty log means it never ran."
    sed -n '/--- after the session ---/,$p' "$RUN/out"
    exit 2
}

# Drop the indented backtrace blocks headless.sh attaches to a first
# occurrence; they quote the message text and would be counted twice.
grep -v '^    ' "$LOG" | grep 'TRUESIGHT_PROBE' > "$RUN/lines"

if ! [ -s "$RUN/lines" ]; then
    echo "INCONCLUSIVE: the probe never ran. Is Creature::TrueSightProbe()"
    echo "still called from Game::Play(), and does this build contain it?"
    exit 2
fi

if grep -q 'TRUESIGHT_PROBE: INCONCLUSIVE' "$RUN/lines"; then
    echo "INCONCLUSIVE: the probe could not construct its case:"
    grep 'TRUESIGHT_PROBE: INCONCLUSIVE' "$RUN/lines" | sed 's/^/  /'
    exit 2
fi

# <name> <substring that names the line> <expected value>
ASSERTS="range:range expected=12 actual=:12
lit-inside:lit-inside expected=visual actual=:visual
dark-inside:dark-inside expected=visual actual=:visual
outside-range:outside-range expected=hidden actual=:hidden
control:control expected=hidden actual=:hidden"

MISSING=0
MISMATCH=0
while IFS=: read -r NAME PREFIX WANT; do
    LINE="$(grep -F "$PREFIX" "$RUN/lines" | head -1)"
    if [ -z "$LINE" ]; then
        echo "INCONCLUSIVE: the '$NAME' assertion's line never appeared."
        MISSING=1
        continue
    fi
    GOT="$(echo "$LINE" | sed -n 's/.*actual=\([a-z0-9]*\).*/\1/p')"
    if [ "$GOT" != "$WANT" ]; then
        echo "FAIL: $NAME -- wanted actual=$WANT, got actual=$GOT"
        echo "      $LINE"
        MISMATCH=1
    fi
done <<< "$ASSERTS"

echo
echo "--- what the probe logged ---"
cat "$RUN/lines"

if [ "$MISSING" -ne 0 ]; then
    exit 2
fi
if [ "$MISMATCH" -ne 0 ]; then
    exit 1
fi

echo
echo "PASS: seed $SEED -- TRUE_SIGHT sees through invisibility and through"
echo "      darkness out to its own range, and does neither beyond it."
exit 0
