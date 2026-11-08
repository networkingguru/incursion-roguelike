#!/bin/bash
# witness for F10 (both sides add a stati value 251): in the landed tree A's status keeps 251 (it is on master, so
# its saved files hold 251); when both exist B holds a different value below LAST_STATI. Read from inc/Defines.h
# with the compiler-free text rule `#define NAME <integer>`. $1 = the worktree.
# fact: stati values -- inc/Defines.h of the landed tree; no game run, no seed
set -uo pipefail
D="$1/inc/Defines.h"
val() { sed -n "s/^#define $1[[:space:]][[:space:]]*\([0-9][0-9]*\)\([[:space:]].*\)\{0,1\}\$/\1/p" "$D" | head -1; }
a="$(val AC8_RACE_A)"; b="$(val AC8_RACE_B)"; last="$(val LAST_STATI)"
echo "AC8_RACE_A=${a:-absent} AC8_RACE_B=${b:-absent} LAST_STATI=${last:-?}"
[ -n "$last" ] || { echo "FAIL: no LAST_STATI"; exit 1; }
[ -n "$a$b" ] || { echo "FAIL: the tree declares neither case status"; exit 1; }
[ -z "$a" ] || [ "$a" = 251 ] || { echo "FAIL: A's status changed from 251 to $a"; exit 1; }
[ -z "$a" ] || [ "$a" -lt "$last" ] || { echo "FAIL: A is not below LAST_STATI"; exit 1; }
[ -z "$b" ] || [ "$b" -lt "$last" ] || { echo "FAIL: B is not below LAST_STATI"; exit 1; }
[ -z "$a" ] || [ -z "$b" ] || [ "$a" != "$b" ] || { echo "FAIL: A and B hold one value, $a"; exit 1; }
echo "witness: statuses hold distinct values below LAST_STATI, A at 251"
