#!/bin/bash
# inc-67gh: measurement, NOT a gate; random outcomes are reported, never asserted.
# Fixed seeds 1..20, one isolated run per seed, fifteen wait actions (240 ticks, four world turns) per run.
set -uo pipefail
unset INCURSION_FORCE_SAVE_ROLL INCURSION_LOF_FORCE_ROLL INCURSION_FORCE_DAMAGE_ROLL
unset INCURSION_RUNTO_SKILL_ROLL INCURSION_SEED_OVERRIDE
cd "$(dirname "$0")/.." || exit 2
base="logs/swarm-theft/measure-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$base"
for seed in {1..20}; do
    INCURSION_SWARM_THEFT_PROBE=1 INCURSION_CHAR_PROBE=1 \
      INCURSION_LOAD=tools/fixtures/chars/alignment-drain-warrior.sav \
      INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
      INCURSION_RUN_DIR="$base/seed-$seed" \
      tools/headless.sh tools/keys/swarm-theft-measure.keys "$seed" > "$base/seed-$seed.out" 2>&1
    echo "$?" > "$base/seed-$seed.exit"
done
python3 tools/swarm_theft_results.py "$base" --measure
