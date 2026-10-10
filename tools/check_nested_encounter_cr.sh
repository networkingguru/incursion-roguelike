#!/bin/bash
# gate: live
# Does a dive whose level generation builds nested encounters reach the end
# with no empty-encounter assert? A nested encounter (Map::enGenPart) built
# its slot at the raw per-member budget CR, below the nested encounter's own
# minCR that Map::enChooseMID admitted it at; at that CR Stage 4 of
# Map::enGenerate skips every Part, so the slot builds nothing and an
# all-nested group comes out empty (ASSERT ... GetEncounterCreature(0)).
# Seed 33 hits that assert on the inc-u3dp tree before inc-upw.7; master hits
# it on no seed from 1 to 400, so this check goes red only on that tree or
# with the clamp in src/Encounter.cpp reverted. Options: tools/gates/Options.Dat.
#
# Usage: tools/check_nested_encounter_cr.sh   (0 pass, 1 fail, 2 cannot tell)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED=33

[ -x ./incursion-headless ] || {
    echo "FAIL: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

RUN_DIR="$ROOT/logs/nested-encounter-cr/seed-$SEED-$$"
rm -rf "$RUN_DIR"
export INCURSION_RUN_DIR="$RUN_DIR"

out="$(INCURSION_OPTIONS=tools/gates/Options.Dat \
       tools/headless.sh tools/keys/dive.keys "$SEED" 2>&1)" || true
run="$(echo "$out" | awk '/^run:/ {print $2}')"
[ -n "$run" ] && RUN_DIR="$run"

screens="$RUN_DIR/logs/screens"
errlog="$RUN_DIR/logs/errors.log"

# The game creates errors.log only when it logs an error, and this assert is
# one such error. If the string is there, the empty-encounter bug is live.
if [ -f "$errlog" ] && grep -q "GetEncounterCreature" "$errlog"; then
    echo "FAIL: the run logged the empty-encounter assert"
    echo "      (GetEncounterCreature) in $errlog"
    exit 1
fi

# A run that left no screen dumps proved nothing: the dive never started, or
# the key script rotted, and a check that cannot see MUST fail, not pass.
if [ ! -d "$screens" ] || ! ls "$screens"/* >/dev/null 2>&1; then
    echo "FAIL: the run left no screen dumps in $screens, so it measured"
    echo "      nothing. Run dir: $RUN_DIR"
    exit 2
fi

echo "PASS: seed $SEED finished with screen dumps and no empty-encounter"
echo "      assert in errors.log. Run dir: $RUN_DIR"
exit 0
