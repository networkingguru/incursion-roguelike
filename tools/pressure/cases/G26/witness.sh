#!/bin/bash
# witness for G26 (both sides add a sacrifice category and raise MAX_SAC_CATS): when the tree declares both category
# constants they hold different values below MAX_SAC_CATS, and MAX_SAC_CATS covers both. No family marks the category
# constants, so no tool can see two categories sharing an index; this reads the landed tree's inc/Defines.h.
# $1 = the worktree.
# fact: category constants and MAX_SAC_CATS -- inc/Defines.h of the landed tree; no game run, no seed
set -uo pipefail
D="$1/inc/Defines.h"
val() { sed -n "s/^#define $1[[:space:]][[:space:]]*\([0-9][0-9]*\)\([[:space:]].*\)\{0,1\}\$/\1/p" "$D" | head -1; }
a="$(val GRW_SAC_A)"; b="$(val GRW_SAC_B)"; m="$(val MAX_SAC_CATS)"
echo "GRW_SAC_A=${a:-absent} GRW_SAC_B=${b:-absent} MAX_SAC_CATS=${m:-?}"
[ -n "$m" ] || { echo "FAIL: no MAX_SAC_CATS"; exit 1; }
[ -n "$a$b" ] || { echo "FAIL: the tree declares neither category"; exit 1; }
[ -z "$a" ] || [ "$a" -lt "$m" ] || { echo "FAIL: A's category is outside MAX_SAC_CATS"; exit 1; }
[ -z "$b" ] || [ "$b" -lt "$m" ] || { echo "FAIL: B's category is outside MAX_SAC_CATS"; exit 1; }
[ -z "$a" ] || [ -z "$b" ] || [ "$a" != "$b" ] || { echo "FAIL: A and B hold one category index, $a"; exit 1; }
echo "witness: the categories hold distinct indexes below MAX_SAC_CATS"
