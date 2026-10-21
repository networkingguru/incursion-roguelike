#!/bin/bash
# gate: live
# inc-8rrt: can the real random-potion generator produce a potion of Stone to
# Flesh, and does a new game assign every potion a flavour?
#
#   tools/check_stone_to_flesh_loot.sh    exit 0 if both hold, 1 otherwise
#
# BUILD FIRST: BACKEND=posix ./build_macos.sh. One fresh NEW game (no
# INCURSION_LOAD) makes flavours, then src/StoneToFleshLootProbe.cpp draws
# Item::GenItem -- the level generator's own call -- 5000 times under
# INCURSION_STONE_FLESH_LOOT_PROBE and logs STONE_FLESH_LOOT. PASS needs the
# summary line, hits >= 1, and no "Insufficient flavours" in errors.log. A
# missing line is FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -x ./incursion-headless ] || { echo "FAIL: build with BACKEND=posix ./build_macos.sh"; exit 1; }
mkdir -p logs/runs
run=$(mktemp -d "$PWD/logs/runs/stone-to-flesh-loot.XXXXXX")
echo "Specimens: $run"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_RUN_DIR="$run"
export INCURSION_STONE_FLESH_LOOT_PROBE=1
unset INCURSION_LOAD
if ! tools/headless.sh tools/keys/stone-to-flesh-loot.keys 1 >"$run/harness.txt" 2>&1; then
    cat "$run/harness.txt"
    echo 'FAIL: harness could not measure'
    exit 1
fi
python3 -I - "$run" <<'PY'
import pathlib, re, sys
logs = list(pathlib.Path(sys.argv[1]).rglob('errors.log'))
if len(logs) != 1:
    sys.exit('FAIL: missing or ambiguous errors.log')
text = logs[0].read_text(errors='replace')
for line in text.splitlines():
    if 'STONE_FLESH_LOOT' in line:
        print(line.split('  ', 1)[-1])
if 'Insufficient flavours' in text:
    sys.exit('FAIL: a new game ran the flavour pool dry')
m = re.findall(r'STONE_FLESH_LOOT draws=(\d+) first_hit=(\d+) hits=(\d+) kinds=(\d+) level=(\d+)', text)
if len(m) != 1:
    sys.exit('FAIL: STONE_FLESH_LOOT summary missing or duplicated')
draws, first_hit, hits, kinds, level = map(int, m[0])
if 'INCONCLUSIVE' in text:
    sys.exit('FAIL: probe could not measure')
if hits < 1:
    sys.exit('FAIL: hits=%d, Stone to Flesh never generated' % hits)
print('PASS: Stone to Flesh loot: draws=%d first_hit=%d hits=%d kinds=%d level=%d'
      % (draws, first_hit, hits, kinds, level))
PY
