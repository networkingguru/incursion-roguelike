#!/bin/bash
# List every line a diff REMOVES and does not put back somewhere else.
#
# Why this exists: a reviewer's weakest sense is for what is no longer there.
# An added line draws the eye. A deleted guard does not, every check stays
# green without it, and an agent's own report will not mention it. On
# 2026-08-25 a Codex round silently removed the AutoBuffs terminator invariant
# from inc/Creature.h -- a bounds guard against three unbounded walks -- and
# every check still passed. This makes that class of change impossible to miss
# by omission.
#
# This is a review aid, not a gate. It always exits 0 unless it is misused.
# Judging the deletions is the reviewer's job; surfacing them is this script's.
#
# Usage:
#   tools/review_deletions.sh                 working tree against HEAD
#   tools/review_deletions.sh <rev>           working tree against <rev>
#   tools/review_deletions.sh <rev1> <rev2>   <rev1> against <rev2>
#
# A line is reported when its content, with leading and trailing whitespace
# stripped, appears as a '-' line and never as a '+' line anywhere in the same
# diff. That ignores lines that only moved or were re-indented, which are noise,
# and keeps lines that genuinely left the tree, which are the point.

set -euo pipefail

cd "$(dirname "$0")/.."

case $# in
    0) DIFF_ARGS=(HEAD) ;;
    1) DIFF_ARGS=("$1") ;;
    2) DIFF_ARGS=("$1" "$2") ;;
    *) echo "usage: $0 [rev [rev]]" >&2; exit 2 ;;
esac

git diff -U0 "${DIFF_ARGS[@]}" | python3 -c '
import sys

added = set()
removed = []          # (file, text) in diff order
path = "?"

for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("+++ b/"):
        path = line[6:]
        continue
    if line.startswith("--- ") or line.startswith("+++ "):
        continue
    if line.startswith("@@") or line.startswith("diff --git"):
        continue
    if line.startswith("+"):
        added.add(line[1:].strip())
    elif line.startswith("-"):
        removed.append((path, line[1:].strip()))

gone = [(f, t) for f, t in removed if t not in added]

# A blank line carries no information on its own; count them, do not list them.
blanks = sum(1 for _, t in gone if not t)
gone = [(f, t) for f, t in gone if t]

if not gone:
    print("No line left the tree unmatched.", end="")
    print(f" ({blanks} blank lines removed.)" if blanks else "")
    sys.exit(0)

current = None
for f, t in gone:
    if f != current:
        print(f"\n{f}")
        current = f
    print(f"  - {t}")

print(f"\n{len(gone)} line(s) removed and not added back anywhere.", end="")
print(f" {blanks} blank line(s) also removed." if blanks else "")
print("Account for each one before approving the change.")
'
