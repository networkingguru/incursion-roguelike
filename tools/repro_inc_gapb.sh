#!/bin/bash
# inc-gapb phase 2: observe the scarab swarm through existing wizard commands.
# Usage: bash tools/repro_inc_gapb.sh [seed] (observed seed: 1)
# Requires the existing headless build and compiled module; changes no game data.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
RUN="$(mktemp -d "$ROOT/logs/inc-gapb-XXXXXXXX")"
export INCURSION_RUN_DIR="$RUN"
export INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat
export INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.sav
export INCURSION_CHAR_PROBE=1
# Freeze Monsters stops movement but does not suppress proximity attacks.
# Evidence: messages-top (3d6 and zero weapon damage), player-stati (named
# filth fever and NAUSEA), weapon-02/03 (42 -> 39 HP), inventory (equipped knife).
bash tools/headless.sh tools/keys/inc-gapb-scarab.keys "${1:-1}" 2>&1 | tee "$RUN/report.txt"
