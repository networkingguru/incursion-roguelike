#!/bin/bash
# gate: live
# inc-pd5xn: monster perception, not drawing, triggers rescans at sense range.
# fact: character, player name and dagger -- INCURSION_LOAD=gnome-warrior-wis3-pickaxe-seed1-opt0822 (Point Buy fixture)
# fact: player setup and visibility -- tools/keys/setup-gnome-warrior-wis3-pickaxe-seed1-opt0822.keys; Wizard Mode Switches (Wizard Sight and Ghostwalking)
# fact: corridor, pocket, light and initial position -- INCURSION_RUNTO_STAGE=R, INCURSION_RUNTO_AT=5,5, INCURSION_RUNTO_LEN=30
# fact: no incidental monsters -- wizard Genocide Everything before staging and before the item scene
# fact: watcher identity, position, sense range and hostility -- wizard Monster Summoning: vrock (fixed Wis 16, demon type), INCURSION_SUMMON_NO_GEAR=1
# fact: watcher actions and position after placement -- INCURSION_RESCAN_HOLD=1; player stays outside its threatened area
# fact: floor item position and reveal -- fixture dagger dropped in the pocket before summoning; wizard Change terrain type opens its intervening wall
# fact: new perceptions and rescan targets -- INCURSION_RESCAN_PROBE=1; handles and names read from each run, color bytes stripped
# The hidden/visible walks differ only by Wizard Sight, which consumes no turn.
# The item's negative and positive controls use the SAME dagger at (20,7).
# Exit 0 pass, 1 assertion failure, 2 scene/harness could not be measured.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
[ -x ./incursion-headless ] || { echo 'INCONCLUSIVE: headless binary missing'; exit 2; }
mkdir -p logs/runs
base=$(mktemp -d "$PWD/logs/runs/rescan-check-XXXXXXXX") || exit 2
echo "runs: $base"
for scene in trigger trigger-visible items; do
    env INCURSION_RESCAN_PROBE=1 INCURSION_RESCAN_HOLD=1 \
        INCURSION_RUNTO_PROBE=1 INCURSION_RUNTO_STAGE=R \
        INCURSION_RUNTO_AT=5,5 INCURSION_RUNTO_LEN=30 INCURSION_SUMMON_NO_GEAR=1 \
        INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
        INCURSION_LOAD=gnome-warrior-wis3-pickaxe-seed1-opt0822 \
        INCURSION_RUN_DIR="$base/$scene" \
        tools/headless.sh "tools/keys/rescan-$scene.keys" "${1:-3}" \
        > "$base/$scene.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "INCONCLUSIVE: $scene harness exit $rc; $base/$scene.out"
        exit 2
    fi
done
python3 tools/rescan_trigger_assert.py "$base"
