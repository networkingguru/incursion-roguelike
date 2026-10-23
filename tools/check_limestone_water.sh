#!/bin/bash
# gate: live
# inc-nhgh: fresh maps, since saved characters also pin their dungeon.
# inc-s1qj: natural seeds may roll only wet panels, so one extra run sets
# INCURSION_BLOB_MIN_PROBE=dry (natural water removed before the top-up) and always measures before=0.
# Override LIMESTONE_SEEDS to widen the deterministic dive sample.
#
# This check tests level generation, so it cannot fix the world: it asserts an
# invariant that must hold on every seed (a Limestone Cave panel never ends below
# its minimum water count), and it exits 2 when no panel needed the top-up.
# fact: the rolled character survives the dive -- wizard Cheat Death on (tools/keys/limestone-water.keys)
# fact: nothing attacks him on the way -- wizard Freeze Monsters on
# fact: the levels -- NOT fixed, they are what is measured (an invariant, not a pinned map)
# fact: the character -- NOT loaded: a saved character pins the dungeon (inc-nhgh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RUN_ROOT="$(mktemp -d "$ROOT/logs/limestone-water-XXXXXX")"
echo "specimens: $RUN_ROOT"
run_failed=0
for seed in ${LIMESTONE_SEEDS:-7 1 2 52}; do
    run="$RUN_ROOT/seed-$seed"
    rc=0
    INCURSION_BLOB_MIN_PROBE=1 INCURSION_RUN_DIR="$run" \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        tools/headless.sh tools/keys/limestone-water.keys "$seed" > "$RUN_ROOT/seed-$seed.log" 2>&1 || rc=$?
    # Exit 7 is an assertion report: retain it for diagnosis, but still
    # evaluate the independent before/after terrain oracle.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 7 ]; then
        echo "UNMEASURED: seed $seed harness exit $rc"
        run_failed=1
    fi
done
run="$RUN_ROOT/seed-dry"
rc=0
INCURSION_BLOB_MIN_PROBE=dry INCURSION_RUN_DIR="$run" \
    INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
    tools/headless.sh tools/keys/limestone-water.keys "${LIMESTONE_DRY_SEED:-7}" > "$RUN_ROOT/seed-dry.log" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 7 ]; then
    echo "UNMEASURED: dry run harness exit $rc"
    run_failed=1
fi
python3 - "$RUN_ROOT" "$run_failed" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
rows = []
for path in sorted(root.glob('seed-*/logs/blob-min.log')):
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'BLOB_MIN region="Limestone Cave" before=(\d+) count=(\d+) min=(\d+)', line)
        if match:
            before, count, minimum = map(int, match.groups())
            rows.append((before, count, minimum))
            if count < minimum:
                print(f'RED: {path}: {line}')
if not rows:
    print('UNMEASURED: no Limestone Cave panels observed')
    sys.exit(2)
failed = any(count < minimum for before, count, minimum in rows)
exercised = sum(before < minimum for before, count, minimum in rows)
topped = sum(before < minimum <= count for before, count, minimum in rows)
print(f'{"RED" if failed else "UNMEASURED" if int(sys.argv[2]) or not exercised else "GREEN"}: {len(rows)} Limestone Cave panels; '
      f'minimum count observed={min(count for _, count, _ in rows)}; before<min panels={exercised}; topped up={topped}')
if failed:
    sys.exit(1)
if not exercised:
    print("UNMEASURED: no panel needed the minimum top-up")
    sys.exit(2)
if int(sys.argv[2]):
    print('UNMEASURED: incomplete harness run')
    sys.exit(2)
PY
