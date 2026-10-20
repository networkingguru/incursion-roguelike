#!/bin/bash
# gate: live
# Does a pool of grease behave like the SRD Grease spell? Bead inc-ckw0.
#
# THE DEFECT. The "pool of grease" terrain (lib/dungeon.irh) rolled Balance
# against max(15, the square's TerraDC) on every move, attack, jump-off and
# landing, and any failure knocked the creature down. The SRD Grease spell
# asks a DC 10 Balance check only to walk within or through the grease, at
# half speed. A failure stops the creature that round and calls for a Reflex
# save against the spell's DC or a fall; failing by 5 or more falls with no
# save. Standing still and attacking need no check.
#
# THE ORACLE is the game's own message history ('v'), read after one action in
# each scenario, plus the turn counter in each screen header. The d20 of every
# skill check is pinned with INCURSION_RUNTO_SKILL_ROLL and the Reflex save
# with INCURSION_FORCE_SAVE_ROLL, so each outcome is forced, not hoped for.
# A frozen kobold in sight makes the character "threatened"; an unthreatened
# creature takes 20 on Balance and the die never matters.
# Balance modifier of the seed-4 paladin is -1, so roll R gives total R-1.
#
# CASES (a run each; the key scripts are tools/keys/grease-srd-*.keys):
#   M1  roll 20  leave grease: check is DC 10, passes; the step costs twice the
#                step that entered it (half speed)
#   M2  roll 11  total 10 passes DC 10 (it failed DC 15): no slip
#   M3  roll 10, save 20  fail by 1: Reflex save rolled and passed; the
#                creature stays in the grease on its feet
#   M4  roll 10, save 1   fail by 1: Reflex failed; knocked from its feet
#   M5  roll 5, save 20   fail by 6: knocked down and NO Reflex save rolled
#   A1  roll 1   attack from inside grease: no Balance check, the kobold dies
#   S1  roll 1   stand still in grease: no Balance check
#   I1  roll 1   CONTROL, attack from an Ice Floor square: DC 10 Balance
#                check and a slip, before and after the grease fix
#
# Usage: tools/check_grease_srd.sh   (0 pass, 1 fail, 2 inconclusive)
# Needs ./incursion-headless (BACKEND=posix ./build_macos.sh).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -x ./incursion-headless ] || {
    echo "INCONCLUSIVE: ./incursion-headless not built. Run: BACKEND=posix ./build_macos.sh"
    exit 2
}

OPTS=tools/fixtures/options-2026-08-22.dat
rc=0
STAMP="$$-$RANDOM"
RUNS=()

fail() { echo "FAIL [$CASE]: $*"; rc=1; }

# run_case <keys> <roll> [save]  -> sets $S (screens dir) or exits 2
run_case() {
    local keys="$1" roll="$2" save="${3:-}" dir
    dir="logs/runs/grease-srd-$STAMP-$CASE"
    RUNS+=("$dir")
    env INCURSION_RUNTO_SKILL_ROLL="$roll" ${save:+INCURSION_FORCE_SAVE_ROLL=$save} \
        INCURSION_OPTIONS="$OPTS" INCURSION_RUN_DIR="$dir" \
        tools/headless.sh "tools/keys/$keys" 4 >"$dir.out" 2>&1
    S="$dir/logs/screens"
    ls "$S"/*-history.txt >/dev/null 2>&1 || {
        echo "INCONCLUSIVE [$CASE]: no message history dumped. Output: $dir.out"; exit 2; }
    H="$(ls "$S"/*-history.txt)"
    grep -q "Messages" "$H" || {
        echo "INCONCLUSIVE [$CASE]: the history screen is not the message list ($H)"; exit 2; }
}

screen() { ls "$S"/*-"$1".txt; }
turn() { sed -n 's/^=== screen .* turn \([0-9]*\) ===.*/\1/p' "$(screen "$1")"; }
has() { grep -q -- "$1" "$H"; }
count() { grep -c -- "$1" "$H"; }
# the character stands in grease when the location line names it
in_grease() { grep -q "(pool of grease)" "$(screen "$1")"; }

# --- M1: the check is DC 10 and movement in grease is half speed
CASE=M1; run_case grease-srd-move.keys 20
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
t0="$(turn start)"; t1="$(turn in)"; t2="$(turn out)"
enter=$((t1 - t0)); leave=$((t2 - t1))
has "Balance Check:.*vs DC 10 \[success\]" ||
    fail "no Balance check against DC 10 that succeeded when leaving the grease"
has "Balance Check:.*vs DC 15" &&
    fail "a Balance check was rolled against DC 15"
[ "$leave" -ge $((2 * enter - 2)) ] ||
    fail "leaving the grease cost $leave turns, entering cost $enter: not half speed"

# --- M2: total 10 meets DC 10
CASE=M2; run_case grease-srd-move.keys 11
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "Balance Check:.*= 10 vs DC 10 \[success\]" ||
    fail "a total of 10 did not pass DC 10"
has "slip" && fail "the character slipped on a passed check"

# --- M3: fail by 1, Reflex save passes -> stays, on his feet
CASE=M3; run_case grease-srd-move.keys 10 20
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "Balance Check:.*= 9 vs DC 10 \[failure\]" || fail "no failed DC 10 Balance check"
has "Reflex Save:.*\[success\]" || fail "no Reflex save was rolled after the failed check"
has "knocked from your feet" && fail "a creature that passed its Reflex save fell"
in_grease out || fail "the creature left the grease on a failed check"

# --- M4: fail by 1, Reflex save fails -> falls
CASE=M4; run_case grease-srd-move.keys 10 1
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "Reflex Save:.*\[failure\]" || fail "no failed Reflex save"
has "knocked from your feet" || fail "a failed Reflex save did not knock the creature down"
in_grease out || fail "the creature left the grease on a failed check"

# --- M5: fail by 6 -> falls, and no Reflex save
CASE=M5; run_case grease-srd-move.keys 5 20
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "Balance Check:.*= 4 vs DC 10 \[failure\]" || fail "no failed DC 10 Balance check"
has "knocked from your feet" || fail "failing by 5 or more did not knock the creature down"
has "Reflex Save" && fail "a Reflex save was rolled after failing by 5 or more"

# --- A1: attacking from grease rolls no Balance check
CASE=A1; run_case grease-srd-attack.keys 1
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "killing the kobold" || fail "the attack from grease did not land"
has "Balance Check" && fail "attacking from grease rolled a Balance check"

# --- S1: standing still rolls no Balance check
CASE=S1; run_case grease-srd-stand.keys 1
in_grease in || { echo "INCONCLUSIVE [$CASE]: the character never stood in grease"; exit 2; }
has "Balance Check" && fail "standing still in grease rolled a Balance check"

# --- I1: Ice Floor is untouched: DC 10 Balance check on attack, then a slip
CASE=I1; run_case grease-srd-ice.keys 1
has "Balance Check:.*vs DC 10 \[failure\]" ||
    fail "no failed DC 10 Balance check when attacking from Ice Floor"
has "You slip on the ice" || fail "Ice Floor did not make the attacker slip"

if [ "$rc" -eq 0 ]; then
    echo "PASS: grease follows the SRD (DC 10, half speed, Reflex or fall, no check to attack or stand); Ice Floor unchanged"
    # runs leave no value once passed; keep failed ones for inspection
    for d in "${RUNS[@]}"; do rm -rf "$d" "$d.out"; done
else
    echo "Run directories kept: ${RUNS[*]}"
fi
exit "$rc"
