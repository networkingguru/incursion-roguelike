#!/bin/bash
# inc-9m0e: capture evidence, not a pass/fail check of blindness semantics.
# Usage: bash tools/repro_blind_map_view.sh
# Requires: BACKEND=posix ./build_macos.sh
# All generated modules, saves, logs and screen dumps remain under logs/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASE="$ROOT/logs/runs/blind-map-view-$(date +%s)-$$"
mkdir -p "$BASE/module/mod" "$BASE/module/logs" "$BASE/run/mod" "$BASE/run/lib"
cp -Rf "$ROOT/lib" "$BASE/module/lib"
ln -s "$ROOT/inc" "$BASE/module/inc"
cat tools/fixtures/conditions-attack-gods.irh >> "$BASE/module/lib/main.irc"
echo "specimens: $BASE"
INCURSIONPATH="$BASE/module/" ./incursion-headless -compile main.irc \
    < /dev/null > "$BASE/module/compile.log" 2>&1
cp -f "$BASE/module/mod/Incursion.Mod" "$BASE/run/mod/Incursion.Mod"
INCURSION_RUN_DIR="$BASE/run" \
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/orc-barbarian-seed1-opt0822.char \
    tools/headless.sh tools/keys/blind-map-view.keys 1 > "$BASE/run/session.txt" 2>&1
cat "$BASE/run/session.txt"
