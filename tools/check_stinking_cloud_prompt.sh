#!/bin/bash
# gate: live
# inc-uprr: does a breather with a high Fortitude bonus still get asked
# "Confirm enter the stinking cloud?"
# Needs the posix build: BACKEND=posix ./build_macos.sh
#
# THE DEFECT. lib/dungeon.irh, terrain "stinking cloud;terrain", EV_MON_CONSIDER
# tests `!EActor->GetAttr(A_SAV_FORT) < 15`. The `!` binds first, so the test is
# always true and the warning prompt (src/Move.cpp, only on a step from other
# terrain into the cloud) appears for every material-plane breather.
# THE RULE. Fortitude bonus < WARN_SAVE_DC (15) -> prompt. >= 15 -> no prompt.
#
# TWO SESSIONS, same character, same keys (tools/keys/stinking-cloud-prompt.keys):
#   LOW   INCURSION_FORT_PROBE=14 adds +14 to the player's Fortitude bonus
#         (src/Values.cpp, a getenv-guarded test hook), so the sheet reads +14
#         (WARN_SAVE_DC-1). Prompt expected.
#   HIGH  INCURSION_FORT_PROBE=15 adds +15, so the sheet reads +15
#         (WARN_SAVE_DC). Prompt must NOT appear.
# The exact values pin the boundary. If the fixture's base Fortitude moves,
# the sheet no longer reads 14 and 15, and the check FAILS.
# Each session reads its Fortitude bonus off the character sheet the game draws
# (the "Fortitude  +N" line) and the prompt off the screen photographed at the
# step into the cloud. A session counts only when the sheet and the step were
# both read AND the character stood in the cloud: logs/chance_probe.log
# (INCURSION_CHANCE_PROBE) holds a Fortitude save, rolled when he leaves a cloud
# square. No such save means he never entered: that is a failure, not a pass.
#
# Exit 0 pass, 1 fail ("measured nothing" counts as fail).
#
# fact: character (elf mage, Fortitude +0) -- fixture elf-mage-illusions-seed1, INCURSION_LOAD
# fact: wizard mode, Freeze Monsters on -- saved in the fixture
# fact: the map and its monsters -- the fixture's save pins the dungeon
# fact: three stinking cloud squares east of him -- wizard Change terrain type (tools/keys/stinking-cloud-prompt.keys)
# fact: the Fortitude bonus of each case -- read from the character sheet screen, never assumed
# fact: LOW Fortitude bonus -- INCURSION_FORT_PROBE=14 (src/Values.cpp), sheet reads WARN_SAVE_DC-1
# fact: HIGH Fortitude bonus -- INCURSION_FORT_PROBE=15 (src/Values.cpp), sheet reads WARN_SAVE_DC
# fact: the prompt -- read from the screen photographed at the step in, before any answer
# fact: he stood in the cloud -- a Fortitude save line in chance_probe.log
# fact: each save's die -- never read
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -x ./incursion-headless ] || { echo 'FAIL: measured nothing; build with BACKEND=posix ./build_macos.sh'; exit 1; }
OPTS=tools/fixtures/options-2026-08-22.dat
FIX=tools/fixtures/chars/elf-mage-illusions-seed1
SEED=1
WARN_SAVE_DC=15
status=0

# run_case <name> <probe value or empty> -> sets FORT PROMPT SAVES; returns 1 when nothing was measured
run_case() {
    local out run envp=()
    [ -n "$2" ] && envp=(INCURSION_FORT_PROBE="$2")
    out="$(env ${envp[@]+"${envp[@]}"} INCURSION_CHANCE_PROBE=1 INCURSION_LOAD="$FIX.sav" INCURSION_OPTIONS="$OPTS" \
           INCURSION_RUN_DIR="logs/stinking-cloud-prompt.$$-$1" \
           tools/headless.sh tools/keys/stinking-cloud-prompt.keys "$SEED" 2>&1 < /dev/null)"
    run="$(echo "$out" | awk '/^run:/ {print $2}')"
    if [ -z "$run" ] || grep -q 'NO GAMEPLAY\|gave up after\|looked for something' <<< "$out"; then
        echo "FAIL: $1 measured nothing (script did not complete)"
        return 1
    fi
    local sheet entry
    sheet="$(ls "$run"/logs/screens/*-sheet.txt 2>/dev/null | head -1)"
    entry="$(ls "$run"/logs/screens/*-entry.txt 2>/dev/null | head -1)"
    if [ -z "$sheet" ] || [ -z "$entry" ]; then
        echo "FAIL: $1 measured nothing (sheet or entry screen missing in $run)"
        return 1
    fi
    FORT="$(sed -n 's/^ *Fortitude *\([-+][0-9]*\).*/\1/p' "$sheet" | head -1)"
    if [ -z "$FORT" ]; then
        echo "FAIL: $1 measured nothing (no Fortitude line on the sheet, $sheet)"
        return 1
    fi
    FORT=$((FORT))
    if grep -q 'Confirm enter the' "$entry"; then PROMPT=yes; else PROMPT=no; fi
    SAVES="$([ -f "$run/logs/chance_probe.log" ] && awk '$1=="save" && $2==0' "$run/logs/chance_probe.log" | wc -l | tr -d ' ')"
    if [ "${SAVES:-0}" -lt 1 ]; then
        echo "FAIL: $1 measured nothing (no Fortitude save: he never stood in the cloud, $run)"
        return 1
    fi
    RUN="$run"
}

run_case low 14 || exit 1
lowF=$FORT; lowP=$PROMPT
echo "LOW:  Fortitude bonus $lowF, prompt $lowP, $SAVES cloud saves ($RUN)"
run_case high 15 || exit 1
highF=$FORT; highP=$PROMPT
echo "HIGH: Fortitude bonus $highF, prompt $highP, $SAVES cloud saves ($RUN)"

if [ "$lowF" -eq $((WARN_SAVE_DC-1)) ] && [ "$lowP" = yes ]; then
    echo "LOW ok: bonus $lowF == $((WARN_SAVE_DC-1)), prompt shown"
else
    echo "FAIL: LOW: bonus $lowF must be $((WARN_SAVE_DC-1)) and prompt yes (got $lowP); fixture base Fortitude may have moved"; status=1
fi
if [ "$highF" -eq "$WARN_SAVE_DC" ] && [ "$highP" = no ]; then
    echo "HIGH ok: bonus $highF == $WARN_SAVE_DC, no prompt"
else
    echo "FAIL: HIGH: bonus $highF must be $WARN_SAVE_DC and prompt no (got $highP); fixture base Fortitude may have moved"; status=1
fi
[ "$status" = 0 ] && echo "PASS: the cloud prompt follows the Fortitude bonus" || echo "FAIL"
exit "$status"
