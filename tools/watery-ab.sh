#!/bin/bash
# Reproducer for inc-q3r5: Watery Double kills its own caster.
#
# READ THIS BEFORE TRUSTING THE A/B. This script was written as an A/B of
# inc-fiiq's __StatiRemoval change, and that framing was WRONG. The crash is
# NOT caused by that change. A clean HEAD (c7e5d2f) worktree build crashes
# identically -- same four asserts, same order, same frames. The "unfixed"
# binary this script compares against, ./incursion-nocleanupevent, was never
# built from HEAD: its symbol table still exports RedundantFieldGrant and the
# four-argument RemoveEffStati, so it is the working tree with one hunk
# reverted, not the state before the change. Its disagreement with the fixed
# build proves nothing about inc-fiiq.
#
# What the fixture DOES demonstrate, on any build including HEAD:
# tools/keys/watery-death.keys makes the player cast Watery Double at a giant
# tortoise standing in shallow water and then kills the tortoise. The cast
# leaves the caster holding EFF_FLAG1 whose stati object is the tortoise
# (lib/wspells.irh:7648). Killing the tortoise sends that row through
# Thing::CleanupRefedStati to the spell's EV_REMOVED handler
# (lib/wspells.irh:7664). PEVENT (inc/Events.h:65) binds both EActor and
# EVictim to the row's HOLDER, not to the stati object, so the handler's
# cancellation branch calls EVictim->Remove(true) on the caster -- the player.
# Result: SIGSEGV, four InBounds asserts from TextTerm::ShowStatus.
#
# The control, tools/keys/watery-nocast.keys, is the identical run with the
# cast removed and exits 0, so the crash needs the cast.
#
# The handler bug is upstream's. See bead inc-q3r5 for the fix directions.
#
# Usage: tools/watery-ab.sh   (0 the two builds disagree as described,
#                              1 they do not, 2 inconclusive)
#
# The exit code is retained only so the fixture still runs. Do not read it as
# evidence about inc-fiiq.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

FIXED="${INCURSION_BIN:-./incursion-headless}"
RED="${INCURSION_RED_BIN:-./incursion-nocleanupevent}"
KEYS=tools/keys/watery-death.keys
SEED=20260905

for b in "$FIXED" "$RED"; do
    [ -x "$b" ] || { echo "INCONCLUSIVE: $b is not built."; exit 2; }
done

run_one() { # $1 binary -> prints "<exit> <rundir>"
    local out status
    out="$(INCURSION_BIN="$1" INCURSION_OPTIONS=tools/gates/Options.Dat \
        tools/headless.sh "$KEYS" "$SEED" 2>&1)"
    status=$?
    printf '%s %s\n' "$status" "$(printf '%s\n' "$out" | awk '/^run:/ {print $2}')"
}

read -r fstatus frun <<<"$(run_one "$FIXED")"
read -r rstatus rrun <<<"$(run_one "$RED")"

# The unfixed run must get far enough to prove anything: the cast has to have
# happened, or the two runs differ for a reason that has nothing to do with the
# change under test.
cast=0
grep -qs "aqueous giant tortoise" "$rrun"/logs/screens/*-after-cast.txt && cast=1

alive=0
grep -qs "aqueous giant tortoise" "$rrun"/logs/screens/*-after-kill.txt || alive=1

echo "fixed:   exit $fstatus  ($frun)"
echo "unfixed: exit $rstatus  ($rrun)"
echo "cast reached on the unfixed run: $cast"

fail=0
[ "$cast" -eq 1 ] || { echo "INCONCLUSIVE: the spell never took; the fixture proves nothing."; exit 2; }
if [ "$fstatus" -eq 0 ]; then
    echo "NO DIFFERENCE: the fixed build survived the fixture."
    fail=1
fi
if [ "$rstatus" -ne 0 ]; then
    echo "NO DIFFERENCE: the unfixed build did not survive either (exit $rstatus)."
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "REPRODUCED: the fixed build dies where the unfixed build walks away."
