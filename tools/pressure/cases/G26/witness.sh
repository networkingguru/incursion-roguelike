#!/bin/bash
# witness for G26 (both sides add a row to Mara's SACRIFICE_LIST and raise MAX_SAC_CATS): a sacrifice category is a row
# position in one god's SACRIFICE_LIST (src/Prayer.cpp reads row i/2). PASS only when Mara's list in the landed tree holds
# the row of each side that has landed (A: MA_CHOICE1 6, B: MA_CHOICE1 7) at distinct positions, every row position is
# below MAX_SAC_CATS, and the row count is master's 9 plus one per landed side. A side has landed in a tree when the history
# holds its case-patch commit ("tools: inc-g26a|b case patch"). The merged tree holds both. Stored totals only; no sacrifice
# is scored in play.
# $1 = the worktree.
# fact: Mara's SACRIFICE_LIST rows -- lib/religion.irh of the landed tree; no game run, no seed
# fact: MAX_SAC_CATS -- inc/Defines.h of the landed tree; no game run, no seed
# fact: which sides have landed -- the commit subjects in the worktree's history, written by tools/pressure/route.sh
# fact: master's row count, 9 -- the case's own constant, the list on master before A and B
set -uo pipefail
R="$1/lib/religion.irh"; D="$1/inc/Defines.h"
MASTER_ROWS=9
m="$(sed -n 's/^#define MAX_SAC_CATS[[:space:]][[:space:]]*\([0-9][0-9]*\)\([[:space:]].*\)\{0,1\}$/\1/p' "$D" 2>/dev/null | head -1)"
[ -n "$m" ] || { echo "FAIL: no MAX_SAC_CATS in $D"; exit 1; }
# the rows of Mara's list: from `* SACRIFICE_LIST` to the next `* ` field, inside `God "Mara"`, one row a line
rows="$(awk '
  /^God "/ { ing = ($0 ~ /^God "Mara"/); inl = 0; next }
  ing && /^[[:space:]]*\*[[:space:]]+SACRIFICE_LIST/ { inl = 1; found = 1; next }
  ing && inl && /^[[:space:]]*\*[[:space:]]/ { inl = 0 }
  ing && inl { l = $0; sub(/,[[:space:]]*$/, "", l); gsub(/[[:space:]]+/, " ", l); sub(/^ /, "", l); sub(/ $/, "", l); if (l != "") print l }
' "$R" 2>/dev/null)"
[ -n "$rows" ] || { echo "FAIL: cannot find Mara's SACRIFICE_LIST in $R"; exit 1; }
n="$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
pa="$(printf '%s\n' "$rows" | grep -n -x 'MA_CHOICE1 6' | cut -d: -f1 | head -1)"
pb="$(printf '%s\n' "$rows" | grep -n -x 'MA_CHOICE1 7' | cut -d: -f1 | head -1)"
echo "rows=$n A@${pa:-absent} B@${pb:-absent} MAX_SAC_CATS=$m"
subj="$(git -C "$1" log --format=%s 2>/dev/null)"
wa=0; wb=0
printf '%s\n' "$subj" | grep -q '^tools: inc-g26a case patch' && wa=1
printf '%s\n' "$subj" | grep -q '^tools: inc-g26b case patch' && wb=1
[ $((wa + wb)) -gt 0 ] || { echo "FAIL: neither side's case-patch commit is in the history, cannot tell what must be here"; exit 1; }
if [ $wa -eq 1 ]; then [ -n "$pa" ] || { echo "FAIL: A landed and A's row (MA_CHOICE1 6) is not in Mara's list"; exit 1; }; fi
if [ $wb -eq 1 ]; then [ -n "$pb" ] || { echo "FAIL: B landed and B's row (MA_CHOICE1 7) is not in Mara's list"; exit 1; }; fi
[ -z "$pa" ] || [ -z "$pb" ] || [ "$pa" != "$pb" ] || { echo "FAIL: A and B share one row position"; exit 1; }
[ "$n" -le "$m" ] || { echo "FAIL: $n rows do not fit MAX_SAC_CATS $m"; exit 1; }
[ "$n" -eq $((MASTER_ROWS + wa + wb)) ] || { echo "FAIL: $n rows, expected $((MASTER_ROWS + wa + wb)) (master's $MASTER_ROWS plus one per landed side)"; exit 1; }
echo "witness: Mara's list holds $n rows, A@${pa:-none} B@${pb:-none}, all below MAX_SAC_CATS $m"
