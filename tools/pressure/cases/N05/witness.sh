#!/bin/bash
# witness for N05: ATTR_LAST grew to at least 43, and the entry B put at the old end keeps 41 (no entry moves only
# because it equals the old ATTR_LAST). $1 = the worktree.
# fact: attribute numbers -- inc/Defines.h of the landed tree; no game run, no seed
set -uo pipefail
D="$1/inc/Defines.h"
val() { sed -n "s/^#define $1[[:space:]][[:space:]]*\([0-9][0-9]*\)\([[:space:]].*\)\{0,1\}\$/\1/p" "$D" | head -1; }
last="$(val ATTR_LAST)"; end="$(val A_AC8_END)"
echo "ATTR_LAST=${last:-?} A_AC8_END=${end:-absent}"
[ -n "$last" ] && [ "$last" -ge 43 ] || { echo "FAIL: ATTR_LAST is below 43"; exit 1; }
[ -z "$end" ] || [ "$end" = 41 ] || { echo "FAIL: the entry at the old end moved from 41 to $end"; exit 1; }
echo "witness: ATTR_LAST $last, A_AC8_END ${end:-absent}"
