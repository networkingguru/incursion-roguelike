#!/bin/bash
# inc-bw1xe: replay the existing store check against a supplied binary.
# Diagnostic capture only, not a new acceptance check or seed-independence claim.
# fact: character, initial world -- original INCURSION_LOAD fixture below
# fact: settings -- original INCURSION_OPTIONS chosen by check_store_find.sh
# fact: keys and screen predicates -- unchanged check_store_find.sh/store-find.keys
# fact: random stream -- original seed 1; NOT a control for generated stock
# fact: stock names/qualities/order -- UNCONTROLLED in the original check;
#   this reproduces that hole, rather than asserting new seed-dependent facts.
# fact: module -- this worktree's built mod/Incursion.Mod, shared across binaries
# fact: probes -- no extra probe or forced-roll env vars; clean environment
#
# Build archives using BACKEND=posix ./build_macos.sh, then pass each binary:
#   bash tools/repro_store_find_inc_bw1xe.sh /tmp/inc-bw1xe-a/incursion-headless
#   bash tools/repro_store_find_inc_bw1xe.sh /tmp/inc-bw1xe-b/incursion-headless-landing
#   bash tools/repro_store_find_inc_bw1xe.sh /tmp/inc-bw1xe-b/incursion-headless
# The last binary is the landing rebuilt with ONLY parent src/Item.cpp:
#   git show cd55ecd8^1:src/Item.cpp > /tmp/inc-bw1xe-b/src/Item.cpp
# See logs/inc-bw1xe/findings.txt for the archive/build recipe and evidence.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BIN="${1:?pass an absolute path to the comparison binary}"
mkdir -p "$ROOT/logs/inc-bw1xe"
RUN="$(mktemp -d "$ROOT/logs/inc-bw1xe/replay.XXXXXX")"
env -i PATH="$PATH" HOME="$HOME" \
    INCURSION_BIN="$BIN" INCURSION_RUN_DIR="$RUN/run" \
    bash tools/check_store_find.sh > "$RUN/check.log" 2>&1
result=$?
cat "$RUN/check.log"
printf 'exit=%s\n' "$result" | tee "$RUN/exit.txt"
printf 'capture: %s\n' "$RUN"
exit "$result"
