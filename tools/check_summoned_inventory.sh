#!/bin/bash
# gate: live
# inc-yj4cz: summoned inventory deletion and stolen property regressions.
# fact: character and loaded world -- fixture orc-rogue-seed1-opt0822.sav
# fact: scene terrain -- probe builds floor squares (catalog: probe-built map)
# fact: monsters, gear, worn/property flags, inventory order, SUMMONED links --
#   explicit cause construction required by inc-yj4cz phase 1; read back before vanish
#   (VERIFICATION: once cause is known, rewrite to set up the cause directly).
# fact: theft saving throw -- INCURSION_FORCE_SAVE_ROLL=1 (natural 1 fails)
# fact: theft selection -- exactly one eligible item; random(1) has one outcome
# fact: vanish and item lifetime/ownership -- real RemoveStati(SUMMONED), registry handles
# fact: no AI or timed expiry before observations -- synchronous Game::Play probe
# fact: assertion text -- probe literals and measured numbers, no generated names
# No build. Each case gets a separate process and run directory. Cleanup only
# follows flushed measurements, before the dangling owner's deferred destruction.
set -uo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
base="$ROOT/logs/runs/$(date +%Y%m%d-%H%M%S)-$$-summoned-inventory"
mkdir -p "$base"
failed=0
for c in a b; do
    run="$base/$c"
    INCURSION_SUMMON_INV_PROBE="$c" INCURSION_FORCE_SAVE_ROLL=1 \
        INCURSION_RUN_DIR="$run" INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=tools/fixtures/chars/orc-rogue-seed1-opt0822.sav \
        tools/headless.sh tools/keys/summoned-inventory.keys 1 > "$base/$c-harness.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL case=$c harness_exit=$rc specimen=$base/$c-harness.log"
        failed=1
    fi
    python3 - "$run/logs/summoned-inventory.log" "$c" <<'PY' || failed=1
import pathlib, sys
p = pathlib.Path(sys.argv[1])
print(f'Specimen: {p}')
if not p.is_file():
    sys.exit('FAIL missing probe log')
lines = p.read_text().splitlines()
print('\n'.join(lines))
assertions = [s for s in lines if s.startswith(('PASS ', 'FAIL '))]
expected = {'a': ['a_setup', 'a_positive_control', 'a_setup', 'a_all_items_gone', 'a_no_dangling'],
            'b': ['b_setup', 'b_transfer', 'b_property_cleared', 'b_stolen_item_dropped']}
if ([s.split()[1] for s in assertions] != expected[sys.argv[2]]
        or lines.count('COMPLETE') != 1):
    sys.exit('FAIL missing or unexpected assertion lines/completion')
sys.exit(0 if assertions and all(s.startswith('PASS ') for s in assertions) else 1)
PY
done
echo "Specimen directory: $base"
exit "$failed"
