#!/bin/bash
# gate: live
# inc-4trf: the cheetah's description must show only real feat names, not the
# FeatName() debug fallback "---N (below M = <name>)---".
#
# Monster::Describe (src/Help.cpp:3661) lists each `Feats:` entry through
# FeatName(). A feat id with no FeatInfo[] row makes FeatName return
# "---103 (below 102 = Dance of Tukima)---", which lands in the description
# where a feat's name belongs. Before the fix the cheetah carried FT_DASH.
#
# Facts and their controls (this check reads only what the header names):
#   # fact: character and its druid level -- fixture druid-shoulder-metal-seed7-opt0822.sav
#   # fact: the Wild Shape menu's entries -- lib/ monster data, fixed by the module
#   # fact: the description text -- the cheetah's Feats: list in lib/mon1.irh
# A loaded fixture fixes the character, so no seed decides a fact the check reads.
#
# Usage: tools/check_wildshape_cheetah_desc.sh
# Specimens: logs/wildshape-cheetah-desc/run-<timestamp>-<pid>/ and its .out file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
mkdir -p logs/wildshape-cheetah-desc
run="logs/wildshape-cheetah-desc/run-$(date +%Y%m%d-%H%M%S)-$$"
INCURSION_OPTIONS=tools/fixtures/options-2026-08-22.dat \
INCURSION_LOAD=tools/fixtures/chars/druid-shoulder-metal-seed7-opt0822.sav \
INCURSION_RUN_DIR="$run" tools/headless.sh tools/keys/wildshape-cheetah-desc.keys 1 > "$run.out" 2>&1
status=$?
echo "headless exit: $status; specimens: $run (report: $run.out)"

screens="$run/logs/screens"
[ -d "$screens" ] || { echo "FAIL: no screen dumps at $screens"; exit 1; }

desc="$(ls "$screens"/*-cheetah-desc.txt 2>/dev/null | head -1)"
[ -n "$desc" ] || { echo "FAIL: the cheetah description was never dumped"; exit 1; }

# Guard first: if the menu never named the cheetah, the run is inconclusive.
if ! grep -q "Cheetah" "$desc"; then
  echo "INCONCLUSIVE: the Wild Shape menu did not reach the cheetah."
  echo "  Screens: $screens"
  exit 1
fi

# The assertion that bites.
if grep -q -- "---" "$desc"; then
  echo "FAIL: the cheetah description carries a FeatName() debug fallback:"
  grep -n -- "---" "$desc"
  echo "  A Feats: entry on the cheetah has no src/FeatTab.cpp row (inc-4trf)."
  echo "  Screens: $screens"
  exit 1
fi

echo "PASS: the cheetah description names only real feats (inc-4trf)."
