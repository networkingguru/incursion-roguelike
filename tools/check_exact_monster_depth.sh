#!/bin/bash
# gate: live
# Does an "exact monster" encounter produce exactly the requested monster even
# when that monster is deeper than the level? (bd inc-6qmk)
#
# Map::enChooseMID (src/Encounter.cpp) drops every monster whose Depth exceeds
# e.enDepth. With enConstraint holding one monster rID, that monster is the
# only candidate, so a too-deep request empties the list; enGen then clears
# the constraint and builds a random encounter instead. The M_NOGEN test just
# above the depth test already exempts exact requests; the depth test does not.
#
# THE ORACLE is src/ExactMonProbe.cpp under INCURSION_EXACTMON_PROBE, called
# from Game::Play (src/Main.cpp). It calls Map::thEnGenMonXY as the vrock staff
# calls thEnGenMonSummXY, on a level-1 map, and logs to logs/exactmon.log:
#   case=exact    one "exact monster" request for a ghast (Depth 5). Want
#                 new=1 ghasts=1.
#   case=ordinary 60 single-monster encounters constrained by TYPE (MA_UNDEAD),
#                 not by monster. Want made>0 and too_deep=0: enChooseMID's
#                 depth limit MUST stay. (Fully unconstrained encounters are
#                 not used: they reach deeper monsters by other paths even
#                 with the fix, drow and ghast seen on level 1.)
# Exit 1 on any wrong number, or when the probe cannot establish the facts
# (no log, no DONE, INCONCLUSIVE, level depth not 1, ghast not deeper than the
# level, missing case line). It never passes on absence.
#
# Usage: tools/check_exact_monster_depth.sh   (0 pass, 1 fail, 2 could not measure)
. "$(dirname "$0")/check_lib.sh"

CHECK_OPTIONS=tools/fixtures/options-2026-08-22.dat

export INCURSION_EXACTMON_PROBE=1
export INCURSION_LOAD=tools/fixtures/chars/xsummon-priest-seed5-opt0822.sav
check_run tools/keys/exact-monster-depth.keys 1

LOG="$CHECK_RUN/logs/exactmon.log"
fail() { printf '  FAIL  %s\n' "$1"; CHECK_FAIL=1; }
ok()   { CHECK_EXPECTS=$((CHECK_EXPECTS + 1)); printf '  ok    %s\n' "$1"; }

if [ ! -f "$LOG" ]; then
    fail "no probe log at $LOG (is ExactMonProbe still called from Game::Play?)"
    check_done "an exact-monster request makes exactly that monster"
fi
echo "  specimen: $LOG"
sed 's/^/        /' "$LOG"

[ "$(tail -1 "$LOG")" = DONE ] && ok "log ends with DONE" || fail "log does not end with DONE"
if grep -qF INCONCLUSIVE "$LOG"; then
    fail "log carries an INCONCLUSIVE line"
fi

lvl="$(grep '^level ' "$LOG")"
if [ "$lvl" = "level depth=1 ghast_depth=5" ]; then
    ok "level 1, ghast Depth 5 (the request is deeper than the level)"
else
    fail "level line is '$lvl', want 'level depth=1 ghast_depth=5'"
fi

ex="$(grep '^case=exact ' "$LOG")"
if [ -z "$ex" ]; then
    fail "no case=exact line"
elif [ "$ex" = "case=exact new=1 ghasts=1" ]; then
    ok "case 1: exact request for a too-deep ghast made exactly one ghast"
else
    fail "case 1: '$ex', want 'case=exact new=1 ghasts=1' (exact request replaced by a random encounter)"
fi

od="$(grep '^case=ordinary ' "$LOG")"
made="$(sed -n 's/^case=ordinary made=\([0-9]*\) .*/\1/p' <<< "$od")"
deep="$(sed -n 's/^case=ordinary .* too_deep=\([0-9]*\) .*/\1/p' <<< "$od")"
if [ -z "$od" ] || [ -z "$made" ] || [ -z "$deep" ]; then
    fail "no usable case=ordinary line"
elif [ "$made" -le 0 ]; then
    fail "case 2: ordinary encounters made no monsters; nothing was measured"
elif [ "$deep" -ne 0 ]; then
    fail "case 2: $deep ordinary monsters were deeper than level 1 ($od)"
else
    ok "case 2: $made ordinary monsters, none deeper than level 1"
fi

check_done "an exact-monster request makes exactly that monster, and ordinary encounters keep the depth limit"
